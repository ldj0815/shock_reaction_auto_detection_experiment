function xClean = clean_front_line(xRaw, madTol, ySmoothWin)
%CLEAN_FRONT_LINE Reject outliers and lightly smooth a per-row front line.
%   xRaw       : vector of x positions (pixels); may contain NaN (no detection)
%   madTol     : MAD multiplier for outlier rejection (e.g. 3)
%   ySmoothWin : odd window length for movmedian smoothing along y (e.g. 5)
%   xClean     : column vector, same length as xRaw. Outliers and original
%                NaNs are set to NaN; surviving values are median-smoothed.
    xRaw = xRaw(:);
    med  = median(xRaw, 'omitnan');
    madv = median(abs(xRaw - med), 'omitnan');

    spread = 1.4826 * madv;
    if isnan(spread) || spread == 0
        spread = std(xRaw, 'omitnan');   % fallback when MAD degenerates
    end

    x = xRaw;
    if ~isnan(spread) && spread > 0
        isOut = abs(xRaw - med) > madTol * spread;
        isOut(isnan(xRaw)) = false;
        x(isOut) = NaN;
    end

    validMask = ~isnan(x);
    win = max(1, round(ySmoothWin));
    sm = movmedian(x, win, 'omitnan');
    xClean = sm;
    xClean(~validMask) = NaN;   % keep gaps where there was no valid detection
end
