function fig = asphere_check_figure(A_du, n_medium, N_rays, x_start_du, extend_du)
%ASPHERE_CHECK_FIGURE  Standalone sanity check of the commercial asphere.
%
%   fig = asphere_check_figure(A_du, n_medium, N_rays, x_start_du, extend_du)
%
%   Port of AsphericalLensIntegration.m (the whole script body, lines 44-147,
%   plus its local functions): N collimated rays enter from the RIGHT, travel in
%   -x, refract through the element and focus to the left. It is the independent
%   check that the sag / normal / Snell chain of asphere_sag is right - nothing
%   of the omni construction is involved.
%
%   Inputs
%     A_du       the asphere in DESIGN UNITS, either the lens.asphere struct made
%                by construct_two_stage (R_du, k, coef_du, CT_du, half_aperture_du, n)
%                or the same numbers as R, k, coef, CT, half_aperture, n
%     n_medium   surrounding index (default 1)
%     N_rays     collimated input rays (default 21; odd -> one on-axis ray)
%     x_start_du where the collimated rays begin, right of the lens
%                (default CT + 2*half_aperture)
%     extend_du  ray length past the exit surface
%                (default 1.5 x the thin-lens focal length, so the focus is in frame)
%
%   Returns the figure handle. Nothing is saved (the caller decides).
%
%   ORIENTATION. The script's geometry is: Surface 1 = right/input face with its
%   vertex at x = 0, Surface 2 = left/output face with its vertex at x = -CT, and
%   x_s(y) = x_vertex + sag(|y|). Both catalog aspheres are plano-aspheric, so
%   the check is drawn in the script's own configuration - flat input face,
%   aspheric output face doing the focusing - which is the mirror image of how
%   the element sits in the two-stage system (where the same aspheric face
%   COLLIMATES light travelling +x). By reversibility the two are the same test,
%   and this way the sag sign convention of asphere_sag is exercised exactly as
%   generate_commercial_lens uses it: thickness = CT - sag(r), thinning outward.
%
%   NOTE: graphics only - this function draws, it computes nothing the rest of
%   the library consumes.

    if nargin < 2 || isempty(n_medium), n_medium = 1.0; end
    if nargin < 3 || isempty(N_rays),   N_rays   = 21;  end

    A = normalize_asphere(A_du);

    CT      = A.CT;             % centre thickness (design units)
    half_ap = A.half_aperture;  % clear half-aperture (design units)
    n_lens  = A.n;              % glass refractive index

    % Surface 1 - right / input face (flat, see ORIENTATION above)
    R1 = Inf;    K1 = 0;    coef1 = struct();
    % Surface 2 - left / output face (the asphere; converging with R2 > 0)
    R2 = A.R;    K2 = A.k;  coef2 = A.coef;

    if nargin < 4 || isempty(x_start_du), x_start_du = CT + 2*half_ap; end
    if nargin < 5 || isempty(extend_du)
        if isfinite(R2) && R2 ~= 0 && n_lens ~= n_medium
            extend_du = 1.5 * abs(R2) / (n_lens/n_medium - 1);   % ~1.5 focal lengths
        else
            extend_du = 10 * half_ap;
        end
    end
    x_start = x_start_du;
    extend  = extend_du;

    %% -------------------------
    %  Build surface profile functions      (script lines 44-57)
    %  -------------------------
    % sag(r)  : displacement in +x from surface vertex as a function of |y|
    % dsag(r) : d(sag)/dr  (needed for surface normal)
    sag1  = @(r) sag_of (r, R1, K1, coef1);
    dsag1 = @(r) dsag_of(r, R1, K1, coef1);
    sag2  = @(r) sag_of (r, R2, K2, coef2);
    dsag2 = @(r) dsag_of(r, R2, K2, coef2);

    % x-coordinate of each surface as a function of y
    % Surface 1 vertex at x = 0;  Surface 2 vertex at x = -CT
    x_s1 = @(y)  sag1(abs(y));
    x_s2 = @(y) -CT + sag2(abs(y));

    %% -------------------------
    %  Draw lens cross-section              (script lines 59-95)
    %  -------------------------
    fig = figure('Name', 'Aspherical Lens Ray Trace', 'Color', 'w');
    hold on; axis equal; grid on;
    xlabel('x  (optical axis, design units)');
    ylabel('y  (design units)');
    title(sprintf('Aspherical Lens  |  n=%.4f  CT=%.1f du  R2=%.1f du  K2=%.2f', ...
                  n_lens, CT, R2, K2));

    r_plot   = linspace(0, half_ap, 500);
    xs1_top  = sag1(r_plot);          % surface 1 x-profile (upper half)
    xs2_top  = -CT + sag2(r_plot);    % surface 2 x-profile (upper half)

    lens_color = [0.72 0.87 0.98];    % light blue glass fill

    % Upper-half polygon: along S1 from y=0->half_ap, top edge, back along S2
    fill([xs1_top, fliplr(xs2_top)], [r_plot, fliplr(r_plot)], ...
         lens_color, 'EdgeColor', 'none', 'FaceAlpha', 0.7);
    % Lower-half (mirror y)
    fill([xs1_top, fliplr(xs2_top)], -[r_plot, fliplr(r_plot)], ...
         lens_color, 'EdgeColor', 'none', 'FaceAlpha', 0.7);

    % Outlines
    lw = 1.8;
    plot(xs1_top,  r_plot, 'k-', 'LineWidth', lw);   % S1 upper
    plot(xs1_top, -r_plot, 'k-', 'LineWidth', lw);   % S1 lower
    plot(xs2_top,  r_plot, 'k-', 'LineWidth', lw);   % S2 upper
    plot(xs2_top, -r_plot, 'k-', 'LineWidth', lw);   % S2 lower
    % Edge caps at maximum aperture
    plot([xs1_top(end), xs2_top(end)], [ half_ap,  half_ap], 'k-', 'LineWidth', lw);
    plot([xs1_top(end), xs2_top(end)], [-half_ap, -half_ap], 'k-', 'LineWidth', lw);

    % Optical axis
    ax_lo = min(xs2_top) - extend/4;
    ax_hi = x_start + half_ap/2;
    plot([ax_lo, ax_hi], [0, 0], 'k--', 'LineWidth', 0.6);

    %% -------------------------
    %  Ray trace                            (script lines 97-147)
    %  -------------------------
    y_rays = linspace(-half_ap, half_ap, N_rays);

    col_in   = [0.15 0.40 0.85];   % blue   - before lens
    col_lens = [0.10 0.60 0.15];   % green  - inside glass
    col_out  = [0.85 0.15 0.15];   % red    - after lens

    for ri = 1:N_rays
        y0 = y_rays(ri);

        % ---- Segment 1: horizontal collimated ray to Surface 1 ----
        x_hit1 = x_s1(y0);    % trivial for horizontal ray
        y_hit1 = y0;

        % Surface 1 normal (pointing toward +x, into incoming medium)
        [nx1, ny1] = surf_normal(y_hit1, dsag1, +1);

        % Refract: n_medium -> n_lens  (incoming direction is (-1, 0))
        [dx2, dy2] = snell_2d(-1, 0, nx1, ny1, n_medium, n_lens);
        if isnan(dx2), continue; end

        % ---- Segment 2: refracted ray inside glass to Surface 2 ----
        % Find t such that x_hit1+t*dx2 = x_s2(y_hit1+t*dy2)
        F2   = @(t) (x_hit1 + t*dx2) - x_s2(y_hit1 + t*dy2);
        t_bracket = find_bracket(F2, 1e-6, 4*CT / (abs(dx2)+1e-12));
        if isempty(t_bracket), continue; end
        t2   = fzero(F2, t_bracket);
        x_hit2 = x_hit1 + t2*dx2;
        y_hit2 = y_hit1 + t2*dy2;
        if abs(y_hit2) > half_ap + 1e-6, continue; end   % missed aperture

        % Surface 2 normal (pointing toward +x, into incoming medium = glass)
        [nx2, ny2] = surf_normal(y_hit2, dsag2, +1);

        % Refract: n_lens -> n_medium
        [dx3, dy3] = snell_2d(dx2, dy2, nx2, ny2, n_lens, n_medium);
        if isnan(dx3), continue; end

        % ---- Segment 3: exit ray extension ----
        x_end = x_hit2 + extend*dx3;
        y_end = y_hit2 + extend*dy3;

        % ---- Plot ----
        plot([x_start, x_hit1], [y0,     y_hit1], '-', 'Color', [col_in,   0.85], 'LineWidth', 0.9);
        plot([x_hit1,  x_hit2], [y_hit1, y_hit2], '-', 'Color', [col_lens, 0.85], 'LineWidth', 0.9);
        plot([x_hit2,  x_end ], [y_hit2, y_end ], '-', 'Color', [col_out,  0.85], 'LineWidth', 0.9);
    end
