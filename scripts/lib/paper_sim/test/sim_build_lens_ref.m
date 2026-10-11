function lens = sim_build_lens_ref(P, C)
%SIM_BUILD_LENS_REF  REFERENCE COPY (pre-scaling, O(R^2)) of sim_build_lens - equivalence tests only. Construct one paper lens from the simulation-mode parameters.
%
%   lens = sim_build_lens(P, C)
%     P  per-figure block (n2, layers, design_rays, fan_max_deg, fan_eps_deg)
%     C  common block     (n1, weights, jump_size_du)
%
%   Self-contained copy of the legacy construction (calculate_angles +
%   construct_lens of LensConstructionGradual.m) so the paper figures do not
%   depend on the vendor pipeline in lib/. Two changes, neither affects the result:
%     - Snell's surface-normal equation is solved in closed form instead of
%       vpasolve (same root; the paper .mat lenses are rebuilt to <= 3e-10 du);
%     - the self-intersection test runs on all segment pairs at once.
%   Design fan: alpha_i = (i-1)*(fan_max_deg - fan_eps_deg)/(design_rays - 1),
%   inner vertex at 1 du, source at the origin, every ray collimated (0 deg).

    L  = P.layers;   R = P.design_rays;
    n1 = C.n1;       n2 = P.n2;
    w  = C.weights;
    fprintf('  constructing: n2 = %.4g, %d surfaces, %d design rays, fan 0..%.4f deg ...\n', ...
            n2, L, R, P.fan_max_deg - P.fan_eps_deg);
    t0 = tic;

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

    %% surfaces, grown one after the other (construct_lens)
    d = 1;  jump = C.jump_size_du;  max_attempts = 100000;
    final_lens = cell(L+1, 1);
    lt = [d, 0];
    for i = 1:R-1
        p = line_ix(lt(i,:), gamma(i,1), [0 0], alpha(i+1,1));
        if any(isnan(p)), p = [d, tand(alpha(i+1,1))*d]; end
        lt = [lt; p]; %#ok<AGROW>
    end
    final_lens{1} = lt;
    for j = 2:L
        x0 = final_lens{j-1}(1,1) + jump;
        ok = false;  attempts = 0;
        while ~ok && attempts < max_attempts
            attempts = attempts + 1;
            lt = [x0, 0];
            for i = 1:R-1
                p = line_ix(lt(i,:), gamma(i,j), final_lens{j-1}(i+1,:), alpha(i+1,j));
                if any(isnan(p)), break; end
                lt = [lt; p]; %#ok<AGROW>
            end
            if size(lt,1) == R && no_crossing(lt, final_lens(1:j-1))
                final_lens{j} = lt;  ok = true;
            else
                x0 = x0 + jump;
            end
        end
        if ~ok, error('sim_build_lens:failed', 'Failed to construct surface %d after %d attempts.', j, max_attempts); end
    end
    fprintf('  constructed in %.1f s\n', toc(t0));
    lens = struct('final_lens', {final_lens}, 'n1', n1, 'n2', n2, 'L', L, 'source_pos', [0 0]);
end

% ---------------------------------------------------------------------------
function p = line_ix(p1, a1, p2, a2)
% find_intersection of the legacy scripts: two lines given by point + angle (deg)
    if mod(a1,180) == 90
        x = p1(1); y = tand(a2)*(x - p2(1)) + p2(2);
    elseif mod(a2,180) == 90
        x = p2(1); y = tand(a1)*(x - p1(1)) + p1(2);
    else
        m1 = tand(a1); m2 = tand(a2);
        if abs(m1 - m2) < 1e-6, p = [NaN NaN]; return; end
        x = (p2(2) - p1(2) + m1*p1(1) - m2*p2(1)) / (m1 - m2);
        y = m1*(x - p1(1)) + p1(2);
    end
    if abs(x) > 1e6 || abs(y) > 1e6, p = [NaN NaN]; return; end
    p = [x, y];
end

% ---------------------------------------------------------------------------
function ok = no_crossing(new_layer, prev_layers)
% is_valid_layer/check_intersection of the legacy scripts, all pairs at once
    ok = true;
    P1 = new_layer(1:end-1,:);  P2 = new_layer(2:end,:);
    okP = all(isfinite(P1),2) & all(isfinite(P2),2);
    for k = 1:numel(prev_layers)
        Q = prev_layers{k};
        if isempty(Q), continue; end
        Q1 = Q(1:end-1,:);  Q2 = Q(2:end,:);
        okQ = all(isfinite(Q1),2) & all(isfinite(Q2),2);
        dpx = P1(:,1) - P2(:,1);  dpy = P1(:,2) - P2(:,2);
        dqx = (Q1(:,1) - Q2(:,1)).';  dqy = (Q1(:,2) - Q2(:,2)).';
        den = dpx*dqy - dpy*dqx;
        ax = P1(:,1) - Q1(:,1).';  ay = P1(:,2) - Q1(:,2).';
        t = (ax.*dqy - ay.*dqx) ./ den;
        u = -(dpx.*ay - dpy.*ax) ./ den;
        hit = (abs(den) >= 1e-9) & t >= 0 & t <= 1 & u >= 0 & u <= 1 & okP & okQ.';
        if any(hit(:)), ok = false; return; end
    end
end

function a = wrap180(a), a = mod(a + 180, 360) - 180; end
