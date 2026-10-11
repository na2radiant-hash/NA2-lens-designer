function S = normalise_objlist(v, fields)
%NORMALISE_OBJLIST  Bring a config "list of objects" into one canonical shape.
%
%   S = normalise_objlist(v, fields)
%
%   S is a 1 x N struct array with exactly the fields named in the cellstr
%   FIELDS (in that order). A field an item does not carry is set to []
%   (= JSON null, "not set"); a field that is not in FIELDS is an error,
%   because a typo must not vanish silently.
%
%   Why: jsondecode returns a JSON list of objects in three shapes - [] for an
%   empty list, an N x 1 struct array when every item has the same keys in the
%   same order, and an N x 1 cell array of structs otherwise (JSON null -> []).
%   Consumers of design.element_materials / spherical_surfaces / slope_limits
%   should not care, so this accepts all of them (plus a scalar struct) and
%   returns one shape. Idempotent: normalise_objlist(S, fields) is S again.

    if ischar(fields), fields = {fields}; end
    fields = fields(:).';
    nf = numel(fields);

    % the items as a 1 x N cell of scalar structs, whatever came in
    if isstruct(v)
        items = num2cell(v(:).');          % struct array or scalar struct
    elseif iscell(v)
        items = v(:).';                    % cell of structs
    elseif isnumeric(v) && isempty(v)
        items = {};                        % [] / JSON null / empty list
    else
        error('normalise_objlist:type', ...
              'expected [] / a struct array / a cell array of structs, got a %s', class(v));
    end

    % prototype item: every declared field, all empty
    proto = struct();
    for f = 1:nf, proto.(fields{f}) = []; end

    S = repmat(proto, 1, numel(items));    % 1 x 0 with the right fields when empty
    for k = 1:numel(items)
        it = items{k};
        if ~isstruct(it) || numel(it) ~= 1
            error('normalise_objlist:item', 'item %d is not an object (got a %s)', k, class(it));
        end
        extra = setdiff(fieldnames(it), fields);
        if ~isempty(extra)
            error('normalise_objlist:field', 'item %d has an unknown field "%s" (allowed: %s)', ...
                  k, extra{1}, strjoin(fields, ', '));
        end
        for f = 1:nf
            if isfield(it, fields{f}), S(k).(fields{f}) = it.(fields{f}); end
        end
    end
end