end

%% ==========================================================
%  LOCAL FUNCTIONS   (AsphericalLensIntegration.m lines 149-228)
%% ==========================================================

function A = normalize_asphere(A_du)
%NORMALIZE_ASPHERE  Accept either lens.asphere (…_du names) or the plain Adu names.
    A = struct();
    A.R            = pick(A_du, {'R_du', 'R'},                        Inf);
    A.k            = pick(A_du, {'k', 'K'},                           0);
    A.coef         = pick(A_du, {'coef_du', 'coef'},                  struct());
    A.CT           = pick(A_du, {'CT_du', 'CT'},                      []);
    A.half_aperture= pick(A_du, {'half_aperture_du', 'half_aperture'}, []);
    A.n            = pick(A_du, {'n', 'n_lens'},                      []);
    if isempty(A.CT) || isempty(A.half_aperture) || isempty(A.n)
        error('asphere_check_figure:input', 'A_du needs CT, half aperture and index (CT_du / half_aperture_du / n).');
    end
end

function v = pick(S, names, dflt)
    v = dflt;
    for i = 1:numel(names)
        if isfield(S, names{i}) && ~isempty(S.(names{i})), v = S.(names{i}); return; end
    end
end

function z = sag_of(r, R, K, coef)
% Aspheric sag - delegates to asphere_sag (same equation as the script's asph_sag,
% extended from A4..A10 to the D..M set the Edmund datasheets use).
    z = asphere_sag(r, R, K, coef);
