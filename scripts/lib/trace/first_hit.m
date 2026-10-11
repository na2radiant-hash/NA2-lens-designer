function [hit, P_hit, alpha_out, theta_in, info] = first_hit(P0, alpha_in, pts, n_in, n_out, overshoot, sph, smooth, kinks)
%FIRST_HIT  Nearest intersection of a ray with a polyline surface, then refraction.
%
%   [hit, P_hit, alpha_out, theta_in, info] = first_hit(P0, alpha_in, pts, n_in, n_out, overshoot, sph, smooth)
%
%   pts is an [N x 2] polyline. The NEAREST intersection (distance > 1e-9) is
%   taken, then Snell's law is applied there. info.tir is true when the ray is
%   lost to total internal reflection at that point (alpha_out = NaN);
%   info.overshoot_used is true when the hit lay past the segment end (u > 1).
%
%   sph    [] or [centre_x radius]: the polyline samples a prescribed sphere - the chord
%          search only decides hit / segment, position and normal are the exact sphere's.
%   smooth false (default) = the segment's own constant normal (legacy). true
%          (trace.smooth_normals) = the tangent turns linearly along the segment from
%          this segment's direction (the design tangent at its first vertex, ray k) to
%          the next segment's direction (ray k+1): the smooth surface the construction
%          polyline samples. Constant normals send a ray that lands just before or
%          after a vertex a whole design-ray step off target - the ~0.9 deg
%          collimation residual, and isolated lost rays next to compressed crescent tips.
%   kinks  vertex indices where the surface has a REAL corner (the start of a straight
%          wall or cone, design.slope_limits): the tangent is not interpolated across
%          them, because there the polyline is the surface, not a sampling of a smooth one.
%
%   Note: the legacy first_hit_with_layer skipped segments where refraction
%   failed and could pick a farther segment; here the geometry decides first.

    hit = false; P_hit = [NaN, NaN]; alpha_out = NaN; theta_in = NaN;
    info = struct('tir', false, 'overshoot_used', false, 'segment', 0, 'u', NaN, 'theta_out', NaN);
    if isempty(pts) || size(pts, 1) < 2, return; end

    best_d = inf;  best = [];
    for k = 1:size(pts,1)-1
        [a_new, P, th_in, th_out, u, tir] = refract_ray_2d(P0, alpha_in, pts(k,:), pts(k+1,:), n_in, n_out, overshoot);
        if any(isnan(P)), continue; end
        d = hypot(P(1) - P0(1), P(2) - P0(2));
        if d > 1e-9 && d < best_d
            best_d = d;
            best = struct('P', P, 'a', a_new, 'th_in', th_in, 'th_out', th_out, 'u', u, 'tir', tir, 'k', k);
        end
    end
    if isempty(best), return; end
    if nargin < 7, sph = []; end
    if nargin >= 8 && ~isempty(smooth) && smooth && isempty(sph) && size(pts, 1) >= 3
        % smooth surface: same hit point, tangent interpolated between the two design tangents
        k = best.k;  u = min(max(best.u, 0), 1);
        d1 = pts(k+1, :) - pts(k, :);  a1 = atan2d(d1(2), d1(1));
        if k + 2 <= size(pts, 1), d2 = pts(k+2, :) - pts(k+1, :);  a2 = atan2d(d2(2), d2(1)); else, a2 = a1; end
        if nargin >= 9 && ~isempty(kinks) && any(kinks == k + 1), a2 = a1; end     % a corner: constant tangent up to it
        phi = a1 + u * wrapTo180(a2 - a1) - 90;
        if abs(wrapTo180(alpha_in - phi)) > 90, phi = wrapTo180(phi + 180); end
        th_in = wrapTo180(alpha_in - phi);
        so = (n_in / n_out) * sind(th_in);
        best.th_in = th_in;
        if abs(so) > 1 + 1e-12
            best.tir = true;  best.a = NaN;  best.th_out = NaN;
        else
            best.tir = false;  best.th_out = asind(max(min(so, 1), -1));  best.a = wrapTo360(phi + best.th_out);
        end
    end
    if ~isempty(sph)
        % prescribed sphere: the chord search only decides hit / segment; position and normal are exact
        c = sph(1);  Rs = sph(2);
        d = [cosd(alpha_in), sind(alpha_in)];  PC = P0(:).' - [c, 0];
        b = d * PC.';  disc = b^2 - (PC * PC.' - Rs^2);
        if disc >= 0
            ts = [-b - sqrt(disc), -b + sqrt(disc)];
            [~, it] = min(abs(ts - best_d));
            H = P0(:).' + ts(it) * d;
            phi = atan2d(H(2), H(1) - c);
            if abs(wrapTo180(alpha_in - phi)) > 90, phi = wrapTo180(phi + 180); end
            th_in = wrapTo180(alpha_in - phi);
            so = (n_in / n_out) * sind(th_in);
            best.P = H;  best.th_in = th_in;
            if abs(so) > 1 + 1e-12
                best.tir = true;  best.a = NaN;  best.th_out = NaN;
            else
                best.tir = false;  best.th_out = asind(max(min(so, 1), -1));  best.a = wrapTo360(phi + best.th_out);
            end
        end
    end

    hit       = true;
    P_hit     = best.P;
    alpha_out = best.a;
    theta_in  = best.th_in;
    info.tir  = best.tir;
    info.overshoot_used = best.u > 1;
    info.segment   = best.k;
    info.u         = best.u;
    info.theta_out = best.th_out;
end
