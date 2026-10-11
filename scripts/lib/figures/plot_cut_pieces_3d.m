function plot_cut_pieces_3d(final_lens, elem, scale_mm, cut, dmeta, out_dir)
    % Revolves the element (both surfaces) 360 deg and colours it by which side of
    % the cut plane each part is on — showing the two pieces the cut produces. The
    % cut position reads the SAME single variable as the cross-section: cut.x0.
    if nargin < 3 || isempty(scale_mm), scale_mm = 1; end
    if nargin < 5 || isempty(dmeta),    dmeta = default_dmeta(); end
    if nargin < 6, out_dir = ''; end
    li = 2*elem - 1;  lo = 2*elem;
    if lo > numel(final_lens) || isempty(final_lens{lo})
        warning('plot_cut_pieces_3d: element %d not available.', elem); return;
    end
    x0 = 0;
    if ~isempty(cut) && isfield(cut,'x0'), x0 = cut.x0; end   % single source of truth
    inn = final_lens{li} * scale_mm;
    out = final_lens{lo} * scale_mm;

    nt = 140;  th = linspace(0, 2*pi, nt);  ct = cos(th);  st = sin(th);
    cBack = [0.22 0.45 0.80];  cFront = [0.90 0.60 0.22];

    fig = figure('Name', sprintf('Element %d cut into two pieces (3D)', elem), 'Color', 'w');
    ax = axes; hold(ax, 'on');
    for s = 1:2
        if s == 1, S = out; else, S = inn; end
        xf = S(:,1);  r = abs(S(:,2));
        C  = repmat(double(xf >= x0), 1, nt);      % 0 = back (x<x0), 1 = front (x>=x0)
        surf(ax, repmat(xf,1,nt), r*ct, r*st, C, 'EdgeColor', 'none', ...
             'FaceColor', 'flat', 'FaceLighting', 'gouraud');
    end
    colormap(ax, [cBack; cFront]);  caxis(ax, [0 1]);

    % cut plane: translucent grey disk at x0
    rr = max(abs(out(:,2)));
    [TT, RR] = meshgrid(linspace(0, 2*pi, 60), [0 rr]);
    surf(ax, x0 + 0*TT, RR.*cos(TT), RR.*sin(TT), 'FaceColor', [0.4 0.4 0.4], ...
         'FaceAlpha', 0.15, 'EdgeColor', 'none');
    plot3(ax, 0, 0, 0, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 7);   % focus

    axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
    xlabel(ax, 'optical axis (mm)'); ylabel(ax, 'y (mm)'); zlabel(ax, 'z (mm)');
    % title block matching the cross-section: element/material, then the cut line
    title(ax, {sprintf('Element %d split 3D  -  %s', elem, dmeta.glass), ...
        sprintf('cut plane at x = %.2f mm    (blue = back piece, amber = front piece)', x0)}, ...
        'Interpreter', 'none', 'FontSize', 12);
    [wm, dpi] = dmeta_style(dmeta, 300);
    if ~isempty(wm), text(ax, 0.015, 0.075, sprintf('%s  (%s)', wm, dmeta.rev), ...
         'Units','normalized', 'Color',[0.65 0 0], 'FontWeight','bold', 'FontSize', 11); end
    text(ax, 0.015, 0.035, dmeta.note, ...
         'Units','normalized', 'Color',[0.35 0.35 0.35], 'FontSize', 10);
    view(ax, 3); camlight(ax, 'headlight'); lighting(ax, 'gouraud');
    material(ax, 'dull'); rotate3d(ax, 'on');

    % --- export: 300-dpi PNG via exportgraphics (no UI toolbar) ---
    if ~isempty(out_dir)
        if ~exist(out_dir, 'dir'), mkdir(out_dir); end
        set(fig, 'Units', 'inches', 'Position', [1 1 11 8.5]);
        try, ax.Toolbar.Visible = 'off'; catch, end
        drawnow;
        revtag = regexprep(dmeta.rev, '[^A-Za-z0-9]', '');
        base   = fullfile(out_dir, sprintf('element%d_split_3D_%s', elem, revtag));
        exportgraphics(fig, [base '.png'], 'Resolution', dpi);
        fprintf('3D split view exported: %s.png  (cut x = %.2f mm)\n', base, x0);
    else
        fprintf('3D two-piece cut view: element %d at x = %.2f mm.\n', elem, x0);
    end
end

function [wm, dpi] = dmeta_style(dmeta, dpi_default)
    % watermark text and PNG resolution from dmeta (config), with the legacy defaults
    wm = 'PRELIMINARY - NOT FOR MANUFACTURE';
    if isstruct(dmeta) && isfield(dmeta, 'watermark'), wm = dmeta.watermark; end
    dpi = dpi_default;
    if isstruct(dmeta) && isfield(dmeta, 'png_dpi') && ~isempty(dmeta.png_dpi), dpi = dmeta.png_dpi; end
end
