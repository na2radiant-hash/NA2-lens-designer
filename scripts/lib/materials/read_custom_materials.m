function G = read_custom_materials(filename)
%READ_CUSTOM_MATERIALS  Parse custom_materials.json (polymers etc.) into read_agf-style records.
%
%   G = read_custom_materials(filename)
%
%   N x 1 struct array with EXACTLY the fields of read_agf, in the same order, so that
%   material_lookup and materials_table can concatenate both sources and treat a custom
%   material like any catalog glass:
%     name, key, formula, mil, nd, vd, status, status_str, cd, ld_um, tce, density, dPgF,
%     td, it, comment, catalog, maker, file
%   What differs from an AGF record (a hand-written file has less to offer):
%     nd, vd      COMPUTED from the formula at the d/F/C lines (587.5618, 486.1327,
%                 656.2725 nm): there is no reference column to trust, and computing them
%                 makes a typo in a coefficient visible in the report. NaN when range_um
%                 does not cover the three lines.
%     status      5, status_str 'custom' (the AGF status codes stop at 4 = melt)
%     mil         '';  tce, density, dPgF NaN;  td NaN(1,7);  it empty (no transmittance table)
%     comment     source URL and comment joined with ' | '
%     catalog     file name without extension ('custom_materials' for the shipped file, so
%                 'custom_materials:PMMA' disambiguates like 'SCHOTT:N-LASF9')
%     maker       the entry's maker in upper case (package folder tag <MAKER>_<name>_<wl>nm)
%
%   File format: {"_doc": [...], "materials": [{name, maker, formula, coefficients, range_um,
%   source, comment}, ...]}; the _doc block of the file documents every field. name, formula,
%   coefficients and range_um are required; maker defaults to 'CUSTOM', source and comment
%   to ''. Every malformed entry is an error naming the entry: a catalog file must never
%   yield a wrong index silently.

    D_F_C_UM = [587.5618 486.1327 656.2725] / 1000;

    if ~exist(filename, 'file'), error('read_custom_materials:file', 'custom materials file not found: %s', filename); end
    txt = fileread(filename);
    try
        raw = jsondecode(txt);
    catch ME
        error('read_custom_materials:json', '%s is not valid JSON: %s', filename, ME.message);
    end
    if ~isstruct(raw) || numel(raw) ~= 1 || ~isfield(raw, 'materials')
        error('read_custom_materials:format', '%s: the root must be an object with a "materials" array', filename);
    end
    items = raw.materials;
    % jsondecode gives a struct array when every entry has the same keys, a cell otherwise, [] when empty
    if isempty(items)
        items = {};
    elseif isstruct(items)
        items = num2cell(items(:));
    elseif ~iscell(items)
        error('read_custom_materials:format', '%s: "materials" must be an array of objects', filename);
    end

    [~, base] = fileparts(filename);
    empty = struct('name', '', 'key', '', 'formula', NaN, 'mil', '', 'nd', NaN, 'vd', NaN, ...
                   'status', 5, 'status_str', 'custom', 'cd', zeros(1, 10), 'ld_um', [NaN NaN], ...
                   'tce', NaN, 'density', NaN, 'dPgF', NaN, 'td', NaN(1, 7), 'it', zeros(0, 3), ...
                   'comment', '', 'catalog', base, 'maker', 'CUSTOM', 'file', filename);
    G = repmat(empty, 0, 1);
    for i = 1:numel(items)
        e = items{i};
        where = sprintf('%s: materials[%d]', filename, i);
        if ~isstruct(e) || numel(e) ~= 1, error('read_custom_materials:item', '%s must be an object', where); end
        g = empty;
        g.name = req_text(e, 'name', where);
        g.key  = normalise(g.name);
        where = sprintf('%s (%s)', where, g.name);
        mk = opt_text(e, 'maker', where);
        if ~isempty(mk), g.maker = upper(mk); end
        g.formula = req_number(e, 'formula', where);
        if g.formula ~= round(g.formula) || g.formula < 1 || g.formula > 13
            error('read_custom_materials:formula', '%s: formula must be an AGF dispersion formula number 1..13 (see agf_index), got %g', where, g.formula);
        end
        cd = req_vector(e, 'coefficients', where);
        if numel(cd) > 10, error('read_custom_materials:coefficients', '%s: at most 10 coefficients (a CD record), got %d', where, numel(cd)); end
        g.cd(1:numel(cd)) = cd;
        ld = req_vector(e, 'range_um', where);
        if numel(ld) ~= 2 || ld(1) <= 0 || ld(2) <= ld(1)
            error('read_custom_materials:range', '%s: range_um must be [min max] in micrometres with 0 < min < max', where);
        end
        g.ld_um = ld;
        % the formula must at least be evaluable over its own range (catches a sign slip in L1)
        n_ends = agf_index(g.cd, g.formula, g.ld_um);
        if ~isreal(n_ends) || any(~isfinite(n_ends) | n_ends <= 0)     % sqrt of a negative n^2 is complex, not Inf
            error('read_custom_materials:value', '%s: the formula gives an invalid index at the range limits (%g, %g)', where, n_ends(1), n_ends(2));
        end
        % nd / vd like the makers quote them, but from the formula (nothing else to trust)
        if D_F_C_UM(2) >= g.ld_um(1) - 1e-9 && D_F_C_UM(3) <= g.ld_um(2) + 1e-9
            n3 = agf_index(g.cd, g.formula, D_F_C_UM);
            g.nd = n3(1);  g.vd = (n3(1) - 1) / (n3(2) - n3(3));
        end
        parts = {opt_text(e, 'source', where), opt_text(e, 'comment', where)};
        g.comment = strjoin(parts(~cellfun(@isempty, parts)), ' | ');
        if any(strcmp({G.key}, g.key))
            error('read_custom_materials:duplicate', '%s: "%s" is listed twice (names match ignoring case, ''-'', '' '' and ''_'')', filename, g.name);
        end
        G(end+1, 1) = g; %#ok<AGROW>
    end
end

function k = normalise(name)
    % same key as read_agf, so lookups do not care where a material came from
    k = upper(name);
    k = k(k ~= '-' & k ~= ' ' & k ~= '_');
end

function v = req_text(e, f, where)
    if ~isfield(e, f) || ~ischar(e.(f)) || isempty(strtrim(e.(f)))
        error('read_custom_materials:field', '%s: "%s" must be a non-empty string', where, f);
    end
    v = strtrim(e.(f));
end

function v = opt_text(e, f, where)
    v = '';
    if ~isfield(e, f) || isempty(e.(f)), return; end         % absent or JSON null
    if ~ischar(e.(f)), error('read_custom_materials:field', '%s: "%s" must be a string', where, f); end
    v = strtrim(e.(f));
end

function v = req_number(e, f, where)
    if ~isfield(e, f) || ~isnumeric(e.(f)) || numel(e.(f)) ~= 1 || ~isfinite(e.(f))
        error('read_custom_materials:field', '%s: "%s" must be one finite number', where, f);
    end
    v = double(e.(f));
end

function v = req_vector(e, f, where)
    if ~isfield(e, f), error('read_custom_materials:field', '%s: "%s" is missing', where, f); end
    x = e.(f);
    if ~isnumeric(x) || isempty(x) || any(~isfinite(x(:)))
        error('read_custom_materials:field', '%s: "%s" must be a non-empty list of finite numbers', where, f);
    end
    v = double(x(:)).';
end
