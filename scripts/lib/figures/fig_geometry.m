function fig = fig_geometry(lens, stack, cfg, svg_path, header, png_path)
%FIG_GEOMETRY  The construction-geometry figure of LensConstructionGradual (unchanged drawing).
%
%   fig = fig_geometry(lens, stack, cfg, svg_path, header, png_path)
%     header    cellstr printed under the title (run_header_lines: materials and
%               refractive indices, prescribed sphere / straight wall, design); {} = title only
%     png_path  also save a PNG there ('' = no PNG), so every package holds a picture
%
%   Outline of every surface + mirrored copy, crescent tips closed (flat cap
%   for element 1, pointy tip for the others), the source; optional translucent
%   fill (figures.rfq.filled_overlay) and optional ray overlay
%   (figures.rfq.ray_overlay: n_rays uniform rays up to the nominal fan, extended
%   by extend_len_du). svg_path = '' skips the SVG export (export.svg_geometry).
%   Prescribed spheres (lens.surfaces, design.spherical_surfaces) are drawn as
%   their exact arc through design_profiles; built layers are unchanged.

    F = cfg.figures.rfq;
    surfaces = [];  if isfield(lens, 'surfaces'), surfaces = lens.surfaces; end
    final_lens = design_profiles(lens.final_lens, surfaces);
    layers_count = lens.L;  source_pos = lens.source_pos;

    fig = figure('Name', 'Lens Construction Output');
    clf; hold on;
    set(fig, 'Color', 'w');
    xlabel('X-axis'); ylabel('Y-axis');
    axis equal; grid on;
    ttl = {'Constructed Lens Geometry (weighted bending, collimated output)'};
    if nargin >= 5 && ~isempty(header), ttl = [ttl, header(:).']; end
    title(ttl, 'Interpreter', 'none', 'FontSize', 9);

    mirrored_lens = mirror_lens(final_lens);
    for j = 1:layers_count
        if isempty(final_lens{j}), continue; end
        plot(final_lens{j}(:,1),    final_lens{j}(:,2),    'k', 'LineWidth', 1.5);
        plot(mirrored_lens{j}(:,1), mirrored_lens{j}(:,2), 'k', 'LineWidth', 1.5);
    end
    plot(source_pos(1), source_pos(2), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');

    % Close the innermost crescent: connect layer 1 and layer 2 tip endpoints (top and bottom)
    plot([final_lens{1}(end,1), final_lens{2}(end,1)], ...
         [final_lens{1}(end,2), final_lens{2}(end,2)], 'k', 'LineWidth', 1.5);
    plot([mirrored_lens{1}(end,1), mirrored_lens{2}(end,1)], ...
         [mirrored_lens{1}(end,2), mirrored_lens{2}(end,2)], 'k', 'LineWidth', 1.5);

    % Close outer crescents (layers 3&4, 5&6, ...) with a pointy end
    for e = 2 : floor(layers_count / 2)
        li = 2*e - 1;  lo = 2*e;
        if isempty(final_lens{li}) || isempty(final_lens{lo}), continue; end
        p1 = final_lens{li}(end,:);
        a1 = atan2d(p1(2) - final_lens{li}(end-1,2), p1(1) - final_lens{li}(end-1,1));
        p2 = final_lens{lo}(end,:);
        a2 = atan2d(p2(2) - final_lens{lo}(end-1,2), p2(1) - final_lens{lo}(end-1,1));
        tip_top = find_intersection(p1, a1, p2, a2);
        if ~any(isnan(tip_top))
            plot([p1(1), tip_top(1)], [p1(2), tip_top(2)], 'k', 'LineWidth', 1.5);
            plot([p2(1), tip_top(1)], [p2(2), tip_top(2)], 'k', 'LineWidth', 1.5);
        end
        p1m = mirrored_lens{li}(end,:);
        a1m = atan2d(p1m(2) - mirrored_lens{li}(end-1,2), p1m(1) - mirrored_lens{li}(end-1,1));
        p2m = mirrored_lens{lo}(end,:);
        a2m = atan2d(p2m(2) - mirrored_lens{lo}(end-1,2), p2m(1) - mirrored_lens{lo}(end-1,1));
        tip_bot = find_intersection(p1m, a1m, p2m, a2m);
        if ~any(isnan(tip_bot))
            plot([p1m(1), tip_bot(1)], [p1m(2), tip_bot(2)], 'k', 'LineWidth', 1.5);
            plot([p2m(1), tip_bot(1)], [p2m(2), tip_bot(2)], 'k', 'LineWidth', 1.5);
        end
    end

    % glass spacers and asphere, if any
    if ~isempty(lens.glass_info) && isstruct(lens.glass_info) && isfield(lens.glass_info, 'gaps')
        for k = 1:numel(lens.glass_info.gaps)
            g = lens.glass_info.gaps(k);
            if isnan(g.h_glass), continue; end
            plot([g.x_left g.x_left g.x_right g.x_right g.x_left], [g.h_glass -g.h_glass -g.h_glass g.h_glass g.h_glass], ...
                 'Color', [0.20 0.45 0.75], 'LineWidth', 1.2);
        end
    end
    if ~isempty(lens.asphere) && isstruct(lens.asphere)
        for S = {lens.asphere.S1, lens.asphere.S2}
            P = S{1};
            plot(P(:,1), P(:,2), 'k', 'LineWidth', 1.5);  plot(P(:,1), -P(:,2), 'k', 'LineWidth', 1.5);
        end
    end
    fprintf('Plotted constructed lens.\n');

    % OPTIONAL FILLED OVERLAY (closed polygons for each layer, top + mirrored bottom)
    if F.filled_overlay
        overlay_handles = gobjects(0);
        for j = 1:layers_count
            if isempty(final_lens{j}), continue; end
            top = final_lens{j};
            poly_xy = [top; flipud([top(:,1), -top(:,2)])];
            if any(isnan(poly_xy(:))) || any(isinf(poly_xy(:))), continue; end
            if ~isequal(poly_xy(1,:), poly_xy(end,:)), poly_xy = [poly_xy; poly_xy(1,:)]; end %#ok<AGROW>
            h = patch(poly_xy(:,1), poly_xy(:,2), [0.2 0.7 0.35], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
            overlay_handles(end+1) = h; %#ok<AGROW>
        end
        uistack(overlay_handles, 'bottom');
        fprintf('Filled overlay enabled.\n');
    end

    % OPTIONAL RAY-TRACE OVERLAY on the geometry figure (through the full surface stack)
    if F.ray_overlay.enable
        T = cfg.trace;
        T.n_rays = F.ray_overlay.n_rays;  T.sampling = 'deterministic';
        T.max_angle_deg = lens.nominal_max_angle;  T.min_angle_deg = 0;  T.angle_epsilon_deg = 1e-6;
        T.extend_len = F.ray_overlay.extend_len_du;
        tr = trace_rays(lens, stack, T);
        for ri = 1:tr.n_rays
            path_r = tr.paths{ri};
            t   = (ri - 1) / max(tr.n_rays - 1, 1);
            col = [t,  0.25*(1 - abs(2*t - 1)),  1 - t];   % blue -> violet -> red
            plot(path_r(:,1),  path_r(:,2), '-', 'Color', [col, 0.75], 'LineWidth', 0.8);
            if max(abs(path_r(:,2))) > 0.5
                plot(path_r(:,1), -path_r(:,2), '-', 'Color', [col, 0.75], 'LineWidth', 0.8);
            end
        end
        fprintf('Ray trace overlay complete (%d rays).\n', tr.n_rays);
    end

    % PNG copy: a picture of the result in every package (also on FAIL)
    if nargin >= 6 && ~isempty(png_path)
        drawnow;
        try
            exportgraphics(fig, png_path, 'Resolution', 150);
        catch
            print(fig, png_path, '-dpng', '-r150');
        end
        fprintf('Figure exported to PNG: %s\n', png_path);
    end

    % EXPORT FIGURE TO SVG (vector) for Inkscape
    if nargin >= 4 && ~isempty(svg_path)
        grid off; box off;
        set(gca, 'TickDir', 'out');
        set(fig, 'Renderer', 'painters');
        print(fig, svg_path, '-dsvg');
        fprintf('Figure exported to SVG: %s\n', svg_path);
    end
end
