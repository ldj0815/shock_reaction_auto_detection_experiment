function [shockOut, rxnOut] = temporal_prior_refine( ...
    shockRawNow, rxnRawNow, prevCleaned, Gmag, Iblur, yRows, params)
%TEMPORAL_PRIOR_REFINE Rescue per-row detections using the CLEANED previous-
%   frame curve. For each enabled front, predict each row's x as
%   prevCleaned.<front>(row) + medianDisplacement (from one earlier frame if
%   present); if the current raw value is NaN or deviates from the prediction
%   by more than deviationTol, search [pred-W, pred+W] for the strongest Gmag
%   pixel also in the correct brightness region (dark for shock / bright for
%   reaction) — no global magThresh applied within the window. If a toggle is
%   off, that front passes through unchanged.
%
%   shockRawNow, rxnRawNow : numel(yRows)x1 current raw detections
%   prevCleaned : struct with .shock, .rxn (numel(yRows)x1, NaN allowed) and
%                 optionally .shockPrev, .rxnPrev (one earlier cleaned frame)
%   Gmag, Iblur : HxW (Iblur = smoothed proc used for brightness labeling)
%   yRows       : row indices the per-row arrays correspond to
%   params      : useShockPrior (true), useRxnPrior (false),
%                 searchHalfWidth (10), deviationTol (4), deadband (0)
    if ~isfield(params,'useShockPrior') || isempty(params.useShockPrior), params.useShockPrior = true; end
    if ~isfield(params,'useRxnPrior')   || isempty(params.useRxnPrior),   params.useRxnPrior   = false; end
    if ~isfield(params,'searchHalfWidth') || isempty(params.searchHalfWidth), params.searchHalfWidth = 10; end
    if ~isfield(params,'deviationTol')  || isempty(params.deviationTol),  params.deviationTol  = 4; end
    if ~isfield(params,'deadband')      || isempty(params.deadband),      params.deadband      = 0; end

    shockOut = shockRawNow;
    rxnOut   = rxnRawNow;

    if params.useShockPrior && isfield(prevCleaned,'shock') && ~isempty(prevCleaned.shock) && ~all(isnan(prevCleaned.shock))
        shockOut = refineOne(shockRawNow, prevCleaned.shock, ...
            optField(prevCleaned,'shockPrev'), Gmag, Iblur, yRows, 'dark', params);
    end
    if params.useRxnPrior && isfield(prevCleaned,'rxn') && ~isempty(prevCleaned.rxn) && ~all(isnan(prevCleaned.rxn))
        rxnOut = refineOne(rxnRawNow, prevCleaned.rxn, ...
            optField(prevCleaned,'rxnPrev'), Gmag, Iblur, yRows, 'bright', params);
    end
end

function v = optField(s, f)
    if isfield(s, f), v = s.(f); else, v = []; end
end

function out = refineOne(rawNow, prevC, prev2C, Gmag, Iblur, yRows, side, params)
    n = numel(rawNow);
    out = rawNow;
    [H, W] = size(Gmag);
    if ~isempty(prev2C) && numel(prev2C) == numel(prevC)
        d  = prevC - prev2C;
        dx = median(d(~isnan(d)));
        if isnan(dx), dx = 0; end
    else
        dx = 0;
    end
    for i = 1:n
        if isnan(prevC(i)), continue; end
        pred = prevC(i) + dx;
        cur  = rawNow(i);
        if ~isnan(cur) && abs(cur - pred) <= params.deviationTol
            continue;
        end
        lo = max(1, round(pred - params.searchHalfWidth));
        hi = min(W, round(pred + params.searchHalfWidth));
        if lo > hi, continue; end
        y = yRows(i);
        if y < 1 || y > H, continue; end
        g  = Gmag(y, lo:hi);
        Ib = Iblur(y, lo:hi);
        if strcmp(side, 'dark')
            ok = Ib < -params.deadband;
        else
            ok = Ib >  params.deadband;
        end
        candMag = g;
        candMag(~ok) = -Inf;
        [bestVal, j] = max(candMag);
        if isinf(bestVal) || bestVal <= 0, continue; end
        out(i) = lo + j - 1;
    end
end
