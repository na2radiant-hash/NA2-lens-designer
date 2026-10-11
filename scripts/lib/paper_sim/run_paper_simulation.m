function files = run_paper_simulation(SIM, projRoot)
%RUN_PAPER_SIMULATION  Paper mode of LensConstructionGradual: the paper panels, no config.
%
%   files = run_paper_simulation(SIM, projRoot)
%
%   SIM is the PAPER parameter block typed at the top of LensConstructionGradual.m.
%   Each enabled figure builds its own lens from those parameters and exports
%   only its paper panels to SIM.out_dir (relative paths: under the NA2 folder):
%
%     Fig 1A  fig1A_zoom.{pdf,svg}        + _600dpi.png   (StochasticRayTrace 'fig1', zoom view)
%     Fig 1B  fig1B_raytrace.{pdf,svg}    + _600dpi.png   (StochasticRayTrace 'fig1', full view)
%     Fig 1E  fig1E_rays2d.{pdf,emf}      + _600dpi.png   (Tracing3D, 2-D rays only)
%     Fig 1F  fig1F_rays3d.pdf            + _600dpi.png   (Tracing3D, 3-D, N copies + circles)
%     Fig 2C  fig2C_simulation.{pdf,svg}  + _600dpi.png   (StochasticRayTrace 'fig2', full view)
%             fig2C_zoom.{pdf,svg}        + _600dpi.png   (zoom on the inner elements, for the inset)
%     Fig 3B+3C  fig3BC_collection.pdf    + _600dpi.png   (StochasticRayTrace 'fig1', collection
%                fig3BC_collection_nolabels.pdf + _600dpi.png   figure, labelled and label-free;
%                x axis NA or theta_0 in degrees: SIM.fig3BC.x_axis)
%     Fig S (tolerances)  figS_A/B/C.pdf + _600dpi.png, and figS_A/B/C_nolabels.* with no text
%                at all (no letters, titles, axis / tick labels, legends), tolerance_results.csv
%                (sim_tolerance / sim_fig_tolerance: A method schematic; B lambda/2 figure error
%                 on every surface, Monte Carlo of the lost power vs distance; C alignment error
%                 of the two parts of element 1, lost power vs the error, lambda/4 spec marked)
%
%   Export routes are the original scripts' (print -dpdf -r0 / -dsvg and
%   exportgraphics 600 dpi for the StochasticRayTrace panels; exportgraphics
%   vector + 600 dpi for the Tracing3D panels). Fig 3 is exported with
%   exportgraphics (vector PDF + 600 dpi PNG): the original print -dpdf put the
%   26-cm-wide figure on a letter page and cut its left edge off.
%   Existing files are overwritten.

    tStart = tic;
    out_dir = SIM.out_dir;
    if ~is_absolute(out_dir), out_dir = fullfile(projRoot, out_dir); end
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    C = SIM.common;
    files = {};
    fprintf('=== NA2 paper mode (paper figures, manual parameters, no config) ===\noutput: %s\n', out_dir);

    % ---------------------------------------------------------------- Fig 1A / 1B
    lens1 = [];                                   % Fig 1A/1B lens, reused by Fig 3C
    if SIM.fig1AB.enable
        P = SIM.fig1AB;
        fprintf('--- Fig 1A/1B: n2 = %.4g, %d surfaces, %d drawn rays ---\n', P.n2, P.layers, P.drawn_rays);
        lens = sim_build_lens(P, C);  lens1 = lens;
        F = sim_fig_raytrace(lens, P.drawn_rays, {'regular', 'zoom'}, P.zoom_half, C);
        files = [files, export_raytrace(F.zoom,    fullfile(out_dir, 'fig1A_zoom'))];
        files = [files, export_raytrace(F.regular, fullfile(out_dir, 'fig1B_raytrace'))];
    end

    % ---------------------------------------------------------------- Fig 1E / 1F
    if SIM.fig1EF.enable
        P = SIM.fig1EF;
        fprintf('--- Fig 1E/1F: n2 = %.4g, %d surfaces, rays at [%s] deg ---\n', P.n2, P.layers, num2str(P.ray_angles));
        lens = sim_build_lens(P, C);
        F = sim_fig_tracing3d(lens, P);
        files = [files, export_tracing3d(F.rays2d, fullfile(out_dir, 'fig1E_rays2d'), true)];
        files = [files, export_tracing3d(F.rays3d, fullfile(out_dir, 'fig1F_rays3d'), false)];
    end

    % ---------------------------------------------------------------- Fig 2C
    if SIM.fig2C.enable
        P = SIM.fig2C;
        fprintf('--- Fig 2C: n2 = %.4g, %d surfaces ---\n', P.n2, P.layers);
        lens = sim_build_lens(P, C);
        views = {'regular'};  if P.zoom, views{end+1} = 'zoom'; end
        F = sim_fig_raytrace(lens, P.drawn_rays, views, P.zoom_half, C, ...
                             struct('ray_angles', P.ray_angles, 'zoom_elements', P.zoom_elements));
        files = [files, export_raytrace(F.regular, fullfile(out_dir, 'fig2C_simulation'))];
        if P.zoom, files = [files, export_raytrace(F.zoom, fullfile(out_dir, 'fig2C_zoom'))]; end
    end

    % ---------------------------------------------------------------- Fig 3B / 3C
    if SIM.fig3BC.enable
        fprintf('--- Fig 3B/3C: collection efficiency vs %s + theta_0 (Fig 1A/1B lens), targets [%s] ---\n', SIM.fig3BC.x_axis, num2str(SIM.fig3BC.targets));
        if isempty(lens1), lens1 = sim_build_lens(SIM.fig1AB, C); end
        f3 = sim_fig_collection(lens1, SIM.fig3BC.targets, true,  SIM.fig3BC.x_axis);
        files = [files, export_vector(f3, fullfile(out_dir, 'fig3BC_collection'))];
        f3 = sim_fig_collection(lens1, SIM.fig3BC.targets, false, SIM.fig3BC.x_axis);
        files = [files, export_vector(f3, fullfile(out_dir, 'fig3BC_collection_nolabels'))];
    end

    % ---------------------------------------------------------------- Fig S: tolerances
    if isfield(SIM, 'tol') && SIM.tol.enable
        P = SIM.tol;
        fprintf('--- Tolerances: n2 = %.4g, %d surfaces, lambda/%g figure, lambda/%g alignment ---\n', ...
                P.n2, P.layers, 1 / P.surface_pv_waves, 1 / P.align_waves);
        lensT = sim_build_lens(P, C);
        R = sim_tolerance(lensT, P);
        for with_labels = [true false]                % one figure per panel, labelled / with no text at all
            FS = sim_fig_tolerance(lensT, R, P, with_labels);
            sfx = '';  if ~with_labels, sfx = '_nolabels'; end
            for pn = 'ABC'
                files = [files, export_vector(FS.(pn), fullfile(out_dir, ['figS_' pn sfx]))];
            end
        end
        files = [files, {write_tolerance_csv(R, fullfile(out_dir, 'tolerance_results.csv'))}];
    end

    fprintf('--- %d file(s) written to %s (%.1f s) ---\n', numel(files), out_dir, toc(tStart));
    for k = 1:numel(files), fprintf('  %s\n', files{k}); end
