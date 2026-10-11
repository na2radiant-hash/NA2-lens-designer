function [pts, alpha_out, theta_in, theta_out, gamma, S] = sphere_layer(prev_pts, alpha_in, alpha0, c, Rs, nij, j, prev_profiles)
%SPHERE_LAYER  A prescribed spherical surface (design.spherical_surfaces): intersect and refract the design rays.
%
%   [pts, alpha_out, theta_in, theta_out, gamma, S] = sphere_layer(prev_pts, alpha_in, alpha0, c, Rs, nij, j, prev_profiles)
%     prev_pts      [R x 2] where each design ray leaves the previous surface (the source for j = 1)
%     alpha_in      [R x 1] its direction (deg);  alpha0 [R x 1] emission angles (for messages)
%     c, Rs         sphere centre on the axis (x = c, 0 = emitter) and radius, design units
%     nij           [n_in n_out] of the surface;  j its index
%     prev_profiles cell of the surfaces built so far (dense arcs for spheres) - the sphere must not cross them
%
%   Nothing is searched: the layer is where the rays meet the sphere. pts(i,:) is
%   the hit of ray i (so final_lens{j} keeps one row per design ray like every other
%   layer), the normal is radial, Snell gives alpha_out; theta_in/theta_out/gamma
%   follow the construction convention (gamma = phi + 90, |theta_in| <= 90).
%   S is the lens.surfaces entry: the exact arc from the vertex to the last design
%   ray (pts_dense, ~0.25 deg steps) for exports, trace and drawings, the polar
%   angle of every ray on the sphere, and zemax_R_du (negative when the centre lies
%   on the emitter side of the vertex, the Zemax sign convention).
%
%   Errors (construction stops; these are the FAILs of the variant): a ray misses
%   the sphere (first missing emission angle named), total internal reflection at
%   it, the hits are not ordered along the arc, or the arc crosses an earlier surface.

    R = numel(alpha_in);
    pts = nan(R, 2);  alpha_out = nan(R, 1);  theta_in = nan(R, 1);  theta_out = nan(R, 1);  gamma = nan(R, 1);
    theta_rays = nan(R, 1);
    missed = false(R, 1);  tir = false(R, 1);
    C = [c, 0];
    for i = 1:R
        P = prev_pts(i, :);
        d = [cosd(alpha_in(i)), sind(alpha_in(i))];
        PC = P - C;
        b  = d(1)*PC(1) + d(2)*PC(2);
        cc = PC(1)^2 + PC(2)^2 - Rs^2;
        disc = b^2 - cc;
        if disc < 0, missed(i) = true; continue; end
        sq = sqrt(disc);
        ts = [-b - sq, -b + sq];
        ts = ts(ts > 1e-9);                                  % ahead of the ray only
        if isempty(ts), missed(i) = true; continue; end
        t = min(ts);                                          % first crossing ahead
        H = P + t * d;
        pts(i, :) = H;
        theta_rays(i) = atan2d(abs(H(2)), H(1) - c);          % polar angle about the centre, 0 = +x side
        % radial normal, oriented like the construction's phi: |alpha - phi| <= 90
        phi = atan2d(H(2), H(1) - c);
        if abs(wrapTo180(alpha_in(i) - phi)) > 90, phi = wrapTo180(phi + 180); end
        th_in = wrapTo180(alpha_in(i) - phi);
        sin_out = (nij(1) / nij(2)) * sind(th_in);
        if abs(sin_out) > 1, tir(i) = true; continue; end
        th_out = asind(sin_out);
        theta_in(i) = th_in;  theta_out(i) = th_out;
        gamma(i) = phi + 90;
        alpha_out(i) = phi + th_out;
        % same branch as the incoming angle (a full-turn jump would corrupt the deficit carry)
        if abs(alpha_out(i) - alpha_in(i)) > 180
            alpha_out(i) = alpha_out(i) - 360 * round((alpha_out(i) - alpha_in(i)) / 360);
        end
    end
    if any(missed)
        i1 = find(missed, 1);
        error('construct_lens:sphere_miss', ['surface %d (design.spherical_surfaces, centre %.4f du, radius %.4f du): %d of %d design rays miss the sphere; ' ...
               'the first is ray %d at %.3f deg emission (arriving at %.3f deg from x = %.4f, r = %.4f du). Enlarge the radius or move the centre.'], ...
               j, c, Rs, sum(missed), R, i1, alpha0(i1), alpha_in(i1), prev_pts(i1, 1), prev_pts(i1, 2));
    end
    if any(tir)
        i1 = find(tir, 1);
        phi1 = atan2d(pts(i1, 2), pts(i1, 1) - c);
        error('construct_lens:sphere_tir', ['surface %d (prescribed sphere): %d design rays are totally internally reflected, ' ...
               'the first is ray %d at %.3f deg emission (incidence %.2f deg, n %.4f -> %.4f).'], ...
               j, sum(tir), i1, alpha0(i1), abs(wrapTo180(alpha_in(i1) - phi1)), nij(1), nij(2));
    end
    dth = diff(theta_rays);
    if ~(all(dth >= -1e-9) || all(dth <= 1e-9))
        k = find(sign(dth) ~= sign(dth(1)) & abs(dth) > 1e-9, 1);
        error('construct_lens:sphere_order', 'surface %d (prescribed sphere): the design-ray hits are not ordered along the arc (ray %d turns back).', j, k + 1);
    end

    % ---- exact arc from the vertex (ray 1, on axis) to the last design ray ----
    th1 = theta_rays(1);  thR = theta_rays(end);
    n_arc = max(2, ceil(abs(thR - th1) / 0.25) + 1);
    th = linspace(th1, thR, n_arc).';
    pts_dense = [c + Rs * cosd(th), Rs * sind(th)];
    pts_dense(1, :) = pts(1, :);  pts_dense(end, :) = pts(end, :);     % endpoints exactly on the hits

    % ---- must not cross any surface built before it ----
    for k = 1:numel(prev_profiles)
        if isempty(prev_profiles{k}), continue; end
        if ~is_valid_layer(pts_dense, prev_profiles(k), 2)
            error('construct_lens:sphere_cross', ['surface %d (prescribed sphere, centre %.4f du, radius %.4f du) crosses surface %d. ' ...
                   'A prescribed sphere must lie entirely beyond its neighbours.'], j, c, Rs, k);
        end
    end

    S = surface_template('sphere');
    S.center_z_du    = c;
    S.radius_du      = Rs;
    S.vertex_x_du    = pts(1, 1);
    S.theta_max_deg  = thR;
    S.theta_rays_deg = theta_rays;
    S.pts_dense      = pts_dense;
    if pts(1, 1) > c, S.zemax_R_du = -Rs; else, S.zemax_R_du = Rs; end
end
