function T = test_paper_sim_equivalence(Rs)
%TEST_PAPER_SIM_EQUIVALENCE  Scaled paper-mode code vs the pre-scaling reference copies.
%
%   T = test_paper_sim_equivalence            % R = 60, 120, 400, 2000
%   T = test_paper_sim_equivalence([60 120])
%
%   For the three default paper lenses (Fig 1AB, Fig 1EF, Fig 2C) and each R:
%     - final_lens of sim_build_lens vs sim_build_lens_ref       (max |diff|, must be <= 1e-12)
%     - traced rays: the Fig 1A/1B/2C drawn fan after the AUTO_MAX_ANGLE bisection
%       (u_over 0.05), the Fig 1E/1F ray angles (u_over 1e-12) and a dense 0..180 deg
%       fan, sim_first_hit vs sim_first_hit_ref on the same lens  (max |diff| of
%       every path point and exit angle, must be <= 1e-12)
%   Then the R of each paper .mat lens (inputs/designs) is rebuilt and compared
%   (expected <= 3e-10 du). Run from anywhere; not on the normal run path.

    if nargin < 1, Rs = [60 120 400 2000]; end
    here = fileparts(mfilename('fullpath'));
    addpath(here);  addpath(fileparts(here));
    naRoot = fileparts(fileparts(fileparts(fileparts(here))));      % NA2

    C.n1 = 1;
    C.weights = struct('J_front', 10, 'k_shape', 0.8, 'base_w', 0.8, 'hardness_exp', 2.0, 'layer_exp', 1.2);
    C.jump_size_du = 0.1;
    C.draw_max_deg = 162.5;  C.draw_eps_deg = 1e-6;
    lenses = struct('name', {'fig1AB', 'fig1EF', 'fig2C'}, ...
                    'n2', {2.003, 2.003, 1.57}, 'layers', {8, 8, 16}, ...
                    'fan_max_deg', {162.54, 180, 180 - asind(0.3)}, 'fan_eps_deg', {0, 0.1, 0.1}, ...
                    'drawn', {10, [], 6}, ...
                    'mat', {'lens_data_dipole_4_elements_no_glass', 'lens_data_dipole_4_elements', 'lens_data_8_elements_n157'});

    T = table();
    for R = Rs
        for s = lenses
            P = s;  P.design_rays = R;
            tr = tic;  [~, Lr] = evalc('sim_build_lens_ref(P, C)');  t_ref = toc(tr);
            tn = tic;  [~, Ln] = evalc('sim_build_lens(P, C)');      t_new = toc(tn);
            dlens = lens_diff(Ln.final_lens, Lr.final_lens);
            if isempty(s.drawn)
                ang = [0 80 150 178];  uo = 1e-12;             % Fig 1E/1F rays
            else
                ang = drawn_fan(Ln, C, s.drawn);  uo = 0.05;   % Fig 1A/1B/2C after AUTO_MAX_ANGLE
            end
            ang_dense = linspace(0, 180, 181);
            tt = tic;
            dray = max(trace_diff(Ln, ang, uo), trace_diff(Ln, ang_dense, 0.05));
            t_trace = toc(tt);
            pass = dlens <= 1e-12 && dray <= 1e-12;
            T = [T; table(string(s.name), R, dlens, dray, t_ref, t_new, t_trace, pass, ...
                 'VariableNames', {'lens', 'R', 'max_diff_final_lens', 'max_diff_rays', ...
                                   't_build_ref_s', 't_build_new_s', 't_trace_both_s', 'pass'})]; %#ok<AGROW>
            fprintf('%-7s R=%5d  lens %.3g  rays %.3g  build ref %.2f s / new %.2f s  %s\n', ...
                    s.name, R, dlens, dray, t_ref, t_new, tf(pass));
        end
    end

    fprintf('\n--- paper lenses (inputs/designs) ---\n');
    for s = lenses
        f = fullfile(naRoot, 'inputs', 'designs', [s.mat '.mat']);
        if ~exist(f, 'file'), fprintf('%-7s %s: not present\n', s.name, s.mat); continue; end
        M = load(f, 'final_lens');
        P = s;  P.design_rays = size(M.final_lens{1}, 1);
        [~, Ln] = evalc('sim_build_lens(P, C)');
        dm = lens_diff(Ln.final_lens, M.final_lens);
        fprintf('%-7s R=%d vs %s.mat: max |diff| %.3g du  %s\n', s.name, P.design_rays, s.mat, dm, tf(dm <= 3e-10));
    end
end

% ---------------------------------------------------------------------------
function d = lens_diff(A, B)
    d = 0;
    if numel(A) ~= numel(B), d = inf; return; end
    for j = 1:numel(A)
        if ~isequal(size(A{j}), size(B{j})), d = inf; return; end
        if ~isempty(A{j}), d = max(d, max(abs(A{j}(:) - B{j}(:)))); end
    end
end

function a = drawn_fan(lens, C, N)
% sim_fig_raytrace: AUTO_MAX_ANGLE bisection, then the uniform drawn fan (reference hit)
    ok = @(al) collimates(al, lens, @sim_first_hit_ref);
    hi_a = C.draw_max_deg;
    if ~ok(hi_a) && ok(90)
        lo_a = 90;
        for it = 1:44
            mid = 0.5*(lo_a + hi_a);
            if ok(mid), lo_a = mid; else, hi_a = mid; end
        end
        hi_a = lo_a;
    end
    % the bisection itself must agree with the scaled hit function
    okn = @(al) collimates(al, lens, @sim_first_hit);
    assert(okn(hi_a) == ok(hi_a), 'AUTO_MAX_ANGLE predicate differs');
    a = linspace(C.draw_eps_deg, hi_a - C.draw_eps_deg, N);
end

function c = collimates(alpha0, lens, hitfun)
    c = false;  P0 = lens.source_pos;  ac = alpha0;  ni = lens.n1;  no = lens.n2;
    for j = 1:lens.L
        [h, Ph, an] = hitfun(P0, ac, lens.final_lens{j}, ni, no, 0.05);
        if ~h, return; end
        P0 = Ph;  ac = an;  t = ni;  ni = no;  no = t;
    end
    c = abs(mod(ac + 180, 360) - 180) < 2;
end

function d = trace_diff(lens, angles, u_over)
    d = 0;
    for a0 = angles
        [pn, an] = trace(lens, a0, u_over, @sim_first_hit);
        [pr, ar] = trace(lens, a0, u_over, @sim_first_hit_ref);
        if ~isequal(size(pn), size(pr)) || (isnan(an) ~= isnan(ar)), d = inf; return; end
        d = max([d; abs(pn(:) - pr(:)); abs(an - ar) * ~isnan(an)]);
    end
end

function [path, ac] = trace(lens, a0, u_over, hitfun)
    P0 = lens.source_pos;  ac = a0;  ni = lens.n1;  no = lens.n2;  path = P0;
    for j = 1:lens.L
        [h, Ph, an] = hitfun(P0, ac, lens.final_lens{j}, ni, no, u_over);
        if ~h, break; end
        path = [path; Ph]; %#ok<AGROW>
        P0 = Ph;  ac = an;  t = ni;  ni = no;  no = t;
    end
end

function s = tf(b), if b, s = 'PASS'; else, s = 'FAIL'; end, end
