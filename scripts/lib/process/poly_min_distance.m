function [dmin, Pa, Pb] = poly_min_distance(A, B)
%POLY_MIN_DISTANCE  Minimum distance between two polylines (vertices of one to segments of the other, both ways).
%
%   [dmin, Pa, Pb] = poly_min_distance(A, B)   A, B: [N x 2]. Pa on A, Pb on B.

    dmin = inf; Pa = [NaN NaN]; Pb = [NaN NaN];
    [d1, p1, q1] = pts_to_segments(A, B);
    [d2, p2, q2] = pts_to_segments(B, A);
    if d1 <= d2, dmin = d1; Pa = p1; Pb = q1; else, dmin = d2; Pa = q2; Pb = p2; end
end

function [dmin, P, Q] = pts_to_segments(A, B)
    % nearest distance from any vertex of A to any segment of B
    dmin = inf; P = [NaN NaN]; Q = [NaN NaN];
    if size(B, 1) < 2
        for i = 1:size(A, 1)
            d = hypot(A(i,1) - B(1,1), A(i,2) - B(1,2));
            if d < dmin, dmin = d; P = A(i,:); Q = B(1,:); end
        end
        return;
    end
    S  = B(2:end, :) - B(1:end-1, :);
    L2 = sum(S.^2, 2);  L2(L2 == 0) = eps;
    for i = 1:size(A, 1)
        W = A(i, :) - B(1:end-1, :);
        t = max(0, min(1, sum(W .* S, 2) ./ L2));
        C = B(1:end-1, :) + S .* t;
        d = hypot(A(i,1) - C(:,1), A(i,2) - C(:,2));
        [dm, k] = min(d);
        if dm < dmin, dmin = dm; P = A(i,:); Q = C(k,:); end
    end
end
