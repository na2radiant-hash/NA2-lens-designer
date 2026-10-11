function [alpha_next, theta_in, theta_out, gamma, n_fallback, unphysical] = layer_angles(W, j, alpha_j, nij, carry)
%LAYER_ANGLES  Snell solve of ONE surface for every design ray: planned bend + carried shortfall.
%
%   [alpha_next, theta_in, theta_out, gamma, n_fallback, unphysical] = layer_angles(W, j, alpha_j, nij, carry)
%     W        bend_weights output
%     j        surface index (weights column)
%     alpha_j  [R x 1] global ray angles arriving at surface j (deg)
%     nij      [n_in n_out] of surface j
%     carry    [R x 1] extra bend this surface must deliver for earlier prescribed /
%              clamped surfaces ([] or zeros = none); a value of exactly 0 changes nothing
%   Returns the angle after the surface, the local incidence / refraction angles,
%   the tangent angle gamma = phi + 90 the surface needs where ray i crosses it,
%   the number of symbolic solves that fell back to phi = 0, and unphysical(i) =
%   true when the solved "refraction" leaves on the incoming side of the surface
%   (cos(theta_in) and cos(theta_out) of opposite sign), i.e. the surface cannot
%   deliver that bend by refraction.
%
%   This is the inner (i,j) body of the original calculate_angles, unchanged.

    R = numel(alpha_j);
    if nargin < 5 || isempty(carry), carry = zeros(R, 1); end
    n_in = nij(1);  n_out = nij(2);
    alpha_next = zeros(R, 1);  theta_in = zeros(R, 1);  theta_out = zeros(R, 1);  gamma = zeros(R, 1);
    unphysical = false(R, 1);
    n_fallback = 0;

    use_symbolic = strcmpi(W.method, 'symbolic');
    if use_symbolic
        phi_sym = sym('phi_sym');
    end
    for i = 1:R
        % distribute the per-ray total bend with the weights
        delta_alpha = W.total_bend(i) * ( W.wm(i,j) / W.Wsum(i) );
        if carry(i) ~= 0
            delta_alpha = delta_alpha + carry(i);       % shortfall of an earlier sphere / clamp
        end
        a_j    = alpha_j(i);
        a_next = a_j - delta_alpha;

        % Snell in the surface frame: n_in*sin(alpha_j - phi) == n_out*sin(alpha_next - phi)
        if use_symbolic
            f = n_in * sind(a_j - phi_sym) - n_out * sind(a_next - phi_sym);
            phi_guess = 0;
            try
                phi_val = double(vpasolve(f == 0, phi_sym, [-180, 180]));
                if isempty(phi_val); phi_val = phi_guess; n_fallback = n_fallback + 1; end
            catch
                phi_val = phi_guess; n_fallback = n_fallback + 1;
            end
        else
            % closed form: tan(phi) = (n_in sin a - n_out sin b) / (n_in cos a - n_out cos b);
            % of the two roots (phi, phi+180) keep the one with |incidence| <= 90 deg.
            % Both give the same surface line (gamma and gamma+180 are the same tangent).
            phi_val = atan2d(n_in * sind(a_j) - n_out * sind(a_next), ...
                             n_in * cosd(a_j) - n_out * cosd(a_next));
            if abs(wrapTo180(a_j - phi_val)) > 90
                phi_val = wrapTo180(phi_val + 180);
            end
        end

        % Local incidence & refraction relative to the chosen normal
        th_in  = wrapTo180(a_j    - phi_val);
        th_out = wrapTo180(a_next - phi_val);

        theta_in(i)   = th_in;
        theta_out(i)  = th_out;
        gamma(i)      = phi_val + 90;      % surface tangent angle
        alpha_next(i) = a_next;
        % a real refraction crosses the surface: the incoming and outgoing directions have the same
        % sign along the normal. (Root-agnostic: vpasolve may return phi or phi + 180, the same tangent.)
        unphysical(i) = cosd(th_in) * cosd(th_out) < -1e-12;
    end
end