end

% ---------------------------------------------------------------------------
function f = export_raytrace(fig, base)
% StochasticRayTrace.m export block: PDF (print -r0), 600-dpi PNG, SVG (painters).
    print(fig, [base '.pdf'], '-dpdf', '-r0');
    exportgraphics(fig, [base '_600dpi.png'], 'Resolution', 600);
    print(fig, [base '.svg'], '-dsvg');
    f = {[base '.pdf'], [base '_600dpi.png'], [base '.svg']};
end

% ---------------------------------------------------------------------------
function f = export_tracing3d(fig, base, with_emf)
% Tracing3D.m export block: vector PDF (+ EMF for the 2-D panel), 600-dpi PNG.
    exportgraphics(fig, [base '.pdf'], 'ContentType', 'vector', 'BackgroundColor', 'white');
    f = {[base '.pdf']};
    if with_emf
        if ispc
            exportgraphics(fig, [base '.emf'], 'ContentType', 'vector', 'BackgroundColor', 'white');
            f{end+1} = [base '.emf'];
        else
            fprintf('  (EMF skipped: Windows only)\n');
        end
    end
    exportgraphics(fig, [base '_600dpi.png'], 'Resolution', 600, 'BackgroundColor', 'white');
    f{end+1} = [base '_600dpi.png'];
end

% ---------------------------------------------------------------------------
function f = export_vector(fig, base)
% Fig 3: whole figure as vector PDF + 600-dpi PNG.
    exportgraphics(fig, [base '.pdf'], 'ContentType', 'vector', 'BackgroundColor', 'white');
    exportgraphics(fig, [base '_600dpi.png'], 'Resolution', 600, 'BackgroundColor', 'white');
    f = {[base '.pdf'], [base '_600dpi.png']};
end

% ---------------------------------------------------------------------------
function f = write_tolerance_csv(R, f)
% one row per case and observation distance: deflection = exit-angle change [urad, rms over the
% weighted rays]; blur = rms ray displacement [um]; lost = power outside the design envelope [%]
    fid = fopen(f, 'w');
    fprintf(fid, 'case,corr_len_mm,align_waves,distance_m,slope_rms_mrad,deflection_rms_urad,deflection_rms_max_urad,blur_mean_um,blur_max_um,lost_mean_pct,lost_max_pct\n');
    A = R.align_only;
    for id = 1:numel(R.distances_m)
        fprintf(fid, 'alignment_spec,,%g,%g,,%.2f,%.2f,%.2f,%.2f,%.4g,%.4g\n', R.align_mm / R.lambda_mm, R.distances_m(id), A.dth_rms * 1e6, ...
                A.dth_rms * 1e6, A.blur(id) * 1e3, A.blur(id) * 1e3, A.loss(id) * 100, A.loss(id) * 100);
    end
    if isfield(R, 'align_sweep')
        for k = 1:numel(R.align_sweep.waves)
            fprintf(fid, 'alignment_sweep,,%.4g,%g,,,,,,%.4g,%.4g\n', R.align_sweep.waves(k), R.distances_m(end), ...
                    R.align_sweep.loss(k, end) * 100, R.align_sweep.loss(k, end) * 100);
        end
    end
    for ic = 1:numel(R.mc)
        m = R.mc(ic);
        for id = 1:numel(R.distances_m)
            fprintf(fid, 'figure_error,%g,,%g,%.3f,%.1f,%.1f,%.1f,%.1f,%.4g,%.4g\n', m.corr_len_mm, R.distances_m(id), ...
                    m.slope_rms_mrad, m.dth_rms_mean * 1e6, m.dth_rms_max * 1e6, m.blur_mean_mm(id) * 1e3, m.blur_max_mm(id) * 1e3, ...
                    m.loss_mean(id) * 100, m.loss_max(id) * 100);
        end
    end
    fclose(fid);
end

% ---------------------------------------------------------------------------
function tf = is_absolute(p)
    p = strrep(p, '\', '/');
    tf = ~isempty(regexp(p, '^([A-Za-z]:/|//|/)', 'once'));
end
