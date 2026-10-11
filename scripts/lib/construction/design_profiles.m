function FL = design_profiles(final_lens, surfaces)
%DESIGN_PROFILES  Surface polylines for drawing/export: prescribed spheres as their exact arc.
%
%   FL = design_profiles(final_lens, surfaces)
%
%   final_lens{j} holds one row per design ray for every surface kind (what the
%   construction, the truncation check and the two-stage rebuild work on). A
%   prescribed sphere (design.spherical_surfaces) is only sampled there where
%   the design rays hit it; its exact arc is kept in surfaces(j).pts_dense.
%   This returns the cell with those layers replaced by the dense arc, so
%   exporters, the validation trace and the drawings see the true sphere.
%   Built and clamped layers are returned unchanged; surfaces = [] returns the
%   input as is (loaded legacy lenses).

    FL = final_lens;
    if nargin < 2 || isempty(surfaces) || ~isstruct(surfaces), return; end
    for j = 1:min(numel(FL), numel(surfaces))
        s = surfaces(j);
        if isfield(s, 'kind') && strcmp(s.kind, 'sphere') && isfield(s, 'pts_dense') && ~isempty(s.pts_dense)
            FL{j} = s.pts_dense;
        end
    end
end
