function write_dxf(filename, ents, precision)
%WRITE_DXF  Write a minimal ASCII DXF containing LWPOLYLINE entities (NA2_v2 na2_write_dxf).
%   precision = decimal places of the coordinates (default 6).
% Write a minimal ASCII DXF containing LWPOLYLINE entities.
%   ents : struct array with fields
%            .pts   [N x 2] vertices
%            .closed logical (true = closed polyline)
%            .layer  char    (layer name)
% Compatible with SolidWorks / Fusion / AutoCAD 2D-sketch import.
    if nargin < 3 || isempty(precision), precision = 6; end
    fmt = sprintf('10\\n%%.%df\\n20\\n%%.%df\\n', precision, precision);
    fid = fopen(filename, 'w');
    if fid == -1, error('write_dxf:open','Cannot open %s', filename); end
    c = onCleanup(@() fclose(fid));

    fprintf(fid, '0\nSECTION\n2\nENTITIES\n');
    for k = 1:numel(ents)
        P = ents(k).pts;  n = size(P,1);
        lay = 'PROFILE';  if isfield(ents,'layer') && ~isempty(ents(k).layer), lay = ents(k).layer; end
        cl  = 0;          if isfield(ents,'closed') && ~isempty(ents(k).closed) && ents(k).closed, cl = 1; end
        fprintf(fid, '0\nLWPOLYLINE\n8\n%s\n90\n%d\n70\n%d\n', lay, n, cl);
        for i = 1:n
            fprintf(fid, fmt, P(i,1), P(i,2));
        end
    end
    fprintf(fid, '0\nENDSEC\n0\nEOF\n');
end
