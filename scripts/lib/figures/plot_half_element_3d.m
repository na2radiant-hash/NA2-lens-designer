function plot_half_element_3d(final_lens, elem, scale_mm)
    % Renders the TOP HALF (y >= 0) of one element in 3D: the piece produced by
    % splitting the solid on the plane through the optical axis. Both surfaces
    % are revolved over theta = 0..pi only, and the flat cut face (the crescent
    % cross-section) is outlined at height 0 so the bond plane is visible.
    if nargin < 3 || isempty(scale_mm), scale_mm = 1; end
    li = 2*elem - 1;  lo = 2*elem;
    if lo > numel(final_lens) || isempty(final_lens{lo})
        warning('plot_half_element_3d: element %d not available.', elem); return;
    end
    inn = final_lens{li} * scale_mm;
    out = final_lens{lo} * scale_mm;

    nt = 90;  th = linspace(0, pi, nt);      % top half only: sin(theta) >= 0
    ct = cos(th);  st = sin(th);

    figure('Name', sprintf('Top-half element %d (3D)', elem), 'Color', 'w');
    ax = axes; hold(ax, 'on');

    % revolved half-surfaces: point = (x, r*cos(th), r*sin(th)); z = r*sin(th) >= 0
    ro = abs(out(:,2));
    surf(ax, repmat(out(:,1),1,nt), ro*ct, ro*st, 'FaceColor', [0.10 0.72 0.66], ...
         'EdgeColor', 'none', 'FaceAlpha', 0.55, 'FaceLighting', 'gouraud');   % outer dome
    ri = abs(inn(:,2));
    surf(ax, repmat(inn(:,1),1,nt), ri*ct, ri*st, 'FaceColor', [0.90 0.62 0.22], ...
         'EdgeColor', 'none', 'FaceAlpha', 1.0, 'FaceLighting', 'gouraud');    % inner cavity

    % flat cut face (bond plane) outlined at z = 0 — the crescent cross-section
    z0 = @(n) zeros(n,1);
    plot3(ax, out(:,1),  out(:,2), z0(size(out,1)), 'k', 'LineWidth', 1.2);
    plot3(ax, out(:,1), -out(:,2), z0(size(out,1)), 'k', 'LineWidth', 1.2);
    plot3(ax, inn(:,1),  inn(:,2), z0(size(inn,1)), 'k', 'LineWidth', 1.2);
    plot3(ax, inn(:,1), -inn(:,2), z0(size(inn,1)), 'k', 'LineWidth', 1.2);
    plot3(ax, [inn(end,1) out(end,1)], [ inn(end,2)  out(end,2)], [0 0], 'k', 'LineWidth', 1.2);
    plot3(ax, [inn(end,1) out(end,1)], [-inn(end,2) -out(end,2)], [0 0], 'k', 'LineWidth', 1.2);
    plot3(ax, 0, 0, 0, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 7);   % focus

    axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
    xlabel(ax, 'optical axis (mm)'); ylabel(ax, 'y (mm)'); zlabel(ax, 'cut height (mm)');
    title(ax, sprintf('Top-half of element %d (y >= 0) - one of two bonded pieces', elem), ...
          'Interpreter', 'none');
    view(ax, [-35, 22]); camlight(ax, 'headlight'); lighting(ax, 'gouraud');
    material(ax, 'dull'); rotate3d(ax, 'on');
    fprintf('3D top-half view drawn for element %d.\n', elem);
end
