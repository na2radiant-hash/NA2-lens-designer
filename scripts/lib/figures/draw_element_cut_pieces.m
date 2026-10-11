function draw_element_cut_pieces(final_lens, elem, scale_mm, out_dir, cut, dmeta)
%DRAW_ELEMENT_CUT_PIECES  RFQ drawing of the two pieces the cut plane makes of one element.
%
%   draw_element_cut_pieces(final_lens, elem, scale_mm, out_dir, cut, dmeta)
%
%   Files written to out_dir, all in the style of draw_element_cross_section
%   (fonts, line weights, watermark, run.notes line, title block with material
%   and n, revision stamp):
%     element<k>_cut_pieces_<Rev>.pdf / .png            the sheet: all five panels
%     element<k>_cut_pieces_<Rev>_pieceA.pdf / .png     piece A alone   back piece,  x <= cut
%     element<k>_cut_pieces_<Rev>_pieceB.pdf / .png     piece B alone   front piece, x >= cut
%     element<k>_cut_pieces_<Rev>_assembled.pdf / .png  the two assembled, cut plane dash-dot,
%                                                       surface crossings marked
%     element<k>_cut_pieces_<Rev>_pieceA_3D.png         piece A in 3-D  -- the legacy
%     element<k>_cut_pieces_<Rev>_pieceB_3D.png         piece B in 3-D     plot_cut_pieces_separated
%                                                       panels (outer surface translucent teal,
%                                                       inner opaque amber, cut face grey), which
%                                                       the legacy function only drew on screen
%   Each 2-D piece is dimensioned: axial length, diameter, the flat cut face
%   (an annulus: outer / inner diameter) and the max local surface slope of
%   that piece AFTER the split, per surface (S1 inner / S2 outer) - the number a
%   vendor judges tool access by. Slope convention = the sag table's: surface-
%   normal angle from the optical axis per profile segment, > 90 deg = overhang.
%   The partial segment the plane cuts belongs to both pieces.
%
%   The split is the axis-normal plane at cut.x0, the ONE cut-position variable
%   shared with the cross-section, the sag README and the 3-D split view.
%   cut.angle_deg is drawn on the cross-section only; a non-zero value is noted.

    li = 2*elem - 1;  lo = 2*elem;      % inner / outer layer indices
    if lo > numel(final_lens) || isempty(final_lens{li}) || isempty(final_lens{lo})
        warning('draw_element_cut_pieces: element %d not available.', elem); return;
    end
    if nargin < 3 || isempty(scale_mm), scale_mm = 1; end
    if nargin < 5 || isempty(cut),      cut = struct('enable', true, 'x0', 0, 'angle_deg', 0); end
    if nargin < 6 || isempty(dmeta),    dmeta = default_dmeta(); end
    x0 = 0;       if isfield(cut, 'x0'),        x0 = cut.x0;             end   % single source of truth
    cut_ang = 0;  if isfield(cut, 'angle_deg'), cut_ang = cut.angle_deg; end
    if cut_ang ~= 0
        warning('draw_element_cut_pieces:angle', ...
            'pieces are split on the axis-normal plane at x = %.2f mm; cut.angle_deg = %g is drawn on the cross-section only.', x0, cut_ang);
    end

    %% ---- geometry (mm): the element, its split, per-piece numbers ------------
    G.elem = elem;  G.x0 = x0;  G.cut_ang = cut_ang;
    G.inn = final_lens{li} * scale_mm;    % [axial, radius] in mm, vertex -> tip
    G.out = final_lens{lo} * scale_mm;
    [G.ib, G.ifr, G.riC] = split_prof(G.inn, x0);    % inner: back, front, crossing radii (same helper as the 3-D views)
    [G.ob, G.ofr, G.roC] = split_prof(G.out, x0);    % outer
    G.ri0 = 0;  if ~isempty(G.riC), G.ri0 = G.riC(1); end
    G.ro0 = 0;  if ~isempty(G.roC), G.ro0 = G.roC(1); end
    G.haveA = size(G.ib, 1) >= 2 && size(G.ob, 1) >= 2;
    G.haveB = size(G.ifr, 1) >= 2 && size(G.ofr, 1) >= 2;
    if ~G.haveA || ~G.haveB
        warning('draw_element_cut_pieces:nocut', ...
            'element %d: the cut plane at x = %.2f mm does not divide both surfaces (piece A %d/%d pts, piece B %d/%d pts).', ...
            elem, x0, size(G.ib, 1), size(G.ob, 1), size(G.ifr, 1), size(G.ofr, 1));
    end
    % identical formulas to the cross-section
    G.r_out = max(abs(G.out(:,2)));
    x_all   = [G.inn(:,1); G.out(:,1)];
    G.L     = max(x_all) - min(x_all);
    G.xr    = [min(x_all) max(x_all)];  G.span = G.xr(2) - G.xr(1);
    G.A = piece_numbers(G.ib,  G.ob,  x0, 'back');
    G.B = piece_numbers(G.ifr, G.ofr, x0, 'front');
    G.cutOD = 2*G.ro0;  G.cutID = 2*G.ri0;
    G.polyA = [];  if G.haveA, G.polyA = [G.ib;  flipud(G.ob)];  end   % closed by the cut face
    G.polyB = [];  if G.haveB, G.polyB = [G.ifr; flipud(G.ofr)]; end   % closed along the optical axis

    %% ---- style (draw_element_cross_section + the legacy 3-D views) ------------
    S.lw = 1.8;  S.dc = [0.15 0.15 0.15];  S.sz = 0.05 * G.r_out;  S.fs = 11;  S.fst = 11;
    S.cAxis = [0.3 0.3 0.3];  S.cCut = [0.85 0 0];
    S.tintA = [0.80 0.87 0.96];  S.tintB = [0.98 0.91 0.80];   % pale versions of the split-3D blue / amber
    S.cOut = [0.10 0.72 0.66];  S.cIn = [0.90 0.62 0.22];  S.aOut = 0.45;  S.nt = 140;
    [wm, dpi] = dmeta_style(dmeta, 300);
    T.line1 = sprintf('Element %d cut pieces  -  %s', elem, dmeta.glass);
    T.line2 = sprintf('split-and-bond: the axis-normal cut at x = %.2f mm makes piece A (back, x <= cut) and piece B (front, x >= cut)   |   diameter %.2f mm   |   length %.2f mm', ...
                      x0, 2*G.r_out, G.L);
    T.line2_short = sprintf('cut plane at x = %.2f mm   |   piece A = back (x <= cut), piece B = front (x >= cut)   |   dia %.2f mm   |   length %.2f mm', ...
                            x0, 2*G.r_out, G.L);                 % fits the single-panel page width
    T.wm = wm;  T.rev = dmeta.rev;  T.note = dmeta.note;

    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    revtag = regexprep(dmeta.rev, '[^A-Za-z0-9]', '');      % 'Rev B' -> 'RevB'
    base   = sprintf('element%d_cut_pieces_%s', elem, revtag);
    panels = {@panel_pieceA, @panel_pieceB, @panel_assembled, @(ax, G, S) panel_3d(ax, G, S, 'A'), @(ax, G, S) panel_3d(ax, G, S, 'B')};
    tags   = {'pieceA', 'pieceB', 'assembled', 'pieceA_3D', 'pieceB_3D'};
    fmts   = {{'pdf', 'png'}, {'pdf', 'png'}, {'pdf', 'png'}, {'png'}, {'png'}};

    %% ---- the sheet: five panels ----------------------------------------------
    fig = figure('Name', sprintf('Element %d - RFQ cut pieces', elem), 'Color', 'w');
    set(fig, 'Units', 'inches', 'Position', [1 1 16 10], ...
        'PaperUnits', 'inches', 'PaperPosition', [0 0 16 10], 'PaperSize', [16 10]);
    pos = {[0.045 0.50 0.285 0.30], [0.375 0.50 0.285 0.30], [0.705 0.50 0.285 0.30], ...
           [0.15 0.085 0.32 0.30], [0.55 0.085 0.32 0.30]};
    for k = 1:5
        ax = axes('Parent', fig, 'Position', pos{k});
        panels{k}(ax, G, S);
        try, ax.Toolbar.Visible = 'off'; catch, end
    end
    stamp(fig, T, false);
    drawnow;
    save_fig(fig, base, out_dir, {'pdf', 'png'}, dpi, false);

    %% ---- each panel on its own, same stamps ----------------------------------
    for k = 1:5
        f = figure('Name', sprintf('Element %d - cut pieces: %s', elem, tags{k}), 'Color', 'w');
        set(f, 'Units', 'inches', 'Position', [1 1 10 7.5], ...
            'PaperUnits', 'inches', 'PaperPosition', [0 0 10 7.5], 'PaperSize', [10 7.5]);
        ax = axes('Parent', f, 'Position', [0.11 0.13 0.82 0.62]);
        panels{k}(ax, G, S);
        try, ax.Toolbar.Visible = 'off'; catch, end
        stamp(f, T, true);
        drawnow;
        save_fig(f, [base '_' tags{k}], out_dir, fmts{k}, dpi, false);
        close(f);
    end

    fprintf(['Cut-pieces drawing exported: %s(.pdf/.png) + _pieceA, _pieceB, _assembled (.pdf/.png), _pieceA_3D, _pieceB_3D (.png)\n' ...
             '  Element %d cut at x = %.2f mm: piece A (back) length %.2f, dia %.2f mm | piece B (front) length %.2f, dia %.2f mm\n' ...
             '  cut face OD %.2f / ID %.2f mm | max local slope after split: A S1/S2 %.1f/%.1f deg, B S1/S2 %.1f/%.1f deg\n'], ...
            fullfile(out_dir, base), elem, x0, G.A.len, 2*G.A.rmax, G.B.len, 2*G.B.rmax, G.cutOD, G.cutID, G.A.s1, G.A.s2, G.B.s1, G.B.s2);
