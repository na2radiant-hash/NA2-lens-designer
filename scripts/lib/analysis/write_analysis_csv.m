function files = write_analysis_csv(AN, trace, stack, lens, out_dir)
%WRITE_ANALYSIS_CSV  Plain CSV files of the analyses (collimation, Fresnel, profile, collection, rays).
%
%   files = write_analysis_csv(AN, trace, stack, lens, out_dir)
%   Written only for the analyses present in AN. Lengths in mm.

    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    files = {};
    mm = lens.mm_per_du;

    % per-ray trace summary (always, when traced)
    if ~isempty(trace)
        f = fullfile(out_dir, 'rays.csv');
        fid = fopen(f, 'w');
        fprintf(fid, 'ray,emission_deg,status,surfaces_hit,exit_deg,overshoot_used\n');
        for r = 1:trace.n_rays
            fprintf(fid, '%d,%.6f,%s,%d,%.6f,%d\n', r, trace.alphas0(r), trace.status{r}, trace.n_hits(r), trace.exit_angles(r), trace.overshoot_used(r));
        end
        fclose(fid);  files{end+1} = f;
    end

    if isfield(AN, 'collimation') && ~isempty(AN.collimation)
        f = fullfile(out_dir, 'collimation.csv');
        write_matrix(f, AN.collimation.columns, AN.collimation.table);
        files{end+1} = f;
    end

    if isfield(AN, 'fresnel') && ~isempty(AN.fresnel)
        F = AN.fresnel;
        f = fullfile(out_dir, 'fresnel_per_interface.csv');
        fid = fopen(f, 'w');
        fprintf(fid, 'interface,label,n_in,n_out,brewster_deg,critical_deg,mean_incidence_deg,max_incidence_deg,mean_reflectance_pct,n_TIR,min_TIR_margin_deg\n');
        for k = 1:size(F.per_interface, 1)
            v = F.per_interface(k, :);
            fprintf(fid, '%d,%s,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f,%.4f,%d,%.3f\n', v(1), F.labels{k}, v(2), v(3), v(4), v(5), v(6), v(7), v(8), v(9), F.tir_margin_deg(k));
        end
        fclose(fid);  files{end+1} = f;
        f = fullfile(out_dir, 'fresnel_per_ray.csv');
        fid = fopen(f, 'w');
        S = size(F.per_ray_intensity, 2);
        fprintf(fid, 'ray,emission_deg,status%s,output_pct\n', sprintf(',I_after_%d', 1:S));
        for r = 1:size(F.per_ray_intensity, 1)
            fprintf(fid, '%d,%.6f,%s%s,%.4f\n', r, trace.alphas0(r), trace.status{r}, sprintf(',%.4f', F.per_ray_intensity(r, :)), F.output_pct(r));
        end
        fclose(fid);  files{end+1} = f;
    end

    if isfield(AN, 'profile') && ~isempty(AN.profile) && ~isempty(AN.profile.r)
        P = AN.profile;
        f = fullfile(out_dir, 'intensity_profile.csv');
        fid = fopen(f, 'w');
        fprintf(fid, '# plane_x_mm,%.6f,r50_mm,%.6f,r_1e2_mm,%.6f,rays,%d\n', P.plane_x * mm, P.r_50 * mm, P.r_1e2 * mm, P.n_rays);
        fprintf(fid, 'r_mm,enclosed_fraction\n');
        fprintf(fid, '%.6f,%.6f\n', [P.r(:) * mm, P.enclosed_fraction(:)].');
        fclose(fid);  files{end+1} = f;
        f = fullfile(out_dir, 'intensity_bins.csv');
        fid = fopen(f, 'w');
        fprintf(fid, 'r_center_mm,power_au\n');
        fprintf(fid, '%.6f,%.8g\n', [P.bin_centers(:) * mm, P.bin_power(:)].');
        fclose(fid);  files{end+1} = f;
    end

    if isfield(AN, 'collection') && ~isempty(AN.collection)
        K = AN.collection;
        f = fullfile(out_dir, 'collection_summary.csv');
        fid = fopen(f, 'w');
        fprintf(fid, 'quantity,value\n');
        fprintf(fid, 'phi_traced_%s,%.6f\n', K.emitter.type, K.phi_traced);
        fprintf(fid, 'phi_traced_isotropic,%.6f\n', K.phi_traced_isotropic);
        fprintf(fid, 'phi_fan_max_%s,%.6f\n', K.emitter.type, K.phi_fan_max);
        fprintf(fid, 'phi_fan_max_isotropic,%.6f\n', K.phi_fan_max_isotropic);
        fprintf(fid, 'legacy_ray_fraction,%.6f\n', K.legacy_ray_fraction);
        fprintf(fid, 'legacy_sin2_fraction,%.6f\n', K.legacy_sin2_fraction);
        fprintf(fid, 'theta_lens_deg,%.4f\n', K.theta_lens_deg);
        fprintf(fid, 'NA_lens,%.4f\n', K.NA_lens);
        fprintf(fid, 'phi_isotropic_analytic_at_lens,%.6f\n', K.phi_iso_at_lens);
        fprintf(fid, 'phi_dipole_analytic_at_lens,%.6f\n', K.phi_dip_at_lens);
        for k = 1:numel(K.targets)
            fprintf(fid, 'target_%g_theta0_deg_dipole,%.4f\n', K.targets(k), K.target_theta0_dip(k));
            fprintf(fid, 'target_%g_NA_dipole,%.4f\n', K.targets(k), K.target_NA_dip(k));
        end
        fclose(fid);  files{end+1} = f;
        f = fullfile(out_dir, 'collection_curve.csv');
        write_matrix(f, {'theta0_deg', 'NA', 'phi_isotropic', 'phi_dipole'}, [K.theta0, sind(K.theta0), K.phi_iso_curve, K.phi_dip_curve]);
        files{end+1} = f;
    end
end

function write_matrix(f, cols, A)
    fid = fopen(f, 'w');
    fprintf(fid, '%s\n', strjoin(cols, ','));
    fmt = [strjoin(repmat({'%.6f'}, 1, size(A, 2)), ','), '\n'];
    fprintf(fid, fmt, A.');
    fclose(fid);
end
