function files = export_all(lens, M, cfg, out, dmeta, cfg_info)
%EXPORT_ALL  Run every enabled geometry exporter on the manufacturing profile.
%
%   files = export_all(lens, M, cfg, out, dmeta, cfg_info)
%
%   Uses M.final_lens (the profile after tip truncation / fillet; identical to
%   the design when those are off) scaled to mm (export.units = 'mm') or left in
%   design units ('du'). Writers are the original LensConstructionGradual
%   functions plus the NA2_v2 DXF-revolve and Zemax Grid Sag exporters.
%
%   Per-element materials (design.element_materials) and prescribed / clamped
%   surfaces (design.spherical_surfaces, design.slope_limits) reach the writers
%   through lens.material.elements, lens.n_surface and M.surfaces. A lens that
%   lacks those fields (a legacy lens.mat loaded through design.from_mat) is
%   exported exactly as before: one glass name, alternating n1/n2 and Grid Sag
%   for every surface.

    X = cfg.export;
    if strcmpi(X.units, 'du'), scale = 1; else, scale = lens.mm_per_du; end
    run_tag = sprintf('n%.2f_WD%.2f_rays%d', lens.n2, cfg.design.WD_mm, cfg.design.rays_count);   % e.g. n1.85_WD1.00_rays120
    files = {};
    els = cfg.run.elements(:).';
    x0s = cfg.process.cut.x0_mm(:).';
    if numel(x0s) == 1, x0s = repmat(x0s, size(els)); end
    L = lens.L;
    FL = M.final_lens;                                 % design units, processed

    % ---- per-element materials and surface kinds (all empty for a legacy lens) ----
    elmat = [];                                        % lens.material.elements(e) or []
    if isfield(lens, 'material') && isstruct(lens.material) && isfield(lens.material, 'elements')
        elmat = lens.material.elements;
    end
    nsurf = [];                                        % L x 2 [n_in n_out], [] -> export_zemax alternates n1/n2
    if isfield(lens, 'n_surface') && isnumeric(lens.n_surface) && size(lens.n_surface, 1) >= L && size(lens.n_surface, 2) >= 2
        nsurf = lens.n_surface(1:L, 1:2);
    end
    surfaces = [];                                     % M.surfaces (kind per surface), [] -> all 'built'
    if isfield(M, 'surfaces') && isstruct(M.surfaces) && ~isempty(M.surfaces)
        surfaces = M.surfaces;
    elseif isfield(lens, 'surfaces') && isstruct(lens.surfaces) && ~isempty(lens.surfaces)
        surfaces = lens.surfaces;
    end
    % Zemax material per surface: the element's glass after an odd (inner) surface, air after
    % an even (outer) one. An element without a catalog name (index used as written, or the
    % default material of a legacy config) gets '' so export_zemax keeps its old guess from n.
    surf_glass = repmat({''}, 1, L);
    for j = 1:L
        e = ceil(j / 2);
        if mod(j, 2) == 1 && ~isempty(elmat) && e <= numel(elmat) && isfield(elmat, 'name') ...
                && ischar(elmat(e).name) && ~isempty(elmat(e).name)
            surf_glass{j} = elmat(e).name;
        elseif mod(j, 2) == 0
            surf_glass{j} = 'AIR';
        end
    end

    % ---- 2D profile per listed element (XT) ----
    if strcmpi(X.profile_2d, 'xt')
        for k = 1:numel(els)
            el = els(k);
            f = fullfile(out.geometry, sprintf('element%d_profile.xt', el));
            export_lens_to_xt(cellfun(@(c) c * scale, FL(2*el-1:2*el), 'UniformOutput', false), X.xt_thickness_mm, f);
            files{end+1} = f; %#ok<AGROW>
        end
    end

    % ---- XYZ line tables (all surfaces), half tables, grid ----
    if X.xyz_lines
        export_lens_xyz_tables(FL, L, X.head_offset_mm, X.xyz_line_spacing_mm, out.geometry, scale, run_tag);
    end
    if X.xyz_lines_half
        export_lens_xyz_tables(FL, L, X.head_offset_mm, X.xyz_line_spacing_mm, fullfile(out.geometry, 'half_lens'), scale, run_tag, true);
    end
    if X.xyz_grid
        export_lens_xyz_grid(FL, L, X.grid_spacing_mm, X.grid_center_at_zero, X.head_offset_mm, X.grid_interp, out.geometry, scale, run_tag);
    end

    % ---- sag table + README per listed element (same profile, scale and cut as the drawing) ----
    if X.sag_table
        for k = 1:numel(els)
            cut = struct('enable', cfg.process.cut.enable, 'x0', x0s(k), 'angle_deg', cfg.process.cut.angle_deg);
            % the README names the element's own material (falls back to the package glass label)
            dmeta_e = dmeta;
            if ~isempty(elmat) && els(k) <= numel(elmat) && isfield(elmat, 'label') ...
                    && ischar(elmat(els(k)).label) && ~isempty(elmat(els(k)).label)
                dmeta_e.glass = elmat(els(k)).label;
            end
            export_element_sag_table(FL, els(k), scale, out.geometry, cut, dmeta_e, ...
                                     sprintf('lens.mat (built from %s)', cfg_info.name), surfaces);
        end
    end

    % ---- DXF revolve profile (NA2_v2) ----
    if X.dxf_revolve
        f = export_dxf_revolve(cellfun(@(c) c * scale, FL, 'UniformOutput', false), L, fullfile(out.geometry, 'lens_revolve_profile.dxf'), X.dxf_precision);
        files{end+1} = f; %#ok<AGROW>
    end

    % ---- STEP solid of revolution per listed element (Python + cadquery, see export_step) ----
    if X.step
        cut = [];
        if X.step_pieces && cfg.process.cut.enable, cut = x0s; end
        sopts = struct('python', X.step_python, 'cut', cut, 'stl', X.step_stl, 'rev', dmeta.rev);
        f = export_step(M, els, scale, fullfile(out.geometry, 'step'), sopts);
        files = [files, f];
    end

    % ---- Zemax Grid Sag (NA2_v2); prescribed spheres go out as STANDARD surfaces ----
    if X.zemax
        info = export_zemax(cellfun(@(c) c * scale, FL, 'UniformOutput', false), L, lens.n1, lens.n2, ...
                            fullfile(out.geometry, 'zemax', 'lens_gridsag.zmx'), X.zemax_n_grid, ...
                            nsurf, surf_glass, surfaces, scale);
        if any(~info.single_valued)
            fprintf(2, 'NOTE: Zemax Grid Sag exported the OUTER branch only of re-entrant surface(s) [%s].\n', num2str(find(~info.single_valued)));
        end
        files{end+1} = info.zmx; %#ok<AGROW>
    end
end