end

%% ===========================================================================
%  PANELS (each draws into the axes it is given; used by the sheet and the singles)
%% ===========================================================================
function panel_pieceA(ax, G, S)
    hold(ax, 'on');
    ttl = 'Piece A  -  back piece (x <= cut)';
    if ~G.haveA
        finish2d(ax, G.xr + [-0.1 0.1]*G.span, [-1.2 1.2]*G.r_out, S.fs);
        title(ax, {ttl, 'cut plane does not divide this element'}, 'Interpreter', 'none', 'FontSize', S.fst);
        return;
    end
    A = G.A;
    fill(ax, G.polyA(:,1),  G.polyA(:,2), S.tintA, 'EdgeColor', 'none');
    fill(ax, G.polyA(:,1), -G.polyA(:,2), S.tintA, 'EdgeColor', 'none');
    draw_piece_outline(ax, G.ib, G.ob, [G.x0 G.ri0; G.x0 G.ro0], true, S.lw);
    off = max(0.15*A.len, 0.10*A.rmax);                 % dimension offset: never cramped on a thin piece
    xl = [A.xmin - 2.4*off, G.x0 + 2.4*off];  yl = [-1.36 1.36] * max(A.rmax, 0.3*G.r_out);
    piece_frame(ax, G, S, xl, yl);
    dim_line(ax, [A.xmin, 1.16*A.rmax], [G.x0, 1.16*A.rmax], sprintf('length %.2f mm', A.len), 'h', S.dc, S.sz, S.fs);
    vdim(ax, A.xmin - off, -A.rmax, A.rmax, sprintf('dia %.2f mm', 2*A.rmax), 'left', S.dc, S.sz, S.fs);
    vdim(ax, G.x0 + off, -G.ro0, G.ro0, sprintf('cut face dia %.2f mm', G.cutOD), 'right', S.dc, S.sz, S.fs);
    finish2d(ax, xl, yl, S.fs);
    title(ax, {ttl, dims_line(A, G), slope_line(A)}, 'Interpreter', 'none', 'FontSize', S.fst);
