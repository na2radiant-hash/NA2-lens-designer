function intersection = find_intersection(p1, a1, p2, a2)
    if mod(a1, 180) == 90
        x  = p1(1); m2 = tand(a2); y  = m2 * (x - p2(1)) + p2(2);
    elseif mod(a2, 180) == 90
        x  = p2(1); m1 = tand(a1); y  = m1 * (x - p1(1)) + p1(2);
    else
        m1 = tand(a1); m2 = tand(a2);
        if abs(m1 - m2) < 1e-6, intersection = [NaN, NaN]; return; end
        x = (p2(2) - p1(2) + m1 * p1(1) - m2 * p2(1)) / (m1 - m2);
        y = m1 * (x - p1(1)) + p1(2);
    end
    if abs(x) > 1e6 || abs(y) > 1e6, intersection = [NaN, NaN]; return; end
    intersection = [x, y];
end
