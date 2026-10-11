function M = material_lookup(name, lambda_nm, materials_dir)
%MATERIAL_LOOKUP  Refractive index of a catalog glass at one wavelength.
%
%   M = material_lookup(name, lambda_nm, materials_dir)
%     name           'S-LAH71' | 'N-LASF9' | 'TAFD55' | 'PMMA' ... (case-insensitive; '-', ' ',
%                    '_' ignored). Prefix with the catalog to disambiguate: 'OHARA:S-LAH71',
%                    'SCHOTT:N-LASF9', 'HOYA:LAF2', 'custom_materials:PMMA' (catalog = start
%                    of the file name).
%     lambda_nm      wavelength in nm; [] = d-line 587.5618 nm (M.wavelength_default = true)
%     materials_dir  folder holding the *.agf catalogs (every file is searched) and, when
%                    present, custom_materials.json (polymers such as PMMA and PC that no maker
%                    ships as an AGF; read by read_custom_materials, same record layout)
%
%   Errors (the run must not continue on any of these):
%     - no *.agf file and no custom_materials.json in materials_dir
%     - name not found (message lists the catalogs searched and near matches)
%     - name found in more than one catalog and no catalog prefix given
%     - wavelength outside the catalog's validity range (LD record / range_um)
%
%   M fields: name, key, catalog, maker, file, formula, formula_name, wavelength_nm,
%   wavelength_default, n, nd, vd, status, status_str, ld_nm, density, tce, dPgF,
%   dn_check (n(587.56 nm) - catalog nd: a catalog inconsistency when > 1e-4),
%   tau_i (internal transmittance at the wavelength for it_thickness_mm, NaN if no
%   table), it_thickness_mm, comment.
%
%   The parsed catalogs are cached (persistent) and re-read when a file changes.

    D_LINE_NM = 587.5618;
    if nargin < 2, lambda_nm = []; end
    if ~ischar(name) || isempty(strtrim(name)), error('material_lookup:name', 'material name must be a non-empty string'); end
    name = strtrim(name);

    G = load_catalogs(materials_dir);
    catalogs = unique({G.catalog});

    % optional CATALOG: prefix
    wanted_cat = '';
    k = find(name == ':', 1);
    if ~isempty(k), wanted_cat = strtrim(name(1:k-1)); name = strtrim(name(k+1:end)); end
    key = upper(name);  key = key(key ~= '-' & key ~= ' ' & key ~= '_');

    hits = find(strcmp({G.key}, key));
    if ~isempty(wanted_cat)
        incat = cellfun(@(c) strncmpi(c, wanted_cat, numel(wanted_cat)), {G.catalog});
        if ~any(incat)
            error('material_lookup:catalog', 'No catalog starting with "%s" in %s (have: %s)', wanted_cat, materials_dir, strjoin(catalogs, ', '));
        end
        hits = hits(incat(hits));
    end
    if isempty(hits)
        near = G(strncmp({G.key}, key, min(4, numel(key))));
        near_s = '';
        if ~isempty(near)
            nm = arrayfun(@(g) sprintf('%s (%s)', g.name, g.catalog), near, 'UniformOutput', false);
            near_s = sprintf('\n  near matches: %s', strjoin(nm(1:min(12, end)), ', '));
        end
        error('material_lookup:notfound', 'Material "%s" not found in %d glasses of %s (catalogs: %s).%s', ...
              name, numel(G), materials_dir, strjoin(catalogs, ', '), near_s);
    end
    if numel(hits) > 1
        nm = arrayfun(@(g) sprintf('%s:%s', g.catalog, g.name), G(hits), 'UniformOutput', false);
        error('material_lookup:ambiguous', 'Material "%s" exists in several catalogs: %s. Use the CATALOG:NAME form.', name, strjoin(nm, ', '));
    end
    g = G(hits);

    M = struct();
    M.name = g.name;  M.key = g.key;  M.catalog = g.catalog;  M.maker = g.maker;  M.file = g.file;
    M.formula = g.formula;
    M.wavelength_default = isempty(lambda_nm);
    if M.wavelength_default, lambda_nm = D_LINE_NM; end
    M.wavelength_nm = lambda_nm;
    M.ld_nm = g.ld_um * 1000;
    if all(isfinite(M.ld_nm)) && (lambda_nm < M.ld_nm(1) - 1e-9 || lambda_nm > M.ld_nm(2) + 1e-9)
        error('material_lookup:range', '%s (%s): wavelength %.1f nm is outside the catalog dispersion range %.0f-%.0f nm', ...
              g.name, g.catalog, lambda_nm, M.ld_nm(1), M.ld_nm(2));
    end
    [M.n, M.formula_name] = agf_index(g.cd, g.formula, lambda_nm / 1000);
    M.nd = g.nd;  M.vd = g.vd;
    M.dn_check = agf_index(g.cd, g.formula, D_LINE_NM / 1000) - g.nd;
    M.status = g.status;  M.status_str = g.status_str;
    M.density = g.density;  M.tce = g.tce;  M.dPgF = g.dPgF;
    M.comment = g.comment;
    M.tau_i = NaN;  M.it_thickness_mm = NaN;
    if ~isempty(g.it)
        it = sortrows(g.it, 1);
        lam_um = lambda_nm / 1000;
        if lam_um >= it(1,1) && lam_um <= it(end,1)
            [lu, iu] = unique(it(:,1));
            M.tau_i = interp1(lu, it(iu,2), lam_um, 'linear');
            M.it_thickness_mm = it(iu(1), 3);
        end
    end
    if ~isfinite(M.n) || M.n <= 0
        error('material_lookup:value', '%s (%s): dispersion formula gives an invalid index (%g) at %.1f nm', g.name, g.catalog, M.n, lambda_nm);
    end
