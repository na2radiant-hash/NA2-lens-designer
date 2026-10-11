function C = analyze_collimation(trace, target_deg, collimation_fraction)
%ANALYZE_COLLIMATION  Exit-angle statistics of the collected rays.
%
%   C = analyze_collimation(trace, target_deg, collimation_fraction)
%
%   The intended exit angle of a ray emitted at alpha0 is
%       target + alpha0 * (1 - collimation_fraction)
%   (= target for a fully collimating design). dev = wrapTo180(exit - intended). C.table columns: ray, emission_deg,
%   exit_deg, dev_deg, abs_dev_deg (collected rays only). C.mean_abs_deg,
%   C.max_abs_deg, C.rms_deg, C.n_collected, C.n_total, C.worst_ray (emission
%   angle of the largest deviation). (na2_analyze_collimation + the 3Elem CSV.)

    if nargin < 2 || isempty(target_deg), target_deg = 0; end
    if nargin < 3 || isempty(collimation_fraction), collimation_fraction = 1; end
    keep = trace.collected;
    ray  = find(keep);
    a0   = trace.alphas0(keep);
    ex   = trace.exit_angles(keep);
    intended = target_deg + a0 * (1 - collimation_fraction);
    dev  = wrapTo180(ex - intended);

    C.table = [ray(:), a0(:), wrapTo180(ex(:)), dev(:), abs(dev(:))];
    C.columns = {'ray', 'emission_deg', 'exit_deg', 'dev_deg', 'abs_dev_deg'};
    C.target_deg  = target_deg;
    C.collimation_fraction = collimation_fraction;
    C.n_collected = numel(ray);
    C.n_total     = trace.n_rays;
    if isempty(dev)
        C.mean_abs_deg = NaN; C.max_abs_deg = NaN; C.rms_deg = NaN; C.worst_ray = NaN;
    else
        C.mean_abs_deg = mean(abs(dev));
        [C.max_abs_deg, iw] = max(abs(dev));
        C.rms_deg = sqrt(mean(dev.^2));
        C.worst_ray = a0(iw);
    end
end
