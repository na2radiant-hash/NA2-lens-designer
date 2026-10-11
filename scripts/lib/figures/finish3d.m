function finish3d(ax, ttl)
    axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
    xlabel(ax, 'optical axis (mm)'); ylabel(ax, 'y (mm)'); zlabel(ax, 'z (mm)');
    title(ax, ttl);
    view(ax, 3); camlight(ax, 'headlight'); lighting(ax, 'gouraud');
    material(ax, 'dull'); rotate3d(ax, 'on');
end
