function [b, f, rc] = split_prof(S, x0)
    % split a profile [x,r] at x = x0: back (x <= x0), front (x >= x0), crossing radii.
    % Both parts contain the crossing point; a vertex exactly on the plane belongs to both.
    b = zeros(0,2);  f = zeros(0,2);  rc = [];
    for k = 1:size(S,1)
        p = S(k,:);
        if p(1) <= x0, b(end+1,:) = p; end %#ok<AGROW>
        if p(1) >= x0, f(end+1,:) = p; end %#ok<AGROW>
        if p(1) == x0, rc(end+1) = abs(p(2)); end %#ok<AGROW>
        if k < size(S,1)
            q = S(k+1,:);
            if (p(1)-x0)*(q(1)-x0) < 0                 % segment crosses x0
                t  = (x0 - p(1)) / (q(1) - p(1));
                cp = p + t*(q - p);
                b(end+1,:) = cp;  f(end+1,:) = cp;  rc(end+1) = abs(cp(2)); %#ok<AGROW>
            end
        end
    end
end
