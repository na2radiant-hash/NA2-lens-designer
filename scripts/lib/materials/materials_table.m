function T = materials_table(materials_dir, csv_out, lambda_nm)
%MATERIALS_TABLE  One-line-per-glass index of every *.agf catalog (for people, SharePoint, Excel).
%
%   T = materials_table(materials_dir, csv_out, lambda_nm)
%     materials_dir  folder with the *.agf files and custom_materials.json (default: <NA2>/inputs/materials)
%     csv_out        CSV to write ('' = no file; default: <materials_dir>/materials_index.csv)
%     lambda_nm      extra wavelengths to tabulate (default [575 637])
%
%   Columns: catalog, name, status, nd, vd, n_<lambda> ..., formula, lambda_min_nm,
%   lambda_max_nm, density_g_cm3, TCE_1e-6_K, dPgF, tau_i_<lambda>_10mm ..., comment.
%   The index is GENERATED from the catalogs - never edit it by hand; rerun this after
%   dropping a new .agf file or editing custom_materials.json (its polymers come last,
%   status 'custom', nd/vd from their formula). n values come from the dispersion formula
%   (not the nd column), so the table is exactly what LensConstructionGradual will use.
%
%   Example:  materials_table('inputs/materials', 'inputs/materials/materials_index.csv')

    if nargin < 1 || isempty(materials_dir)
        here = fileparts(mfilename('fullpath'));
        materials_dir = fullfile(here, '..', '..', '..', 'inputs', 'materials');
    end
    if nargin < 2, csv_out = fullfile(materials_dir, 'materials_index.csv'); end
    if nargin < 3 || isempty(lambda_nm), lambda_nm = [575 637]; end
    lambda_nm = lambda_nm(:).';

    files = [dir(fullfile(materials_dir, '*.agf')); dir(fullfile(materials_dir, '*.AGF'))];
    [~, iu] = unique(lower({files.name}));  files = files(sort(iu));
    custom = dir(fullfile(materials_dir, 'custom_materials.json'));   % polymers, appended after the catalogs
    if isempty(files) && isempty(custom), error('materials_table:nofiles', 'no *.agf file (nor custom_materials.json) in %s', materials_dir); end
    G = [];
    for i = 1:numel(files)
        Gi = read_agf(fullfile(materials_dir, files(i).name));
        if isempty(G), G = Gi; else, G = [G; Gi]; end %#ok<AGROW>
    end
    for i = 1:numel(custom)
        Gi = read_custom_materials(fullfile(materials_dir, custom(i).name));   % same fields as read_agf
        if isempty(G), G = Gi; elseif ~isempty(Gi), G = [G; Gi]; end %#ok<AGROW>
    end

    nG = numel(G);  nL = numel(lambda_nm);
    T = struct('catalog', {{G.catalog}'}, 'name', {{G.name}'}, 'status', {{G.status_str}'}, ...
               'nd', [G.nd]', 'vd', [G.vd]', 'n', NaN(nG, nL), 'tau_i', NaN(nG, nL), ...
               'formula', NaN(nG, 1), 'lambda_min_nm', NaN(nG, 1), 'lambda_max_nm', NaN(nG, 1), ...
               'density', [G.density]', 'tce', [G.tce]', 'dPgF', [G.dPgF]', 'comment', {{G.comment}'}, ...
               'lambda_nm', lambda_nm);
    for i = 1:nG
        g = G(i);
        T.formula(i) = g.formula;
        T.lambda_min_nm(i) = g.ld_um(1) * 1000;  T.lambda_max_nm(i) = g.ld_um(2) * 1000;
        for j = 1:nL
            lam = lambda_nm(j);
            if lam >= T.lambda_min_nm(i) - 1e-9 && lam <= T.lambda_max_nm(i) + 1e-9
                T.n(i, j) = agf_index(g.cd, g.formula, lam / 1000);
            end
            if ~isempty(g.it)
                it = sortrows(g.it, 1);  [lu, ku] = unique(it(:,1));
                if lam/1000 >= lu(1) && lam/1000 <= lu(end), T.tau_i(i, j) = interp1(lu, it(ku,2), lam/1000, 'linear'); end
            end
        end
    end

    if ~isempty(csv_out)
        fid = fopen(csv_out, 'w');
        if fid < 0, error('materials_table:write', 'cannot write %s', csv_out); end
        hdr = 'catalog,name,status,nd,vd';
        for j = 1:nL, hdr = [hdr, sprintf(',n_%gnm', lambda_nm(j))]; end %#ok<AGROW>
        hdr = [hdr, ',formula,lambda_min_nm,lambda_max_nm,density_g_cm3,TCE_1e-6_K,dPgF'];
        for j = 1:nL, hdr = [hdr, sprintf(',tau_i_%gnm_10mm', lambda_nm(j))]; end %#ok<AGROW>
        fprintf(fid, '%s,comment\n', hdr);
        for i = 1:nG
            fprintf(fid, '%s,%s,%s,%.6f,%.2f', T.catalog{i}, T.name{i}, T.status{i}, T.nd(i), T.vd(i));
            for j = 1:nL, fprintf(fid, ',%s', num_or_blank(T.n(i, j), '%.6f')); end
            fprintf(fid, ',%d,%.0f,%.0f,%s,%s,%s', T.formula(i), T.lambda_min_nm(i), T.lambda_max_nm(i), ...
                    num_or_blank(T.density(i), '%.3f'), num_or_blank(T.tce(i), '%.2f'), num_or_blank(T.dPgF(i), '%.5f'));
            for j = 1:nL, fprintf(fid, ',%s', num_or_blank(T.tau_i(i, j), '%.4f')); end
            c = strrep(T.comment{i}, '"', '''');  c = strrep(c, ',', ';');
            fprintf(fid, ',%s\n', c);
        end
        fclose(fid);
        fprintf('materials_table: %d materials from %d catalog(s) and %d custom file(s) -> %s\n', nG, numel(files), numel(custom), csv_out);
    end
end

function s = num_or_blank(v, fmt)
    if isfinite(v), s = sprintf(fmt, v); else, s = ''; end
end
