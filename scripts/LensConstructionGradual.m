function LensConstructionGradual(config_path)
%LENSCONSTRUCTIONGRADUAL  Build, validate, export and document the omnidirectional lens from ONE config.
%
%   Two equivalent ways to run:
%     1) command window, naming the config:
%            LensConstructionGradual('inputs/config_example.json')
%            LensConstructionGradual('C:\...\my_vendor_config.json')
%     2) Play button / F5 / "run" with no argument:
%            uses DEFAULT_CONFIG below - the one line in this file you may edit.
%   Paths may be absolute or relative to the NA2 folder (the parent of scripts/).
%
%   Apart from DEFAULT_CONFIG this file contains NO user inputs: every setting
%   comes from the config (documented key by key in inputs/config_example.json).
%
%   Pipeline (each stage is a function in scripts/lib/, see scripts/README.md):
%     read_config -> validate_config -> resolve_material -> make_output_folder -> build_lens
%     -> apply_process -> trace_rays -> analyses -> run_checks
%     -> export_all + drawings + paper figures -> write_report (+ runs_index.csv)
%   sweep.enable repeats the whole pipeline for each value of one config key.
%
%   Every legacy script of this repository is available through config flags
%   (construction variants, validation trace, Fresnel / intensity / collection
%   analyses, DXF / Zemax exports, paper figures, parameter sweeps); the
%   originals are kept under "old stuff" for reference only.
%   ============================================================

%% ==== RUN MODE: which mode the Play button / F5 / VS Code Run uses ==========
%   'paper'  = PAPER FIGURES, manual: builds the paper lenses from the values
%              typed in PAPER below and writes only the panels of
%              Final Figures.pptx (Fig 1A, 1B, 1E, 1F, 2C, 3B, 3C) and the tolerance
%              figure (Fig S) to outputs/paper_figures/.
%              No config file.
%   'vendor' = VENDOR PACKAGE, config-driven: the pipeline below, run on
%              DEFAULT_CONFIG (section 0).
%   A call with a config path, LensConstructionGradual('inputs/x.json'),
%   is always vendor mode.
RUN_MODE = 'paper';     % 'paper' | 'vendor'

%% ==== PAPER FIGURES: manual parameters (used only when RUN_MODE = 'paper') ====
%   The defaults are the values behind the published panels. Each figure builds
%   its own lens: design fan alpha_i = (i-1)*(fan_max_deg - fan_eps_deg)/(design_rays-1),
%   inner vertex at 1 du, source at the origin.
% --- Fig 1A (zoom) + Fig 1B (full view) -------------------------------------
PAPER.fig1AB.enable      = false;
PAPER.fig1AB.n2          = 2.003;    % lens refractive index
PAPER.fig1AB.layers      = 8;        % surfaces (2 per element -> 4 elements)
PAPER.fig1AB.design_rays = 2000;      % rays the lens is CONSTRUCTED with
PAPER.fig1AB.fan_max_deg = 162.54;   % design fan edge (180 - asind(NA_hole 0.3), rounded as in the paper lens)
PAPER.fig1AB.fan_eps_deg = 0;        % last design ray at fan_max_deg - fan_eps_deg
PAPER.fig1AB.drawn_rays  = 10;       % rays DRAWN in the upper half (mirrored -> 19 lines)
PAPER.fig1AB.zoom_half   = 10;       % Fig 1A window half-size [du] ([] = auto-frame 2 inner elements)
% --- Fig 1E (2-D rays) + Fig 1F (3-D rays) -----------------------------------
PAPER.fig1EF.enable      = false;
PAPER.fig1EF.n2          = 2.003;
PAPER.fig1EF.layers      = 8;
PAPER.fig1EF.design_rays = 2000;
PAPER.fig1EF.fan_max_deg = 180;      % full omnidirectional design fan ...
PAPER.fig1EF.fan_eps_deg = 0.1;      % ... up to 179.9 deg
PAPER.fig1EF.ray_angles  = [0 80 150 178];                                      % traced emission angles [deg]
PAPER.fig1EF.arrow_segs  = {[4 6 8 9], [4 6 8 9], [3 4 5 6 7 8 9], [3 4 5 6 7 8 9]}; % Fig 1E arrowhead segments per ray
PAPER.fig1EF.n_copies    = 4;        % Fig 1F azimuthal copies of each ray
PAPER.fig1EF.circles     = true;     % Fig 1F output-aperture circles
PAPER.fig1EF.emitter_r   = 2.0;      % Fig 1F emitter ball radius [du]
PAPER.fig1EF.triad       = true;     % Fig 1F z/x/y direction triad
% --- Fig 2C: simulation of the experimental prototype -------------------------
PAPER.fig2C.enable       = false;
PAPER.fig2C.n2           = 1.58;     % prototype material
PAPER.fig2C.layers       = 16;       % 8 elements
PAPER.fig2C.design_rays  = 2000;
%PAPER.fig2C.fan_max_deg  = 180 - asind(0.3);   % NA_hole 0.3
PAPER.fig2C.fan_max_deg  = 180;   

