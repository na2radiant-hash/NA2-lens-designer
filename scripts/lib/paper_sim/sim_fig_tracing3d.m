function figs = sim_fig_tracing3d(lens, P)
%SIM_FIG_TRACING3D  Paper Fig 1E (2-D rays, no lens) and Fig 1F (3-D revolved rays).
%
%   figs = sim_fig_tracing3d(lens, P)
%     lens  struct from sim_build_lens
%     P     fig1EF block: ray_angles, arrow_segs, n_copies, circles, emitter_r, triad
%   figs.rays2d, figs.rays3d  figure handles
%
%   Port of Tracing3D.m (2026-08-07): the 2-D "rays only" figure (section 5b) and
%   the 3-D figure for one azimuthal copy count with the output-aperture circles
%   (section 6, the variant used in the paper). The 2-D "with lens" figure and the
%   no-circles 3-D copy are not paper panels and are not drawn.

    final_lens    = lens.final_lens;
    n1_global     = lens.n1;
    n2_global     = lens.n2;
    L             = lens.L;
    origin_global = lens.source_pos(:).';

    ray_angles   = P.ray_angles;
    arrow_segs   = P.arrow_segs;
    RAY_ALPHA_3D = 0.85 * ones(1, numel(ray_angles));
    RAY_COLORS   = repmat([1.00 0.15 0.00], numel(ray_angles), 1);   % red
    RAY_ALPHA    = 0.85;
    EMITTER_COLOR = [231 99 61]/255;   % #E7633D
    EMITTER_R     = P.emitter_r;
    TRIAD_ON      = P.triad;

    has_pts = cellfun(@(c) ~isempty(c) && size(c,1)>=2, final_lens);
    allX    = cell2mat(cellfun(@(c) c(:,1), final_lens(has_pts), 'uni', 0));
    xmin    = min(allX);   xmax = max(allX);
    xspan   = max(1e-9, xmax - xmin);
    x_end   = xmax + 0.55 * xspan;

    %% ---- 2-D ray tracing at the specified angles ----
    N_rays  = numel(ray_angles);
    alphas0 = ray_angles(:);
    paths2D = cell(N_rays, 1);
    for ri = 1:N_rays
        alpha_cur = alphas0(ri);
        P0        = origin_global;
        n_in      = n1_global;
        n_out     = n2_global;
        path      = P0;
        survived  = true;
        for j = 1:L
            if j > numel(final_lens), survived = false; break; end
            [hit, P_hit, alpha_next] = sim_first_hit(P0, alpha_cur, final_lens{j}, n_in, n_out, 1e-12);
            if ~hit, survived = false; break; end
            path      = [path; P_hit]; %#ok<AGROW>
            P0        = P_hit;
            alpha_cur = alpha_next;
            tmp = n_in; n_in = n_out; n_out = tmp;
        end
        if survived
            D_exit = [cosd(alpha_cur), sind(alpha_cur)];
            if D_exit(1) > 1e-6
                t_ext = (x_end - P0(1)) / D_exit(1);
                if t_ext > 0
                    path = [path; P0 + t_ext * D_exit]; %#ok<AGROW>
                end
            else
                extend_len = max(50, 0.6 * xspan);
                path = [path; P0 + extend_len * D_exit]; %#ok<AGROW>
            end
        end
        paths2D{ri} = path;
        fprintf('  Ray %d (%.1f deg): survived=%d, path_pts=%d\n', ri, alphas0(ri), survived, size(path,1));
    end

    %% ---- Fig 1E: 2-D rays only ----
    src_col   = EMITTER_COLOR;
    arrow_len = 7;
    arrow_w   = 2.6;

    fig2b = figure('Name','2D Ray Trace (rays only)', 'Units','centimeters', 'Position',[30 26 22 22]);
    set(fig2b, 'Color', 'w');
    ax2b = axes('Parent', fig2b);
    hold(ax2b, 'on');
    for ri = 1:N_rays
        path = paths2D{ri};
        if size(path,1) < 2, continue; end
        ray_col = RAY_COLORS(mod(ri-1, size(RAY_COLORS,1)) + 1, :);
        plot(ax2b, path(:,1),  path(:,2), '-', 'Color',[ray_col, RAY_ALPHA], 'LineWidth',1.5);
        if max(abs(path(:,2))) > 0.5
            plot(ax2b, path(:,1), -path(:,2), '-', 'Color',[ray_col, RAY_ALPHA], 'LineWidth',1.5);
        end
    end
    for ri = 1:N_rays
        path = paths2D{ri};
        if size(path,1) < 2 || ri > numel(arrow_segs), continue; end
        ray_col = RAY_COLORS(mod(ri-1, size(RAY_COLORS,1)) + 1, :);
        for k = arrow_segs{ri}
            if k+1 > size(path,1), continue; end
            sgn_list = 1;
            if max(abs(path(:,2))) > 0.5, sgn_list = [1, -1]; end
            for sgn = sgn_list
                P1 = [path(k,1),   sgn*path(k,2)];
                P2 = [path(k+1,1), sgn*path(k+1,2)];
                d  = P2 - P1;
                if norm(d) < 1.15*arrow_len, continue; end
                dhat = d/norm(d);  perp = [-dhat(2), dhat(1)];
                bL = P2 - arrow_len*dhat + arrow_w*perp;
                bR = P2 - arrow_len*dhat - arrow_w*perp;
                fill(ax2b, [P2(1),bL(1),bR(1)], [P2(2),bL(2),bR(2)], ray_col, 'EdgeColor','none', 'FaceAlpha', RAY_ALPHA);
            end
        end
    end
    plot(ax2b, origin_global(1), origin_global(2), 'o', ...
         'MarkerFaceColor', src_col, 'MarkerEdgeColor','none', 'MarkerSize',5);
    axis(ax2b, 'equal');  axis(ax2b, 'off');
    figs.rays2d = fig2b;

    %% ---- Fig 1F: 3-D, n_copies azimuthal copies, with aperture circles ----
    arrow_seg_3d  = 9;
    arrow_len_3d  = 9;
    arrow_w_3d    = 6.0;
    AZ_VIEW       = -30;
    EL_VIEW       = 18;

    N_c   = P.n_copies;
    phi_c = linspace(0, 360, N_c+1);  phi_c(end) = [];
    add_circles = P.circles;

    fig3 = figure('Name', sprintf('3D - N=%d%s', N_c, repmat(' circles',1,add_circles)), ...
                  'Units','centimeters', 'Position',[2 2 26 18]);
    set(fig3, 'Color', 'w');
    ax3 = axes('Parent', fig3);
    hold(ax3, 'on');
    grid(ax3, 'on');
    set(ax3, 'Color','w', 'XColor','k', 'YColor','k', 'ZColor','k', ...
        'GridColor',[0.75 0.75 0.75], 'GridAlpha',0.5, ...
        'GridLineStyle',':', 'FontSize',10, 'FontName','Times New Roman', ...
        'LineWidth',0.8, 'TickDir','out', 'Box','off', ...
        'XTickLabel',{}, 'YTickLabel',{}, 'ZTickLabel',{}, ...
        'TickLength',[0 0]);
    view(ax3, AZ_VIEW, EL_VIEW);
    set(ax3, 'CameraViewAngle', 9);

    for ri = 1:N_rays
        path = paths2D{ri};
        if size(path,1) < 2, continue; end
        x2d      = path(:,1);
        r2d      = abs(path(:,2));
        ray_col  = RAY_COLORS(mod(ri-1, size(RAY_COLORS,1)) + 1, :);
        alpha_ri = RAY_ALPHA_3D(min(ri, numel(RAY_ALPHA_3D)));
        for ph_deg = phi_c
            Y3 = r2d * cosd(ph_deg);
            Z3 = r2d * sind(ph_deg);
            plot3(ax3, x2d, Y3, Z3, '-', 'Color',[ray_col, alpha_ri], 'LineWidth',1.2);

            k3 = arrow_seg_3d;
            if k3+1 <= numel(x2d)
                dx = x2d(k3+1)-x2d(k3);
                dr = r2d(k3+1)-r2d(k3);
                d3 = [dx, dr*cosd(ph_deg), dr*sind(ph_deg)];
                if norm(d3) > 1e-9
                    dhat3 = d3/norm(d3);
                    e1 = [-dr, dx*cosd(ph_deg), dx*sind(ph_deg)];
                    if norm(e1) < 1e-9, e1 = [0,-sind(ph_deg),cosd(ph_deg)]; end
                    e1 = e1/norm(e1);
                    e2 = cross(dhat3, e1);
                    if norm(e2) > 1e-9, e2 = e2/norm(e2);
                    else, e2 = cross(dhat3,[1,0,0]); e2 = e2/norm(e2); end
                    tip3   = [x2d(k3+1), r2d(k3+1)*cosd(ph_deg), r2d(k3+1)*sind(ph_deg)];
                    base_c = tip3 - arrow_len_3d*dhat3;
                    N_cone = 10;
                    tc = linspace(0, 2*pi, N_cone+1); tc(end) = [];
                    for ci = 1:N_cone
                        ni  = mod(ci,N_cone)+1;
                        bp1 = base_c + arrow_w_3d*(cos(tc(ci))*e1 + sin(tc(ci))*e2);
                        bp2 = base_c + arrow_w_3d*(cos(tc(ni))*e1 + sin(tc(ni))*e2);
                        patch(ax3, [tip3(1),bp1(1),bp2(1)], [tip3(2),bp1(2),bp2(2)], [tip3(3),bp1(3),bp2(3)], ...
                              ray_col, 'EdgeColor','none', 'FaceAlpha',alpha_ri);
                    end
                end
            end
        end
    end

    if add_circles
        for ri = 1:N_rays
            path = paths2D{ri};
            if size(path,1) < 2, continue; end
            x2d = path(:,1);  r2d = abs(path(:,2));
            k3  = arrow_seg_3d;
            if k3+1 > numel(x2d), continue; end
            r_tip = r2d(k3+1);  x_tip = x2d(k3+1);
            if r_tip < 1e-9, continue; end
            th_c = linspace(0, 2*pi, 180);
            plot3(ax3, x_tip*ones(1,180), r_tip*cos(th_c), r_tip*sin(th_c), ...
                  '-', 'Color',[0.75 0.75 0.75], 'LineWidth',1.5);
        end
    end

    % emitter ball
    [sx,sy,sz] = sphere(24);  sphere_r = EMITTER_R;
    surf(ax3, origin_global(1)+sphere_r*sx, origin_global(2)+sphere_r*sy, sphere_r*sz, ...
         'FaceColor',EMITTER_COLOR, 'EdgeColor','none', 'FaceAlpha',1.0, ...
         'AmbientStrength',0.4, 'DiffuseStrength',0.7, 'SpecularStrength',0.5);

    axis(ax3,'tight'); pause(0.01);
    xl = xlim(ax3); yl = ylim(ax3); zl = zlim(ax3);
    xlim(ax3,[xl(1)-0.05*(xl(2)-xl(1)), xl(2)+0.05*(xl(2)-xl(1))]);
    ylim(ax3,[yl(1)-0.15*(yl(2)-yl(1)), yl(2)+0.15*(yl(2)-yl(1))]);
    zlim(ax3,[zl(1)-0.15*(zl(2)-zl(1)), zl(2)+0.15*(zl(2)-zl(1))]);

    % direction triad (data +X -> label z, +Y -> x, +Z -> y)
    if TRIAD_ON
        xl = xlim(ax3); yl = ylim(ax3); zl = zlim(ax3);
        tr_len = 0.10 * (xl(2)-xl(1));
        tr_o   = [xl(1)+0.03*(xl(2)-xl(1)), yl(1)+0.08*(yl(2)-yl(1)), zl(1)+0.06*(zl(2)-zl(1))];
        tr_col = [0.15 0.15 0.15];
        quiver3(ax3, tr_o(1),tr_o(2),tr_o(3), tr_len,0,0, 0, 'Color',tr_col, 'LineWidth',1.3, 'MaxHeadSize',0.8);
        quiver3(ax3, tr_o(1),tr_o(2),tr_o(3), 0,tr_len,0, 0, 'Color',tr_col, 'LineWidth',1.3, 'MaxHeadSize',0.8);
        quiver3(ax3, tr_o(1),tr_o(2),tr_o(3), 0,0,tr_len, 0, 'Color',tr_col, 'LineWidth',1.3, 'MaxHeadSize',0.8);
        text(ax3, tr_o(1)+1.30*tr_len, tr_o(2), tr_o(3), 'z', ...
             'FontName','Times New Roman', 'FontAngle','italic', 'FontSize',12, 'Color',tr_col);
        text(ax3, tr_o(1), tr_o(2)+1.30*tr_len, tr_o(3), 'x', ...
             'FontName','Times New Roman', 'FontAngle','italic', 'FontSize',12, 'Color',tr_col);
        text(ax3, tr_o(1), tr_o(2), tr_o(3)+1.30*tr_len, 'y', ...
             'FontName','Times New Roman', 'FontAngle','italic', 'FontSize',12, 'Color',tr_col);
    end
    figs.rays3d = fig3;
end
