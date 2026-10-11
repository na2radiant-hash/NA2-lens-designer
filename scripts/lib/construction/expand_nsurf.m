function nsurf = expand_nsurf(nsurf, L)
%EXPAND_NSURF  Per-surface (n_in, n_out) table from either a pair [n1 n2] or an [L x 2] list.
%
%   nsurf = expand_nsurf(nsurf, L)
%   [n1 n2]  -> the legacy alternation: odd surfaces [n1 n2] (air -> glass), even [n2 n1]
%   [L x 2]  -> used as given (design.element_materials: one index per element)

    if isempty(nsurf), error('expand_nsurf:empty', 'no refractive indices given'); end
    is_pair = isvector(nsurf) && numel(nsurf) == 2 && (L ~= 2 || size(nsurf, 1) == 1);
    if is_pair
        n1 = nsurf(1);  n2 = nsurf(2);
        nsurf = zeros(L, 2);
        for j = 1:L
            if mod(j, 2) == 1, nsurf(j, :) = [n1, n2]; else, nsurf(j, :) = [n2, n1]; end
        end
    end
    if ~isequal(size(nsurf), [L, 2])
        error('expand_nsurf:size', 'nsurf must be [n1 n2] or an [%d x 2] list of (n_in, n_out) per surface', L);
    end
end
