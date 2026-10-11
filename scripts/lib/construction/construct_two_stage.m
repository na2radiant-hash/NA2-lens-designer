function lens = construct_two_stage(lens, D, w, sol, copts, mm_per_du, nsurf)
%CONSTRUCT_TWO_STAGE  Omni pre-collimator + commercial asphere (LensConstructionGradual_3Elem).
%
%   lens = construct_two_stage(lens, D, w, sol, copts, mm_per_du, nsurf)
%     nsurf  [L x 2] (n_in, n_out) per omni surface (design.element_materials);
%            omitted = [n_outside n_lens] alternating as before
%
%   Port of LensConstructionGradual_3Elem.m. The script builds only the first
%   D.layers_count omni surfaces (6 = three crescent elements) while the bending
%   WEIGHTS are still spread over a larger design budget, lets a catalog asphere
%   finish the collimation, and then rebuilds the LAST omni surface so that the
%   residual error of the pair cancels ("tuned envelope", Stage 3).
%
%   Inputs (all as build_lens assembles them)
%     lens      pre-filled struct: L, n1, n2, source_pos, design_max_angle,
%               nominal_max_angle, mm_per_du, cstats, glass_info, asphere, source
%     D         cfg.design
%     w         D.weights          (J_front, k_shape, base_w, hardness_exp, layer_exp)
%     sol       D.solver           (method, jump_size_du, max_attempts)
%     copts     construct_lens options (angles / truncate / edge_min / glass)
%     mm_per_du physical scale, mm per design unit (= D.WD_mm)
%
%   Stages
%     1  construct_lens over D.layers_count surfaces, with
%        copts.angles.L_design = D.layers_design_budget (empty -> max(8, layers_count)).
%     2  the asphere's two surfaces as [x r] polylines, placed x_offset_mm behind
%        the rightmost point of the omni stack (script lines 117-123).
%     3  optional error-cancelling rebuild of surface D.layers_count, then the
%        asphere is re-placed 2 mm behind the (now bulged) stack, exactly as the
%        script does at lines 661-669.
%     Stage 4 of the script (the final validation ray trace) is NOT done here -
%     the library traces the finished lens separately through trace_rays.
%
%   Returns lens with final_lens, gamma_matrix, theta_in_matrix, theta_out_matrix,
%   cstats, glass_info, source = 'built (two-stage)', plus
%     lens.asphere                 S1, S2 ([N x 2] upper-half polylines, du, what
%                                  build_stack traces), S1_full/S2_full (the
%                                  script's full-aperture sampling, used by the
%                                  Stage-3 internal trace), n, model, name,
%                                  x_vertex1, x_vertex2, CT_du, half_aperture_du,
%                                  R_du, k, coef_du, asphere_on_s2, mm parameters
%                                  and the offsets actually applied
%     lens.final_lens_uncorrected  the Stage-1+2 surfaces (correction on only)
%     lens.correction              envelope arrays and the Stage-3 bookkeeping,
%                                  including gamma_prev / gamma_new for the
%                                  rebuilt surface
%
%   After a Stage-3 rebuild, gamma_matrix(:, layers_count) holds the NEW normals
%   while theta_in_matrix / theta_out_matrix still hold the pre-correction
%   incidence and refraction angles of that surface - exactly what the script
%   saves (it overwrites only gamma_matrix, line 636). lens.correction keeps both
%   normal columns, so nothing is lost.
%
%   WEIGHTS. The script's pre-collimation branch (its calculate_angles,
%   full_collimation = false, lines 863-869) uses
%       J_front = 6, k_shape = 3.5, base_w = 0.8, hardness_exp = 2, layer_exp = 0.8
%   which differ from the main script's set. They are NOT hard-coded here - put
%   those five numbers in design.weights to reproduce the script.
%
%   UNITS. The script worked in millimetres with the inner vertex at x = 0.5 and
%   WD = 0.5 mm; here the inner vertex is at 1 du, so script_x = lens_x * mm_per_du
%   and every millimetre parameter of the asphere is divided by mm_per_du (radii,
%   CT, aperture, offsets) while a coefficient of the r^(2m) term is multiplied by
%   mm_per_du^(2m-1). With mm_per_du = 0.5 the scalings are exact powers of two,
%   so the port reproduces the script bit for bit.

    % ---------------------------------------------------------------- setup
    CA = D.commercial_asphere;
    R  = D.rays_count;
    Lc = D.layers_count;
    n1 = D.n_outside;
    s  = mm_per_du;
    if nargin < 7 || isempty(nsurf), nsurf = [D.n_outside, D.n_lens]; end
    nsurf = expand_nsurf(nsurf, Lc);

    % --------------------------------------------------- Stage 1: omni surfaces
    % Script lines 104-106 + its construct_lens (line 971): calculate_angles gets
    % L_design (the full weight distribution) while only L layers are built.
    aopts = struct();
    if isfield(copts, 'angles') && ~isempty(copts.angles), aopts = copts.angles; end
    Ld = [];
    if isfield(D, 'layers_design_budget'), Ld = D.layers_design_budget; end
    if isempty(Ld), Ld = max(8, Lc); end     % script's layers_design default = 8
    aopts.L_design = Ld;
    copts.angles   = aopts;

    [final_lens, gamma_matrix, theta_in_matrix, theta_out_matrix, cstats, glass_info, surfaces, budget] = construct_lens( ...
        Lc, R, nsurf, lens.source_pos, lens.design_max_angle, ...
        w, D.fan_epsilon_deg, D.collimation_target_deg, sol, copts);

    % --------------------------------------------------- Stage 2: the asphere
    if strcmpi(CA.model, 'custom')
        A = CA.custom;
        if ~isfield(A, 'name') || isempty(A.name), A.name = 'custom (config block)'; end
    else
        A = asphere_catalog(CA.model);
    end
    Adu = asphere_to_du(A, s);               % mm -> design units
    n3  = A.n;

    x_offset_du = CA.x_offset_mm / s;                       % script: stage2_x_offset = 1 mm
    x_vertex1   = stack_right_edge(final_lens) + x_offset_du;   % script lines 118-120
    [S1_pts, S2_pts] = generate_commercial_lens(Adu.half_aperture, x_vertex1, Adu.CT, Adu.asphere_on_s2, Adu);

    % --------------------------------------------------- Stage 3: correction
    lens.final_lens_uncorrected = [];
    lens.correction             = [];
    correction_on = isfield(CA, 'correction') && ~isempty(CA.correction) && CA.correction.enable;

    if correction_on
        CO = CA.correction;
        lens.final_lens_uncorrected = final_lens;   % keeps the uncorrected surface Lc
        eval_dZdy = make_eval_dZdy(Adu);            % script lines 310-317, in du

        % --- 1. exact ray angles hitting the last omni surface from the inside
        %        (script lines 530-533)
        gamma_prev  = gamma_matrix(:, Lc);          % normals before the rebuild
        phi_L       = gamma_matrix(:, Lc) - 90;
        alpha_in_L  = theta_in_matrix(:, Lc)  + phi_L;
        alpha_out_L = theta_out_matrix(:, Lc) + phi_L;   % current exit angles

        target_alpha_out = zeros(R, 1);
        valid_correction = false(R, 1);

        % --- 2. trace the construction rays forward through the asphere to get
        %        the exit angle each ray WOULD need (script lines 538-570)
        for i = 1:R
            P_start = final_lens{Lc}(i, :);
            a_start = alpha_out_L(i);

            [hit1, P_S1, a_after_S1] = rt_first_hit(P_start, a_start, S1_pts, n1, n3);
            if ~hit1, continue; end

            if Adu.asphere_on_s2
                [hit2, P_S2, ~] = rt_first_hit(P_S1, a_after_S1, S2_pts, n3, n1);
                if ~hit2, continue; end
                dZdy = eval_dZdy(P_S2(2));
                angN = atan2d(dZdy, 1);
                theta_out_req = wrapTo180(0 - angN);
                sin_in = (n1/n3) * sind(theta_out_req);
                if abs(sin_in) >= 1, continue; end
                alpha_g = wrapTo180(angN + asind(sin_in));
                sin_air = (n3/n1) * sind(alpha_g);
                if abs(sin_air) >= 1, continue; end
                alpha_req = asind(sin_air);
            else
                dZdy = eval_dZdy(P_S1(2));
                angN = atan2d(dZdy, 1);
                theta_g = wrapTo180(0 - angN);
                sin_air = (n3/n1) * sind(theta_g);
                if abs(sin_air) >= 1, continue; end
                alpha_req = wrapTo180(angN + asind(sin_air));
            end

            target_alpha_out(i) = alpha_req;
            valid_correction(i) = true;
        end
        % rays that never made it through keep their present angle (script line 570)
        target_alpha_out(~valid_correction) = alpha_out_L(~valid_correction);

        % --- 2.5 parametric calibration envelope (script lines 572-595)
        tune_amplitude = CO.tune_amplitude;
        tune_power     = CO.tune_power;
        edge_baseline  = 0.23;                      % script line 589 (hard-coded floor)
        if isfield(CO, 'edge_baseline') && ~isempty(CO.edge_baseline)
            edge_baseline = CO.edge_baseline;
        end
        % The script hard-codes tune_peak_ray = 60 (line 41) while rays_count is
        % 30 (line 39): with a peak beyond the last ray the falling half of the
        % window never runs and the envelope tops out at sin(29/59*pi/2)^p - a
        % bug, harmless only because the reference run used rays_count = 120,
        % where 60 really is the middle ray. The config therefore stores the peak
        % as a FRACTION of rays_count; correction.tune_peak_ray (absolute) may be
        % set to replay the literal 60 for a parity check.
        tune_peak_ray = max(1, round(CO.tune_peak_ray_frac * R));
        if isfield(CO, 'tune_peak_ray') && ~isempty(CO.tune_peak_ray)
            tune_peak_ray = CO.tune_peak_ray;
        end

        correction_weight = zeros(R, 1);
        for i = 1:R
            if i <= tune_peak_ray
                % Scale 0 to 1 from center axis to the peak error
                norm_x = (i - 1) / max(1, tune_peak_ray - 1);
            else
                % Scale 1 to 0 from the peak error to the extreme edge
                norm_x = (R - i) / max(1, R - tune_peak_ray);
            end
            % sine window with the tuning power (note: sin() in RADIANS, as the script)
            correction_weight(i) = tune_amplitude * ((1 - edge_baseline) * (sin(norm_x * pi/2)^tune_power) + edge_baseline);
        end

        delta_alpha        = target_alpha_out - alpha_out_L;
        tuned_target_alpha = alpha_out_L + delta_alpha .* correction_weight;

        % --- 3. new surface normals for the last layer (script lines 599-611)
        new_gamma_L = zeros(R, 1);
        n_g = nsurf(Lc, 1);  n_a = nsurf(Lc, 2);       % the last omni surface: its element's glass -> outside
        for i = 1:R
            a_in  = alpha_in_L(i);
            a_req = tuned_target_alpha(i);
            % Analytical Snell's law solution (fast and stable)
            Y = n_g * sind(a_in) - n_a * sind(a_req);
            X = n_g * cosd(a_in) - n_a * cosd(a_req);
            phi_val = atan2d(Y, X);
            new_gamma_L(i) = phi_val + 90;
        end

        % --- 4. rebuild the last layer (script lines 613-655)
        jump_size    = sol.jump_size_du;      % script: 0.1
        max_attempts = sol.max_attempts;      % script: 100000
        layer_valid  = false;
        attempts     = 0;
        current_layer_x_start_guess = final_lens{Lc-1}(1,1) + jump_size;

        while ~layer_valid && attempts < max_attempts
            attempts  = attempts + 1;
            lens_temp = [current_layer_x_start_guess, 0];
            for i = 1:R-1
                point1 = lens_temp(i, :);
                angle1 = new_gamma_L(i);
                point2 = final_lens{Lc-1}(i+1, :);
                angle2 = alpha_in_L(i+1);     % trajectory from the previous layer is unchanged
                ip = find_intersection(point1, angle1, point2, angle2);
                if any(isnan(ip)), break; end
                lens_temp = [lens_temp; ip]; %#ok<AGROW>
            end

            if size(lens_temp, 1) == R
                if is_valid_layer(lens_temp, final_lens(1:Lc-1), Lc)
                    final_lens{Lc}       = lens_temp;
                    gamma_matrix(:, Lc)  = new_gamma_L;
                    layer_valid          = true;
                else
                    current_layer_x_start_guess = current_layer_x_start_guess + jump_size;
                end
            else
                current_layer_x_start_guess = current_layer_x_start_guess + jump_size;
            end
        end

        if ~layer_valid
            error('construct_two_stage:correction', ...
                  'Stage 3 failed to rebuild surface %d after %d attempts. Increase design.solver.jump_size_du.', Lc, max_attempts);
        end

        % --- re-place the asphere behind the bulged surface (script lines 661-669)
        x_offset_new_mm = 2;                  % script: stage2_x_offset_new = 2 mm
        if isfield(CO, 'x_offset_after_mm') && ~isempty(CO.x_offset_after_mm)
            x_offset_new_mm = CO.x_offset_after_mm;
        end
        x_offset_du = x_offset_new_mm / s;
        x_vertex1   = stack_right_edge(final_lens) + x_offset_du;
        [S1_pts, S2_pts] = generate_commercial_lens(Adu.half_aperture, x_vertex1, Adu.CT, Adu.asphere_on_s2, Adu);

        lens.correction = struct( ...
            'enabled', true, 'layer', Lc, ...
            'tune_amplitude', tune_amplitude, 'tune_peak_ray', tune_peak_ray, ...
            'tune_peak_ray_frac', CO.tune_peak_ray_frac, 'tune_power', tune_power, ...
            'edge_baseline', edge_baseline, ...
            'correction_weight', correction_weight, 'delta_alpha', delta_alpha, ...
            'alpha_in', alpha_in_L, 'alpha_out_before', alpha_out_L, ...
            'target_alpha_out', target_alpha_out, 'tuned_target_alpha', tuned_target_alpha, ...
            'valid_correction', valid_correction, 'n_valid', sum(valid_correction), ...
            'gamma_prev', gamma_prev, 'gamma_new', new_gamma_L, 'attempts', attempts, ...
            'x_start_du', current_layer_x_start_guess, ...
            'x_offset_after_mm', x_offset_new_mm);
        cstats.correction_attempts = attempts;
        budget.per_layer(Lc).kind = 'built (stage-3 rebuilt)';   % its share is now the error-cancelling target
    end

    % --------------------------------------------------- pack the asphere struct
    % S1/S2 are the upper half (r >= 0), N_pts from the vertex outward - the form
    % build_stack expects. S1_full/S2_full are the script's full-aperture
    % sampling (-CA..+CA, 500 points) that Stage 3 traced against; they are kept
    % so a parity run can reproduce the script's own numbers.
    N_pts = 500;
    r_up  = linspace(0, Adu.half_aperture, N_pts)';
    z_up  = asphere_sag(r_up, Adu.R, Adu.k, Adu.coef);
    x_vertex2 = x_vertex1 + Adu.CT;
    if ~Adu.asphere_on_s2
        S1_up = [x_vertex1 + z_up,               r_up];   % convex asphere faces the omni lens
        S2_up = [x_vertex2 * ones(N_pts,1),      r_up];   % flat
    else
        S1_up = [x_vertex1 * ones(N_pts,1),      r_up];   % flat
        S2_up = [x_vertex2 - z_up,               r_up];   % convex asphere faces the output
    end

    asph = struct();
    asph.S1               = S1_up;
    asph.S2               = S2_up;
    asph.S1_full          = S1_pts;
    asph.S2_full          = S2_pts;
    asph.n                = n3;
    asph.model            = CA.model;
    asph.name             = A.name;
    asph.x_vertex1        = x_vertex1;
    asph.x_vertex2        = x_vertex2;
    asph.CT_du            = Adu.CT;
    asph.half_aperture_du = Adu.half_aperture;
    asph.R_du             = Adu.R;
    asph.k                = Adu.k;
    asph.coef_du          = Adu.coef;
    asph.asphere_on_s2    = Adu.asphere_on_s2;
    asph.x_offset_du      = x_offset_du;
    asph.mm_per_du        = s;
    asph.R_mm             = A.R_mm;
    asph.CT_mm            = A.CT_mm;
    asph.half_aperture_mm = A.half_aperture_mm;
    asph.coef_mm          = struct('D', A.D, 'E', A.E, 'F', A.F, 'G', A.G, ...
                                   'H', A.H, 'J', A.J, 'L', A.L, 'M', A.M);
    asph.x_offset_mm      = x_offset_du * s;
    asph.N_pts            = N_pts;

    % --------------------------------------------------- pack the lens struct
    lens.final_lens       = final_lens;
    lens.gamma_matrix     = gamma_matrix;
    lens.theta_in_matrix  = theta_in_matrix;
    lens.theta_out_matrix = theta_out_matrix;
    lens.cstats           = cstats;
    lens.glass_info       = glass_info;
    lens.asphere          = asph;
    lens.surfaces         = surfaces;
    lens.budget           = budget;
    lens.source           = 'built (two-stage)';