end

function panel_pieceB(ax, G, S)
    hold(ax, 'on');
    ttl = 'Piece B  -  front piece (x >= cut)';
    if ~G.haveB
        finish2d(ax, G.xr + [-0.1 0.1]*G.span, [-1.2 1.2]*G.r_out, S.fs);
        title(ax, {ttl, 'cut plane does not divide this element'}, 'Interpreter', 'none', 'FontSize', S.fst);
        return;
    end
    B = G.B;
    fill(ax, G.polyB(:,1),  G.polyB(:,2), S.tintB, 'EdgeColor', 'none');
    fill(ax, G.polyB(:,1), -G.polyB(:,2), S.tintB, 'EdgeColor', 'none');
    draw_piece_outline(ax, G.ifr, G.ofr, [G.x0 G.ri0; G.x0 G.ro0], false, S.lw);
    off = max(0.15*B.len, 0.10*B.rmax);
    xl = [G.x0 - 2.4*off, B.xmax + 2.4*off];  yl = [-1.36 1.36] * max(B.rmax, 0.3*G.r_out);
    piece_frame(ax, G, S, xl, yl);
    dim_line(ax, [G.x0, 1.16*B.rmax], [B.xmax, 1.16*B.rmax], sprintf('length %.2f mm', B.len), 'h', S.dc, S.sz, S.fs);
    vdim(ax, B.xmax + off, -B.rmax, B.rmax, sprintf('dia %.2f mm', 2*B.rmax), 'right', S.dc, S.sz, S.fs);
    vdim(ax, G.x0 - off, -G.ro0, G.ro0, sprintf('cut face dia %.2f mm', G.cutOD), 'left', S.dc, S.sz, S.fs);
    finish2d(ax, xl, yl, S.fs);
    title(ax, {ttl, dims_line(B, G), slope_line(B)}, 'Interpreter', 'none', 'FontSize', S.fst);
