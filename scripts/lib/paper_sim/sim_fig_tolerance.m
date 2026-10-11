function F = sim_fig_tolerance(lens, R, T, with_labels)
%SIM_FIG_TOLERANCE  Supplementary figure of the paper's two fabrication-tolerance checks.
%
%   F = sim_fig_tolerance(lens, R, T, with_labels)     lens from sim_build_lens, R from sim_tolerance, T = PAPER.tol
%
%   One figure per panel, F.A, F.B, F.C, so the panels can be laid out in PowerPoint.
%   with_labels = true (default): the full panels, with their letters. false (the _nolabels copies,
%   as for Fig 3): no text at all, no panel letters, titles, axis labels, tick labels, legends or
%   annotations, only the graphics, for labelling in PowerPoint; the axes keep their positions.
%
%   (A) method: the design collector with its rays, the bonding plane of element 1 and the
%       observation plane at distance D with the design beam envelope (not to scale); insets:
%       the two perturbations, exaggerated (lambda/2 peak-to-valley figure error with correlation
%       length l_c on every surface; the two parts of element 1 offset);
%   (B) check 1: power outside the design envelope versus distance, per correlation length (mean
%       and worst of the realisations), with the 0.1 % line;
%   (C) check 2: power outside the design envelope versus the alignment error of the two parts of
%       element 1 (offset, transverse and axial, equal to the error); the lambda/4 spec marked.
%       Independent of the distance (the lost rays are those arriving at the step between the parts).

    % style of the manuscript's Fig 3B: Arial, 13 pt ticks, 14 pt Title-Case axis labels with the unit
    % (and the scale) in square brackets, plain tick numbers, 0.9 pt axes, grid on, box on
    pub_font = 'Arial';  fs = 13;  fs_lg = 14;  lw_ax = 0.9;  grid_alpha = 0.18;
    navy  = [0.08 0.20 0.50];  lensfill = [185 225 240]/255;  red = [0.80 0.10 0.10];
    cols  = {[0.00 0.45 0.70], [0.90 0.50 0.00], [0.00 0.60 0.50], [0.50 0.00 0.55], [0.35 0.70 0.90]};

    if nargin < 4 || isempty(with_labels), with_labels = true; end
    tag = '';  if ~with_labels, tag = ' (no labels)'; end
    % one figure per panel: A (schematic + insets) 12 x 11 cm, B and C 13.5 x 11 cm
    F.A = figure('Name', ['Fig S A: method' tag], 'Color', 'w', 'Units', 'centimeters', 'Position', [3 3 12 11]);
    F.B = figure('Name', ['Fig S B: lambda/2 surfaces' tag], 'Color', 'w', 'Units', 'centimeters', 'Position', [16 3 13.5 11]);
    F.C = figure('Name', ['Fig S C: lambda/4 alignment' tag], 'Color', 'w', 'Units', 'centimeters', 'Position', [30 3 13.5 11]);
    grey = [0.3 0.3 0.3];

    %% ================= (A) method schematic =================
    axA = axes('Parent', F.A, 'Position', [0.01 0.04 0.52 0.92]);  hold(axA, 'on');
    final_lens = lens.final_lens;  L = min(lens.L, numel(final_lens));
    xs = cell2mat(cellfun(@(c) c(:,1), final_lens(1:L), 'uni', 0));
    xmin = min(xs);  xmax = max(xs);  span = xmax - xmin;
    h_max = R.h_max;
    % elements (fill) and surfaces (edges), mirrored about the axis
    for j = 2:2:L
        up_i = final_lens{j-1}; up_o = final_lens{j};
        verts = [up_o; flipud(up_i); [up_i(:,1), -up_i(:,2)]; flipud([up_o(:,1), -up_o(:,2)])];
        patch(axA, verts(:,1), verts(:,2), lensfill, 'EdgeColor', 'none');
    end
    for j = 1:L
        c = final_lens{j};
        plot(axA, c(:,1),  c(:,2), 'k-', 'LineWidth', 0.6);
        plot(axA, c(:,1), -c(:,2), 'k-', 'LineWidth', 0.6);
    end
    % a few design rays, extended to the observation plane
    x_plane = xmax + 0.55 * span;
    for a0 = [0 25 59 87 117 139 161]
        pth = trace_one(a0, lens, L);
        if isempty(pth), continue; end
        ac = pth(end, 3);  P0 = pth(end, 1:2);
        if cosd(ac) > 1e-9
            pth = [pth(:, 1:2); P0 + (x_plane - P0(1)) / cosd(ac) * [cosd(ac), sind(ac)]];
        else
            pth = pth(:, 1:2);
        end
        plot(axA, pth(:,1),  pth(:,2), '-', 'Color', navy, 'LineWidth', 0.6);
        plot(axA, pth(:,1), -pth(:,2), '-', 'Color', navy, 'LineWidth', 0.6);
    end
    plot(axA, 0, 0, 'o', 'MarkerFaceColor', [231 99 61]/255, 'MarkerEdgeColor', 'none', 'MarkerSize', 4);
    yb = 0.35 * h_max;                                         % bonding plane of element 1 (through elements 1-2)
    plot(axA, [R.cut_x_mm R.cut_x_mm], [-yb yb], '--', 'Color', red, 'LineWidth', 0.9);
    text(axA, xmin - 0.05 * span, -0.58 * h_max, {'Bonding plane', 'of element 1'}, 'FontName', pub_font, 'FontSize', fs - 1, ...
         'Color', red, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
    % observation plane and design envelope
    plot(axA, [x_plane x_plane], [-1.15 1.15] * h_max, '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.9);
    plot(axA, [xmax x_plane], [ h_max  h_max], ':', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.9);
    plot(axA, [xmax x_plane], [-h_max -h_max], ':', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.9);
    xb = xmax + 0.30 * span;                                   % axis break (not to scale)
    plot(axA, xb + [-0.012 0.012] * span, [-1.0 -0.80] * h_max * 0.25, 'w-', 'LineWidth', 4);
    plot(axA, xb + [-0.02 0.0] * span, [-0.12 0.12] * h_max, 'k-', 'LineWidth', 0.7);
    plot(axA, xb + [ 0.0 0.02] * span, [-0.12 0.12] * h_max, 'k-', 'LineWidth', 0.7);
    text(axA, x_plane + 0.04 * span, -1.22 * h_max, {'Observation plane,', 'distance D'}, 'FontName', pub_font, 'FontSize', fs - 1, ...
         'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');
    text(axA, xmax + 0.27 * span, h_max * 0.78, {'Design', 'envelope'}, 'FontName', pub_font, 'FontSize', fs - 2, ...
         'HorizontalAlignment', 'center', 'Color', [0.3 0.3 0.3]);
    text(axA, xb, -0.30 * h_max, 'Not to scale', 'FontName', pub_font, 'FontSize', fs - 2, 'Color', [0.4 0.4 0.4], 'HorizontalAlignment', 'center');
    axis(axA, 'equal'); axis(axA, 'off');
    xlim(axA, [xmin - 0.08 * span, x_plane + 0.08 * span]);  ylim(axA, [-1.45 1.3] * h_max);
    if with_labels
        text(axA, 0.0, 0.98, 'A', 'FontName', pub_font, 'FontSize', fs + 5, 'FontWeight', 'bold', 'Units', 'normalized');
    end

    % inset A1: surface figure error (exaggerated)
    ax1 = axes('Parent', F.A, 'Position', [0.58 0.62 0.40 0.26]);  hold(ax1, 'on');
    s = linspace(0, 1, 300);
    prof = 0.06 * (sin(2*pi*3.2*s + 0.4) + 0.6 * sin(2*pi*7.1*s + 2.0));
    patch(ax1, [s fliplr(s)], [prof, -0.5 * ones(size(s))], lensfill, 'EdgeColor', 'none');
    plot(ax1, s, prof, 'k-', 'LineWidth', 1.0);
    plot(ax1, s, zeros(size(s)), '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 0.6);
    plot(ax1, [0.80 0.80], [min(prof) max(prof)], '-', 'Color', red, 'LineWidth', 0.8);
    text(ax1, 0.83, 0.5 * (min(prof) + max(prof)), '\lambda/2', 'FontName', pub_font, 'FontSize', fs - 1, 'Color', red);
    plot(ax1, [0.15 0.15 + 0.31], [-0.17 -0.17], '-', 'Color', red, 'LineWidth', 0.8);
    text(ax1, 0.15 + 0.155, -0.21, '\it{l}_c', 'FontName', pub_font, 'FontSize', fs - 1, 'Color', red, ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'Interpreter', 'tex');
    axis(ax1, 'off'); xlim(ax1, [0 1]); ylim(ax1, [-0.35 0.25]);
    title(ax1, {'Figure error', 'on every surface'}, 'FontName', pub_font, 'FontSize', fs - 1, 'FontWeight', 'normal');

    % inset A2: element 1 split, the rear part offset (exaggerated)
    ax2 = axes('Parent', F.A, 'Position', [0.58 0.05 0.40 0.42]);  hold(ax2, 'on');
    t = linspace(-pi/2, pi/2, 100);
    plot(ax2, 0.55 * cos(t), 0.55 * sin(t), 'k-', 'LineWidth', 1.0);              % outer front
    plot(ax2, 0.30 * cos(t), 0.30 * sin(t), 'k-', 'LineWidth', 1.0);              % inner front
    tb = linspace(pi/2, 3*pi/2, 100);  dy = 0.07;                                   % rear part, offset
    plot(ax2, 0.55 * cos(tb), 0.55 * sin(tb) + dy, 'k-', 'LineWidth', 1.0);
    plot(ax2, 0.30 * cos(tb), 0.30 * sin(tb) + dy, 'k-', 'LineWidth', 1.0);
    plot(ax2, [0 0], [-0.75 0.75], '--', 'Color', red, 'LineWidth', 0.8);          % bonding plane
    plot(ax2, [0.62 0.62], [0 dy], '-', 'Color', red, 'LineWidth', 0.8);
    text(ax2, 0.66, dy / 2, '\lambda/4', 'FontName', pub_font, 'FontSize', fs - 1, 'Color', red);
    axis(ax2, 'equal'); axis(ax2, 'off'); xlim(ax2, [-0.8 0.95]); ylim(ax2, [-0.8 0.8]);
    title(ax2, {'Element 1:', 'two parts'}, 'FontName', pub_font, 'FontSize', fs - 1, 'FontWeight', 'normal');

    %% ================= (B) check 1: lost power vs distance =================
    axC = axes('Parent', F.B, 'Position', [0.20 0.16 0.77 0.80]);  hold(axC, 'on'); box(axC, 'on'); grid(axC, 'on');
    Dg = R.dist_grid_m;  floor_pct = 1e-5;
    for ic = 1:numel(R.mc)
        m = R.mc(ic);  c = cols{min(ic, numel(cols))};
        plot(axC, Dg, max(m.curve_max  * 100, floor_pct), '--', 'Color', c, 'LineWidth', 0.8, 'HandleVisibility', 'off');
        plot(axC, Dg, max(m.curve_mean * 100, floor_pct), '-',  'Color', c, 'LineWidth', 2.0, ...
             'DisplayName', sprintf('l_c = %g mm', m.corr_len_mm));
    end
    plot(axC, [Dg(1) Dg(end)], [0.1 0.1], ':', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.9, 'HandleVisibility', 'off');
    text(axC, 0.6, 0.1, '0.1%', 'FontName', pub_font, 'FontSize', fs - 1, 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center');
    set(axC, 'XScale', 'log', 'YScale', 'log', 'FontName', pub_font, 'FontSize', fs, 'LineWidth', lw_ax, ...
             'GridAlpha', grid_alpha, 'XColor', 'k', 'YColor', 'k', ...
             'XTick', [0.03 0.1 0.3 1 3], 'XTickLabel', {'0.03', '0.1', '0.3', '1', '3'}, ...
             'YTick', [1e-4 1e-3 1e-2 1e-1 1], 'YTickLabel', {'0.0001', '0.001', '0.01', '0.1', '1'}, 'YMinorGrid', 'off');
    xlim(axC, [Dg(1) Dg(end)]);  ylim(axC, [5e-5 1]);
    xlabel(axC, 'Distance D [m, Log scale]', 'FontName', pub_font, 'FontSize', fs_lg);
    ylabel(axC, {'Power Outside the Design', 'Envelope [%, Log scale]'}, 'FontName', pub_font, 'FontSize', fs_lg);
    lg = legend(axC, 'Location', 'northwest', 'FontSize', fs - 1, 'Box', 'off');
    set(lg, 'FontName', pub_font, 'Color', 'none');
    text(axC, Dg(end) * 0.95, 6e-5, {sprintf('Solid: mean, dashed: worst of %d', R.n_trials), sprintf('%s emitter', R.emitter)}, ...
         'FontName', pub_font, 'FontSize', fs - 1, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'Color', [0.45 0.45 0.45]);
    if with_labels
        text(axC, -0.22, 1.03, 'B', 'FontName', pub_font, 'FontSize', fs + 5, 'FontWeight', 'bold', 'Units', 'normalized');
    end

    %% ================= (C) check 2: lost power vs alignment error =================
    axD = axes('Parent', F.C, 'Position', [0.20 0.19 0.77 0.77]);  hold(axD, 'on'); box(axD, 'on'); grid(axD, 'on');
    if isfield(R, 'align_sweep') && ~isempty(R.align_sweep.waves)
        wv = R.align_sweep.waves;  c = [0.55 0.10 0.10];
        plot(axD, wv, max(R.align_sweep.loss(:, end).' * 100, floor_pct), '-o', 'Color', c, 'LineWidth', 2.0, 'MarkerSize', 5, ...
             'MarkerFaceColor', c, 'DisplayName', 'Two parts of element 1');
        spec = R.align_mm / R.lambda_mm;
        plot(axD, [spec spec], [5e-5 1], ':', 'Color', grey, 'LineWidth', 0.9, 'HandleVisibility', 'off');
        text(axD, spec * 1.08, 0.5, {'\lambda/4', 'spec'}, 'FontName', pub_font, 'FontSize', fs - 1, 'Color', grey, 'VerticalAlignment', 'top');
        plot(axD, [wv(1) wv(end)] .* [1/1.3 1.3], [0.1 0.1], ':', 'Color', grey, 'LineWidth', 0.9, 'HandleVisibility', 'off');
        text(axD, wv(1) / 1.2, 0.1, '0.1%', 'FontName', pub_font, 'FontSize', fs - 1, 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left');
        set(axD, 'XScale', 'log', 'YScale', 'log', 'FontName', pub_font, 'FontSize', fs, 'LineWidth', lw_ax, ...
                 'GridAlpha', grid_alpha, 'XColor', 'k', 'YColor', 'k', 'XTick', wv, ...
                 'XTickLabel', arrayfun(@(v) wave_label(v), wv, 'UniformOutput', false), ...
                 'YTick', [1e-4 1e-3 1e-2 1e-1 1], 'YTickLabel', {'0.0001', '0.001', '0.01', '0.1', '1'}, 'YMinorGrid', 'off', 'XMinorGrid', 'off');
        xlim(axD, [wv(1) / 1.3, wv(end) * 1.3]);  ylim(axD, [5e-5 1]);
    else
        text(axD, 0.5, 0.5, 'no alignment sweep', 'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    xlabel(axD, {'Alignment Error of the Two', 'Parts of Element 1 [Log scale]'}, 'FontName', pub_font, 'FontSize', fs_lg);
    ylabel(axD, {'Power Outside the Design', 'Envelope [%, Log scale]'}, 'FontName', pub_font, 'FontSize', fs_lg);
    if with_labels
        text(axD, -0.22, 1.03, 'C', 'FontName', pub_font, 'FontSize', fs + 5, 'FontWeight', 'bold', 'Units', 'normalized');
    end

    if ~with_labels
        for f = [F.A F.B F.C], strip_text(f); end
    end
    drawnow;
end

% ---------------------------------------------------------------------------
function strip_text(f)
% remove every writing from figure f (the _nolabels copy): text objects, axis labels, titles,
% legends and tick labels; the graphics and the axes positions stay as in the labelled copy
    delete(findall(f, 'Type', 'legend'));
    set(findall(f, 'Type', 'text'), 'String', '');          % includes XLabel, YLabel and Title
    set(findall(f, 'Type', 'axes'), 'XTickLabel', {}, 'YTickLabel', {}, 'ZTickLabel', {});
end

% ---------------------------------------------------------------------------
function s = wave_label(v)
% tick label of an alignment error given in waves: lambda, lambda/2, lambda/4, ...
    if abs(v - 1) < 1e-9, s = '\lambda';
    else,                 s = sprintf('\\lambda/%g', round(1 / v));
    end
end

% ---------------------------------------------------------------------------
function pth = trace_one(a0, lens, L)
% [x y angle] along one design ray through the reference lens (legacy first-hit rule)
    P0 = lens.source_pos(:).';  ac = a0;  ni = lens.n1;  no = lens.n2;
    pth = [P0, ac];
    for j = 1:L
        [hit, Ph, an] = sim_first_hit(P0, ac, lens.final_lens{j}, ni, no, 0.05);
        if ~hit, pth = []; return; end
        P0 = Ph; ac = an;  pth = [pth; P0, ac]; %#ok<AGROW>
        t = ni; ni = no; no = t;
    end
end
