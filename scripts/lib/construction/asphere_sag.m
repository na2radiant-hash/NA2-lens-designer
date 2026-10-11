function [z, dzdr] = asphere_sag(r, R, k, coef)
%ASPHERE_SAG  Even-asphere sag z(r) and slope dz/dr, in the convention of the scripts.
%
%   [z, dzdr] = asphere_sag(r, R, k, coef)
%
%   r     radial height from the optical axis, r >= 0 (pass abs(y)); any array shape
%   R     vertex radius of curvature, c = 1/R. Inf (or 0) = flat -> polynomial only
%   k     conic constant (0 sphere, -1 paraboloid)
%   coef  struct with any of the fields D E F G H J L M (missing fields = 0);
%         a scalar 0 or [] is accepted as "no polynomial"
%
%   SAG EQUATION - copied from LensConstructionGradual_3Elem.m, function
%   generate_commercial_lens (lines 1110-1114), which is the same formula as
%   AsphericalLensIntegration.m / asph_sag (lines 153-166):
%
%       Y2 = r.^2
%       z  = c*Y2 ./ (1 + sqrt(max(0, 1 - (1+k)*c^2*Y2)))
%            + D*Y2 + E*Y2.^2 + F*Y2.^3 + G*Y2.^4
%            + H*Y2.^5 + J*Y2.^6 + L*Y2.^7 + M*Y2.^8
%
%   so the polynomial orders are  D->r^2, E->r^4, F->r^6, G->r^8, H->r^10,
%   J->r^12, L->r^14, M->r^16.  This is the script's ordering and it is what the
%   Edmund coefficient values in asphere_catalog are consistent with (at the
%   O128 mm clear aperture of DWG 22722 the terms are 1.04, 0.054, -0.015,
%   -0.011, +0.0011 mm - a converging series only under this ordering).
%
%   SIGN CONVENTION (identical in both scripts)
%     z is the displacement of the surface from its VERTEX measured toward +x,
%     as a function of the height r. R > 0 therefore puts the centre of curvature
%     at +x: the surface is concave toward +x and convex toward -x, and z >= 0.
%     A caller places a face as
%         front face (light arrives from -x):  x(r) = x_vertex + z(r)
%         rear  face (light leaves toward +x): x(r) = x_vertex - z(r)
%     which is exactly what generate_commercial_lens does (script lines 1118-1126):
%     with a positive R the element is thickest on axis in both orientations.
%
%   SLOPE
%       dz/dr = c*r ./ sqrt(max(1e-14, 1 - (1+k)*c^2*r^2))
%               + 2*D*r + 4*E*r^3 + 6*F*r^5 + 8*G*r^7
%               + 10*H*r^9 + 12*J*r^11 + 14*L*r^13 + 16*M*r^15
%     The clamp 1e-14 (instead of the sag's 0) is the scripts' own - see
%     AsphericalLensIntegration.m line 178 and the script's inline eval_dZdy
%     (lines 314-317). NOTE: that inline eval_dZdy drops the D, L and M terms;
%     the version here keeps them, which is identical for every catalog model
%     (D = L = M = 0) and correct for a custom block that sets them. Stage 3 of
%     construct_two_stage still uses the script's own eval_dZdy verbatim so the
%     correction stays bit-identical to the reference run.
%
%   UNITS
%     The formula is scale-free: to work in design units (du) with
%     s = mm_per_du, pass R_du = R_mm / s and scale every coefficient of the
%     r^(2m) term by s^(2m-1):
%        D_du = D*s^1,  E_du = E*s^3,  F_du = F*s^5,  G_du = G*s^7,
%        H_du = H*s^9,  J_du = J*s^11, L_du = L*s^13, M_du = M*s^15
%     (construct_two_stage/asphere_to_du does exactly this.)

    if nargin < 3 || isempty(k), k = 0; end
    if nargin < 4, coef = struct(); end
    c = coefficients(coef);

    r2 = r.^2;

    poly  = c.D*r2 + c.E*r2.^2 + c.F*r2.^3 + c.G*r2.^4 ...
          + c.H*r2.^5 + c.J*r2.^6 + c.L*r2.^7 + c.M*r2.^8;
    dpoly = 2*c.D*r + 4*c.E*r.^3 + 6*c.F*r.^5 + 8*c.G*r.^7 ...
          + 10*c.H*r.^9 + 12*c.J*r.^11 + 14*c.L*r.^13 + 16*c.M*r.^15;

    if isempty(R) || isinf(R) || R == 0
        % flat surface (AsphericalLensIntegration.m lines 158-161 / 173-176)
        z    = poly;
        dzdr = dpoly;
        return;
    end

    cv  = 1/R;
    arg = 1 - (1+k)*cv^2*r2;
    z    = cv*r2 ./ (1 + sqrt(max(arg, 0))) + poly;
    dzdr = cv*r  ./ sqrt(max(arg, 1e-14))   + dpoly;
end

% ------------------------------------------------------------------ helpers
function c = coefficients(coef)
%COEFFICIENTS  Fill the D..M slots, defaulting anything absent to 0.
    names = {'D', 'E', 'F', 'G', 'H', 'J', 'L', 'M'};
    for kk = 1:numel(names), c.(names{kk}) = 0; end
    if isempty(coef), return; end
    if isnumeric(coef)
        if any(coef(:) ~= 0)
            error('asphere_sag:coef', 'coef must be a struct with fields D..M (or 0 / [] for none).');
        end
        return;
    end
    if ~isstruct(coef)
        error('asphere_sag:coef', 'coef must be a struct with fields D..M (or 0 / [] for none).');
    end
    for kk = 1:numel(names)
        if isfield(coef, names{kk}) && ~isempty(coef.(names{kk}))
            c.(names{kk}) = coef.(names{kk});
        end
    end
end
