function [shockX, rxnX, shockMask, rxnMask] = detect_bands_in_frame( ...
    proc, Gmag, yRows, scanDir, roiMask, params)
%DETECT_BANDS_IN_FRAME Band-based shock/reaction detection.
%   Strong-gradient pixels (within roiMask) are split into a DARK-region band
%   (shock) and a BRIGHT-region band (reaction) by a smoothed proc, then each
%   row's interface is the LEADING band pixel in scanDir.
%
%   proc, Gmag : HxW double (background-subtracted frame and its gradient magnitude)
%   yRows      : row indices to scan
%   scanDir    : +1 = scan left->right (reverse of right->left propagation)
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

    if scanDir > 0, cols = 1:W; else, cols = W:-1:1; end
    for i = 1:n
        y = yRows(i);
        shockX(i) = leadingX(shockMask(y, cols), cols);
        rxnX(i)   = leadingX(rxnMask(y, cols),  cols);
    end
end

function x = leadingX(maskRowWalk, cols)
    j = find(maskRowWalk, 1, 'first');
    if isempty(j), x = NaN; else, x = cols(j); end
end
