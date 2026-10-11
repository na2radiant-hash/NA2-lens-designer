function [alpha, theta_in, theta_out, gamma, n_fallback, W] = calculate_angles(L, R, varargin)
%CALCULATE_ANGLES  Per-ray / per-surface bending schedule and surface-normal angles.
%
%   [alpha, theta_in, theta_out, gamma, n_fallback, W] = calculate_angles(L, R, nsurf, max_angle, w, epsilon, theta_target, opts)
%   [...] = calculate_angles(L, R, n1, n2, max_angle, w, epsilon, theta_target, opts)   (legacy call)
%
%   nsurf: [L x 2] (n_in, n_out) per surface (design.element_materials), or the
%   pair [n1 n2] for the legacy alternation air/glass/air (see expand_nsurf).
%
%   Angles in degrees. alpha(:,1) is the initial global angle of each design ray;
%   alpha(:,j+1) the angle after surface j; gamma(i,j) the surface tangent angle
%   (= normal angle phi + 90) that surface j must have where ray i crosses it.
%
%   Maths of LensConstructionGradual.m (2026-09-05), with the variants of the
%   other construction scripts folded in through opts:
%     opts.method               'symbolic' (vpasolve, the original) | 'analytic' (closed form)
%     opts.collimation_fraction 1 = every ray ends at theta_target (strict collimation);
%                               <1 = ray keeps (1-f) of its initial angle (2Omni1Aspherical)
%     opts.L_design             surfaces the WEIGHTS are distributed over (>= L); the rays
%                               are only bent through the first L (3Elem two-stage mode)
%   w: J_front, k_shape, base_w, hardness_exp, layer_exp   (k_shape = 0 -> uniform split)
%   n_fallback counts symbolic solves that silently returned phi = 0 (0 for analytic).
%   W is the schedule (bend_weights) - construct_lens re-solves surface by surface
%   with layer_angles when a prescribed sphere or a slope clamp changes what a
%   surface delivers. The whole schedule is bend_weights + layer_angles applied to
%   every surface in order, which is exactly the original loop.

    if numel(varargin) >= 6 && isnumeric(varargin{1}) && isscalar(varargin{1}) && isnumeric(varargin{2}) && isscalar(varargin{2})
        nsurf = [varargin{1}, varargin{2}];  args = varargin(3:end);          % legacy (n1, n2)
    else
        nsurf = varargin{1};                 args = varargin(2:end);
    end
    max_angle = args{1};  w = args{2};  epsilon = args{3};  theta_target = args{4};
    opts = struct();  if numel(args) >= 5 && ~isempty(args{5}), opts = args{5}; end
    nsurf = expand_nsurf(nsurf, L);

    W = bend_weights(L, R, max_angle, w, epsilon, theta_target, opts);
    n_fallback = 0;
    alpha     = zeros(R, L+1);
    theta_in  = zeros(R, L);
    theta_out = zeros(R, L);
    gamma     = zeros(R, L);
    alpha(:, 1) = W.alpha0;

    % ---------------- compute angles layer by layer ----------------
    for j = 1:L
        [alpha(:, j+1), theta_in(:, j), theta_out(:, j), gamma(:, j), nf] = layer_angles(W, j, alpha(:, j), nsurf(j, :), []);
        n_fallback = n_fallback + nf;
    end
end
