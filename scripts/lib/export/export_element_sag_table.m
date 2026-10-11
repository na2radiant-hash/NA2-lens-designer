function export_element_sag_table(final_lens, elem, scale_mm, out_dir, cut, dmeta, src_name, surfaces)
%EXPORT_ELEMENT_SAG_TABLE  Sag CSV (surface, r_mm, sag_mm, slope_deg) + companion README for one element.
%
%   export_element_sag_table(final_lens, elem, scale_mm, out_dir, cut, dmeta, src_name, surfaces)
%
%   final_lens  cell of [x r] polylines in design units (the manufacturing profile)
%   surfaces    optional 1 x L struct with .kind per surface (M.surfaces). A prescribed
%               sphere or a draft-clamped surface of this element gets an extra README line
%               after the S1/S2 data; [] or all 'built' leaves the README exactly as before.
%               The CSV rows always come from the polyline in final_lens (a sphere layer
%               already holds its dense arc there), so the sampling never changes.
    if nargin < 3 || isempty(scale_mm), scale_mm = 1;              end
    if nargin < 5 || isempty(cut),      cut = struct('x0', NaN);   end
    if nargin < 6 || isempty(dmeta),    dmeta = default_dmeta();   end
    if nargin < 7 || isempty(src_name), src_name = '(unknown)';    end
    if nargin < 8 || ~isstruct(surfaces), surfaces = struct([]);   end
    li = 2*elem - 1;  lo = 2*elem;
    if lo > numel(final_lens) || isempty(final_lens{li}) || isempty(final_lens{lo})
        warning('export_element_sag_table: element %d not available.', elem); return;
    end
    x0 = NaN;  if isfield(cut,'x0'), x0 = cut.x0; end

    inn = final_lens{li} * scale_mm;    % [axial, radius] mm, ordered vertex -> tip
    out = final_lens{lo} * scale_mm;

    % --- headline: identical formulas to draw_element_cross_section ---
    r_out   = max(abs(out(:,2)));                 OD    = 2*r_out;
    r_mouth = abs(inn(end,2));                     mouth = 2*r_mouth;
    L = max([inn(:,1); out(:,1)]) - min([inn(:,1); out(:,1)]);
    [~, iv] = min(abs(inn(:,2)));  WD = inn(iv,1);
    Rin = vertex_R(inn);

    s1 = sag_surf_stats(inn, x0);
    s2 = sag_surf_stats(out, x0);

    step_mm = 0.010;                    % arc-length resample step (see header rationale)
    T1 = sag_resample(inn, step_mm, x0);
    T2 = sag_resample(out, step_mm, x0);

    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    revtag = regexprep(dmeta.rev, '[^A-Za-z0-9]', '');
    csvbase = sprintf('element%d_sag_table_%s', elem, revtag);
    fname  = fullfile(out_dir, [csvbase '.csv']);
    rname  = fullfile(out_dir, [csvbase '_README.txt']);
    today  = char(datetime('today', 'Format', 'yyyy-MM-dd'));

    % --- CLEAN CSV: single header row, 4 columns, NO comment block (imports cleanly
    %     into Excel/point-cloud tools). All metadata lives in the companion README. ---
    fid = fopen(fname, 'w');
    if fid == -1
        fprintf(2, '*** SAG TABLE NOT WRITTEN: cannot open %s\n', fname);
        fprintf(2, '*** Most likely it is OPEN IN EXCEL (file lock). Close it and re-run.\n');
        warning('export_element_sag_table: cannot open %s (locked?)', fname);
        return;
    end
    fprintf(fid, 'surface,r_mm,sag_mm,slope_deg\n');
    sag_write_rows(fid, 'S1_inner', T1);
    sag_write_rows(fid, 'S2_outer', T2);
    fclose(fid);

    % --- COMPANION SPEC SHEET (.txt): revision, material, scale, per-surface data,
    %     and how to read the CSV. Kept out of the CSV so the table stays clean. ---
    rid = fopen(rname, 'w');
    if rid ~= -1
        q = @(varargin) fprintf(rid, varargin{:});
        q('ELEMENT %d  SAG / SURFACE-PROFILE TABLE  --  PRELIMINARY, NOT FOR MANUFACTURE\n', elem);
        q('companion spec for: %s.csv\n', csvbase);
        q('==================================================================\n');
        q('design revision   : %s\n', dmeta.rev);
        q('material / index  : %s\n', dmeta.glass);
        q('date generated    : %s\n', today);
        q('source .mat       : %s\n', src_name);
        q('generating script : scripts/construction/LensConstructionGradual.m (same run as the cross-section figure)\n');
        q('units             : millimetres (mm)\n');
        q('scale             : mm_per_du = %.6f  (the .mat is unitless design units; physical size set by WD = %.4f mm)\n', scale_mm, WD);
        q('optical frame     : focus at origin; +x = optical axis; surface = the profile revolved about +x\n');
        q('split / cut plane : axis-normal at x = %+.4f mm  (front piece x >= cut, back piece x <= cut)\n', x0);
        q('\n');
        q('element envelope  : outer diameter %.4f mm | overall length %.4f mm | working distance %.4f mm | cavity vertex R ~ %.4f mm\n', OD, L, WD, Rin);
        q('\n');
        q('S1 inner cavity   : physical diameter %.4f mm | cavity-mouth aperture %.4f mm | vertex at x = %+.4f mm (sag = 0 there)\n', 2*s1.rmax, mouth, s1.xv);
        q('                    re-entrant as monolith: %s | max local slope: monolith %.2f deg, front-piece %.2f deg, back-piece %.2f deg\n', tf_yesno(s1.reent), s1.smono, s1.sfront, s1.sback);
        q('S2 outer dome     : physical diameter %.4f mm | edge aperture %.4f mm | vertex at x = %+.4f mm (sag = 0 there)\n', 2*s2.rmax, 2*abs(out(end,2)), s2.xv);
        q('                    re-entrant as monolith: %s | max local slope: monolith %.2f deg, front-piece %.2f deg, back-piece %.2f deg\n', tf_yesno(s2.reent), s2.smono, s2.sfront, s2.sback);
        % prescribed sphere / draft-clamped cone of this element (design.spherical_surfaces,
        % design.slope_limits): the vendor must know which part of the profile is analytic
        prof = {inn, out};                                 % element-local S1 / S2, mm
        for k = 1:2
            j = li + k - 1;
            if j > numel(surfaces) || ~isfield(surfaces, 'kind') || ~ischar(surfaces(j).kind), continue; end
            S = surfaces(j);
            if strcmp(S.kind, 'sphere')
                q('S%d is a PRESCRIBED SPHERE: R = %.4f mm, center x = %.4f mm (design.spherical_surfaces)\n', ...
                  k, abs(S.radius_du) * scale_mm, S.center_z_du * scale_mm);
            elseif strcmp(S.kind, 'clamped')
                P = prof{k};  k1 = S.first_clamped_ray;    % row of the first clamped design ray (Inf = never)
                if isfinite(k1) && k1 >= 1 && k1 <= size(P, 1)
                    q('S%d draft cone at %g deg (design.slope_limits, pull %s) from r = %.4f mm to the tip\n', ...
                      k, S.max_slope_deg, S.pull, abs(P(k1, 2)));
                else
                    q('S%d draft limit %g deg (design.slope_limits, pull %s): never active, the surface is fully constructed\n', ...
                      k, S.max_slope_deg, S.pull);
                end
            end
        end
        q('clear aperture    : full physical aperture is used optically; no CA mask / mount margin defined yet (mounting/integration TBD)\n');
        q('\n');
        q('HOW TO READ THE CSV\n');
        q('  columns: surface, r_mm, sag_mm, slope_deg\n');
        q('    surface   - S1_inner (cavity) or S2_outer (dome)\n');
        q('    r_mm      - radial height from the optical axis, mm\n');
        q('    sag_mm    - axial sag from that surface''s OWN vertex (0 at vertex; negative = toward the focus, -x). Vertex x listed above.\n');
        q('    slope_deg - local surface-normal angle from the optical axis (0 = faces along axis, 90 = vertical wall, >90 = overhang)\n');
        q('  ROWS ARE ORDERED along each surface from the on-axis vertex to the crescent tip -- KEEP THIS ORDER, do NOT sort the file.\n');
        q('  Both surfaces are RE-ENTRANT (slope exceeds 90 deg), so sag is NOT single-valued in r: a given radius occurs at two\n');
        q('  different sags. Treat (r_mm, sag_mm) as a PARAMETRIC curve in row order; interpolate LINEARLY between consecutive rows of\n');
        q('  the same surface (each row lies exactly on the design profile, so linear interpolation is exact). Do NOT fit sag = f(r).\n');
        q('  Rotate the (r, sag) curve about the optical axis to obtain the surface of revolution.\n');
        q('  sampling: arc-length resample at %.3f mm with every native construction vertex retained; values rounded to 1e-6 mm (1 nm,\n', step_mm);
        q('            far below any figure tolerance). Native profile: S1 %d pts, S2 %d pts.\n', size(inn,1), size(out,1));
        fclose(rid);
    end

    fprintf('Sag table exported: %s\n', fname);
    fprintf('  + spec sheet    : %s\n', rname);
    fprintf('  S1 inner: %d rows, re-entrant=%s, slope mono/front/back = %.1f/%.1f/%.1f deg\n', ...
            size(T1,1), tf_yesno(s1.reent), s1.smono, s1.sfront, s1.sback);
    fprintf('  S2 outer: %d rows, re-entrant=%s, slope mono/front/back = %.1f/%.1f/%.1f deg\n', ...
            size(T2,1), tf_yesno(s2.reent), s2.smono, s2.sfront, s2.sback);
