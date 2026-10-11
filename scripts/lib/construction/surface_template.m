function s = surface_template(kind)
%SURFACE_TEMPLATE  One entry of lens.surfaces with every field present (struct arrays need that).
%
%   s = surface_template(kind)   kind = 'built' (default) | 'sphere' | 'clamped'
%   sphere  : center_z_du, radius_du, vertex_x_du, theta_max_deg, theta_rays_deg, pts_dense, zemax_R_du
%   clamped : max_slope_deg, pull, first_clamped_ray, n_clamped, clamp_from_deg, clamp_r_from_du,
%             demoldable, demold_note
%   built   : only kind

    if nargin < 1 || isempty(kind), kind = 'built'; end
    s = struct('kind', kind, ...
               'center_z_du', [], 'radius_du', [], 'vertex_x_du', [], 'theta_max_deg', [], ...
               'theta_rays_deg', [], 'pts_dense', [], 'zemax_R_du', [], ...
               'max_slope_deg', [], 'pull', '', 'first_clamped_ray', [], 'n_clamped', [], ...
               'clamp_from_deg', [], 'clamp_r_from_du', [], 'demoldable', [], 'demold_note', '');
end
