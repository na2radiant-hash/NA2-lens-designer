function files = paper_fig_collection(K, cfg, base, out_dir)
%PAPER_FIG_COLLECTION  Paper Fig 3b: analytic dipole collection-efficiency curve.
%
%   files = paper_fig_collection(K, cfg, base, out_dir)
%
%   K is the analysis/analyze_collection struct - the curve is taken from
%   K.theta0 / K.phi_dip_curve (and the marked half-angles from K.target_theta0_dip
%   when the configured mark point is one of the analysed targets), so the figure
%   and the report can never disagree.
%
%   Ported from na2_fig_collection.m verbatim: the four y-axis modes
%     linear      phi as it is,
%     log         log10 phi with percent tick labels,
%     complement  log(1 - phi) reversed, gridlines at 100 - log_base^k percent,
%     power       1 - (1-phi)^power, a flat-ish top that still spreads the near-100 %,
%   the [ymin ymax] window, the Arial 12 / linewidth 2.5 publication styling, the
%   Okabe-Ito marker colours, and each mark point's drop line + label placed at the
%   visual middle of that line.
%
%   Axis choice, scale, range, log base, power and mark points all come from
%   cfg.figures.paper.collection_plot.

    P = cfg.figures.paper;
    C = P.collection_plot;

    CURVE_LW = 2.5;                     % na2_fig_collection main red curve
    FONT     = 'Arial';
    FONT_SZ  = 12;

    th  = K.theta0(:).';
    phi = K.phi_dip_curve(:).';

    use_NA = strcmpi(C.x_axis, 'NA');
    if use_NA
        m  = th <= 90;
        Xc = sind(th(m));  Yc = phi(m);
        xl = 'NA = sin\theta_0';  xlims = [0 1];  xfun = @(t) sind(t);
    else
        Xc = th;  Yc = phi;
        xl = '\theta_0 (deg)';    xlims = [0 180]; xfun = @(t) t;
    end
    ymin = C.y_range(1);  ymax = C.y_range(2);

    fig = figure('Name', base, 'NumberTitle', 'off', 'Color', 'w', ...
                 'Units', 'centimeters', 'Position', [2 2 P.fig_size_cm(1) P.fig_size_cm(2)]);
    ax = axes('Parent', fig);
    hold(ax, 'on');  grid(ax, 'on');  box(ax, 'on');
    set(ax, 'FontName', FONT, 'FontSize', FONT_SZ);

    switch lower(C.y_scale)
        case 'complement'                       % log of (1-phi), reversed -> expands near 100 %
            if ymax >= 1                        % a top of exactly 100 % is -inf on a log axis
                warning('paper_fig_collection:ymaxClamped', ...
                    'complement mode needs ymax < 1; clamping %.4g -> 0.9999.', ymax);
                ymax = 0.9999;
            end
            plot(ax, Xc, 1-Yc, 'r-', 'LineWidth', CURVE_LW);
            u_top = 1-ymax;  u_bot = 1-ymin;
            set(ax, 'YScale', 'log', 'YDir', 'reverse');  ylim(ax, [u_top u_bot]);
            lbase = 10;
            if isfield(C, 'log_base') && ~isempty(C.log_base), lbase = C.log_base; end
            [ut, ul] = complement_ticks(u_top, u_bot, lbase);
            if numel(ut) <= 2                   % only the endpoints -> the base is too large
                warning('paper_fig_collection:baseTooLarge', ...
                    ['log_base=%g gives NO gridlines between 100%% and %g%% ' ...
                     '(the first would be at %.4g%%). Use a SMALLER base (e.g. 2, 3, e).'], ...
                    lbase, ymin*100, (1-lbase/100)*100);
            end
            set(ax, 'YTick', ut, 'YTickLabel', ul);
            ytf = @(p) 1-p;  yfloor = u_bot;
        case 'power'                            % keep a flat-ish top, still spread near-100 %
            p = 0.5;
            if isfield(C, 'power') && ~isempty(C.power), p = C.power; end
            p = min(max(p, 1e-3), 1);
            g = @(v) 1 - (1-v).^p;              % monotone map, stretched near 100 %
            plot(ax, Xc, g(Yc), 'r-', 'LineWidth', CURVE_LW);
            ylim(ax, [g(ymin) g(ymax)]);
            te = [50 60 70 80 90 95 98 99 99.5 99.9 100]/100;      % round efficiency ticks...
            te = te(te >= ymin-1e-9 & te <= ymax+1e-9);            % ...inside the range
            set(ax, 'YTick', g(te), 'YTickLabel', ...
                arrayfun(@(v) sprintf('%g%%', v*100), te, 'UniformOutput', false));
            ytf = g;  yfloor = g(ymin);
        case 'log'
            plot(ax, Xc, Yc, 'r-', 'LineWidth', CURVE_LW);  set(ax, 'YScale', 'log');
            ylim(ax, [ymin ymax]);  ytf = @(p) p;  yfloor = ymin;
            percent_yticks(ax);
        otherwise                               % linear
            plot(ax, Xc, Yc, 'r-', 'LineWidth', CURVE_LW);
            ylim(ax, [ymin ymax]);  ytf = @(p) p;  yfloor = ymin;
            percent_yticks(ax);
    end
    xlim(ax, xlims);  xlabel(ax, xl);  ylabel(ax, 'Light collection efficiency');

    % --- marked targets -------------------------------------------------------
    cols = {[0.90 0.50 0], [0 0.45 0.70], [0 0.60 0.50], [0.50 0 0.55]};
    mth  = th(th <= 90);  mphi = phi(th <= 90);
    for k = 1:numel(C.mark_points)
        pv = C.mark_points(k);
        th_k = target_half_angle(K, pv, mth, mphi);
        if isnan(th_k), continue; end
        xk = xfun(th_k);  yk = ytf(pv);  c = cols{min(k, numel(cols))};
        plot(ax, [xk xk], [yk yfloor], '--', 'Color', c, 'LineWidth', 1.0);      % drop line
        plot(ax, xk, yk, 'o', 'Color', c, 'MarkerFaceColor', c, 'MarkerSize', 10);
        % label at the VISUAL middle of the drop line (geometric mean on a log axis)
        if strcmp(get(ax, 'YScale'), 'log')
            y_lbl = sqrt(yk*yfloor);
        else
            y_lbl = (yk + yfloor)/2;
        end
        text(ax, xk, y_lbl, sprintf('  %.3g%%', pv*100), 'Color', c, ...
             'FontWeight', 'bold', 'FontName', FONT, 'VerticalAlignment', 'middle');
    end

    drawnow;
    files = save_fig(fig, base, out_dir, P.formats, P.png_dpi, true);
