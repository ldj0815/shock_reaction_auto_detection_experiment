function [shockX, rxnX, shockMask, rxnMask] = detect_bands_in_frame( ...
    proc, Gmag, yRows, scanDir, roiMask, params)
%DETECT_BANDS_IN_FRAME Band-based shock/reaction detection.
%   Strong-gradient pixels (within roiMask) are split into a DARK-region band
%   (shock) and a BRIGHT-region band (reaction) by a smoothed proc, then each
%   row's interface is the GRADIENT-MAGNITUDE-WEIGHTED CENTROID of the
%   LEADING connected segment of that band in scanDir (the centerline of the
%   ridge, with any trailing segment in the same brightness class ignored) —
%   this places the interface at the peak of the gradient rather than at the
%   upstream edge.
%
%   proc, Gmag : HxW double (background-subtracted frame and its gradient magnitude)
%   yRows      : row indices to scan
%   scanDir    : +1 = scan left->right (reverse of right->left propagation);
%                determines which connected segment of the band is "leading".
%   roiMask    : HxW logical; only ROI pixels are eligible
%   params     : magThreshFrac (default 0.95), intensitySigma (5),
%                deadband (0), minArea (30)
    if nargin < 6 || isempty(params), params = struct(); end
    if ~isfield(params,'magThreshFrac') || isempty(params.magThreshFrac), params.magThreshFrac = 0.95; end
    if ~isfield(params,'intensitySigma') || isempty(params.intensitySigma), params.intensitySigma = 5; end
    if ~isfield(params,'deadband') || isempty(params.deadband), params.deadband = 0; end
    if ~isfield(params,'minArea')  || isempty(params.minArea),  params.minArea  = 30; end

    [H, W] = size(proc);
    n = numel(yRows);
    shockX = nan(n, 1);
    rxnX   = nan(n, 1);
    shockMask = false(H, W);
    rxnMask   = false(H, W);

    rowsMask = false(H, W); rowsMask(yRows, :) = true;
    sample = Gmag(rowsMask & roiMask);
    if isempty(sample) || ~any(sample > 0), return; end
    sv  = sort(sample(:));
    idx = max(1, round(params.magThreshFrac * numel(sv)));
    magThresh = sv(idx);

    Iblur = imgaussfilt(proc, params.intensitySigma);
    strong = (Gmag >= magThresh) & roiMask;
    shockMask = strong & (Iblur < -params.deadband);
    rxnMask   = strong & (Iblur >  params.deadband);
    if params.minArea > 0
        shockMask = bwareaopen(shockMask, params.minArea);
        rxnMask   = bwareaopen(rxnMask,   params.minArea);
    end

    for i = 1:n
        y = yRows(i);
        shockX(i) = leadingCentroidX(shockMask(y, :), Gmag(y, :), scanDir);
        rxnX(i)   = leadingCentroidX(rxnMask(y, :),  Gmag(y, :), scanDir);
    end
end

function x = leadingCentroidX(maskRow, gmagRow, scanDir)
%LEADINGCENTROIDX Gmag-weighted centroid of the LEADING connected segment of
%   the band in scanDir order. Trailing band segments (e.g. the back of a
%   dark zone where it transitions into the reaction zone) are ignored — only
%   the first run of true pixels encountered when walking in scanDir is used.
%   Returns NaN if no segment exists or its total weight is zero.
    d = diff([false, maskRow(:)', false]);
    starts = find(d == 1);
    ends   = find(d == -1) - 1;
    if isempty(starts), x = NaN; return; end
    if scanDir > 0
        s = starts(1);   e = ends(1);     % first run in column order
    else
        s = starts(end); e = ends(end);   % last run = first when walking R->L
    end
    idx = s:e;
    w = double(gmagRow(idx));
    sw = sum(w);
    if sw <= 0, x = NaN; return; end
    x = sum(double(idx) .* w) / sw;
end
