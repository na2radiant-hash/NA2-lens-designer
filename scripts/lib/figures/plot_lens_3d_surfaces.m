function plot_lens_3d_surfaces(final_lens, layers_count, n_theta, float_mm)
    % Revolves each 2D layer profile around the optical axis and renders it
    % as a topographical dome, analogous to Plotly's go.Surface. Each surface
    % gets its OWN tile: the aperture (radius) spreads across the x-y plane and
    % the optical-axis coordinate becomes height Z, shifted so the dome's
    % lowest point floats float_mm above the plane. Height-mapped colour +
    % a translucent footprint disk at z = 0 make the "floating" read clearly.
    if nargin < 3 || isempty(n_theta), n_theta = 160;  end
    if nargin < 4 || isempty(float_mm), float_mm = 10; end

    theta = linspace(0, 2*pi, n_theta);
    ct = cos(theta);        % 1 x n_theta
    st = sin(theta);

    idx = find(~cellfun(@isempty, final_lens(1:min(layers_count, numel(final_lens)))));
    if isempty(idx), warning('plot_lens_3d_surfaces: no layers to draw.'); return; end

    figure('Name', 'Lens 3D Surfaces (one dome per layer)', 'Color', 'w');
    tl = tiledlayout('flow', 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, 'Constructed Lens — each surface as a dome floating above the x-y plane');

    for j = idx(:).'
        prof = final_lens{j};
        xf = prof(:,1);              % optical-axis coordinate (N x 1)
        r  = abs(prof(:,2));         % radius from the axis     (N x 1)

        zcol = xf - min(xf) + float_mm;      % height, floated above the plane
        X = r * ct;                          % N x n_theta (aperture plane)
        Y = r * st;
        Z = repmat(zcol, 1, n_theta);

        ax = nexttile; hold(ax, 'on');

        % footprint disk on the x-y plane (shows the dome is floating)
        rmax = max(r);
        fill3(ax, rmax*ct, rmax*st, zeros(1, n_theta), [0.5 0.5 0.5], ...
              'FaceAlpha', 0.10, 'EdgeColor', 'none');

        surf(ax, X, Y, Z, Z, 'EdgeColor', 'none', 'FaceAlpha', 0.97, ...
             'FaceLighting', 'gouraud');

        axis(ax, 'tight'); grid(ax, 'on'); box(ax, 'on');
        zlim(ax, [0, max(zcol)]);            % keep the z=0 plane in view
        xlabel(ax, 'X'); ylabel(ax, 'Y'); zlabel(ax, 'Z  (optical axis)');
        elem = ceil(j/2);
        if mod(j,2)==1, side = 'inner'; else, side = 'outer'; end
        title(ax, sprintf('element %d %s (layer %d) — r_{max}=%.1f mm', ...
                          elem, side, j, rmax));
        view(ax, [-40, 25]);
        camlight(ax, 'headlight'); lighting(ax, 'gouraud'); material(ax, 'dull');
        rotate3d(ax, 'on');
    end

    colormap(parula);
    fprintf('3D surface preview drawn (%d domes, %d angular steps, float %.1f mm).\n', ...
            numel(idx), n_theta, float_mm);
end