end

% ---------------------------------------------------------------------------
function th_k = target_half_angle(K, pv, mth, mphi)
%TARGET_HALF_ANGLE  Half-angle at efficiency pv: the analysed value when the mark
%   point is one of K.targets, otherwise interpolated on K's own dipole curve
%   (phi decreases monotonically from 1, so the axes are flipped for interp1).
    th_k = NaN;
    if isfield(K, 'targets') && ~isempty(K.targets) && isfield(K, 'target_theta0_dip')
        hit = find(abs(K.targets(:).' - pv) <= 1e-12 * max(1, abs(pv)), 1);
        if ~isempty(hit) && hit <= numel(K.target_theta0_dip)
            th_k = K.target_theta0_dip(hit);
            if ~isnan(th_k), return; end
        end
    end
    th_k = interp1(fliplr(mphi), fliplr(mth), pv, 'linear', NaN);
end

% ---------------------------------------------------------------------------
function percent_yticks(ax)
%PERCENT_YTICKS  Relabel the current y-ticks as percentages (0.99 -> "99%").
    yt = get(ax, 'YTick');
    set(ax, 'YTickLabel', arrayfun(@(v) sprintf('%g%%', v*100), yt, 'UniformOutput', false));
end

% ---------------------------------------------------------------------------
function [ut, ul] = complement_ticks(u_top, u_bot, base)
%COMPLEMENT_TICKS  Gridlines at efficiency = 100 - base^k percent (k = 1, 2, 3, ...),
%   i.e. equally spaced on the log(1-phi) axis, plus the two frame endpoints.
%     base = 2, range [50,100]% -> 100, 98, 96, 92, 84, 68, 50
%     base = e                  -> 100, 97.28, 92.61, 79.91, 50
    if nargin < 3 || isempty(base), base = 10; end
    if ~(base > 1), base = 2; end                     % base must be > 1
    if ~(u_top > 0), u_top = u_bot/1e4; end           % guard: a top of exactly 100 % -> finite
    ug = [];  k = 1;
    while k <= 500
        u = base^k / 100;                             % distance below 100 % = base^k percent
        if u >= u_bot*(1-1e-9), break; end            % reached/past the bottom
        if u > u_top*(1+1e-9), ug(end+1) = u; end     %#ok<AGROW>  strictly inside
        k = k + 1;
    end
    ut = unique([u_top, ug, u_bot]);
    ul = arrayfun(@(v) fmt_eff(v, u_top), ut, 'UniformOutput', false);
end

% ---------------------------------------------------------------------------
function s = fmt_eff(u, u_top)
%FMT_EFF  Efficiency label; the very top (>= 99.99 %) is shown as a clean "100%".
%   (round(e, 4) of the source is written out so it also runs on Octave.)
    e = (1 - u) * 100;
    if u <= u_top*(1+1e-9) && e >= 99.99
        s = '100%';
    else
        s = sprintf('%g%%', round(e * 1e4) / 1e4);
    end
end
