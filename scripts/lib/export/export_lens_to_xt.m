function export_lens_to_xt(final_lens, thickness_mm, filename)
    layers = final_lens(~cellfun(@isempty, final_lens));
    if numel(layers) < 2
        error('export_lens_to_xt:NotEnoughLayers', ...
              'Need at least 2 non-empty layers (front/back) to build a single element.');
    end

    front = layers{1};
    back  = layers{2};

    front_top = front(front(:,2) >= 0, :);
    back_top  = back(back(:,2)  >= 0, :);

    if size(front_top,1) < 2 || size(back_top,1) < 2
        error('export_lens_to_xt:TooFewPoints', ...
              'Not enough points in top half of layers 1 and 2.');
    end

    [~, idxF] = sort(front_top(:,1), 'ascend');
    front_top = front_top(idxF,:);

    [~, idxB] = sort(back_top(:,1), 'ascend');
    back_top  = back_top(idxB,:);

    poly_xy = [front_top; flipud(back_top)];

    if ~isequal(poly_xy(1,:), poly_xy(end,:))
        poly_xy = [poly_xy; poly_xy(1,:)];
    end

    N = size(poly_xy,1);

    fid = fopen(filename, 'w');
    if fid == -1
        error('export_lens_to_xt:FileOpenError', 'Could not open file "%s" for writing.', filename);
    end

    fprintf(fid, '# 2D LENS PROFILE XT EXPORT\n');
    fprintf(fid, '# thickness_mm (for info only): %.6f\n', thickness_mm);
    fprintf(fid, '# One closed polygon built from layers 1 & 2 (top half only)\n\n');

    fprintf(fid, 'PROFILE N %d\n', N);
    for i = 1:N
        x = poly_xy(i,1);
        y = poly_xy(i,2);
        z = 0.0;
        fprintf(fid, '%.9g %.9g %.9g\n', x, y, z);
    end

    fclose(fid);
    fprintf('2D XT export complete: %s (points: %d, thickness info: %.3f mm)\n', ...
            filename, N, thickness_mm);
end
