function [cfg, mat, emat] = resolve_material(cfg, projRoot)
%RESOLVE_MATERIAL  design.material / design.element_materials -> refractive index per element, package name.
%
%   [cfg, mat, emat] = resolve_material(cfg, projRoot)
%
%   design.material.name empty : design.n_lens is used as written for every element not listed
%                                in element_materials, mat = [].
%   otherwise                  : design.n_lens := n(name, design.material.wavelength_nm) from the
%                                *.agf catalogs (and custom_materials.json) in <projRoot>/inputs/materials;
%                                mat holds the provenance (material_lookup output + n_lens_config = the
%                                value the config had, [] or a number).
%   design.element_materials   : per-element override, one entry per element in emat (1 x nE):
%       element, name, n, source ('catalog' | 'custom' | 'as written' | 'default'), maker, catalog,
%       wavelength_nm, formula_name, nd, vd, status_str, label (drawing text), tag (folder piece,
%       e.g. 'E1-PMMA_n1.489', '' for the default), warn ('' | 'no dispersion data'), lookup (the
%       material_lookup struct or []).
%       name -> catalog / custom dispersion formula at the design wavelength; n -> as written,
%       flagged 'no dispersion data' (WARN in the report).
%   run.material null : filled with '<MAKER>_<glass>_<wavelength>nm' (e.g. SCHOTT_N-LASF9_637nm), the
%                       second package subfolder; with listed elements it becomes
%                       'E1-PMMA_n1.489__SCHOTT_N-LASF9_637nm' (per-element tags, then the default).
%   Any lookup problem is an error before any folder is made: unknown / ambiguous name,
%   wavelength out of range, no catalogs.
%   Idempotent: run_one calls it again after a sweep changed the wavelength.

    mat = [];  emat = [];
    Mc = cfg.design.material;
    materials_dir = fullfile(projRoot, 'inputs', 'materials');
    has_default = isfield(Mc, 'name') && ~isempty(Mc.name);
    wl = [];  if isfield(Mc, 'wavelength_nm'), wl = Mc.wavelength_nm; end

    if has_default
        mat = material_lookup(Mc.name, wl, materials_dir);
        mat.n_lens_config = cfg.design.n_lens;
        cfg.design.n_lens = mat.n;
        mat.run_material_config = cfg.run.material;
    end

    % ---- one entry per element: the default, then the listed overrides ----
    %      (no listed element -> emat stays [] and every consumer keeps its single-material path)
    nE = floor(cfg.design.layers_count / 2);
    items = objlist_rows(field_or(cfg.design, 'element_materials', []), {'element', 'name', 'n'});
    if isempty(items)
        if isempty(cfg.run.material) || isempty(strtrim(cfg.run.material))
            if has_default, cfg.run.material = sprintf('%s_%s_%.0fnm', mat.maker, mat.name, mat.wavelength_nm); end
        end
        return;
    end
    emat = repmat(element_entry(), 1, nE);
    for e = 1:nE
        E = element_entry();  E.element = e;  E.source = 'default';
        if has_default
            E = fill_from_lookup(E, mat);
            E.source = 'default';                 % unlisted element; the provenance stays in catalog / maker / lookup
            E.label = sprintf('%s %s (n = %.4f at %g nm)', mat.maker, mat.name, mat.n, mat.wavelength_nm);
        else
            % design.n_lens typed, no catalog glass: there is no material name to show
            % (run.material is the package folder label, not a glass)
            E.name = '';  E.n = cfg.design.n_lens;        % no glass name: consumers print the index, Zemax keeps its n-based guess
            E.status_str = 'as written';  E.formula_name = 'none';
            E.label = sprintf('n = %.4g as written (design.n_lens)', cfg.design.n_lens);
        end
        emat(e) = E;
    end
    tags = {};
    for k = 1:numel(items)
        it = items(k);
        if isempty(it.element) || it.element < 1 || it.element > nE || it.element ~= round(it.element)
            error('resolve_material:element', 'design.element_materials[%d].element must be an integer in 1..%d', k, nE);
        end
        e = it.element;
        E = emat(e);
        has_name = ~isempty(it.name);  has_n = ~isempty(it.n);
        if has_name == has_n
            error('resolve_material:element', 'design.element_materials[%d] (element %d): give exactly one of name / n', k, e);
        end
        if has_name
            M = material_lookup(it.name, wl, materials_dir);
            E = fill_from_lookup(E, M);
            E.label = sprintf('%s (n = %.4f at %g nm)', M.name, M.n, M.wavelength_nm);
            if M.wavelength_default, E.label = [E.label ' [d-line default]']; end
            E.tag = sprintf('E%d-%s_n%.4g', e, M.name, M.n);
        else
            E.name = '';                                  % an index as written has no material name
            E.n = it.n;
            E.source = 'as written';
            E.maker = '';  E.catalog = '';  E.wavelength_nm = NaN;  E.formula_name = 'none';
            E.nd = NaN;  E.vd = NaN;  E.status_str = 'as written';  E.lookup = [];
            E.label = sprintf('n = %.4g as written (no dispersion data)', it.n);
            E.tag = sprintf('E%d-n%.4g', e, it.n);
            E.warn = 'no dispersion data';
        end
        emat(e) = E;
        tags{end+1} = E.tag; %#ok<AGROW>
    end

    % ---- second package folder <run.material>_n<n_lens>: derived when null ----
    if isempty(cfg.run.material) || isempty(strtrim(cfg.run.material))
        parts = tags;
        if has_default
            parts{end+1} = sprintf('%s_%s_%.0fnm', mat.maker, mat.name, mat.wavelength_nm);
        end
        if ~isempty(parts), cfg.run.material = strjoin(parts, '__'); end
    end
end

% ---------------------------------------------------------------------------
function E = element_entry()
    E = struct('element', [], 'name', '', 'n', [], 'source', 'default', 'maker', '', 'catalog', '', ...
               'wavelength_nm', NaN, 'formula_name', '', 'nd', NaN, 'vd', NaN, 'status_str', '', ...
               'label', '', 'tag', '', 'warn', '', 'lookup', []);
end

function E = fill_from_lookup(E, M)
    E.name = M.name;  E.n = M.n;  E.maker = M.maker;  E.catalog = M.catalog;
    E.wavelength_nm = M.wavelength_nm;  E.formula_name = M.formula_name;
    E.nd = M.nd;  E.vd = M.vd;  E.status_str = M.status_str;  E.lookup = M;
    if strcmp(M.status_str, 'custom'), E.source = 'custom'; else, E.source = 'catalog'; end
    E.warn = '';
end

function v = field_or(s, name, default)
    v = default;
    if isstruct(s) && isfield(s, name), v = s.(name); end
end

function S = objlist_rows(v, fields)
%OBJLIST_ROWS  A JSON list of objects (jsondecode: struct array, cell of structs, or []) as a 1 x N struct array
%   with exactly the given fields (absent ones = []).
    S = repmat(cell2struct(repmat({[]}, numel(fields), 1), fields(:), 1), 1, 0);
    if isempty(v), return; end
    if iscell(v), items = v; else, items = num2cell(v(:).'); end
    for k = 1:numel(items)
        it = items{k};
        if ~isstruct(it), error('resolve_material:objlist', 'design.element_materials item %d is not an object', k); end
        row = cell2struct(repmat({[]}, numel(fields), 1), fields(:), 1);
        for f = 1:numel(fields)
            if isfield(it, fields{f}), row.(fields{f}) = it.(fields{f}); end
        end
        S(end+1) = row; %#ok<AGROW>
    end
end
