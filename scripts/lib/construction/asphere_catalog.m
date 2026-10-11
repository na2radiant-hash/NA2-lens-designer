function A = asphere_catalog(model)
%ASPHERE_CATALOG  Datasheet parameters of the commercial aspheres used as Stage 2.
%
%   A = asphere_catalog(model)
%
%   model : 'edmund_22722_150mm' (alias '150mm')
%           'edmund_15003_100mm' (alias '100mm')
%
%   Returns a struct with exactly the fields of design.commercial_asphere.custom
%   plus a human-readable name:
%
%     R_mm             vertex radius of curvature of the ASPHERIC face (mm).
%                      Sign convention as in asphere_sag: R > 0 puts the centre
%                      of curvature at +x, sag grows toward +x from the vertex.
%                      Inf = flat.
%     k                conic constant
%     D E F G H J L M  even polynomial coefficients. NOTE the order convention of
%                      LensConstructionGradual_3Elem.m (function generate_commercial_lens,
%                      lines 1110-1114): with Y2 = r^2 the sag adds
%                          D*Y2 + E*Y2^2 + F*Y2^3 + G*Y2^4 + H*Y2^5 + J*Y2^6 + L*Y2^7 + M*Y2^8
%                      i.e. D->r^2, E->r^4, F->r^6, G->r^8, H->r^10, J->r^12,
%                      L->r^14, M->r^16.  (D = L = M = 0 for both catalog models,
%                      so the r^2 slot is unused; the working coefficients are the
%                      4th..12th order ones E..J.)  See asphere_sag for the exact
%                      formula and for the mm -> design-unit scaling.
%     asphere_on_s2    false: S1 (the face the omni lens sees first) is the asphere
%                             and S2 is flat;
%                      true : S1 is flat and S2 (the exit face) is the asphere.
%     n                glass index at the working wavelength
%     CT_mm            centre thickness (mm)
%     half_aperture_mm clear half aperture (mm)
%     name             catalog description
%
%   Values are copied verbatim from LensConstructionGradual_3Elem.m lines 62-94
%   (the "Commercial aspherical lens (Stage 2)" block). The script stores the
%   vertex CURVATURE C = 1/R for both models; here it is stored as a radius,
%   R_mm = 1/C (the reciprocal round-trip is exact in double precision for both
%   models - verified).
%
%   Unknown models raise an error, as in the script's own switch (line 92).

    if nargin < 1 || isempty(model), error('asphere_catalog:usage', 'A model name is required.'); end
    if ~(ischar(model) || (exist('isstring', 'builtin') && isstring(model)))
        error('asphere_catalog:usage', 'The model must be a character string.');
    end
    model = lower(char(model));

    switch model
        case {'edmund_15003_100mm', '100mm'}
            % Edmund Optics DWG 15003 - O100 mm F/0.8, N-SF5, S1 convex asphere
            % (script lines 70-79)
            A.R_mm             = 1 / 1.858149e-2;   % script: 'C', 1.858149e-2
            A.k                = -0.786;
            A.D                = 0;
            A.E                = 1.65e-7;
            A.F                = 3.22e-12;
            A.G                = -1.03e-15;
            A.H                = -4.03e-19;
            A.J                = 1.99e-23;
            A.L                = 0;
            A.M                = 0;
            A.asphere_on_s2    = false;             % S1 convex asphere, S2 flat
            A.n                = 1.673;
            A.CT_mm            = 31.20;             % centre thickness (mm)
            A.half_aperture_mm = 45;                % O90 mm CA (use 50 for the full O100 body)
            A.name             = 'Edmund Optics DWG 15003, O100 mm F/0.8, N-SF5, S1 convex asphere';

        case {'edmund_22722_150mm', '150mm'}
            % Edmund Optics DWG 22722 - O150 mm NIR, N-SF5, S2 convex asphere
            % (script lines 81-90)
            A.R_mm             = 80.725;            % script: 'C', 1/80.725
            A.k                = -0.843;
            A.D                = 0;
            A.E                = 6.19e-8;
            A.F                = 7.803e-13;
            A.G                = -5.48e-17;
            A.H                = -9.649e-21;
            A.J                = 2.242e-25;
            A.L                = 0;
            A.M                = 0;
            A.asphere_on_s2    = true;              % S1 flat, S2 convex asphere
            A.n                = 1.673;
            A.CT_mm            = 45.40;             % centre thickness (mm)
            A.half_aperture_mm = 64;                % O128 mm CA (use 75 for the full O150 body)
            A.name             = 'Edmund Optics DWG 22722, O150 mm NIR, N-SF5, S2 convex asphere';

        otherwise
            error('asphere_catalog:unknown', ...
                  'Unknown asphere model "%s". Choose ''edmund_22722_150mm'' or ''edmund_15003_100mm'' (or design.commercial_asphere.model = ''custom'').', model);
    end
end
