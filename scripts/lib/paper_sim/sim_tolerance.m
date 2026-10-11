function R = sim_tolerance(lens, T)
%SIM_TOLERANCE  The paper's two fabrication-tolerance checks: lambda/2 surfaces, lambda/4 alignment.
%
%   R = sim_tolerance(lens, T)     lens from sim_build_lens (mm, inner vertex at WD = 1 mm)
%   T = PAPER.tol: lambda_nm, surface_pv_waves (0.5 = lambda/2 peak-to-valley per surface),
%       align_waves (0.25 = lambda/4 offset of the two parts of element 1, transversely and
%       axially), cut_x_mm (bonding plane), corr_len_mm (correlation lengths
%       of the figure error, i.e. the typical bump size), distances_m, dist_grid_m, n_trials,
%       n_rays, seed, emitter ('dipole': power per angle ~ sin^3, as in Fig. 3; 'isotropic': ~ sin),
%       align_sweep_waves (alignment errors evaluated for the figure, in waves; default 1/16..1)
%
%   Method
%     1. The design surfaces are smooth splines through the construction points (the surface a
%        vendor makes from the exported table). Element 1 is two parts, split at the bonding plane.
%     2. Reference: rays from the emitter are traced through the design; the collimated beam fills
%        the envelope |y| <= h_max (exit aperture radius).
%     3. Perturbation: every surface gets a random smooth height field, peak-to-valley lambda/2,
%        with correlation length l_c (the surface is moved along its normal, so the slope error
%        follows from the same field).
%     4. The rays are traced again. A ray is lost when its design position plus its displacement
%        a + b*D (exit shift + deflection x distance) leaves the envelope.
%     5. Monte Carlo: n_trials random surfaces per l_c; mean and worst lost power are reported.
%     Check 2 (separately): the rear part of element 1 offset by the alignment error transversely
%     and axially; rays arriving at the step between the two parts are lost (the fan is sampled
%     finely there). Deterministic, for the spec value (align_waves) and for the sweep
%     align_sweep_waves. The trace covers the upper half-plane only, so one offset is evaluated
%     twice, outward and inward: the two halves of the beam; their mean is the loss of the beam.
%
%   R: alpha, w, h_max, W_ref, mc(l_c) with loss_mean/loss_max at distances_m and
%      curve_mean/curve_max on dist_grid_m, blur (rms ray displacement), the rms deflection, the
%      rms slope of the lambda/2 field; align_only (the spec value: loss, curve, blur, dth_rms);
%      align_sweep (waves, loss per distance; the loss does not depend on the distance).

    if ~isfield(T, 'emitter'), T.emitter = 'dipole'; end
    if ~isfield(T, 'align_sweep_waves'), T.align_sweep_waves = [1/16 1/8 1/4 1/2 1]; end
    lam  = T.lambda_nm * 1e-6;                 % mm
    pv   = T.surface_pv_waves * lam;
    al   = T.align_waves * lam;
    xcut = T.cut_x_mm;

    surf = lens.final_lens(:);
    surf = surf(~cellfun(@isempty, surf));
    L = numel(surf);  n1 = lens.n1;  n2 = lens.n2;
    nin  = zeros(1, L);  nout = zeros(1, L);
    for j = 1:L
        if mod(j, 2) == 1, nin(j) = n1; nout(j) = n2; else, nin(j) = n2; nout(j) = n1; end
    end
    pieces = cell(1, L);                       % element 1: two pieces, every other surface one
    for j = 1:L
        pc = make_piece(surf{j});
        if j <= 2, pieces{j} = split_at_cut(pc, xcut); else, pieces{j} = {pc}; end
    end
    if exist('rng', 'file'), rng(T.seed); else, rand('seed', T.seed); randn('seed', T.seed); end

    %% ---- rays and reference trace -------------------------------------------------
    alpha = linspace(0, 170, T.n_rays).';  da = alpha(2) - alpha(1);
    C_ref = make_curves(pieces);
    [P_ref, ang_ref, ok, hit_ref] = trace_curves(alpha, C_ref, nin, nout, []);
    coll = ok & abs(wrap180(ang_ref)) < 1;
    amax = alpha(find(coll, 1, 'last'));
    res_rms = sqrt(mean(deg2rad(wrap180(ang_ref(coll & alpha <= amax))).^2));
    % fine sampling (da/60 over +-0.25 deg) around the rays that cross the bonding plane on
    % surfaces 1 and 2: the lambda/4 step shadows a band of ~1e-4 rad there, narrower than da
    dal = da * ones(size(alpha));  fine = da / 60;  half = 0.25;  acs = [];
    for j = 1:L
        if numel(pieces{j}) < 2, continue; end
        kc = find(diff(hit_ref.piece(:, j)) ~= 0 & ok(1:end-1) & ok(2:end));
        for m = 1:numel(kc)
            ac = (alpha(kc(m)) + alpha(kc(m) + 1)) / 2;
            if isempty(acs) || all(abs(acs - ac) > 2 * half), acs(end+1) = ac; end %#ok<AGROW>
        end
    end
    for ac = acs
        keep = alpha < ac - half | alpha > ac + half;
        af = (ac - half:fine:ac + half).';
        alpha = [alpha(keep); af];  dal = [dal(keep); fine * ones(size(af))];
    end
    [alpha, order] = sort(alpha);  dal = dal(order);
    [P_ref, ang_ref, ok, hit_ref] = trace_curves(alpha, C_ref, nin, nout, []);
    sel = ok & abs(wrap180(ang_ref)) < 1 & alpha <= amax;
    alpha = alpha(sel); dal = dal(sel); P_ref = P_ref(sel, :); ang_ref = ang_ref(sel);
    hit_ref.piece = hit_ref.piece(sel, :);  hit_ref.facet = hit_ref.facet(sel, :);
    switch lower(T.emitter)                    % power per unit emission angle (ring x pattern)
        case 'dipole',    w = sind(alpha).^3 .* dal;
        case 'isotropic', w = sind(alpha) .* dal;
        otherwise, error('sim_tolerance:emitter', 'emitter must be ''dipole'' or ''isotropic''.');
    end
    w = w / sum(w);
    h_max  = max(surf{end}(:, 2));
    x_obs0 = surf{end}(1, 1);
    W_ref  = sqrt(sum(w .* P_ref(:, 2).^2));
    fprintf('  tolerance: n = %.4g, %d surfaces, %s emitter; fan 0..%.2f deg (%d rays); aperture radius %.1f mm\n', ...
            n2, L, T.emitter, amax, numel(alpha), h_max);
    fprintf('  reference collimation residual %.3f mrad rms (half-facet lag of the construction, cancels in the differences)\n', res_rms * 1e3);
    fprintf('  figure error PV %.0f nm per surface; alignment %.0f nm offset (transverse and axial); bonding plane x = %.2f mm\n', ...
            pv * 1e6, al * 1e6, xcut);

    R = struct('alpha', alpha, 'w', w, 'y_exit', P_ref(:, 2), 'h_max', h_max, 'W_ref', W_ref, 'amax', amax, ...
               'lambda_mm', lam, 'pv_mm', pv, 'align_mm', al, 'cut_x_mm', xcut, 'emitter', T.emitter, ...
               'distances_m', T.distances_m, 'dist_grid_m', T.dist_grid_m, 'corr_len_mm', T.corr_len_mm, 'n_trials', T.n_trials);
    Dmm   = T.distances_m(:).' * 1000;
    Dgrid = T.dist_grid_m(:).' * 1000;
    G = struct('pieces', {pieces}, 'alpha', alpha, 'hit_ref', hit_ref, 'P_ref', P_ref, 'ang_ref', ang_ref, ...
               'w', w, 'h_max', h_max, 'x_obs0', x_obs0, 'Dmm', Dmm, 'Dgrid', Dgrid, 'nin', nin, 'nout', nout);

    %% ---- check 2: alignment of the two parts of element 1 (deterministic) ----
    R.align_only = align_case(G, al, xcut);                           % the spec value
    fprintf('  alignment lambda/%g: deflection %.1f urad rms; lost %.3g%%, all distances\n', ...
            1 / T.align_waves, R.align_only.dth_rms * 1e6, R.align_only.loss(end) * 100);
    wv = T.align_sweep_waves(:).';
    R.align_sweep = struct('waves', wv, 'loss', zeros(numel(wv), numel(Dmm)));
    for k = 1:numel(wv)
        A = align_case(G, wv(k) * lam, xcut);
        R.align_sweep.loss(k, :) = A.loss;
        fprintf('      alignment error lambda x %.4g: lost %.3g%%\n', wv(k), A.loss(end) * 100);
    end

    %% ---- check 1: lambda/2 figure error, Monte Carlo per l_c --------------------------
    R.mc = struct('corr_len_mm', {}, 'slope_rms_mrad', {}, 'dth_rms_mean', {}, 'dth_rms_max', {}, 'blur_mean_mm', {}, ...
                  'blur_max_mm', {}, 'loss_mean', {}, 'loss_max', {}, 'curve_mean', {}, 'curve_max', {});
    for ic = 1:numel(T.corr_len_mm)
        lc = T.corr_len_mm(ic);
        dth = zeros(T.n_trials, 1); sr = dth; blur = zeros(T.n_trials, numel(Dmm)); loss = blur;
        curve = zeros(T.n_trials, numel(Dgrid));
        for it = 1:T.n_trials
            E = evaluate(G, struct('pv', pv, 'lc', lc, 'align', false, 'sgn', 1, 'al', 0, 'xcut', xcut));
            dth(it) = E.dth_rms; sr(it) = E.slope_rms; blur(it, :) = E.blur; loss(it, :) = E.loss; curve(it, :) = E.curve;
        end
        m = struct('corr_len_mm', lc, 'slope_rms_mrad', mean(sr) * 1e3, 'dth_rms_mean', mean(dth), 'dth_rms_max', max(dth), ...
                   'blur_mean_mm', mean(blur, 1), 'blur_max_mm', max(blur, [], 1), 'loss_mean', mean(loss, 1), ...
                   'loss_max', max(loss, [], 1), 'curve_mean', mean(curve, 1), 'curve_max', max(curve, [], 1));
        R.mc(end+1) = m;
        fprintf('  l_c = %g mm (%d trials): rms slope %.3f mrad, deflection %.0f urad rms (max %.0f)\n', ...
                lc, T.n_trials, m.slope_rms_mrad, m.dth_rms_mean * 1e6, m.dth_rms_max * 1e6);
        for id = 1:numel(Dmm)
            fprintf('      D = %g m: blur %.0f um (max %.0f); lost power mean %.3g%%, max %.3g%%\n', Dmm(id) / 1000, ...
                    m.blur_mean_mm(id) * 1e3, m.blur_max_mm(id) * 1e3, m.loss_mean(id) * 100, m.loss_max(id) * 100);
        end
    end
