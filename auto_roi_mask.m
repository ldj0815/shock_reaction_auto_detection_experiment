function roi = auto_roi_mask(backRef, params)
%AUTO_ROI_MASK Illuminated-test-section ROI from a background frame.
%   roi = auto_roi_mask(backRef)
%   roi = auto_roi_mask(backRef, params)
%   params: dilatePx (default 3), minFrac (default 0.2 — keep components
%           covering at least this fraction of the largest one).
%   Otsu threshold on a normalized backRef, then close, fill holes,
%   area-filter, dilate. An all-dark / constant input returns all-false.
    if nargin < 2 || isempty(params), params = struct(); end
    if ~isfield(params,'dilatePx') || isempty(params.dilatePx), params.dilatePx = 3; end
    if ~isfield(params,'minFrac')  || isempty(params.minFrac),  params.minFrac  = 0.2; end

    bk = double(backRef);
    if max(bk(:)) <= min(bk(:))
        roi = false(size(bk)); return;
    end
    g = mat2gray(bk);
    t = graythresh(g);
    if t <= 0
        roi = false(size(bk)); return;
    end
    m = g >= t;
    m = imclose(m, strel('disk', 2));
    m = imfill(m, 'holes');
    cc = bwconncomp(m);
    if cc.NumObjects == 0
        roi = false(size(m)); return;
    end
    areas = cellfun(@numel, cc.PixelIdxList);
    keep  = areas >= params.minFrac * max(areas);
    m2 = false(size(m));
    for i = 1:cc.NumObjects
        if keep(i), m2(cc.PixelIdxList{i}) = true; end
    end
    if params.dilatePx > 0
        m2 = imdilate(m2, strel('disk', round(params.dilatePx)));
    end
    roi = m2;
end
