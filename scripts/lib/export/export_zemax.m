function info = export_zemax(final_lens, L, n1, n2, filename, Ngrid, nsurf, surf_glass, surfaces, mm_per_du)
%EXPORT_ZEMAX  Grid Sag .DAT per surface + prescription CSV + scaffold .zmx (NA2_v2 na2_export_zemax).
%   final_lens: cell of [x r] polylines in mm. Ngrid: grid points per side (odd).
%   info.single_valued(j) is false for re-entrant surfaces, which are exported as
%   their outer branch only - Grid Sag cannot represent them.
% Export the lens to Zemax as GRID SAG surfaces (Option B result: the freeform
% crescents don't fit aspheres, so every surface is exported as its EXACT sampled
% sag). Includes the air/glass gaps as a sequential system.
% Writes, into the .zmx's folder:
%   <name>_surfN.DAT           - a Zemax Grid Sag data file per surface (import these)
%   <name>_prescription.csv    - surface order: thickness, material, semi-dia, sag file
%   <name>.zmx                 - a scaffold sequential file (GRIDSAG surfaces; import the .DATs)
%
% Optional (per-element materials and prescribed spheres; any of them may be [] or omitted):
%   nsurf      L x 2 [n_in n_out] per surface (lens.n_surface): index after surface j =
%              nsurf(j,2). Empty -> alternate n2 / n1 as before.
%   surf_glass 1 x L cellstr, the glass name after each odd surface (even entries are
%              ignored, air follows every outer surface). Empty name -> the old guess from
%              the index (material_name), so lenses without a catalog name export as before.
%   surfaces   1 x L struct with .kind (M.surfaces). A 'sphere' layer is a true sphere
%              (design.spherical_surfaces): no .DAT is written, the .zmx surface is
%              TYPE STANDARD with CURV 1/R (R signed the Zemax way: negative when the
%              centre lies on the emitter side of the vertex) and CONI 0.
%   mm_per_du  scale of the polylines (mm per design unit; 1 when they are in du) so the
%              sphere radius surfaces(j).zemax_R_du is written in the same units.
    if nargin < 6  || isempty(Ngrid),      Ngrid = 201;      end    % grid points per side (odd -> centre sample)
    if nargin < 7,                          nsurf = [];       end
    if nargin < 8,                          surf_glass = {};  end
    if nargin < 9,                          surfaces = [];    end
    if nargin < 10 || isempty(mm_per_du),  mm_per_du = 1;    end
    [p,n,~] = fileparts(filename);
    if ~isempty(p) && ~exist(p,'dir'), mkdir(p); end
    zmxfile = fullfile(p,[n '.zmx']);  csvfile = fullfile(p,[n '_prescription.csv']);

    % which layers are prescribed spheres (everything else is sampled as Grid Sag)
    is_sphere = false(L,1);  curv = zeros(L,1);  R_signed = nan(L,1);
    if isstruct(surfaces)
        for j = 1:min(L, numel(surfaces))
            s = surfaces(j);
            if isfield(s, 'kind') && strcmp(s.kind, 'sphere')
                is_sphere(j) = true;
                R_signed(j)  = s.zemax_R_du * mm_per_du;
                curv(j)      = 1 / R_signed(j);
            end
        end
    end

    vertex=nan(L,1); semidia=nan(L,1); maxsag=nan(L,1); mono=false(L,1); datname=strings(L,1);
    for j = 1:L
        pts = final_lens{j};  pts = pts(pts(:,2) >= 0, :);
        if is_sphere(j)
            % exact sphere: the vertex is known analytically (the polyline is the dense arc
            % from the vertex, but a design-ray-sampled one need not start on the axis)
            s = surfaces(j);
            if isfield(s, 'vertex_x_du') && ~isempty(s.vertex_x_du), x0 = s.vertex_x_du * mm_per_du;
            else, [~, iv] = min(pts(:,2));  x0 = pts(iv,1); end
            Rmax = max(pts(:,2));
            mono(j)   = true;                              % a STANDARD surface needs no sag table
            vertex(j) = x0;  semidia(j) = Rmax;  maxsag(j) = max(abs(pts(:,1) - x0));
            datname(j) = sprintf('SPHERE R=%.4f (conic 0)', R_signed(j));
            continue;
        end
        [rq, ia] = unique(pts(:,2));  xq = pts(ia,1);      % unique radii (single-valued sag needs this)
        x0 = xq(1);                                        % vertex at min r
        sag = xq - x0;
        Rmax = max(rq);
        mono(j)   = (numel(rq) == size(pts,1)) && all(diff(rq) > 0);
        vertex(j) = x0;  semidia(j) = Rmax;  maxsag(j) = max(abs(sag));
        datname(j) = sprintf('%s_surf%d.DAT', n, j);
        write_gridsag_dat(fullfile(p, datname(j)), rq, sag, Rmax, Ngrid);
    end

    % thicknesses (gaps) and material after each surface
    thick=zeros(L,1); idx_after=zeros(L,1); matname=strings(L,1);
    for j = 1:L
        if j < L, thick(j) = vertex(j+1) - vertex(j); else, thick(j) = 0; end
        if ~isempty(nsurf)
            idx_after(j) = nsurf(j,2);                      % per-surface indices (element materials)
        elseif mod(j,2)==1
            idx_after(j) = n2;
        else
            idx_after(j) = n1;
        end
        if mod(j,2)==1
            nm = '';
            if iscell(surf_glass) && j <= numel(surf_glass) && ischar(surf_glass{j}), nm = surf_glass{j}; end
            if isempty(nm), matname(j) = material_name(idx_after(j)); else, matname(j) = string(nm); end
        else
            matname(j) = "AIR";
        end
    end
    obj_thick = vertex(1);

    surface = (1:L)';
    T = table(surface, thick, idx_after, matname, semidia, maxsag, mono, datname, ...
        'VariableNames', {'surface','thickness_mm','index_after','material', ...
                          'semi_dia_mm','max_sag_mm','single_valued','gridsag_file'});
    writetable(T, csvfile);
    datfiles = cellstr(datname(:).');  datfiles(is_sphere) = {''};    % spheres have no data file
    info = struct('single_valued', mono(:).', 'semi_dia_mm', semidia(:).', 'max_sag_mm', maxsag(:).', ...
                  'files', {datfiles}, 'is_sphere', is_sphere(:).', 'zmx', zmxfile, 'csv', csvfile);

    write_zmx(zmxfile, thick, matname, semidia, datname, obj_thick, Ngrid, is_sphere, curv, R_signed);

    fprintf('Zemax GRID SAG export (Option B) -> %s\n', csvfile);
    fprintf('  surf | thick(mm) | material | semi-dia | max sag | single-valued | data file\n');
    for j = 1:L
        fprintf('   %2d  | %8.3f | %-8s | %7.2f | %6.2f | %5s | %s\n', ...
            j, thick(j), matname(j), semidia(j), maxsag(j), string(mono(j)), datname(j));
    end
    if any(~mono)
        fprintf('  NOTE: surfaces [%s] are NOT single-valued sag(r) (they curve back); Grid Sag uses\n', ...
            num2str(find(~mono).'));
        fprintf('        the outer branch only - those elements may need a true freeform surface in Zemax.\n');
    end
    fprintf('Wrote scaffold Zemax file -> %s\n', zmxfile);
    fprintf('  In Zemax: for each surface set type = Grid Sag and Import its _surfN.DAT (verify on your end).\n');
    if any(is_sphere)
        fprintf('  Surface(s) [%s] are prescribed spheres: already STANDARD surfaces in the .zmx, nothing to import.\n', ...
            num2str(find(is_sphere).'));
    end
end

% ------------------------------------------------------------------------------
function write_gridsag_dat(datfile, prof_r, prof_sag, Rmax, N)
% Zemax Grid Sag .DAT: header "nx ny delx dely unitflag xdec ydec", then N*N rows
% "z dz/dx dz/dy d2z/dxdy nodata", ordered x-fastest then y (both -Rmax..+Rmax).
%
% The surface is rotationally symmetric, sag = f(r) with r = hypot(x,y), so the
% Cartesian slopes Zemax needs for the surface NORMALS (and therefore Snell's law)
% come from the radial derivatives f'(r), f''(r):
%     dz/dx    = f'(r) * x/r
%     dz/dy    = f'(r) * y/r
%     d2z/dxdy = x*y * (f''(r)*r - f'(r)) / r^3
% Supplying these (instead of zeros) gives Zemax the exact normals and removes the
% spurious TIR that slope-less grid sag produces on steep surfaces. The sag column
% is unchanged, so the geometry is identical - this only adds accuracy.
    del = 2*Rmax / (N-1);
    xs  = linspace(-Rmax, Rmax, N);
    [X, Y] = meshgrid(xs, xs);               % X(iy,ix)=xs(ix), Y(iy,ix)=xs(iy)
    R = hypot(X, Y);

    % sag and its radial derivatives from the SAME pchip profile (central diffs)
    h   =  del/4;                             % slope step, smaller than grid spacing
    f   =  interp1(prof_r, prof_sag, R,             'pchip', 'extrap');
    fRp =  interp1(prof_r, prof_sag, R + h,         'pchip', 'extrap');
    fRm =  interp1(prof_r, prof_sag, max(R - h, 0), 'pchip', 'extrap');
    fp  = (fRp - fRm) ./ (2*h);               % f'(r)
    fpp = (fRp - 2*f + fRm) ./ (h^2);         % f''(r)

    Rs = R; Rs(Rs == 0) = 1;                  % guard divide-by-zero at the centre
    dzdx = fp .* X ./ Rs;
    dzdy = fp .* Y ./ Rs;
    d2   = X .* Y .* (fpp .* R - fp) ./ (Rs.^3);
    onAxis = (R == 0);                        % centre: all slopes vanish by symmetry
    dzdx(onAxis) = 0;  dzdy(onAxis) = 0;  d2(onAxis) = 0;

    fid = fopen(datfile, 'wt');  c = onCleanup(@() fclose(fid));   % 'wt' = CRLF on Windows
    fprintf(fid, '%d %d %.10g %.10g 0 0 0\n', N, N, del, del);   % unitflag 0 = mm
    for iy = 1:N
        for ix = 1:N
            if R(iy,ix) <= Rmax
                fprintf(fid, '%.9g %.9g %.9g %.9g 0\n', ...
                        f(iy,ix), dzdx(iy,ix), dzdy(iy,ix), d2(iy,ix));
            else
                fprintf(fid, '0 0 0 0 1\n');                     % nodata = 1 outside aperture
            end
        end
    end
end

function nm = material_name(n)
% Legacy guess of a glass name from its index, used only when no name is known
% (no surf_glass given, or an element whose index is used as written).
    if     abs(n-1.85)   < 0.02, nm = "N-LASF9";
    elseif abs(n-2.003)  < 0.03, nm = "S-LAH79";
    elseif abs(n-1.5168) < 0.01, nm = "N-BK7";
    elseif abs(n-1.5)    < 0.02, nm = "N-BK7";
    else,  nm = "MODEL"; end
end

function write_zmx(zmxfile, thick, matname, semidia, datname, obj_thick, N, is_sphere, curv, R_signed)
    L = numel(thick);
    if nargin < 8 || isempty(is_sphere), is_sphere = false(L,1); end
    fid = fopen(zmxfile, 'w');  c = onCleanup(@() fclose(fid));
    fprintf(fid, 'VERS 190513 0 0\nMODE SEQ\nNAME NA2 omni lens (Grid Sag auto-export)\nUNIT MM MM MM MM\n');
    fprintf(fid, 'SURF 0\nTYPE STANDARD\nCURV 0.0\nDISZ %.8g\n', obj_thick);
    for j = 1:L
        if is_sphere(j)
            % a prescribed sphere is a plain STANDARD surface: curvature 1/R, no conic
            fprintf(fid, 'SURF %d\nTYPE STANDARD\nCURV %.10g\nCONI 0\nDISZ %.8g\n', j, curv(j), thick(j));
        else
            fprintf(fid, 'SURF %d\nTYPE GRIDSAG\nCURV 0.0\nDISZ %.8g\n', j, thick(j));
        end
        if ~strcmp(matname(j),"AIR"), fprintf(fid, 'GLAS %s 0 0\n', matname(j)); end
        fprintf(fid, 'DIAM %.8g\n', semidia(j));
        if is_sphere(j)
            fprintf(fid, 'COMM prescribed sphere R = %.4f mm, conic 0 (design.spherical_surfaces)\n', R_signed(j));
        else
            fprintf(fid, 'COMM import Grid Sag data file: %s (grid %dx%d)\n', datname(j), N, N);
        end
    end
    fprintf(fid, 'SURF %d\nTYPE STANDARD\nCURV 0.0\nDISZ 0.0\n', L+1);
end
