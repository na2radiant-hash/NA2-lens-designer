function S = fit_sphere(lens_mat, k, r_max_mm)
%FIT_SPHERE  Least-squares on-axis sphere through one surface of a built lens (for design.spherical_surfaces).
%
%   S = fit_sphere(lens_mat, k, r_max_mm)
%     lens_mat   path of a lens.mat written by LensConstructionGradual (fields final_lens,
%                mm_per_du), or the loaded struct itself, or a lens struct with those fields
%     k          surface index into final_lens (1 = cavity, 2 = outer surface of element 1, ...)
%     r_max_mm   optional cap: fit only the rows from the vertex out to the first row whose
%                radius exceeds r_max_mm (physical mm). Omitted or [] = the whole polyline.
%
%   The polyline final_lens{k} is [x r] in design units, vertex -> tip, upper half. The sphere
%   is constrained to have its center on the optical axis, so it is x = c +/- sqrt(R^2 - r^2):
%     1. algebraic fit  x^2 + r^2 = 2 c x + K  (K = R^2 - c^2), a linear least-squares problem
%        that gives a robust start without an initial guess;
%     2. 10 Gauss-Newton steps on the geometric residual  d_i = |p_i - center| - R, which is
%        what the design rays actually see (the algebraic fit weights far points too much).
%   Printed: center_z_du and radius_du (the two numbers design.spherical_surfaces takes),
%   both sphere vertices c + R and c - R with the one that matches the polyline vertex
%   marked, the same in mm, the max and RMS residual in mm (max with its row), and a
%   ready-to-paste JSON item for design.spherical_surfaces. The same numbers come back in S.
%
%   Why "from the vertex out" for the cap: the outer surfaces of this omnidirectional lens
%   wrap around the emitter, so r rises to a maximum and then falls again towards the tip.
%   Rows on the far side with a small r are not part of the cap; only the contiguous run
%   starting at the vertex is used, and the tool says how many far-side rows it skipped.
%
%   Standalone: needs nothing on the path (only load and core MATLAB/Octave).
%
%   Examples:
%     fit_sphere('.../RevB_2026-09-16/lens.mat', 2)          % whole outer surface of element 1
%     S = fit_sphere('.../lens.mat', 2, 4.5);                 % Isuzu cap out to r = 4.5 mm
%     fit_sphere(load('.../lens.mat'), 1)                     % cavity from the loaded struct

    if nargin < 2 || isempty(k)
        error('fit_sphere:args', 'usage: S = fit_sphere(lens_mat, k, r_max_mm)');
    end
    if nargin < 3, r_max_mm = []; end
    if ~isempty(r_max_mm) && (~isnumeric(r_max_mm) || ~isscalar(r_max_mm) || ~(r_max_mm > 0))
        error('fit_sphere:args', 'r_max_mm must be a positive scalar (mm) or []');
    end
    if ~isnumeric(k) || ~isscalar(k) || k ~= round(k) || k < 1
        error('fit_sphere:args', 'k must be a positive integer surface index');
    end

    %% ---- load ------------------------------------------------------------------
    if ischar(lens_mat)
        src = lens_mat;
        if exist(lens_mat, 'file') ~= 2
            error('fit_sphere:nofile', 'lens.mat not found: %s', lens_mat);
        end
        D = load(lens_mat);
    elseif isstruct(lens_mat)
        src = '<lens struct>';
        D = lens_mat;
    else
        error('fit_sphere:args', 'lens_mat must be a path (char) or a struct with final_lens');
    end
    if ~isfield(D, 'final_lens') || ~iscell(D.final_lens)
        error('fit_sphere:fields', '%s has no final_lens cell', src);
    end
    FL = D.final_lens;
    mm_warn = '';
    if isfield(D, 'mm_per_du') && ~isempty(D.mm_per_du)
        mm = double(D.mm_per_du);
    else
        % Legacy .mat files (before the port) carry no scale; the inner vertex is at
        % 1 du = WD_mm by construction, so without WD the mm numbers are just du.
        mm = 1;
        mm_warn = 'WARN: no mm_per_du in the file, mm values below are design units';
    end
    if k > numel(FL) || isempty(FL{k})
        error('fit_sphere:surface', 'surface %d: %s has %d layers and layer %d is %s', ...
              k, src, numel(FL), k, tern(k <= numel(FL), 'empty', 'absent'));
    end
    P = double(FL{k});
    if size(P, 2) < 2
        error('fit_sphere:surface', 'surface %d: expected [x r] rows, got %s', k, mat2str(size(P)));
    end
    P = P(:, 1:2);
    n_total = size(P, 1);

    %% ---- rows to fit -------------------------------------------------------------
    n_skipped_far = 0;
    if isempty(r_max_mm)
        n_use = n_total;
        cap_note = 'no cap, whole polyline';
    else
        i_over = find(P(:, 2) * mm > r_max_mm, 1, 'first');
        if isempty(i_over)
            n_use = n_total;
            cap_note = sprintf('r_max %.4f mm never reached, whole polyline', r_max_mm);
        else
            n_use = i_over - 1;
            % rows past the cap edge that come back under r_max_mm sit on the far side
            n_skipped_far = sum(P(i_over:end, 2) * mm <= r_max_mm);
            cap_note = sprintf('from the vertex out to r <= %.4f mm', r_max_mm);
        end
    end
    if n_use < 3
        error('fit_sphere:rows', 'surface %d: only %d row(s) inside r_max_mm = %g, need at least 3', ...
              k, n_use, r_max_mm);
    end
    x = P(1:n_use, 1);  r = P(1:n_use, 2);

    %% ---- 1. algebraic fit: x^2 + r^2 = 2 c x + K -------------------------------
    A = [2 * x, ones(n_use, 1)];
    b = x.^2 + r.^2;
    q = A \ b;
    c0 = q(1);  K0 = q(2);
    R0 = sqrt(max(K0 + c0^2, 0));
    if ~(R0 > 0)
        error('fit_sphere:degenerate', 'surface %d: the algebraic fit gave no sphere (all rows on the axis?)', k);
    end

    %% ---- 2. Gauss-Newton on the geometric residual dist - R ---------------------
    c = c0;  R = R0;  n_iter = 10;  last_step = NaN;
    for it = 1:n_iter
        dx   = x - c;
        dist = sqrt(dx.^2 + r.^2);
        dist = max(dist, eps);                       % a row on the center has no direction
        d    = dist - R;
        J    = [-dx ./ dist, -ones(n_use, 1)];       % d(d_i)/dc, d(d_i)/dR
        step = (J' * J) \ (J' * d);
        c = c - step(1);  R = R - step(2);
        last_step = max(abs(step));
    end
    dx   = x - c;
    dist = sqrt(dx.^2 + r.^2);
    resid_du = dist - R;
    [max_abs_du, i_max] = max(abs(resid_du));
    rms_du = sqrt(mean(resid_du.^2));

    %% ---- vertex bookkeeping ------------------------------------------------------
    v_plus = c + R;  v_minus = c - R;
    x_vertex_poly = P(1, 1);
    if abs(v_plus - x_vertex_poly) <= abs(v_minus - x_vertex_poly)
        vertex_x = v_plus;  vsign = 1;  vertex_lbl = 'c + R';
    else
        vertex_x = v_minus; vsign = -1; vertex_lbl = 'c - R';
    end
    % half angle of the used arc as seen from the center, measured from the vertex direction
    theta_max_deg = atan2(r(end), vsign * (x(end) - c)) * 180 / pi;
    json = sprintf('{"surface": %d, "center_z_du": %.6f, "radius_du": %.6f}', k, c, R);

    %% ---- print -----------------------------------------------------------------
    fprintf('fit_sphere: surface %d of %s\n', k, src);
    fprintf('  scale            : mm_per_du = %.6f\n', mm);
    if ~isempty(mm_warn), fprintf('  %s\n', mm_warn); end
    fprintf('  rows used        : %d of %d (%s)\n', n_use, n_total, cap_note);
    if n_skipped_far > 0
        fprintf('                     %d far-side row(s) with r <= r_max (surface wraps around) skipped\n', n_skipped_far);
    end
    fprintf('  rows span        : x = [%.4f, %.4f] mm, r = [%.4f, %.4f] mm\n', ...
            min(x) * mm, max(x) * mm, min(r) * mm, max(r) * mm);
    fprintf('  algebraic start  : c = %.6f du, R = %.6f du\n', c0, R0);
    fprintf('  Gauss-Newton     : %d iterations, last step %.2e du\n', n_iter, last_step);
    fprintf('  center_z_du      : %.6f\n', c);
    fprintf('  radius_du        : %.6f\n', R);
    fprintf('  vertex x (du)    : c + R = %.6f, c - R = %.6f  (polyline vertex at x = %.6f, %s is %.2e du away)\n', ...
            v_plus, v_minus, x_vertex_poly, vertex_lbl, abs(vertex_x - x_vertex_poly));
    fprintf('  center x (mm)    : %.4f\n', c * mm);
    fprintf('  radius (mm)      : %.4f\n', R * mm);
    fprintf('  vertex x (mm)    : %.4f  (%s)\n', vertex_x * mm, vertex_lbl);
    fprintf('  arc used         : last row at r = %.4f mm, %.2f deg from the vertex as seen from the center\n', ...
            r(end) * mm, theta_max_deg);
    fprintf('  residual (mm)    : max |dist - R| = %.3e at row %d (x = %.4f, r = %.4f mm), RMS = %.3e\n', ...
            max_abs_du * mm, i_max, x(i_max) * mm, r(i_max) * mm, rms_du * mm);
    fprintf('  JSON             : %s\n', json);

    %% ---- return ------------------------------------------------------------------
    S = struct('surface', k, 'source', src, 'mm_per_du', mm, ...
               'r_max_mm', tern(isempty(r_max_mm), Inf, r_max_mm), ...
               'n_rows_used', n_use, 'n_rows_total', n_total, 'n_rows_skipped_far', n_skipped_far, ...
               'center_z_du', c, 'radius_du', R, ...
               'vertex_x_du', vertex_x, 'vertex_x_du_both', [v_plus, v_minus], 'vertex_side', vertex_lbl, ...
               'center_z_mm', c * mm, 'radius_mm', R * mm, 'vertex_x_mm', vertex_x * mm, ...
               'theta_max_deg', theta_max_deg, ...
               'max_residual_mm', max_abs_du * mm, 'max_residual_row', i_max, 'rms_residual_mm', rms_du * mm, ...
               'residual_mm', resid_du * mm, ...
               'algebraic_center_z_du', c0, 'algebraic_radius_du', R0, 'gn_last_step_du', last_step, ...
               'json', json);
end

function v = tern(cond, a, b)
%TERN  Inline if/else so the messages above stay on one line.
    if cond, v = a; else, v = b; end
end
