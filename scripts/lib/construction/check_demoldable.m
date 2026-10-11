function [ok, note, k_bad] = check_demoldable(pts, is_inner, pull, alpha0)
%CHECK_DEMOLDABLE  Can the mold tool that forms this surface leave the part along the axis?
%
%   [ok, note, k_bad] = check_demoldable(pts, is_inner, pull, alpha0)
%     pts       [x r] polyline vertex -> tip (design units)
%     is_inner  true for an odd surface (formed by a core), false for an outer one (cavity block)
%     pull      'back' = the tool leaves toward the emitter (-x) | 'front' = toward +x
%     alpha0    emission angle per design ray (for the note; [] = row numbers only)
%
%   Rule: along the surface from the tip (mouth) inward the radius must never
%   grow, i.e. from the vertex to the tip r is non-decreasing, and the surface must
%   run monotonically toward the tool's exit: a core pulled back or a cavity block
%   pulled front need the tip on the -x side of the vertex (x non-increasing vertex
%   -> tip); the other two combinations need the opposite. The first violating
%   segment is named in note (k_bad = its index, 0 when ok).

    ok = true;  note = '';  k_bad = 0;
    x = pts(:, 1);  r = abs(pts(:, 2));
    dx = diff(x);  dr = diff(r);
    tol = 1e-9;
    if (is_inner && strcmpi(pull, 'back')) || (~is_inner && strcmpi(pull, 'front'))
        sx = -1;
    else
        sx = 1;
    end
    bad_r = find(dr < -tol, 1);
    bad_x = find(sx * dx < -tol, 1);
    k = min([bad_r, bad_x]);
    if isempty(k), return; end
    ok = false;  k_bad = k;
    if nargin >= 4 && ~isempty(alpha0) && k <= numel(alpha0)
        who = sprintf('segment %d (ray %d, %.2f deg emission)', k, k, alpha0(k));
    else
        who = sprintf('segment %d', k);
    end
    if ~isempty(bad_r) && k == bad_r
        note = sprintf('%s: r falls %.4f -> %.4f du toward the tip (undercut against pull %s)', who, r(k), r(k+1), pull);
    else
        note = sprintf('%s: the surface turns back in x (%.4f -> %.4f du) against pull %s', who, x(k), x(k+1), pull);
    end
end