PAPER.fig2C.fan_eps_deg  = 0.1;
PAPER.fig2C.drawn_rays   = 6;        % used only when ray_angles = []: evenly spaced fan, mirrored -> 11 lines
PAPER.fig2C.ray_angles   = [0 25 59 87 117 139 161];   % emission angles of the drawn rays [deg]: axis ray +
                                     % 6 per half (mirrored) = 13 lines, matched to the laser photo's exit heights.
                                     % 161 deg ~ last collimated ray (161.35); steeper rays leave through the mouth.
                                     % Evenly spaced alternative: [0 25 52 79 107 134 161]
PAPER.fig2C.zoom         = true;     % also export the zoom on the inner elements (fig2C_zoom.*), for the inset
PAPER.fig2C.zoom_half    = [];       % zoom window half-size [du]; [] = auto: frames zoom_elements fully + 8 %
PAPER.fig2C.zoom_elements = 1;       % inner elements (crescents) fully enclosed by the auto zoom window
% --- Fig 3B (collection efficiency vs NA) + Fig 3C (lens zoom with theta_0) --
%     one figure, labelled + label-free copies; Fig 3C uses the Fig 1A/1B lens above
PAPER.fig3BC.enable      = false;
PAPER.fig3BC.targets     = [0.99, 0.999];   % collection levels marked on the dipole curve (99 %, 99.9 %)
PAPER.fig3BC.x_axis      = 'theta';        % 'theta' = theta_0 = FULL mouth angle (tip to mirrored tip), 0-180 deg;
                                           %           Fig 3C arc spans the whole inner mouth
                                           % 'NA'    = NA = sin(half-angle), 0-1; Fig 3C shows the half-angle (published panel)
% --- Fig S: fabrication tolerances (lambda/2 surfaces, lambda/4 split-element alignment) -------
%     Monte Carlo on the sapphire design: reference beam vs perturbed beam at a distance D
%     (see sim_tolerance.m). Writes figS_tolerance.* and tolerance_results.csv.
PAPER.tol.enable          = true;
PAPER.tol.n2              = 1.77;    % sapphire
PAPER.tol.layers          = 8;
PAPER.tol.design_rays     = 400;     % finer point table than the figures (the surfaces are traced as smooth splines)
PAPER.tol.fan_max_deg     = 180 - asind(0.3);   % NA_hole 0.3
PAPER.tol.fan_eps_deg     = 0.1;
PAPER.tol.lambda_nm       = 632.8;   % test wavelength of the catalog specs
PAPER.tol.surface_pv_waves = 0.5;    % check 1: lambda/2 peak-to-valley figure error on every surface
PAPER.tol.align_waves     = 0.25;    % check 2: lambda/4 offset (transverse and axial) between the two parts of element 1
PAPER.tol.align_sweep_waves = [1/16 1/8 1/4 1/2 1];   % alignment errors drawn in Fig S C (in waves)
PAPER.tol.cut_x_mm        = -1.30;   % axis-normal bonding plane of element 1 (source at x = 0)
PAPER.tol.corr_len_mm     = [0.5 1 2 5];   % correlation lengths (bump sizes) of the figure error
PAPER.tol.distances_m     = [0.1 1]; % observation distances reported in the table / console
PAPER.tol.dist_grid_m     = logspace(-1.5, 0.5, 25);   % distances of the loss-vs-distance curve (0.03-3 m)
PAPER.tol.n_trials        = 100;     % Monte Carlo realisations per correlation length
PAPER.tol.n_rays          = 4001;    % traced emission angles (upper half)
PAPER.tol.emitter         = 'dipole';   % 'dipole' (axial, as in Fig. 3) | 'isotropic'
PAPER.tol.seed            = 1;
% --- common to all paper figures ----------------------------------------------
PAPER.common.n1             = 1;         % outside medium
PAPER.common.weights        = struct('J_front', 10, 'k_shape', 0.8, 'base_w', 0.8, ...
                                     'hardness_exp', 2.0, 'layer_exp', 1.2);   % bending split over the surfaces
