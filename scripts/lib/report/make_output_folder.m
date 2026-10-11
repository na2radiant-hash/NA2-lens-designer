function out = make_output_folder(cfg, projRoot, config_path, opts)
%MAKE_OUTPUT_FOLDER  Create the package folder and its subfolders.
%
%   out = make_output_folder(cfg, projRoot, config_path)
%
%   Layout:  <output_root>/<run.vendor>/<run.material>_n<design.n_lens>/<RevX_yyyy-mm-dd>/
%            (run.material null + catalog glass -> <MAKER>_<glass>_<wavelength>nm, see resolve_material)
%            e.g.  outputs/packages/Isuzu/PMMA_n1.72/RevA_2026-09-07/
%
%   - run.output_root may be absolute, or relative to projRoot (the NA2 folder).
%   - The package folder is never overwritten: run.on_exists = 'error' refuses
%     to run, 'suffix' appends _2, _3, ...
%   - Copies the config verbatim into the package as config_used.json.
%
%   opts (optional): .parent  absolute folder that receives the package directly
%                           (sweeps put their packages under one sweep folder)
%                    .name    package folder name instead of RevX_yyyy-mm-dd
%
%   out fields: root, vendor_dir, design_dir, pkg, geometry, drawings, analysis, figures,
%               design_tag, pkgname, revlabel, revtag, date

    P = package_paths(cfg, projRoot);
    root = P.root;  revlabel = P.revlabel;  revtag = P.revtag;  datestr_ = P.date;  pkgname = P.pkgname;
    design_tag = P.design_tag;  vendor_dir = P.vendor_dir;  design_dir = P.design_dir;
    if ~exist(root, 'dir'), mkdir(root); end
    if ~exist(vendor_dir, 'dir')
        mkdir(vendor_dir);
        fprintf('New vendor folder created: %s\n', vendor_dir);
    end
    if ~exist(design_dir, 'dir'), mkdir(design_dir); end

    parent = design_dir;
    if nargin >= 4 && ~isempty(opts)
        if isfield(opts, 'parent') && ~isempty(opts.parent), parent = opts.parent; if ~exist(parent, 'dir'), mkdir(parent); end, end
        if isfield(opts, 'name') && ~isempty(opts.name), pkgname = opts.name; end
    end
    pkg = fullfile(parent, pkgname);
    if exist(pkg, 'dir')
        switch cfg.run.on_exists
            case 'error'
                error('make_output_folder:exists', ...
                    ['Package folder already exists:\n  %s\n' ...
                     'A sent package is never overwritten. Bump run.rev, or set run.on_exists = "suffix".'], pkg);
            case 'suffix'
                k = 2;
                while exist(fullfile(parent, sprintf('%s_%d', pkgname, k)), 'dir'), k = k + 1; end
                pkgname = sprintf('%s_%d', pkgname, k);
                pkg = fullfile(parent, pkgname);
        end
    end
    mkdir(pkg);
    mkdir(fullfile(pkg, 'geometry'));
    mkdir(fullfile(pkg, 'drawings'));
    mkdir(fullfile(pkg, 'analysis'));
    mkdir(fullfile(pkg, 'figures'));
    copyfile(config_path, fullfile(pkg, 'config_used.json'));

    out.root       = root;
    out.vendor_dir = vendor_dir;
    out.design_dir = design_dir;
    out.design_tag = design_tag;
    out.pkg        = pkg;
    out.geometry   = fullfile(pkg, 'geometry');
    out.drawings   = fullfile(pkg, 'drawings');
    out.analysis   = fullfile(pkg, 'analysis');
    out.figures    = fullfile(pkg, 'figures');
    out.pkgname    = pkgname;
    out.revlabel   = revlabel;
    out.revtag     = revtag;
    out.date       = datestr_;
end

function tf = is_absolute(p)
    p = strrep(p, '\', '/');
    tf = ~isempty(regexp(p, '^([A-Za-z]:/|//|/)', 'once'));
end
