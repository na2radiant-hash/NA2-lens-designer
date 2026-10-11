function lens = build_lens(cfg, mat, emat)
%BUILD_LENS  Construct the lens described by cfg.design (or load one from a .mat).
%
%   lens = build_lens(cfg, mat, emat)
%     mat   provenance of design.n_lens when it came from a glass catalog
%           (resolve_material output) or [] - stored as lens.material.default.
%     emat  per-element material list (resolve_material output, one entry per
%           element; unlisted elements carry the default) or [] - stored as
%           lens.material.elements and turned into the per-surface indices.
%
%   Dispatches on the design flags:
%     - standard omni construction (LensConstructionGradual), with
%       truncation (TunedWeightsTest) and/or glass spacers (Relaxated...GlassGap)
%       folded into construct_lens, the solver / partial-collimation /
%       design-budget options folded into calculate_angles, and the Isuzu
%       molding variants: per-element materials (design.element_materials),
%       prescribed spheres (design.spherical_surfaces) and slope clamps
%       (design.slope_limits);
%     - two-stage omni + commercial asphere (LensConstructionGradual_3Elem)
%       through construct_two_stage;
%     - design.from_mat: skip construction and load an existing lens_data .mat
%       (legacy designs, fast figure iteration).
%
%   lens fields: final_lens (cell, du), L, n1, n2, source_pos, gamma_matrix,
%   theta_in_matrix, theta_out_matrix, design_max_angle (construction fan), nominal_max_angle (from NA_hole),
%   designed_max_angle (= design fan - fan_epsilon: the last design ray, the default trace limit),
%   mm_per_du, cstats, glass_info ([]), asphere ([] or struct), source ('built'|'loaded'),
%   material (struct: default = the catalog lookup or [], elements = per-element list),
%   element_n (index per element), n_surface ([L x 2] n_in / n_out per surface),
%   surfaces (1 x L, kind 'built' | 'sphere' | 'clamped' + their numbers, see surface_template),
%   budget (bending budget per ray and surface, [] for a loaded lens).

    if nargin < 2, mat = []; end
    if nargin < 3, emat = []; end
    D = cfg.design;
    if isempty(D.n_lens)
        error('build_lens:n_lens', 'design.n_lens is empty and no material was resolved - set design.n_lens or design.material.name');
    end
    mm_per_du = D.WD_mm;                       % inner vertex sits at 1 du by construction
    source_pos = [0, 0];

    if isempty(D.fan_max_deg_override)
        nominal_max_angle = 180 - asind(D.NA_hole);
        design_max_angle  = 180 - asind(D.NA_hole + D.NA_design_margin);
    else
        nominal_max_angle = D.fan_max_deg_override;
        design_max_angle  = nominal_max_angle;
    end

    % ---- per-element index -> per-surface (n_in, n_out) ----
    %      odd surfaces enter the element (n_outside -> n_e), even ones leave it
    L = D.layers_count;  nE = floor(L / 2);
    element_n = D.n_lens * ones(1, nE);
    if ~isempty(emat)
        for e = 1:numel(emat)
            if ~isempty(emat(e).element) && ~isempty(emat(e).n) && emat(e).element >= 1 && emat(e).element <= nE
                element_n(emat(e).element) = emat(e).n;
            end
        end
    end
    n_surface = zeros(L, 2);
    for j = 1:L
        e = ceil(j / 2);
        if mod(j, 2) == 1, n_surface(j, :) = [D.n_outside, element_n(e)]; else, n_surface(j, :) = [element_n(e), D.n_outside]; end
    end
    material = struct('default', {mat}, 'elements', {emat});

    lens = struct('final_lens', [], 'L', L, 'n1', D.n_outside, 'n2', D.n_lens, ...
                  'source_pos', source_pos, 'gamma_matrix', [], 'theta_in_matrix', [], ...
                  'theta_out_matrix', [], 'design_max_angle', design_max_angle, ...
                  'nominal_max_angle', nominal_max_angle, 'designed_max_angle', design_max_angle - D.fan_epsilon_deg, 'mm_per_du', mm_per_du, ...
                  'cstats', struct('attempts', [], 'fallbacks', 0, 'failsafe_layer1', 0), ...
                  'glass_info', [], 'asphere', [], 'source', 'built', 'material', {material}, ...
                  'element_n', element_n, 'n_surface', n_surface, 'surfaces', [], 'budget', []);

    % ---------------------------------------------------------------- load
    if isfield(D, 'from_mat') && ~isempty(D.from_mat)
        if ~exist(D.from_mat, 'file'), error('build_lens:mat', 'design.from_mat not found: %s', D.from_mat); end
        S = load(D.from_mat, '-mat');    % '-mat': some legacy design files carry a ".m" name
        req = {'final_lens', 'n1', 'n2', 'layers_count'};
        for k = 1:numel(req)
            if ~isfield(S, req{k}), error('build_lens:mat', 'design.from_mat is missing "%s": %s', req{k}, D.from_mat); end
        end
        lens.final_lens = S.final_lens(:);
        lens.L  = S.layers_count;
        lens.n1 = S.n1;   lens.n2 = S.n2;
        if isfield(S, 'gamma_matrix'),     lens.gamma_matrix     = S.gamma_matrix;     end
        if isfield(S, 'theta_in_matrix'),  lens.theta_in_matrix  = S.theta_in_matrix;  end
        if isfield(S, 'theta_out_matrix'), lens.theta_out_matrix = S.theta_out_matrix; end
        if isfield(S, 'glass_info'),       lens.glass_info       = S.glass_info;       end
        if isfield(S, 'asphere'),          lens.asphere          = S.asphere;          end
        if isfield(S, 'source_pos') && ~isempty(S.source_pos), lens.source_pos = S.source_pos(:).'; end
        % the loaded lens was built with ONE index (n2): every element gets it
        lens.element_n = S.n2 * ones(1, floor(lens.L / 2));
        lens.n_surface = expand_nsurf([S.n1, S.n2], lens.L);
        lens.surfaces  = repmat(surface_template('built'), 1, lens.L);
        % ... unless the file is a package lens.mat of this pipeline: it carries the per-surface
        % indices, the surface kinds (sphere arcs, clamps) and the per-element materials it was built with
        if isfield(S, 'n_surface') && isequal(size(S.n_surface), [lens.L, 2]), lens.n_surface = S.n_surface; end
        if isfield(S, 'element_n') && numel(S.element_n) == floor(lens.L / 2), lens.element_n = S.element_n(:).'; end
        if isfield(S, 'surfaces') && isstruct(S.surfaces) && numel(S.surfaces) == lens.L && isfield(S.surfaces, 'kind')
            lens.surfaces = S.surfaces(:).';
        end
        if isfield(S, 'material') && isstruct(S.material) && isfield(S.material, 'elements') && ~isempty(S.material.elements)
            lens.material.elements = S.material.elements;
        end
        if isfield(S, 'budget') && isstruct(S.budget), lens.budget = S.budget; end
        % scale: the legacy scripts used an inner vertex at 0.5 or 1 du; WD_mm is the
        % physical focus->vertex distance in every case
        [~, iv] = min(abs(lens.final_lens{1}(:,2)));
        lens.mm_per_du = D.WD_mm / lens.final_lens{1}(iv, 1);
        lens.source = sprintf('loaded from %s', D.from_mat);
        if abs(lens.n2 - D.n_lens) > 1e-9
            warning('build_lens:index', 'design.n_lens = %.4f but the loaded .mat was built with n2 = %.4f (the .mat wins).', D.n_lens, lens.n2);
        end
        return;
    end

    % ---------------------------------------------------------------- build
    w   = D.weights;
    sol = D.solver;
    aopts = struct('method', sol.method, 'collimation_fraction', D.collimation_fraction, ...
                   'L_design', D.layers_design_budget);
    copts = struct('angles', aopts, 'truncate', D.truncation.enable, ...
                   'edge_min', D.truncation.edge_min_thickness_mm / mm_per_du);   % mm -> du
    if D.glass_cell.enable
        copts.glass = struct('enable', true, 'before_elements', D.glass_cell.before_elements, ...
                             'n_glass', D.glass_cell.n_glass, 'width_du', D.glass_cell.width_mm / mm_per_du, ...
                             'height_factor', D.glass_cell.height_factor);
    end
    % Isuzu molding variants (all empty in the shipped example)
    copts.spheres = objlist_rows(field_or(D, 'spherical_surfaces', []), {'surface', 'center_z_du', 'radius_du'});
    for k = 1:numel(copts.spheres)
        if isempty(copts.spheres(k).center_z_du)          % surface 1: centre derived so the vertex stays at 1 du
            copts.spheres(k).center_z_du = 1 - copts.spheres(k).radius_du;
        end
    end
    copts.clamps = objlist_rows(field_or(D, 'slope_limits', []), {'surface', 'max_slope_deg', 'pull'});
    copts.budget_tol_deg = 0.01;
    if isfield(cfg, 'checks') && isfield(cfg.checks, 'bending_budget_tol_deg') && ~isempty(cfg.checks.bending_budget_tol_deg)
        copts.budget_tol_deg = cfg.checks.bending_budget_tol_deg;
    end

    if D.commercial_asphere.enable
        lens = construct_two_stage(lens, D, w, sol, copts, mm_per_du, n_surface);
        return;
    end

    [final_lens, gamma_m, thin_m, thout_m, cstats, glass_info, surfaces, budget] = construct_lens( ...
        D.layers_count, D.rays_count, n_surface, source_pos, design_max_angle, ...
        w, D.fan_epsilon_deg, D.collimation_target_deg, sol, copts);
    lens.final_lens       = final_lens;
    lens.gamma_matrix     = gamma_m;
    lens.theta_in_matrix  = thin_m;
    lens.theta_out_matrix = thout_m;
    lens.cstats           = cstats;
    lens.glass_info       = glass_info;
    lens.surfaces         = surfaces;
    lens.budget           = budget;
end

% ---------------------------------------------------------------------------
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
        if ~isstruct(it), error('build_lens:objlist', 'list item %d is not an object', k); end
        row = cell2struct(repmat({[]}, numel(fields), 1), fields(:), 1);
        for f = 1:numel(fields)
            if isfield(it, fields{f}), row.(fields{f}) = it.(fields{f}); end
        end
        S(end+1) = row; %#ok<AGROW>
    end
end