PAPER.common.jump_size_du   = 0.1;       % construction step between surface vertices [du]
PAPER.common.draw_max_deg   = 162.5;     % Fig 1A/1B/2C: last drawn ray before auto-tuning [deg]
PAPER.common.draw_eps_deg   = 1e-6;      % drawn fan = [eps, max - eps]
PAPER.common.auto_max_angle = true;      % end the drawn fan at the marginal ray that still collimates
PAPER.out_dir               = 'outputs/paper_figures';   % relative to the NA2 folder; files are overwritten

close all;    % every run (paper or vendor) starts with no figures from previous runs

if (nargin < 1 || isempty(config_path)) && strcmpi(RUN_MODE, 'paper')
    paperDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(paperDir, 'lib', 'paper_sim'));
    run_paper_simulation(PAPER, fileparts(paperDir));
    return;
elseif ~any(strcmpi(RUN_MODE, {'paper', 'vendor'}))
    error('LensConstructionGradual:runMode', 'RUN_MODE must be ''paper'' or ''vendor'' (got ''%s'').', RUN_MODE);
end

%% ---- 0. DEFAULT CONFIG: used by the Play button / a call without argument ----
DEFAULT_CONFIG = 'inputs/config_isuzu_BC.json';  % <-- edit this pointer to run another config (baseline: inputs/config_example.json; PMMA element 1: inputs/config_isuzu_A.json)

scriptDir = fileparts(mfilename('fullpath'));
projRoot  = fullfile(scriptDir, '..');
addpath(genpath(fullfile(scriptDir, 'lib')));

%% ---- 1. configuration (the only input) --------------------------------
if nargin < 1 || isempty(config_path)
    config_path = DEFAULT_CONFIG;
    fprintf('No config argument given - using DEFAULT_CONFIG from this file: %s\n', config_path);
end
if ~(ischar(config_path) || isstring(config_path))
    error('LensConstructionGradual:usage', 'The argument must be a config path, e.g. LensConstructionGradual(''inputs/config_example.json'')');
end
config_path = char(config_path);
if ~is_absolute_path(config_path), config_path = fullfile(projRoot, config_path); end
[cfg, cfg_info] = read_config(config_path);          % JSON -> struct, _doc keys removed
cfg_info.n_keys = validate_config(cfg);              % unknown / missing / type / range -> error
cfg = resolve_paths(cfg, projRoot);                  % design.from_mat relative to NA2
resolve_material(cfg, projRoot);                     % early check only: an unknown glass stops here, before any folder is made
if cfg.run.close_figures_at_start, close all; end    % the screen shows this run only

%% ---- 2. single run or sweep -------------------------------------------
if cfg.sweep.enable
    run_sweep(cfg, cfg_info, projRoot, config_path);
else
    run_one(cfg, cfg_info, projRoot, config_path, []);
end
end

%% ============================================================
%  ONE COMPLETE RUN
%% ============================================================
function R = run_one(cfg, cfg_info, projRoot, config_path, folder_opts)
tStart = tic;
[cfg, mat, emat] = resolve_material(cfg, projRoot); % again here: a sweep may have changed the wavelength
cfg_info.material  = mat;                            % the default glass (catalog lookup or [])
cfg_info.materials = emat;                           % one entry per element (design.element_materials)
out = make_output_folder(cfg, projRoot, config_path, folder_opts);
if cfg.run.log_console
    diary(fullfile(out.pkg, 'build.log')); diary on;
    diaryCleanup = onCleanup(@() diary('off')); %#ok<NASGU>
