function files = export_step(M, elements, scale, out_dir, opts)
%EXPORT_STEP  Solid of revolution of each listed element as STEP (via scripts/tools/make_step.py).
%
%   files = export_step(M, elements, scale, out_dir, opts)
%
%   M         apply_process output (manufacturing profile, design units)
%   elements  element numbers (cfg.run.elements)
%   scale     mm per design unit (1 for export.units = 'du')
%   out_dir   folder for the STEP files (geometry/step)
%   opts      .python  interpreter with cadquery installed (cfg.export.step_python)
%             .cut     [] or one cut position per element (mm, axis-normal plane) -> also
%                      writes the front/back pieces (cfg.export.step_pieces + process.cut)
%             .stl     also write an STL tessellation
%             .rev     revision string for the check file
%
%   MATLAB writes only the meridional outline, element<k>_profile.csv:
%       segment,x_mm,r_mm   with segments S1 [S1_FILLET] CAP [S2_FILLET] S2
%   (x = optical axis, focus at 0; the same closed upper-half crescent the drawings and
%   the XT / DXF exporters use, after tip truncation and fillet). make_step.py fits an
%   interpolating B-spline through each surface's points (radial tangent on the axis,
%   G1 across the fillet), revolves the closed profile about the axis and writes
%   element<k>.step (AP214, mm, optical axis = +Z) plus element<k>_step_check.txt
%   (valid closed solid, volume vs. Pappus on the polyline, envelope, spline-vs-polyline
%   deviation, re-import, STL watertightness) and element<k>_step_preview.png (section of
%   the solid over the profile points + cut-away). No CAD kernel is needed in MATLAB.
%
%   A missing Python / cadquery is reported loudly but does not fail the run: the STEP
%   is an extra on top of the tables and drawings.

    files = {};
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    here = fileparts(mfilename('fullpath'));                     % scripts/lib/export
    script = fullfile(here, '..', '..', 'tools', 'make_step.py');
    if ~exist(script, 'file')
        fprintf(2, '*** STEP NOT WRITTEN: %s missing.\n', script);  return;
    end
    if nargin < 5, opts = struct(); end
    if ~isfield(opts, 'python') || isempty(opts.python), opts.python = 'python'; end
    if ~isfield(opts, 'cut'),  opts.cut = []; end
    if ~isfield(opts, 'stl'),  opts.stl = true; end
    if ~isfield(opts, 'rev'),  opts.rev = ''; end
    cuts = opts.cut(:).';
    if numel(cuts) == 1, cuts = repmat(cuts, size(elements)); end

    for k = 1:numel(elements)
        el = elements(k);
        if el > numel(M.elements)
            warning('export_step: element %d not available.', el);  continue;
        end
        E = M.elements(el);
        nbi = 0;  nbo = 0;                                       % fillet blend points appended by apply_process
        if isfield(E, 'n_blend_inner'), nbi = E.n_blend_inner; end
        if isfield(E, 'n_blend_outer'), nbo = E.n_blend_outer; end
        inner = E.inner * scale;  outer = E.outer * scale;       % [x r], vertex -> tip (+ blend)
        if E.pointy && ~isempty(E.cap) && size(E.cap, 1) == 3
            tip = E.cap(2, :) * scale;                           % untruncated pointy tip: meet at the tangent intersection
            inner = [inner; tip]; %#ok<AGROW>
        end
        if nbi > 0 && nbo == 0 && norm(inner(end, :) - outer(end, :)) < 1e-9
            nbo = 1;        % fillet at a pointy tip (apply_process>fillet_tip): the blend sits on the
        end                 % inner side and the outer side ends with the blend's last point -> 2-point join
        ni = size(inner, 1) - nbi;  no = size(outer, 1) - nbo;

        csvf = fullfile(out_dir, sprintf('element%d_profile.csv', el));
        fid = fopen(csvf, 'w');
        if fid == -1, fprintf(2, '*** STEP profile not written: cannot open %s\n', csvf); continue; end
        fprintf(fid, 'segment,x_mm,r_mm\n');
        write_rows(fid, 'S1',        inner(1:ni, :));
        if nbi > 0, write_rows(fid, 'S1_FILLET', inner(ni:end, :)); end
        cap = [inner(end, :); outer(end, :)];
        write_rows(fid, 'CAP', cap);                              % zero length at a pointy tip: make_step.py skips it
        if nbo > 0, write_rows(fid, 'S2_FILLET', outer(end:-1:no, :)); end
        write_rows(fid, 'S2',        outer(no:-1:1, :));          % tip -> vertex (closes along the axis)
        fclose(fid);
        files{end+1} = csvf; %#ok<AGROW>

        name = sprintf('element%d', el);
        args = sprintf('"%s" --out "%s" --name %s --check --png', csvf, out_dir, name);
        if ~isempty(cuts) && isfinite(cuts(k)), args = sprintf('%s --cut %.6f', args, cuts(k)); end
        if opts.stl, args = [args ' --stl']; end %#ok<AGROW>
        if ~isempty(opts.rev), args = sprintf('%s --rev "%s"', args, opts.rev); end
        cmd = sprintf('"%s" "%s" %s', opts.python, script, args);
        [status, txt] = system(cmd);
        stepf = fullfile(out_dir, [name '.step']);
        if status == 0 && exist(stepf, 'file')
            files{end+1} = stepf; %#ok<AGROW>
            v = regexp(txt, 'verdict\s+(\w+)', 'tokens', 'once');
            if isempty(v), v = {'?'}; end
            fprintf('STEP: %s written, check %s (see %s_step_check.txt).\n', [name '.step'], v{1}, name);
        elseif status == 2 && exist(stepf, 'file')
            files{end+1} = stepf; %#ok<AGROW>
            fprintf(2, '*** STEP %s written but its self-check FAILED - read %s_step_check.txt before sending it:\n%s\n', ...
                    [name '.step'], name, txt);
        else
            fprintf(2, ['*** STEP NOT WRITTEN for element %d (exit %d).\n' ...
                        '    command: %s\n%s\n' ...
                        '    Needs Python with cadquery: pip install cadquery, then set export.step_python\n' ...
                        '    to that interpreter (full path if it is not on PATH).\n'], el, status, cmd, strtrim(txt));
        end
    end
end

function write_rows(fid, tag, P)
    for i = 1:size(P, 1)
        fprintf(fid, '%s,%.9f,%.9f\n', tag, P(i, 1), P(i, 2));
    end
end
