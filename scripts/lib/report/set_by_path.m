function s = set_by_path(s, path, value)
%SET_BY_PATH  Assign a nested config value by dot-path, with optional list index.
%
%   cfg = set_by_path(cfg, 'design.weights.k_shape', 1.8)
%   cfg = set_by_path(cfg, 'design.spherical_surfaces[1].radius_du', 5)   item 1 (1-based)
%   cfg = set_by_path(cfg, 'design.slope_limits[].max_slope_deg', 87)     every item
%
%   A list segment key[i] / key[] works on a struct array and on a cell array
%   of structs (the two shapes jsondecode gives a JSON list of objects) and,
%   when it is the last segment, on a numeric / logical vector.
%   Errors if a key does not exist, an index is out of range or the list is
%   empty: a typo must not create a new key, and a sweep over an empty list
%   must not silently do nothing.

    parts = strsplit(path, '.');
    s = assign(s, parts, value, '');
end

function s = assign(s, parts, value, sofar)
    % sofar = the part of the path already consumed (for error messages)
    seg = parts{1};
    br = find(seg == '[', 1);
    has_idx = ~isempty(br);
    if has_idx
        key = seg(1:br-1);
        tail = seg(br:end);
        if strcmp(tail, '[]')
            idx = NaN;                                  % NaN = every item
        elseif ~isempty(regexp(tail, '^\[\d+\]$', 'once'))
            idx = str2double(tail(2:end-1));
        else
            error('set_by_path:syntax', 'Bad path segment "%s" (expected key, key[i] or key[])', seg);
        end
    else
        key = seg;
    end
    here = key;
    if ~isempty(sofar), here = [sofar '.' key]; end

    if ~isstruct(s) || ~isscalar(s) || ~isfield(s, key)
        error('set_by_path:missing', 'Config has no key "%s"', here);
    end

    if ~has_idx
        if isscalar(parts)
            s.(key) = value;
        else
            s.(key) = assign(s.(key), parts(2:end), value, here);
        end
        return;
    end

    v = s.(key);
    last = isscalar(parts);                            % this segment is the end of the path
    if isempty(v) && (isnumeric(v) || iscell(v) || isstruct(v))
        % an empty JSON list arrives as [] (0x0 double), a 1-item list as a 1x1
        % struct: both are "lists" here, but there is nothing to set in this one
        error('set_by_path:empty', '"%s" is an empty list: nothing to set for "%s"', here, seg);
    end
    if ~(isstruct(v) || iscell(v) || (last && (isnumeric(v) || islogical(v))))
        error('set_by_path:notlist', '"%s" is not a list (it is a %s), so "%s" cannot be indexed', here, class(v), seg);
    end
    n = numel(v);
    if isnan(idx)
        sel = 1:n;
    elseif idx < 1 || idx > n
        error('set_by_path:range', 'Index %d out of range for "%s" (%d item(s), 1-based)', idx, here, n);
    else
        sel = idx;
    end
    for i = sel
        ipath = sprintf('%s[%d]', here, i);
        if iscell(v)
            if last, v{i} = value; else, v{i} = assign(v{i}, parts(2:end), value, ipath); end
        elseif isstruct(v)
            if last, v(i) = value; else, v(i) = assign(v(i), parts(2:end), value, ipath); end
        else
            v(i) = value;                               % numeric / logical vector, last segment only
        end
    end
    s.(key) = v;
end
