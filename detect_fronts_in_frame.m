function [shockX, rxnX] = detect_fronts_in_frame(grayImg, yRows, scanDir, params)
%DETECT_FRONTS_IN_FRAME Per-row detection of shock and reaction fronts.
%   grayImg : HxW double image (any linear intensity scale, e.g. 16-bit counts)
%   yRows   : vector of row indices to scan (the calibrated chamber height).
%             Must be within [1, size(grayImg,1)]; out-of-range indices are not validated.
%   scanDir : +1 to scan left->right, -1 to scan right->left
%             (this is the REVERSE of the propagation direction)
%   params  : struct with fields shockThresh, rxnThresh, whiteLevel,
%             scanSmoothWin, gradSpan
%   shockX  : numel(yRows)x1 vector of shock x positions (pixels), NaN if none
%   rxnX    : numel(yRows)x1 vector of reaction-front x positions, NaN if none
%
%   Detection uses a STEP-HEIGHT measure over a fixed span L = gradSpan:
%   g(i) = v(i+L) - v(i).  shockThresh / rxnThresh are therefore brightness
%   CHANGES in intensity counts (over L px), nearly independent of scanSmoothWin
%   (which only denoises).  The shock is the first span with g <= -shockThresh;
%   the reaction front is the first span behind the shock with g >= +rxnThresh
%   AND post-edge intensity >= whiteLevel.  Each front is localized to the
%   single steepest pixel within its flagged span (~1px). No shock -> both NaN.
    W = size(grayImg, 2);
    if scanDir > 0
        cols = 1:W;
    else
        cols = W:-1:1;
    end
    n   = numel(yRows);
    shockX = nan(n, 1);
    rxnX   = nan(n, 1);
    win = max(1, round(params.scanSmoothWin));
    L   = max(1, round(params.gradSpan));

    for i = 1:n
        row = double(grayImg(yRows(i), :));
        sm  = movmean(row, win);
        v   = sm(cols);            % intensity in walk order
        m   = numel(v);
        if m < L+1, continue; end  % too short to measure a step

        d = diff(v);               % single-step diffs, length m-1
        g = v(1+L:m) - v(1:m-L);   % step height over span L, length m-L
        bright = v(1+L:m);         % post-edge intensity aligned with g

        kS = find(g <= -params.shockThresh, 1, 'first');
        if isempty(kS), continue; end                 % no shock -> both NaN
        ws = kS:(kS+L-1);                              % localize within span
        [~, rel] = min(d(ws));                         % steepest single drop
        shockX(i) = cols(ws(rel) + 1);

        rmask = (g >= params.rxnThresh) & (bright >= params.whiteLevel);
        rmask(1:kS) = false;                           % strictly behind the shock
        kR = find(rmask, 1, 'first');
        if ~isempty(kR)
            wr = kR:(kR+L-1);
            [~, rel2] = max(d(wr));                    % steepest single rise
            rxnX(i) = cols(wr(rel2) + 1);
        end
    end
end
