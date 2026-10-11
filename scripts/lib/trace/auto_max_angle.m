function [a_max, ok] = auto_max_angle(lens, stack, T, iters, tol_deg)
%AUTO_MAX_ANGLE  Widest emission angle whose ray still collimates (StochasticRayTrace AUTO_MAX_ANGLE).
%
%   [a_max, ok] = auto_max_angle(lens, stack, T, iters, tol_deg)
%
%   Bisection between 90 deg and the nominal fan limit: a ray "collimates" when
%   it passes every surface and |wrapTo180(exit - intended)| < tol_deg, where
%   intended = T.collimation_target_deg + alpha * (1 - T.collimation_fraction)
%   (both optional in T; default 0 and 1 = strict collimation). ok = false
%   (and a_max = nominal limit) when even the 90-degree probe fails.

    if nargin < 4 || isempty(iters), iters = 44; end
    if nargin < 5 || isempty(tol_deg), tol_deg = 2; end
    hi = lens.nominal_max_angle;
    if isfield(T, 'max_angle_deg') && ~isempty(T.max_angle_deg), hi = T.max_angle_deg; end
    target = 0; frac = 1;
    if isfield(T, 'collimation_target_deg') && ~isempty(T.collimation_target_deg), target = T.collimation_target_deg; end
    if isfield(T, 'collimation_fraction') && ~isempty(T.collimation_fraction), frac = T.collimation_fraction; end
    lo = 90;
    ok = collimates(lo);
    if ~ok, a_max = hi; return; end
    if collimates(hi), a_max = hi; return; end
    for it = 1:iters
        mid = 0.5 * (lo + hi);
        if collimates(mid), lo = mid; else, hi = mid; end
    end
    a_max = lo;

    function c = collimates(a)
        T1 = T;  T1.alphas0 = a;
        tr = trace_rays(lens, stack, T1);
        c = tr.collected(1) && abs(wrapTo180(tr.exit_angles(1) - (target + a * (1 - frac)))) < tol_deg;
    end
end
