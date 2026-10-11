function valid = is_valid_layer(new_layer, final_lens, j)
%IS_VALID_LAYER  True when no segment of new_layer crosses any segment of the layers built so far.
%
%   Same test as the original LensConstructionGradual (check_intersection on every
%   segment pair: denominators below 1e-9 and non-finite points count as "no
%   crossing"), evaluated on all pairs at once instead of in a triple loop. The
%   arithmetic per pair is identical, so the decision is identical; the speed-up
%   is ~1000x, which is what makes construction fast without the symbolic solver.

    valid = true;
    if j == 1, return; end
    P1 = new_layer(1:end-1, :);  P2 = new_layer(2:end, :);
    okP = all(isfinite(P1), 2) & all(isfinite(P2), 2);
    for k = 1:j
        if k > length(final_lens) || isempty(final_lens{k}), continue; end
        prev = final_lens{k};
        Q1 = prev(1:end-1, :);  Q2 = prev(2:end, :);
        okQ = all(isfinite(Q1), 2) & all(isfinite(Q2), 2);
        % denom = (p1x-p2x)(q1y-q2y) - (p1y-p2y)(q1x-q2x)      [n_new x n_prev]
        dpx = P1(:,1) - P2(:,1);  dpy = P1(:,2) - P2(:,2);
        dqx = (Q1(:,1) - Q2(:,1)).';  dqy = (Q1(:,2) - Q2(:,2)).';
        denom = dpx * dqy - dpy * dqx;
        % t = ((p1x-q1x)(q1y-q2y) - (p1y-q1y)(q1x-q2x)) / denom
        ax = P1(:,1) - Q1(:,1).';  ay = P1(:,2) - Q1(:,2).';
        t = (ax .* dqy - ay .* dqx) ./ denom;
        % u = -((p1x-p2x)(p1y-q1y) - (p1y-p2y)(p1x-q1x)) / denom
        u = -(dpx .* ay - dpy .* ax) ./ denom;
        hit = (abs(denom) >= 1e-9) & (t >= 0) & (t <= 1) & (u >= 0) & (u <= 1);
        hit = hit & okP & okQ.';
        if any(hit(:)), valid = false; return; end
    end
end
