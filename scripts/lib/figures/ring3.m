function ring3(ax, x, ri, ro, col)
    if ro <= ri, return; end
    th = linspace(0, 2*pi, 80);  rr = [ri; ro];
    surf(ax, x*ones(2,numel(th)), rr*cos(th), rr*sin(th), ...
         'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud');
end
