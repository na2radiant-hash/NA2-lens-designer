function stack = build_stack(lens)
%BUILD_STACK  Ordered list of refracting surfaces a ray meets, with the media on each side.
%
%   stack = build_stack(lens)
%
%   Each entry: pts ([N x 2] polyline, design units, upper half r >= 0), n_in,
%   n_out, label, kind ('lens' | 'glass' | 'asphere'), element (0 if none).
%   Order: omni surfaces 1..L, with the two flat faces of a glass spacer
%   inserted before the element it precedes, and the commercial asphere's two
%   surfaces appended after the last omni surface.
%   Media per surface come from lens.n_surface (design.element_materials: one
%   index per element); a lens without it alternates n1/n2 as before. A
%   prescribed sphere is traced as its exact arc (design_profiles); a clamped surface
%   reports its corner (kinks) so the smooth-normal trace does not round it off.

    stack = struct('pts', {}, 'n_in', {}, 'n_out', {}, 'label', {}, 'kind', {}, 'element', {}, 'sphere', {}, 'kinks', {});
    L = lens.L;  n1 = lens.n1;  n2 = lens.n2;
    nsurf = [];
    if isfield(lens, 'n_surface') && ~isempty(lens.n_surface) && size(lens.n_surface, 1) >= L
        nsurf = lens.n_surface;
    end
    surfaces = [];  if isfield(lens, 'surfaces'), surfaces = lens.surfaces; end
    FL = design_profiles(lens.final_lens, surfaces);
    gaps = [];
    if ~isempty(lens.glass_info) && isstruct(lens.glass_info) && isfield(lens.glass_info, 'gaps') ...
            && isfield(lens.glass_info, 'enabled') && lens.glass_info.enabled
        gaps = lens.glass_info.gaps;
    end

    for j = 1:L
        if j > numel(FL) || isempty(FL{j}), continue; end
        % glass spacer whose "enforce" surface is this one: its two faces come first
        for k = 1:numel(gaps)
            g = gaps(k);
            if g.j_enforce == j && ~isnan(g.h_glass)
                h = g.h_glass;  n3 = lens.glass_info.n3;
                stack(end+1) = struct('pts', [g.x_left, 0; g.x_left, h], 'n_in', n1, 'n_out', n3, ...
                    'label', sprintf('glass cell %d entry', g.element), 'kind', 'glass', 'element', g.element, 'sphere', [], 'kinks', []); %#ok<AGROW>
                stack(end+1) = struct('pts', [g.x_right, 0; g.x_right, h], 'n_in', n3, 'n_out', n1, ...
                    'label', sprintf('glass cell %d exit', g.element), 'kind', 'glass', 'element', g.element, 'sphere', [], 'kinks', []); %#ok<AGROW>
            end
        end
        if ~isempty(nsurf)
            nin = nsurf(j, 1);  nout = nsurf(j, 2);
        elseif mod(j, 2) == 1
            nin = n1; nout = n2;
        else
            nin = n2; nout = n1;
        end
        sph = [];  kinks = [];
        if ~isempty(surfaces) && isstruct(surfaces) && j <= numel(surfaces)
            if strcmp(surfaces(j).kind, 'sphere'), sph = [surfaces(j).center_z_du, surfaces(j).radius_du]; end
            % a straight wall / cone starts with a real corner at the first clamped design ray
            if strcmp(surfaces(j).kind, 'clamped') && ~isempty(surfaces(j).first_clamped_ray) && isfinite(surfaces(j).first_clamped_ray)
                kinks = surfaces(j).first_clamped_ray;
            end
        end
        stack(end+1) = struct('pts', FL{j}, 'n_in', nin, 'n_out', nout, ...
            'label', sprintf('surface %d (element %d %s)', j, ceil(j/2), inout(j)), 'kind', 'lens', 'element', ceil(j/2), 'sphere', sph, 'kinks', kinks); %#ok<AGROW>
    end

    if ~isempty(lens.asphere) && isstruct(lens.asphere)
        A = lens.asphere;
        stack(end+1) = struct('pts', A.S1, 'n_in', n1, 'n_out', A.n, 'label', 'asphere S1', 'kind', 'asphere', 'element', L/2 + 1, 'sphere', [], 'kinks', []); %#ok<AGROW>
        stack(end+1) = struct('pts', A.S2, 'n_in', A.n, 'n_out', n1, 'label', 'asphere S2', 'kind', 'asphere', 'element', L/2 + 1, 'sphere', [], 'kinks', []); %#ok<AGROW>
    end
end

function s = inout(j)
    if mod(j, 2) == 1, s = 'inner'; else, s = 'outer'; end
end
