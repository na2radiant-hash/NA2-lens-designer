function revsurf(ax, prof, nt, col, alph)
    if nargin < 5 || isempty(alph), alph = 1; end
    if size(prof,1) < 2, return; end
    th = linspace(0, 2*pi, nt);  r = abs(prof(:,2));
    surf(ax, repmat(prof(:,1),1,nt), r*cos(th), r*sin(th), ...
         'FaceColor', col, 'EdgeColor', 'none', 'FaceAlpha', alph, 'FaceLighting', 'gouraud');
end
