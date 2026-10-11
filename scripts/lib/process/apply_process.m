function M = apply_process(lens, cfg)
%APPLY_PROCESS  Manufacturing profile of every element: tip truncation and edge fillet.
%
%   M = apply_process(lens, cfg)
%
%   Works in design units on the closed upper-half crescent of each element
%   (inner surface vertex -> tip, cap, outer surface tip -> vertex, closed the
%   same way the drawings close it: flat cap for element 1, pointy tip for the
%   others). Two operations from cfg.process, both off at 0:
%     tip_truncate_mm  walk back this arc length from the tip along both sides
%                      and close with a straight cap (removes the knife edge);
%     edge_fillet_mm   round the two cap corners: trim d = rho / tan(theta/2)
%                      along each side and blend with a tangent-continuous curve
%                      (quadratic Bezier through the tangent intersection) - a
%                      close approximation of a fillet of radius rho on a polyline.
%   With both at 0 the profiles are returned unchanged, so every exporter gives
%   the same files as before.
%
%   A prescribed sphere (design.spherical_surfaces) enters here as its exact
%   dense arc (design_profiles), so every vendor file and drawing downstream
%   carries the true sphere; the design-ray sampling stays in lens.final_lens.
%
%   M.final_lens      cell like lens.final_lens with the processed inner/outer polylines
%   M.surfaces        lens.surfaces (kind per surface) or []
%   M.elements(e)     inner, outer, cap, pointy, trimmed_inner_du, trimmed_outer_du
%   M.first_lost_ray  smallest design-ray index whose inner-surface point was removed
%                     (Inf = none) -> fan loss in the checks
%   M.changed         true when any operation was applied

    mm = lens.mm_per_du;
    t_du = cfg.process.tip_truncate_mm / mm;
    r_du = cfg.process.edge_fillet_mm  / mm;
    L = lens.L;  nE = floor(L/2);
    surfaces = [];  if isfield(lens, 'surfaces'), surfaces = lens.surfaces; end
    FL0 = design_profiles(lens.final_lens, surfaces);
    M.final_lens = FL0;
    M.surfaces = surfaces;
    M.changed = (t_du > 0) || (r_du > 0);
    M.first_lost_ray = Inf;
    M.elements = struct('inner', {}, 'outer', {}, 'cap', {}, 'pointy', {}, ...
                        'trimmed_inner_du', {}, 'trimmed_outer_du', {}, 'fillet_d_du', {}, 'n_blend_inner', {}, 'n_blend_outer', {});

    for e = 1:nE
        li = 2*e - 1;  lo = 2*e;
        inner = FL0{li};  outer = FL0{lo};
        [tip, cap, pointy] = crescent_outline(inner, outer, e);
        E = struct('inner', inner, 'outer', outer, 'cap', cap, 'pointy', pointy, ...
                   'trimmed_inner_du', 0, 'trimmed_outer_du', 0, 'fillet_d_du', 0, 'n_blend_inner', 0, 'n_blend_outer', 0);
        if M.changed
            % side polylines ending at the apex (the pointy tip or the cap corners)
            if pointy, sideA = [inner; tip]; sideB = [outer; tip]; else, sideA = inner; sideB = outer; end
            % --- truncation: walk back t along both sides from the apex ---
            [sideA, cutA] = walk_back(sideA, t_du);
            [sideB, cutB] = walk_back(sideB, t_du);
            % --- fillet at the two corners (sideA end -> cap -> sideB end) ---
            d = 0;  blendA = []; blendB = [];
            if r_du > 0
                capdir = sideB(end, :) - sideA(end, :);
                if norm(capdir) < 1e-12 && pointy       % untruncated pointy tip: one corner
                    [sideA, sideB, d, blendA] = fillet_tip(sideA, sideB, r_du);
                else
                    [sideA, blendA, dA] = fillet_corner(sideA,  capdir, r_du);
                    [sideB, blendB, dB] = fillet_corner(sideB, -capdir, r_du);
                    d = max(dA, dB);
                end
            end
            E.trimmed_inner_du = cutA;  E.trimmed_outer_du = cutB;  E.fillet_d_du = d;
            E.inner = [sideA; blendA];
            E.outer = [sideB; blendB];
            E.n_blend_inner = size(blendA, 1);  E.n_blend_outer = size(blendB, 1);   % for export_step
            E.cap   = [E.inner(end, :); E.outer(end, :)];
            E.pointy = false;
            M.final_lens{li} = E.inner;
            M.final_lens{lo} = E.outer;
            % design rays that no longer meet the inner surface: points removed from the tip
            is_sphere = ~isempty(surfaces) && isstruct(surfaces) && li <= numel(surfaces) ...
                        && strcmp(surfaces(li).kind, 'sphere') && ~isempty(surfaces(li).theta_rays_deg);
            if is_sphere
                % the inner profile is the dense arc: map the surviving arc back to the design rays
                S = surfaces(li);
                p_end  = sideA(end, :);
                th_end = atan2d(abs(p_end(2)), p_end(1) - S.center_z_du);
                th1    = S.theta_rays_deg(1);
                lost   = find(abs(S.theta_rays_deg - th1) > abs(th_end - th1) + 1e-9, 1);
                if ~isempty(lost), M.first_lost_ray = min(M.first_lost_ray, lost); end
            else
                n_kept = size(sideA, 1) - double(pointy);         % original inner points still present
                n_kept = min(n_kept, size(inner, 1));
                if n_kept < size(inner, 1)
                    M.first_lost_ray = min(M.first_lost_ray, n_kept + 1);
                end
            end
        end
        M.elements(e) = E;
    end
