function files = paper_fig_3dbody(lens, cfg, base, out_dir, zoom)
%PAPER_FIG_3DBODY  Paper Fig 1c / Fig 1d: the lens as a lit 3-D solid of revolution.
%
%   files = paper_fig_3dbody(lens, cfg, base, out_dir, zoom)
%
%   zoom = false -> Fig 1c, every surface;
%   zoom = true  -> Fig 1d, only the first figures.paper.zoom_n_elements elements.
%
%   Ported from SolidOfRevolution.m verbatim: the axes styling and camera
%   (view 25/18, CameraViewAngle 6), the bone colormap indexed by layer with the
%   "Refractive Index Layer (inner -> outer)" colorbar, the star source marker and
%   its label, the per-layer revolution surface (alpha 0.55, flat face colour,
%   ambient/diffuse/specular 0.35/0.75/0.45, specular exponent 20) and the
%   two-light + material([0.35 0.75 0.45 20 0.3]) lighting rig.
%
%   Revolution resolution: cfg.figures.rfq.n_theta when the config has it,
%   otherwise SolidOfRevolution's own 120.
%
%   DEVIATION: the source loaded a .mat whose geometry was already in millimetres;
%   here the design-unit geometry is scaled by lens.mm_per_du on the way in, so the
%   "X/Y/Z (mm)" axis labels and the 8 mm source-label offset stay literally true.

    if nargin < 5 || isempty(zoom), zoom = false; end
    P = cfg.figures.paper;

    N_THETA_DEFAULT = 120;              % SolidOfRevolution n_theta
    SRC_LABEL_DZ_MM = 8;                % 'Source' text sits 8 mm above the marker
    FACE_ALPHA      = 0.55;             % alpha_val

    n_theta = N_THETA_DEFAULT;
    if isfield(cfg.figures, 'rfq') && isfield(cfg.figures.rfq, 'n_theta') && ~isempty(cfg.figures.rfq.n_theta)
        n_theta = cfg.figures.rfq.n_theta;
    end

    s = lens.mm_per_du;                 % design units -> mm
    final_lens = lens.final_lens;
    L = min(lens.L, numel(final_lens));
    j_last = L;
    if zoom, j_last = min(2 * P.zoom_n_elements, L); end

    src   = lens.source_pos(:).' * s;
    src_x = src(1);  src_y = src(2);  src_z = 0;

    % --- figure & axes --------------------------------------------------------
    fig = figure('Name', base, 'NumberTitle', 'off', 'Color', 'w', ...
                 'Units', 'pixels', 'Position', [100 100 1000 780]);
    ax = axes('Parent', fig, 'Color', 'w', ...
              'XColor', 'k', 'YColor', 'k', 'ZColor', 'k', ...
              'GridColor', [0.6 0.6 0.6], 'GridAlpha', 0.5, ...
              'FontSize', 12, 'FontName', 'Helvetica', 'LineWidth', 1.2);
    hold(ax, 'on');  axis(ax, 'equal');  grid(ax, 'on');

    view(ax, 25, 18);
    set(ax, 'CameraViewAngle', 6);

    xlabel(ax, 'X (mm)', 'Color', 'k', 'FontSize', 13, 'FontWeight', 'bold');
    ylabel(ax, 'Y (mm)', 'Color', 'k', 'FontSize', 13, 'FontWeight', 'bold');
    zlabel(ax, 'Z (mm)', 'Color', 'k', 'FontSize', 13, 'FontWeight', 'bold');
    title(ax, '3D Lens Geometry - Solid of Revolution', ...
          'Color', 'k', 'FontSize', 15, 'FontWeight', 'bold');

    % --- colormap: one bone shade per layer -----------------------------------
    cmap = bone(L);
    colormap(ax, cmap);
    try
        cb = colorbar(ax);
        set(cb, 'Color', 'k');
        set(get(cb, 'Label'), 'String', 'Refractive Index Layer (inner -> outer)', ...
            'Color', 'k', 'FontSize', 12);
    catch
        % colorbar label handling differs between MATLAB and Octave - the bar itself
        % is what matters for the figure.
    end
    set_color_limits(ax, [1 L]);

    % --- source marker --------------------------------------------------------
    plot3(ax, src_x, src_y, src_z, 'p', ...
          'MarkerFaceColor', [0.85 0.1 0.1], 'MarkerEdgeColor', 'k', ...
          'MarkerSize', 14, 'LineWidth', 1.2);
    text(ax, src_x, src_y, src_z + SRC_LABEL_DZ_MM, 'Source', ...
         'Color', 'k', 'FontSize', 10, 'FontWeight', 'bold');

    % --- solid of revolution --------------------------------------------------
    theta = linspace(0, 2*pi, n_theta);
    for j = 1:j_last
        curve = final_lens{j};
        if isempty(curve), continue; end
        curve = curve(curve(:,2) >= 0, :) * s;        % upper half, mm
        if isempty(curve), continue; end

        x = curve(:,1);
        r = curve(:,2);
        [T, Xgrid] = meshgrid(theta, x);
        R = repmat(r, 1, n_theta);
        Y = R .* cos(T);
        Z = R .* sin(T);
        C = ones(size(Xgrid)) * j;

        surf(ax, Xgrid, Y, Z, C, ...
             'FaceAlpha', FACE_ALPHA, ...
             'FaceColor', 'flat', ...
             'EdgeColor', 'none', ...
             'AmbientStrength',  0.35, ...
             'DiffuseStrength',  0.75, ...
             'SpecularStrength', 0.45, ...
             'SpecularExponent', 20);
    end

    % --- lighting -------------------------------------------------------------
    delete(findall(fig, 'Type', 'light'));
    light('Parent', ax, 'Position', [ 200  150  200], 'Style', 'infinite', 'Color', [1   1   1  ]);
    light('Parent', ax, 'Position', [-100 -100 -100], 'Style', 'infinite', 'Color', [0.3 0.3 0.5]);
    lighting(ax, 'gouraud');
    try
        material(ax, [0.35 0.75 0.45 20 0.3]);
    catch
        axes(ax);  material([0.35 0.75 0.45 20 0.3]);   % older material(): current axes only
    end

    set(ax, 'TickDir', 'out', 'Box', 'off');
    drawnow;

    files = save_fig(fig, base, out_dir, P.formats, P.png_dpi, true);
end

% ---------------------------------------------------------------------------
function set_color_limits(ax, lims)
%SET_COLOR_LIMITS  clim (R2022a+) with the caxis fallback of older MATLAB / Octave.
    try
        clim(ax, lims);
    catch
        caxis(ax, lims); %#ok<CAXIS>
    end
end
