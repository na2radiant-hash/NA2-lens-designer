function verdict = write_report(cfg, info, out, stats, CK, AN)
%WRITE_REPORT  report.txt + report.json in the package; one row appended to runs_index.csv.
%
%   verdict = write_report(cfg, info, out, stats, CK, AN)
%     stats: ok, err, runtime_s, git, matlab, lens (built lens or []), unwired (cell)
%     CK:    result of run_checks ([] if the run failed before the checks)
%     AN:    analyses struct ([] or fields collimation/fresnel/profile/collection)
%
%   Verdict: FAIL when the run errored or any check FAILED, otherwise PASS
%   (WARN lines never block). Vendor geometry is only written on PASS unless
%   run.export_on_fail is true - the main script enforces that.
%
%   Lenses built with per-element materials, prescribed spheres or draft clamps
%   (lens.material.elements, lens.surfaces, lens.budget) get MATERIALS / SURFACES /
%   BUDGET lines after the CONSTRUCTION block and the matching report.json keys
%   (materials, surfaces, budget); a lens without those fields writes today's report.

    D = cfg.design;
    if ~stats.ok
        verdict = 'FAIL';
    elseif ~isempty(CK)
        verdict = CK.verdict;
    else
        verdict = 'PASS';
    end
    n_fail = 0; n_warn = 0;
    if ~isempty(CK), n_fail = CK.n_fail; n_warn = CK.n_warn; end
    if ~stats.ok, n_fail = n_fail + 1; end

    files = list_files(out.pkg, out.pkg);
    L = {};
    L{end+1} = sprintf('NA2 RUN REPORT   %s / %s   %s   %s        VERDICT: %s  (%d fail, %d warn)', ...
        cfg.run.vendor, out.design_tag, ['Rev ' out.revlabel], datestr(now, 'yyyy-mm-dd HH:MM'), verdict, n_fail, n_warn);
    L{end+1} = sprintf('config   %s   (sha1 %s)', info.path, info.sha1);
    if isfield(info, 'material') && ~isempty(info.material), L{end+1} = sprintf('glass    %s  (%s)  n = %.6f at %g nm', info.material.name, info.material.catalog, info.material.n, info.material.wavelength_nm); end
    L{end+1} = sprintf('code     git %s   |   MATLAB %s   |   runtime %.1f s', stats.git, stats.matlab, stats.runtime_s);
    L{end+1} = sprintf('package  %s', out.pkg);
    L{end+1} = '';
    if ~stats.ok
        L{end+1} = sprintf('ERROR    %s', strrep(stats.err, sprintf('\n'), ' | '));
        L{end+1} = '';
    end

    % ---- CONFIG ----
    L{end+1} = sprintf('CONFIG        [PASS] schema validated (%d settings); %d keys accepted but not consumed by this version', info.n_keys, numel(stats.unwired));
    for i = 1:numel(stats.unwired), L{end+1} = sprintf('                     - %s', stats.unwired{i}); end %#ok<AGROW>

    % ---- CONSTRUCTION ----
    lens = stats.lens;
    if isempty(lens) || isempty(lens.final_lens)
        L{end+1} = 'CONSTRUCTION  [FAIL] no lens built';
    else
        cs = lens.cstats;
        att = cs.attempts;  if isempty(att), att = 0; end
        L{end+1} = sprintf('CONSTRUCTION  [INFO] %s; %d/%d surfaces; attempts per surface: %s', lens.source, ...
            sum(~cellfun(@isempty, lens.final_lens(1:min(lens.L, numel(lens.final_lens))))), lens.L, ...
            strjoin(arrayfun(@(a) sprintf('%d', a), att, 'UniformOutput', false), ' '));
        L{end+1} = sprintf('                     n_lens %.4f | n_outside %.4f | NA_hole %.3f -> fan 0..%.2f deg (design %.2f) | %d design rays | solver %s | weights J%d k%.2f b%.2f h%.2f l%.2f', ...
            lens.n2, lens.n1, D.NA_hole, lens.nominal_max_angle, lens.design_max_angle, D.rays_count, D.solver.method, ...
            D.weights.J_front, D.weights.k_shape, D.weights.base_w, D.weights.hardness_exp, D.weights.layer_exp);
        feats = {};
        if D.collimation_fraction ~= 1, feats{end+1} = sprintf('partial collimation %.2f', D.collimation_fraction); end
        if D.truncation.enable, feats{end+1} = 'truncation'; end
        if D.glass_cell.enable, feats{end+1} = sprintf('glass cell before %s', mat2str(D.glass_cell.before_elements)); end
        if D.commercial_asphere.enable, feats{end+1} = sprintf('commercial asphere %s%s', D.commercial_asphere.model, tern(D.commercial_asphere.correction.enable, ' + correction', '')); end
        if ~isempty(feats), L{end+1} = sprintf('                     variants: %s', strjoin(feats, ', ')); end
        L = [L, lens_variant_lines(lens, cfg)];     % MATERIALS / SURFACES / BUDGET, empty for a plain build
    end

    % ---- check rows grouped by section ----
    if ~isempty(CK)
        secs = {'CONSTRUCTION', 'MATERIAL', 'SURFACES', 'SCALE', 'OPTICS', 'GEOMETRY'};
        secs = [secs, setdiff(unique({CK.rows.section}), secs, 'stable')];   % any new section is never silently dropped
        for s = 1:numel(secs)
            rows = CK.rows(strcmp({CK.rows.section}, secs{s}));
            if isempty(rows), continue; end
            first = true;
            for r = 1:numel(rows)
                head = '';  if first, head = secs{s}; first = false; end
                L{end+1} = sprintf('%-13s [%-4s] %-34s %-18s %-16s %s', head, rows(r).status, rows(r).name, rows(r).value, rows(r).threshold, rows(r).note); %#ok<AGROW>
            end
        end
        for e = 1:numel(CK.geometry)
            g = CK.geometry(e);
            L{end+1} = sprintf('                     element %d: OD %.3f  length %.3f  mouth %.3f  vertex x %.3f  R~%.3f  edge %.3f  centre %.3f  gap-> %s  slope %.1f/%.1f deg', ...
                g.elem, g.OD, g.length, g.mouth, g.vertex_x, g.vertex_R, g.edge_thickness, g.center_thickness, ...
                tern(isnan(g.gap_to_next), '-', sprintf('%.3f', g.gap_to_next)), g.max_slope_inner, g.max_slope_outer); %#ok<AGROW>
        end
    else
        L{end+1} = 'OPTICS / GEOMETRY  [--]  checks not run';
    end

    % ---- analyses summary ----
    if ~isempty(AN) && isstruct(AN)
        if isfield(AN, 'collection') && ~isempty(AN.collection)
            K = AN.collection;
            L{end+1} = sprintf('COLLECTION    [INFO] traced %.4f (%s emitter, 3-D weighted) | isotropic %.4f | fan max %.4f | legacy ray fraction %.4f, sin2 %.4f', ...
                K.phi_traced, K.emitter.type, K.phi_traced_isotropic, K.phi_fan_max, K.legacy_ray_fraction, K.legacy_sin2_fraction);
            L{end+1} = sprintf('                     analytic at theta_lens %.2f deg (NA %.3f): isotropic %.4f, dipole %.4f', K.theta_lens_deg, K.NA_lens, K.phi_iso_at_lens, K.phi_dip_at_lens);
        end
        if isfield(AN, 'profile') && ~isempty(AN.profile) && ~isempty(AN.profile.r)
            P = AN.profile;  mm = stats.lens.mm_per_du;
            L{end+1} = sprintf('PROFILE       [INFO] at x = %.2f mm: r50 %.3f mm, r(1-e^-2) %.3f mm over %d rays', P.plane_x * mm, P.r_50 * mm, P.r_1e2 * mm, P.n_rays);
        end
    end

    % ---- exports ----
    L{end+1} = sprintf('EXPORTS       [%s] %d files in package:', tern(stats.ok, 'INFO', 'FAIL'), numel(files));
    for i = 1:numel(files), L{end+1} = sprintf('                     %9s  %s', files(i).size, files(i).rel); end %#ok<AGROW>
    L{end+1} = sprintf('FOLDER        [INFO] fresh folder %s; runs_index.csv appended', out.pkgname);

    txt = strjoin(L, newline);
    fid = fopen(fullfile(out.pkg, 'report.txt'), 'w'); fprintf(fid, '%s\n', txt); fclose(fid);
    fprintf('\n%s\n\n', txt);

    % ---- machine-readable copy ----
    R = struct('verdict', verdict, 'n_fail', n_fail, 'n_warn', n_warn, 'vendor', cfg.run.vendor, 'material', cfg.run.material, ...
               'n_lens', D.n_lens, 'elements', cfg.run.elements(:).', 'rev', out.revlabel, 'date', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
               'config', info.path, 'config_sha1', info.sha1, 'git', stats.git, 'matlab', stats.matlab, ...
               'runtime_s', stats.runtime_s, 'error', stats.err, 'unwired_keys', {stats.unwired}, ...
               'files', {{files.rel}}, 'package', out.pkg);
    if isfield(info, 'material') && ~isempty(info.material)
        m = info.material;
        R.glass = struct('name', m.name, 'catalog', m.catalog, 'file', m.file, 'wavelength_nm', m.wavelength_nm, 'wavelength_default', m.wavelength_default, ...
                         'n', m.n, 'nd', m.nd, 'vd', m.vd, 'formula', m.formula_name, 'status', m.status_str, 'tau_i_catalog', m.tau_i);
    end
    if ~isempty(CK), R.checks = CK.rows; R.geometry = CK.geometry; end
    if ~isempty(lens) && ~isempty(lens.final_lens)
        R.construction = lens.cstats;  R.mm_per_du = lens.mm_per_du;  R.source = lens.source;
        [~, elems] = material_parts(lens);
        if ~isempty(elems), R.materials = strip_field(elems, 'lookup'); end          % the lookup is the whole catalog record
        surfs = lens_surfaces(lens);
        if ~isempty(surfs), R.surfaces = strip_field(surfs, 'pts_dense'); end        % the dense arc is geometry, not a report
        B = lens_budget(lens);
        if ~isempty(B)
            tol = budget_tol(B, cfg);
            Bj = struct();
            Bj.per_layer = getf(B, 'per_layer', []);
            Bj.max_residual_deg = getf(B, 'max_residual_deg', NaN);
            Bj.worst_ray = getf(B, 'worst_ray', NaN);
            Bj.worst_ray_deg = getf(B, 'worst_ray_deg', NaN);
            Bj.tol_deg = tol;
            Bj.closed = strcmp(budget_status(B, tol), 'PASS');
            Bj.n_unphysical = getf(B, 'n_unphysical', 0);
            R.budget = Bj;
        end
    end
    if ~isempty(AN) && isstruct(AN)
        if isfield(AN, 'collimation') && ~isempty(AN.collimation), R.collimation = rmfield(AN.collimation, 'table'); end
        if isfield(AN, 'fresnel') && ~isempty(AN.fresnel), R.fresnel = struct('mean_transmission', AN.fresnel.mean_transmission, 'min_tir_margin_deg', AN.fresnel.min_tir_margin_deg, 'n_tir', AN.fresnel.n_tir); end
        if isfield(AN, 'collection') && ~isempty(AN.collection), R.collection = rmfield(rmfield(rmfield(AN.collection, 'theta0'), 'phi_iso_curve'), 'phi_dip_curve'); end
        if isfield(AN, 'profile') && ~isempty(AN.profile) && ~isempty(AN.profile.r), R.profile = struct('plane_x_du', AN.profile.plane_x, 'r_50_du', AN.profile.r_50, 'r_1e2_du', AN.profile.r_1e2); end
    end
    fid = fopen(fullfile(out.pkg, 'report.json'), 'w'); fprintf(fid, '%s', jsonencode(R)); fclose(fid);

    % ---- runs index ----
    idx = fullfile(out.root, 'runs_index.csv');
    newfile = ~exist(idx, 'file');
    fid = fopen(idx, 'a');
    if fid ~= -1
        if newfile
            fprintf(fid, 'date,vendor,material,n_lens,rev,elements,NA_hole,WD_mm,rays,layers,verdict,fails,warns,runtime_s,package,config\n');
        end
        elems = strjoin(arrayfun(@(a) sprintf('%d', a), cfg.run.elements(:).', 'UniformOutput', false), ' ');
        fprintf(fid, '%s,%s,%s,%.4f,%s,%s,%.3f,%.3f,%d,%d,%s,%d,%d,%.1f,%s,%s\n', datestr(now, 'yyyy-mm-dd HH:MM'), ...
            cfg.run.vendor, cfg.run.material, D.n_lens, out.revlabel, elems, D.NA_hole, D.WD_mm, D.rays_count, D.layers_count, ...
            verdict, n_fail, n_warn, stats.runtime_s, fullfile(cfg.run.vendor, out.design_tag, out.pkgname), info.name);
        fclose(fid);
    else
        warning('write_report:index', 'Could not append to %s (open in Excel?)', idx);
    end
end

function files = list_files(root, base)
    files = struct('rel', {}, 'size', {});
    d = dir(root);
    for i = 1:numel(d)
        if d(i).name(1) == '.', continue; end
        p = fullfile(root, d(i).name);
        if d(i).isdir
            files = [files, list_files(p, base)]; %#ok<AGROW>
        else
            files(end+1) = struct('rel', strrep(p, [base filesep], ''), 'size', human_size(d(i).bytes)); %#ok<AGROW>
        end
    end
end

function s = human_size(b)
    if b < 1024, s = sprintf('%d B', b);
    elseif b < 1024^2, s = sprintf('%.1f KB', b / 1024);
    else, s = sprintf('%.2f MB', b / 1024^2);
    end
end

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end

% ---------------------------------------------------------------------------
function lines = lens_variant_lines(lens, cfg)
    % MATERIALS / SURFACES / BUDGET summary lines; {} when the lens has none of the fields
    lines = {};
    [~, elems] = material_parts(lens);
    if nitems(elems) > 0
        parts = cell(1, nitems(elems));
        for k = 1:nitems(elems)
            E = getitem(elems, k);
            nm = getf(E, 'name', '');  if ~isempty(nm), nm = [nm ' ']; end
            why = getf(E, 'source', '-');
            wl = getf(E, 'wavelength_nm', []);
            if isnumeric(wl) && isscalar(wl) && isfinite(wl), why = sprintf('%s, at %g nm', why, wl); end
            w = getf(E, 'warn', '');  if ~isempty(w), why = sprintf('%s; %s', why, w); end
            parts{k} = sprintf('element %d: %sn = %.6f (%s)', getf(E, 'element', k), nm, getf(E, 'n', NaN), why);
        end
        lines{end+1} = sprintf('MATERIALS     [INFO] %s', strjoin(parts, ' | '));
    end
    surfs = lens_surfaces(lens);
    mm = lens.mm_per_du;
    parts = {};  any_special = false;
    for j = 1:nitems(surfs)
        s = getitem(surfs, j);
        kind = getf(s, 'kind', 'built');
        if strcmp(kind, 'sphere')
            parts{end+1} = sprintf('S%d sphere R %.4f mm center x %.4f mm', j, getf(s, 'radius_du', NaN) * mm, getf(s, 'center_z_du', NaN) * mm); %#ok<AGROW>
            any_special = true;
        elseif strcmp(kind, 'clamped')
            k1 = getf(s, 'first_clamped_ray', Inf);
            if isfinite(k1), act = sprintf('clamp from ray %d (%.1f deg)', k1, getf(s, 'clamp_from_deg', NaN)); else, act = 'never active'; end
            parts{end+1} = sprintf('S%d draft %g deg pull %s, %s', j, getf(s, 'max_slope_deg', NaN), getf(s, 'pull', '-'), act); %#ok<AGROW>
            any_special = true;
        end
    end
    if ~isempty(parts), lines{end+1} = sprintf('SURFACES      [INFO] %s', strjoin(parts, ' | ')); end
    B = lens_budget(lens);
    if ~isempty(B)
        tol = budget_tol(B, cfg);
        st = budget_status(B, tol);
        lines{end+1} = sprintf('BUDGET        [%s] closed: max residual %.4f deg (tol %g)', st, getf(B, 'max_residual_deg', NaN), tol);
        % the per-layer ledger only matters when a layer could not take its planned share
        if any_special || ~strcmp(st, 'PASS')
            pl = getf(B, 'per_layer', []);
            for j = 1:nitems(pl)
                p = getitem(pl, j);
                lines{end+1} = sprintf('                     layer %d %s: share mean/max  %.2f/%.2f | carried max %.2f | achieved mean %.2f | deficit max %.2f (ray %d, %.1f deg)', ...
                    getf(p, 'layer', j), getf(p, 'kind', 'built'), getf(p, 'share_mean', NaN), getf(p, 'share_max', NaN), getf(p, 'carried_max', NaN), ...
                    getf(p, 'achieved_mean', NaN), getf(p, 'deficit_max', NaN), getf(p, 'deficit_ray', NaN), getf(p, 'deficit_ray_deg', NaN)); %#ok<AGROW>
            end
        end
    end
end

% optional lens fields (same accessors as run_checks): every one tolerates a missing field
% so a lens loaded from an older lens.mat still gets its report
function [Mt, elems] = material_parts(lens)
    % lens.material is either the catalog lookup itself (single glass, older lens.mat) or the
    % per-element struct {default, elements}
    Mt = [];  elems = [];
    if ~isfield(lens, 'material') || ~isstruct(lens.material) || isempty(lens.material), return; end
    Mm = lens.material;
    if isfield(Mm, 'default') || isfield(Mm, 'elements')
        Mt = getf(Mm, 'default', []);
        elems = getf(Mm, 'elements', []);
    else
        Mt = Mm;
    end
    if ~isstruct(Mt), Mt = []; end
end

function S = lens_surfaces(lens)
    S = [];
    if isfield(lens, 'surfaces') && ~isempty(lens.surfaces) && (isstruct(lens.surfaces) || iscell(lens.surfaces)), S = lens.surfaces; end
end

function B = lens_budget(lens)
    B = [];
    if isfield(lens, 'budget') && isstruct(lens.budget) && ~isempty(lens.budget), B = lens.budget; end
end

function tol = budget_tol(B, cfg)
    % cfg.checks first (where every threshold lives), the budget's own tol_deg as the fallback
    tol = [];
    if isfield(cfg.checks, 'bending_budget_tol_deg'), tol = cfg.checks.bending_budget_tol_deg; end
    if isempty(tol), tol = getf(B, 'tol_deg', []); end
    if isempty(tol), tol = 0.01; end
end

function s = budget_status(B, tol)
    % same rule as the 'bending budget closed' row of run_checks
    r = getf(B, 'max_residual_deg', NaN);
    s = 'PASS';
    if r > tol + 1e-9 * max(1, abs(tol)), s = 'FAIL'; end
    if getf(B, 'n_unphysical', 0) > 0, s = 'FAIL'; end
    if ~logical(getf(B, 'closed', true)), s = 'FAIL'; end
end

function A = strip_field(A, name)
    if iscell(A)
        for k = 1:numel(A)
            if isstruct(A{k}) && isfield(A{k}, name), A{k} = rmfield(A{k}, name); end
        end
    elseif isstruct(A) && isfield(A, name)
        A = rmfield(A, name);
    end
end

function n = nitems(A)
    if isempty(A), n = 0; else, n = numel(A); end
end

function s = getitem(A, k)
    if iscell(A), s = A{k}; else, s = A(k); end
end

function v = getf(s, name, default)
    v = default;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name)), v = s.(name); end
end
