function dim_line(ax, pA, pB, label, orient, col, sz, fs, varargin)
    plot(ax, [pA(1) pB(1)], [pA(2) pB(2)], '-', 'Color', col, 'LineWidth', 0.7);
    mid = 0.5*(pA + pB);
    if strcmpi(orient, 'h')
        plot(ax, [pA(1) pA(1)], pA(2)+[-sz sz], '-', 'Color', col, 'LineWidth', 0.7);
        plot(ax, [pB(1) pB(1)], pB(2)+[-sz sz], '-', 'Color', col, 'LineWidth', 0.7);
        if pA(2) < 0, va = 'bottom'; yo = 0.8*sz; else, va = 'top'; yo = -0.8*sz; end  % label inward
        text(ax, mid(1), mid(2)+yo, label, 'Color', col, 'FontSize', fs, ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', va);
    else
        plot(ax, pA(1)+[-sz sz], [pA(2) pA(2)], '-', 'Color', col, 'LineWidth', 0.7);
        plot(ax, pB(1)+[-sz sz], [pB(2) pB(2)], '-', 'Color', col, 'LineWidth', 0.7);
        if pA(1) < 0, xo = -0.8*sz; else, xo = 0.8*sz; end
        text(ax, mid(1)+xo, mid(2), label, 'Color', col, 'FontSize', fs, 'Rotation', 90, ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    end
    if numel(varargin) >= 2          % optional extension lines from feature points
        e1 = varargin{1};  e2 = varargin{2};
        plot(ax, [e1(1) pA(1)], [e1(2) pA(2)], ':', 'Color', col, 'LineWidth', 0.5);
        plot(ax, [e2(1) pB(1)], [e2(2) pB(2)], ':', 'Color', col, 'LineWidth', 0.5);
    end
end
