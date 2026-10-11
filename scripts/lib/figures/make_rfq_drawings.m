function make_rfq_drawings(lens, M, cfg, out, dmeta, which)
%MAKE_RFQ_DRAWINGS  Vendor drawings of LensConstructionGradual (unchanged drawing code, new folder).
%
%   make_rfq_drawings(lens, M, cfg, out, dmeta, which)
%     which  'all' (default) | 'pictures' = the views of the RESULT every run gets, PASS or FAIL
%            (3-D dome preview, whole-lens overview) | 'vendor' = the dimensioned element
%            drawings that go to a vendor and are withheld on FAIL (cross-section, cut pieces)
%
%   figures.rfq.surfaces_3d   3D dome preview of every surface (+ PNG)
%   figures.rfq.cross_section dimensioned cross-section of each listed element (PDF + PNG)
%   figures.rfq.cut_pieces    per listed element (needs process.cut.enable): the cut-pieces sheet
%                             element<k>_cut_pieces (PDF + PNG: piece A, piece B, assembled + per-piece 3-D),
%                             each panel also on its own (_pieceA, _pieceB, _assembled, _pieceA_3D, _pieceB_3D)
%                             and the 3-D split view element<k>_split_3D (PNG)
%   figures.rfq.overview      whole-lens overview with one diameter per element (PNG + SVG)
%   Drawings use the manufacturing profile M.final_lens (identical to the design
%   unless truncation / fillet are on) and the physical scale lens.mm_per_du.
%   Per-element materials (design.element_materials -> lens.material.elements): each
%   element's drawings carry its own glass label and the overview ticks name the
%   material; without them dmeta.glass (the default material) is used as before.
%   Prescribed spheres and draft clamps (M.surfaces) are annotated in the cross-section.

    F = cfg.figures.rfq;
    FL = M.final_lens;  mm = lens.mm_per_du;  L = lens.L;
    els = cfg.run.elements(:).';
    x0s = cfg.process.cut.x0_mm(:).';
    if numel(x0s) == 1, x0s = repmat(x0s, size(els)); end
    surfaces = [];  if isfield(M, 'surfaces'), surfaces = M.surfaces; end
    [labels, glass] = element_labels(lens);      % both {} unless the lens has per-element materials
    if nargin < 6 || isempty(which), which = 'all'; end
    do_pictures = any(strcmp(which, {'all', 'pictures'}));
    do_vendor   = any(strcmp(which, {'all', 'vendor'}));

    if do_pictures && F.surfaces_3d
        plot_lens_3d_surfaces(FL, L, F.n_theta, F.surface_float_mm);
        try
            exportgraphics(gcf, fullfile(out.drawings, 'lens_surfaces_3d.png'), 'Resolution', F.png_dpi);
        catch
            print(gcf, fullfile(out.drawings, 'lens_surfaces_3d.png'), '-dpng', sprintf('-r%d', F.png_dpi));
        end
    end
    for k = 1:numel(els) * double(do_vendor)
        el = els(k);
        cut = struct('enable', cfg.process.cut.enable, 'x0', x0s(k), 'angle_deg', cfg.process.cut.angle_deg);
        dmeta_e = dmeta;                         % this element's own glass label, the default one otherwise
        if el <= numel(glass) && ~isempty(glass{el}), dmeta_e.glass = glass{el}; end
        if F.cross_section
            draw_element_cross_section(FL, el, mm, out.drawings, cut, dmeta_e, surfaces);
        end
        if cut.enable && F.cut_pieces
            plot_cut_pieces_3d(FL, el, mm, cut, dmeta_e, out.drawings);        % split view
            draw_element_cut_pieces(FL, el, mm, out.drawings, cut, dmeta_e);   % the two pieces, each on its own panel
        end
    end
    if do_pictures && F.overview
        draw_lens_overview(FL, L, mm, out.drawings, dmeta, labels);
    end
end

% ---------------------------------------------------------------------------
function [labels, glass] = element_labels(lens)
%ELEMENT_LABELS  Overview tick text ('PMMA n=1.489') and drawing glass label per element.
%   Both come from lens.material.elements (name, n, label). A lens without
%   per-element materials (legacy lens.mat, single material: lens.material is the
%   flat catalog struct or empty) gives two empty cells, i.e. today's drawings.
    labels = {};  glass = {};
    if ~isfield(lens, 'material') || ~isstruct(lens.material) || ~isfield(lens.material, 'elements'), return; end
    E = lens.material.elements;
    if ~isstruct(E) || isempty(E), return; end
    labels = cell(1, numel(E));  glass = cell(1, numel(E));
    for e = 1:numel(E)
        nm = '';   if isfield(E, 'name')  && ischar(E(e).name),  nm = strtrim(E(e).name); end
        lab = '';  if isfield(E, 'label') && ischar(E(e).label), lab = E(e).label; end
        if isfield(E, 'n') && isnumeric(E(e).n) && isscalar(E(e).n)
            % short form for the tick: name + index (an 'as written' index has no name)
            if isempty(nm), labels{e} = sprintf('n=%.4g', E(e).n);
            else,           labels{e} = sprintf('%s n=%.4g', nm, E(e).n); end
        else
            labels{e} = lab;
        end
        glass{e} = lab;
    end
end
