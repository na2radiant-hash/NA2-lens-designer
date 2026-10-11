function fig = fig_raytrace(lens, trace, header, summary, out_dir, dpi)
%FIG_RAYTRACE  Picture of the validation ray trace: the whole lens and a zoom on the inner elements.
%
%   fig = fig_raytrace(lens, trace, header, summary, out_dir, dpi)
%     trace    result of trace_rays (the validation trace the checks judge)
%     header   cellstr from run_header_lines (materials, variants, design)
%     summary  one line with the numbers of the run (collected / lost, collimation, collection)
%     out_dir  folder that receives ray_trace.png ('' = do not save)
%
%   Every run gets this picture, PASS or FAIL: it is how a lost ray is found.
%   Collected rays are blue, LOST rays (miss / total internal reflection) thick red
%   and drawn up to where they stop. About 60 rays are drawn evenly over the fan,
%   plus every lost one. Lengths in mm; the lower half is the mirror image.

    if nargin < 6 || isempty(dpi), dpi = 150; end
    mm = lens.mm_per_du;  L = lens.L;  nE = floor(L / 2);
    surfaces = [];  if isfield(lens, 'surfaces'), surfaces = lens.surfaces; end
    FL = design_profiles(lens.final_lens, surfaces);

    n = trace.n_rays;
    keep = unique([round(linspace(1, n, min(n, 60))), find(~trace.collected(:)).']);
    cOK = [0.15 0.45 0.85];  cBad = [0.85 0.05 0.05];

    fig = figure('Name', 'Validation ray trace', 'Color', 'w');
    set(fig, 'Units', 'pixels', 'Position', [40 60 1750 900]);
    for p = 1:2
        ax = axes('Parent', fig, 'Position', [0.05 + 0.50 * (p - 1), 0.08, 0.43, 0.72]);   % the top 16 % is the header
        hold(ax, 'on');  axis(ax, 'equal');  grid(ax, 'on');  box(ax, 'on');
        for r = keep
            P = trace.paths{r} * mm;
            if trace.collected(r), col = cOK; lw = 0.6; else, col = cBad; lw = 1.6; end
            plot(ax, P(:,1),  P(:,2), '-', 'Color', col, 'LineWidth', lw);
            plot(ax, P(:,1), -P(:,2), '-', 'Color', col, 'LineWidth', lw);
        end
        for e = 1:nE
            inner = FL{2*e-1} * mm;  outer = FL{2*e} * mm;
            if isempty(inner) || isempty(outer), continue; end
            [~, cap] = crescent_outline(inner, outer, e);
            for sgn = [1 -1]
                plot(ax, inner(:,1), sgn * inner(:,2), 'k', 'LineWidth', 1.3);
                plot(ax, outer(:,1), sgn * outer(:,2), 'k', 'LineWidth', 1.3);
                plot(ax, cap(:,1),   sgn * cap(:,2),   'k', 'LineWidth', 1.3);
            end
        end
        if ~isempty(lens.asphere) && isstruct(lens.asphere)
            for S = {lens.asphere.S1, lens.asphere.S2}
                Q = S{1} * mm;  plot(ax, Q(:,1), Q(:,2), 'k', 'LineWidth', 1.3);  plot(ax, Q(:,1), -Q(:,2), 'k', 'LineWidth', 1.3);
            end
        end
        plot(ax, 0, 0, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        xlabel(ax, 'optical axis (mm)');  ylabel(ax, 'radius (mm)');
        if p == 1
            allx = cell2mat(cellfun(@(c) c(:,1), FL(1:L), 'UniformOutput', false)) * mm;
            ally = cell2mat(cellfun(@(c) c(:,2), FL(1:L), 'UniformOutput', false)) * mm;
            span = max(allx) - min(allx);
            xlim(ax, [min(allx) - 0.08 * span, max(allx) + 0.30 * span]);  ylim(ax, 1.08 * max(abs(ally)) * [-1 1]);
            title(ax, 'whole lens', 'FontWeight', 'normal');
        else
            ez = min(2, nE);                                   % zoom: the first two elements
            zx = cell2mat(cellfun(@(c) c(:,1), FL(1:2*ez), 'UniformOutput', false)) * mm;
            zy = cell2mat(cellfun(@(c) c(:,2), FL(1:2*ez), 'UniformOutput', false)) * mm;
            span = max(zx) - min(zx);
            xlim(ax, [min(zx) - 0.10 * span, max(zx) + 0.10 * span]);  ylim(ax, 1.10 * max(abs(zy)) * [-1 1]);
            title(ax, sprintf('zoom: elements 1-%d', ez), 'FontWeight', 'normal');
        end
    end
    txt = [{'Validation ray trace  (blue = collected, red = lost)'}, header(:).', {summary}];
    annotation(fig, 'textbox', [0.03 0.855 0.94 0.14], 'String', txt, 'EdgeColor', 'none', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 10, 'Interpreter', 'none', 'FitBoxToText', 'off');
    drawnow;
    if nargin >= 5 && ~isempty(out_dir)
        if ~exist(out_dir, 'dir'), mkdir(out_dir); end
        f = fullfile(out_dir, 'ray_trace.png');
        try
            exportgraphics(fig, f, 'Resolution', dpi);
        catch
            print(fig, f, '-dpng', sprintf('-r%d', dpi));
        end
        fprintf('Ray-trace picture saved: %s\n', f);
    end
end
