function [cfg, info] = read_config(config_path)
%READ_CONFIG  Load an NA2 run configuration (JSON) into a struct.
%
%   [cfg, info] = read_config(path)
%
%   - Documentation keys ("_doc" in the JSON, which jsondecode renames to the
%     field "x_doc") are removed recursively, so cfg holds settings only.
%   - JSON null becomes [] ("derive automatically").
%   - info: path, name, text (verbatim file content), sha1 (of the text; 'n/a'
%     if the Java digest is unavailable).
%
%   No defaults are applied here: validate_config requires every key.

    if ~exist(config_path, 'file')
        error('read_config:missing', 'Config file not found: %s', config_path);
    end
    txt = fileread(config_path);
    try
        raw = jsondecode(txt);
    catch ME
        error('read_config:json', 'Config is not valid JSON (%s): %s', config_path, ME.message);
    end
    if ~isstruct(raw)
        error('read_config:notObject', 'Config root must be a JSON object: %s', config_path);
    end

    cfg = strip_docs(raw);

    [~, nm, ext] = fileparts(config_path);
    info.path = config_path;
    info.name = [nm ext];
    info.text = txt;
    info.sha1 = sha1_of(txt);
end

function s = strip_docs(s)
    % remove the documentation field at every level
    % (MATLAB's jsondecode renames "_doc" to "x_doc"; Octave keeps "_doc")
    if ~isstruct(s), return; end
    for k = 1:numel(s)
        if isfield(s, 'x_doc'), s = rmfield(s, 'x_doc'); end
        if isfield(s, '_doc'),  s = rmfield(s, '_doc');  end
        fn = fieldnames(s);
        for i = 1:numel(fn)
            v = s(k).(fn{i});
            if isstruct(v), s(k).(fn{i}) = strip_docs(v); end
        end
    end
end

function h = sha1_of(txt)
    h = 'n/a';
    try
        md = java.security.MessageDigest.getInstance('SHA-1');
        md.update(uint8(txt));
        h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2).', 1, []));
    catch
        % Java not available (e.g. -nojvm): leave 'n/a'
    end
end
