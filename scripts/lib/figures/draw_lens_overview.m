function draw_lens_overview(final_lens, layers_count, scale_mm, out_dir, dmeta, labels)
    if nargin < 5, dmeta = []; end
    if nargin < 6, labels = {}; end
    [wm, dpi] = dmeta_style(dmeta, 150);
    revlabel = 'Rev A'; if isstruct(dmeta) && isfield(dmeta, 'rev'), revlabel = dmeta.rev; end
    % Whole-lens cross-section with a single light diameter caliper per element
    % (thin vertical line at the widest point, ticked at ±radius, labelled Ø).
    % Deliberately minimal — an assembly overview, not a manufacturing drawing.
    % labels (optional): one string per element, e.g. 'PMMA n=1.489' (per-element
    % materials), appended to that element's diameter tick; {} = diameters only.
    % The title names dmeta.glass; without one it keeps the legacy N-LASF9 text.
    has_labels = iscell(labels) && any(~cellfun(@isempty, labels));
    if nargin < 3 || isempty(scale_mm), scale_mm = 1; end
    n_elem = floor(layers_count / 2);
    dc = [0.20 0.20 0.20];  ec = [0 0 0];

    figure('Name', 'Lens overview — element diameters', 'Color', 'w');
    ax = axes; hold(ax, 'on'); axis(ax, 'equal');

    % --- draw element outlines; collect each element's radius & widest-x ---
    rs = nan(1, n_elem);  xeq = nan(1, n_elem);  xall = [];
    for e = 1:n_elem
        li = 2*e - 1;  lo = 2*e;
        if lo > numel(final_lens) || isempty(final_lens{lo}), continue; end
        inn = final_lens{li} * scale_mm;
        out = final_lens{lo} * scale_mm;
        plot(ax, inn(:,1),  inn(:,2), '-', 'Color', ec, 'LineWidth', 1.3);
        plot(ax, inn(:,1), -inn(:,2), '-', 'Color', ec, 'LineWidth', 1.3);
        plot(ax, out(:,1),  out(:,2), '-', 'Color', ec, 'LineWidth', 1.3);
        plot(ax, out(:,1), -out(:,2), '-', 'Color', ec, 'LineWidth', 1.3);
        plot(ax, [inn(end,1) out(end,1)], [ inn(end,2)  out(end,2)], '-', 'Color', ec, 'LineWidth', 1.3);
        plot(ax, [inn(end,1) out(end,1)], [-inn(end,2) -out(end,2)], '-', 'Color', ec, 'LineWidth', 1.3);
        [rs(e), ie] = max(abs(out(:,2)));  xeq(e) = out(ie,1);
        xall = [xall; inn(:,1); out(:,1)]; %#ok<AGROW>
    end
    xr = [min(xall) max(xall)];  span = xr(2) - xr(1);

    % focus + optical axis
    plot(ax, 0, 0, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);

    % --- diameter dimensions: one radius scale on the right, one tick per element ---
    rmax = max(rs(~isnan(rs)));
    xb = xr(2) + 0.10*span;  tk = 0.012*span;
    plot(ax, [xb xb], [-rmax rmax], '-', 'Color', dc, 'LineWidth', 0.8);          % scale line
    for e = 1:n_elem
        if isnan(rs(e)), continue; end
        plot(ax, [xeq(e) xb], [ rs(e)  rs(e)], ':', 'Color', dc, 'LineWidth', 0.5);  % extension lines
        plot(ax, [xeq(e) xb], [-rs(e) -rs(e)], ':', 'Color', dc, 'LineWidth', 0.5);
        plot(ax, xb+[-tk tk], [ rs(e)  rs(e)], '-', 'Color', dc, 'LineWidth', 0.9);  % tick pair
        plot(ax, xb+[-tk tk], [-rs(e) -rs(e)], '-', 'Color', dc, 'LineWidth', 0.9);
        lab = sprintf('El %d: %.1f mm', e, 2*rs(e));
        if has_labels && e <= numel(labels) && ~isempty(labels{e}), lab = sprintf('%s, %s', lab, labels{e}); end
        text(ax, xb+1.8*tk, rs(e), lab, 'Color', dc, ...
             'FontSize', 9, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
             'Interpreter', 'none');
    end
    plot(ax, [xr(1)-2 xb], [0 0], '-.', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.7);

    daspect(ax, [1 1 1]);                            % equal aspect, but keep our chosen limits
    xroom = 0.34;  if has_labels, xroom = 0.60; end  % material names make the tick labels twice as long
    xlim(ax, [xr(1)-0.05*span, xb + xroom*span]);    % room for the labels
    ylim(ax, [-1.12*rmax, 1.16*rmax]);               % headroom so the top label clears the frame
    grid(ax, 'on'); box(ax, 'on'); set(ax, 'FontSize', 10);
    xlabel(ax, 'optical axis (mm)'); ylabel(ax, 'radius (mm)');
    % first title line: the drawing's glass label (same form as the element drawings);
    % the legacy hard-coded text only when dmeta carries no glass label
    if isstruct(dmeta) && isfield(dmeta, 'glass') && ischar(dmeta.glass) && ~isempty(dmeta.glass)
        line1 = sprintf('Full lens — element diameters  -  %s', dmeta.glass);
    else
        line1 = 'Full lens — element diameters (N-LASF9, n = 1.85)';
    end
    title(ax, {line1, ...
        sprintf('%d elements; focus at origin; overall length %.1f mm', n_elem, span)}, ...
        'Interpreter', 'none', 'FontSize', 12);
    if ~isempty(wm), text(ax, 0.015, 0.02, sprintf('%s (%s)', wm, revlabel), 'Units', 'normalized', ...
         'Color', [0.65 0 0], 'FontWeight', 'bold', 'FontSize', 10); end

    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    base = fullfile(out_dir, 'lens_overview');
    set(gcf, 'PaperUnits', 'inches', 'PaperPositionMode', 'manual', 'PaperPosition', [0 0 13 9]);
    drawnow;
    try, print(gcf, base, '-dpng', sprintf('-r%d', dpi)); catch, saveas(gcf, [base '.png']); end
    try, print(gcf, base, '-dsvg'); catch, end
    fprintf('Lens overview saved: %s(.png/.svg)\n', base);
end

function [wm, dpi] = dmeta_style(dmeta, dpi_default)
    % watermark text and PNG resolution from dmeta (config), with the legacy defaults
    wm = 'PRELIMINARY - NOT FOR MANUFACTURE';
    if isstruct(dmeta) && isfield(dmeta, 'watermark'), wm = dmeta.watermark; end
    dpi = dpi_default;
    if isstruct(dmeta) && isfield(dmeta, 'png_dpi') && ~isempty(dmeta.png_dpi), dpi = dmeta.png_dpi; end
end
