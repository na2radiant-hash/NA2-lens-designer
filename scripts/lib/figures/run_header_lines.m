function lines = run_header_lines(lens, cfg, glass_label)
%RUN_HEADER_LINES  What a result picture must say about the run: materials, construction variants, design.
%
%   lines = run_header_lines(lens, cfg, glass_label)      (cellstr: materials, one line per variant surface, design)
%
%   1  materials / refractive indices: glass_label as the entry script builds it
%      ('SCHOTT N-LASF9 (n = 1.8445 at 637 nm)', or per element
%      'E1 PMMA (n = 1.4886 at 637 nm) | E2-E4 OHARA S-LAH99 (n = 1.9935 at 637 nm)')
%   2  construction variants, only when the lens has any (lens.surfaces):
%      'S2 (outer surface of element 1): SPHERE R = 5.730 mm, centre x = 0.170 mm'
%      'S1 (cavity of element 1): STRAIGHT wall from r = 1.86 mm (pull back)' / '87 deg draft ...'
%   3  the design in one line: NA hole -> fan, working distance, rays, surfaces
%   Used as the header of the construction-geometry figure and of the ray-trace picture.

    mm = lens.mm_per_du;
    if nargin < 3 || isempty(glass_label), glass_label = sprintf('n = %.4g', lens.n2); end
    lines = {glass_label};

    v = {};
    if isfield(lens, 'surfaces') && isstruct(lens.surfaces)
        for j = 1:numel(lens.surfaces)
            s = lens.surfaces(j);
            e = ceil(j / 2);
            if mod(j, 2) == 1
                if e == 1, where = sprintf('S%d (cavity of element 1)', j); else, where = sprintf('S%d (inner surface of element %d)', j, e); end
            else
                where = sprintf('S%d (outer surface of element %d)', j, e);
            end
            switch s.kind
                case 'sphere'
                    v{end+1} = sprintf('%s: SPHERE R = %.3f mm, centre x = %.3f mm', where, s.radius_du * mm, s.center_z_du * mm); %#ok<AGROW>
                case 'clamped'
                    if abs(s.max_slope_deg - 90) < 1e-9, what = 'STRAIGHT wall'; else, what = sprintf('%g deg draft (%g deg taper)', s.max_slope_deg, 90 - s.max_slope_deg); end
                    if ~isempty(s.first_clamped_ray) && isfinite(s.first_clamped_ray)
                        v{end+1} = sprintf('%s: %s from r = %.2f mm (pull %s)', where, what, s.clamp_r_from_du * mm, s.pull); %#ok<AGROW>
                    else
                        v{end+1} = sprintf('%s: no undercut inside the fan (the %g deg limit is never reached)', where, s.max_slope_deg); %#ok<AGROW>
                    end
            end
        end
    end
    lines = [lines, v];                               % one line per prescribed / clamped surface (a joined line is clipped by the figure)

    D = cfg.design;
    lines{end+1} = sprintf('NA hole %.2f -> design fan 0..%.1f deg   |   WD %.2f mm   |   %d design rays, %d surfaces', ...
        D.NA_hole, lens.design_max_angle, D.WD_mm, D.rays_count, lens.L);
end