end

function dz = dsag_of(r, R, K, coef)
% Derivative d(sag)/dr - second output of asphere_sag.
    [~, dz] = asphere_sag(r, R, K, coef);
end

function [nx, ny] = surf_normal(y, dsag_fn, orient)
% Unit surface normal at height y for surface x = x_vertex + sag(|y|).
%   orient = +1 -> normal points toward +x (right); -1 -> toward -x.
% Gradient of implicit F = x - x_vertex - sag(|y|):
%   dF/dx = 1,   dF/dy = -sign(y)*dsag(|y|)
    r  = abs(y);
    sg = sign(y);  if sg == 0, sg = 1; end
    ds = dsag_fn(r);
    raw = [1, -sg*ds];
    raw = orient * raw / norm(raw);
    nx = raw(1);  ny = raw(2);
end

function [dx_out, dy_out] = snell_2d(dx_in, dy_in, nx, ny, n1, n2)
% Vector Snell's law in 2D - same angle convention as StochasticRayTrace.m.
% (nx,ny): unit normal pointing INTO the incoming medium.
    ang_ray = atan2d(dy_in, dx_in);
    ang_n   = atan2d(ny, nx);
    th_in   = wrap180(ang_ray - ang_n);
    if abs(th_in) > 90
        ang_n = wrap180(ang_n + 180);
        th_in = wrap180(ang_ray - ang_n);
    end
    sin_out = (n1/n2) * sind(th_in);
    if abs(sin_out) > 1 + 1e-10
        dx_out = NaN; dy_out = NaN; return;   % TIR
    end
    th_out  = asind(max(min(sin_out, 1), -1));
    ang_out = wrap180(ang_n + th_out);
    dx_out  = cosd(ang_out);
    dy_out  = sind(ang_out);
end

function bracket = find_bracket(F, t_lo, t_hi)
% Find a sign-change bracket in F over [t_lo, t_hi] by dense sampling.
    bracket = [];
    ts = linspace(t_lo, t_hi, 500);
    Fs = arrayfun(F, ts);
    idx = find(diff(sign(Fs)) ~= 0, 1);
    if ~isempty(idx)
        bracket = ts([idx, idx+1]);
    end
end

function a = wrap180(a)
    a = mod(a + 180, 360) - 180;
end
