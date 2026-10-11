function files = save_fig(fig, base, out_dir, formats, dpi, both)
%SAVE_FIG  Export one figure in the requested formats, labeled and label-free.
%
%   files = save_fig(fig, base, out_dir, formats, dpi, both)
%
%   formats  cell array of 'svg' | 'pdf' | 'png' | 'emf' (a single string is fine)
%   dpi      raster resolution of the PNG export
%   both     true  -> <base>_labeled.* AND <base>_nolabels.*
%            false -> <base>.*
%   files    cell array of the full paths actually written.
%
%   Export routes (StochasticRayTrace.m export block / na2_save_fig_both.m):
%     svg  print -dsvg with the painters renderer (true vector, no transparency
%          flattening - the 2026-08-07 fix for the speckled zoom panel)
%     pdf  exportgraphics ContentType 'vector', falling back to print -dpdf -r0
%     png  exportgraphics at `dpi` (never a screen-resolution clipboard bitmap),
%          falling back to print -dpng -r<dpi>
%     emf  exportgraphics ContentType 'vector' (Tracing3D.m .emf exports)
%
%   The label-free copy is na2_save_fig_both.m's: copy the figure, delete every
%   text object, blank the tick labels, hide the legends.
%
%   DEVIATIONS from na2_save_fig_both.m: the formats and the PNG resolution come
%   from the config instead of being fixed at PNG+SVG/200 dpi, and the label-free
%   COPY IS CLOSED after export (na2_save_fig_both deliberately left it on screen).
%   A format that fails to export warns and is skipped rather than aborting the run.

    if nargin < 4 || isempty(formats), formats = {'png'}; end
    if nargin < 5 || isempty(dpi),     dpi = 300;         end
    if nargin < 6 || isempty(both),    both = false;      end
    if ~iscell(formats), formats = {char(formats)}; end
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    set(fig, 'Color', 'w');
    files = {};

    if both, labeled_base = [base '_labeled']; else, labeled_base = base; end
    files = [files, export_formats(fig, labeled_base, out_dir, formats, dpi)];

    if both
        f2 = copy_figure(fig);
        if ~isempty(f2)
            strip_labels(f2, base);
            files = [files, export_formats(f2, [base '_nolabels'], out_dir, formats, dpi)];
            close(f2);
        end
    end
end

% ---------------------------------------------------------------------------
function written = export_formats(fig, name, out_dir, formats, dpi)
    written = {};
    for k = 1:numel(formats)
        fmt = lower(strtrim(char(formats{k})));
        if isempty(fmt), continue; end
        target = fullfile(out_dir, [name '.' fmt]);
        ok = true;
        try
            switch fmt
                case 'svg'
                    set(fig, 'Renderer', 'painters');
                    print(fig, target, '-dsvg');
                case 'pdf'
                    if has_exportgraphics()
                        exportgraphics(fig, target, 'ContentType', 'vector', 'BackgroundColor', 'white');
                    else
                        set(fig, 'Renderer', 'painters');
                        print(fig, target, '-dpdf', '-r0');
                    end
                case 'png'
                    if has_exportgraphics()
                        exportgraphics(fig, target, 'Resolution', dpi, 'BackgroundColor', 'white');
                    else
                        print(fig, target, '-dpng', sprintf('-r%d', round(dpi)));
                    end
                case 'emf'
                    if has_exportgraphics()
                        exportgraphics(fig, target, 'ContentType', 'vector', 'BackgroundColor', 'white');
                    else
                        print(fig, target, '-dmeta');
                    end
                otherwise
                    warning('save_fig:format', 'Unknown figure format "%s" - skipped.', fmt);
                    ok = false;
            end
        catch err
            warning('save_fig:export', 'Could not write %s (%s).', target, err.message);
            ok = false;
        end
        if ok, written{end+1} = target; end %#ok<AGROW>
    end
end

% ---------------------------------------------------------------------------
function tf = has_exportgraphics()
    tf = exist('exportgraphics', 'file') == 2 || exist('exportgraphics', 'builtin') == 5;
end

% ---------------------------------------------------------------------------
function f2 = copy_figure(fig)
    f2 = [];
    try
        f2 = copyobj(fig, groot);
    catch
        try
            f2 = copyobj(fig, 0);
        catch err
            warning('save_fig:copy', 'Could not copy the figure for the label-free export (%s).', err.message);
        end
    end
end

% ---------------------------------------------------------------------------
function strip_labels(f2, base)
%STRIP_LABELS  na2_save_fig_both.m label-free pass, verbatim.
    set(f2, 'Name', [base ' (no labels - for PowerPoint)']);
    delete(findall(f2, 'Type', 'text'));                % titles, annotations, marker labels
    axs = findobj(f2, 'Type', 'axes');
    for k = 1:numel(axs)
        ax = axs(k);
        set(ax, 'XTickLabel', {}, 'YTickLabel', {});
        try, set(ax, 'ZTickLabel', {}); catch, end
        xlabel(ax, '');  ylabel(ax, '');  title(ax, '');
        try, zlabel(ax, ''); catch, end
        try
            lg = get(ax, 'Legend');
            if ~isempty(lg), set(lg, 'Visible', 'off'); end
        catch
        end
    end
    lgs = findobj(f2, 'Type', 'legend');
    for k = 1:numel(lgs), set(lgs(k), 'Visible', 'off'); end
    set(f2, 'Color', 'w');
end
