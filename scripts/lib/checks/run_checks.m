function CK = run_checks(lens, M, trace, AN, cfg)
%RUN_CHECKS  Pass/fail table of the run (thresholds from cfg.checks).
%
%   CK = run_checks(lens, M, trace, AN, cfg)
%     lens  built lens (design units, lens.mm_per_du)
%     M     manufacturing profiles from apply_process
%     trace validation trace ([] if trace.enable was false)
%     AN    analyses struct: collimation, fresnel (fields may be missing)
%
%   CK.rows(k): section, name, status ('PASS'|'WARN'|'FAIL'|'INFO'), value, threshold, note
%   CK.verdict  'PASS' | 'FAIL' (any FAIL) ; CK.n_fail, CK.n_warn
%   CK.geometry  per-element numbers in mm (also used by the report and lens.mat)
%
%   Optional lens fields (absent on loaded legacy lenses and older lens.mat files):
%     material.default / material.elements  per-element materials -> MATERIAL rows
%     surfaces(j).kind 'built'|'sphere'|'clamped' -> SURFACES rows; the GEOMETRY slopes
%                      use design_profiles so a prescribed sphere is measured on its exact arc
%     budget       bending-budget bookkeeping -> 'bending budget closed' under CONSTRUCTION
%   With none of them present the table is exactly the one of the single-material design.

    T = cfg.checks;  mm = lens.mm_per_du;  L = lens.L;  nE = floor(L/2);
    rows = struct('section', {}, 'name', {}, 'status', {}, 'value', {}, 'threshold', {}, 'note', {});
    [Mt, elems] = material_parts(lens);
    surfs = lens_surfaces(lens);
    B = lens_budget(lens);

    % ---------------------------------------------------------------- CONSTRUCTION
    cs = lens.cstats;
    rows = add(rows, 'CONSTRUCTION', 'solver fallbacks (phi = 0)', judge(cs.fallbacks, T.max_solver_fallbacks, 'max'), ...
        sprintf('%d', cs.fallbacks), sprintf('<= %d', T.max_solver_fallbacks), ...
        sprintf('of %d Snell solves; layer-1 failsafes %d', size(lens.gamma_matrix, 1) * L, cs.failsafe_layer1));
    if ~isempty(B)
        % a prescribed sphere or a draft clamp cannot always pass its bending shortfall on;
        % the budget says whether the last built surface still delivered the planned exit angles
        tol = budget_tol(B, cfg);
        rows = add(rows, 'CONSTRUCTION', 'bending budget closed', budget_status(B, tol), ...
            sprintf('max residual %.4f deg', getf(B, 'max_residual_deg', NaN)), sprintf('<= %g deg', tol), ...
            sprintf('worst ray %.2f deg emission; %d unrealisable Snell solves', getf(B, 'worst_ray_deg', NaN), getf(B, 'n_unphysical', 0)));
    end

    % ---------------------------------------------------------------- MATERIAL (catalog lookup)
    if ~isempty(Mt)
        rows = add(rows, 'MATERIAL', 'n_lens from catalog', 'INFO', sprintf('%.6f', Mt.n), sprintf('at %g nm', Mt.wavelength_nm), ...
            sprintf('%s | %s | %s (formula %d) | nd %.5f vd %.2f | valid %.0f-%.0f nm | %s', Mt.name, Mt.catalog, Mt.formula_name, Mt.formula, ...
                    Mt.nd, Mt.vd, Mt.ld_nm(1), Mt.ld_nm(2), Mt.status_str));
        if Mt.wavelength_default
            rows = add(rows, 'MATERIAL', 'design wavelength', 'WARN', sprintf('%.2f nm', Mt.wavelength_nm), 'd-line default', ...
                'design.material.wavelength_nm is null - the catalog reference wavelength was used, not our emitter line');
        end
        if ~isempty(Mt.n_lens_config) && abs(Mt.n_lens_config - Mt.n) > 1e-4
            rows = add(rows, 'MATERIAL', 'design.n_lens overridden', 'WARN', sprintf('%.4f -> %.6f', Mt.n_lens_config, Mt.n), '|dn| <= 1e-4', ...
                'the config value is ignored while design.material.name is set (set n_lens to null to silence)');
        end
        if Mt.status == 2 || Mt.status == 3
            rows = add(rows, 'MATERIAL', 'catalog status', 'WARN', Mt.status_str, 'standard/preferred', ...
                'availability must be confirmed with the maker before quoting');
        end
        if abs(Mt.dn_check) > 1e-4
            rows = add(rows, 'MATERIAL', 'catalog consistency', 'WARN', sprintf('n(587.56) - nd = %.1e', Mt.dn_check), '<= 1e-4', ...
                'the dispersion coefficients and the listed nd disagree in the maker''s file; the formula value is used');
        end
        if isfinite(Mt.tau_i)
            rows = add(rows, 'MATERIAL', 'internal transmittance', 'INFO', sprintf('%.4f', Mt.tau_i), sprintf('per %g mm', Mt.it_thickness_mm), ...
                sprintf('at %g nm from the catalog table (bulk absorption only; Fresnel losses are under OPTICS)', Mt.wavelength_nm));
        end
    end
    % per-element materials (design.element_materials): one row each so the report shows which
    % index every element was built with and where it came from
    for k = 1:nitems(elems)
        E = getitem(elems, k);
        e = getf(E, 'element', k);
        nm = getf(E, 'name', '');
        cat = getf(E, 'catalog', '');  if isempty(cat), cat = getf(E, 'maker', ''); end
        if isempty(cat), cat = '-'; end
        wl = getf(E, 'wavelength_nm', []);
        wl_s = '';  if isnumeric(wl) && isscalar(wl) && isfinite(wl), wl_s = sprintf(' | at %g nm', wl); end
        val = sprintf('%s n=%.6f', nm, getf(E, 'n', NaN));  val = strtrim(val);
        if isempty(getf(E, 'warn', ''))
            rows = add(rows, 'MATERIAL', sprintf('element %d material', e), 'INFO', val, '', ...
                sprintf('%s | %s%s', getf(E, 'source', '-'), cat, wl_s));
        else
            rows = add(rows, 'MATERIAL', sprintf('element %d material', e), 'WARN', val, '', ...
                'no dispersion data - index used as written');
        end
        % a LISTED element glass gets the same catalog warnings as the default glass
        % (unlisted elements are the default glass, already reported above)
        Lk = getf(E, 'lookup', []);
        if isstruct(Lk) && ~strcmp(getf(E, 'source', ''), 'default')
            if getf(Lk, 'wavelength_default', false)
                rows = add(rows, 'MATERIAL', sprintf('element %d design wavelength', e), 'WARN', sprintf('%.2f nm', getf(Lk, 'wavelength_nm', NaN)), 'd-line default', ...
                    'design.material.wavelength_nm is null - the catalog reference wavelength was used, not our emitter line');
            end
            st = getf(Lk, 'status', NaN);
            if isequal(st, 2) || isequal(st, 3)
                rows = add(rows, 'MATERIAL', sprintf('element %d catalog status', e), 'WARN', getf(Lk, 'status_str', ''), 'standard/preferred', ...
                    'availability must be confirmed with the maker before quoting');
            end
            dn = getf(Lk, 'dn_check', 0);
            if isnumeric(dn) && isscalar(dn) && abs(dn) > 1e-4
                rows = add(rows, 'MATERIAL', sprintf('element %d catalog consistency', e), 'WARN', sprintf('n(587.56) - nd = %.1e', dn), '<= 1e-4', ...
                    'the dispersion coefficients and the listed nd disagree in the maker''s file; the formula value is used');
            end
        end
    end

    % ---------------------------------------------------------------- SURFACES (prescribed / clamped)
    for j = 1:min(L, nitems(surfs))
        s = getitem(surfs, j);
        kind = getf(s, 'kind', 'built');
        if strcmp(kind, 'sphere')
            c = getf(s, 'center_z_du', NaN);  Rs = getf(s, 'radius_du', NaN);
            xv = getf(s, 'vertex_x_du', c + Rs);
            rows = add(rows, 'SURFACES', sprintf('S%d prescribed sphere', j), 'INFO', sprintf('R=%.4f mm', Rs * mm), ...
                sprintf('center x=%.4f mm', c * mm), ...
                sprintf('vertex x=%.4f mm, last design ray at %.2f deg on the sphere', xv * mm, getf(s, 'theta_max_deg', NaN)));
        elseif strcmp(kind, 'clamped')
            pull = getf(s, 'pull', '-');
            k1 = getf(s, 'first_clamped_ray', Inf);
            if isfinite(k1)
                note = sprintf('active from ray %d (%.2f deg emission) to the fan edge, %d rays', k1, getf(s, 'clamp_from_deg', NaN), getf(s, 'n_clamped', 0));
                d = layer_deficit(B, j);   % the shortfall this clamp hands to the next layers
                if isfinite(d), note = sprintf('%s; carried deficit max %.4f deg', note, d); end
            else
                note = 'never active';
            end
            rows = add(rows, 'SURFACES', sprintf('S%d draft clamp', j), 'INFO', ...
                sprintf('%g deg, pull %s', getf(s, 'max_slope_deg', NaN), pull), '', note);
            dm = logical(getf(s, 'demoldable', true));
            rows = add(rows, 'SURFACES', sprintf('S%d demoldability', j), tern(dm, 'PASS', 'FAIL'), ...
                tern(dm, 'demoldable', 'undercut'), sprintf('pull %s', pull), getf(s, 'demold_note', ''));
        end
    end

    % ---------------------------------------------------------------- SCALE
    if ~isempty(T.warn_scale_mm_per_du) && abs(mm - T.warn_scale_mm_per_du) > 1e-9
        rows = add(rows, 'SCALE', 'mm per design unit', 'WARN', sprintf('%.6f', mm), sprintf('expected %.6f', T.warn_scale_mm_per_du), 'checks.warn_scale_mm_per_du');
    else
        rows = add(rows, 'SCALE', 'mm per design unit', 'INFO', sprintf('%.6f', mm), '', sprintf('WD %.3f mm', cfg.design.WD_mm));
    end

    % ---------------------------------------------------------------- OPTICS
    if ~isempty(trace)
        if isfield(AN, 'collimation') && ~isempty(AN.collimation)
            C = AN.collimation;
            rows = add(rows, 'OPTICS', 'collimation max |dev|', judge(C.max_abs_deg, T.collimation_max_deg, 'max'), ...
                sprintf('%.4f deg', C.max_abs_deg), sprintf('<= %.3f deg', T.collimation_max_deg), ...
                sprintf('worst ray at %.2f deg emission; target %.2f deg', C.worst_ray, C.target_deg));
            rows = add(rows, 'OPTICS', 'collimation RMS', judge(C.rms_deg, T.collimation_rms_deg, 'max'), ...
                sprintf('%.4f deg', C.rms_deg), sprintf('<= %.3f deg', T.collimation_rms_deg), ...
                sprintf('%d of %d rays collected', C.n_collected, C.n_total));
        end
        lost_note = '';
        if trace.n_lost > 0
            la = trace.alphas0(~trace.collected);
            lost_note = sprintf('emission %.2f..%.2f deg; miss %d, TIR %d', min(la), max(la), trace.n_miss, trace.n_tir);
        end
        rows = add(rows, 'OPTICS', 'rays lost (miss or TIR)', judge(trace.n_lost, T.max_lost_rays, 'max'), ...
            sprintf('%d of %d', trace.n_lost, trace.n_rays), sprintf('<= %d', T.max_lost_rays), lost_note);
        rows = add(rows, 'OPTICS', 'rays needing segment overshoot', 'INFO', sprintf('%d', trace.n_overshoot), '', ...
            sprintf('hits past a segment end (allowance %.3g)', cfg.trace.segment_overshoot));
        if isfield(AN, 'fresnel') && ~isempty(AN.fresnel)
            Fr = AN.fresnel;
            if isfinite(Fr.min_tir_margin_deg)
                rows = add(rows, 'OPTICS', 'TIR margin', judge(Fr.min_tir_margin_deg, T.tir_margin_warn_deg, 'min', true), ...
                    sprintf('%.2f deg', Fr.min_tir_margin_deg), sprintf('>= %.1f deg', T.tir_margin_warn_deg), ...
                    sprintf('%s, ray at %.2f deg emission', Fr.labels{max(Fr.min_tir_margin_interface, 1)}, Fr.min_tir_margin_ray_deg));
            end
            rows = add(rows, 'OPTICS', 'Fresnel transmission', 'INFO', sprintf('%.4f', Fr.mean_transmission), '', ...
                sprintf('mean over collected rays, %s, uncoated', Fr.polarization));
        end
    else
        rows = add(rows, 'OPTICS', 'validation trace', 'INFO', 'not run', '', 'trace.enable = false');
    end

    % ---------------------------------------------------------------- GEOMETRY (mm)
    % slopes come from the design profiles: a prescribed sphere is measured on its dense
    % arc instead of the ray-sampled polyline (built layers are returned unchanged)
    FL = design_profiles(lens.final_lens, surfs);
    G = struct('elem', {}, 'OD', {}, 'length', {}, 'mouth', {}, 'vertex_x', {}, 'vertex_R', {}, ...
               'edge_thickness', {}, 'center_thickness', {}, 'max_slope_inner', {}, 'max_slope_outer', {}, 'gap_to_next', {});
    min_edge = inf; min_center = inf; min_gap = inf; max_slope = 0; worst = struct('edge', 0, 'center', 0, 'gap', 0, 'slope', 0);
    for e = 1:nE
        inner = lens.final_lens{2*e-1} * mm;  outer = lens.final_lens{2*e} * mm;
        g.elem = e;
        g.OD     = 2 * max(abs(outer(:,2)));
        g.mouth  = 2 * abs(inner(end,2));
        xs = [inner(:,1); outer(:,1)];  g.length = max(xs) - min(xs);
        [~, iv] = min(abs(inner(:,2)));  g.vertex_x = inner(iv, 1);
        g.vertex_R = vertex_radius(inner);
        Em = M.elements(e);
        g.edge_thickness   = norm(Em.inner(end,:) - Em.outer(end,:)) * mm;   % cap length of the manufacturing profile
        g.center_thickness = (outer(1,1) - inner(1,1));
        g.max_slope_inner = max_slope_deg(FL{2*e-1} * mm);
        g.max_slope_outer = max_slope_deg(FL{2*e} * mm);
        if e < nE
            nxt = lens.final_lens{2*e+1} * mm;
            g.gap_to_next = poly_min_distance(outer, nxt);
        else
            g.gap_to_next = NaN;
        end
        G(e) = g;
        if g.edge_thickness < min_edge, min_edge = g.edge_thickness; worst.edge = e; end
        if g.center_thickness < min_center, min_center = g.center_thickness; worst.center = e; end
        if ~isnan(g.gap_to_next) && g.gap_to_next < min_gap, min_gap = g.gap_to_next; worst.gap = e; end
        ms = max(g.max_slope_inner, g.max_slope_outer);
        if ms > max_slope, max_slope = ms; worst.slope = e; end
    end
    rows = add(rows, 'GEOMETRY', 'edge thickness', judge(min_edge, T.min_edge_thickness_mm, 'min'), ...
        sprintf('%.3f mm', min_edge), sprintf('>= %.3f mm', T.min_edge_thickness_mm), ...
        sprintf('element %d, at the last design ray (cap of the manufacturing profile)', worst.edge));
    rows = add(rows, 'GEOMETRY', 'center thickness', judge(min_center, T.min_center_thickness_mm, 'min'), ...
        sprintf('%.3f mm', min_center), sprintf('>= %.3f mm', T.min_center_thickness_mm), sprintf('element %d', worst.center));
    if nE > 1
        rows = add(rows, 'GEOMETRY', 'air gap between elements', judge(min_gap, T.min_air_gap_mm, 'min'), ...
            sprintf('%.3f mm', min_gap), sprintf('>= %.3f mm', T.min_air_gap_mm), sprintf('elements %d-%d, minimum over the surfaces', worst.gap, worst.gap + 1));
    end
    reent = max_slope > T.max_re_entrant_slope_deg;
    rows = add(rows, 'GEOMETRY', 're-entrant surfaces', 'INFO', sprintf('max slope %.1f deg', max_slope), sprintf('> %.0f deg = overhang', T.max_re_entrant_slope_deg), ...
        sprintf('element %d; %s', worst.slope, tern(reent, 'split-and-bond required (or molding impossible without split)', 'no overhang')));
    if cfg.process.draft_deg > 0
        rows = add(rows, 'GEOMETRY', 'molding draft', judge(90 - max_slope, cfg.process.draft_deg, 'min', true), ...
            sprintf('%.1f deg', 90 - max_slope), sprintf('>= %.1f deg', cfg.process.draft_deg), 'slope margin to the pull direction (axis)');
    end
    if cfg.process.min_wall_mm > 0
        rows = add(rows, 'GEOMETRY', 'molding min wall', judge(min(min_edge, min_center), cfg.process.min_wall_mm, 'min', true), ...
            sprintf('%.3f mm', min(min_edge, min_center)), sprintf('>= %.3f mm', cfg.process.min_wall_mm), 'min of edge and center thickness');
    end

    % cut plane crossings (listed elements)
    if cfg.process.cut.enable && T.require_single_cut_crossing
        els = cfg.run.elements(:).';  x0s = cfg.process.cut.x0_mm(:).';
        if numel(x0s) == 1, x0s = repmat(x0s, size(els)); end
        for k = 1:numel(els)
            e = els(k);  x0 = x0s(k);
            for side = 1:2
                P = M.final_lens{2*e - 2 + side} * mm;
                nc = sum((P(1:end-1,1) - x0) .* (P(2:end,1) - x0) < 0);
                rows = add(rows, 'GEOMETRY', sprintf('cut plane element %d %s', e, tern(side == 1, 'S1 inner', 'S2 outer')), ...
                    judge(abs(nc - 1), 0, 'max'), sprintf('%d crossing(s)', nc), '= 1', sprintf('x = %+.3f mm', x0));
            end
        end
    end

    % fillet / truncation fan loss
    if M.changed
        R = size(lens.gamma_matrix, 1);
        alpha0 = (0:R-1) * (lens.design_max_angle - cfg.design.fan_epsilon_deg) / (R - 1);
        [w, ~] = emitter_weights(alpha0, cfg.emitter);
        if isfinite(M.first_lost_ray) && M.first_lost_ray <= R
            lost = sum(w(M.first_lost_ray:end)) / sum(w) * 100;
            a_lost = alpha0(M.first_lost_ray);
        else
            lost = 0;  a_lost = NaN;
        end
        rows = add(rows, 'GEOMETRY', 'fan lost to fillet/truncation', judge(lost, T.max_fillet_fan_loss_pct, 'max', true), ...
            sprintf('%.2f %%', lost), sprintf('<= %.2f %%', T.max_fillet_fan_loss_pct), ...
            tern(lost > 0, sprintf('design rays from %.2f deg to the fan edge', a_lost), 'no design ray removed'));
    end

    CK.rows = rows;
    CK.geometry = G;
    st = {rows.status};
    CK.n_fail = sum(strcmp(st, 'FAIL'));
    CK.n_warn = sum(strcmp(st, 'WARN'));
    if CK.n_fail > 0, CK.verdict = 'FAIL'; else, CK.verdict = 'PASS'; end
