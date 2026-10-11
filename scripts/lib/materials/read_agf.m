function G = read_agf(filename)
%READ_AGF  Parse a Zemax glass catalog (*.agf) into a struct array.
%
%   G = read_agf(filename)
%
%   One element per glass (NM record) with fields
%     name        catalog spelling (e.g. 'S-LAH71')
%     key         normalised name for matching: upper case, no '-', ' ' or '_'
%     formula     Zemax dispersion formula number (1..13, see agf_index)
%     mil         MIL / 6-digit code string
%     nd, vd      catalog values from the NM line (reference; n is computed from the formula)
%     status      0 standard | 1 preferred | 2 obsolete | 3 special (inquiry) | 4 melt
%     status_str  the word for it
%     cd          1x10 dispersion coefficients (zero-padded)
%     ld_um       [min max] wavelength range of the formula, micrometres
%     tce, density, dPgF   from the ED record (NaN when absent)
%     td          thermal coefficients D0 D1 D2 E0 E1 Ltk Tref (NaN(1,7) when absent)
%     it          Nx3 internal transmittance table [wavelength_um  tau  thickness_mm]
%     comment     GC record
%     catalog     catalog name = file name without extension
%     maker       first word of the file name, upper case ('OHARA_260701.AGF' -> 'OHARA',
%                 'schott glasses ... .AGF' -> 'SCHOTT'): name the files MAKER_date.agf
%     file        full path
%
%   Records: CC catalog comment, NM name/formula/MIL/nd/vd/exclude/status/melt,
%   GC comment, ED thermal-expansion/density/dPgF, CD coefficients, TD dn/dT,
%   OD/MD other/mechanical (ignored), LD wavelength range, IT transmittance.
%   Handles CRLF, UTF-8 BOM and UTF-16 files.

    if ~exist(filename, 'file'), error('read_agf:file', 'AGF file not found: %s', filename); end
    fid = fopen(filename, 'r');  bytes = fread(fid, inf, '*uint8')';  fclose(fid);
    if numel(bytes) >= 2 && bytes(1) == 255 && bytes(2) == 254                 % UTF-16 LE BOM
        txt = native2unicode(bytes(3:end), 'UTF-16LE');
    elseif numel(bytes) >= 3 && bytes(1) == 239 && bytes(2) == 187 && bytes(3) == 191   % UTF-8 BOM
        txt = char(bytes(4:end));
    else
        txt = char(bytes);
    end
    txt = txt(txt ~= 0 & txt ~= 13);                        % stray NULs (UTF-16 without BOM), CR
    lines = regexp(txt, '\n', 'split');

    [~, base] = fileparts(filename);
    maker = upper(regexp(base, '^[A-Za-z0-9]+', 'match', 'once'));
    if isempty(maker), maker = upper(base); end
    empty = struct('name', '', 'key', '', 'formula', NaN, 'mil', '', 'nd', NaN, 'vd', NaN, ...
                   'status', NaN, 'status_str', '', 'cd', zeros(1, 10), 'ld_um', [NaN NaN], ...
                   'tce', NaN, 'density', NaN, 'dPgF', NaN, 'td', NaN(1, 7), 'it', zeros(0, 3), ...
                   'comment', '', 'catalog', base, 'maker', maker, 'file', filename);
    G = repmat(empty, 0, 1);
    g = [];  it = zeros(0, 3);
    for i = 1:numel(lines)
        ln = strtrim(lines{i});
        if numel(ln) < 2, continue; end
        tag = ln(1:2);  rest = strtrim(ln(3:end));
        switch tag
            case 'NM'
                if ~isempty(g), g.it = it; G(end+1, 1) = g; end %#ok<AGROW>
                g = empty;  it = zeros(0, 3);
                tok = regexp(rest, '\S+', 'match');
                g.name = tok{1};
                g.key  = normalise(tok{1});
                if numel(tok) >= 2, g.formula = str2double(tok{2}); end
                if numel(tok) >= 3, g.mil = tok{3}; end
                if numel(tok) >= 4, g.nd = str2double(tok{4}); end
                if numel(tok) >= 5, g.vd = str2double(tok{5}); end
                if numel(tok) >= 7, g.status = str2double(tok{7}); end
                g.status_str = status_word(g.status);
            case 'GC'
                if ~isempty(g), g.comment = rest; end
            case 'ED'
                v = sscanf(rest, '%f');
                if ~isempty(g) && numel(v) >= 3, g.tce = v(1); g.density = v(3); end
                if ~isempty(g) && numel(v) >= 4, g.dPgF = v(4); end
            case 'CD'
                v = sscanf(rest, '%f')';
                if ~isempty(g), g.cd = zeros(1, 10); g.cd(1:min(10, numel(v))) = v(1:min(10, numel(v))); end
            case 'TD'
                v = sscanf(rest, '%f')';
                if ~isempty(g) && numel(v) >= 7, g.td = v(1:7); end
            case 'LD'
                v = sscanf(rest, '%f')';
                if ~isempty(g) && numel(v) >= 2, g.ld_um = v(1:2); end
            case 'IT'
                v = sscanf(rest, '%f')';
                if ~isempty(g) && numel(v) >= 2
                    if numel(v) < 3, v(3) = NaN; end
                    it(end+1, :) = v(1:3); %#ok<AGROW>
                end
            otherwise
                % CC, OD, MD, BD, ... : not needed
        end
    end
    if ~isempty(g), g.it = it; G(end+1, 1) = g; end
    if isempty(G), error('read_agf:empty', 'No NM records found in %s - is it a Zemax AGF file?', filename); end
end

function k = normalise(name)
    k = upper(name);
    k = k(k ~= '-' & k ~= ' ' & k ~= '_');
end

function s = status_word(code)
    switch code
        case 0, s = 'standard';
        case 1, s = 'preferred';
        case 2, s = 'obsolete';
        case 3, s = 'special/inquiry';
        case 4, s = 'melt';
        otherwise, s = 'unknown';
    end
end
