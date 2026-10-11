function files = paper_fig_schematic(lens, cfg, base, out_dir)
%PAPER_FIG_SCHEMATIC  Paper Fig 3a: outline-only schematic for Illustrator.
%
%   files = paper_fig_schematic(lens, cfg, base, out_dir)
%
%   The bare drawing an illustrator needs and nothing else: every surface as a
%   black stroke (upper half + mirror), the crescent tips closed, the optical axis,
%   the emitter dot. No fills, no heatmap, no rays, no axis decorations - so the SVG
%   stays small and every path in it is a lens surface.
%
%   Outline and tip closure: na2_draw_lens_outline.m + process/crescent_outline.
%   Optical-axis stroke: the dash-dot centre line of figures/draw_lens_overview.m.
%   Stroke colour/width and the emitter come from the style preset, so the schematic
%   matches the other panels.
%
%   Exported vector-only (the 'svg' and 'pdf' entries of figures.paper.formats;
%   'svg' if the config asks for neither) and WITHOUT a label-free twin - the figure
%   carries no text, so both copies would be identical.

    P = cfg.figures.paper;
    S = style_preset(cfg.figures.style);

    AXIS_COLOR = [0.5 0.5 0.5];   % draw_lens_overview centre line
    AXIS_LW    = 0.7;
    AXIS_PAD   = 0.06;            % axis line overhangs the lens by 6 % of its length

    final_lens = lens.final_lens;
    L = min(lens.L, numel(final_lens));
    n_elements = floor(L / 2);
    src = lens.source_pos(:).';

    fig = figure('Name', base, 'NumberTitle', 'off', 'Color', 'w', ...
                 'Units', 'centimeters', 'Position', [2 2 P.fig_size_cm(1) P.fig_size_cm(2)]);
    ax = axes('Parent', fig);
    hold(ax, 'on');  axis(ax, 'equal');

    % --- optical axis ---------------------------------------------------------
    allX = [];
    for j = 1:L
        if isempty(final_lens{j}), continue; end
        allX = [allX; final_lens{j}(:,1)]; %#ok<AGROW>
    end
    if isempty(allX), error('paper_fig_schematic:layers', 'No usable layers in lens.final_lens.'); end
    xmin = min([allX; src(1)]);  xmax = max([allX; src(1)]);
    pad  = AXIS_PAD * max(1e-9, xmax - xmin);
    plot(ax, [xmin - pad, xmax + pad], [src(2), src(2)], '-.', ...
         'Color', AXIS_COLOR, 'LineWidth', AXIS_LW);

    % --- surfaces (upper + mirrored), no fill ---------------------------------
    for j = 1:L
        if isempty(final_lens{j}), continue; end
        up = final_lens{j};  lo = [up(:,1), -up(:,2)];
        plot(ax, up(:,1), up(:,2), '-', 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
        plot(ax, lo(:,1), lo(:,2), '-', 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
    end

    % --- crescent tip closures ------------------------------------------------
    for e = 1:n_elements
        li = 2*e - 1;  lo = 2*e;
        if lo > L || isempty(final_lens{li}) || isempty(final_lens{lo}), continue; end
        if size(final_lens{li},1) < 2 || size(final_lens{lo},1) < 2, continue; end
        [~, cap] = crescent_outline(final_lens{li}, final_lens{lo}, e);
        capm = [cap(:,1), -cap(:,2)];
        plot(ax, cap(:,1),  cap(:,2),  '-', 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
        plot(ax, capm(:,1), capm(:,2), '-', 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
    end

    % --- commercial asphere, when the design has one ---------------------------
    if isfield(lens, 'asphere') && ~isempty(lens.asphere) && isstruct(lens.asphere)
        A = lens.asphere;
        curves = {A.S1, A.S2, [A.S1(end,:); A.S2(end,:)]};
        for c = 1:numel(curves)
            cu = curves{c};  cm = [cu(:,1), -cu(:,2)];
            plot(ax, cu(:,1), cu(:,2), '-', 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
            plot(ax, cm(:,1), cm(:,2), '-', 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
        end
    end

    % --- emitter --------------------------------------------------------------
    plot(ax, src(1), src(2), 'o', 'MarkerFaceColor', S.emitterColor, ...
         'MarkerEdgeColor', 'none', 'MarkerSize', S.emitterSize);

    axis(ax, 'off');
    set(fig, 'Renderer', 'painters');
    drawnow;

    fmts = {};
    for k = 1:numel(P.formats)
        f = lower(strtrim(char(P.formats{k})));
        if strcmp(f, 'svg') || strcmp(f, 'pdf'), fmts{end+1} = f; end %#ok<AGROW>
    end
    if isempty(fmts), fmts = {'svg'}; end
    files = save_fig(fig, base, out_dir, fmts, P.png_dpi, false);
end
