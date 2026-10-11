function n_keys = validate_config(cfg)
%VALIDATE_CONFIG  Check an NA2 run configuration against config_schema.
%
%   n_keys = validate_config(cfg)     (n_keys = number of leaf settings in the schema)
%
%   Errors (with the complete list of problems) when:
%     - a key is present in the config but not in the schema  (typo protection)
%     - a schema key is missing from the config                (no silent defaults)
%     - a value has the wrong type / is outside its enum
%     - an item of a list-of-objects key ('objlist:' leaf) has a missing,
%       unknown or mistyped field (the message names the item, e.g.
%       design.element_materials[2].element)
%     - a value fails a physical range check (see range_checks below)

    S = config_schema();
    n_keys = count_leaves(S);
    problems = {};

    problems = [problems, walk_unknown(cfg, S, '')];
    problems = [problems, walk_schema(S, cfg, '')];
    if isempty(problems)
        problems = [problems, range_checks(cfg)];
    end

    if ~isempty(problems)
        msg = sprintf('Config has %d problem(s):\n', numel(problems));
        for i = 1:numel(problems)
            msg = [msg, sprintf('  %2d. %s\n', i, problems{i})]; %#ok<AGROW>
        end
        error('validate_config:invalid', '%s', msg);
    end
end

% ---------------------------------------------------------------------------
function p = walk_unknown(c, s, prefix)
    % every field of the config must exist in the schema
    p = {};
    if ~isstruct(c), return; end
    fn = fieldnames(c);
    for i = 1:numel(fn)
        key = fn{i};
        path = join_path(prefix, key);
        if ~isfield(s, key)
            p{end+1} = sprintf('unknown key "%s" (typo? not in config_schema)', path); %#ok<AGROW>
        elseif isstruct(s.(key))
            if ~isstruct(c.(key))
                p{end+1} = sprintf('"%s" must be an object with sub-keys', path); %#ok<AGROW>
            else
                p = [p, walk_unknown(c.(key), s.(key), path)]; %#ok<AGROW>
            end
        end
    end
end

function p = walk_schema(s, c, prefix)
    % every schema key must exist in the config, with the right type
    p = {};
    fn = fieldnames(s);
    for i = 1:numel(fn)
        key = fn{i};
        path = join_path(prefix, key);
        if ~isstruct(c) || ~isfield(c, key)
            p{end+1} = sprintf('missing key "%s"', path); %#ok<AGROW>
            continue;
        end
        if isstruct(s.(key))
            if isstruct(c.(key))
                p = [p, walk_schema(s.(key), c.(key), path)]; %#ok<AGROW>
            end
            % (non-struct value for a struct key is reported by walk_unknown)
        else
            err = check_type(c.(key), s.(key), path);
            if iscell(err)
                % objlist: one complete problem string per item field, paths included
                p = [p, err]; %#ok<AGROW>
            elseif ~isempty(err)
                p{end+1} = sprintf('"%s": %s', path, err); %#ok<AGROW>
            end
        end
    end
end

function err = check_type(v, t, path)
    % err = '' when v is a valid value of leaf type t, a message otherwise.
    % For an 'objlist:' leaf err is a cell array of complete problem strings
    % (they must name the item, hence PATH; '' when not given).
    if nargin < 3, path = ''; end
    err = '';
    switch t
        case 'bool'
            if ~(islogical(v) && isscalar(v)), err = 'must be true or false'; end
        case 'num'
            if ~(isnumeric(v) && isscalar(v) && isfinite(v)), err = 'must be a number'; end
        case 'int'
            if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v == round(v)), err = 'must be an integer'; end
        case 'num?'
            if ~(isempty(v) || (isnumeric(v) && isscalar(v) && isfinite(v))), err = 'must be a number or null'; end
        case 'str'
            if ~ischar(v), err = 'must be a string'; end
        case 'str?'
            if ~(isempty(v) || ischar(v)), err = 'must be a string or null'; end
        case 'numvec'
            if ~(isnumeric(v) && (isempty(v) || isvector(v))), err = 'must be a list of numbers (or [])'; end
        case 'strlist'
            ok = ischar(v) || (iscell(v) && all(cellfun(@ischar, v)));
            if ~ok, err = 'must be a string or a list of strings'; end
        otherwise
            if strncmp(t, 'enum:', 5)
                opts = strsplit(t(6:end), '|');
                if ~ischar(v) || ~any(strcmp(v, opts))
                    err = sprintf('must be one of: %s', strjoin(opts, ', '));
                end
            elseif strncmp(t, 'objlist:', 8)
                err = check_objlist(v, t(9:end), path);
            else
                err = sprintf('schema bug: unknown type "%s"', t);
            end
    end
