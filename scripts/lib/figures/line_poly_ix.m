function P = line_poly_ix(p0, d, poly)
    P = zeros(0, 2);
    for k = 1:size(poly,1)-1
        a = poly(k,:);  s = poly(k+1,:) - a;      % segment a -> a+s
        M = [d(:), -s(:)];
        if abs(det(M)) < 1e-12, continue; end     % parallel
        tu = M \ (a - p0)';                        % [t; u]
        if tu(2) >= -1e-9 && tu(2) <= 1+1e-9       % within the segment
            P(end+1,:) = a + tu(2)*s; %#ok<AGROW>
        end
    end
end