end

%% ===========================================================================
%  perturbation and evaluation
%% ===========================================================================
function A = align_case(G, al, xcut)
% the rear part of element 1 offset by al transversely and axially. The trace covers the upper
% half-plane only, so the offset is evaluated twice, outward (+al) and inward (-al): the two halves
% of the beam for one offset. Their mean is the loss of the whole beam (rms for blur and deflection).
    E1 = evaluate(G, struct('pv', 0, 'lc', 1, 'align', true, 'sgn',  1, 'al', al, 'xcut', xcut));
    E2 = evaluate(G, struct('pv', 0, 'lc', 1, 'align', true, 'sgn', -1, 'al', al, 'xcut', xcut));
    A = E1;
    A.loss = (E1.loss + E2.loss) / 2;                 A.curve   = (E1.curve + E2.curve) / 2;
    A.blur = sqrt((E1.blur.^2 + E2.blur.^2) / 2);     A.dth_rms = sqrt((E1.dth_rms^2 + E2.dth_rms^2) / 2);
end

function E = evaluate(G, P)
% one perturbed lens: displacement of every ray, deflection, blur and lost power per distance
    [pieces, slope_rms] = perturbed_pieces(G.pieces, P);
    [Pp, ang, okp] = trace_curves(G.alpha, make_curves(pieces), G.nin, G.nout, G.hit_ref);
    dth = deg2rad(wrap180(ang) - wrap180(G.ang_ref));
    tp = tand(wrap180(ang));  tr = tand(wrap180(G.ang_ref));
    a = (Pp(:, 2) - G.P_ref(:, 2)) + (G.x_obs0 - Pp(:, 1)) .* tp - (G.x_obs0 - G.P_ref(:, 1)) .* tr;   % exit shift
    b = tp - tr;                                                                                     % deflection
    w = G.w;  wn = sum(w(okp));
    E = struct('a', a, 'b', b, 'okp', okp, 'slope_rms', slope_rms, 'dth_rms', sqrt(sum(w(okp) .* dth(okp).^2) / wn));
    E.blur = zeros(1, numel(G.Dmm)); E.loss = E.blur;
    for id = 1:numel(G.Dmm)
        dy = a + b * G.Dmm(id);
        E.blur(id) = sqrt(sum(w(okp) .* dy(okp).^2) / wn);
        E.loss(id) = sum(w(abs(G.P_ref(:, 2) + dy) > G.h_max | ~okp));
    end
    E.curve = zeros(1, numel(G.Dgrid));
    for id = 1:numel(G.Dgrid)
        E.curve(id) = sum(w(abs(G.P_ref(:, 2) + a + b * G.Dgrid(id)) > G.h_max | ~okp));
    end