end
fprintf('=== NA2 run %s / %s  %s ===\nconfig : %s\npackage: %s\n', cfg.run.vendor, out.design_tag, ['Rev ' out.revlabel], config_path, out.pkg);

stats = struct('ok', false, 'err', '', 'runtime_s', 0, 'git', git_hash(projRoot), 'matlab', version, ...
               'lens', [], 'unwired', {unconsumed_keys(cfg)});
CK = [];  AN = struct();  err_obj = [];
glass_label = sprintf('%s (n = %.4g)', cfg.run.material, cfg.design.n_lens);
if ~isempty(mat), glass_label = sprintf('%s %s (n = %.4f at %g nm)', mat.maker, mat.name, mat.n, mat.wavelength_nm); end
glass_label = mixed_glass_label(emat, glass_label);   % 'E1 PMMA (...) | others ...' when elements differ
dmeta = struct('rev', ['Rev ' out.revlabel], 'glass', glass_label, ...
               'note', cfg.run.notes, 'watermark', cfg.figures.rfq.watermark, 'png_dpi', cfg.figures.rfq.png_dpi);
try
    %% ---- 3. construction -------------------------------------------------
    fprintf('--- Lens Construction Phase ---\n');
    lens = build_lens(cfg, mat, emat);
    stats.lens = lens;
    if ~isempty(mat)
        fprintf('Material %s (%s): n = %.6f at %g nm%s (catalog nd %.5f, vd %.2f, %s).\n', mat.name, mat.catalog, mat.n, ...
            mat.wavelength_nm, tern(mat.wavelength_default, ' [d-line default - no wavelength given]', ''), mat.nd, mat.vd, mat.status_str);
    end
    for e = 1:numel(emat)
        if ~strcmp(emat(e).source, 'default')
            fprintf('Element %d material: %s [%s]%s\n', e, emat(e).label, emat(e).source, tern(isempty(emat(e).warn), '', [' WARN ' emat(e).warn]));
        end
    end
    fprintf('Lens %s: %d surfaces, mm_per_du = %.6f (solver fallbacks %d, layer-1 failsafes %d).\n', ...
        lens.source, lens.L, lens.mm_per_du, lens.cstats.fallbacks, lens.cstats.failsafe_layer1);
    if isfield(lens, 'surfaces') && ~isempty(lens.surfaces)
        for j = 1:numel(lens.surfaces)
            sj = lens.surfaces(j);
            switch sj.kind
                case 'sphere'
                    fprintf('Surface %d: prescribed sphere, centre x = %.4f du, R = %.4f du (vertex x = %.4f du, last design ray at %.2f deg on the sphere).\n', ...
                        j, sj.center_z_du, sj.radius_du, sj.vertex_x_du, sj.theta_max_deg);
                case 'clamped'
                    if isfinite(sj.first_clamped_ray)
                        fprintf('Surface %d: slope limit %g deg (pull %s) active from design ray %d (%.2f deg emission), %d rays; demoldable: %s%s\n', ...
                            j, sj.max_slope_deg, sj.pull, sj.first_clamped_ray, sj.clamp_from_deg, sj.n_clamped, tern(sj.demoldable, 'yes', 'NO'), ...
                            tern(isempty(sj.demold_note), '', [' - ' sj.demold_note]));
                    else
                        fprintf('Surface %d: slope limit %g deg (pull %s) never active; demoldable: %s\n', j, sj.max_slope_deg, sj.pull, tern(sj.demoldable, 'yes', 'NO'));
                    end
            end
        end
    end
    if isfield(lens, 'budget') && ~isempty(lens.budget) && isstruct(lens.budget)
        Bg = lens.budget;
        fprintf('Bending budget: %s (max exit residual %.4f deg at %.2f deg emission, tol %g deg, %d unrealisable Snell solves).\n', ...
            tern(Bg.closed, 'closed', 'NOT CLOSED'), Bg.max_residual_deg, Bg.worst_ray_deg, Bg.tol_deg, Bg.n_unphysical);
    end
    stack = build_stack(lens);

    %% ---- 4. manufacturing profile (truncation / fillet) --------------------
    M = apply_process(lens, cfg);
    if M.changed, fprintf('Manufacturing profile: tip truncation %.3f mm, edge fillet %.3f mm applied.\n', cfg.process.tip_truncate_mm, cfg.process.edge_fillet_mm); end

    %% ---- 5. validation trace + analyses -------------------------------------
    trace = [];
    if cfg.trace.enable
        T = cfg.trace;
        T.extend_len = cfg.trace.extend_factor * lens_length(lens);
        T.collimation_target_deg = cfg.design.collimation_target_deg;  T.collimation_fraction = cfg.design.collimation_fraction;
        if T.auto_max_angle
            [a_max, ok] = auto_max_angle(lens, stack, T, T.auto_max_iters, T.auto_collimation_tol_deg);
            if ok, fprintf('Auto max angle: %.4f deg (nominal %.4f).\n', a_max, lens.nominal_max_angle); T.max_angle_deg = a_max;
            else,  warning('LensConstructionGradual:autoMax', 'auto_max_angle: even the 90-degree ray fails; keeping the nominal fan.'); end
        end
        trace = trace_rays(lens, stack, T);
        fprintf('Validation trace: %d rays, %d collected, %d miss, %d TIR, %d needed segment overshoot.\n', ...
            trace.n_rays, sum(trace.collected), trace.n_miss, trace.n_tir, trace.n_overshoot);
        A = cfg.analysis;
        if A.collimation.enable,        AN.collimation = analyze_collimation(trace, cfg.design.collimation_target_deg, cfg.design.collimation_fraction); end
        if A.fresnel.enable,            AN.fresnel     = analyze_fresnel(trace, stack, A.fresnel.polarization); end
        if A.intensity_profile.enable
            px = A.intensity_profile.plane_x_mm;  if ~isempty(px), px = px / lens.mm_per_du; end
            AN.profile = analyze_intensity_profile(trace, lens, cfg.emitter, px, A.intensity_profile.n_bins);
        end
        if A.collection_efficiency.enable
            AN.collection = analyze_collection(trace, lens, cfg.emitter, A.collection_efficiency.targets, A.collection_efficiency.theta_lens_deg);
        end
        if A.save_csv, write_analysis_csv(AN, trace, stack, lens, out.analysis); end
    end

    %% ---- 6. checks -------------------------------------------------------------
    CK = run_checks(lens, M, trace, AN, cfg);
    fprintf('Checks: %s (%d fail, %d warn)\n', CK.verdict, CK.n_fail, CK.n_warn);

    %% ---- 7. save the lens data (same variable names as the legacy .mat files) ---
    final_lens = lens.final_lens; n1 = lens.n1; n2 = lens.n2; layers_count = lens.L; source_pos = lens.source_pos; %#ok<NASGU>
    gamma_matrix = lens.gamma_matrix; theta_in_matrix = lens.theta_in_matrix; theta_out_matrix = lens.theta_out_matrix; %#ok<NASGU>
    mm_per_du = lens.mm_per_du; lens_mfg = M.final_lens; glass_info = lens.glass_info; asphere = lens.asphere; %#ok<NASGU>
    checks = CK; analyses = AN; material = lens.material; %#ok<NASGU>
    surfaces = lens.surfaces; budget = lens.budget; n_surface = lens.n_surface; element_n = lens.element_n; %#ok<NASGU>
    meta = struct('config_path', config_path, 'config_sha1', cfg_info.sha1, 'date', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                  'matlab', version, 'git', stats.git, 'source', lens.source, 'design_max_angle', lens.design_max_angle, ...
                  'nominal_max_angle', lens.nominal_max_angle, 'construction', lens.cstats); %#ok<NASGU>
    save(fullfile(out.pkg, 'lens.mat'), 'final_lens', 'n1', 'n2', 'layers_count', 'source_pos', 'gamma_matrix', ...
         'theta_in_matrix', 'theta_out_matrix', 'mm_per_du', 'lens_mfg', 'glass_info', 'asphere', 'material', ...
         'n_surface', 'element_n', 'surfaces', 'budget', 'cfg', 'meta', 'checks', 'analyses');
    fprintf('Lens data saved to %s\n', fullfile(out.pkg, 'lens.mat'));

    %% ---- 8. pictures of the RESULT: every run gets them, PASS or FAIL ------------
    %      construction geometry (SVG + PNG), validation ray trace, 3-D preview, whole-lens
    %      overview, paper panels. A picture that fails to draw must not cost the report.
    hdr = run_header_lines(lens, cfg, glass_label);      % materials / indices, sphere / straight wall, design
    svg_path = '';  if cfg.export.svg_geometry, svg_path = fullfile(out.drawings, 'lens_geometry.svg'); end
    fig_geometry(lens, stack, cfg, svg_path, hdr, fullfile(out.drawings, 'lens_geometry.png'));
    if ~isempty(trace)
        summ = sprintf('%d rays to %.2f deg: %d collected, %d lost', trace.n_rays, trace.max_angle, sum(trace.collected), trace.n_lost);
        if isfield(AN, 'collimation'), summ = sprintf('%s   |   collimation max %.2f deg, rms %.2f deg', summ, AN.collimation.max_abs_deg, AN.collimation.rms_deg); end
        if isfield(AN, 'collection'),  summ = sprintf('%s   |   collection %.4f (%s)', summ, AN.collection.phi_traced, cfg.emitter.type); end
        summ = sprintf('%s   |   checks: %s', summ, CK.verdict);
        try_picture(@() fig_raytrace(lens, trace, hdr, summ, out.drawings, cfg.figures.rfq.png_dpi), 'ray-trace picture');
    end
    try_picture(@() make_rfq_drawings(lens, M, cfg, out, dmeta, 'pictures'), '3-D preview / overview');
    if cfg.figures.paper.enable
        K = [];  if isfield(AN, 'collection'), K = AN.collection; end
        try_picture(@() make_paper_figures(lens, stack, K, cfg, out.figures), 'paper panels');
    end

    %% ---- 9. vendor geometry and dimensioned element drawings (withheld on FAIL) ---
    if strcmp(CK.verdict, 'PASS') || cfg.run.export_on_fail
        export_all(lens, M, cfg, out, dmeta, cfg_info);
        make_rfq_drawings(lens, M, cfg, out, dmeta, 'vendor');
        if cfg.figures.asphere_check && ~isempty(lens.asphere)
            fig = asphere_check_figure(lens.asphere, lens.n1, 21, lens.asphere.x_vertex1 + 20 / lens.mm_per_du, 120 / lens.mm_per_du);
            save_fig(fig, 'asphere_check', out.drawings, {'png'}, cfg.figures.rfq.png_dpi, false);
        end
    else
        fprintf(2, 'Checks FAILED: vendor geometry and element drawings withheld (run.export_on_fail = false); the result pictures are in drawings/.\n');
    end
    stats.ok = true;