end

% ---------------------------------------------------------------------------
function G = load_catalogs(materials_dir)
    persistent cache
    if ~exist(materials_dir, 'dir')
        error('material_lookup:dir', 'materials folder not found: %s', materials_dir);
    end
    files = [dir(fullfile(materials_dir, '*.agf')); dir(fullfile(materials_dir, '*.AGF'))];
    names = {files.name};
    [~, iu] = unique(lower(names));  files = files(sort(iu));      % case-insensitive file systems list twice
    % polymers etc. that no maker ships as an AGF live in one hand-written JSON next to the catalogs
    custom = dir(fullfile(materials_dir, 'custom_materials.json'));
    if isempty(files) && isempty(custom)
        error('material_lookup:nofiles', 'No *.agf catalog (nor custom_materials.json) in %s - download the Zemax AGF files from the glass makers (see scripts/README.md)', materials_dir);
    end
    sig = sprintf('%s|', materials_dir);
    for i = 1:numel(files), sig = [sig, sprintf('%s:%d:%.6f|', files(i).name, files(i).bytes, files(i).datenum)]; end %#ok<AGROW>
    for i = 1:numel(custom), sig = [sig, sprintf('%s:%d:%.6f|', custom(i).name, custom(i).bytes, custom(i).datenum)]; end %#ok<AGROW>
    if ~isempty(cache) && strcmp(cache.sig, sig)
        G = cache.G;  return;
    end
    G = [];
    for i = 1:numel(files)
        Gi = read_agf(fullfile(materials_dir, files(i).name));
        if isempty(G), G = Gi; else, G = [G; Gi]; end %#ok<AGROW>
    end
    for i = 1:numel(custom)
        Gi = read_custom_materials(fullfile(materials_dir, custom(i).name));   % same fields as read_agf
        if isempty(G), G = Gi; elseif ~isempty(Gi), G = [G; Gi]; end %#ok<AGROW>
    end
    cache = struct('sig', sig, 'G', G);
end
