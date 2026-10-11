function files = make_paper_figures(lens, stack, K, cfg, out_dir)
%MAKE_PAPER_FIGURES  Draw and export every enabled paper panel.
%
%   files = make_paper_figures(lens, stack, K, cfg, out_dir)
%
%   Dispatches cfg.figures.paper.panels to the panel functions and returns every
%   file written:
%     fig1a  paper_fig_crosssection(..., zoom = false)  -> fig1a_crosssection
%     fig1b  paper_fig_crosssection(..., zoom = true )  -> fig1b_crosssection_zoom
%     fig1c  paper_fig_3dbody(..., zoom = false)        -> fig1c_3dbody
%     fig1d  paper_fig_3dbody(..., zoom = true )        -> fig1d_3dbody_zoom
%     fig1e  paper_fig_raytrace (2-D half)              -> fig1e_raytrace2d
%     fig1f  paper_fig_raytrace (3-D half)              -> fig1f_raytrace3d
%     fig3a  paper_fig_schematic                        -> fig3a_schematic
%     fig3b  paper_fig_collection                       -> fig3b_collection
%     fig3c  paper_fig_dipole                           -> fig3c_dipole
%
%   K may be [] (no collection analysis in this run): fig3b is then skipped with a
%   warning. fig1e and fig1f share one paper_fig_raytrace call - the panel whose
%   switch is off gets an empty base name and is not drawn.
%
%   Figures are closed after export when cfg.run.show_figures is false; the panel
%   functions themselves never close anything, so a run with show_figures = true
%   leaves the labeled figures on screen exactly as the original scripts did.

    if nargin < 3, K = []; end
    files = {};
    if ~isfield(cfg, 'figures') || ~isfield(cfg.figures, 'paper')
        warning('make_paper_figures:noConfig', 'cfg.figures.paper is missing - no paper panels drawn.');
        return;
    end
    P   = cfg.figures.paper;
    pan = P.panels;

    show = true;
    if isfield(cfg, 'run') && isfield(cfg.run, 'show_figures') && ~isempty(cfg.run.show_figures)
        show = logical(cfg.run.show_figures);
    end
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    % --- Fig 1a / 1b: cross-section, full and zoomed --------------------------
    if panel_on(pan, 'fig1a')
        fprintf('Fig 1a (cross-section)...\n');
        files = run_panel(files, show, @() paper_fig_crosssection(lens, stack, cfg, 'fig1a_crosssection', out_dir, false));
    end
    if panel_on(pan, 'fig1b')
        fprintf('Fig 1b (cross-section, zoom)...\n');
        files = run_panel(files, show, @() paper_fig_crosssection(lens, stack, cfg, 'fig1b_crosssection_zoom', out_dir, true));
    end

    % --- Fig 1c / 1d: 3-D solid of revolution ---------------------------------
    if panel_on(pan, 'fig1c')
        fprintf('Fig 1c (3-D body)...\n');
        files = run_panel(files, show, @() paper_fig_3dbody(lens, cfg, 'fig1c_3dbody', out_dir, false));
    end
    if panel_on(pan, 'fig1d')
        fprintf('Fig 1d (3-D body, zoom)...\n');
        files = run_panel(files, show, @() paper_fig_3dbody(lens, cfg, 'fig1d_3dbody_zoom', out_dir, true));
    end

    % --- Fig 1e / 1f: ray-trace panels (one call draws both) ------------------
    if panel_on(pan, 'fig1e') || panel_on(pan, 'fig1f')
        b2d = '';  b3d = '';
        if panel_on(pan, 'fig1e'), b2d = 'fig1e_raytrace2d'; end
        if panel_on(pan, 'fig1f'), b3d = 'fig1f_raytrace3d'; end
        fprintf('Fig 1e/1f (ray trace)...\n');
        files = run_panel(files, show, @() paper_fig_raytrace(lens, stack, cfg, b2d, b3d, out_dir));
    end

    % --- Fig 3a: schematic ----------------------------------------------------
    if panel_on(pan, 'fig3a')
        fprintf('Fig 3a (schematic)...\n');
        files = run_panel(files, show, @() paper_fig_schematic(lens, cfg, 'fig3a_schematic', out_dir));
    end

    % --- Fig 3b: collection curve --------------------------------------------
    if panel_on(pan, 'fig3b')
        if isempty(K)
            warning('make_paper_figures:noCollection', ...
                'Fig 3b needs the analyze_collection result (K); none was given - panel skipped.');
        else
            fprintf('Fig 3b (collection efficiency)...\n');
            files = run_panel(files, show, @() paper_fig_collection(K, cfg, 'fig3b_collection', out_dir));
        end
    end

    % --- Fig 3c: dipole panel -------------------------------------------------
    if panel_on(pan, 'fig3c')
        fprintf('Fig 3c (dipole / theta)...\n');
        files = run_panel(files, show, @() paper_fig_dipole(lens, cfg, 'fig3c_dipole', out_dir));
    end

    fprintf('Paper figures: %d file(s) written to %s\n', numel(files), out_dir);
end

% ---------------------------------------------------------------------------
function tf = panel_on(pan, name)
    tf = isfield(pan, name) && ~isempty(pan.(name)) && pan.(name);
end

% ---------------------------------------------------------------------------
function files = run_panel(files, show, fn)
%RUN_PANEL  Call one panel function, collect its files, close what it opened when
%   cfg.run.show_figures is false.
    before = findall(0, 'Type', 'figure');
    new_files = fn();
    if ~isempty(new_files)
        files = [files, reshape(new_files, 1, [])];
    end
    if ~show, close_new_figures(before); end
end

% ---------------------------------------------------------------------------
function close_new_figures(before)
    after = findall(0, 'Type', 'figure');
    for k = 1:numel(after)
        h = after(k);
        is_old = false;
        for m = 1:numel(before)
            if h == before(m), is_old = true; break; end
        end
        if ~is_old && ishandle(h), close(h); end
    end
end