end

%% ============================================================
%  LOCAL HELPERS
%% ============================================================

function Adu = asphere_to_du(A, s)
%ASPHERE_TO_DU  Datasheet millimetres -> design units (s = mm per design unit).
%   Lengths divide by s; the coefficient of the r^(2m) term multiplies by s^(2m-1)
%   so that z(r)/s is the same function of r/s. With the script's convention
%   (D->r^2 ... M->r^16) the exponents are 1, 3, 5, 7, 9, 11, 13, 15.
    Adu.R  = A.R_mm / s;                    % Inf stays Inf
    Adu.k  = A.k;
    Adu.coef = struct('D', A.D * s^1,  'E', A.E * s^3,  'F', A.F * s^5,  'G', A.G * s^7, ...
                      'H', A.H * s^9,  'J', A.J * s^11, 'L', A.L * s^13, 'M', A.M * s^15);
    Adu.CT            = A.CT_mm / s;
    Adu.half_aperture = A.half_aperture_mm / s;
    Adu.asphere_on_s2 = logical(A.asphere_on_s2);
    Adu.n             = A.n;
    % curvature for the verbatim script formulas below (C = 1/R, 0 when flat)
    if isempty(A.R_mm) || isinf(A.R_mm) || A.R_mm == 0
        Adu.C = 0;
    else
        Adu.C = 1 / Adu.R;
    end
