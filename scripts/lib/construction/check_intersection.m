function intersects = check_intersection(p1, p2, q1, q2)
    intersects = false;
    if any(isinf(p1)) || any(isnan(p1)) || any(isinf(p2)) || any(isnan(p2)) || ...
       any(isinf(q1)) || any(isnan(q1)) || any(isinf(q2)) || any(isnan(q2))
        return;
    end
    denom = (p1(1) - p2(1)) * (q1(2) - q2(2)) - (p1(2) - p2(2)) * (q1(1) - q2(1));
    if abs(denom) < 1e-9, return; end
    t = ((p1(1) - q1(1)) * (q1(2) - q2(2)) - (p1(2) - q1(2)) * (q1(1) - q2(1))) / denom;
    u = -((p1(1) - p2(1)) * (p1(2) - q1(2)) - (p1(2) - p2(2)) * (p1(1) - q1(1))) / denom;
    intersects = (t >= 0 && t <= 1 && u >= 0 && u <= 1);
end
