function S = style_preset(name)
%STYLE_PRESET  Lens / ray colour preset for the paper panels.
%
%   S = style_preset(name)
%
%   name = 'b9e1f0' | 'scientificblue' | 'blue' | 'darkyellow' | 'green'
%          (cfg.figures.style; case-insensitive)
%
%   Fields
%     lensFace, lensAlpha   crescent fill colour / opacity
%     edgeColor, edgeLW     black surface outline
%     gapLW                 white stroke laid UNDER every edge so adjacent shells
%                           stay visually separated (StochasticRayTrace: edgeLW + 3.0)
%     rayColor, rayLW, rayAlpha
%     emitterColor, emitterSize
%     glowColor             pale halo stroke under the edges ([] = no glow)
%     tintColor, tintAlpha  extra translucent wash over each crescent ([] = none)
%
%   Every value is copied from StochasticRayTrace.m:
%     - the per-figure style block ("Per-figure lens and ray style", is_sci / is_b9),
%     - the ray palette (colors.blue / darkyellow / scientificblue / b9e1f0),
%     - the legacy defaults of the RAY_EMPHASIS_MODE = false branch (the 'green' style),
%     - EMITTER_COLOR (#E7633D) and the MarkerSize 5 of the "Draw Source" block,
%     - gapLW = cur_edgelw + 3.0 and the sci glow / tint patches.
%   Figure2Simulation.m's "Fig-1B style constants" block repeats the 'b9e1f0' values
%   (FILL_COL, EDGE_LW, GAP_LW, RAY_COL, RAY_LW, RAY_ALPHA) and agrees with them.
%
%   DEVIATION: StochasticRayTrace has no green RAY colour - 'green' names the legacy
%   LENS style only (lensFace [0.68 0.92 0.68]), and the legacy scripts paired it with
%   the first entry of their ray palette. 'green' therefore reuses colors.blue
%   ([0.15 0.35 0.75], GenerateAllVersions.m ray_colors{1}); nothing else is invented.

    if nargin < 1 || isempty(name), name = 'b9e1f0'; end
    if ~(ischar(name) || (exist('isstring', 'builtin') && isstring(name)))
        error('style_preset:name', 'The style name must be a character string.');
    end
    key = lower(strtrim(char(name)));

    % --- shared constants (StochasticRayTrace) --------------------------------
    EMITTER_COLOR = [231 99 61] / 255;   % #E7633D, the Fig-3 emitter hex
    EMITTER_SIZE  = 5;                   % "Draw Source" MarkerSize
    GAP_LW_EXTRA  = 3.0;                 % gapLW = edgeLW + 3.0
    RAY_ALPHA     = 0.75;                % plot(..., 'Color', [col_r, 0.75], ...)

    % --- legacy (non-sci, non-b9) lens style: RAY_EMPHASIS_MODE = false branch -
    LEGACY_FACE  = [0.68 0.92 0.68];
    LEGACY_ALPHA = 0.45;
    LEGACY_EDGE  = [0 0 0];
    LEGACY_EDGELW = 1.5;
    LEGACY_RAYLW  = 0.65;

    switch key
        case 'b9e1f0'                              % is_b9 branch + colors.b9e1f0
            S.lensFace  = [185/255, 225/255, 240/255];   % #b9e1f0
            S.lensAlpha = 1.0;
            S.edgeColor = [0 0 0];
            S.edgeLW    = 1.2;
            S.rayColor  = [0.08 0.20 0.50];              % dark navy
            S.rayLW     = 0.80;
            S.glowColor = [];                            % "no glow (clean SVG)"
            S.tintColor = [];
            S.tintAlpha = 0;

        case 'scientificblue'                      % is_sci branch + colors.scientificblue
            S.lensFace  = [0.72 0.88 0.94];              % light cyan-blue
            S.lensAlpha = 0.72;
            S.edgeColor = [0 0 0];                       % is_sci -> ec = [0 0 0]
            S.edgeLW    = 1.0;
            S.rayColor  = [0.08 0.28 0.62];              % deep blue
            S.rayLW     = 0.70;
            S.glowColor = [0.86 0.94 0.97];              % pale cyan glow
            S.tintColor = [0.52 0.78 0.91];              % second patch over each shell
            S.tintAlpha = 0.25;

        case 'blue'                                % legacy lens + colors.blue
            S.lensFace  = LEGACY_FACE;
            S.lensAlpha = LEGACY_ALPHA;
            S.edgeColor = LEGACY_EDGE;
            S.edgeLW    = LEGACY_EDGELW;
            S.rayColor  = [0.15 0.35 0.75];
            S.rayLW     = LEGACY_RAYLW;
            S.glowColor = [];
            S.tintColor = [];
            S.tintAlpha = 0;

        case 'darkyellow'                          % legacy lens + colors.darkyellow
            S.lensFace  = LEGACY_FACE;
            S.lensAlpha = LEGACY_ALPHA;
            S.edgeColor = LEGACY_EDGE;
            S.edgeLW    = LEGACY_EDGELW;
            S.rayColor  = [0.75 0.55 0.00];
            S.rayLW     = LEGACY_RAYLW;
            S.glowColor = [];
            S.tintColor = [];
            S.tintAlpha = 0;

        case 'green'                               % the legacy default (see DEVIATION above)
            S.lensFace  = LEGACY_FACE;
            S.lensAlpha = LEGACY_ALPHA;
            S.edgeColor = LEGACY_EDGE;
            S.edgeLW    = LEGACY_EDGELW;
            S.rayColor  = [0.15 0.35 0.75];
            S.rayLW     = LEGACY_RAYLW;
            S.glowColor = [];
            S.tintColor = [];
            S.tintAlpha = 0;

        otherwise
            error('style_preset:unknown', ...
                  'Unknown style "%s". Use b9e1f0 | scientificblue | blue | darkyellow | green.', key);
    end

    S.gapLW        = S.edgeLW + GAP_LW_EXTRA;
    S.rayAlpha     = RAY_ALPHA;
    S.emitterColor = EMITTER_COLOR;
    S.emitterSize  = EMITTER_SIZE;
    S.name         = key;
end
