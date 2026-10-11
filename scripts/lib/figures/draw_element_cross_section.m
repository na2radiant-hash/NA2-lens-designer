function draw_element_cross_section(final_lens, elem, scale_mm, out_dir, cut, dmeta, surfaces)
    % Dimensioned 2D cross-section of a single element for vendor RFQs.
    % Inner + outer surfaces are taken from true final_lens coords (correct
    % relative registration), converted design-units -> mm, and drawn in the
    % optical convention (horizontal = optical axis, vertical = radius, both
    % halves shown). Exported as vector PDF + 300-dpi PNG to out_dir.
    % surfaces (optional, lens.surfaces / M.surfaces): a prescribed sphere or a
    % draft clamp on one of this element's two surfaces adds a note line, and the
    % clamped cone is overdrawn in colour so the vendor sees where the draft rules.
    li = 2*elem - 1;  lo = 2*elem;      % inner / outer layer indices
    if lo > numel(final_lens) || isempty(final_lens{li}) || isempty(final_lens{lo})
        warning('draw_element_cross_section: element %d not available.', elem); return;
    end
    if nargin < 3 || isempty(scale_mm), scale_mm = 0.5; end
    if nargin < 5, cut = []; end
    if nargin < 6 || isempty(dmeta), dmeta = default_dmeta(); end
    if nargin < 7, surfaces = []; end
    cut_x0 = NaN;   % set below if a cut is enabled; kept defined for the export log

    inn = final_lens{li} * scale_mm;    % [axial, radius] in mm
    out = final_lens{lo} * scale_mm;

    % geometry (mm)
    r_out   = max(abs(out(:,2)));                 % overall radius = widest of outer surface
    r_mouth = abs(inn(end,2));                    % radius at inner-surface tip = cavity mouth
    x_all   = [inn(:,1); out(:,1)];
    L       = max(x_all) - min(x_all);            % overall axial length
    x_split_i = inn(abs(inn(:,2))==max(abs(inn(:,2))),1); x_split_i = x_split_i(1); % inner equator
    x_split_o = out(abs(out(:,2))==max(abs(out(:,2))),1); x_split_o = x_split_o(1); % outer equator

    figure('Name', sprintf('Element %d — RFQ cross-section', elem), 'Color', 'w');
    ax = axes; hold(ax, 'on'); axis(ax, 'equal');

    % surfaces: top (as-is) and mirrored bottom
    plot(ax, inn(:,1),  inn(:,2), 'k', 'LineWidth', 1.8);
    plot(ax, inn(:,1), -inn(:,2), 'k', 'LineWidth', 1.8);
    plot(ax, out(:,1),  out(:,2), 'k', 'LineWidth', 1.8);
    plot(ax, out(:,1), -out(:,2), 'k', 'LineWidth', 1.8);
    % close the crescent tips (top + bottom)
    plot(ax, [inn(end,1) out(end,1)], [ inn(end,2)  out(end,2)], 'k', 'LineWidth', 1.8);
    plot(ax, [inn(end,1) out(end,1)], [-inn(end,2) -out(end,2)], 'k', 'LineWidth', 1.8);
    % prescribed sphere / draft clamp of this element's surfaces (design.spherical_surfaces,
    % design.slope_limits): note lines below; the clamped cone is overdrawn in colour
    [snotes, scols, cones, ccol] = surface_notes({inn, out}, [li lo], surfaces, scale_mm);
    for c = 1:numel(cones)
        plot(ax, cones{c}(:,1),  cones{c}(:,2), '-', 'Color', ccol, 'LineWidth', 2.2);
        plot(ax, cones{c}(:,1), -cones{c}(:,2), '-', 'Color', ccol, 'LineWidth', 2.2);
    end
    % focus marker
    plot(ax, 0, 0, 'r+', 'MarkerSize', 10, 'LineWidth', 1.5);
    text(ax, 0, 0.06, 'focus', 'Color', 'r', 'FontSize', 10, ...
         'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center');

    % optical axis (axis of revolution) — dash-dot centerline
    xr  = [min(x_all) max(x_all)];
    span = xr(2) - xr(1);  pad = 0.14 * span;
    plot(ax, [xr(1)-pad xr(2)+pad], [0 0], '-.', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.8);
    text(ax, xr(2)+pad, 0, 'optical axis ', 'Color', [0.3 0.3 0.3], 'FontSize', 10, ...
         'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');

    % working distance: focus -> inner on-axis vertex
    [~, iv] = min(abs(inn(:,2)));  x_vertex = inn(iv,1);

    % --- dimension callouts (light gray, informational; no extension lines) ---
    dc = [0.15 0.15 0.15];  sz = 0.05 * r_out;  fs = 11;
    dim_line(ax, [xr(1), 1.16*r_out], [xr(2), 1.16*r_out], ...
             sprintf('length %.2f mm', L), 'h', dc, sz, fs);                    % overall length (top)
    dim_line(ax, [xr(2)+0.15*span, -r_out], [xr(2)+0.15*span, r_out], ...
             sprintf('diameter %.2f mm', 2*r_out), 'v', dc, sz, fs);            % overall diameter
    dim_line(ax, [xr(1)-0.15*span, -r_mouth], [xr(1)-0.15*span, r_mouth], ...
             sprintf('mouth dia %.2f mm', 2*r_mouth), 'v', dc, sz, fs);         % cavity mouth diameter
    % working distance: too small to bar-dimension in the throat, so mark it on the
    % axis (ticks at focus & vertex) and lead the label out into the open cavity.
    twd = 0.07;
    plot(ax, [0 0], [-twd twd], '-', 'Color', dc, 'LineWidth', 0.7);                 % tick at focus
    plot(ax, [x_vertex x_vertex], [-twd twd], '-', 'Color', dc, 'LineWidth', 0.7);   % tick at vertex
    plot(ax, [0 x_vertex], [0 0], '-', 'Color', dc, 'LineWidth', 1.2);               % measure on axis
    plot(ax, [0.5*x_vertex -0.70], [0 -0.42], '-', 'Color', dc, 'LineWidth', 0.7);   % short solid leader
    text(ax, -0.76, -0.44, sprintf('WD %.2f mm', x_vertex), 'Color', dc, ...
         'FontSize', fs, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');

    % --- curvature marking: inner cavity radial extent ---
    rin = max(abs(inn(:,2)));
    dim_line(ax, [x_split_i 0], [x_split_i rin], sprintf('r %.2f', rin), 'v', dc, sz, fs);

    grid(ax, 'on'); box(ax, 'on');  set(ax, 'FontSize', 10);
    xlabel(ax, 'optical axis (mm)', 'FontSize', fs);
    ylabel(ax, 'radius (mm)', 'FontSize', fs);
    title(ax, {sprintf('Element %d cross-section  -  %s', elem, dmeta.glass), ...
        sprintf('diameter %.2f mm   |   length %.2f mm   |   cavity mouth %.2f mm   |   working dist %.2f mm', ...
                2*r_out, L, 2*r_mouth, x_vertex)}, 'Interpreter', 'none', 'FontSize', 12);

    % --- notes block: all statements grouped, bottom-left ---
    Rin = vertex_R(inn);
    [wm, dpi] = dmeta_style(dmeta, 300);
    ns = numel(snotes);  dy = 0.04;     % surface notes sit between the note and the vertex radius line
    if ~isempty(wm), text(ax, 0.015, 0.115 + ns*dy, sprintf('%s  (%s)', wm, dmeta.rev), ...
         'Units','normalized', 'Color',[0.65 0 0], 'FontWeight','bold', 'FontSize', 11); end
    text(ax, 0.015, 0.075 + ns*dy, dmeta.note, ...
         'Units','normalized', 'Color',[0.35 0.35 0.35], 'FontSize', 10);
    for i = 1:ns
        text(ax, 0.015, 0.075 + (ns - i)*dy, snotes{i}, ...
             'Units','normalized', 'Color', scols{i}, 'FontSize', 10, 'Interpreter', 'none');
    end
    if isfinite(Rin)
        text(ax, 0.015, 0.035, sprintf('inner cavity vertex radius R \\approx %.2f mm', Rin), ...
             'Units','normalized', 'Color',[0.35 0.35 0.35], 'FontSize', 10);
    end

    % --- cut plane overlay: ONE position variable (cut_x0) feeds the line, the
    %     marked points AND the annotation, so they can never disagree. ---
    if ~isempty(cut) && isfield(cut,'enable') && cut.enable
        cut_x0  = cut.x0;                               % <-- single source of truth
        cut_ang = 0;  if isfield(cut,'angle_deg'), cut_ang = cut.angle_deg; end
        xl = xlim(ax);  yl = ylim(ax);                  % lock frame so the line can't rescale it
        a  = deg2rad(cut_ang);  d = [sin(a) cos(a)];  p0 = [cut_x0, 0];   % plane anchored on axis
        T  = 3*max(diff(xl), diff(yl));
        plot(ax, p0(1)+[-T T]*d(1), p0(2)+[-T T]*d(2), '--', 'Color', [0.85 0 0], 'LineWidth', 2);
        % mark where the cut crosses each surface (inner/outer, top/bottom)
        curves = {[out(:,1) out(:,2)], [out(:,1) -out(:,2)], ...
                  [inn(:,1) inn(:,2)], [inn(:,1) -inn(:,2)]};
        for c = 1:numel(curves)
            Pc = line_poly_ix(p0, d, curves{c});
            if ~isempty(Pc)
                plot(ax, Pc(:,1), Pc(:,2), 'o', 'MarkerFaceColor', [0.85 0 0], ...
                     'MarkerEdgeColor', 'k', 'MarkerSize', 6);
            end
        end
        text(ax, p0(1), yl(2), sprintf(' cut plane at x = %.2f mm (%.0f deg)', cut_x0, cut_ang), ...
             'Color', [0.85 0 0], 'FontSize', 9, ...
             'VerticalAlignment', 'top', 'Interpreter', 'none');
        xlim(ax, xl);  ylim(ax, yl);
    end

    % --- export: vector PDF + 300-dpi PNG via exportgraphics (no UI toolbar) ---
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    fig = gcf;
    set(fig, 'Units', 'inches', 'Position', [1 1 13 9]);   % legible print size
    try, ax.Toolbar.Visible = 'off'; catch, end            % belt-and-braces (exportgraphics omits it anyway)
    drawnow;
    revtag = regexprep(dmeta.rev, '[^A-Za-z0-9]', '');      % 'Rev B' -> 'RevB'
    base   = fullfile(out_dir, sprintf('element%d_cross_section_%s', elem, revtag));
    exportgraphics(fig, [base '.pdf'], 'ContentType', 'vector');
    exportgraphics(fig, [base '.png'], 'Resolution', dpi);

    fprintf(['Cross-section exported: %s(.pdf/.png)\n' ...
             '  Element %d (mm): OD=%.2f, length=%.2f, cavity mouth=%.2f, working dist=%.2f\n' ...
             '  Cut plane at x = %.2f mm\n'], ...
            base, elem, 2*r_out, L, 2*r_mouth, x_vertex, cut_x0);
    for i = 1:ns, fprintf('  %s\n', snotes{i}); end
end

function [notes, cols, cones, clamp_col] = surface_notes(polys, idx, surfaces, scale_mm)
    % Note text + colour per prescribed / clamped surface of this element and the
    % clamped cone polylines (mm) to overdraw in clamp_col; polys{q} is surface
    % idx(q) in mm. A built surface, an empty surfaces array or a legacy lens
    % (no surfaces at all) adds nothing, so the drawing is the old one.
    notes = {};  cols = {};  cones = {};
    clamp_col = [0.85 0.33 0.10];  gray = [0.35 0.35 0.35];
    if isempty(surfaces) || ~isstruct(surfaces) || ~isfield(surfaces, 'kind'), return; end
    for q = 1:numel(idx)
        j = idx(q);
        if j > numel(surfaces) || ~ischar(surfaces(j).kind), continue; end
        s = surfaces(j);  P = polys{q};
        if strcmp(s.kind, 'sphere') && numfield(s, 'radius_du')
            cz = NaN;  if numfield(s, 'center_z_du'), cz = s.center_z_du; end
            notes{end+1} = sprintf('S%d: prescribed sphere R = %.3f mm, center x = %.3f mm', ...
                                   j, s.radius_du * scale_mm, cz * scale_mm); %#ok<AGROW>
            cols{end+1} = gray; %#ok<AGROW>
        elseif strcmp(s.kind, 'clamped') && numfield(s, 'max_slope_deg')
            pull = '?';  if isfield(s, 'pull') && ischar(s.pull) && ~isempty(s.pull), pull = s.pull; end
            k = Inf;  if numfield(s, 'first_clamped_ray'), k = s.first_clamped_ray; end
            if isfinite(k) && k >= 1 && size(P, 1) >= 2
                % ray k is the first whose segment (point k -> k+1) runs at the limit (construct_lens),
                % so the cone starts at point k and ends n_clamped rays later (or at the tip)
                i0 = max(1, min(size(P, 1) - 1, round(k)));
                i1 = size(P, 1);
                if numfield(s, 'n_clamped') && s.n_clamped > 0, i1 = min(i1, i0 + round(s.n_clamped)); end
                cones{end+1} = P(i0:i1, :); %#ok<AGROW>
                notes{end+1} = sprintf('S%d: draft %.4g deg from r = %.2f mm (pull %s)', ...
                                       j, s.max_slope_deg, abs(P(i0, 2)), pull); %#ok<AGROW>
            else
                notes{end+1} = sprintf('S%d: draft limit %.4g deg never active (pull %s)', ...
                                       j, s.max_slope_deg, pull); %#ok<AGROW>
            end
            cols{end+1} = clamp_col; %#ok<AGROW>
        end
    end
end

function tf = numfield(s, f)
    % true when s.(f) exists and is a numeric scalar (the surfaces struct array
    % carries every kind's fields, empty where they do not apply)
    tf = isfield(s, f) && isnumeric(s.(f)) && isscalar(s.(f));
end

function [wm, dpi] = dmeta_style(dmeta, dpi_default)
    % watermark text and PNG resolution from dmeta (config), with the legacy defaults
    wm = 'PRELIMINARY - NOT FOR MANUFACTURE';
    if isstruct(dmeta) && isfield(dmeta, 'watermark'), wm = dmeta.watermark; end
    dpi = dpi_default;
    if isstruct(dmeta) && isfield(dmeta, 'png_dpi') && ~isempty(dmeta.png_dpi), dpi = dmeta.png_dpi; end
end