end

function panel_assembled(ax, G, S)
    hold(ax, 'on');
    hA = [];  hB = [];
    if G.haveA
        hA = fill(ax, G.polyA(:,1),  G.polyA(:,2), S.tintA, 'EdgeColor', 'none');
        fill(ax, G.polyA(:,1), -G.polyA(:,2), S.tintA, 'EdgeColor', 'none');
    end
    if G.haveB
        hB = fill(ax, G.polyB(:,1),  G.polyB(:,2), S.tintB, 'EdgeColor', 'none');
        fill(ax, G.polyB(:,1), -G.polyB(:,2), S.tintB, 'EdgeColor', 'none');
    end
    inn = G.inn;  out = G.out;  lw = S.lw;
    % surfaces: top (as-is) and mirrored bottom; crescent tips closed (cross-section style)
    plot(ax, inn(:,1),  inn(:,2), 'k', 'LineWidth', lw);
    plot(ax, inn(:,1), -inn(:,2), 'k', 'LineWidth', lw);
    plot(ax, out(:,1),  out(:,2), 'k', 'LineWidth', lw);
    plot(ax, out(:,1), -out(:,2), 'k', 'LineWidth', lw);
    plot(ax, [inn(end,1) out(end,1)], [ inn(end,2)  out(end,2)], 'k', 'LineWidth', lw);
    plot(ax, [inn(end,1) out(end,1)], [-inn(end,2) -out(end,2)], 'k', 'LineWidth', lw);
    plot(ax, 0, 0, 'r+', 'MarkerSize', 10, 'LineWidth', 1.5);                              % focus
    text(ax, 0, 0.06, 'focus', 'Color', 'r', 'FontSize', 10, ...
         'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center');
    pad = 0.14 * G.span;
    plot(ax, [G.xr(1)-pad G.xr(2)+pad], [0 0], '-.', 'Color', S.cAxis, 'LineWidth', 0.8);   % optical axis
    text(ax, G.xr(2)+pad, 0, 'optical axis ', 'Color', S.cAxis, 'FontSize', 10, ...
         'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
    xl = [G.xr(1) - 0.20*G.span, G.xr(2) + 0.20*G.span];  yl = [-1.30 1.30] * G.r_out;
    finish2d(ax, xl, yl, S.fs);
    % cut plane: dash-dot through the whole frame, crossings marked (as on the cross-section)
    plot(ax, [G.x0 G.x0], yl, '-.', 'Color', S.cCut, 'LineWidth', 2);
    for rc = [G.riC(:); G.roC(:)].'
        plot(ax, [G.x0 G.x0], [rc -rc], 'o', 'MarkerFaceColor', S.cCut, 'MarkerEdgeColor', 'k', 'MarkerSize', 6);
    end
    text(ax, G.x0, yl(1), sprintf(' cut plane at x = %.2f mm (%.0f deg)', G.x0, G.cut_ang), ...
         'Color', S.cCut, 'FontSize', 9, 'VerticalAlignment', 'bottom', 'Interpreter', 'none');
    xlim(ax, xl);  ylim(ax, yl);
    if ~isempty(hA) && ~isempty(hB)
        legend([hA hB], {'A  back piece (x <= cut)', 'B  front piece (x >= cut)'}, 'Location', 'northeast');
    end
    title(ax, {'Assembled  -  the two bonded pieces', ...
        sprintf('cut plane at x = %.2f mm (%.0f deg), surface crossings marked', G.x0, G.cut_ang)}, ...
        'Interpreter', 'none', 'FontSize', S.fst);
end

function panel_3d(ax, G, S, which)
    % the legacy plot_cut_pieces_separated panel: outer translucent, inner opaque, cut face grey
    hold(ax, 'on');
    if which == 'A'
        po = G.ob;  pin = G.ib;  ttl = 'Piece A  -  back piece (x <= cut), 3-D';
    else
        po = G.ofr; pin = G.ifr; ttl = 'Piece B  -  front piece (x >= cut), 3-D';
    end
    revsurf(ax, po,  S.nt, S.cOut, S.aOut);
    revsurf(ax, pin, S.nt, S.cIn, 1.0);
    ring3(ax, G.x0, G.ri0, G.ro0, [0.6 0.6 0.6]);
    finish3d(ax, ttl);
end

%% ===========================================================================
%  HELPERS
%% ===========================================================================
function stamp(fig, T, short)
    % title block (material and n), watermark with revision, run.notes line - figure level
    line2 = T.line2;  if short, line2 = T.line2_short; end
    annotation(fig, 'textbox', [0.03 0.945 0.94 0.045], 'String', T.line1, ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontSize', 13, 'FontWeight', 'bold', 'Interpreter', 'none', 'Margin', 2);
    annotation(fig, 'textbox', [0.03 0.905 0.94 0.035], 'String', line2, ...
        'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontSize', 11, 'Interpreter', 'none', 'Margin', 2);
    if ~isempty(T.wm)
        annotation(fig, 'textbox', [0.03 0.035 0.94 0.03], 'String', sprintf('%s  (%s)', T.wm, T.rev), ...
            'EdgeColor', 'none', 'Color', [0.65 0 0], 'FontWeight', 'bold', 'FontSize', 11, ...
            'Interpreter', 'none', 'VerticalAlignment', 'middle', 'Margin', 2);
    end
    annotation(fig, 'textbox', [0.03 0.005 0.94 0.03], 'String', T.note, ...
        'EdgeColor', 'none', 'Color', [0.35 0.35 0.35], 'FontSize', 10, ...
        'Interpreter', 'none', 'VerticalAlignment', 'middle', 'Margin', 2);
end

function P = piece_numbers(pin, pou, x0, side)
    % axial extent, max radius and max local slope of one piece (pin/pou = its
    % inner/outer profile portions, cut crossing included)
    xs = [pin(:,1); pou(:,1)];  rs = abs([pin(:,2); pou(:,2)]);
    if isempty(xs), xs = x0; rs = 0; end
    P.xmin = min(xs);  P.xmax = max(xs);  P.rmax = max(rs);
    if strcmp(side, 'back'), P.len = x0 - P.xmin; else, P.len = P.xmax - x0; end
    P.s1 = max_slope_deg(pin);
    P.s2 = max_slope_deg(pou);
end

function s = max_slope_deg(P)
    % surface-normal angle from the optical axis per segment (> 90 = overhang),
    % the sag table / checks convention; NaN when the piece has no segment
    if size(P, 1) < 2, s = NaN; return; end
    x = P(:,1);  r = abs(P(:,2));
    s = max(atan2d(abs(diff(x)), diff(r)));
end

function s = dims_line(P, G)
    s = sprintf('length %.2f mm   |   dia %.2f mm   |   cut face OD %.2f / ID %.2f mm', P.len, 2*P.rmax, G.cutOD, G.cutID);
end

function s = slope_line(P)
    s = sprintf('max local slope after split: S1 inner %.1f deg, S2 outer %.1f deg', P.s1, P.s2);
end

function piece_frame(ax, G, S, xl, yl)
    % optical axis, the cut plane (dash-dot) and the focus when it is in frame
    plot(ax, xl, [0 0], '-.', 'Color', S.cAxis, 'LineWidth', 0.8);
    plot(ax, [G.x0 G.x0], yl, '-.', 'Color', S.cCut, 'LineWidth', 1.0);
    if xl(1) < 0 && xl(2) > 0, plot(ax, 0, 0, 'r+', 'MarkerSize', 10, 'LineWidth', 1.5); end
end

function draw_piece_outline(ax, pin, pou, face, with_cap, lw)
    % black outline of one piece: its part of both surfaces, the flat cut face,
    % and (back piece) the crescent-tip cap; top half and mirrored bottom half
    for sgn = [1 -1]
        plot(ax, pin(:,1), sgn*pin(:,2), 'k', 'LineWidth', lw);
        plot(ax, pou(:,1), sgn*pou(:,2), 'k', 'LineWidth', lw);
        plot(ax, face(:,1), sgn*face(:,2), 'k', 'LineWidth', lw);              % cut face, edge-on
        if with_cap
            plot(ax, [pin(end,1) pou(end,1)], sgn*[pin(end,2) pou(end,2)], 'k', 'LineWidth', lw);
        end
    end
end

function vdim(ax, x, y1, y2, label, side, col, sz, fs)
    % vertical dimension with the same primitives as dim_line('v'), label side chosen
    plot(ax, [x x], [y1 y2], '-', 'Color', col, 'LineWidth', 0.7);
    plot(ax, x+[-sz sz], [y1 y1], '-', 'Color', col, 'LineWidth', 0.7);
    plot(ax, x+[-sz sz], [y2 y2], '-', 'Color', col, 'LineWidth', 0.7);
    if strcmpi(side, 'left'), xo = -0.8*sz; else, xo = 0.8*sz; end
    text(ax, x+xo, 0.5*(y1+y2), label, 'Color', col, 'FontSize', fs, 'Rotation', 90, ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end

function finish2d(ax, xl, yl, fs)
    daspect(ax, [1 1 1]);  xlim(ax, xl);  ylim(ax, yl);
    grid(ax, 'on'); box(ax, 'on');  set(ax, 'FontSize', 10);
    xlabel(ax, 'optical axis (mm)', 'FontSize', fs);
    ylabel(ax, 'radius (mm)', 'FontSize', fs);
end

function [wm, dpi] = dmeta_style(dmeta, dpi_default)
    % watermark text and PNG resolution from dmeta (config), with the legacy defaults
    wm = 'PRELIMINARY - NOT FOR MANUFACTURE';
    if isstruct(dmeta) && isfield(dmeta, 'watermark'), wm = dmeta.watermark; end
    dpi = dpi_default;
    if isstruct(dmeta) && isfield(dmeta, 'png_dpi') && ~isempty(dmeta.png_dpi), dpi = dmeta.png_dpi; end
end