end

function x_right = stack_right_edge(final_lens)
%STACK_RIGHT_EDGE  Rightmost point of the built omni surfaces (script lines 118-119).
    nonempty_idx = find(~cellfun(@isempty, final_lens));
    x_right      = max(cellfun(@(c) max(c(:,1)), final_lens(nonempty_idx)));
end

function f = make_eval_dZdy(Adu)
%MAKE_EVAL_DZDY  The script's inline signed sag derivative (lines 310-317), in du.
%   Kept VERBATIM, including that it omits the D, L and M terms (all zero for
%   every catalog model) - asphere_sag has the complete derivative.
    C_  = Adu.C;        kk_ = Adu.k;
    E_  = Adu.coef.E;   F_  = Adu.coef.F;   G_ = Adu.coef.G;
    H_  = Adu.coef.H;   J_  = Adu.coef.J;
    f = @(Y) sign(Y) .* ( ...
        C_.*abs(Y) ./ sqrt(max(1e-14, 1 - (1+kk_)*C_^2.*Y.^2)) ...
        + 4*E_.*abs(Y).^3 + 6*F_.*abs(Y).^5 + 8*G_.*abs(Y).^7 ...
        + 10*H_.*abs(Y).^9 + 12*J_.*abs(Y).^11 );
end

function [S1_pts, S2_pts] = generate_commercial_lens(CA_half, X_start, thickness, asphere_on_s2, c)
% Generate (x,y) polyline arrays for the commercial aspherical lens.
%   VERBATIM from LensConstructionGradual_3Elem.m lines 1093-1127, with the
%   coefficient struct read from the du-scaled fields (c.C, c.k, c.coef.*).
%   asphere_on_s2 = false -> S1 aspheric (vertex at X_start),  S2 flat
%   asphere_on_s2 = true  -> S1 flat (at X_start), S2 aspheric (vertex at X_start+thickness)
%   The sampling is the script's: N_pts over the FULL aperture -CA_half..+CA_half.

