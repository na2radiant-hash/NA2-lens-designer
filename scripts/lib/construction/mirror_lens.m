function mirrored_lens = mirror_lens(lens_cell_array)
    mirrored_lens = cell(size(lens_cell_array));
    for j = 1:length(lens_cell_array)
        if isempty(lens_cell_array{j}), continue; end
        mirrored_lens{j}      = lens_cell_array{j};
        mirrored_lens{j}(:,2) = -lens_cell_array{j}(:,2);
    end
end
