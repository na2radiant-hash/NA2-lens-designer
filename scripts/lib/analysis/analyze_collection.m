function K = analyze_collection(trace, lens, emitter, targets, theta_lens_deg)
%ANALYZE_COLLECTION  Collection efficiency: traced (3-D weighted) and analytic curve.
%
%   K = analyze_collection(trace, lens, emitter, targets, theta_lens_deg)
%
%   Traced efficiency = fraction of the EMITTED power (full sphere) that passes
%   every surface: integral over the sampled fan of collected(alpha) p(alpha)
%   sin(alpha), divided by the analytic full-sphere total (emitter_weights).
%   Reported for the configured emitter and, for reference, for an isotropic one,
%   plus the legacy 1-D metrics of StochasticRayTrace (fraction of rays; sin^2-
%   weighted fraction without the solid-angle factor) so old numbers can be matched.
%   Analytic curve phi(theta0) of the fraction collected inside a half-angle
%   theta0 (= 180 - alpha_max): isotropic (1 + cos theta0)/2 ... as in
%   StochasticRayTrace, dipole (2 - cos^3 theta0 + 3 cos theta0)/4 (na2_fig_collection).
%   targets: efficiency levels to mark; theta_lens_deg ([] = asin(NA_hole)) is
%   the lens acceptance half-angle for the NA axis of the figure.

    if nargin < 4, targets = []; end
    if nargin < 5 || isempty(theta_lens_deg), theta_lens_deg = 180 - lens.nominal_max_angle; end

    a = trace.alphas0(:);  c = double(trace.collected(:));
    [w_e, tot_e] = emitter_weights(a, emitter);
    [w_i, tot_i] = emitter_weights(a, struct('type', 'isotropic'));
    K.phi_traced          = fan_integral(a, c .* w_e) / tot_e;
    K.phi_traced_isotropic= fan_integral(a, c .* w_i) / tot_i;
    K.phi_fan_max         = fan_integral(a, w_e) / tot_e;          % if every sampled ray were collected
    K.phi_fan_max_isotropic = fan_integral(a, w_i) / tot_i;
    % legacy 1-D metrics (StochasticRayTrace collection_efficiency)
    K.legacy_ray_fraction = mean(c);
    s2 = sind(a).^2;
    K.legacy_sin2_fraction = sum(c .* s2) / sum(s2);

    % analytic curves vs half-angle theta0 (0..180) and NA = sin(theta0) for theta0 <= 90
    th = linspace(0, 180, 4000).';
    K.theta0 = th;
    K.phi_iso_curve = (1 + cosd(th)) / 2;
    K.phi_dip_curve = (2 - cosd(th).^3 + 3*cosd(th)) / 4;
    K.theta_lens_deg = theta_lens_deg;
    K.NA_lens = sind(theta_lens_deg);
    K.phi_iso_at_lens = (1 + cosd(theta_lens_deg)) / 2;
    K.phi_dip_at_lens = (2 - cosd(theta_lens_deg)^3 + 3*cosd(theta_lens_deg)) / 4;
    K.targets = targets(:).';
    K.target_theta0_dip = nan(size(K.targets));
    K.target_NA_dip = nan(size(K.targets));
    m = th <= 90;
    for k = 1:numel(K.targets)
        K.target_theta0_dip(k) = interp1(K.phi_dip_curve(m), th(m), K.targets(k), 'linear', NaN);
        K.target_NA_dip(k) = sind(K.target_theta0_dip(k));
    end
    K.emitter = emitter;
end

function v = fan_integral(a_deg, f)
    % integral of f(alpha) d(alpha) over the sampled fan (alpha in radians)
    a = deg2rad(a_deg);
    if numel(a) < 2, v = 0; return; end
    da = diff(a);
    if all(abs(da - da(1)) < 1e-9 * max(1, abs(da(1))))
        v = trapz(a, f);                                  % uniform grid: trapezoid
    else
        v = mean(f) * (max(a) - min(a));                  % Monte-Carlo estimate
    end
end
