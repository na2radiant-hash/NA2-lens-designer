function [n, formula_name] = agf_index(cd, formula, lambda_um)
%AGF_INDEX  Refractive index from Zemax AGF dispersion coefficients.
%
%   [n, formula_name] = agf_index(cd, formula, lambda_um)
%     cd         coefficients of the CD record (up to 10, zero-padded)
%     formula    Zemax dispersion formula number (NM record, 3rd field)
%     lambda_um  wavelength(s) in micrometres (vectorised)
%
%   Formulas (OpticStudio glass catalog definitions, lambda in um):
%     1 Schott       n^2 = a0 + a1 L2 + a2/L2 + a3/L2^2 + a4/L2^3 + a5/L2^4        (L2 = lambda^2)
%     2 Sellmeier 1  n^2 - 1 = sum_{i=1..3} K_i L2/(L2 - L_i)       (K1 L1 K2 L2 K3 L3)
%     3 Herzberger   n = A + B*H + C*H^2 + D L2 + E L2^2 + F L2^3,  H = 1/(L2 - 0.028)
%     4 Sellmeier 2  n^2 - 1 = A + B1 L2/(L2 - l1^2) + B2/(L2 - l2^2)
%     5 Conrady      n = n0 + A/lambda + B/lambda^3.5
%     6 Sellmeier 3  n^2 - 1 = sum_{i=1..4} K_i L2/(L2 - L_i)
%     7 Handbook 1   n^2 = A + B/(L2 - C) - D L2
%     8 Handbook 2   n^2 = A + B L2/(L2 - C) - D L2
%     9 Sellmeier 4  n^2 = A + B L2/(L2 - C) + D L2/(L2 - E)
%    10 Extended     n^2 = a0 + a1 L2 + a2/L2 + ... + a7/L2^6
%    11 Sellmeier 5  n^2 - 1 = sum_{i=1..5} K_i L2/(L2 - L_i)
%    12 Extended 2   n^2 = a0 + a1 L2 + a2/L2 + a3/L2^2 + a4/L2^3 + a5/L2^4 + a6 L2^2 + a7 L2^3
%    13 Extended 3   n^2 = a0 + a1 L2 + a2 L2^2 + a3/L2 + a4/L2^2 + ... + a8/L2^6
%   Schott, Ohara and Hoya catalogs use 1 and 2 only (both verified against the
%   catalog nd for every glass of the 2025/2026 files).

    c = zeros(1, 10);  c(1:min(10, numel(cd))) = cd(1:min(10, numel(cd)));
    lam = lambda_um(:).';  L2 = lam.^2;
    switch formula
        case 1,  formula_name = 'Schott';
            n2 = c(1) + c(2)*L2 + c(3)./L2 + c(4)./L2.^2 + c(5)./L2.^3 + c(6)./L2.^4;
        case 2,  formula_name = 'Sellmeier 1';
            n2 = 1 + c(1)*L2./(L2 - c(2)) + c(3)*L2./(L2 - c(4)) + c(5)*L2./(L2 - c(6));
        case 3,  formula_name = 'Herzberger';
            H = 1 ./ (L2 - 0.028);
            n  = c(1) + c(2)*H + c(3)*H.^2 + c(4)*L2 + c(5)*L2.^2 + c(6)*L2.^3;  n2 = n.^2;
        case 4,  formula_name = 'Sellmeier 2';
            n2 = 1 + c(1) + c(2)*L2./(L2 - c(3)^2) + c(4)./(L2 - c(5)^2);
        case 5,  formula_name = 'Conrady';
            n  = c(1) + c(2)./lam + c(3)./lam.^3.5;  n2 = n.^2;
        case 6,  formula_name = 'Sellmeier 3';
            n2 = 1 + c(1)*L2./(L2 - c(2)) + c(3)*L2./(L2 - c(4)) + c(5)*L2./(L2 - c(6)) + c(7)*L2./(L2 - c(8));
        case 7,  formula_name = 'Handbook of Optics 1';
            n2 = c(1) + c(2)./(L2 - c(3)) - c(4)*L2;
        case 8,  formula_name = 'Handbook of Optics 2';
            n2 = c(1) + c(2)*L2./(L2 - c(3)) - c(4)*L2;
        case 9,  formula_name = 'Sellmeier 4';
            n2 = c(1) + c(2)*L2./(L2 - c(3)) + c(4)*L2./(L2 - c(5));
        case 10, formula_name = 'Extended';
            n2 = c(1) + c(2)*L2 + c(3)./L2 + c(4)./L2.^2 + c(5)./L2.^3 + c(6)./L2.^4 + c(7)./L2.^5 + c(8)./L2.^6;
        case 11, formula_name = 'Sellmeier 5';
            n2 = 1 + c(1)*L2./(L2 - c(2)) + c(3)*L2./(L2 - c(4)) + c(5)*L2./(L2 - c(6)) + c(7)*L2./(L2 - c(8)) + c(9)*L2./(L2 - c(10));
        case 12, formula_name = 'Extended 2';
            n2 = c(1) + c(2)*L2 + c(3)./L2 + c(4)./L2.^2 + c(5)./L2.^3 + c(6)./L2.^4 + c(7)*L2.^2 + c(8)*L2.^3;
        case 13, formula_name = 'Extended 3';
            n2 = c(1) + c(2)*L2 + c(3)*L2.^2 + c(4)./L2 + c(5)./L2.^2 + c(6)./L2.^3 + c(7)./L2.^4 + c(8)./L2.^5 + c(9)./L2.^6;
        otherwise
            error('agf_index:formula', 'Unsupported AGF dispersion formula %g', formula);
    end
    n = sqrt(n2);
    n = reshape(n, size(lambda_um));
end
