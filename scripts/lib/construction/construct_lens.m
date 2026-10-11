function [final_lens, gamma_matrix, theta_in_matrix, theta_out_matrix, cstats, glass_info, surfaces, budget] = ...
    construct_lens(L, R, nsurf, source_pos, max_angle, w, epsilon, theta_target, sol, opts)
%CONSTRUCT_LENS  Grow the lens surface by surface from the bending schedule.
%
%   Maths of LensConstructionGradual.m (2026-09-05). The construction variants
%   that changed how a surface is PLACED or SHAPED are folded in through opts:
%     opts.angles      struct passed to bend_weights (method, collimation_fraction, L_design)
%     opts.truncate    true -> knife-edge check (LensConstructionGradualTunedWeightsTest):
%     opts.edge_min    [1 x L] minimum material at the crescent tip, design units; 0 = none
%     opts.glass       [] or struct(enable, before_elements, width_du, height_factor):
%                      rectangular glass spacer forced BEFORE the listed elements
%                      (RelaxatedLensConstructionDipoleWithGlassGap); the next surface
%                      is pushed past the spacer's right edge, the spacer height is
%                      height_factor x the following element's half-height
%     opts.spheres     struct array (surface, center_z_du, radius_du): that surface is a
%                      PRESCRIBED sphere (design.spherical_surfaces) - not constructed,
%                      the design rays are intersected with it and refracted (sphere_layer)
%     opts.clamps      struct array (surface, max_slope_deg, pull): while that surface is
%                      built, any segment steeper than the limit (angle from the plane
%                      normal to the axis; > 90 = undercut) becomes a straight cone at the
%                      limit (design.slope_limits); demoldability is checked in pull direction
%     opts.budget_tol_deg  bending-budget closure tolerance (checks.bending_budget_tol_deg)
%   nsurf: [L x 2] (n_in, n_out) per surface, or [n1 n2] (expand_nsurf).
%   sol: jump_size_du, max_attempts.
%
%   THE DEFICIT CARRY. The bending schedule (bend_weights) gives every surface a
%   share of each ray's total bend. A surface is solved (layer_angles) right before
%   it is built, from the angles the rays actually have. A built surface delivers
%   its share exactly (that is what the Snell solve does). A prescribed sphere or a
%   clamped cone delivers whatever its geometry allows; the shortfall
%   (share - achieved, per ray) is spread over the following surfaces in
%   proportion to their weights (carry(i,j) = D(i) * wm(i,j) / sum wm(i,j..L)),
%   so the last free surface still ends every ray at its planned exit angle. With
%   no sphere and no clamp the carry is never touched and every number equals the
%   original all-at-once schedule.
%
%   Returns final_lens (cell{L+1,1}; layer j = [x r] polyline vertex -> tip, design
%   units, inner vertex at 1 du, ONE ROW PER DESIGN RAY for every kind of surface),
%   the angle matrices (actual tangents / angles, clamped or radial where it applies),
%   cstats (attempts per surface, solver fallbacks, layer-1 failsafes), glass_info
%   ([] unless a spacer was built), surfaces (1 x L, see surface_template: kind and,
%   for a sphere, its exact dense arc) and budget (planned / carried / achieved /
%   deficit per ray and surface, closure residual, per-layer summary).

    if nargin < 10 || isempty(opts), opts = struct(); end
    nsurf = expand_nsurf(nsurf, L);
    aopts = struct();  if isfield(opts, 'angles'),   aopts = opts.angles; end
    truncate = false;  if isfield(opts, 'truncate'), truncate = logical(opts.truncate); end
    edge_min = zeros(1, L);
    if isfield(opts, 'edge_min') && ~isempty(opts.edge_min)
        m = opts.edge_min(:).';  nn = min(L, numel(m));  edge_min(1:nn) = m(1:nn);
    end
    glass = [];
    if isfield(opts, 'glass') && ~isempty(opts.glass) && opts.glass.enable && ~isempty(opts.glass.before_elements)
        glass = opts.glass;
        glass.before_elements = unique(glass.before_elements(:).');
        if any(glass.before_elements < 2) || any(glass.before_elements > L/2)
            error('construct_lens:glass', 'glass_cell.before_elements must be in [2 .. %d] for layers_count = %d.', L/2, L);
        end
    end
    % prescribed spheres and slope clamps: one slot per surface
    sph = cell(1, L);  clp = cell(1, L);
    if isfield(opts, 'spheres') && ~isempty(opts.spheres)
        for k = 1:numel(opts.spheres)
            s = opts.spheres(k);
            if s.surface < 1 || s.surface > L || s.surface ~= round(s.surface)
                error('construct_lens:sphere', 'design.spherical_surfaces: surface %g is not one of 1..%d', s.surface, L);
            end
            sph{s.surface} = s;
        end
    end
    if isfield(opts, 'clamps') && ~isempty(opts.clamps)
        for k = 1:numel(opts.clamps)
            s = opts.clamps(k);
            if s.surface < 1 || s.surface > L || s.surface ~= round(s.surface)
                error('construct_lens:clamp', 'design.slope_limits: surface %g is not one of 1..%d', s.surface, L);
            end
            if ~isempty(sph{s.surface})
                error('construct_lens:conflict', 'surface %d is both a prescribed sphere and slope-limited; choose one.', s.surface);
            end
            clp{s.surface} = s;
        end
    end
    tol_budget = 0.01;
    if isfield(opts, 'budget_tol_deg') && ~isempty(opts.budget_tol_deg), tol_budget = opts.budget_tol_deg; end
    any_variant = any(~cellfun(@isempty, sph)) || any(~cellfun(@isempty, clp));

    % ---- the bending schedule; each surface's Snell solve happens right before it is built ----
    W = bend_weights(L, R, max_angle, w, epsilon, theta_target, aopts);
    alpha = zeros(R, L+1);  alpha(:, 1) = W.alpha0;
    gamma_matrix     = zeros(R, L);
    theta_in_matrix  = zeros(R, L);
    theta_out_matrix = zeros(R, L);
    n_fallback = 0;
    planned  = zeros(R, L);  carried = zeros(R, L);  achieved = zeros(R, L);  deficit = zeros(R, L);
    unphys   = false(R, L);
    D = zeros(R, 1);  carrying = false;              % shortfall still to be distributed
    surfaces = repmat(surface_template('built'), 1, L);

    d          = 1;                    % inner vertex at 1 design unit (defines the du)
    jump_size  = sol.jump_size_du;
    max_attempts = sol.max_attempts;
    final_lens = cell(L+1, 1);
    n_failsafe = 0;
    attempts_per_layer = ones(1, L);

    % glass spacers: gap k is inserted before element e -> the outer surface of element
    % e-1 is j_insert = 2(e-1); the first surface of element e (j_enforce = j_insert+1)
    % must start beyond the gap
    glass_info = [];
    if ~isempty(glass)
        glass_info.enabled     = true;
        glass_info.glass_pos   = glass.before_elements;
        glass_info.n3          = glass.n_glass;
        glass_info.glass_width = glass.width_du;
        glass_info.gaps        = struct('element', {}, 'j_insert', {}, 'j_enforce', {}, ...
                                        'x_left', {}, 'x_right', {}, 'h_glass', {});
        j_inserts = 2 * (glass.before_elements - 1);
        j_enforce = j_inserts + 1;
    else
        j_enforce = [];
    end
    tol = 1e-6;

    for j = 1:L
        % ---- what this surface must bend: its share plus the carried shortfall ----
        carry_j = zeros(R, 1);
        if carrying
            % only the surfaces built HERE can absorb a shortfall (in two-stage mode the
            % catalog asphere behind them is a fixed part), so the split stops at L, not Ld
            carry_j = D .* W.wm(:, j) ./ sum(W.wm(:, j:L), 2);
        end
        [a_plan, th_in_p, th_out_p, gam_p, nf, up] = layer_angles(W, j, alpha(:, j), nsurf(j, :), carry_j);
        n_fallback = n_fallback + nf;
        planned(:, j) = alpha(:, j) - a_plan;
        carried(:, j) = carry_j;

        % ================= prescribed sphere: nothing to search =================
        if ~isempty(sph{j})
            if ~isempty(glass) && any(j_enforce == j)
                error('construct_lens:sphere_glass', 'surface %d: a prescribed sphere cannot be the surface right behind a glass spacer.', j);
            end
            if j == 1, prev_pts = repmat(source_pos, R, 1); else, prev_pts = final_lens{j-1}; end
            prev_prof = design_profiles(final_lens(1:j-1), surfaces(1:j-1));
            [pts, a_ach, th_in_s, th_out_s, gam_s, S] = sphere_layer(prev_pts, alpha(:, j), W.alpha0, ...
                sph{j}.center_z_du, sph{j}.radius_du, nsurf(j, :), j, prev_prof);
            final_lens{j} = pts;
            surfaces(j)   = S;
            gamma_matrix(:, j) = gam_s;  theta_in_matrix(:, j) = th_in_s;  theta_out_matrix(:, j) = th_out_s;
            alpha(:, j+1)  = a_ach;
            achieved(:, j) = alpha(:, j) - a_ach;
            deficit(:, j)  = planned(:, j) - achieved(:, j);
            D = D - carry_j + deficit(:, j);  carrying = true;
            % glass: the spacer height follows the element just completed (as for a built surface)
            if ~isempty(glass) && mod(j, 2) == 0
                for kk = 1:numel(glass_info.gaps)
                    if glass_info.gaps(kk).element == j/2 && isnan(glass_info.gaps(kk).h_glass)
                        glass_info.gaps(kk).h_glass = glass.height_factor * max(abs(final_lens{j}(:, 2)));
                    end
                end
            end
            continue;
        end

        % ================= built surface, optionally slope-clamped =================
        unphys(:, j) = up;
        lim = clp{j};
        if j == 1
            % ---- Construct the first layer (j=1) ----
            [lens_temp, gam_act, clamped, nfs] = grow_layer(d, j, R, gam_p, alpha(:, j), [], source_pos, lim, d);
            n_failsafe = n_failsafe + nfs;
            if size(lens_temp, 1) < R       % only possible with a slope limit: the cone never meets the next ray
                i_bad = size(lens_temp, 1) + 1;
                error('construct_lens:clamp_miss', ['surface 1 (slope limit %g deg): the cone at the limit never meets design ray %d ' ...
                       '(%.3f deg emission) ahead of the surface; raise max_slope_deg.'], lim.max_slope_deg, i_bad, W.alpha0(i_bad));
            end
            final_lens{1} = lens_temp;
        else
            % ---- Construct subsequent layers (j=2..L) ----
            layer_valid = false;
            attempts    = 0;
            current_layer_x_start_guess = final_lens{j-1}(1,1) + jump_size;

            % glass spacer before this surface?
            enforce_no_intrusion = false;  x_right = NaN;
            gi = find(j_enforce == j, 1, 'first');
            if ~isempty(gi)
                x_left  = max(final_lens{j-1}(:,1));
                x_right = x_left + glass.width_du;
                current_layer_x_start_guess = current_layer_x_start_guess + glass.width_du;
                enforce_no_intrusion = true;
                g.element   = glass.before_elements(gi);
                g.j_insert  = j_inserts(gi);
                g.j_enforce = j_enforce(gi);
                g.x_left    = x_left;
                g.x_right   = x_right;
                g.h_glass   = NaN;
                glass_info.gaps(end+1) = g;
            end
            prev_prof = design_profiles(final_lens(1:j-1), surfaces(1:j-1));   % spheres as their exact arc

            while ~layer_valid && attempts < max_attempts
                attempts = attempts + 1;
                [lens_temp, gam_act, clamped] = grow_layer(current_layer_x_start_guess, j, R, gam_p, alpha(:, j), final_lens{j-1}, source_pos, lim, d);

                if enforce_no_intrusion && attempts > 50
                    error('construct_lens:glass', ['glass cell before element %d: surface %d cannot be placed behind the spacer ' ...
                           '(x_right = %.3f du) - a re-entrant inner surface wraps back into the gap, and the layer-by-layer ' ...
                           'construction cannot start it further away. The legacy Relaxated script had the same limitation; ' ...
                           'use a spacer only where the next element does not overhang it.'], glass.before_elements(gi), j, x_right);
                end
                if size(lens_temp, 1) == R
                    % --- glass spacer: the new surface must not intrude into the gap ---
                    %     (original test: min x of the surface beyond the spacer's right edge).
                    %     Re-entrant surfaces wrap back behind their vertex by a nearly constant
                    %     distance, so jump straight to the start that clears it instead of
                    %     stepping; give up early when it cannot clear (Relaxated limitation).
                    if enforce_no_intrusion && min(lens_temp(:,1)) < (x_right + tol)
                        wrap = current_layer_x_start_guess - min(lens_temp(:,1));
                        current_layer_x_start_guess = max(current_layer_x_start_guess + jump_size, x_right + tol + wrap + jump_size);
                        continue;
                    end
                    % --- Truncation check: reject X positions that leave too little
                    %     material before the knife-edge intersection (TunedWeightsTest) ---
                    edge_ok = true;
                    if truncate && edge_min(j) > 0
                        p_prev      = final_lens{j-1}(end, :);
                        ang_prev    = gamma_matrix(end, j-1);
                        p_curr      = lens_temp(end, :);
                        ang_curr    = gam_act(end);
                        p_intersect = find_intersection(p_prev, ang_prev, p_curr, ang_curr);
                        if ~any(isnan(p_intersect))
                            delta_y = p_intersect(2) - p_curr(2);
                            if delta_y < edge_min(j)
                                edge_ok = false;
                            end
                        end
                    end

                    if edge_ok && is_valid_layer(lens_temp, prev_prof, j)
                        final_lens{j} = lens_temp;
                        layer_valid   = true;
                        attempts_per_layer(j) = attempts;
                        % glass: the spacer height follows the element just completed
                        if ~isempty(glass) && mod(j,2) == 0
                            elem_built = j/2;
                            for kk = 1:numel(glass_info.gaps)
                                if glass_info.gaps(kk).element == elem_built && isnan(glass_info.gaps(kk).h_glass)
                                    glass_info.gaps(kk).h_glass = glass.height_factor * max(abs(final_lens{j}(:,2)));
                                end
                            end
                        end
                    else
                        current_layer_x_start_guess = current_layer_x_start_guess + jump_size;
                    end
                else
                    current_layer_x_start_guess = current_layer_x_start_guess + jump_size;
                end
            end

            if ~layer_valid
                error('construct_lens:failed', 'Failed to construct layer %d after %d attempts.', j, max_attempts);
            end
        end

        % ---- what the surface actually delivers (a clamped segment refracts at the cone) ----
        a_ach = a_plan;  th_in_a = th_in_p;  th_out_a = th_out_p;
        if any(clamped)
            for i = find(clamped).'
                [a_ach(i), th_in_a(i), th_out_a(i), ok] = refract_at(alpha(i, j), gam_act(i), nsurf(j, :));
                if ~ok
                    error('construct_lens:clamp_tir', ['surface %d (slope limit %g deg): design ray %d at %.3f deg emission is totally ' ...
                           'internally reflected at the clamped cone (incidence %.2f deg, n %.4f -> %.4f).'], ...
                           j, lim.max_slope_deg, i, W.alpha0(i), th_in_a(i), nsurf(j, 1), nsurf(j, 2));
                end
            end
        end
        gamma_matrix(:, j) = gam_act;  theta_in_matrix(:, j) = th_in_a;  theta_out_matrix(:, j) = th_out_a;
        alpha(:, j+1) = a_ach;
        if any(clamped)
            achieved(:, j) = alpha(:, j) - a_ach;
            deficit(:, j)  = planned(:, j) - achieved(:, j);
            D = D - carry_j + deficit(:, j);  carrying = true;
        else
            achieved(:, j) = planned(:, j);
            if carrying, D = D - carry_j; end               % the free surface delivered its carried share
        end
        if ~isempty(lim)
            S = surface_template('clamped');
            S.max_slope_deg = lim.max_slope_deg;
            S.pull          = lim.pull;
            S.n_clamped     = sum(clamped);
            if any(clamped)
                k1 = find(clamped, 1);
                S.first_clamped_ray = k1;
                S.clamp_from_deg    = W.alpha0(k1);
                S.clamp_r_from_du   = lens_temp(min(k1, size(lens_temp, 1)), 2);
            else
                S.first_clamped_ray = Inf;  S.clamp_from_deg = NaN;  S.clamp_r_from_du = NaN;
            end
            [S.demoldable, S.demold_note] = check_demoldable(lens_temp, mod(j, 2) == 1, lim.pull, W.alpha0);
            surfaces(j) = S;
        end
    end
    cstats = struct('attempts', attempts_per_layer, 'fallbacks', n_fallback, 'failsafe_layer1', n_failsafe);

    % ---- bending budget: did every ray leave the last built surface where the schedule planned? ----
    nominal_exit = W.alpha0 - W.total_bend .* (sum(W.wm(:, 1:L), 2) ./ W.Wsum);
    residual = wrapTo180(alpha(:, L+1) - nominal_exit);
    [max_res, iw] = max(abs(residual));
    n_unphys  = sum(unphys(:));
    two_stage = W.Ld > L;                                   % the asphere takes the shares beyond L (never a carried shortfall)
    closed = (n_unphys == 0) && (max_res <= tol_budget) && ~any(abs(deficit(:)) > 180) && ~any(abs(carried(:)) > 180);
    for j = 1:L
        [~, ir] = max(abs(deficit(:, j)));
        nc = 0;  if strcmp(surfaces(j).kind, 'clamped') && ~isempty(surfaces(j).n_clamped), nc = surfaces(j).n_clamped; end
        p = struct('layer', j, 'kind', surfaces(j).kind, ...
                   'share_mean', mean(planned(:, j)), 'share_max', max(abs(planned(:, j))), ...
                   'carried_max', max(abs(carried(:, j))), 'achieved_mean', mean(achieved(:, j)), ...
                   'deficit_max', deficit(ir, j), 'deficit_ray', ir, 'deficit_ray_deg', W.alpha0(ir), 'n_clamped', nc);
        if j == 1, per_layer = repmat(p, 1, L); end
        per_layer(j) = p;
    end
    budget = struct('planned', planned, 'carried', carried, 'achieved', achieved, 'deficit', deficit, ...
                    'residual', residual, 'max_residual_deg', max_res, 'worst_ray', iw, 'worst_ray_deg', W.alpha0(iw), ...
                    'tol_deg', tol_budget, 'closed', closed, 'n_unphysical', n_unphys, 'unphysical', unphys, ...
                    'two_stage', two_stage, 'carried_to_next_stage_deg', max(abs(D)) * double(two_stage), ...
                    'nominal_exit', nominal_exit, 'exit', alpha(:, L+1), 'any_variant', any_variant);
    budget.per_layer = per_layer;
end

% ---------------------------------------------------------------------------
function [lens_temp, gam_act, clamped, n_failsafe] = grow_layer(x_start, j, R, gam_p, alpha_j, prev, source_pos, lim, d)
%GROW_LAYER  One attempt at surface j from an on-axis start: the original vertex-by-vertex loop, plus the slope clamp.
%   Vertex i+1 is where the line through vertex i with the tangent of ray i meets
%   ray i+1 (from the source for j = 1, from its point on the previous surface
%   otherwise). With a slope limit, a segment that would be steeper than the
%   limit (angle from the plane normal to the axis, > 90 = undercut) is replaced
%   by the cone at the limit, running the same way in x and with the radius
%   still growing; that ray then refracts at the cone (clamped(i) = true).
    lens_temp = [x_start, 0];
    gam_act   = gam_p;
    clamped   = false(R, 1);
    n_failsafe = 0;
    sx_prev = -1;                      % every surface runs from its vertex toward the emitter (-x)
    for i = 1:R-1
        point1 = lens_temp(i, :);
        angle1 = gam_p(i);
        if j == 1, point2 = source_pos; else, point2 = prev(i+1, :); end
        angle2 = alpha_j(i+1);
        intersection_point = find_intersection(point1, angle1, point2, angle2);
        if j == 1 && any(isnan(intersection_point))
            intersection_point = [d, tand(angle2)*d]; % Failsafe: simple projection
            n_failsafe = n_failsafe + 1;
        end
        if any(isnan(intersection_point))
            break;
        end
        if ~isempty(lim)
            seg   = intersection_point - point1;
            slope = atan2d(abs(seg(1)), seg(2));                 % surface angle from the plane normal to the axis
            if slope > lim.max_slope_deg + 1e-9
                sx = sign(seg(1));  if sx == 0, sx = sx_prev; end
                angle1 = atan2d(cosd(lim.max_slope_deg), sx * sind(lim.max_slope_deg));   % the cone at the limit
                ip_c = find_intersection(point1, angle1, point2, angle2);
                if j == 1 && any(isnan(ip_c))
                    ip_c = [d, tand(angle2)*d];  n_failsafe = n_failsafe + 1;
                end
                if any(isnan(ip_c)), break; end
                % the cone must meet the ray AHEAD of both the current vertex and the ray's start;
                % a crossing behind either is not a surface (attempt fails; layer 1 reports it)
                if (ip_c - point1) * [sx * sind(lim.max_slope_deg); cosd(lim.max_slope_deg)] <= 0 || ...
                   (ip_c - point2) * [cosd(angle2); sind(angle2)] <= 0
                    break;
                end
                intersection_point = ip_c;
                gam_act(i) = angle1;  clamped(i) = true;
            end
            if abs(seg(1)) > 1e-12, sx_prev = sign(seg(1)); end
        end
        lens_temp = [lens_temp; intersection_point]; %#ok<AGROW>
    end
    % the last ray sits on the end of segment R-1 and refracts at that segment's tangent
    if ~isempty(lim) && R >= 2 && clamped(R-1)
        gam_act(R) = gam_act(R-1);  clamped(R) = true;
    end
end

function [a_new, th_in, th_out, ok] = refract_at(alpha_i, gam, nij)
%REFRACT_AT  Snell refraction of a ray at a surface with tangent angle gam (normal phi = gam - 90).
    phi = gam - 90;
    if abs(wrapTo180(alpha_i - phi)) > 90, phi = wrapTo180(phi + 180); end
    th_in = wrapTo180(alpha_i - phi);
    sin_out = (nij(1) / nij(2)) * sind(th_in);
    ok = abs(sin_out) <= 1;
    if ~ok, a_new = NaN; th_out = NaN; return; end
    th_out = asind(sin_out);
    a_new  = phi + th_out;
    % stay on the branch of the incoming angle: phi may sit a full turn away (cones beyond 90 deg,
    % flipped normals), and a 360 deg jump would enter the deficit carry as a huge "shortfall"
    if abs(a_new - alpha_i) > 180, a_new = a_new - 360 * round((a_new - alpha_i) / 360); end
end