if nargin < 4, asphere_on_s2 = false; end

% Unpack coefficients
C_curv = c.C;         k_c    = c.k;
D_coef = c.coef.D;    E_coef = c.coef.E;  F_coef = c.coef.F;  G_coef = c.coef.G;
H_coef = c.coef.H;    J_coef = c.coef.J;  L_coef = c.coef.L;  M_coef = c.coef.M;

N_pts = 500;
Y  = linspace(-CA_half, CA_half, N_pts)';
Y2 = Y.^2;

% Standard aspheric sag (positive, from vertex toward edges)
arg = max(0, 1 - (1+k_c)*C_curv^2 * Y2);
Z = C_curv*Y2 ./ (1 + sqrt(arg)) ...
    + D_coef*Y2    + E_coef*Y2.^2 + F_coef*Y2.^3 + G_coef*Y2.^4 ...
    + H_coef*Y2.^5 + J_coef*Y2.^6 + L_coef*Y2.^7 + M_coef*Y2.^8;

flat = X_start + thickness * ones(N_pts, 1);

if ~asphere_on_s2
    % Convex S1 faces incoming rays: vertex at X_start, edges sag right
    S1_pts = [X_start + Z,  Y];
    S2_pts = [flat,          Y];
else
    % Flat S1 at X_start; convex S2 faces output: vertex at X_start+thickness, edges sag left
    S1_pts = [X_start * ones(N_pts,1),  Y];
    S2_pts = [flat - Z,                  Y];
