function files = paper_fig_dipole(lens, cfg, base, out_dir)
%PAPER_FIG_DIPOLE  Paper Fig 3c: lens cross-section with the emitter and theta marker.
%
%   files = paper_fig_dipole(lens, cfg, base, out_dir)
%
%   Ported from na2_fig_dipole.m verbatim: the filled lens, the source dot, the two
%   dark-red theta lines (optical axis backwards, and source -> inner crescent tip)
%   with the italic theta label, and the zoom window centred on the inner crescent.
%   The dipole radiation lobes themselves are added later in PowerPoint - this panel
%   is only the lens + the acceptance angle.
%
%   Fill / outline styling comes from the style preset through draw_lens_filled, so
%   Fig 3c matches Fig 1a/1b. The zoom half-window follows figures.paper:
%   zoom_half_mm when set, otherwise the auto window that frames the first
%   zoom_n_elements elements with an 8 % margin (StochasticRayTrace's rule).
%
%   DEVIATION: the source marker uses the style preset's emitter colour (#E7633D,
%   the hex the paper's Fig-1 and Fig-3 emitters share) instead of na2_fig_dipole's
%   [0.85 0.10 0.10]; and the zoom window is config-driven instead of P.zoom_radius.

    P = cfg.figures.paper;
    S = style_preset(cfg.figures.style);

    ANN_COLOR = [0.80 0.10 0.10];   % na2_fig_dipole theta annotation
    ANN_LW    = 2;
    ANN_FS    = 16;

    fig = figure('Name', base, 'NumberTitle', 'off', 'Color', 'w', ...
                 'Units', 'centimeters', 'Position', [2 2 P.fig_size_cm(1) P.fig_size_cm(2)]);
    ax = axes('Parent', fig);
    hold(ax, 'on');  axis(ax, 'equal');  axis(ax, 'off');

    draw_lens_filled(ax, lens, S);

    src = lens.source_pos(:).';
    plot(ax, src(1), src(2), 'o', 'MarkerFaceColor', S.emitterColor, ...
         'MarkerEdgeColor', 'none', 'MarkerSize', S.emitterSize);

    % --- theta: optical axis (backwards) and the line to the inner crescent tip -
    c   = lens.final_lens{1};
    tip = c(end, :);
    d   = hypot(tip(1)-src(1), tip(2)-src(2));
    plot(ax, [src(1) src(1)-d], [src(2) src(2)],   '-', 'Color', ANN_COLOR, 'LineWidth', ANN_LW);
    plot(ax, [src(1) tip(1)],   [src(2) tip(2)],   '-', 'Color', ANN_COLOR, 'LineWidth', ANN_LW);
    text(ax, src(1)-0.35*d, src(2)+0.05*d, '\theta', 'Color', ANN_COLOR, ...
         'FontWeight', 'bold', 'FontSize', ANN_FS, 'HorizontalAlignment', 'right');

    % --- zoom window ----------------------------------------------------------
    zr = zoom_half_du(lens, P);
    cx = mean([min(c(:,1)), max(c(:,1))]);      % centred on the inner crescent, as in na2_fig_dipole
    xlim(ax, [cx-zr, cx+zr]);
    ylim(ax, [-zr, zr]);

    set(fig, 'Renderer', 'painters');
    drawnow;
    files = save_fig(fig, base, out_dir, P.formats, P.png_dpi, true);
end

% ---------------------------------------------------------------------------
function zh = zoom_half_du(lens, P)
%ZOOM_HALF_DU  Zoom half-window in design units (StochasticRayTrace ZOOM_HALF rule).
%   figures.paper.zoom_half_mm when the config sets one, otherwise the square that
%   contains the first zoom_n_elements elements (surface points and closure tips)
%   plus an 8 % margin. Same rule as paper_fig_crosssection - repeated here because
%   MATLAB local functions are file-private.
    if isfield(P, 'zoom_half_mm') && ~isempty(P.zoom_half_mm)
        zh = P.zoom_half_mm / lens.mm_per_du;
        return;
    end
    ZOOM_MARGIN = 1.08;                        % 8 % margin
    final_lens = lens.final_lens;
    L = min(lens.L, numel(final_lens));
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
end
