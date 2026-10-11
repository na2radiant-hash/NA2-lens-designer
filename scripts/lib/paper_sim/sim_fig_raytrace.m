function figs = sim_fig_raytrace(lens, N_rays, views, zoom_half, C, opts)
%SIM_FIG_RAYTRACE  Paper ray-trace panels (Fig 1A zoom, Fig 1B full view, Fig 2C).
%
%   figs = sim_fig_raytrace(lens, N_rays, views, zoom_half, C, opts)
%     lens       struct from sim_build_lens (final_lens, n1, n2, L, source_pos)
%     N_rays     drawn rays in the upper half (mirrored below the axis)
%     views      cell of 'regular' and/or 'zoom'
%     zoom_half  zoom window half-size [du]; [] = auto-frame the inner 2 elements
%     C          common block (draw_max_deg, draw_eps_deg, auto_max_angle)
%     opts       optional struct:
%                  .ray_angles     explicit emission angles [deg] of the upper-half rays
%                                  (0 = axis ray, drawn once); replaces N_rays and the
%                                  auto-tuned linspace fan. Angles beyond the marginal
%                                  collimated ray are kept but reported.
%                  .zoom_elements  inner elements framed by the auto zoom window (default 2)
%   figs         struct with one figure handle per requested view
%
%   Port of StochasticRayTrace.m (2026-08-07) for the settings that produced the
%   paper panels: b9e1f0 style, no grid, no heatmap, uniform deterministic fan,
%   uniform ray colour, collimated-output dart arrowheads (full view only),
%   AUTO_MAX_ANGLE, mirror on, no scale bar, no zoom axis indicator.
%   The drawing code is the original's; switches that were off for the paper
%   (other colour styles, grid, heatmap, arrows on air segments) are removed.

    if nargin < 6 || isempty(opts), opts = struct(); end
    final_lens    = lens.final_lens;
    n1_global     = lens.n1;
    n2_global     = lens.n2;
    L             = lens.L;
    origin_global = lens.source_pos(:).';
    draw_mirror   = true;

    % paper style constants (StochasticRayTrace.m, 'b9e1f0', RAY_EMPHASIS_MODE = false)
    EMITTER_COLOR     = [231 99 61]/255;       % #E7633D
    current_ray_color = [0.08 0.20 0.50];      % colors.b9e1f0 - dark-navy rays
    cur_facecol       = [185/255, 225/255, 240/255];   % #b9e1f0
    cur_facealpha     = 1.0;
    cur_edgelw        = 1.2;
    cur_raylw         = 0.80;
    ec                = [0 0 0];
    COLL_ARROW_FRAC   = 0.040;

    L = min(L, numel(final_lens));
    has_points = cellfun(@(c) ~isempty(c) && size(c,1) >= 2, final_lens);
    if ~any(has_points), error('sim_fig_raytrace:empty', 'No usable layers found in final_lens.'); end

    allX   = cell2mat(cellfun(@(c) c(:,1), final_lens(has_points), 'uni', 0));
    xmin   = min(allX);
    xmax   = max(allX);
    x_span = max(1e-9, xmax - xmin);
    x_end  = xmax + 0.30 * x_span;

    %% ---- auto-tune max fan angle: marginal ray through the exact lens edge ----
    uniform_max_angle = C.draw_max_deg;
    if C.auto_max_angle
        if marginal_ray_collimates(uniform_max_angle, L, n1_global, n2_global, origin_global, final_lens)
            fprintf('  AUTO_MAX_ANGLE: %.2f deg already collimates - kept.\n', uniform_max_angle);
        elseif ~marginal_ray_collimates(90, L, n1_global, n2_global, origin_global, final_lens)
            warning('sim_fig_raytrace:autoMax', 'AUTO_MAX_ANGLE: 90-deg probe ray failed - check lens data. Keeping %.2f deg.', uniform_max_angle);
        else
            lo_a = 90;  hi_a = uniform_max_angle;
            for it_bs = 1:44
                mid_a = 0.5*(lo_a + hi_a);
                if marginal_ray_collimates(mid_a, L, n1_global, n2_global, origin_global, final_lens)
                    lo_a = mid_a;
                else
                    hi_a = mid_a;
                end
            end
            fprintf('  AUTO_MAX_ANGLE: marginal collimated ray at %.3f deg (nominal was %.2f) - fan retuned.\n', ...
                    lo_a, uniform_max_angle);
            uniform_max_angle = lo_a;
        end
    end

    %% ---- crescent tips and lens body (y framing) ----
    n_elements = floor(L/2);
    tip_pts = cell(n_elements, 1);
    for e = 1:n_elements
        li  = 2*e - 1;  loe = 2*e;
        if li > L || loe > L || isempty(final_lens{li}) || isempty(final_lens{loe}), continue; end
        if size(final_lens{li},1) < 2 || size(final_lens{loe},1) < 2, continue; end
        p1 = final_lens{li}(end,:);
        a1 = atan2d(p1(2)-final_lens{li}(end-1,2),  p1(1)-final_lens{li}(end-1,1));
        p2 = final_lens{loe}(end,:);
        a2 = atan2d(p2(2)-final_lens{loe}(end-1,2), p2(1)-final_lens{loe}(end-1,1));
        tpt = sim_tip_intersection(p1, a1, p2, a2);
        if ~any(isnan(tpt)), tip_pts{e} = tpt; end
    end
    y_lim_base = lens_body_ymax(final_lens, L, n_elements, tip_pts, has_points);

    if isempty(zoom_half)
        ZOOM_N_ELEMENTS = 2;
        if isfield(opts, 'zoom_elements') && ~isempty(opts.zoom_elements), ZOOM_N_ELEMENTS = opts.zoom_elements; end
        zext = 0;
        for j = 1:min(2*ZOOM_N_ELEMENTS, L)
            if isempty(final_lens{j}), continue; end
            zext = max([zext; abs(final_lens{j}(:,1)); abs(final_lens{j}(:,2))]);
        end
        for e_z = 1:min(ZOOM_N_ELEMENTS, numel(tip_pts))
            if ~isempty(tip_pts{e_z})
                zext = max(zext, max(abs(tip_pts{e_z})));
            end
        end
        zoom_half = 1.08 * zext;
        fprintf('  Auto zoom window: +/- %.2f data units (frames %d inner elements).\n', zoom_half, ZOOM_N_ELEMENTS);
    end

    %% ---- trace the drawn rays ----
    lo = C.draw_eps_deg;  hi = uniform_max_angle - C.draw_eps_deg;
    alphas0 = linspace(lo, hi, N_rays).';
    if isfield(opts, 'ray_angles') && ~isempty(opts.ray_angles)
        alphas0 = opts.ray_angles(:);
        N_rays  = numel(alphas0);
        fprintf('  Drawn rays at [%s] deg (explicit); marginal collimated ray %.2f deg.\n', ...
                num2str(alphas0.', '%.1f '), uniform_max_angle);
        if any(alphas0 > uniform_max_angle)
            warning('sim_fig_raytrace:beyondMarginal', ['ray angle(s) %s deg exceed the marginal collimated ' ...
                    'ray (%.2f deg): they leave through the lens mouth without being collimated.'], ...
                    num2str(alphas0(alphas0 > uniform_max_angle).', '%.1f '), uniform_max_angle);
        end
    end
    all_paths = cell(N_rays, 1);
    for r = 1:N_rays
        P0 = origin_global;  alpha_cur = alphas0(r);
        n_in = n1_global;  n_out = n2_global;
        path = P0;
        for j = 1:L
            if j > numel(final_lens), break; end
            [hit, P_hit, alpha_next] = sim_first_hit(P0, alpha_cur, final_lens{j}, n_in, n_out, 0.05);
            if ~hit, break; end
            path = [path; P_hit]; %#ok<AGROW>
            P0 = P_hit; alpha_cur = alpha_next;
            tmp = n_in; n_in = n_out; n_out = tmp;
        end
        Df = [cosd(alpha_cur), sind(alpha_cur)];
        if abs(Df(1)) > 1e-12
            x_tgt = x_end; if Df(1) < 0, x_tgt = xmin - 0.15*x_span; end
            t_ext = (x_tgt - P0(1)) / Df(1);
            if t_ext > 1e-9
                path = [path; P0 + t_ext * Df]; %#ok<AGROW>
            end
        end
        all_paths{r} = path;
    end

    %% ---- one figure per view ----
    figs = struct();
    for v_idx = 1:numel(views)
        vName = views{v_idx};
        fig = figure('Name', sprintf('N=%d | b9e1f0 | %s | nogrid', N_rays, vName), 'NumberTitle', 'off');
        hold on; axis equal;
        set(fig, 'Units', 'centimeters', 'Position', [2 2 13 9], 'Color', 'w');
        set(gca, 'DataAspectRatio', [1 1 1]);
        set(gca, 'PlotBoxAspectRatio', [1 1 1]);

        % glass fills: explicit per-element polygons
        for j = 2:2:L
            if j == 2
                if isempty(final_lens{1}) || isempty(final_lens{2}), continue; end
                up1 = final_lens{1}; lo1 = [up1(:,1), -up1(:,2)];
                up2 = final_lens{2}; lo2 = [up2(:,1), -up2(:,2)];
                verts = [up2; flipud(up1); lo1; flipud(lo2)];
            else
                e_fill = j/2;
                if isempty(final_lens{j-1}) || isempty(final_lens{j}), continue; end
                up_i = final_lens{j-1};  lo_i = [up_i(:,1), -up_i(:,2)];
                up_o = final_lens{j};    lo_o = [up_o(:,1), -up_o(:,2)];
                if e_fill <= numel(tip_pts) && ~isempty(tip_pts{e_fill})
                    tptf  = tip_pts{e_fill};
                    tptfm = [tptf(1), -tptf(2)];
                    verts = [up_o; tptf; flipud(up_i); lo_i; tptfm; flipud(lo_o)];
                else
                    verts = [up_o; flipud(up_i); lo_i; flipud(lo_o)];
                end
            end
            if strcmp(vName, 'zoom'), parts = cut_to_window(verts, zoom_half); else, parts = {verts}; end
            for k = 1:numel(parts)
                patch(parts{k}(:,1), parts{k}(:,2), cur_facecol, 'FaceAlpha', cur_facealpha, 'EdgeColor', 'none');
            end
        end

        gapLW = cur_edgelw + 3.0;     % white separation under each black edge

        % surface edges: white gap first, then black on top
        for j = 1:L
            if isempty(final_lens{j}), continue; end
            up = final_lens{j}; lo = up; lo(:,2) = -up(:,2);
            plot(up(:,1), up(:,2), 'Color', 'w', 'LineWidth', gapLW);
            if draw_mirror, plot(lo(:,1), lo(:,2), 'Color', 'w', 'LineWidth', gapLW); end
        end
        for j = 1:L
            if isempty(final_lens{j}), continue; end
            up = final_lens{j}; lo = up; lo(:,2) = -up(:,2);
            plot(up(:,1), up(:,2), 'Color', ec, 'LineWidth', cur_edgelw);
            if draw_mirror, plot(lo(:,1), lo(:,2), 'Color', ec, 'LineWidth', cur_edgelw); end
        end

        % element 1: flat tip
        if L >= 2 && ~isempty(final_lens{1}) && ~isempty(final_lens{2})
            p1t = final_lens{1}(end,:);
            p2t = final_lens{2}(end,:);
            plot([p1t(1),p2t(1)],[p1t(2),p2t(2)],'Color','w','LineWidth',gapLW);
            plot([p1t(1),p2t(1)],[p1t(2),p2t(2)],'Color',ec,'LineWidth',cur_edgelw);
            if draw_mirror
                plot([p1t(1),p2t(1)],[-p1t(2),-p2t(2)],'Color','w','LineWidth',gapLW);
                plot([p1t(1),p2t(1)],[-p1t(2),-p2t(2)],'Color',ec,'LineWidth',cur_edgelw);
            end
        end
        % elements 2+: pointy tip via tangent intersection
        for e = 2:n_elements
            if isempty(tip_pts{e}), continue; end
            tpt = tip_pts{e};
            p1  = final_lens{2*e-1}(end,:);
            p2  = final_lens{2*e}(end,:);
            plot([p1(1),tpt(1)],[p1(2),tpt(2)],'Color','w','LineWidth',gapLW);
            plot([p2(1),tpt(1)],[p2(2),tpt(2)],'Color','w','LineWidth',gapLW);
            plot([p1(1),tpt(1)],[p1(2),tpt(2)],'Color',ec,'LineWidth',cur_edgelw);
            plot([p2(1),tpt(1)],[p2(2),tpt(2)],'Color',ec,'LineWidth',cur_edgelw);
            if draw_mirror
                p1m = [p1(1), -p1(2)];  p2m = [p2(1), -p2(2)];  tpb = [tpt(1), -tpt(2)];
                plot([p1m(1),tpb(1)],[p1m(2),tpb(2)],'Color','w','LineWidth',gapLW);
                plot([p2m(1),tpb(1)],[p2m(2),tpb(2)],'Color','w','LineWidth',gapLW);
                plot([p1m(1),tpb(1)],[p1m(2),tpb(2)],'Color',ec,'LineWidth',cur_edgelw);
                plot([p2m(1),tpb(1)],[p2m(2),tpb(2)],'Color',ec,'LineWidth',cur_edgelw);
            end
        end

        % rays (one colour)
        for r = 1:N_rays
            rpath = all_paths{r};
            if size(rpath,1) < 2, continue; end
            plot(rpath(:,1),  rpath(:,2), '-', 'Color', [current_ray_color, 0.75], 'LineWidth', cur_raylw);
            if draw_mirror && max(abs(rpath(:,2))) > 1e-3
                plot(rpath(:,1), -rpath(:,2), '-', 'Color', [current_ray_color, 0.75], 'LineWidth', cur_raylw);
            end
        end

        % collimated-output dart arrowheads - full view only
        if strcmp(vName, 'regular')
            ah_len_c = COLL_ARROW_FRAC * x_span;
            ah_wid_c = 0.28 * ah_len_c;
            ah_back  = 0.75;
            for r = 1:N_rays
                rpath = all_paths{r};
                if size(rpath,1) < 2, continue; end
                P1 = rpath(end-1,:);  P2 = rpath(end,:);
                dseg = P2 - P1;
                if dseg(1) <= 1e-9 || norm(dseg) < 1e-9, continue; end
                if P2(1) < xmax + 0.5*(x_end - xmax), continue; end
                sgn_list = 1;
                if draw_mirror && max(abs(rpath(:,2))) > 1e-3, sgn_list = [1, -1]; end
                for sgn = sgn_list
                    tip  = [P2(1), sgn*P2(2)];
                    dh   = dseg / norm(dseg);  dh = [dh(1), sgn*dh(2)];
                    perp = [-dh(2), dh(1)];
                    bL   = tip - ah_len_c*dh + ah_wid_c*perp;
                    bR   = tip - ah_len_c*dh - ah_wid_c*perp;
                    bC   = tip - ah_back*ah_len_c*dh;
                    fill([tip(1), bL(1), bC(1), bR(1)], [tip(2), bL(2), bC(2), bR(2)], ...
                         current_ray_color, 'EdgeColor', 'none');
                end
            end
        end

        % emitter
        plot(origin_global(1), origin_global(2), 'o', ...
             'MarkerFaceColor', EMITTER_COLOR, 'MarkerEdgeColor', 'none', 'MarkerSize', 5);

        % view limits
        if strcmp(vName, 'zoom')
            xlim([-zoom_half, zoom_half]);
            ylim([-zoom_half, zoom_half]);
        else
            xlim([xmin - 0.1*x_span, x_end + 0.15*x_span]);
            y_ray_max = 0;
            for r_yl = 1:N_rays
                if size(all_paths{r_yl},1) >= 2
                    y_ray_max = max(y_ray_max, max(abs(all_paths{r_yl}(:,2))));
                end
            end
            y_lim_plot = max(y_lim_base, y_ray_max + 0.60*COLL_ARROW_FRAC*x_span);
            ylim([-y_lim_plot, y_lim_plot]);
        end
        grid off;
        set(gca, 'DataAspectRatio', [1 1 1]);
        axis off;
        set(fig, 'Renderer', 'painters');
        drawnow;
        figs.(vName) = fig;
    end
end

% ---------------------------------------------------------------------------
function parts = cut_to_window(verts, half)
% Glass polygon cut to the zoom window +/- half [du]: one vertex list per piece
% ({} = nothing in view). The vector export (PDF / SVG) does not cut a patch
% that crosses the axes limits: it moves every outside vertex onto the window
% border, which leaves thousands of collinear vertices there (one per design
% ray) and some viewers then fill the polygon with white speckle. A polygon
% that is cut here reaches the export with only its corner points on the border.
    parts = {verts};
    if all(abs(verts(:)) <= half), return; end                                % fully in view: unchanged
    if ~(exist('polyshape', 'file') || exist('polyshape', 'class')), return; end   % Octave: uncut, as before
    ws = warning('off', 'MATLAB:polyshape:repairedBySimplify');
    restore = onCleanup(@() warning(ws));
    pg = intersect(polyshape(verts(:,1), verts(:,2), 'Simplify', true), ...
                   polyshape(half*[-1 1 1 -1], half*[-1 -1 1 1]));
    if pg.NumHoles > 0, return; end                                           % not a shell shape: uncut
    parts = arrayfun(@(p) p.Vertices, regions(pg), 'uni', 0);
end

% ---------------------------------------------------------------------------
function y_lim_base = lens_body_ymax(final_lens, L, n_elements, tip_pts, has_points)
% max |y| of the lens body = union of the glass shells (polyshape, as the original).
    y_all = cell2mat(cellfun(@(c) [c(:,2); -c(:,2)], final_lens(has_points), 'uni', 0));
    if exist('polyshape', 'file') || exist('polyshape', 'class')
        layerPoly = cell(L,1);
        for j = 1:L
            if isempty(final_lens{j}), continue; end
            up = final_lens{j}; lo = up; lo(:,2) = -up(:,2);
            e  = ceil(j/2);
            if e <= n_elements && ~isempty(tip_pts{e})
                tpt = tip_pts{e};
                ring = [up; tpt; [tpt(1), -tpt(2)]; flipud(lo)];
            else
                ring = [up; flipud(lo)];
            end
            layerPoly{j} = polyshape(ring(:,1), ring(:,2), 'Simplify', true);
        end
        lensBody = polyshape;
        for j = 2:2:L
            if isempty(layerPoly{j-1}) || isempty(layerPoly{j}), continue; end
            lensBody = union(lensBody, subtract(layerPoly{j}, layerPoly{j-1}));
        end
        if ~isempty(lensBody.Vertices)
            y_lim_base = max(abs([min(lensBody.Vertices(:,2)), max(lensBody.Vertices(:,2))]));
        else
            y_lim_base = max(abs(y_all));        % empty body: surfaces only (as the original)
        end
        return;
    end
    % no polyshape (Octave only): surfaces and crescent tips approximate the body
    for e = 1:numel(tip_pts)
        if ~isempty(tip_pts{e}), y_all = [y_all; tip_pts{e}(2)]; end %#ok<AGROW>
    end
    y_lim_base = max(abs(y_all));
end

% ---------------------------------------------------------------------------
function ok = marginal_ray_collimates(alpha0, L, n1, n2, origin, final_lens)
% TRUE when the ray emitted at alpha0 hits all L surfaces and exits collimated
% (|final angle| < 2 deg). Predicate of AUTO_MAX_ANGLE.
    ok = false;
    P0 = origin;  ac = alpha0;  ni = n1;  no = n2;
    for j = 1:L
        [hit, P_hit, an] = sim_first_hit(P0, ac, final_lens{j}, ni, no, 0.05);
        if ~hit, return; end
        P0 = P_hit;  ac = an;
        t = ni;  ni = no;  no = t;
    end
    ok = abs(sim_wrap180(ac)) < 2;
end

function a = sim_wrap180(a), a = mod(a + 180, 360) - 180; end
