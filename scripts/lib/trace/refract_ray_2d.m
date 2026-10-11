function [alpha_new, P, theta_in, theta_out, u, tir] = refract_ray_2d(origin, alpha, A, B, n1, n2, overshoot)
%REFRACT_RAY_2D  Intersect a ray with one straight surface segment and apply Snell's law.
%
%   [alpha_new, P, theta_in, theta_out, u, tir] = refract_ray_2d(origin, alpha, A, B, n1, n2, overshoot)
%
%   Maths of the original NA2 tracers (StochasticRayTrace / LensConstructionGradual).
%   Differences from the originals are only in the interface:
%     - overshoot: a hit is accepted up to u = 1 + overshoot past the segment end
%       (StochasticRayTrace used 0.05, LensConstructionGradual 1e-12). u is returned
%       so the caller can count hits that needed the allowance.
%     - no intersection / degenerate geometry -> P = [NaN NaN] instead of error().
%     - total internal reflection -> tir = true, alpha_new = NaN (the ray is lost;
%       reflection is not traced).

    if nargin < 7, overshoot = 1e-12; end
    alpha_new = NaN; theta_in = NaN; theta_out = NaN; u = NaN; tir = false;
    P = [NaN, NaN];

    D = [cosd(alpha), sind(alpha)];  O = origin(:).';
    A = A(:).';  B = B(:).';  S = B - A;
    if norm(S) < 1e-12, return; end                     % degenerate segment
    M = [D(:), -S(:)];  rhs = (A - O).';  detM = det(M);
    if abs(detM) < 1e-12, return; end                   % parallel
    sol = M \ rhs;  t = sol(1);  u = sol(2);
    if t < -1e-12 || u < -1e-12 || u > 1 + overshoot, return; end   % no intersection
    t = max(t, 0);
    P = O + t*D;

    t_hat     = S / norm(S);
    n_hat_ccw = [-t_hat(2),  t_hat(1)];
    n_hat_cw  = [ t_hat(2), -t_hat(1)];
    if dot(D, n_hat_ccw) >= dot(D, n_hat_cw), n_hat = n_hat_ccw; else, n_hat = n_hat_cw; end
    angN      = atan2d(n_hat(2), n_hat(1));
    angRay    = atan2d(D(2), D(1));
    theta_in  = wrapTo180(angRay - angN);
    if abs(theta_in) > 90, angN = wrapTo180(angN + 180);  theta_in = wrapTo180(angRay - angN); end
    sin_out = (n1/n2) * sind(theta_in);
    if abs(sin_out) > 1 + 1e-12
        tir = true;  return;                            % total internal reflection
    end
    sin_out   = max(min(sin_out, 1), -1);
    theta_out = asind(sin_out);
    alpha_new = wrapTo360(angN + theta_out);
end
