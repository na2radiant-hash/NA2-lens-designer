function [hit, P_hit, alpha_out] = sim_first_hit_ref(P0, alpha_in, pts, n_in, n_out, u_over)
%SIM_FIRST_HIT_REF  REFERENCE COPY (per-segment loop) of sim_first_hit - equivalence tests only. Legacy first_hit_with_layer of the paper-figure scripts, verbatim.
%
%   [hit, P_hit, alpha_out] = sim_first_hit(P0, alpha_in, pts, n_in, n_out, u_over)
%
%   Nearest segment of the polyline pts that the ray hits AND refracts through
%   (segments where refraction fails - TIR, no intersection - are skipped, exactly
%   like the original; the lib's trace/first_hit decides on geometry first, which
%   can differ at the crescent tips, so the paper figures keep this version).
%   u_over: hit accepted up to u = 1 + u_over past the segment end
%           StochasticRayTrace.m used 0.05, Tracing3D.m 1e-12.

    hit = false; P_hit = [NaN, NaN]; alpha_out = NaN;
    if isempty(pts) || size(pts,1) < 2, return; end
    best_d = inf;
    for k = 1:size(pts,1)-1
        [alpha_new, P_inter] = refract(P0, alpha_in, pts(k,:), pts(k+1,:), n_in, n_out, u_over);
        if any(isnan(P_inter)) || isnan(alpha_new), continue; end
        d = hypot(P_inter(1)-P0(1), P_inter(2)-P0(2));
        if d > 1e-9 && d < best_d
            best_d = d; P_hit = P_inter; alpha_out = alpha_new; hit = true;
        end
    end
end

function [alpha_new, P] = refract(O, alpha, A, B, n1, n2, u_over)
% refract_ray_2d of StochasticRayTrace.m / Tracing3D.m; the error() branches of the
% original (caught by the caller's try/catch) return NaN here - same outcome.
    alpha_new = NaN;  P = [NaN, NaN];
    D = [cosd(alpha), sind(alpha)]; O = O(:).';
    A = A(:).'; B = B(:).'; S = B - A;
    M = [D(:), -S(:)]; rhs = (A - O).';
    if abs(det(M)) < 1e-12, return; end
    sol = M \ rhs; t = sol(1); u = sol(2);
    if t < -1e-12 || u < -1e-12 || u > 1 + u_over, return; end
    t = max(t, 0);
    if norm(S) < 1e-12, return; end
    Pi = O + t*D;

    t_hat = S / norm(S);
    n_hat_ccw = [-t_hat(2),  t_hat(1)];
    n_hat_cw  = [ t_hat(2), -t_hat(1)];
    if dot(D, n_hat_ccw) >= dot(D, n_hat_cw), n_hat = n_hat_ccw; else, n_hat = n_hat_cw; end

    angN   = atan2d(n_hat(2), n_hat(1));
    angRay = atan2d(D(2), D(1));
    theta_in = sim_wrap180(angRay - angN);
    if abs(theta_in) > 90
        angN = sim_wrap180(angN + 180);
        theta_in = sim_wrap180(angRay - angN);
    end
    sin_out = (n1/n2) * sind(theta_in);
    if abs(sin_out) > 1 + 1e-12, return; end          % TIR: original returned NaN angle
    sin_out = max(min(sin_out, 1), -1);
    alpha_new = sim_wrap360(angN + asind(sin_out));
    P = Pi;
end

function a = sim_wrap180(a), a = mod(a + 180, 360) - 180; end
function a = sim_wrap360(a), a = mod(a, 360); end
