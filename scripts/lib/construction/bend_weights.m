function W = bend_weights(L, R, max_angle, w, epsilon, theta_target, opts)
%BEND_WEIGHTS  The bending schedule of LensConstructionGradual: design fan, total bend, weights.
%
%   W = bend_weights(L, R, max_angle, w, epsilon, theta_target, opts)
%
%   Everything calculate_angles computed BEFORE its Snell loop, with the same
%   arithmetic (the numbers are bit-identical):
%     W.alpha0       [R x 1]  initial global angle of each design ray (deg)
%     W.alpha_final  [R x 1]  intended exit angle (theta_target, or a fraction of alpha0 for
%                             partial collimation, opts.collimation_fraction < 1)
%     W.total_bend   [R x 1]  alpha0 - alpha_final
%     W.wm           [R x Ld] per-ray / per-surface weights,  W.Wsum [R x 1] their row sums
%     W.Ld           surfaces the weights are spread over (>= L; 3Elem two-stage budget)
%     W.L, W.method  surfaces built here; 'symbolic' | 'analytic' Snell solver
%   The planned bend of ray i at surface j is total_bend(i) * wm(i,j) / Wsum(i)
%   (layer_angles). Split out of calculate_angles so construct_lens can solve one
%   surface at a time and carry the shortfall of a prescribed sphere or a clamped
%   (draft-limited) surface into the surfaces that follow.

    if nargin < 7 || isempty(opts), opts = struct(); end
    method = 'symbolic';
    if isfield(opts, 'method') && ~isempty(opts.method), method = opts.method; end
    cfrac = 1;
    if isfield(opts, 'collimation_fraction') && ~isempty(opts.collimation_fraction), cfrac = opts.collimation_fraction; end
    Ld = L;
    if isfield(opts, 'L_design') && ~isempty(opts.L_design), Ld = max(L, opts.L_design); end

    % ---- Initial fan of design rays in [0, max_angle - eps] (full span) ----
    alpha0 = zeros(R, 1);
    for i = 1:R
        alpha0(i) = (i - 1) * (max_angle - epsilon) / (R - 1);
    end

    % ------------ common final angle (COLLIMATION, or a fraction of it) -------------
    alpha_final = theta_target * ones(R,1) + alpha0 * (1 - cfrac);
    total_bend  = alpha0 - alpha_final;                    % total bend per ray

    % ------------- per-layer/per-ray weights (distribution over Ld surfaces) ------------
    J_front      = min(w.J_front, Ld);
    k_shape      = w.k_shape;
    base_w       = w.base_w;
    hardness_exp = w.hardness_exp;
    layer_exp    = w.layer_exp;

    alpha_max = max(alpha0);
    wm   = zeros(R, Ld);
    Wsum = zeros(R, 1);
    for i = 1:R
        hardness = (alpha0(i) / alpha_max)^hardness_exp;
        for j = 1:Ld
            if j <= J_front
                frac_layer = (J_front - (j-1)) / J_front;
                frac_layer = frac_layer^layer_exp;
                extra   = k_shape * hardness * frac_layer;
                wm(i,j) = base_w + extra;
            else
                wm(i,j) = base_w;
            end
        end
        Wsum(i) = sum(wm(i,:));
    end

    W = struct('alpha0', alpha0, 'alpha_final', alpha_final, 'total_bend', total_bend, ...
               'wm', wm, 'Wsum', Wsum, 'Ld', Ld, 'L', L, 'method', method);
end
