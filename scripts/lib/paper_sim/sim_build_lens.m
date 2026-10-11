function lens = sim_build_lens(P, C)
%SIM_BUILD_LENS  Construct one paper lens from the simulation-mode parameters.
%
%   lens = sim_build_lens(P, C)
%     P  per-figure block (n2, layers, design_rays, fan_max_deg, fan_eps_deg)
%     C  common block     (n1, weights, jump_size_du)
%
%   Self-contained copy of the legacy construction (calculate_angles +
%   construct_lens of LensConstructionGradual.m) so the paper figures do not
%   depend on the vendor pipeline in lib/. Changes, none of which affects the result:
%     - Snell's surface-normal equation is solved in closed form instead of
%       vpasolve (same root; the paper .mat lenses are rebuilt to <= 3e-10 du);
%     - the point placement (find_intersection) is inlined into a preallocated
%       loop, same arithmetic in the same order;
%     - the self-intersection test runs the ORIGINAL pair test only on the
%       segment pairs whose (padded) bounding boxes share a cell of a uniform
%       grid - every pair the original could flag is among them, so every
%       accept/reject decision is the same. O(R) memory and time instead of O(R^2),
%       so hundreds of thousands of design rays are possible.
%   The pre-scaling version is kept in test/sim_build_lens_ref.m; the equivalence
%   test test/test_paper_sim_equivalence.m compares the two.
%   Design fan: alpha_i = (i-1)*(fan_max_deg - fan_eps_deg)/(design_rays - 1),
%   inner vertex at 1 du, source at the origin, every ray collimated (0 deg).

    L  = P.layers;   R = P.design_rays;
    n1 = C.n1;       n2 = P.n2;
    w  = C.weights;
    fprintf('  constructing: n2 = %.4g, %d surfaces, %d design rays, fan 0..%.4f deg ...\n', ...
            n2, L, R, P.fan_max_deg - P.fan_eps_deg);
    t0 = tic;
    verbose = R >= 10000;                          % per-surface progress for long builds

    %% bending schedule and surface angles (calculate_angles)
    alpha = zeros(R, L+1);  gamma = zeros(R, L);
    alpha(:,1) = ((0:R-1).') * (P.fan_max_deg - P.fan_eps_deg) / (R - 1);
    alpha0     = alpha(:,1);
    total_bend = alpha0;                            % final angle 0 = collimated
    J_front    = min(w.J_front, L);
    alpha_max  = max(alpha0);
    wm = zeros(R, L);
    for i = 1:R
        hardness = (alpha0(i) / alpha_max)^w.hardness_exp;
        for j = 1:L
            if j <= J_front
                frac_layer = ((J_front - (j-1)) / J_front)^w.layer_exp;
                wm(i,j) = w.base_w + w.k_shape * hardness * frac_layer;
            else
                wm(i,j) = w.base_w;
            end
        end
    end
    Wsum = sum(wm, 2);
    for j = 1:L
        if mod(j,2) == 1, n_in = n1; n_out = n2; else, n_in = n2; n_out = n1; end
        for i = 1:R
            a_j = alpha(i,j);
            a_n = a_j - total_bend(i) * (wm(i,j) / Wsum(i));
            % n_in*sin(a_j - phi) = n_out*sin(a_n - phi), root with |incidence| <= 90
            phi = atan2d(n_in*sind(a_j) - n_out*sind(a_n), n_in*cosd(a_j) - n_out*cosd(a_n));
            if abs(wrap180(a_j - phi)) > 90, phi = wrap180(phi + 180); end
            gamma(i,j)   = phi + 90;               % surface tangent angle
            alpha(i,j+1) = a_n;
        end
    end
    if verbose, fprintf('    surface angles: %.1f s\n', toc(t0)); end

    %% surfaces, grown one after the other (construct_lens)
    d = 1;  jump = C.jump_size_du;  max_attempts = 100000;
    final_lens = cell(L+1, 1);
    [lt, n] = place_points(d, gamma(:,1), alpha(:,1), zeros(R,2), true, d);
    final_lens{1} = lt(1:n,:);
    for j = 2:L
        prev = final_lens{j-1};
        G  = crossing_grid(final_lens(1:j-1));    % earlier surfaces: fixed for all attempts
        x0 = prev(1,1) + jump;
        ok = false;  attempts = 0;
        while ~ok && attempts < max_attempts
            attempts = attempts + 1;
            [lt, n] = place_points(x0, gamma(:,j), alpha(:,j), prev, false, d);
            if n == R && no_crossing(lt, G)
                final_lens{j} = lt;  ok = true;
            else
                x0 = x0 + jump;
            end
        end
        if ~ok, error('sim_build_lens:failed', 'Failed to construct surface %d after %d attempts.', j, max_attempts); end
        if verbose
            fprintf('    surface %d/%d: %d attempts, elapsed %.1f s\n', j, L, attempts, toc(t0));
        end
    end
    fprintf('  constructed in %.1f s\n', toc(t0));

    % resolution: longest straight segment between neighbouring surface points
    seg_max = 0;  seg_j = 0;
    for j = 1:L
        s = max(hypot(diff(final_lens{j}(:,1)), diff(final_lens{j}(:,2))));
        if s > seg_max, seg_max = s; seg_j = j; end
    end
    fprintf('  resolution: longest segment %.6g mm = %.4g um (surface %d)\n', seg_max, seg_max*1e3, seg_j);

    lens = struct('final_lens', {final_lens}, 'n1', n1, 'n2', n2, 'L', L, 'source_pos', [0 0], ...
                  'design_rays', R, 'longest_segment', seg_max, 'longest_segment_surface', seg_j);
end

% ---------------------------------------------------------------------------
function [lt, n] = place_points(x0, g, a, prev, first, d)
% One surface from its start vertex [x0 0]: point i+1 = find_intersection of the
% line (point i, angle g(i)) with the line (prev(i+1,:), angle a(i+1)) - the
% legacy line_ix inlined, same branches and arithmetic. Stops at the first
% failed intersection (n < R), except on the first surface (first = true),
% where a failure falls back to [d, tand(a(i+1))*d] as in the original.
    R  = numel(g);
    m1v = tand(g);  m2v = tand(a);                 % elementwise tand == scalar tand (bitwise)
    v1  = mod(g,180) == 90;  v2 = mod(a,180) == 90;
    lt = zeros(R, 2);  lt(1,1) = x0;  n = 1;
    px = x0;  py = 0;
    for i = 1:R-1
        qx = prev(i+1,1);  qy = prev(i+1,2);
        bad = false;
        if v1(i)
            x = px; y = m2v(i+1)*(x - qx) + qy;
        elseif v2(i+1)
            x = qx; y = m1v(i)*(x - px) + py;
        else
            m1 = m1v(i); m2 = m2v(i+1);
            if abs(m1 - m2) < 1e-6
                bad = true;
            else
                x = (qy - py + m1*px - m2*qx) / (m1 - m2);
                y = m1*(x - px) + py;
            end
        end
        if ~bad && (abs(x) > 1e6 || abs(y) > 1e6 || isnan(x) || isnan(y)), bad = true; end
        if bad
            if ~first, return; end
            x = d;  y = tand(a(i+1))*d;
        end
        n = n + 1;  lt(n,1) = x;  lt(n,2) = y;
        px = x;  py = y;
    end
end

% ---------------------------------------------------------------------------
function G = crossing_grid(prev_layers)
% Segments of all earlier surfaces (never bridging two surfaces), non-finite ones
% dropped (the original test can never flag them), binned on a uniform grid.
    Q1 = zeros(0,2);  Q2 = zeros(0,2);
    for k = 1:numel(prev_layers)
        Q = prev_layers{k};
        if isempty(Q), continue; end
        Q1 = [Q1; Q(1:end-1,:)]; Q2 = [Q2; Q(2:end,:)]; %#ok<AGROW>
    end
    okQ = all(isfinite(Q1),2) & all(isfinite(Q2),2);
    G.Q1 = Q1(okQ,:);  G.Q2 = Q2(okQ,:);
    G.dqx = G.Q1(:,1) - G.Q2(:,1);  G.dqy = G.Q1(:,2) - G.Q2(:,2);
    G.box = seg_boxes(G.Q1, G.Q2);
    span = max(G.box(:,2) - G.box(:,1), G.box(:,4) - G.box(:,3));
    G = bin_grid(G, 2 * max(median(span), 1e-9));
end

function G = bin_grid(G, h)
% (Re)bin the earlier-surface segments on cells of size h.
    G.h  = h;
    G.x0 = min(G.box(:,1));  G.y0 = min(G.box(:,3));
    G.nx = floor((max(G.box(:,2)) - G.x0) / h) + 1;
    G.ny = floor((max(G.box(:,4)) - G.y0) / h) + 1;
    [keys, seg, G.bigQ] = cell_keys(G.box, G);
    [keys, ord] = sort(keys);
    G.seg = seg(ord);
    first = [true; diff(keys) ~= 0];
    G.ukey   = keys(first);
    G.ustart = find(first);
    G.ucount = diff([G.ustart; numel(keys) + 1]);
end

function box = seg_boxes(A, B)
% Segment bounding boxes [xmin xmax ymin ymax], padded far beyond rounding error
% so that any pair the pair test flags (t,u in [0,1]) shares at least one cell.
    pad = 1e-6 * (1 + max(max(abs(A), [], 2), max(abs(B), [], 2)));
    box = [min(A(:,1),B(:,1)) - pad, max(A(:,1),B(:,1)) + pad, ...
           min(A(:,2),B(:,2)) - pad, max(A(:,2),B(:,2)) + pad];
end

function [keys, seg, big] = cell_keys(box, G)
% Grid cells covered by each box (clipped to the grid), as keys ix*ny + iy.
% Boxes covering more than MAX_CELLS cells are returned in 'big' (tested brute force).
    MAX_CELLS = 256;
    ix0 = max(floor((box(:,1) - G.x0) / G.h), 0);  ix1 = min(floor((box(:,2) - G.x0) / G.h), G.nx - 1);
    iy0 = max(floor((box(:,3) - G.y0) / G.h), 0);  iy1 = min(floor((box(:,4) - G.y0) / G.h), G.ny - 1);
    cx = ix1 - ix0 + 1;  cy = iy1 - iy0 + 1;
    inside = cx > 0 & cy > 0;                      % boxes off the grid meet no earlier segment
    nc = cx .* cy;  nc(~inside) = 0;
    big = find(nc > MAX_CELLS);
    nc(big) = 0;
    s   = find(nc > 0);
    ncs = nc(s);
    seg = rep(s, ncs);
    k   = (1:sum(ncs)).' - rep(cumsum(ncs) - ncs, ncs) - 1;   % 0-based index inside each box
    cyr = rep(cy(s), ncs);
    ix  = rep(ix0(s), ncs) + floor(k ./ cyr);
    iy  = rep(iy0(s), ncs) + mod(k, cyr);
    keys = ix * G.ny + iy;
end

% ---------------------------------------------------------------------------
function ok = no_crossing(new_layer, G)
% is_valid_layer/check_intersection of the legacy scripts: TRUE when no segment
% of new_layer crosses a segment of an earlier surface. Candidate pairs from the
% grid, then the original pair test (same formulas, 1e-9 threshold, t,u in [0,1]).
    ok = true;
    if isempty(G.Q1), return; end
    P1 = new_layer(1:end-1,:);  P2 = new_layer(2:end,:);
    okP = all(isfinite(P1),2) & all(isfinite(P2),2);
    P1 = P1(okP,:);  P2 = P2(okP,:);
    if isempty(P1), return; end
    boxP = seg_boxes(P1, P2);
    % a wildly different new layer (long segments): coarser cells for this attempt
    spanP = max(boxP(:,2) - boxP(:,1), boxP(:,4) - boxP(:,3));
    if median(spanP) > 8 * G.h, G = bin_grid(G, 2 * median(spanP)); end

    [keyP, segP, bigP] = cell_keys(boxP, G);
    [tf, loc] = ismember(keyP, G.ukey);
    segP = segP(tf);  loc = loc(tf);
    cnt  = G.ucount(loc);
    pi_  = rep(segP, cnt);
    k    = (1:sum(cnt)).' - rep(cumsum(cnt) - cnt, cnt);          % 1-based within cell
    qi_  = G.seg(rep(G.ustart(loc), cnt) + k - 1);
    if any_hit(P1, P2, pi_, qi_, G), ok = false; return; end

    % boxes too large for the grid: against everything (chunked)
    allQ = (1:size(G.Q1,1)).';  allP = (1:size(P1,1)).';
    for b = bigP.'
        if any_hit(P1, P2, repmat(b, numel(allQ), 1), allQ, G), ok = false; return; end
    end
    for b = G.bigQ.'
        if any_hit(P1, P2, allP, repmat(b, numel(allP), 1), G), ok = false; return; end
    end
end

function hit_any = any_hit(P1, P2, pi_, qi_, G)
% The original pair test, elementwise over candidate pairs (pi_, qi_), in chunks.
    hit_any = false;
    CH = 2e6;
    for c0 = 1:CH:numel(pi_)
        c = c0:min(c0 + CH - 1, numel(pi_));
        p = pi_(c);  q = qi_(c);
        dpx = P1(p,1) - P2(p,1);  dpy = P1(p,2) - P2(p,2);
        dqx = G.dqx(q);           dqy = G.dqy(q);
        den = dpx.*dqy - dpy.*dqx;
        ax = P1(p,1) - G.Q1(q,1);  ay = P1(p,2) - G.Q1(q,2);
        t = (ax.*dqy - ay.*dqx) ./ den;
        u = -(dpx.*ay - dpy.*ax) ./ den;
        if any((abs(den) >= 1e-9) & t >= 0 & t <= 1 & u >= 0 & u <= 1), hit_any = true; return; end
    end
end

function v = rep(x, n), v = repelem(x(:), n(:)); v = v(:); end   % always a column (repelem of one element is a row)

function a = wrap180(a), a = mod(a + 180, 360) - 180; end