end

% ---------------------------------------------------------------------------
function [P, removed] = walk_back(P, s)
    % remove arc length s from the END of polyline P (keeps at least 2 points)
    removed = 0;
    if s <= 0 || size(P, 1) < 3, return; end
    while size(P, 1) > 2
        seg = norm(P(end, :) - P(end-1, :));
        if removed + seg < s
            removed = removed + seg;  P(end, :) = [];
        else
            f = (s - removed) / seg;                       % partial segment
            P(end, :) = P(end, :) + f * (P(end-1, :) - P(end, :));
            removed = s;  return;
        end
    end
end

function [P, blend, d] = fillet_corner(P, capdir, rho)
    % round the corner at the END of P between P's last edge and the cap direction
    blend = [];  d = 0;
    if size(P, 1) < 2 || norm(capdir) < 1e-12, return; end
    u1 = P(end-1, :) - P(end, :);  u1 = u1 / norm(u1);     % back along the side
    u2 = capdir / norm(capdir);                             % along the cap
    ct = max(-1, min(1, dot(u1, u2)));
    theta = acos(ct);                                       % interior corner angle
    if theta < 1e-3 || theta > pi - 1e-3, return; end
    d = rho / tan(theta / 2);
    C = P(end, :);
    [P, got] = walk_back(P, d);
    if got < 1e-12, return; end
    T1 = P(end, :);                                         % tangent point on the side
    T2 = C + min(d, 0.5 * norm(capdir)) * u2;               % tangent point on the cap
    tan1 = P(end, :) - P(end-1, :);  tan1 = tan1 / norm(tan1);
    Q = line_intersection(T1, tan1, T2, -u2);               % control point = tangent intersection
    if any(isnan(Q)), Q = C; end
    s = linspace(0, 1, 10).';  s = s(2:end);
    blend = (1 - s).^2 .* T1 + 2 * (1 - s) .* s .* Q + s.^2 .* T2;
end

function [A, B, d, blend] = fillet_tip(A, B, rho)
    % single sharp corner where the two sides meet (pointy tip, no truncation)
    C = A(end, :);
    u1 = A(end-1, :) - C;  u1 = u1 / norm(u1);
    u2 = B(end-1, :) - C;  u2 = u2 / norm(u2);
    ct = max(-1, min(1, dot(u1, u2)));  theta = acos(ct);
    d = rho / tan(max(theta, 1e-3) / 2);
    A = walk_back(A, d);  B = walk_back(B, d);
    T1 = A(end, :);  T2 = B(end, :);
    s = linspace(0, 1, 10).';  s = s(2:end-1);
    blend = (1 - s).^2 .* T1 + 2 * (1 - s) .* s .* C + s.^2 .* T2;
    % the blend belongs to side A; side B starts where the blend ends
    B = [B; blend(end, :)];
end

function P = line_intersection(p1, d1, p2, d2)
    M = [d1(:), -d2(:)];
    if abs(det(M)) < 1e-12, P = [NaN NaN]; return; end
    t = M \ (p2(:) - p1(:));
    P = p1 + t(1) * d1;
end
