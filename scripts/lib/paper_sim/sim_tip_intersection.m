function pt = sim_tip_intersection(p1, a1, p2, a2)
%SIM_TIP_INTERSECTION  Crescent-tip point: intersection of two lines given by a point
%   and an angle (degrees). tip_intersection of StochasticRayTrace.m, verbatim.
    if mod(a1,180) == 90
        x = p1(1); m2 = tand(a2); y = m2*(x-p2(1)) + p2(2);
    elseif mod(a2,180) == 90
        x = p2(1); m1 = tand(a1); y = m1*(x-p1(1)) + p1(2);
    else
        m1 = tand(a1); m2 = tand(a2);
        if abs(m1-m2) < 1e-6, pt = [NaN,NaN]; return; end
        x = (p2(2)-p1(2) + m1*p1(1) - m2*p2(1)) / (m1-m2);
        y = m1*(x-p1(1)) + p1(2);
    end
    if abs(x) > 1e6 || abs(y) > 1e6, pt = [NaN,NaN]; return; end
    pt = [x, y];
end
