function [tip, cap, pointy] = crescent_outline(inner, outer, elem)
%CRESCENT_OUTLINE  How an element's crescent is closed at its tip (same rule as the drawings).
%
%   [tip, cap, pointy] = crescent_outline(inner, outer, elem)
%
%   Element 1: flat cap between the two tip end points (pointy = false, tip = []).
%   Outer elements: pointy tip = intersection of the two end tangents; cap is
%   [inner end; tip; outer end] (falls back to the flat cap if the tangents are
%   parallel). inner/outer are [x r] polylines vertex -> tip.

    p1 = inner(end, :);  p2 = outer(end, :);
    tip = [];  pointy = false;
    if elem > 1 && size(inner, 1) > 1 && size(outer, 1) > 1
        a1 = atan2d(p1(2) - inner(end-1, 2), p1(1) - inner(end-1, 1));
        a2 = atan2d(p2(2) - outer(end-1, 2), p2(1) - outer(end-1, 1));
        t = find_intersection(p1, a1, p2, a2);
        if ~any(isnan(t)), tip = t; pointy = true; end
    end
    if pointy, cap = [p1; tip; p2]; else, cap = [p1; p2]; end
end