end

function [pieces, slope_rms] = perturbed_pieces(pieces0, P)
% figure error (one random height field per surface, continuous across the bonding plane, applied
% along the normal) and the alignment of the rear part of element 1 (offset al transversely, sign
% sgn, and axially)
    L = numel(pieces0);  pieces = pieces0;  sr = zeros(1, L);
    for j = 1:L
        if P.pv > 0
            srange = [inf, -inf];
            for q = 1:numel(pieces0{j})
                sg = piece_arclength(pieces0{j}{q});
                srange = [min(srange(1), sg(1)), max(srange(2), sg(end))];
            end
            fld = figure_field(srange, P.lc, P.pv);
            sr(j) = fld.slope_rms;
        end
        for q = 1:numel(pieces0{j})
            pc = pieces0{j}{q};  p = pc.pts;  tg = pc.tang;
            if P.pv > 0
                sg = piece_arclength(pc);
                h = interp1(fld.grid, fld.h, sg, 'linear', 'extrap');
                p = p + h .* [-sin(tg), cos(tg)];
            end
            if P.align && j <= 2 && q == 2
                p = [p(:, 1) - P.al, p(:, 2) + P.sgn * P.al];
            end
            pieces{j}{q} = struct('pts', p, 'tang', tg, 'own', pc.own, 's_off', pc.s_off);
        end
    end
    slope_rms = mean(sr);