end

function rows = add(rows, section, name, status, value, threshold, note)
    if nargin < 7, note = ''; end
    rows(end+1) = struct('section', section, 'name', name, 'status', status, 'value', value, 'threshold', threshold, 'note', note);
end

function s = judge(v, limit, mode, warn)   % mode: 'max' (v must be <= limit) | 'min' (v must be >= limit)
    if nargin < 4, warn = false; end
    tol = 1e-9 * max(1, abs(limit));
    bad = (strcmp(mode, 'max') && v > limit + tol) || (strcmp(mode, 'min') && v < limit - tol);
    if ~bad, s = 'PASS'; elseif warn, s = 'WARN'; else, s = 'FAIL'; end
end

function R = vertex_radius(surf)
    % base radius near the on-axis vertex from sag ~ r^2/(2R) (as in the drawing)
    r = abs(surf(:,2));  z = surf(:,1);
    [~, iv] = min(r);  zv = z(iv);
    [~, ip] = min(abs(r - 0.25*max(r)));
    dz = abs(z(ip) - zv);
    if dz < 1e-6, R = Inf; else, R = r(ip)^2 / (2*dz); end
end

function s = max_slope_deg(P)
    % surface-normal angle from the optical axis per segment (>90 = overhang), as in the sag table
    x = P(:,1);  r = abs(P(:,2));
    s = max(atan2d(abs(diff(x)), diff(r)));
