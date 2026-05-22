function [shockX, rxnX] = detect_fronts_in_frame(grayImg, yRows, scanDir, params)
%DETECT_FRONTS_IN_FRAME Per-row detection of shock and reaction fronts.
%   grayImg : HxW double grayscale image (0-255 range)
%   yRows   : vector of row indices to scan (the calibrated chamber height).
%             Must be within [1, size(grayImg,1)]; out-of-range indices are not validated.
%   scanDir : +1 to scan left->right, -1 to scan right->left
%             (this is the REVERSE of the propagation direction)
%   params  : struct with fields shockThresh, rxnThresh, whiteLevel, scanSmoothWin
%   shockX  : numel(yRows)x1 vector of shock x positions (pixels), NaN if none
%   rxnX    : numel(yRows)x1 vector of reaction-front x positions, NaN if none
%
%   Walking from the leading edge along scanDir: the shock is the first sharp
%   darkening (gradient <= -shockThresh); the reaction front is the first sharp
%   brightening behind the shock (gradient >= +rxnThresh AND intensity >= whiteLevel).
    W = size(grayImg, 2);
    if scanDir > 0
        cols = 1:W;
    else
        cols = W:-1:1;
    end
    n = numel(yRows);
    shockX = nan(n, 1);
    rxnX   = nan(n, 1);
    win = max(1, round(params.scanSmoothWin));

    for i = 1:n
        row = double(grayImg(yRows(i), :));
        sm  = movmean(row, win);
        v   = sm(cols);          % intensity in walk order
        g   = diff(v);           % g(k) = v(k+1) - v(k)

        kS = find(g <= -params.shockThresh, 1, 'first');
        if isempty(kS)
            continue;            % no shock -> leave both NaN
        end
        shockX(i) = cols(kS + 1);

        % search reaction strictly behind the shock
        gTail = g(kS+1:end);
        vTail = v(kS+2:end);     % vTail(j) = v(kS+1+j): the intensity just after each gradient in gTail
        kR = find(gTail >= params.rxnThresh & vTail >= params.whiteLevel, 1, 'first');
        if ~isempty(kR)
            kRabs = kS + kR;     % index into g
            rxnX(i) = cols(kRabs + 1);
        end
    end
end