catch err_obj
    stats.err = err_obj.message;
    fprintf(2, 'ERROR: %s\n', err_obj.message);
end

%% ---- 10. report (always written) ----------------------------------------------
stats.runtime_s = toc(tStart);
verdict = write_report(cfg, cfg_info, out, stats, CK, AN);
fprintf('--- %s: total runtime %.2f s ---\n', verdict, stats.runtime_s);
if ~cfg.run.show_figures, close all; end
R = struct('verdict', verdict, 'checks', CK, 'analyses', AN, 'package', out.pkg, 'runtime_s', stats.runtime_s, 'budget', []);
if ~isempty(stats.lens) && isfield(stats.lens, 'budget'), R.budget = stats.lens.budget; end
if ~stats.ok, R.error = err_obj.message; if isempty(folder_opts), rethrow(err_obj); end, end
end

%% ============================================================
%  PARAMETER SWEEP (replaces TuningParameterSweep.m and the Code3 variations)
%% ============================================================
function run_sweep(cfg, cfg_info, projRoot, config_path)
S = cfg.sweep;
vals = S.values;  if isnumeric(vals), vals = num2cell(vals(:).'); end
base_cfg = cfg;  base_cfg.sweep.enable = false;
if ~isempty(cfg.design.material.name) && strcmp(S.parameter, 'design.n_lens')
    error('LensConstructionGradual:sweep', 'design.material.name is set, so design.n_lens is computed from the catalog: sweep design.material.wavelength_nm instead, or set material.name to null.');
end
% every value must be a valid config BEFORE anything is created (a bad third value must not
% abort the sweep after two packages were written)
for i = 1:numel(vals)
    c = set_by_path(base_cfg, S.parameter, vals{i});
    validate_config(c);
    resolve_material(c, projRoot);
end
% one folder for the whole sweep, named after the swept key
P = package_paths(resolve_material(base_cfg, projRoot), projRoot);   % folder name needs the resolved n_lens
short = regexprep(S.parameter, '^.*\.', '');
sweep_dir = fullfile(P.design_dir, sprintf('%s_%s_sweep_%s', P.revtag, P.date, short));
k = 2; base_dir = sweep_dir;
while exist(sweep_dir, 'dir'), sweep_dir = sprintf('%s_%d', base_dir, k); k = k + 1; end
if ~exist(P.design_dir, 'dir'), mkdir(P.design_dir); end
mkdir(sweep_dir);
fprintf('=== SWEEP %s over %d values -> %s ===\n', S.parameter, numel(vals), sweep_dir);
rows = {};
for i = 1:numel(vals)
    v = vals{i};
    c = set_by_path(base_cfg, S.parameter, v);
    c.run.show_figures = false;
    validate_config(c);
    name = sprintf('%s=%s', short, val2str(v));
    fprintf('\n##### sweep %d/%d: %s #####\n', i, numel(vals), name);
    R = run_one(c, cfg_info, projRoot, config_path, struct('parent', sweep_dir, 'name', name));
    rows{end+1} = summarize(R, v); %#ok<AGROW>
end
fid = fopen(fullfile(sweep_dir, 'sweep_summary.csv'), 'w');
fprintf(fid, 'value,verdict,fails,warns,collimation_max_deg,collimation_rms_deg,rays_lost,phi_traced,transmission,min_edge_mm,min_center_mm,min_gap_mm,runtime_s,package,budget_closed,budget_residual_deg,max_slope_deg,error\n');
for i = 1:numel(rows), fprintf(fid, '%s\n', rows{i}); end
fclose(fid);
fprintf('Sweep summary -> %s\n', fullfile(sweep_dir, 'sweep_summary.csv'));
end

function s = summarize(R, v)
    cmax = NaN; crms = NaN; lost = NaN; phi = NaN; tr = NaN; me = NaN; mc = NaN; mg = NaN; nf = NaN; nw = NaN;
    bc = 'n/a'; bres = NaN; ms = NaN;
    if ~isempty(R.checks)
        nf = R.checks.n_fail; nw = R.checks.n_warn;
        G = R.checks.geometry;
        if ~isempty(G)
            me = min([G.edge_thickness]); mc = min([G.center_thickness]); mg = min([G.gap_to_next]);
            ms = max([[G.max_slope_inner], [G.max_slope_outer]]);
        end
    end
    if isfield(R, 'budget') && ~isempty(R.budget) && isstruct(R.budget)
        if R.budget.closed, bc = 'yes'; else, bc = 'no'; end
        bres = R.budget.max_residual_deg;
    end
    if isfield(R.analyses, 'collimation') && ~isempty(R.analyses.collimation)
        cmax = R.analyses.collimation.max_abs_deg; crms = R.analyses.collimation.rms_deg;
        lost = R.analyses.collimation.n_total - R.analyses.collimation.n_collected;
    end
    if isfield(R.analyses, 'collection') && ~isempty(R.analyses.collection), phi = R.analyses.collection.phi_traced; end
    if isfield(R.analyses, 'fresnel') && ~isempty(R.analyses.fresnel), tr = R.analyses.fresnel.mean_transmission; end
    errtxt = '';
    if isfield(R, 'error') && ~isempty(R.error)          % the run stopped (e.g. a design ray missed a prescribed sphere)
        if isnan(nf), nf = 0; nw = 0; end
        nf = nf + 1;                                      % as write_report counts it
        errtxt = regexprep(R.error, '[,\r\n]+', ';');
    end
    s = sprintf('%s,%s,%d,%d,%.5f,%.5f,%d,%.5f,%.5f,%.4f,%.4f,%.4f,%.1f,%s,%s,%.5f,%.2f,%s', val2str(v), R.verdict, nf, nw, cmax, crms, lost, phi, tr, me, mc, mg, R.runtime_s, R.package, bc, bres, ms, errtxt);
end

%% ============================================================
%  SMALL HELPERS
%% ============================================================
function unwired = unconsumed_keys(cfg)
    % config keys that are accepted but have no effect in this run
    unwired = {};
    uses_wl = ~isempty(cfg.design.material.name);
    if ~uses_wl && isfield(cfg.design, 'element_materials') && ~isempty(cfg.design.element_materials)
        it = normalise_objlist(cfg.design.element_materials, {'element', 'name', 'n'});   % a named element material is evaluated there too
        uses_wl = any(arrayfun(@(s) ~isempty(s.name), it));
    end
    if ~uses_wl
        unwired{end+1} = 'design.material.wavelength_nm (used only when design.material.name is set)';
    end
end

function cfg = resolve_paths(cfg, projRoot)
    if isfield(cfg.design, 'from_mat') && ~isempty(cfg.design.from_mat) && ~is_absolute_path(cfg.design.from_mat)
        cfg.design.from_mat = fullfile(projRoot, cfg.design.from_mat);
    end
end

function len = lens_length(lens)
    xs = cell2mat(cellfun(@(c) c(:,1), lens.final_lens(~cellfun(@isempty, lens.final_lens)), 'UniformOutput', false));
    len = max(xs) - min(xs);
end

function s = val2str(v)
    if ischar(v), s = v;
    elseif islogical(v), if v, s = 'true'; else, s = 'false'; end
    elseif isnumeric(v) && isscalar(v), s = sprintf('%.6g', v);
    else, s = strrep(mat2str(v), ' ', '_');
    end
    s = regexprep(s, '[^A-Za-z0-9_.+-]', '_');
end

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end

function try_picture(fn, what)
    % a result picture is a convenience: if it cannot be drawn, say so and keep the run
    try
        fn();
    catch err
        warning('LensConstructionGradual:picture', 'The %s could not be drawn: %s', what, err.message);
    end
end

function s = mixed_glass_label(emat, default_label)
    % drawing / spec-sheet glass line when design.element_materials changes some elements:
    % 'E1 PMMA (n = 1.4886 at 637 nm) | E2-E4 SCHOTT N-LASF9 (n = 1.8445 at 637 nm)'
    s = default_label;
    if isempty(emat) || ~isstruct(emat), return; end
    listed = find(~strcmp({emat.source}, 'default'));
    if isempty(listed), return; end
    parts = arrayfun(@(e) sprintf('E%d %s', e, emat(e).label), listed, 'UniformOutput', false);
    rest = setdiff(1:numel(emat), listed);
    if ~isempty(rest)
        if numel(rest) == 1
            tag = sprintf('E%d', rest);
        elseif all(diff(rest) == 1)
            tag = sprintf('E%d-E%d', rest(1), rest(end));
        else
            tag = strjoin(arrayfun(@(e) sprintf('E%d', e), rest, 'UniformOutput', false), ',');
        end
        parts{end+1} = sprintf('%s %s', tag, emat(rest(1)).label);
    end
    s = strjoin(parts, ' | ');
end

function tf = is_absolute_path(p)
    p = strrep(p, '\', '/');
    tf = ~isempty(regexp(p, '^([A-Za-z]:/|//|/)', 'once'));
end

function h = git_hash(projRoot)
    h = 'n/a';
    try
        [st, txt] = system(sprintf('git -C "%s" rev-parse --short HEAD 2>&1', projRoot));
        if st == 0
            h = strtrim(txt);
            [st2, dirty] = system(sprintf('git -C "%s" status --porcelain 2>&1', projRoot));
            if st2 == 0 && ~isempty(strtrim(dirty)), h = [h ' (dirty)']; end
        end
    catch
    end
end
