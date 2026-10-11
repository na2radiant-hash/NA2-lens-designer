function S = config_schema()
%CONFIG_SCHEMA  Allowed keys and leaf types of the NA2 run configuration.
%
%   GENERATED from inputs/config_example.json by gen_schema.py - do not edit
%   by hand; regenerate when a key is added to the config.
%
%   Leaf type strings understood by validate_config:
%     'bool'     logical scalar
%     'num'      numeric scalar
%     'int'      numeric scalar with an integer value
%     'num?'     numeric scalar or [] (JSON null = "derive automatically")
%     'str'      character vector
%     'str?'     character vector or [] (JSON null)
%     'enum:a|b' character vector from the listed set
%     'numvec'   numeric vector (may be empty)
%     'strlist'  char or cell array of chars
%     'objlist:f1=t1,f2=t2,...'
%                [] or a list of objects (struct array / cell of structs) whose
%                items have exactly the fields f1, f2, ... of leaf types t1, t2, ...
%                (see normalise_objlist for the canonical 1 x N struct shape)
%
%   187 keys.
S = struct();
S.run.vendor = 'str';
S.run.material = 'str?';
S.run.rev = 'str';
S.run.elements = 'numvec';
S.run.notes = 'str';
S.run.output_root = 'str';
S.run.on_exists = 'enum:error|suffix';
S.run.export_on_fail = 'bool';
S.run.show_figures = 'bool';
S.run.close_figures_at_start = 'bool';
S.run.log_console = 'bool';
S.design.from_mat = 'str?';
S.design.n_outside = 'num';
S.design.n_lens = 'num?';
S.design.material.name = 'str?';
S.design.material.wavelength_nm = 'num?';
S.design.layers_count = 'int';
S.design.layers_design_budget = 'num?';
S.design.rays_count = 'int';
S.design.NA_hole = 'num';
S.design.NA_design_margin = 'num';
S.design.fan_max_deg_override = 'num?';
S.design.fan_epsilon_deg = 'num';
S.design.WD_mm = 'num';
S.design.collimation_fraction = 'num';
S.design.collimation_target_deg = 'num';
S.design.weights.J_front = 'num';
S.design.weights.k_shape = 'num';
S.design.weights.base_w = 'num';
S.design.weights.hardness_exp = 'num';
S.design.weights.layer_exp = 'num';
S.design.solver.method = 'enum:symbolic|analytic';
S.design.solver.jump_size_du = 'num';
S.design.solver.max_attempts = 'int';
S.design.truncation.enable = 'bool';
S.design.truncation.edge_min_thickness_mm = 'numvec';
S.design.glass_cell.enable = 'bool';
S.design.glass_cell.before_elements = 'numvec';
S.design.glass_cell.n_glass = 'num';
S.design.glass_cell.width_mm = 'num';
S.design.glass_cell.height_factor = 'num';
S.design.commercial_asphere.enable = 'bool';
S.design.commercial_asphere.model = 'enum:edmund_22722_150mm|edmund_15003_100mm|custom';
S.design.commercial_asphere.x_offset_mm = 'num';
S.design.commercial_asphere.custom.R_mm = 'num';
S.design.commercial_asphere.custom.k = 'num';
S.design.commercial_asphere.custom.D = 'num';
S.design.commercial_asphere.custom.E = 'num';
S.design.commercial_asphere.custom.F = 'num';
S.design.commercial_asphere.custom.G = 'num';
S.design.commercial_asphere.custom.H = 'num';
S.design.commercial_asphere.custom.J = 'num';
S.design.commercial_asphere.custom.L = 'num';
S.design.commercial_asphere.custom.M = 'num';
S.design.commercial_asphere.custom.asphere_on_s2 = 'bool';
S.design.commercial_asphere.custom.n = 'num';
S.design.commercial_asphere.custom.CT_mm = 'num';
S.design.commercial_asphere.custom.half_aperture_mm = 'num';
S.design.commercial_asphere.correction.enable = 'bool';
S.design.commercial_asphere.correction.tune_amplitude = 'num';
S.design.commercial_asphere.correction.tune_peak_ray_frac = 'num';
S.design.commercial_asphere.correction.tune_peak_ray = 'num?';
S.design.commercial_asphere.correction.tune_power = 'num';
S.design.commercial_asphere.correction.edge_baseline = 'num';
S.design.commercial_asphere.correction.x_offset_after_mm = 'num';
S.design.element_materials = 'objlist:element=int,name=str?,n=num?';
S.design.spherical_surfaces = 'objlist:surface=int,center_z_du=num?,radius_du=num';
S.design.slope_limits = 'objlist:surface=int,max_slope_deg=num,pull=enum:back|front';
S.emitter.type = 'enum:isotropic|dipole';
S.emitter.dipole_axis = 'enum:x|y';
S.process.cut.enable = 'bool';
S.process.cut.x0_mm = 'numvec';
S.process.cut.angle_deg = 'num';
S.process.edge_fillet_mm = 'num';
S.process.tip_truncate_mm = 'num';
S.process.min_wall_mm = 'num';
S.process.draft_deg = 'num';
S.trace.enable = 'bool';
S.trace.n_rays = 'int';
S.trace.sampling = 'enum:deterministic|stochastic';
S.trace.seed = 'num';
S.trace.min_angle_deg = 'num';
S.trace.max_angle_deg = 'num?';
S.trace.angle_epsilon_deg = 'num';
S.trace.auto_max_angle = 'bool';
S.trace.auto_max_iters = 'int';
S.trace.auto_collimation_tol_deg = 'num';
S.trace.segment_overshoot = 'num';
S.trace.smooth_normals = 'bool';
S.trace.extend_factor = 'num';
S.analysis.collimation.enable = 'bool';
S.analysis.fresnel.enable = 'bool';
S.analysis.fresnel.polarization = 'enum:unpolarized|s|p';
S.analysis.intensity_profile.enable = 'bool';
S.analysis.intensity_profile.plane_x_mm = 'num?';
S.analysis.intensity_profile.n_bins = 'int';
S.analysis.collection_efficiency.enable = 'bool';
S.analysis.collection_efficiency.targets = 'numvec';
S.analysis.collection_efficiency.theta_lens_deg = 'num?';
S.analysis.save_csv = 'bool';
S.export.sag_table = 'bool';
S.export.sag_step_mm = 'num';
S.export.xyz_lines = 'bool';
S.export.xyz_lines_half = 'bool';
S.export.xyz_line_spacing_mm = 'num';
S.export.head_offset_mm = 'num';
S.export.xyz_grid = 'bool';
S.export.grid_spacing_mm = 'num';
S.export.grid_interp = 'enum:linear|pchip|makima';
S.export.grid_center_at_zero = 'bool';
S.export.profile_2d = 'enum:xt|none';
S.export.xt_thickness_mm = 'num';
S.export.dxf_revolve = 'bool';
S.export.dxf_precision = 'int';
S.export.step = 'bool';
S.export.step_pieces = 'bool';
S.export.step_stl = 'bool';
S.export.step_python = 'str';
S.export.zemax = 'bool';
S.export.zemax_n_grid = 'int';
S.export.svg_geometry = 'bool';
S.export.units = 'enum:mm|du';
S.figures.rfq.cross_section = 'bool';
S.figures.rfq.overview = 'bool';
S.figures.rfq.cut_pieces = 'bool';
S.figures.rfq.surfaces_3d = 'bool';
S.figures.rfq.n_theta = 'int';
S.figures.rfq.surface_float_mm = 'num';
S.figures.rfq.ray_overlay.enable = 'bool';
S.figures.rfq.ray_overlay.n_rays = 'int';
S.figures.rfq.ray_overlay.extend_len_du = 'num';
S.figures.rfq.filled_overlay = 'bool';
S.figures.rfq.watermark = 'str';
S.figures.rfq.png_dpi = 'int';
S.figures.paper.enable = 'bool';
S.figures.paper.panels.fig1a = 'bool';
S.figures.paper.panels.fig1b = 'bool';
S.figures.paper.panels.fig1c = 'bool';
S.figures.paper.panels.fig1d = 'bool';
S.figures.paper.panels.fig1e = 'bool';
S.figures.paper.panels.fig1f = 'bool';
S.figures.paper.panels.fig3a = 'bool';
S.figures.paper.panels.fig3b = 'bool';
S.figures.paper.panels.fig3c = 'bool';
S.figures.paper.n_rays_drawn = 'int';
S.figures.paper.zoom_half_mm = 'num?';
S.figures.paper.zoom_n_elements = 'int';
S.figures.paper.ray_length_mm = 'num';
S.figures.paper.collimation_arrowheads.enable = 'bool';
S.figures.paper.collimation_arrowheads.frac = 'num';
S.figures.paper.scale_bar = 'bool';
S.figures.paper.heatmap.enable = 'bool';
S.figures.paper.heatmap.res = 'int';
S.figures.paper.heatmap.lambda_display_mm = 'num';
S.figures.paper.rays_3d.angles_deg = 'numvec';
S.figures.paper.rays_3d.n_copies = 'int';
S.figures.paper.rays_3d.add_circles = 'bool';
S.figures.paper.rays_3d.arrow_scale = 'num';
S.figures.paper.rays_3d.emitter_radius_du = 'num';
S.figures.paper.collection_plot.x_axis = 'enum:NA|deg';
S.figures.paper.collection_plot.y_scale = 'enum:linear|log|complement|power';
S.figures.paper.collection_plot.y_range = 'numvec';
S.figures.paper.collection_plot.log_base = 'num';
S.figures.paper.collection_plot.power = 'num';
S.figures.paper.collection_plot.mark_points = 'numvec';
S.figures.paper.formats = 'strlist';
S.figures.paper.png_dpi = 'int';
S.figures.paper.fig_size_cm = 'numvec';
S.figures.style = 'enum:b9e1f0|scientificblue|blue|darkyellow|green';
S.figures.asphere_check = 'bool';
S.sweep.enable = 'bool';
S.sweep.parameter = 'str';
S.sweep.values = 'numvec';
S.sweep.rebuild = 'bool';
S.checks.collimation_max_deg = 'num';
S.checks.collimation_rms_deg = 'num';
S.checks.max_lost_rays = 'int';
S.checks.max_solver_fallbacks = 'int';
S.checks.tir_margin_warn_deg = 'num';
S.checks.min_edge_thickness_mm = 'num';
S.checks.min_center_thickness_mm = 'num';
S.checks.min_air_gap_mm = 'num';
S.checks.require_single_cut_crossing = 'bool';
S.checks.max_fillet_fan_loss_pct = 'num';
S.checks.max_re_entrant_slope_deg = 'num';
S.checks.warn_scale_mm_per_du = 'num';
S.checks.bending_budget_tol_deg = 'num';
end
