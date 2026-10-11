function fig_coll = sim_fig_collection(lens, targets, with_labels, x_axis)
%SIM_FIG_COLLECTION  Paper Fig 3B (collection efficiency) + Fig 3C (lens with theta_0), one figure.
%
%   fig_coll = sim_fig_collection(lens, targets, with_labels, x_axis)
%     lens         struct from sim_build_lens (the Fig 1A/1B lens)
%     targets      collection levels to mark, e.g. [0.99 0.999]
%     x_axis       'NA'    = x is NA = sin(theta_half), 0..1, theta_0 drawn as the half-angle
%                            from the axis to the upper mouth tip (the published panel,
%                            'v6_NA_log_labeled')
%                  'theta' = theta_0 is the FULL opening angle of the inner lens mouth
%                            (tip to mirrored tip, = 2 x the half-angle): x is theta_0 in
%                            degrees, 0..180, and Fig 3C draws the arc over the whole mouth.
%                            The curve is the same, only the variable is doubled:
%                            phi(theta_0) = (2 - cos^3(theta_0/2) + 3 cos(theta_0/2))/4.
%                            Log y 50-100 % as in the original's 'v3_deg_log' axis, with the
%                            labelled drop-lines of the published panel
%     with_labels  true  = the labelled figure (collection_N<N>.pdf of the original)
%                  false = the label-free copy (collection_N<N>_nolabels.pdf): no tick
%                          labels and no text, for labelling in PowerPoint
%
%   Port of the COMPUTE_COLLECTION block of StochasticRayTrace.m (2026-08-07,
%   FIGURE_VARIANT = 'fig1') for the paper variant fig4_variant = 'v6_NA_log_labeled':
%   left  = analytic dipole collection phi(theta_0) = (2 - cos^3 + 3 cos)/4 vs NA,
%           log y 50-100 %, drop-lines with % and NA labels at the targets;
%   right = the inner crescent zoom of the lens with the theta_0 annotation.
%   The original drew the left axes in its own window and copyobj'd it (the legend
%   stays behind, so the exported figure has none); here it is drawn in place.
%   The label-free copy was a copyobj with tick labels and every text deleted;
%   here the same figure is drawn without them.

    final_lens    = lens.final_lens;
    L             = min(lens.L, numel(final_lens));
    origin_global = lens.source_pos(:).';
    draw_mirror   = true;

    % analytic dipole curve and the target angles
    th_vec        = linspace(0, 180, 4000);
    phi_dip_curve = (2 - cosd(th_vec).^3 + 3*cosd(th_vec)) / 4;
    th_targets = zeros(1, numel(targets));
    for ti = 1:numel(targets)
        th_targets(ti) = interp1(fliplr(phi_dip_curve), fliplr(th_vec), targets(ti), 'linear', NaN);
    end

    % publication style (Science Advances)
    pub_font  = 'Arial';
    pub_fs    = 13;
    pub_fs_lg = 14;
    pub_lw    = 2.5;
    pub_axlw  = 0.9;
    tgt_colors = {[0.00 0.45 0.70], [0.90 0.50 0.00], [0.00 0.60 0.50], [0.50 0.00 0.55]};
    lensColor_hex = '#4A90E2';
    lc = sscanf(lensColor_hex(2:end), '%2x%2x%2x', [1 3]) / 255;
    lens_fill_col = min(lc + 0.35, 1);

    fig_coll = figure('Name', 'Collection Efficiency (Fig 3B/3C)', ...
        'Color', 'w', 'Units', 'centimeters', 'Position', [4 4 26 10]);

    if nargin < 4 || isempty(x_axis), x_axis = 'NA'; end
    use_theta = strcmpi(x_axis, 'theta');
    if ~use_theta && ~strcmpi(x_axis, 'NA')
        error('sim_fig_collection:xAxis', 'x_axis must be ''NA'' or ''theta'' (got ''%s'').', x_axis);
    end

    %% ====== left panel: Fig 3B ======
    ax1 = axes('Parent', fig_coll, 'Position', [0.08, 0.14, 0.38, 0.78]);
    hold on; grid on; box on;
    set(ax1, 'FontSize', pub_fs, 'FontName', pub_font, 'LineWidth', pub_axlw, ...
             'GridAlpha', 0.18, 'XColor', 'k', 'YColor', 'k');
    % th_vec / th_targets are half-angles; 'theta' mode plots the full angle 2*theta
    if use_theta, x_curve = 2*th_vec; else, x_curve = sind(th_vec); end
    plot(x_curve, phi_dip_curve, 'r-', 'LineWidth', pub_lw);
    yfloor = 0.5;  y_pos_lbl = 0.485;
    for ti = 1:numel(targets)
        lv  = targets(ti);
        tht = th_targets(ti);
        if isnan(tht), continue; end
        tc  = tgt_colors{ti};
        if use_theta, x_m = 2*tht; else, x_m = sind(tht); end
        y_m = lv;
        plot([x_m x_m], [yfloor y_m], '--', 'Color', tc, 'LineWidth', 1.0, 'HandleVisibility', 'off');
        plot(x_m, y_m, 'o', 'Color', tc, 'MarkerSize', 11, 'MarkerFaceColor', tc, 'LineWidth', 1.2, 'HandleVisibility', 'off');
        if with_labels
            pct_lbl = sprintf('%g%%', round(lv*1000)/10);
            text(x_m, 0.80, pct_lbl, ...
                 'Color', tc, 'FontWeight', 'bold', 'FontName', pub_font, 'FontSize', pub_fs, ...
                 'VerticalAlignment', 'middle', 'HorizontalAlignment', 'center', ...
                 'BackgroundColor', 'w', 'Margin', 1);
            if use_theta          % degree label of the original's theta variants
                text(x_m, y_pos_lbl, sprintf('$%.1f^\\circ$', x_m), ...
                     'Interpreter', 'latex', 'FontName', pub_font, ...
                     'FontSize', pub_fs-1, 'Color', tc, 'FontWeight', 'bold', ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'Clipping', 'off');
            else
                text(x_m, y_pos_lbl, sprintf('NA=%.2f', x_m), ...
                     'FontName', pub_font, 'FontSize', pub_fs-1, 'Color', tc, ...
                     'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                     'VerticalAlignment', 'top', 'Clipping', 'off');
            end
        end
    end
    if use_theta          % full mouth angle, 0-180 deg (log y of the original's 'v3_deg_log')
        set(ax1, 'XTick', 0:30:180, 'YScale', 'log', ...
                 'YTick', [0.5 0.6 0.7 0.8 0.9 1.0], ...
                 'YTickLabel', {'50%','60%','70%','80%','90%','100%'});
        xlim([0 180]); ylim([0.5 1]);
    else                  % 'v6_NA_log_labeled' axis (published panel)
        set(ax1, 'XTick', 0:0.2:1, 'YScale', 'log', ...
                 'YTick', [0.5 0.6 0.7 0.8 0.9 1.0], ...
                 'YTickLabel', {'50%','60%','70%','80%','90%','100%'});
        xlim([0 1]); ylim([0.5 1]);
    end
    if ~with_labels, set(ax1, 'XTickLabel', {}, 'YTickLabel', {}); end

    %% ====== right panel: Fig 3C ======
    ax2 = axes('Parent', fig_coll, 'Position', [0.54, 0.14, 0.38, 0.78]);
    hold on; axis equal; set(ax2, 'Color', 'w');

    % zoom on both arcs of the first crescent (surfaces 1 & 2)
    j_nonempty = find(~cellfun(@isempty, final_lens));
    j_crescent = j_nonempty(1:min(2, numel(j_nonempty)));
    crescent_pts = cell2mat(cellfun(@(c) [c; c(:,1), -c(:,2)], final_lens(j_crescent), 'uni', false));
    c_xmin = min(crescent_pts(:,1));  c_xmax = max(crescent_pts(:,1));
    c_ymax = max(abs(crescent_pts(:,2)));
    zm_r   = 0.22 * max(c_xmax - c_xmin, 2*c_ymax);

    % 1. glass fills (polyshape shells, as the original; axis limits clip the view)
    draw_glass_shells(final_lens, L, lens_fill_col);

    % 2. lens outlines
    for j = 1:L
        if isempty(final_lens{j}), continue; end
        up = final_lens{j}; lo = [up(:,1), -up(:,2)];
        lw_j = max(1.4 - 0.07*(j-1), 0.7);
        plot(up(:,1), up(:,2), 'k-', 'LineWidth', lw_j);
        if draw_mirror, plot(lo(:,1), lo(:,2), 'k-', 'LineWidth', lw_j); end
    end

    % 3. source
    plot(origin_global(1), origin_global(2), 'o', ...
         'MarkerFaceColor', [0.85 0.10 0.10], 'MarkerEdgeColor', 'none', 'MarkerSize', 6);

    % 4. theta_0 annotation
    %    'NA'    : half-angle, axis line to the upper tip (the published panel)
    %    'theta' : full mouth angle, upper tip to mirrored lower tip, arc through the axis
    ann_col     = [0.80 0.10 0.10];
    ann_lw      = 2.0;
    lens1_upper = final_lens{j_crescent(1)};
    if lens1_upper(1,2) >= lens1_upper(end,2)
        upper_tip = lens1_upper(1,:);
    else
        upper_tip = lens1_upper(end,:);
    end
    dx_t      = upper_tip(1) - origin_global(1);
    dy_t      = upper_tip(2) - origin_global(2);
    tip_angle = atan2(dy_t, dx_t);
    dist_tip  = sqrt(dx_t^2 + dy_t^2);
    arc_r_ann = dist_tip * 0.40;
    if use_theta
        lower_tip = [upper_tip(1), 2*origin_global(2) - upper_tip(2)];   % mirror about the axis
        plot([origin_global(1), upper_tip(1)], [origin_global(2), upper_tip(2)], ...
             '-', 'Color', ann_col, 'LineWidth', ann_lw);
        plot([origin_global(1), lower_tip(1)], [origin_global(2), lower_tip(2)], ...
             '-', 'Color', ann_col, 'LineWidth', ann_lw);
        arc_th = linspace(tip_angle, 2*pi - tip_angle, 240);           % through pi (the axis)
    else
        plot([origin_global(1), origin_global(1) - dist_tip], [origin_global(2), origin_global(2)], ...
             '-', 'Color', ann_col, 'LineWidth', ann_lw);
        plot([origin_global(1), upper_tip(1)], [origin_global(2), upper_tip(2)], ...
             '-', 'Color', ann_col, 'LineWidth', ann_lw);
        arc_th = linspace(tip_angle, pi, 120);
    end
    plot(origin_global(1) + arc_r_ann*cos(arc_th), origin_global(2) + arc_r_ann*sin(arc_th), ...
         '-', 'Color', ann_col, 'LineWidth', ann_lw);
    if with_labels
        mid_th = (arc_th(1) + arc_th(end)) / 2;                      % pi in 'theta' mode
        text(origin_global(1) + arc_r_ann*2.0*cos(mid_th), origin_global(2) + arc_r_ann*2.0*sin(mid_th), ...
             '$\theta_0$', 'Interpreter', 'latex', ...
             'FontSize', pub_fs_lg, 'Color', ann_col, 'FontWeight', 'bold', ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
             'BackgroundColor', 'white', 'EdgeColor', 'none', 'Margin', 2);
    end
    xlim([c_xmin - zm_r, c_xmax + zm_r]);
    ylim([-(c_ymax + zm_r), c_ymax + zm_r]);
    set(ax2, 'XTick', [], 'YTick', [], 'Box', 'on', 'LineWidth', pub_axlw, 'XColor', 'k', 'YColor', 'k');

    set(fig_coll, 'Renderer', 'painters', 'InvertHardcopy', 'off');
    drawnow;
end

% ---------------------------------------------------------------------------
function draw_glass_shells(final_lens, L, fill_col)
% glassShells of StochasticRayTrace.m: element j/2 = layerPoly{j} minus layerPoly{j-1},
% each layer ring closed through its crescent tip.
    n_elements = floor(L/2);
    tip_pts = cell(n_elements, 1);
    for e = 1:n_elements
        li = 2*e - 1;  loe = 2*e;
        if loe > L || isempty(final_lens{li}) || isempty(final_lens{loe}), continue; end
        if size(final_lens{li},1) < 2 || size(final_lens{loe},1) < 2, continue; end
        p1 = final_lens{li}(end,:);
        a1 = atan2d(p1(2)-final_lens{li}(end-1,2),  p1(1)-final_lens{li}(end-1,1));
        p2 = final_lens{loe}(end,:);
        a2 = atan2d(p2(2)-final_lens{loe}(end-1,2), p2(1)-final_lens{loe}(end-1,1));
        tpt = sim_tip_intersection(p1, a1, p2, a2);
        if ~any(isnan(tpt)), tip_pts{e} = tpt; end
    end
    have_polyshape = exist('polyshape', 'file') || exist('polyshape', 'class');
    rings = cell(L, 1);
    for j = 1:L
        if isempty(final_lens{j}), continue; end
        up = final_lens{j}; lo = up; lo(:,2) = -up(:,2);
        e  = ceil(j/2);
        if e <= n_elements && ~isempty(tip_pts{e})
            tpt = tip_pts{e};
            rings{j} = [up; tpt; [tpt(1), -tpt(2)]; flipud(lo)];
        else
            rings{j} = [up; flipud(lo)];
        end
    end
    js = 2:2:L;
    if ~have_polyshape, js = fliplr(js); end    % fallback paints outer elements first
    for j = js
        if isempty(rings{j-1}) || isempty(rings{j}), continue; end
        if have_polyshape
            shell = subtract(polyshape(rings{j}(:,1), rings{j}(:,2), 'Simplify', true), ...
                             polyshape(rings{j-1}(:,1), rings{j-1}(:,2), 'Simplify', true));
            plot(shell, 'FaceColor', fill_col, 'FaceAlpha', 0.80, 'EdgeColor', 'none');
        else
            % no polyshape (Octave only): outer ring then inner ring in white
            patch(rings{j}(:,1), rings{j}(:,2), fill_col, 'FaceAlpha', 0.80, 'EdgeColor', 'none');
            patch(rings{j-1}(:,1), rings{j-1}(:,2), [1 1 1], 'EdgeColor', 'none');
        end
    end
end
