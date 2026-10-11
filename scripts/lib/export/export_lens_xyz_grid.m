function export_lens_xyz_grid(final_lens, layers_count, spacing_mm, center_at_zero, head_offset_mm, interp_method, out_dir, mm_per_du, tag)
    % Writes each layer as a uniform x-y grid so a surface analyzer does not
    % have to interpolate an uneven/line-structured point cloud (which causes
    % radial "spoke" noise). The surface is a solid of revolution, so height
    % is a pure function of radius r = hypot(x,y); we evaluate z = f(r) at each
    % regular grid node. This is exact in the azimuthal direction -> no noise.
    %
    % Height normalization:
    %   center_at_zero = true  -> the on-axis (0,0) point is placed at Z = 0
    %                             (optical "sag from vertex" convention)
    %   center_at_zero = false -> shifted so min(Z) = head_offset_mm (as the
    %                             line export does)
    if nargin < 6 || isempty(interp_method), interp_method = 'pchip'; end
    if nargin < 8 || isempty(mm_per_du),     mm_per_du = 1;           end
    if nargin < 9 || isempty(tag),           tag = '';               end
    if ~isempty(tag), tag = ['_' tag]; end
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    for j = 1:layers_count
        if j > numel(final_lens) || isempty(final_lens{j}), continue; end

        prof = final_lens{j} * mm_per_du;  % scale design units -> mm
        r = abs(prof(:,2));           % radius from optical axis (mm)
        z = prof(:,1);                % axial coordinate (figure-x, mm)

        % --- reduce to a single-valued profile z(r), sorted by radius ---
        [rs, ord] = sort(r);
        zs = z(ord);
        [ru, ia]  = unique(rs, 'stable');
        zu = zs(ia);
        non_monotonic = any(diff(rs) < -1e-9);
        if non_monotonic
            warning(['export_lens_xyz_grid: layer %d profile is not single-valued ' ...
                     'in r (overhanging crescent); grid uses the sorted envelope and ' ...
                     'may not represent the re-entrant part. This is expected for the ' ...
                     'small inner elements, not for the outer optical surfaces.'], j);
        end
        r_max = max(ru);

        % --- height reference ---
        z_center = interp1(ru, zu, 0, interp_method, 'extrap');   % z at r = 0
        if center_at_zero
            z_shift = -z_center;                     % on-axis point -> 0
        else
            z_shift = head_offset_mm - min(zu);      % min -> machine head offset
        end

        % --- uniform Cartesian net ---
        half = 0 : spacing_mm : r_max;
        axv  = unique([-fliplr(half), half]);        % symmetric, includes 0
        [X, Y] = meshgrid(axv, axv);
        R = hypot(X, Y);
        inside = R <= r_max + 1e-9;

        Zg = interp1(ru, zu, min(R(inside), r_max), interp_method) + z_shift;
        Xo = X(inside);  Yo = Y(inside);

        elem = ceil(j/2);
        if mod(j,2) == 1, side = 'inner'; else, side = 'outer'; end
        fname = fullfile(out_dir, sprintf('lens_xyzgrid_element%d_%s_layer%02d%s.csv', elem, side, j, tag));

        fid = fopen(fname, 'w');
        if fid == -1
            warning('export_lens_xyz_grid:FileOpenError', 'Could not open "%s" for writing.', fname);
            continue;
        end
        % Clean, vendor-friendly table: a single 'x,y,z' header then data only.
        fprintf(fid, 'x,y,z\n');
        fprintf(fid, '%.6f,%.6f,%.6f\n', [Xo(:), Yo(:), Zg(:)].');
        fclose(fid);

        fprintf('XYZ grid export: %s (%d pts, %.4g mm net, r_max=%.2f, z_shift=%.3f)\n', ...
                fname, numel(Xo), spacing_mm, r_max, z_shift);
    end
end