end

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end

% ---------------------------------------------------------------------------
% optional lens fields: every accessor tolerates a missing field so a lens loaded
% from an older lens.mat (or design.from_mat) still produces the full table
function [Mt, elems] = material_parts(lens)
    % lens.material is either the catalog lookup itself (single glass, older lens.mat) or the
    % per-element struct {default, elements}; both must keep working
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
    % the threshold lives in cfg.checks like every other one; the budget's own tol_deg is the
    % fallback for a config written before the key existed
    tol = [];
    if isfield(cfg.checks, 'bending_budget_tol_deg'), tol = cfg.checks.bending_budget_tol_deg; end
    if isempty(tol), tol = getf(B, 'tol_deg', []); end
    if isempty(tol), tol = 0.01; end
end

function s = budget_status(B, tol)
    % closed = every design ray leaves the last built surface within tol of its planned exit
    % angle and every Snell solve was realisable; the construction's own verdict (closed) can
    % only make it stricter
    s = judge(getf(B, 'max_residual_deg', NaN), tol, 'max');
    if getf(B, 'n_unphysical', 0) > 0, s = 'FAIL'; end
    if ~logical(getf(B, 'closed', true)), s = 'FAIL'; end
end

function d = layer_deficit(B, j)
    % max bending deficit leaving layer j (NaN when the budget has no per-layer record)
    d = NaN;
    if isempty(B), return; end
    pl = getf(B, 'per_layer', []);
    if nitems(pl) >= j, d = getf(getitem(pl, j), 'deficit_max', NaN); end
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
