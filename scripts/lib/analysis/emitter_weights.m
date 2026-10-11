function [w, total, p] = emitter_weights(alphas_deg, emitter)
%EMITTER_WEIGHTS  3-D solid-angle weights of meridional rays for a given emitter pattern.
%
%   [w, total, p] = emitter_weights(alphas_deg, emitter)
%
%   A meridional ray at polar angle alpha stands for the whole ring of directions
%   at that angle, so its solid-angle element is sin(alpha) d(alpha) d(phi). The
%   emitter pattern p(alpha) multiplies it:
%     isotropic          p = 1              total = int_0^pi p sin = 2
%     dipole, axis 'x'   p = sin^2(alpha)   total = 4/3     (dipole along the optical axis)
%     dipole, axis 'y'   p = cos^2(alpha)   total = 2/3     (transverse dipole, meridional slice -
%                                                            the legacy StochasticRayTrace DIPOLE_AXIS 'y')
%   w = p .* sin(alpha) (per-ray weight, without the d(alpha) step); total is the
%   analytic integral over the full sphere so that a fraction of EMITTED power is
%   sum(w .* d_alpha) / total.
%   Rays are sampled uniformly in angle everywhere in this code base, so the
%   pattern is applied exactly once - here.

    a = deg2rad(alphas_deg(:));
    switch lower(emitter.type)
        case 'isotropic'
            p = ones(size(a));           total = 2;
        case 'dipole'
            if isfield(emitter, 'dipole_axis') && strcmpi(emitter.dipole_axis, 'y')
                p = cos(a).^2;           total = 2/3;
            else
                p = sin(a).^2;           total = 4/3;
            end
        otherwise
            error('emitter_weights:type', 'Unknown emitter type "%s"', emitter.type);
    end
    w = p .* sin(a);
end
