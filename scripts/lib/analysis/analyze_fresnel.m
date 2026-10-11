function F = analyze_fresnel(trace, stack, polarization)
%ANALYZE_FRESNEL  Fresnel reflection loss per interface and per ray; TIR margin.
%
%   F = analyze_fresnel(trace, stack, polarization)
%
%   Formulas of NA2_v2/lib/na2_analyze_reflection.m:
%     Rs = ((n_in cos ti - n_out cos tt) / (n_in cos ti + n_out cos tt))^2
%     Rp = ((n_in cos tt - n_out cos ti) / (n_in cos tt + n_out cos ti))^2
%     unpolarized = (Rs + Rp)/2 ; 's' / 'p' select one. No coatings, no absorption,
%     no polarization tracking between surfaces (each interface freshly unpolarized).
%   Per ray the intensity chain I <- I (1 - R) from 100 % gives output_pct.
%   Per interface: mean/max incidence, mean reflectance, Brewster angle,
%   critical angle (n_in > n_out only) and the minimum margin |crit| - |incidence|
%   over the rays that reached it (the TIR margin used by the checks).
%   Averages are over collected rays only.

    if nargin < 3 || isempty(polarization), polarization = 'unpolarized'; end
    S = numel(stack);  N = trace.n_rays;
    per_ray_I = nan(N, S);          % intensity (%) after each interface
    output_pct = nan(N, 1);
    inc_all = cell(1, S);
    R_all   = cell(1, S);
    for r = 1:N
        I = 100;
        ths = trace.hit_theta{r};
        for k = 1:numel(ths)
            Rk = fresnel_R(ths(k), stack(k).n_in, stack(k).n_out, polarization);
            I = I * (1 - Rk);
            per_ray_I(r, k) = I;
            inc_all{k}(end+1) = abs(ths(k)); %#ok<AGROW>
            R_all{k}(end+1)   = Rk;          %#ok<AGROW>
        end
        if trace.collected(r), output_pct(r) = I; end
        if strcmp(trace.status{r}, 'tir') && ~isempty(ths), per_ray_I(r, numel(ths)) = 0; end
    end

    % ---- per interface ----
    T = zeros(S, 9);
    labels = cell(S, 1);
    min_margin = inf;  min_margin_k = 0;  min_margin_ray = NaN;
    for k = 1:S
        nin = stack(k).n_in;  nout = stack(k).n_out;
        brew = atand(nout / nin);
        crit = NaN;  if nin > nout, crit = asind(nout / nin); end
        inc = inc_all{k};  Rk = R_all{k};
        if isempty(inc), inc = NaN; Rk = NaN; end
        margin = NaN;
        if ~isnan(crit) && ~isempty(inc_all{k})
            [margin, im] = min(crit - inc_all{k});
            if margin < min_margin
                min_margin = margin;  min_margin_k = k;
                hits = find(cellfun(@(t) numel(t) >= k, trace.hit_theta));
                if ~isempty(hits) && im <= numel(hits), min_margin_ray = trace.alphas0(hits(im)); end
            end
        end
        n_tir = sum(cellfun(@(s) strcmp(s, 'tir'), trace.status) & (trace.n_hits == k));
        T(k, :) = [k, nin, nout, brew, crit, mean(inc), max(inc), 100*mean(Rk), n_tir];
        T(k, 9) = n_tir;
        labels{k} = stack(k).label;
        margins(k) = margin; %#ok<AGROW>
    end
    F.per_interface = T;
    F.per_interface_columns = {'interface', 'n_in', 'n_out', 'brewster_deg', 'critical_deg', ...
                               'mean_incidence_deg', 'max_incidence_deg', 'mean_reflectance_pct', 'n_TIR'};
    F.labels = labels;
    F.tir_margin_deg = margins(:).';
    F.min_tir_margin_deg = min_margin;
    F.min_tir_margin_interface = min_margin_k;
    F.min_tir_margin_ray_deg = min_margin_ray;
    F.per_ray_intensity = per_ray_I;
    F.output_pct = output_pct;
    c = trace.collected;
    F.mean_transmission = mean(output_pct(c)) / 100;
    F.mean_loss_pct = 100 - mean(output_pct(c));
    F.n_tir = trace.n_tir;
    F.polarization = polarization;
end

function R = fresnel_R(theta_i_deg, n_in, n_out, pol)
    ti = abs(theta_i_deg);
    sin_t = (n_in / n_out) * sind(ti);
    if sin_t >= 1, R = 1; return; end
    cos_i = cosd(ti);  cos_t = sqrt(1 - sin_t^2);
    Rs = ((n_in * cos_i - n_out * cos_t) / (n_in * cos_i + n_out * cos_t))^2;
    Rp = ((n_in * cos_t - n_out * cos_i) / (n_in * cos_t + n_out * cos_i))^2;
    switch lower(pol)
        case 's', R = Rs;
        case 'p', R = Rp;
        otherwise, R = (Rs + Rp) / 2;
    end
end