end

function sg = piece_arclength(pc)
% arc length of the piece's points on the surface (global: the back piece of a split surface
% carries the offset s_off of its first point)
    sg = pc.s_off + [0; cumsum(hypot(diff(pc.pts(:, 1)), diff(pc.pts(:, 2))))];
end

function fld = figure_field(srange, lc, pv)
% smooth random height field h(s) over the arc length srange of one surface: white noise smoothed
% with a Gaussian of correlation length lc, scaled to the peak-to-valley pv. fld: grid, h,
% slope_rms [rad] of the field
    ds = lc / 10;  grid = (srange(1) - 3 * lc:ds:srange(2) + 3 * lc).';
    wn = randn(numel(grid), 1);
    kern = exp(-((-3 * lc:ds:3 * lc).' / lc).^2);
    hg = conv(wn, kern, 'same');
    dg = gradient(hg, ds);
    in = grid >= srange(1) & grid <= srange(2);
    sr = sqrt(mean(dg(in).^2));
    f = pv / (max(hg(in)) - min(hg(in)));
    fld = struct('grid', grid, 'h', hg * f, 'slope_rms', sr * f);
end

function pc = make_piece(pts)
% design piece: points + the tangent the construction prescribes at each point = the direction of
% the facet that starts there (the last point keeps the last facet's direction); own = the facets
% a ray may hit on this piece (all of them for a whole surface)
    seg = diff(pts, 1, 1);
    tg = atan2(seg(:, 2), seg(:, 1));
    pc = struct('pts', pts, 'tang', [tg; tg(end)], 'own', [1, size(pts, 1) - 1], 's_off', 0);
end

function pc = split_at_cut(piece, xcut)
% two pieces: front (from the vertex to the bonding plane) and back (bonding plane to the tip).
% The crossing point c is a point of both. Each piece carries the design points up to three facets
% beyond c, so that both splines are interior (not end-conditioned) around the cut and agree there
% to well below a microradian; 'own' limits the hits to each piece's own side of c (a ray may land
% a little beyond c after the Newton refinement, on the overlap, where the spline is consistent).
% A ray arriving at the step between the offset parts hits neither own range and is counted lost
% (the step's own face: lambda/4 high, it scatters ~1e-5 of the rays).
    pts = piece.pts;  tg = piece.tang;  n = size(pts, 1);
    i = find((pts(1:end-1, 1) - xcut) .* (pts(2:end, 1) - xcut) < 0, 1);
    if isempty(i), pc = {piece}; return; end
    a = pts(i, :); b = pts(i + 1, :);
    c = a + (xcut - a(1)) / (b(1) - a(1)) * (b - a);
    ia = max(1, i - 2);  ib = min(n, i + 3);
    s_all = [0; cumsum(hypot(diff(pts(:, 1)), diff(pts(:, 2))))];      % the back piece's global arc length
    pc = {struct('pts', [pts(1:i, :); c; pts(i + 1:ib, :)], 'tang', [tg(1:i); tg(i); tg(i + 1:ib)], ...
                 'own', [1, i], 's_off', 0), ...
          struct('pts', [pts(ia:i, :); c; pts(i + 1:end, :)], 'tang', [tg(ia:i); tg(i); tg(i + 1:end)], ...
                 'own', [i - ia + 2, n - ia + 1], 's_off', s_all(ia))};
end

%% ===========================================================================
%  smooth-surface tracer
%% ===========================================================================
function C = make_curves(pieces)
% parametric cubic spline (chord-length parameter) through the points of every piece;
% pp-form coefficients [a b c d] in du = u - s_k
    L = numel(pieces);  C = cell(1, L);
    for j = 1:L
        C{j} = cell(1, numel(pieces{j}));
        for q = 1:numel(pieces{j})
            pts = pieces{j}{q}.pts;
            s = [0; cumsum(hypot(diff(pts(:, 1)), diff(pts(:, 2))))];
            [~, cx] = unmkpp(spline(s, pts(:, 1)));
            [~, cy] = unmkpp(spline(s, pts(:, 2)));
            C{j}{q} = struct('pts', pts, 's', s, 'cx', cx, 'cy', cy, 'own', pieces{j}{q}.own);
        end
    end
end

function [x, y, dx, dy] = curve_eval(c, k, u)
    du = u - c.s(k);
    cx = c.cx(k, :); cy = c.cy(k, :);
    x  = ((cx(:, 1) .* du + cx(:, 2)) .* du + cx(:, 3)) .* du + cx(:, 4);
    y  = ((cy(:, 1) .* du + cy(:, 2)) .* du + cy(:, 3)) .* du + cy(:, 4);
    dx = (3 * cx(:, 1) .* du + 2 * cx(:, 2)) .* du + cx(:, 3);
    dy = (3 * cy(:, 1) .* du + 2 * cy(:, 2)) .* du + cy(:, 3);
end

function [P, ang, ok, hit] = trace_curves(alpha, C, nin, nout, hit_ref)
% Trace all rays through the smooth surfaces. hit_ref (from the reference trace) narrows the
% coarse search to the facets around the reference hit; [] = full search.
    N = numel(alpha); L = numel(C);
    P = zeros(N, 2); ang = alpha; ok = true(N, 1);
    hit = struct('piece', zeros(N, L), 'facet', zeros(N, L));
    for j = 1:L
        if isempty(hit_ref), qref = []; kref = [];
        else,                qref = hit_ref.piece(:, j); kref = hit_ref.facet(:, j);
        end
        [Pn, angn, okj, q, k] = hit_surface(P, ang, C{j}, nin(j), nout(j), qref, kref);
        ok = ok & okj;
        P(okj, :) = Pn(okj, :); ang(okj) = angn(okj);
        hit.piece(:, j) = q; hit.facet(:, j) = k;
    end
end

function [P, ang_new, ok, qbest, kbest] = hit_surface(P0, ang, pieces, ni, no, qref, kref)
    N = numel(ang);  d = [cosd(ang), sind(ang)];
    tbest = inf(N, 1); qbest = zeros(N, 1); kbest = ones(N, 1); ubest = zeros(N, 1);
    for q = 1:numel(pieces)
        c = pieces{q};  nf = numel(c.s) - 1;
        if isempty(qref)
            lo = ones(N, 1); hi = nf * ones(N, 1);
        else
            win = 40;
            lo = max(1, kref - win); hi = min(nf, kref + win);
            lo(qref ~= q) = 1; hi(qref ~= q) = nf;         % other piece: full search
        end
        lo = max(lo, c.own(1));  hi = min(hi, c.own(2));   % this piece's own side of the cut
        [t, k, u] = coarse_hit(P0, d, c, lo, hi);
        better = t < tbest;
        tbest(better) = t(better); qbest(better) = q; kbest(better) = k(better); ubest(better) = u(better);
    end
    ok = isfinite(tbest);
    P = P0; ang_new = ang;
    if ~any(ok), return; end
    % Newton refinement on the spline of the chosen piece
    idx = find(ok);
    for q = 1:numel(pieces)
        ii = idx(qbest(idx) == q);
        if isempty(ii), continue; end
        c = pieces{q};  O = P0(ii, :); dd = d(ii, :); u = ubest(ii); k = kbest(ii);
        ns = numel(c.s);
        for it = 1:6
            [x, y, dx, dy] = curve_eval(c, k, u);
            F  = dd(:, 1) .* (y - O(:, 2)) - dd(:, 2) .* (x - O(:, 1));
            dF = dd(:, 1) .* dy - dd(:, 2) .* dx;
            u  = u - F ./ dF;
            u  = min(max(u, c.s(1)), c.s(end));
            k  = min(max(1, floor(interp1(c.s, 1:ns, u, 'linear', 'extrap'))), ns - 1);
        end
        [x, y, dx, dy] = curve_eval(c, k, u);
        t = (x - O(:, 1)) .* dd(:, 1) + (y - O(:, 2)) .* dd(:, 2);
        [a_new, okr] = refract_tangent(ang(ii), dx, dy, ni, no);
        good = t > 1e-9 & okr;
        P(ii(good), :) = [x(good), y(good)];  ang_new(ii(good)) = a_new(good);
        ok(ii(~good)) = false;
    end
end

function [t, k, u] = coarse_hit(P0, d, c, lo, hi)
% nearest valid intersection of each ray with the facets lo..hi of the polyline of c (chunked)
    N = size(P0, 1);  A = c.pts(1:end-1, :); B = c.pts(2:end, :); Sg = B - A;
    t = inf(N, 1); k = ones(N, 1); u = zeros(N, 1);
    chunk = 1000;
    for c0 = 1:chunk:N
        ii = (c0:min(c0 + chunk - 1, N)).';
        kmin = min(lo(ii)); kmax = max(hi(ii)); ks = kmin:kmax;
        AOx = A(ks, 1).' - P0(ii, 1);  AOy = A(ks, 2).' - P0(ii, 2);
        den = d(ii, 1) * Sg(ks, 2).' - d(ii, 2) * Sg(ks, 1).';
        tt = (AOx .* Sg(ks, 2).' - AOy .* Sg(ks, 1).') ./ den;
        uu = (AOx .* d(ii, 2) - AOy .* d(ii, 1)) ./ den;
        inwin = (ks >= lo(ii)) & (ks <= hi(ii));
        valid = inwin & abs(den) > 1e-12 & tt > 1e-9 & uu >= -1e-6 & uu <= 1 + 1e-6;
        tt(~valid) = inf;
        [tmin, kk] = min(tt, [], 2);
        t(ii) = tmin;  kabs = ks(kk).';  k(ii) = kabs;
        uf = uu(sub2ind(size(uu), (1:numel(ii)).', kk));
        u(ii) = c.s(kabs) + min(max(uf, 0), 1) .* (c.s(kabs + 1) - c.s(kabs));
    end
end

function [ang_new, ok] = refract_tangent(ang, tx, ty, ni, no)
% Snell at a surface with tangent (tx, ty), the NA2 normal convention
    nrm = hypot(tx, ty);  tx = tx ./ nrm;  ty = ty ./ nrm;
    dx = cosd(ang); dy = sind(ang);
    use_ccw = dx .* (-ty) + dy .* tx >= dx .* ty + dy .* (-tx);
    nx = -ty; ny = tx;  nx(~use_ccw) = ty(~use_ccw); ny(~use_ccw) = -tx(~use_ccw);
    angN = atan2d(ny, nx);
    th_in = wrap180(ang - angN);
    flip = abs(th_in) > 90;
    angN(flip) = wrap180(angN(flip) + 180);  th_in = wrap180(ang - angN);
    s_out = (ni / no) * sind(th_in);
    ok = abs(s_out) <= 1;
    s_out = max(min(s_out, 1), -1);
    ang_new = angN + asind(s_out);
end

function a = wrap180(a), a = mod(a + 180, 360) - 180; end

