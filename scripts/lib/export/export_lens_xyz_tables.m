function export_lens_xyz_tables(final_lens, layers_count, head_offset_mm, y_spacing_mm, out_dir, mm_per_du, tag, half_only)
    % Exports each layer surface as a 3-column CSV describing the 3D surface
    % obtained by revolving the 2D profile around the optical (figure-x) axis.
    % All output is in MILLIMETRES (geometry scaled by mm_per_du), so the tables
    % match the drawing and the stated physical size.
    %
    % Coordinate mapping (machining frame):
    %   table x = signed figure-y (radial position along a sampling line)
    %   table y = height of the sampling line (integer multiples of y_spacing_mm, mm)
    %   table z = figure-x, shifted so that min(z) == head_offset_mm (mm, always > 0)
    %
    % Each sub-table (constant y) traces the surface cut by the plane y=const:
    % from one tip through x=0 to the other tip, following the profile arc,
    % so the y=0 rows reproduce the 2D cross-section exactly.
    if nargin < 6 || isempty(mm_per_du), mm_per_du = 1;      end
    if nargin < 7 || isempty(tag),       tag = '';           end
    if nargin < 8 || isempty(half_only), half_only = false;  end
    if ~isempty(tag), tag = ['_' tag]; end
    half_marker = ''; if half_only, half_marker = '_tophalf'; end
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    for j = 1:layers_count
        if j > numel(final_lens) || isempty(final_lens{j}), continue; end

        prof = final_lens{j} * mm_per_du;  % scale design units -> mm; on axis -> tip
        rT = flipud(abs(prof(:,2)));       % radius from optical axis, arc-ordered tip -> axis
        zT = flipud(prof(:,1));            % figure-x, same order

        z_baseline = min(zT);
        z_shift    = head_offset_mm - z_baseline;   % z_out = fig_x + z_shift

        r_max   = max(rT);
        y_max   = floor(r_max / y_spacing_mm) * y_spacing_mm;
        if half_only
            y_lines = y_max : -y_spacing_mm : 0;        % TOP HALF only (y >= 0)
        else
            y_lines = y_max : -y_spacing_mm : -y_max;   % full surface
        end

        rows = zeros(0, 3);
        for y = y_lines
            ay = abs(y);
            seg = zeros(0, 2);             % [table_x, fig_x], tip -> axis, negative-x side
            Np  = numel(rT);
            for k = 1:Np
                if rT(k) >= ay
                    seg(end+1,:) = [-sqrt(max(rT(k)^2 - ay^2, 0)), zT(k)]; %#ok<AGROW>
                    if k < Np && rT(k+1) < ay      % arc leaves the plane: crossing at x = 0
                        t = (ay - rT(k)) / (rT(k+1) - rT(k));
                        seg(end+1,:) = [0, zT(k) + t*(zT(k+1) - zT(k))]; %#ok<AGROW>
                    end
                elseif k < Np && rT(k+1) >= ay     % arc enters the plane: crossing at x = 0
                    t = (ay - rT(k)) / (rT(k+1) - rT(k));
                    seg(end+1,:) = [0, zT(k) + t*(zT(k+1) - zT(k))]; %#ok<AGROW>
                end
            end
            if isempty(seg), continue; end

            % mirror to the positive-x side (drop duplicated x = 0 point)
            pos = flipud(seg);
            pos(:,1) = -pos(:,1);
            if abs(seg(end,1)) < 1e-12
                pos(1,:) = [];
            end
            line_pts = [seg; pos];
            rows = [rows; line_pts(:,1), repmat(y, size(line_pts,1), 1), ...
                    line_pts(:,2) + z_shift]; %#ok<AGROW>
        end

        elem = ceil(j/2);
        if mod(j,2) == 1, side = 'inner'; else, side = 'outer'; end
        fname = fullfile(out_dir, sprintf('lens_xyz_element%d_%s_layer%02d%s%s.csv', elem, side, j, half_marker, tag));

        fid = fopen(fname, 'w');
        if fid == -1
            warning('export_lens_xyz_tables:FileOpenError', 'Could not open "%s" for writing.', fname);
            continue;
        end
        % Clean, vendor-friendly table: a single 'x,y,z' header then data only.
        % (No '#' metadata block — some point-cloud importers choke on it.)
        fprintf(fid, 'x,y,z\n');
        fprintf(fid, '%.6f,%g,%.6f\n', rows.');
        fclose(fid);

        fprintf('XYZ export: %s (%d points, %d lines, z shift %.3f mm)\n', ...
                fname, size(rows,1), numel(y_lines), z_shift);
    end
end
