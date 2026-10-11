function files = paper_fig_raytrace(lens, stack, cfg, base2d, base3d, out_dir)
%PAPER_FIG_RAYTRACE  Paper Fig 1e (2-D rays only) and Fig 1f (3-D revolved rays).
%
%   files = paper_fig_raytrace(lens, stack, cfg, base2d, base3d, out_dir)
%
%   An EMPTY base skips that panel, so the two figures.paper.panels switches
%   (fig1e / fig1f) can be set independently.
%
%   Fig 1e - Tracing3D.m section 5b ("Rays only (no lens)"): the traced rays and
%   their mirrored copies, with filled arrowheads on chosen segments.
%   Fig 1f - Tracing3D.m section 6 + na2_fig_raytrace.m raytrace3d(): every 2-D ray
%   revolved into rays_3d.n_copies azimuthal copies, a cone arrowhead on the exit
%   segment, optional grey tip circles, the emitter sphere and the direction triad
%   (data +X = label z, +Y = x, +Z = y).
%
%   Angles come from cfg.figures.paper.rays_3d.angles_deg and are clipped to the
%   lens's nominal fan limit with a warning (the shipped list ends at 178 deg,
%   outside a 162.5 deg fan). Rays are traced by trace/trace_rays.
%
%   DEVIATIONS
%     - cone sizes are scene-relative (na2_fig_raytrace: 0.040 / 0.025 of the lens
%       x-span, times rays_3d.arrow_scale) instead of Tracing3D's fixed 9 / 6 mm,
%       so the panel works for any lens size;
%     - the arrowhead segment of Fig 1f is numel(stack) + 1, i.e. the exit segment
%       for whatever surface stack this design has (na2 hard-coded layers_count + 1);
%     - the per-ray 2-D arrow-segment lists are Tracing3D's, cycled when more angles
%       are configured than the four the original had;
%     - the 2-D panel uses figures.paper.fig_size_cm (Tracing3D had a fixed 22x22 cm
%       window); the 3-D panel keeps the original 26x18 cm.

    if nargin < 4, base2d = ''; end
    if nargin < 5, base3d = ''; end
    files = {};
    P = cfg.figures.paper;
    R = P.rays_3d;
    S = style_preset(cfg.figures.style);

    RAY_COLOR      = [1.00 0.15 0.00];   % Tracing3D RAY_COLORS (all four rays red)
    RAY_ALPHA      = 0.85;               % RAY_ALPHA / RAY_ALPHA_3D
    RAY_LW_2D      = 1.5;
    RAY_LW_3D      = 1.2;
    ARROW_LEN_MM   = 7.0;                % Tracing3D arrow_len (2-D head, tip to base)
    ARROW_W_MM     = 2.6;                % Tracing3D arrow_w   (2-D head half-width)
    ARROW_MIN_FRAC = 1.15;               % skip a head when the segment < 1.15 * arrow_len
    MIRROR_MIN_MM  = 0.5;                % |y| below this = an on-axis ray, drawn once
    CONE_LEN_FRAC  = 0.040;              % na2_fig_raytrace: cone depth  / x-span
    CONE_RAD_FRAC  = 0.025;              % na2_fig_raytrace: cone radius / x-span
    N_CONE         = 10;                 % facets of the 3-D cone
    CIRCLE_COLOR   = [0.75 0.75 0.75];   % tip circles
    AZ_VIEW        = -30;
    EL_VIEW        = 18;
    CAM_VIEW_ANGLE = 9;
    FIG3D_SIZE_CM  = [26 18];            % Tracing3D 3-D window
    TRIAD_ON       = true;               % Tracing3D TRIAD_ON
    ARROW_SEGS_DEFAULT = {[4 6 8 9], [4 6 8 9], [3 4 5 6 7 8 9], [3 4 5 6 7 8 9]};

    % --- geometry extent ------------------------------------------------------
    final_lens = lens.final_lens;
    L = min(lens.L, numel(final_lens));
    allX = [];
    for j = 1:L
        if isempty(final_lens{j}) || size(final_lens{j},1) < 2, continue; end
        allX = [allX; final_lens{j}(:,1)]; %#ok<AGROW>
    end
    if isempty(allX), error('paper_fig_raytrace:layers', 'No usable layers in lens.final_lens.'); end
    xspan = max(1e-9, max(allX) - min(allX));

    % --- emission angles ------------------------------------------------------
    ang = R.angles_deg(:);
    eps_ang = 0;
    if isfield(cfg, 'trace') && isfield(cfg.trace, 'angle_epsilon_deg') && ~isempty(cfg.trace.angle_epsilon_deg)
        eps_ang = cfg.trace.angle_epsilon_deg;
    end
    a_lim = lens.nominal_max_angle - eps_ang;
    over  = ang > a_lim;
    if any(over)
        warning('paper_fig_raytrace:clip', ...
            'Ray angles [%s] exceed the lens fan limit (%.2f deg) and were clipped.', ...
            strtrim(sprintf('%.4g ', ang(over))), lens.nominal_max_angle);
        ang(over) = a_lim;
    end

    % --- trace ----------------------------------------------------------------
    T = struct('alphas0', ang, 'extend_len', P.ray_length_mm / lens.mm_per_du);
    if isfield(cfg, 'trace') && isfield(cfg.trace, 'segment_overshoot') && ~isempty(cfg.trace.segment_overshoot)
        T.segment_overshoot = cfg.trace.segment_overshoot;
    end
    trace = trace_rays(lens, stack, T);
    paths = trace.paths;

    % --- Fig 1e: 2-D rays only ------------------------------------------------
    if ~isempty(base2d)
        arrow_len = ARROW_LEN_MM / lens.mm_per_du;      % mm -> design units
        arrow_w   = ARROW_W_MM   / lens.mm_per_du;
        y_mirror  = MIRROR_MIN_MM / lens.mm_per_du;

        fig = figure('Name', base2d, 'NumberTitle', 'off', 'Color', 'w', ...
                     'Units', 'centimeters', 'Position', [2 2 P.fig_size_cm(1) P.fig_size_cm(2)]);
        ax = axes('Parent', fig);  hold(ax, 'on');

        % rays (top + mirrored bottom)
        for ri = 1:numel(paths)
            path = paths{ri};
            if size(path,1) < 2, continue; end
            plot(ax, path(:,1),  path(:,2), '-', 'Color', [RAY_COLOR, RAY_ALPHA], 'LineWidth', RAY_LW_2D);
            if max(abs(path(:,2))) > y_mirror
                plot(ax, path(:,1), -path(:,2), '-', 'Color', [RAY_COLOR, RAY_ALPHA], 'LineWidth', RAY_LW_2D);
            end
        end
        % arrowheads (top + mirrored bottom), tip AT the segment end
        for ri = 1:numel(paths)
            path = paths{ri};
            if size(path,1) < 2, continue; end
            segs = ARROW_SEGS_DEFAULT{mod(ri-1, numel(ARROW_SEGS_DEFAULT)) + 1};
            for k = segs
                if k+1 > size(path,1), continue; end
                sgn_list = 1;
                if max(abs(path(:,2))) > y_mirror, sgn_list = [1, -1]; end
                for sgn = sgn_list
                    P1 = [path(k,1),   sgn*path(k,2)];
                    P2 = [path(k+1,1), sgn*path(k+1,2)];
                    d  = P2 - P1;
                    if norm(d) < ARROW_MIN_FRAC*arrow_len, continue; end
                    dhat = d / norm(d);  perp = [-dhat(2), dhat(1)];
                    bL = P2 - arrow_len*dhat + arrow_w*perp;
                    bR = P2 - arrow_len*dhat - arrow_w*perp;
                    fill(ax, [P2(1),bL(1),bR(1)], [P2(2),bL(2),bR(2)], RAY_COLOR, ...
                         'EdgeColor', 'none', 'FaceAlpha', RAY_ALPHA);
                end
            end
        end
        src = lens.source_pos(:).';
        plot(ax, src(1), src(2), 'o', 'MarkerFaceColor', S.emitterColor, ...
             'MarkerEdgeColor', 'none', 'MarkerSize', S.emitterSize);
        axis(ax, 'equal');  axis(ax, 'off');
        set(fig, 'Renderer', 'painters');
        drawnow;
        files = [files, save_fig(fig, base2d, out_dir, P.formats, P.png_dpi, true)];
    end

    % --- Fig 1f: 3-D revolved rays -------------------------------------------
    if ~isempty(base3d)
        N_c   = R.n_copies;
        phi_c = linspace(0, 360, N_c+1);  phi_c(end) = [];
        arrow_seg_3d = numel(stack) + 1;                       % the exit (extension) segment
        arrow_len_3d = R.arrow_scale * CONE_LEN_FRAC * xspan;
        arrow_w_3d   = R.arrow_scale * CONE_RAD_FRAC * xspan;
        src = lens.source_pos(:).';

        fig3 = figure('Name', base3d, 'NumberTitle', 'off', 'Color', 'w', ...
                      'Units', 'centimeters', 'Position', [2 2 FIG3D_SIZE_CM(1) FIG3D_SIZE_CM(2)]);
        ax3 = axes('Parent', fig3);  hold(ax3, 'on');  grid(ax3, 'on');
        set(ax3, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'ZColor', 'k', ...
                 'GridColor', [0.75 0.75 0.75], 'GridAlpha', 0.5, ...
                 'GridLineStyle', ':', 'FontSize', 10, 'FontName', 'Times New Roman', ...
                 'LineWidth', 0.8, 'TickDir', 'out', 'Box', 'off', ...
                 'XTickLabel', {}, 'YTickLabel', {}, 'ZTickLabel', {}, ...
                 'TickLength', [0 0]);       % hide tick MARKS only - axis lines + grid stay
        view(ax3, AZ_VIEW, EL_VIEW);
        set(ax3, 'CameraViewAngle', CAM_VIEW_ANGLE);

        % rays and cones
        for ri = 1:numel(paths)
            path = paths{ri};
            if size(path,1) < 2, continue; end
            x2d = path(:,1);  r2d = abs(path(:,2));  k3 = arrow_seg_3d;
            for ph_deg = phi_c
                Y3 = r2d * cosd(ph_deg);
                Z3 = r2d * sind(ph_deg);
                plot3(ax3, x2d, Y3, Z3, '-', 'Color', [RAY_COLOR, RAY_ALPHA], 'LineWidth', RAY_LW_3D);
                if k3+1 <= numel(x2d)
                    dx = x2d(k3+1) - x2d(k3);
                    dr = r2d(k3+1) - r2d(k3);
                    d3 = [dx, dr*cosd(ph_deg), dr*sind(ph_deg)];
                    if norm(d3) > 1e-9
                        dhat3 = d3 / norm(d3);
                        e1 = [-dr, dx*cosd(ph_deg), dx*sind(ph_deg)];
                        if norm(e1) < 1e-9, e1 = [0, -sind(ph_deg), cosd(ph_deg)]; end
                        e1 = e1 / norm(e1);
                        e2 = cross(dhat3, e1);
                        if norm(e2) > 1e-9
                            e2 = e2 / norm(e2);
                        else
                            e2 = cross(dhat3, [1,0,0]);  e2 = e2 / norm(e2);
                        end
                        tip3   = [x2d(k3+1), r2d(k3+1)*cosd(ph_deg), r2d(k3+1)*sind(ph_deg)];
                        base_c = tip3 - arrow_len_3d*dhat3;
                        tc = linspace(0, 2*pi, N_CONE+1);  tc(end) = [];
                        for ci = 1:N_CONE
                            ni  = mod(ci, N_CONE) + 1;
                            bp1 = base_c + arrow_w_3d*(cos(tc(ci))*e1 + sin(tc(ci))*e2);
                            bp2 = base_c + arrow_w_3d*(cos(tc(ni))*e1 + sin(tc(ni))*e2);
                            patch(ax3, [tip3(1),bp1(1),bp2(1)], ...
                                       [tip3(2),bp1(2),bp2(2)], ...
                                       [tip3(3),bp1(3),bp2(3)], ...
                                  RAY_COLOR, 'EdgeColor', 'none', 'FaceAlpha', RAY_ALPHA);
                        end
                    end
                end
            end
        end

        % circles connecting the arrowhead tips (one per ray)
        if R.add_circles
            for ri = 1:numel(paths)
                path = paths{ri};
                if size(path,1) < 2, continue; end
                x2d = path(:,1);  r2d = abs(path(:,2));  k3 = arrow_seg_3d;
                if k3+1 > numel(x2d), continue; end
                r_tip = r2d(k3+1);  x_tip = x2d(k3+1);
                if r_tip < 1e-9, continue; end                 % skip the on-axis ray
                th_c = linspace(0, 2*pi, 180);
                plot3(ax3, x_tip*ones(1,180), r_tip*cos(th_c), r_tip*sin(th_c), '-', ...
                      'Color', CIRCLE_COLOR, 'LineWidth', 1.5);
            end
        end

        % emitter sphere (#E7633D, the Fig-3 ball)
        [sx, sy, sz] = sphere(24);
        sphere_r = R.emitter_radius_du;
        surf(ax3, src(1)+sphere_r*sx, src(2)+sphere_r*sy, sphere_r*sz, ...
             'FaceColor', S.emitterColor, 'EdgeColor', 'none', 'FaceAlpha', 1.0, ...
             'AmbientStrength', 0.4, 'DiffuseStrength', 0.7, 'SpecularStrength', 0.5);

        % axis limits
        axis(ax3, 'tight');  drawnow;
        xl = xlim(ax3);  yl = ylim(ax3);  zl = zlim(ax3);
        xlim(ax3, [xl(1)-0.05*(xl(2)-xl(1)), xl(2)+0.05*(xl(2)-xl(1))]);
        ylim(ax3, [yl(1)-0.15*(yl(2)-yl(1)), yl(2)+0.15*(yl(2)-yl(1))]);
        zlim(ax3, [zl(1)-0.15*(zl(2)-zl(1)), zl(2)+0.15*(zl(2)-zl(1))]);

        % direction triad, drawn AFTER the limits are final so it shares the camera
        if TRIAD_ON
            xl = xlim(ax3);  yl = ylim(ax3);  zl = zlim(ax3);
            tr_len = 0.10 * (xl(2)-xl(1));
            tr_o   = [xl(1)+0.03*(xl(2)-xl(1)), ...
                      yl(1)+0.08*(yl(2)-yl(1)), ...
                      zl(1)+0.06*(zl(2)-zl(1))];
            tr_col = [0.15 0.15 0.15];
            quiver3(ax3, tr_o(1),tr_o(2),tr_o(3), tr_len,0,0, 0, ...
                    'Color', tr_col, 'LineWidth', 1.3, 'MaxHeadSize', 0.8);   % label z (data +X)
            quiver3(ax3, tr_o(1),tr_o(2),tr_o(3), 0,tr_len,0, 0, ...
                    'Color', tr_col, 'LineWidth', 1.3, 'MaxHeadSize', 0.8);   % label x (data +Y)
            quiver3(ax3, tr_o(1),tr_o(2),tr_o(3), 0,0,tr_len, 0, ...
                    'Color', tr_col, 'LineWidth', 1.3, 'MaxHeadSize', 0.8);   % label y (data +Z)
            text(ax3, tr_o(1)+1.30*tr_len, tr_o(2), tr_o(3), 'z', ...
                 'FontName', 'Times New Roman', 'FontAngle', 'italic', 'FontSize', 12, 'Color', tr_col);
            text(ax3, tr_o(1), tr_o(2)+1.30*tr_len, tr_o(3), 'x', ...
                 'FontName', 'Times New Roman', 'FontAngle', 'italic', 'FontSize', 12, 'Color', tr_col);
            text(ax3, tr_o(1), tr_o(2), tr_o(3)+1.30*tr_len, 'y', ...
                 'FontName', 'Times New Roman', 'FontAngle', 'italic', 'FontSize', 12, 'Color', tr_col);
        end

        drawnow;
        % PNG only: a vector export of a revolved 3-D scene is enormous.
        files = [files, save_fig(fig3, base3d, out_dir, {'png'}, P.png_dpi, true)];
    end
end
