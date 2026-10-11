function trace = trace_rays(lens, stack, T)
%TRACE_RAYS  Independent validation ray trace through the surface stack.
%
%   trace = trace_rays(lens, stack, T)
%
%   T (from cfg.trace, angles in degrees, lengths in design units):
%     n_rays, sampling ('deterministic' | 'stochastic'), seed, min_angle_deg,
%     max_angle_deg ([] = lens.designed_max_angle, the last design ray), angle_epsilon_deg,
%     segment_overshoot, extend_len (du; ray length past the last surface),
%     smooth_normals (false = constant normal per polyline segment, true = tangent
%     interpolated between the design tangents; omni surfaces only, see first_hit),
%     or T.alphas0 to trace a given list of angles instead of sampling.
%
%   Rays are sampled UNIFORMLY IN ANGLE. Emitter patterns enter later as weights
%   (see emitter_weights), so no pattern is ever counted twice.
%
%   Returns per ray: path (points, du), exit angle, status ('collected' = passed
%   every surface, 'miss' = left the stack, 'tir' = total internal reflection),
%   per-interface incidence angle / indices / surface index, and the number of
%   rays that needed the segment-overshoot allowance.

    n1 = lens.n1;  source = lens.source_pos(:).';
    max_angle = lens.nominal_max_angle;
    if isfield(lens, 'designed_max_angle') && ~isempty(lens.designed_max_angle), max_angle = lens.designed_max_angle; end
    if isfield(T, 'max_angle_deg') && ~isempty(T.max_angle_deg), max_angle = T.max_angle_deg; end
    min_angle = 0;  if isfield(T, 'min_angle_deg') && ~isempty(T.min_angle_deg), min_angle = T.min_angle_deg; end
    eps_ang = 1e-6; if isfield(T, 'angle_epsilon_deg') && ~isempty(T.angle_epsilon_deg), eps_ang = T.angle_epsilon_deg; end
    overshoot = 1e-12; if isfield(T, 'segment_overshoot') && ~isempty(T.segment_overshoot), overshoot = T.segment_overshoot; end
    extend_len = 300; if isfield(T, 'extend_len') && ~isempty(T.extend_len), extend_len = T.extend_len; end
    smooth = isfield(T, 'smooth_normals') && ~isempty(T.smooth_normals) && logical(T.smooth_normals);   % trace.smooth_normals, see first_hit

    if isfield(T, 'alphas0') && ~isempty(T.alphas0)
        alphas0 = T.alphas0(:);
    else
        N = T.n_rays;
        if isfield(T, 'sampling') && strcmpi(T.sampling, 'stochastic')
            if isfield(T, 'seed') && ~isempty(T.seed), rng(T.seed); end
            alphas0 = sort(min_angle + eps_ang + (max_angle - min_angle - 2*eps_ang) * rand(N, 1));
        else
            alphas0 = linspace(min_angle + eps_ang, max_angle - eps_ang, N).';
        end
    end
    N = numel(alphas0);
    S = numel(stack);

    paths      = cell(N, 1);
    exit_ang   = nan(N, 1);
    status     = cell(N, 1);
    n_hits     = zeros(N, 1);
    hit_theta  = cell(N, 1);
    hit_theta_out = cell(N, 1);
    hit_nin    = cell(N, 1);
    hit_nout   = cell(N, 1);
    hit_surf   = cell(N, 1);
    hit_pts    = cell(N, 1);
    overshoot_used = false(N, 1);
    stopped_at = zeros(N, 1);

    for ri = 1:N
        a = alphas0(ri);  P = source;  path = P;
        ths = zeros(1, S); thos = zeros(1, S); nins = zeros(1, S); nouts = zeros(1, S); pts = zeros(S, 2);
        st = 'collected';  k_last = 0;
        for k = 1:S
            sph_k = [];  if isfield(stack, 'sphere'), sph_k = stack(k).sphere; end   % prescribed sphere: exact hit and normal
            smooth_k = smooth && (~isfield(stack, 'kind') || strcmp(stack(k).kind, 'lens'));   % omni surfaces only
            kinks_k = [];  if isfield(stack, 'kinks'), kinks_k = stack(k).kinks; end          % real corners (straight wall / cone)
            [hit, P_hit, a_out, th_in, info] = first_hit(P, a, stack(k).pts, stack(k).n_in, stack(k).n_out, overshoot, sph_k, smooth_k, kinks_k);
            if ~hit, st = 'miss'; break; end
            if info.overshoot_used, overshoot_used(ri) = true; end
            path(end+1, :) = P_hit; %#ok<AGROW>
            ths(k) = th_in;  thos(k) = info.theta_out;  nins(k) = stack(k).n_in;  nouts(k) = stack(k).n_out;  pts(k, :) = P_hit;
            k_last = k;
            if info.tir, st = 'tir'; break; end
            P = P_hit;  a = a_out;
        end
        if strcmp(st, 'collected')
            path(end+1, :) = P + extend_len * [cosd(a), sind(a)]; %#ok<AGROW>
            exit_ang(ri) = a;
        end
        paths{ri}   = path;
        status{ri}  = st;
        n_hits(ri)  = k_last;
        stopped_at(ri) = k_last + strcmp(st, 'miss');   % surface index the ray failed at (0 = none)
        hit_theta{ri} = ths(1:k_last);  hit_theta_out{ri} = thos(1:k_last);
        hit_nin{ri} = nins(1:k_last);   hit_nout{ri} = nouts(1:k_last);
        hit_surf{ri} = 1:k_last;        hit_pts{ri} = pts(1:k_last, :);
    end

    collected = strcmp(status, 'collected');
    trace = struct('alphas0', alphas0, 'paths', {paths}, 'exit_angles', exit_ang, ...
                   'collected', collected, 'status', {status}, 'n_hits', n_hits, ...
                   'hit_theta', {hit_theta}, 'hit_theta_out', {hit_theta_out}, ...
                   'hit_nin', {hit_nin}, 'hit_nout', {hit_nout}, 'hit_surface', {hit_surf}, ...
                   'hit_points', {hit_pts}, 'overshoot_used', overshoot_used, 'stopped_at', stopped_at, ...
                   'n_rays', N, 'n_surfaces', S, 'min_angle', min_angle, 'max_angle', max_angle, ...
                   'source', source, 'extend_len', extend_len, 'n_lost', sum(~collected), ...
                   'n_tir', sum(strcmp(status, 'tir')), 'n_miss', sum(strcmp(status, 'miss')), ...
                   'n_overshoot', sum(overshoot_used));
end