end

function s = sag_surf_stats(P, x0)
    x = P(:,1);  r = abs(P(:,2));
    [s.rmax, ie] = max(r);   s.xeq = x(ie);
    s.reent = (ie > 1) && (ie < numel(r));       % equator interior => r rises then falls
    [~, iv] = min(r);  s.xv = x(iv);
    dx = diff(x);  dr = diff(r);
    sg = atan2d(abs(dx), dr);                     % normal-from-axis per native segment; >90 = overhang
    s.smono  = max(sg);
    midx = (x(1:end-1) + x(2:end)) / 2;
    s.sfront = max([sg(midx >= x0); -inf]);
    s.sback  = max([sg(midx <= x0); -inf]);
end

function T = sag_resample(P, step_mm, x0)
    x = P(:,1);  r = abs(P(:,2));
    keep = [true; hypot(diff(x), diff(r)) > 1e-12];      % drop any zero-length segments
    x = x(keep);  r = r(keep);
    seglen = hypot(diff(x), diff(r));
    s = [0; cumsum(seglen)];
    segang = atan2d(abs(diff(x)), diff(r));              % exact per-segment slope
    grid = (0 : step_mm : s(end))';
    scut = [];
    ix = find((x(1:end-1) - x0) .* (x(2:end) - x0) < 0, 1);   % single x-crossing of the cut
    if ~isempty(ix)
        t = (x0 - x(ix)) / (x(ix+1) - x(ix));
        scut = s(ix) + t * (s(ix+1) - s(ix));
    end
    su = unique([s; grid; scut]);                        % native vertices are retained exactly
    xq = interp1(s, x, su, 'linear');
    rq = interp1(s, r, su, 'linear');
    seg_idx = discretize(su, s);                         % which native segment each point lies in
    seg_idx(isnan(seg_idx)) = numel(segang);
    seg_idx = min(max(seg_idx, 1), numel(segang));
    slope = segang(seg_idx);
    sag   = xq - x(1);                                   % vertex is the first point (s = 0)
    piece = double(xq >= x0);
    T = [su, rq, xq, sag, slope, piece];
end

function sag_write_rows(fid, name, T)
    % clean, human-precision rows: surface, r_mm, sag_mm, slope_deg
    % T columns are [arc, r, x, sag, slope, piece]; we emit r, sag, slope.
    % 1e-6 mm = 1 nm, far below any figure tolerance; rows stay in vertex->tip order.
    for k = 1:size(T,1)
        fprintf(fid, '%s,%.6f,%.6f,%.4f\n', name, T(k,2), T(k,4), T(k,5));
    end
end

function t = tf_yesno(b), if b, t = 'yes'; else, t = 'no'; end, end