end

function p = check_objlist(v, spec, path)
    % 'objlist:f1=t1,f2=t2,...': [] or a list of objects, every object with
    % exactly the declared fields, each field checked with its own leaf type.
    % jsondecode gives a struct array (same keys in the same order in every
    % item) or a cell of structs, so both are accepted here on the raw value;
    % the semantic checks later use normalise_objlist.
    p = {};
    parts = strsplit(spec, ',');
    fields = cell(1, numel(parts)); types = cell(1, numel(parts));
    for i = 1:numel(parts)
        eq = find(parts{i} == '=', 1);
        fields{i} = parts{i}(1:eq-1);
        types{i}  = parts{i}(eq+1:end);
    end
    if isnumeric(v) && isempty(v)
        return;                                              % [] = feature off
    elseif isstruct(v)
        items = num2cell(v(:).');
    elseif iscell(v) && all(cellfun(@(x) isstruct(x) && isscalar(x), v(:).'))
        items = v(:).';
    else
        p{end+1} = sprintf('"%s": must be [] or a list of objects {%s}', path, strjoin(fields, ', '));
        return;
    end
    for k = 1:numel(items)
        it = items{k};
        ipath = sprintf('%s[%d]', path, k);
        have = fieldnames(it).';
        for f = 1:numel(fields)
            if ~any(strcmp(have, fields{f}))
                p{end+1} = sprintf('missing item field "%s.%s" (every item has: %s; null = not set)', ...
                                   ipath, fields{f}, strjoin(fields, ', ')); %#ok<AGROW>
                continue;
            end
            err = check_type(it.(fields{f}), types{f});
            if ~isempty(err)
                p{end+1} = sprintf('"%s.%s": %s', ipath, fields{f}, err); %#ok<AGROW>
            end
        end
        extra = setdiff(have, fields);
        for f = 1:numel(extra)
            p{end+1} = sprintf('unknown item field "%s.%s" (typo? allowed: %s)', ...
                               ipath, extra{f}, strjoin(fields, ', ')); %#ok<AGROW>
        end
    end
end

function p = range_checks(cfg)
    % physical / logical consistency (only reached when structure and types are fine)
    p = {};
    D = cfg.design;
    has_material = ~isempty(D.material.name);
    if has_material && isempty(strtrim(D.material.name))
        p{end+1} = 'design.material.name must be a glass name or null';
    end
    if ~has_material && isempty(D.n_lens)
        p{end+1} = 'design.n_lens must be a number when design.material.name is null';
    end
    if ~isempty(D.material.wavelength_nm) && (D.material.wavelength_nm < 150 || D.material.wavelength_nm > 20000)
        p{end+1} = 'design.material.wavelength_nm must be in nm (150..20000) or null (= d-line 587.56 nm)';
    end
    if ~isempty(D.n_lens)
        if D.n_lens <= D.n_outside,      p{end+1} = 'design.n_lens must exceed design.n_outside'; end
        if D.n_lens < 1 || D.n_lens > 4, p{end+1} = 'design.n_lens outside 1..4 - is it a refractive index?'; end
    end
    if D.layers_count < 2 || mod(D.layers_count, 2) ~= 0
        p{end+1} = 'design.layers_count must be even and >= 2 (two surfaces per element)';
    end
    if D.rays_count < 3,               p{end+1} = 'design.rays_count must be >= 3'; end
    if D.NA_hole <= 0 || D.NA_hole >= 1, p{end+1} = 'design.NA_hole must be in (0, 1)'; end
    if D.NA_design_margin < 0 || D.NA_hole + D.NA_design_margin >= 1
        p{end+1} = 'design.NA_hole + design.NA_design_margin must stay below 1';
    end
    if ~isempty(D.fan_max_deg_override) && (D.fan_max_deg_override <= 0 || D.fan_max_deg_override > 180)
        p{end+1} = 'design.fan_max_deg_override must be in (0, 180]';
    end
    if D.fan_epsilon_deg < 0,          p{end+1} = 'design.fan_epsilon_deg must be >= 0'; end
    if D.WD_mm <= 0,                   p{end+1} = 'design.WD_mm must be > 0'; end
    if D.collimation_fraction <= 0 || D.collimation_fraction > 1
        p{end+1} = 'design.collimation_fraction must be in (0, 1]';
    end
    W = D.weights;
    if W.J_front < 1,                  p{end+1} = 'design.weights.J_front must be >= 1'; end
    if W.k_shape < 0 || W.base_w <= 0, p{end+1} = 'design.weights: k_shape >= 0 and base_w > 0 required'; end
    if D.solver.jump_size_du <= 0,     p{end+1} = 'design.solver.jump_size_du must be > 0'; end
    if D.solver.max_attempts < 1,      p{end+1} = 'design.solver.max_attempts must be >= 1'; end
    if numel(D.truncation.edge_min_thickness_mm) ~= D.layers_count && D.truncation.enable
        p{end+1} = 'design.truncation.edge_min_thickness_mm needs one value per surface (layers_count)';
    end
    p = [p, objlist_checks(cfg)];
    R = cfg.run;
    if isempty(R.material) && ~has_material
        p{end+1} = 'run.material must be given when design.material.name is null (with a catalog glass it may be null = <MAKER>_<glass>_<wavelength>nm)';
    end
    for nm = {'vendor', 'material'}
        v = R.(nm{1});
        if isempty(v), continue; end
        if isempty(strtrim(v)) || any(v == '/' | v == '\' | v == ':' | v == '*' | v == '?' | v == '"')
            p{end+1} = sprintf('run.%s must be a plain folder name (no slashes, colons or wildcards)', nm{1}); %#ok<AGROW>
        end
    end
    if isempty(strtrim(R.rev)),        p{end+1} = 'run.rev must not be empty'; end
    E = R.elements(:).';
    if isempty(E) || any(E ~= round(E)) || any(E < 1) || any(E > D.layers_count / 2) || numel(unique(E)) ~= numel(E)
        p{end+1} = sprintf('run.elements must be a non-empty list of distinct integers between 1 and %d (layers_count/2)', D.layers_count / 2);
    end
    P = cfg.process;
    if numel(P.cut.x0_mm) ~= 1 && numel(P.cut.x0_mm) ~= numel(E)
        p{end+1} = 'process.cut.x0_mm must be one number or one value per entry of run.elements';
    end
    if P.cut.angle_deg < -90 || P.cut.angle_deg > 90, p{end+1} = 'process.cut.angle_deg must be within +-90'; end
    if P.edge_fillet_mm < 0 || P.tip_truncate_mm < 0, p{end+1} = 'process fillet/truncation must be >= 0'; end
    X = cfg.export;
    if X.sag_step_mm <= 0 || X.xyz_line_spacing_mm <= 0 || X.grid_spacing_mm <= 0
        p{end+1} = 'export step/spacing values must be > 0';
    end
    if mod(X.zemax_n_grid, 2) ~= 1,    p{end+1} = 'export.zemax_n_grid must be odd (centre sample)'; end
    F = cfg.figures.rfq;
    if F.n_theta < 8 || F.png_dpi < 50, p{end+1} = 'figures.rfq: n_theta >= 8 and png_dpi >= 50 required'; end
    T = cfg.trace;
    if T.n_rays < 1,                   p{end+1} = 'trace.n_rays must be >= 1'; end
    if ~isempty(T.max_angle_deg) && (T.max_angle_deg <= T.min_angle_deg || T.max_angle_deg > 180)
        p{end+1} = 'trace.max_angle_deg must exceed min_angle_deg and be <= 180';
    end
    if cfg.checks.bending_budget_tol_deg < 0, p{end+1} = 'checks.bending_budget_tol_deg must be >= 0 (deg)'; end
end

function p = objlist_checks(cfg)
    % semantics of the per-element / per-surface lists (design.element_materials,
    % spherical_surfaces, slope_limits). Item shapes and field types were already
    % checked by check_objlist, so the values can be used directly here.
    p = {};
    D = cfg.design;
    L = D.layers_count;
    nE = L / 2;
    EM = normalise_objlist(D.element_materials,  {'element', 'name', 'n'});
    SS = normalise_objlist(D.spherical_surfaces, {'surface', 'center_z_du', 'radius_du'});
    SL = normalise_objlist(D.slope_limits,       {'surface', 'max_slope_deg', 'pull'});

    % --- element_materials: one material per listed element, given as a name OR an index
    for k = 1:numel(EM)
        it = EM(k);
        ip = sprintf('design.element_materials[%d]', k);
        if it.element < 1 || it.element > nE
            p{end+1} = sprintf('%s.element must be between 1 and %d (layers_count/2)', ip, nE); %#ok<AGROW>
        end
        if ischar(it.name) && isempty(strtrim(it.name))
            p{end+1} = sprintf('%s.name must be a glass name (catalog spelling, or PMMA / PC) or null', ip); %#ok<AGROW>
        end
        has_name = ischar(it.name) && ~isempty(strtrim(it.name));
        has_n    = ~isempty(it.n);
        if has_name == has_n
            p{end+1} = sprintf('%s: set exactly one of name (catalog / custom material) and n (index as written), the other null', ip); %#ok<AGROW>
        end
        if has_n
            if it.n <= D.n_outside,  p{end+1} = sprintf('%s.n must exceed design.n_outside', ip); end %#ok<AGROW>
            if it.n < 1 || it.n > 4, p{end+1} = sprintf('%s.n outside 1..4 - is it a refractive index?', ip); end %#ok<AGROW>
        end
    end
    d = duplicates([EM.element]);
    if ~isempty(d), p{end+1} = sprintf('design.element_materials lists element %d more than once', d(1)); end

    % --- spherical_surfaces: prescribed sphere per surface
    for k = 1:numel(SS)
        it = SS(k);
        ip = sprintf('design.spherical_surfaces[%d]', k);
        if it.surface < 1 || it.surface > L
            p{end+1} = sprintf('%s.surface must be between 1 and %d (layers_count)', ip, L); %#ok<AGROW>
        end
        if it.radius_du <= 0
            p{end+1} = sprintf('%s.radius_du must be > 0 (design units, 1 du = WD_mm)', ip); %#ok<AGROW>
        end
        if it.surface == 1
            % the cavity vertex defines the scale (1 du = WD_mm), so a prescribed S1
            % must pass through it: vertex x = center + radius = 1 (or center null = derived)
            if ~isempty(it.center_z_du) && abs(it.center_z_du + it.radius_du - 1) > 1e-9
                p{end+1} = sprintf(['%s: surface 1 must keep its vertex at 1 du (= WD_mm): center_z_du + radius_du = 1 ' ...
                                    '(got %.6g), or center_z_du null = derived as 1 - radius_du'], ip, it.center_z_du + it.radius_du); %#ok<AGROW>
            end
        elseif isempty(it.center_z_du)
            p{end+1} = sprintf('%s.center_z_du must be a number (null is only derived for surface 1)', ip); %#ok<AGROW>
        end
    end
    d = duplicates([SS.surface]);
    if ~isempty(d), p{end+1} = sprintf('design.spherical_surfaces lists surface %d more than once', d(1)); end

    % --- slope_limits: draft clamp per surface
    for k = 1:numel(SL)
        it = SL(k);
        ip = sprintf('design.slope_limits[%d]', k);
        if it.surface < 1 || it.surface > L
            p{end+1} = sprintf('%s.surface must be between 1 and %d (layers_count)', ip, L); %#ok<AGROW>
        end
        if it.max_slope_deg <= 0 || it.max_slope_deg >= 180
            p{end+1} = sprintf('%s.max_slope_deg must be in (0, 180) (90 = straight wall, 87 = 3 deg draft, > 90 = undercut)', ip); %#ok<AGROW>
        end
    end
    d = duplicates([SL.surface]);
    if ~isempty(d), p{end+1} = sprintf('design.slope_limits lists surface %d more than once', d(1)); end

    % --- conflicts between the lists and with the other construction modes
    both = intersect([SS.surface], [SL.surface]);
    if ~isempty(both)
        p{end+1} = sprintf('surface %d is in both design.spherical_surfaces and design.slope_limits (a surface is prescribed or clamped, not both)', both(1));
    end
    if ~isempty(D.from_mat) && (~isempty(EM) || ~isempty(SS) || ~isempty(SL))
        p{end+1} = 'design.from_mat skips the construction, so design.element_materials, spherical_surfaces and slope_limits must be [] with it';
    end
    CA = D.commercial_asphere;
    if CA.enable && CA.correction.enable && any([[SS.surface], [SL.surface]] == L)
        % Stage 3 of the two-stage build rebuilds the last built surface from
        % scratch, which would silently discard the prescription / clamp on it
        p{end+1} = sprintf('surface %d (layers_count) cannot be in spherical_surfaces / slope_limits while commercial_asphere.correction rebuilds it (Stage 3)', L);
    end
end

function d = duplicates(x)
    % values that occur more than once in the vector x (empty when none)
    x = x(:).';
    d = [];
    if isempty(x), return; end
    d = unique(x(arrayfun(@(t) sum(x == t) > 1, x)));
end

function n = count_leaves(s)
    n = 0;
    fn = fieldnames(s);
    for i = 1:numel(fn)
        if isstruct(s.(fn{i})), n = n + count_leaves(s.(fn{i})); else, n = n + 1; end
    end
end

function s = join_path(prefix, key)
    if isempty(prefix), s = key; else, s = [prefix '.' key]; end
end
