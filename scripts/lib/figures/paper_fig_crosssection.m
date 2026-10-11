function files = paper_fig_crosssection(lens, stack, cfg, base, out_dir, zoom)
%PAPER_FIG_CROSSSECTION  Paper Fig 1a (full view) / Fig 1b (zoom): rays through the lens.
%
%   files = paper_fig_crosssection(lens, stack, cfg, base, out_dir, zoom)
%
%   zoom = false -> Fig 1a, the whole lens with the collimated output;
%   zoom = true  -> Fig 1b, the inner elements around the emitter.
%
%   Ported from StochasticRayTrace.m (the whole "START LIVE PLOTTING" pass for one
%   style / one view), block by block:
%     - AUTO_MAX_ANGLE  -> trace/auto_max_angle
%     - ray pre-calculation and the EXTEND_TO_RIGHT extension to
%       x_end = xmax + extend_factor * x_span
%     - the heatmap pre-computation (near-field sin^2/r, ray-traced far field,
%       radial blend, spherical -> plane-wave oscillation morph)
%     - the fills / edges / tips (through draw_lens_filled)
%     - the ray lines, the collimated-output dart arrowheads, the emitter dot,
%       the view limits, the scale bar.
%
%   Everything adjustable comes from cfg.figures.paper, cfg.figures.style,
%   cfg.trace and cfg.emitter. Config lengths are millimetres; the geometry is in
%   design units, so they are divided by lens.mm_per_du here.
%
%   DEVIATIONS: rays are traced by trace/trace_rays (one shared tracer) instead of
%   the script's own first_hit_with_layer loop, and only rays with
%   trace.collected == true are drawn and extended (the script also extended the
%   rays that missed a surface, which it then drew); y_lim_base is taken from the
%   surface points rather than from a polyshape lens body (same value, no polyshape
%   dependency).

    if nargin < 6 || isempty(zoom), zoom = false; end
    P = cfg.figures.paper;
    S = style_preset(cfg.figures.style);
    mm_per_du = lens.mm_per_du;

    HEATMAP_FILL_ALPHA = 0.35;   % StochasticRayTrace: fills go translucent over the heatmap
    NEAR_FIELD_GAMMA   = 0.45;   % (dipole_w / r) .^ 0.45 - mild gamma for dynamic range
    ALPHA_RAMP_EXP     = 0.35;   % AlphaData = hm_norm .^ 0.35
    HEATMAP_SIGMA_PIX  = 2;      % Gaussian blur of the far field, in pixels
    BLEND_R0_FRAC      = 0.65;   % blend starts at 0.65 * r_lens_est ...
    BLEND_DR_FRAC      = 0.35;   % ... and is complete 0.35 * r_lens_est later
    SCALE_BAR_MM       = 10;     % regular view: 10 mm bar
    SCALE_BAR_MM_ZOOM  = 1;      % zoom view: 1 mm bar

    % --- geometry extents (StochasticRayTrace "Load lens geometry") -----------
    final_lens = lens.final_lens;
    L = min(lens.L, numel(final_lens));
    has_points = false(1, L);
    for j = 1:L
        has_points(j) = ~isempty(final_lens{j}) && size(final_lens{j}, 1) >= 2;
    end
    if ~any(has_points), error('paper_fig_crosssection:layers', 'No usable layers in lens.final_lens.'); end
    allX = [];  allY = [];
    for j = 1:L
        if ~has_points(j), continue; end
        allX = [allX; final_lens{j}(:,1)]; %#ok<AGROW>
        allY = [allY; final_lens{j}(:,2)]; %#ok<AGROW>
    end
    xmin   = min(allX);
    xmax   = max(allX);
    x_span = max(1e-9, xmax - xmin);
    ext_f  = 0.30;                                   % StochasticRayTrace x_end = xmax + 0.30*x_span
    if isfield(cfg, 'trace') && isfield(cfg.trace, 'extend_factor') && ~isempty(cfg.trace.extend_factor)
        ext_f = cfg.trace.extend_factor;
    end
    x_end      = xmax + ext_f * x_span;
    y_lim_base = max(abs(allY));
    origin     = lens.source_pos(:).';

    % --- fan limit: nominal, or the marginal collimating ray (AUTO_MAX_ANGLE) --
    T = base_trace_opts(cfg, lens);
    a_max = lens.nominal_max_angle;
    if isfield(cfg.trace, 'auto_max_angle') && cfg.trace.auto_max_angle
        [a_max, ok] = auto_max_angle(lens, stack, T, cfg.trace.auto_max_iters, cfg.trace.auto_collimation_tol_deg);
        if ~ok
            warning('paper_fig_crosssection:autoMaxAngle', ...
                'AUTO_MAX_ANGLE: the 90-deg probe ray failed - keeping the nominal fan limit %.2f deg.', a_max);
        else
            fprintf('  fan limit: %.3f deg (nominal %.2f deg)\n', a_max, lens.nominal_max_angle);
        end
    end

    % --- rays (uniform in angle over [0, a_max], deterministic) ---------------
    T.n_rays        = P.n_rays_drawn;
    T.sampling      = 'deterministic';
    T.min_angle_deg = 0;
    T.max_angle_deg = a_max;
    trace = trace_rays(lens, stack, T);
    N_rays = trace.n_rays;

    % EXTEND_TO_RIGHT: replace the tracer's fixed-length tail with the run to the
    % plot edge - rightward rays to x_end, backward (hole) rays to the left border.
    paths = trace.paths;
    for r = 1:N_rays
        if ~trace.collected(r), continue; end
        p = paths{r};
        if size(p, 1) < 2, continue; end
        P0 = p(end-1, :);
        Df = [cosd(trace.exit_angles(r)), sind(trace.exit_angles(r))];
        if abs(Df(1)) > 1e-12
            x_tgt = x_end;
            if Df(1) < 0, x_tgt = xmin - 0.15 * x_span; end
            t_ext = (x_tgt - P0(1)) / Df(1);
            if t_ext > 1e-9, p(end, :) = P0 + t_ext * Df; end
        end
        paths{r} = p;
    end

    % --- heatmap grid ---------------------------------------------------------
    HM = [];
    if P.heatmap.enable
        HM = heatmap_grid(paths, trace, cfg, lens, xmin, xmax, x_span, x_end, y_lim_base, ...
                          NEAR_FIELD_GAMMA, HEATMAP_SIGMA_PIX, BLEND_R0_FRAC, BLEND_DR_FRAC);
    end

    % --- figure ---------------------------------------------------------------
    fig = figure('Name', base, 'NumberTitle', 'off', 'Color', 'w', ...
                 'Units', 'centimeters', 'Position', [2 2 P.fig_size_cm(1) P.fig_size_cm(2)]);
    ax = axes('Parent', fig);
    hold(ax, 'on');  axis(ax, 'equal');
    set(ax, 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatio', [1 1 1]);

    % heatmap first so the lens geometry renders on top
    if ~isempty(HM)
        hm_norm = HM.grid / (max(HM.grid(:)) + eps);
        ih = imagesc(ax, HM.xc, HM.yc, hm_norm);
        n_cm = 256;                                   % white (null) -> yellow -> orange -> red
        cmap_r = [ones(n_cm,1), linspace(1,0,n_cm)', linspace(1,0,n_cm)'];
        colormap(ax, cmap_r);
        set(ih, 'AlphaData', hm_norm .^ ALPHA_RAMP_EXP);
        set(ax, 'YDir', 'normal');
    end

    % lens body: over the heatmap the fills go translucent so the lobes show through
    Sdraw = S;
    if ~isempty(HM), Sdraw.lensAlpha = S.lensAlpha * HEATMAP_FILL_ALPHA; end
    draw_lens_filled(ax, lens, Sdraw);

    % --- ray lines (upper + mirrored) ----------------------------------------
    for r = 1:N_rays
        if ~trace.collected(r), continue; end
        rpath = paths{r};
        if size(rpath, 1) < 2, continue; end
        plot(ax, rpath(:,1),  rpath(:,2), '-', 'Color', [S.rayColor, S.rayAlpha], 'LineWidth', S.rayLW);
        if max(abs(rpath(:,2))) > 1e-3
            plot(ax, rpath(:,1), -rpath(:,2), '-', 'Color', [S.rayColor, S.rayAlpha], 'LineWidth', S.rayLW);
        end
    end

    % --- collimated-output arrowheads (regular view only) ---------------------
    % Slim four-point "stealth dart": tip, two barbs, a concave notch on the back.
    if P.collimation_arrowheads.enable && ~zoom
        ah_len_c = P.collimation_arrowheads.frac * x_span;   % head length, data units
        ah_wid_c = 0.28 * ah_len_c;                          % half-width  (slim profile)
        ah_back  = 0.75;                                     % notch depth (1.0 = plain triangle)
        for r = 1:N_rays
            if ~trace.collected(r), continue; end
            rpath = paths{r};
            if size(rpath, 1) < 2, continue; end
            P1 = rpath(end-1, :);  P2 = rpath(end, :);
            dseg = P2 - P1;
            if dseg(1) <= 1e-9 || norm(dseg) < 1e-9, continue; end       % rightward rays only
            if P2(1) < xmax + 0.5 * (x_end - xmax), continue; end        % must reach the exit region
            sgn_list = 1;
            if max(abs(rpath(:,2))) > 1e-3, sgn_list = [1, -1]; end
            for sgn = sgn_list
                tip  = [P2(1), sgn*P2(2)];
                dh   = dseg / norm(dseg);  dh = [dh(1), sgn*dh(2)];
                perp = [-dh(2), dh(1)];
                bL   = tip - ah_len_c*dh + ah_wid_c*perp;
                bR   = tip - ah_len_c*dh - ah_wid_c*perp;
                bC   = tip - ah_back*ah_len_c*dh;
                fill(ax, [tip(1), bL(1), bC(1), bR(1)], [tip(2), bL(2), bC(2), bR(2)], ...
                     S.rayColor, 'EdgeColor', 'none');
            end
        end
    end

    % --- emitter (#E7633D, same hex as Fig 3) ---------------------------------
    plot(ax, origin(1), origin(2), 'o', 'MarkerFaceColor', S.emitterColor, ...
         'MarkerEdgeColor', 'none', 'MarkerSize', S.emitterSize);

    % --- view limits ----------------------------------------------------------
    if zoom
        zh = zoom_half_du(lens, P, L);
        xlim(ax, [-zh, zh]);   % the window is centred on the emitter at the origin
        ylim(ax, [-zh, zh]);
    else
        xlim(ax, [xmin - 0.1*x_span, x_end + 0.15*x_span]);
        % y from the CONTENT: the marginal ray sits on the rim, so pad by the
        % arrowhead half-width or its head would be clipped.
        y_ray_max = 0;
        for r = 1:N_rays
            if ~trace.collected(r), continue; end
            if size(paths{r}, 1) >= 2
                y_ray_max = max(y_ray_max, max(abs(paths{r}(:,2))));
            end
        end
        y_lim_plot = max(y_lim_base, y_ray_max + 0.60 * P.collimation_arrowheads.frac * x_span);
        ylim(ax, [-y_lim_plot, y_lim_plot]);
    end
    grid(ax, 'off');
    set(ax, 'DataAspectRatio', [1 1 1]);
    axis(ax, 'off');

    % --- scale bar (bottom-left, data coordinates) ----------------------------
    if P.scale_bar
        if zoom
            sb_mm = SCALE_BAR_MM_ZOOM;
        else
            sb_mm = SCALE_BAR_MM;
        end
        sb_len = sb_mm / mm_per_du;                  % mm -> design units
        xl = xlim(ax);  yl = ylim(ax);
        sb_x = xl(1) + 0.04*(xl(2)-xl(1));
        sb_y = yl(1) + 0.04*(yl(2)-yl(1));
        sb_h = 0.010*(yl(2)-yl(1));                  % end-cap height
        % The bar is drawn UNLABELED, as in the source (it builds a '10 mm' / '1 mm'
        % string and never prints it) - the length belongs in the figure caption.
        line(ax, [sb_x, sb_x+sb_len],       [sb_y, sb_y],            'Color', 'k', 'LineWidth', 1.5);
        line(ax, [sb_x, sb_x],              [sb_y-sb_h, sb_y+sb_h],  'Color', 'k', 'LineWidth', 1.5);
        line(ax, [sb_x+sb_len, sb_x+sb_len],[sb_y-sb_h, sb_y+sb_h],  'Color', 'k', 'LineWidth', 1.5);
        fprintf('  scale bar: %g mm (%.3f du), unlabeled - state the length in the caption\n', sb_mm, sb_len);
    end

    set(fig, 'Renderer', 'painters');
    drawnow;
    files = save_fig(fig, base, out_dir, P.formats, P.png_dpi, true);
end

% ---------------------------------------------------------------------------
function T = base_trace_opts(cfg, lens)
%BASE_TRACE_OPTS  cfg.trace -> the trace_rays option struct used by the panels.
    T = struct();
    T.max_angle_deg     = lens.nominal_max_angle;
    T.min_angle_deg     = 0;
    T.angle_epsilon_deg = cfg.trace.angle_epsilon_deg;
    T.segment_overshoot = cfg.trace.segment_overshoot;
    T.sampling          = 'deterministic';
    T.seed              = cfg.trace.seed;
    T.n_rays            = cfg.figures.paper.n_rays_drawn;
    T.extend_len        = cfg.figures.paper.ray_length_mm / lens.mm_per_du;   % mm -> du
end

% ---------------------------------------------------------------------------
function zh = zoom_half_du(lens, P, L)
%ZOOM_HALF_DU  Zoom half-window in design units.
%   zoom_half_mm when the config sets one; otherwise the StochasticRayTrace
%   auto window: the square, centred on the source, that contains the first
%   zoom_n_elements elements (surface points AND their closure tips) + 8 %.
    if isfield(P, 'zoom_half_mm') && ~isempty(P.zoom_half_mm)
        zh = P.zoom_half_mm / lens.mm_per_du;
        return;
    end
    ZOOM_MARGIN = 1.08;                    % 8 % margin so nothing is cut at the frame
    final_lens = lens.final_lens;
    zext = 0;
    for j = 1:min(2*P.zoom_n_elements, L)
        if isempty(final_lens{j}), continue; end
        zext = max([zext; abs(final_lens{j}(:,1)); abs(final_lens{j}(:,2))]);
    end
    for e = 1:P.zoom_n_elements
        li = 2*e - 1;  lo = 2*e;
        if lo > L || isempty(final_lens{li}) || isempty(final_lens{lo}), continue; end
        if size(final_lens{li},1) < 2 || size(final_lens{lo},1) < 2, continue; end
        [tip, ~, pointy] = crescent_outline(final_lens{li}, final_lens{lo}, e);
        if pointy, zext = max(zext, max(abs(tip))); end
    end
    zh = ZOOM_MARGIN * zext;
    fprintf('  auto zoom window: +/- %.2f du (frames %d inner elements)\n', zh, P.zoom_n_elements);
end

% ---------------------------------------------------------------------------
function HM = heatmap_grid(paths, trace, cfg, lens, xmin, xmax, x_span, x_end, y_lim_base, ...
                           near_gamma, sigma_pix, blend_r0, blend_dr)
%HEATMAP_GRID  Dipole intensity map behind the rays (StochasticRayTrace block 1b).
%   Analytic near field (dipole weight / r, gamma-compressed) blended radially into
%   the ray-traced far field of the exit segments, then multiplied by an
%   oscillating factor that morphs cos(kr) rings into cos(kx) plane-wave stripes.
    P = cfg.figures.paper;
    hm_res   = P.heatmap.res;
    lambda   = P.heatmap.lambda_display_mm / lens.mm_per_du;    % mm -> design units
    origin   = lens.source_pos(:).';
    hm_x_min = xmin - 0.1*x_span;
    hm_x_max = x_end + 0.15*x_span;
    hm_y_min = -y_lim_base;
    hm_y_max =  y_lim_base;
    hm_xe    = linspace(hm_x_min, hm_x_max, hm_res+1);
    hm_ye    = linspace(hm_y_min, hm_y_max, hm_res+1);
    hm_xc    = (hm_xe(1:end-1) + hm_xe(2:end)) / 2;
    hm_yc    = (hm_ye(1:end-1) + hm_ye(2:end)) / 2;

    % dipole emission weights: sin^2 (axis 'x') or cos^2 (axis 'y')
    use_cos2 = 0;
    if isfield(cfg, 'emitter') && isfield(cfg.emitter, 'dipole_axis') && strcmpi(cfg.emitter.dipole_axis, 'y')
        use_cos2 = 1;
    end
    alpha0_rad  = trace.alphas0(:) * pi / 180;
    ray_weights = (1-use_cos2)*sin(alpha0_rad).^2 + use_cos2*cos(alpha0_rad).^2;

    % === NEAR FIELD: analytic dipole intensity sin^2(alpha)/r =================
    [X_hm, Y_hm] = meshgrid(hm_xc, hm_yc);
    dx_hm    = X_hm - origin(1);
    dy_hm    = Y_hm - origin(2);
    r_hm     = sqrt(dx_hm.^2 + dy_hm.^2) + 1e-9;
    alpha_hm = atan2(dy_hm, dx_hm);
    dipole_w = (1-use_cos2)*sin(alpha_hm).^2 + use_cos2*cos(alpha_hm).^2;
    r_cell     = hm_xe(2) - hm_xe(1);            % cap r at one cell: no source singularity
    near_field = (dipole_w ./ max(r_hm, r_cell)) .^ near_gamma;
    near_field = near_field / (max(near_field(:)) + eps);

    % === FAR FIELD: ray-traced exit segments, Gaussian-blurred ===============
    k_r_hm = ceil(3*sigma_pix);
    [kx_k, ky_k] = meshgrid(-k_r_hm:k_r_hm, -k_r_hm:k_r_hm);
    kern = exp(-(kx_k.^2 + ky_k.^2) / (2*sigma_pix^2));
    kern = kern / sum(kern(:));

    far_field = zeros(hm_res, hm_res);
    for r = 1:numel(paths)
        rpath = paths{r};
        if size(rpath,1) < 2, continue; end
        do_mirror_r = max(abs(rpath(:,2))) > 1e-3;
        w   = ray_weights(r);
        P1r = rpath(end-1,:);  P2r = rpath(end,:);
        seg_len = hypot(P2r(1)-P1r(1), P2r(2)-P1r(2));
        n_pts   = max(3, ceil(600 * seg_len / (hm_x_max - hm_x_min)));
        ts  = linspace(0, 1, n_pts);
        xs  = P1r(1) + ts*(P2r(1)-P1r(1));
        ys  = P1r(2) + ts*(P2r(2)-P1r(2));
        ws  = (w / n_pts) * ones(1, n_pts);
        xi_b = bin_index(xs, hm_xe);
        yi_b = bin_index(ys, hm_ye);
        val  = xi_b>=1 & xi_b<=hm_res & yi_b>=1 & yi_b<=hm_res;
        if any(val)
            subs = [yi_b(val)', xi_b(val)'];
            far_field = far_field + accumarray(subs, ws(val)', [hm_res hm_res], @sum, 0);
        end
        if do_mirror_r
            yi_bm = bin_index(-ys, hm_ye);
            valm  = xi_b>=1 & xi_b<=hm_res & yi_bm>=1 & yi_bm<=hm_res;
            if any(valm)
                subsm = [yi_bm(valm)', xi_b(valm)'];
                far_field = far_field + accumarray(subsm, ws(valm)', [hm_res hm_res], @sum, 0);
            end
        end
    end
    far_field = conv2(far_field, kern, 'same');
    far_field = far_field / (max(far_field(:)) + eps);

    % === BLEND: analytic near field inside the lens, traced field outside =====
    r_lens_est = max(y_lim_base, xmax - origin(1));
    blend      = max(0, min(1, (r_hm - blend_r0*r_lens_est) / (blend_dr*r_lens_est)));
    heat_grid  = (1-blend) .* near_field + blend .* far_field;

    % === OSCILLATION: spherical cos(kr) -> plane-wave cos(kx) =================
    k_wave      = 2*pi / lambda;
    x_from_src  = X_hm - origin(1);
    x_lens_exit = max(xmax - origin(1), 1e-9);
    blend_wave  = max(0, min(1, x_from_src ./ x_lens_exit));   % 0 at the source, 1 at the rim
    osc_sph     = cos(k_wave * r_hm);
    osc_plane   = cos(k_wave * x_from_src);
    osc         = (1-blend_wave) .* osc_sph + blend_wave .* osc_plane;
    heat_grid   = heat_grid .* ((1 + osc) / 2);

    HM = struct('grid', heat_grid, 'xc', hm_xc, 'yc', hm_yc);
end

% ---------------------------------------------------------------------------
function idx = bin_index(v, edges)
%BIN_INDEX  Bin index of v in UNIFORM edges - the [~, idx] = histc(v, edges) result.
%   (histc is deprecated in MATLAB and gone in newer Octave; the edges here are a
%   linspace, so the closed-form index is exact and matches histc value for value:
%   out-of-range -> 0, the top edge -> numel(edges). Verified against histc.)
    e1 = edges(1);  dx = edges(2) - edges(1);  n = numel(edges);
    idx = floor((v - e1) / dx) + 1;
    idx(v == edges(end)) = n;
    idx(v < e1 | v > edges(end)) = 0;
end
