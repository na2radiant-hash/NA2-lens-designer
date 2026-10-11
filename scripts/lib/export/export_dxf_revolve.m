function dxffile = export_dxf_revolve(final_lens, L, filename, precision)
%EXPORT_DXF_REVOLVE  Revolve profile of every element as a DXF (NA2_v2 na2_export_step, verbatim).
%   final_lens: cell of [x r] polylines in the units you want in the file (mm).
% Export the 2-D REVOLVE PROFILE of the lens as a DXF, for making a parametric
% STEP in CAD:  import the DXF, revolve each closed profile 360 deg about the
% X (optical) axis to get a solid, then File > Save As > STEP.
%
% Each crescent element becomes one closed profile (its upper-half cross-section,
% inner surface + outer surface). A reference AXIS line is included as the
% revolve axis. (This is the agreed 'profile -> CAD -> STEP' route.)
    if nargin < 4 || isempty(precision), precision = 6; end
    [p,n,~] = fileparts(filename);
    if ~isempty(p) && ~exist(p,'dir'), mkdir(p); end
    dxffile = fullfile(p, [n '.dxf']);

    ents = struct('pts',{},'closed',{},'layer',{});
    xall = [];
    for e = 1:floor(L/2)
        li = 2*e-1;  lo = 2*e;
        if lo > L || isempty(final_lens{li}) || isempty(final_lens{lo}), continue; end
        inner = final_lens{li};  outer = final_lens{lo};   % NATIVE order (axis -> rim/tip).
        % Do NOT sort by x or radius: the crescents curve back in BOTH, so any single-
        % coordinate sort self-crosses. The generation order already traces each surface
        % correctly - this is the exact order na2_draw_lens_outline uses for the figures.
        if e == 1
            prof = [inner; flipud(outer)];                 % innermost: blunt rim join
        else
            tip = crescent_tip(inner, outer);              % outer crescents meet at a point
            if any(isnan(tip)), prof = [inner; flipud(outer)];
            else,               prof = [inner; tip; flipud(outer)];  end
        end
        if ~isequal(prof(1,:), prof(end,:)), prof = [prof; prof(1,:)]; end
        ents(end+1) = struct('pts',prof, 'closed',true, 'layer',sprintf('ELEMENT_%d',e)); %#ok<AGROW>
        xall = [xall; prof(:,1)]; %#ok<AGROW>
    end
    if isempty(ents)
        warning('export_dxf_revolve:empty','No lens profile to export.');  return;
    end
    % reference revolve axis (the optical / X axis)
    ents(end+1) = struct('pts',[min(xall)-2, 0; max(xall)+2, 0], 'closed',false, 'layer','AXIS');

    write_dxf(dxffile, ents, precision);
    fprintf(['Wrote revolve profile (DXF, %d elements) -> %s\n' ...
             '   In CAD: import the DXF, revolve each closed ELEMENT profile 360 deg\n' ...
             '   about the AXIS (X) line to make a solid, then Save As STEP.\n'], ...
             numel(ents)-1, dxffile);
end

% ------------------------------------------------------------------------------
function tip = crescent_tip(inner, outer)
% Pointy edge where an outer crescent's two surfaces meet: intersection of the two
% end tangents. Mirrors the closing logic in na2_draw_lens_outline.
    p1 = inner(end,:);  d1 = p1 - inner(end-1,:);
    p2 = outer(end,:);  d2 = p2 - outer(end-1,:);
    A = [d1(1), -d2(1); d1(2), -d2(2)];   % solve p1 + t*d1 = p2 + s*d2
    if abs(det(A)) < 1e-12, tip = [NaN NaN];  return;  end
    ts  = A \ (p2 - p1).';
    tip = p1 + ts(1)*d1;
end