end
end

function [hit, P_hit, alpha_out] = rt_first_hit(P0, alpha_in, surf_pts, n_in, n_out)
% Walk every segment of surf_pts; keep the closest valid refraction hit.
%   VERBATIM from LensConstructionGradual_3Elem.m lines 1129-1146. The library's
%   own trace uses trace/first_hit.m; this copy exists only so that Stage 3
%   measures the residual exactly as the script did.
hit = false; P_hit = [NaN,NaN]; alpha_out = NaN;
if isempty(surf_pts) || size(surf_pts,1) < 2, return; end
best_d = inf;
for k = 1:size(surf_pts,1)-1
    try
        [a_new, P_int] = rt_refract(P0, alpha_in, surf_pts(k,:), surf_pts(k+1,:), n_in, n_out);
    catch
        continue;
    end
    if any(isnan(P_int)) || isnan(a_new), continue; end
    d = hypot(P_int(1)-P0(1), P_int(2)-P0(2));
    if d > 1e-9 && d < best_d
        best_d = d; P_hit = P_int; alpha_out = a_new; hit = true;
    end
end
end

function [alpha_new, P_hit] = rt_refract(O, alpha, A, B, n_in, n_out)
% Intersect ray (O, alpha deg) with segment A->B and apply Snell's law.
%   VERBATIM from LensConstructionGradual_3Elem.m lines 1148-1174.
D   = [cosd(alpha), sind(alpha)];
S   = B - A;
M   = [D(:), -S(:)];
if abs(det(M)) < 1e-12, error('parallel'); end
sol = M \ (A(:) - O(:));
t = sol(1); u = sol(2);
if t < 1e-9 || u < -1e-6 || u > 1+1e-6, error('no hit'); end
P_hit = O + t * D;

t_hat = S / norm(S);
n_hat = [-t_hat(2), t_hat(1)];
if dot(D, n_hat) > 0, n_hat = -n_hat; end   % normal must oppose incoming ray

angN     = atan2d(n_hat(2), n_hat(1));
th_in    = wrapTo180(atan2d(D(2), D(1)) - angN);
if abs(th_in) > 90
    angN  = wrapTo180(angN + 180);
    th_in = wrapTo180(atan2d(D(2), D(1)) - angN);
end

sin_out = (n_in/n_out) * sind(th_in);
if abs(sin_out) > 1+1e-12, error('TIR'); end
sin_out   = max(min(sin_out, 1), -1);
alpha_new = wrapTo180(angN + asind(sin_out));
end
