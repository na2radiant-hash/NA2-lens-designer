function plot_cut_pieces_separated(final_lens, elem, scale_mm, cut)
    % Rebuilds each piece of the perpendicular cut at x = cut.x0 as its own
    % closed solid (its side of both surfaces + the flat cut face) and shows the
    % two pieces in separate subplots so each can be inspected on its own.
    if nargin < 3 || isempty(scale_mm), scale_mm = 1; end
    li = 2*elem - 1;  lo = 2*elem;
    if lo > numel(final_lens) || isempty(final_lens{lo})
        warning('plot_cut_pieces_separated: element %d not available.', elem); return;
    end
    x0 = 0;
    if ~isempty(cut) && isfield(cut,'x0'), x0 = cut.x0; end   % single source of truth
    inn = final_lens{li} * scale_mm;
    out = final_lens{lo} * scale_mm;
    nt = 140;

    [ob, of, roC] = split_prof(out, x0);     % outer: back, front, crossing radius
    [ib, iff, riC] = split_prof(inn, x0);    % inner: back, front, crossing radius
    ro0 = 0; if ~isempty(roC), ro0 = roC(1); end
    ri0 = 0; if ~isempty(riC), ri0 = riC(1); end

    cOut = [0.10 0.72 0.66];  cIn = [0.90 0.62 0.22];  aOut = 0.45;  % outer translucent, inner opaque
    figure('Name', sprintf('Element %d cut pieces (separated)', elem), 'Color', 'w');
    tl = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('Element %d split at x = %.2f mm - the two bonded pieces', elem, x0), ...
          'Interpreter', 'none');

    ax1 = nexttile;  hold(ax1, 'on');
    revsurf(ax1, ob,  nt, cOut, aOut);  revsurf(ax1, ib,  nt, cIn, 1.0);
    ring3(ax1, x0, ri0, ro0, [0.6 0.6 0.6]);
    finish3d(ax1, 'Back piece  (x \leq cut)');

    ax2 = nexttile;  hold(ax2, 'on');
    revsurf(ax2, of,  nt, cOut, aOut);  revsurf(ax2, iff, nt, cIn, 1.0);
    ring3(ax2, x0, ri0, ro0, [0.6 0.6 0.6]);
    finish3d(ax2, 'Front piece  (x \geq cut)');

    fprintf('Separated cut-piece view: element %d at x = %.2f mm.\n', elem, x0);
end
