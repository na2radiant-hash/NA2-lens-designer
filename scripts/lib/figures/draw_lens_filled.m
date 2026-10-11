function draw_lens_filled(ax, lens, S)
%DRAW_LENS_FILLED  Filled glass crescents + black outline, in the paper style.
%
%   draw_lens_filled(ax, lens, S)
%
%   ax    target axes;  lens  the lens struct (geometry in design units);
%   S     a style_preset struct.
%
%   Ported from StochasticRayTrace.m, "START LIVE PLOTTING" section, in its own
%   draw order:
%     1. one explicit patch per element ("Draw each glass shell" block - element 1
%        closes with a flat cap, elements 2+ with the pointy tangent tip, the
%        2026-08-07 fix that replaced the polyshape subtract),
%     2. glass-cell rectangles (na2_draw_glass.m; the legacy glass-gap script draws
%        them after the fills and before the edges),
%     3. the commercial asphere body, if the design has one,
%     4. white "gap" strokes under every edge, then the glow stroke (sci style only),
%        then the black edges,
%     5. the crescent tip closures, same three strokes.
%
%   Tips come from process/crescent_outline so the fill and the outline close the
%   crescent in exactly the same place. Prescribed spheres (lens.surfaces) are
%   drawn as their exact arc through design_profiles; built layers are unchanged.
%
%   DEVIATION: the source built the fills through polyshape/subtract only for the
%   pre-2026-08-07 path; the explicit-vertex version ported here is the one it
%   actually draws with, and it needs no polyshape.

    if nargin < 3 || isempty(S), S = style_preset('b9e1f0'); end

    GLOW_LW_EXTRA = 1.8;   % StochasticRayTrace: glow stroke width = edgeLW + 1.8

    surfaces = [];  if isfield(lens, 'surfaces'), surfaces = lens.surfaces; end
    final_lens = design_profiles(lens.final_lens, surfaces);
    L = min(lens.L, numel(final_lens));
    n_elements = floor(L / 2);

    % --- crescent tips (process/crescent_outline) -----------------------------
    tip_pts = cell(n_elements, 1);
    caps    = cell(n_elements, 1);
    for e = 1:n_elements
        li = 2*e - 1;  lo = 2*e;
        if lo > L || isempty(final_lens{li}) || isempty(final_lens{lo}), continue; end
        if size(final_lens{li}, 1) < 2 || size(final_lens{lo}, 1) < 2, continue; end
        [tip, cap, pointy] = crescent_outline(final_lens{li}, final_lens{lo}, e);
        caps{e} = cap;
        if pointy, tip_pts{e} = tip; end
    end

    % --- 1. element fills -----------------------------------------------------
    % Polygon per element: outer curve -> tip -> inner curve reversed -> mirrored
    % inner -> mirrored tip -> mirrored outer reversed.
    for j = 2:2:L
        li = j - 1;
        if isempty(final_lens{li}) || isempty(final_lens{j}), continue; end
        up_i = final_lens{li};  lo_i = [up_i(:,1), -up_i(:,2)];
        up_o = final_lens{j};   lo_o = [up_o(:,1), -up_o(:,2)];
        e = j / 2;
        if e <= numel(tip_pts) && ~isempty(tip_pts{e})
            tptf  = tip_pts{e};
            tptfm = [tptf(1), -tptf(2)];
            verts = [up_o; tptf; flipud(up_i); lo_i; tptfm; flipud(lo_o)];
        else
            % element 1 (flat tip): outer -> inner reversed -> mirrored inner -> mirrored outer
            verts = [up_o; flipud(up_i); lo_i; flipud(lo_o)];
        end
        patch(ax, verts(:,1), verts(:,2), S.lensFace, ...
              'FaceAlpha', S.lensAlpha, 'EdgeColor', 'none');
        if ~isempty(S.tintColor)
            patch(ax, verts(:,1), verts(:,2), S.tintColor, ...
                  'FaceAlpha', S.tintAlpha, 'EdgeColor', 'none');
        end
    end

    % --- 2. glass cells (na2_draw_glass.m) ------------------------------------
    draw_glass_cells(ax, lens.glass_info);

    % --- 3. commercial asphere ------------------------------------------------
    if isfield(lens, 'asphere') && ~isempty(lens.asphere) && isstruct(lens.asphere)
        draw_asphere(ax, lens.asphere, S, GLOW_LW_EXTRA);
    end

    % --- 4. white gap strokes, glow, black edges ------------------------------
    if ~isempty(S.gapLW) && S.gapLW > 0
        for j = 1:L
            if isempty(final_lens{j}), continue; end
            up = final_lens{j};  lo = [up(:,1), -up(:,2)];
            plot(ax, up(:,1), up(:,2), 'Color', 'w', 'LineWidth', S.gapLW);
            plot(ax, lo(:,1), lo(:,2), 'Color', 'w', 'LineWidth', S.gapLW);
        end
    end
    for j = 1:L
        if isempty(final_lens{j}), continue; end
        up = final_lens{j};  lo = [up(:,1), -up(:,2)];
        if ~isempty(S.glowColor)
            plot(ax, up(:,1), up(:,2), 'Color', S.glowColor, 'LineWidth', S.edgeLW + GLOW_LW_EXTRA);
            plot(ax, lo(:,1), lo(:,2), 'Color', S.glowColor, 'LineWidth', S.edgeLW + GLOW_LW_EXTRA);
        end
        plot(ax, up(:,1), up(:,2), 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
        plot(ax, lo(:,1), lo(:,2), 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
    end

    % --- 5. crescent tip closures --------------------------------------------
    % Element 1: flat cap between the two tip points. Elements 2+: the polyline
    % inner tip -> pointy tip -> outer tip (the source drew it as two segments).
    for e = 1:n_elements
        cap = caps{e};
        if isempty(cap), continue; end
        capm = [cap(:,1), -cap(:,2)];
        if ~isempty(S.gapLW) && S.gapLW > 0
            plot(ax, cap(:,1),  cap(:,2),  'Color', 'w', 'LineWidth', S.gapLW);
            plot(ax, capm(:,1), capm(:,2), 'Color', 'w', 'LineWidth', S.gapLW);
        end
        if ~isempty(S.glowColor)
            plot(ax, cap(:,1),  cap(:,2),  'Color', S.glowColor, 'LineWidth', S.edgeLW + GLOW_LW_EXTRA);
            plot(ax, capm(:,1), capm(:,2), 'Color', S.glowColor, 'LineWidth', S.edgeLW + GLOW_LW_EXTRA);
        end
        plot(ax, cap(:,1),  cap(:,2),  'Color', S.edgeColor, 'LineWidth', S.edgeLW);
        plot(ax, capm(:,1), capm(:,2), 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
    end
end

% ---------------------------------------------------------------------------
function draw_glass_cells(ax, glass_info)
%DRAW_GLASS_CELLS  Rectangular glass-cell gaps (na2_draw_glass.m, verbatim).
    if isempty(glass_info) || ~isstruct(glass_info) || ~isfield(glass_info, 'gaps'), return; end
    if ~isfield(glass_info, 'enabled') || ~glass_info.enabled, return; end
    glassFace = [0.65 0.85 1.00];  glassEdge = [0.20 0.45 0.75];
    for k = 1:numel(glass_info.gaps)
        g = glass_info.gaps(k);
        if isnan(g.h_glass), continue; end
        xL = g.x_left;  xR = g.x_right;  hG = g.h_glass;
        patch(ax, [xL xR xR xL], [hG hG -hG -hG], glassFace, ...
              'FaceAlpha', 0.25, 'EdgeColor', glassEdge, 'LineWidth', 1.2);
        plot(ax, [xL xL xR xR xL], [hG -hG -hG hG hG], 'Color', glassEdge, 'LineWidth', 1.2);
    end
end

% ---------------------------------------------------------------------------
function draw_asphere(ax, A, S, glow_extra)
%DRAW_ASPHERE  Body of the commercial asphere: fill between S1 and S2, mirrored.
%   S1/S2 are upper-half [x r] polylines running vertex -> rim (construct_two_stage),
%   so the glass body is S1 outward, across the rim, S2 back in - then mirrored.
    if ~isfield(A, 'S1') || ~isfield(A, 'S2') || isempty(A.S1) || isempty(A.S2), return; end
    up = [A.S1; flipud(A.S2)];
    lo = [up(:,1), -up(:,2)];
    verts = [up; flipud(lo)];
    patch(ax, verts(:,1), verts(:,2), S.lensFace, 'FaceAlpha', S.lensAlpha, 'EdgeColor', 'none');
    if ~isempty(S.tintColor)
        patch(ax, verts(:,1), verts(:,2), S.tintColor, 'FaceAlpha', S.tintAlpha, 'EdgeColor', 'none');
    end
    rim = [A.S1(end,:); A.S2(end,:)];                 % flat edge closing the two surfaces
    curves = {A.S1, A.S2, rim};
    for c = 1:numel(curves)
        cu = curves{c};  cm = [cu(:,1), -cu(:,2)];
        if ~isempty(S.gapLW) && S.gapLW > 0
            plot(ax, cu(:,1), cu(:,2), 'Color', 'w', 'LineWidth', S.gapLW);
            plot(ax, cm(:,1), cm(:,2), 'Color', 'w', 'LineWidth', S.gapLW);
        end
        if ~isempty(S.glowColor)
            plot(ax, cu(:,1), cu(:,2), 'Color', S.glowColor, 'LineWidth', S.edgeLW + glow_extra);
            plot(ax, cm(:,1), cm(:,2), 'Color', S.glowColor, 'LineWidth', S.edgeLW + glow_extra);
        end
        plot(ax, cu(:,1), cu(:,2), 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
        plot(ax, cm(:,1), cm(:,2), 'Color', S.edgeColor, 'LineWidth', S.edgeLW);
    end
end
