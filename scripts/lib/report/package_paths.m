function P = package_paths(cfg, projRoot)
%PACKAGE_PATHS  Where a run's package goes (nothing is created here).
%
%   P = package_paths(cfg, projRoot)
%   P.root, P.vendor_dir, P.design_dir, P.design_tag, P.revlabel, P.revtag, P.date, P.pkgname
%   Layout: <output_root>/<run.vendor>/<run.material>_n<design.n_lens>/<RevX_yyyy-mm-dd>
%   (values after resolve_material: with a catalog glass and run.material = null the second
%    folder reads e.g. SCHOTT_N-LASF9_637nm_n1.844)

    root = cfg.run.output_root;
    if ~is_absolute(root), root = fullfile(projRoot, root); end
    try
        root = char(java.io.File(root).getCanonicalPath());   % normalise ../ and separators
    catch
        % no JVM: keep the path as given
    end
    P.root       = root;
    P.revlabel   = regexprep(strtrim(cfg.run.rev), '^[Rr][Ee][Vv]\s*', '');   % 'Rev B' or 'B' -> 'B'
    P.revtag     = ['Rev' regexprep(P.revlabel, '[^A-Za-z0-9]', '')];         % -> 'RevB'
    P.date       = datestr(now, 'yyyy-mm-dd');
    P.pkgname    = [P.revtag '_' P.date];
    P.design_tag = sprintf('%s_n%.4g', strtrim(cfg.run.material), cfg.design.n_lens);   % e.g. N-LASF9_n1.85
    P.vendor_dir = fullfile(root, strtrim(cfg.run.vendor));
    P.design_dir = fullfile(P.vendor_dir, P.design_tag);
end

function tf = is_absolute(p)
    p = strrep(p, '\\', '/');
    tf = ~isempty(regexp(p, '^([A-Za-z]:/|//|/)', 'once'));
end
