function P = analyze_intensity_profile(trace, lens, emitter, plane_x_du, n_bins)
%ANALYZE_INTENSITY_PROFILE  Radial enclosed-power profile of the collimated beam.
%
%   P = analyze_intensity_profile(trace, lens, emitter, plane_x_du, n_bins)
%
%   Port of NA2_v2/lib/na2_intensity_profile.m: every collected ray's last segment
%   is extrapolated to the plane x = plane_x_du ([] = xmax + 0.5 * lens length),
%   giving its exit radius r = |y|. The 2-D meridional ray stands for a ring, so it
%   is weighted by the emitter pattern x sin(alpha) (emitter_weights - applied
%   ONCE, the rays being sampled uniformly in angle). P.r / P.enclosed_fraction is
%   the fraction of collected power inside radius r; r_50 and r_1e2 (1 - e^-2)
%   are read off it; bin_power is power per radial bin (not divided by annulus
%   area). Design units in, design units out.

    if nargin < 5 || isempty(n_bins), n_bins = 100; end
    allx = cell2mat(cellfun(@(c) c(:,1), lens.final_lens(~cellfun(@isempty, lens.final_lens)), 'UniformOutput', false));
    xmin = min(allx);  xmax = max(allx);
    if nargin < 4 || isempty(plane_x_du), plane_x_du = xmax + 0.5 * (xmax - xmin); end
    P.plane_x = plane_x_du;

    w_all = emitter_weights(trace.alphas0, emitter);
    r = [];  w = [];
    for k = 1:trace.n_rays
        if ~trace.collected(k), continue; end
        p = trace.paths{k};  A = p(end-1, :);  B = p(end, :);
        if abs(B(1) - A(1)) < 1e-9, continue; end          % parallel to the plane
        t = (plane_x_du - A(1)) / (B(1) - A(1));
        y = A(2) + t * (B(2) - A(2));
        r(end+1) = abs(y); %#ok<AGROW>
        w(end+1) = w_all(k); %#ok<AGROW>
    end
    P.n_rays = numel(r);
    if numel(r) < 2
        P.r = []; P.enclosed_fraction = []; P.r_50 = NaN; P.r_1e2 = NaN;
        P.bin_centers = []; P.bin_power = []; return;
    end
    [rs, order] = sort(r(:));  ws = w(order);
    P.r = rs;
    P.enclosed_fraction = cumsum(ws) / sum(ws);
    P.r_50  = quantile_radius(rs, P.enclosed_fraction, 0.5);
    P.r_1e2 = quantile_radius(rs, P.enclosed_fraction, 1 - exp(-2));
    rmax = max(rs) * 1.05;
    edges = linspace(0, rmax, n_bins + 1);
    P.bin_centers = 0.5 * (edges(1:end-1) + edges(2:end));
    P.bin_power = zeros(1, n_bins);
    idx = min(max(floor(rs / rmax * n_bins) + 1, 1), n_bins);
    for k = 1:numel(rs), P.bin_power(idx(k)) = P.bin_power(idx(k)) + ws(k); end
end

function rq = quantile_radius(r, F, q)
    [Fu, iu] = unique(F);
    if numel(Fu) < 2, rq = NaN; return; end
    rq = interp1(Fu, r(iu), q, 'linear', 'extrap');
end
