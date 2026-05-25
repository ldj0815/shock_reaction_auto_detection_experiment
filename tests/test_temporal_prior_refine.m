function tests = test_temporal_prior_refine
tests = functiontests(localfunctions);
end

function test_refines_nan_row_using_prior(t)
    H = 10; W = 100;
    yRows = 3:7;
    Gmag = zeros(H, W);
    Iblur = ones(H, W);                     % default bright
    Gmag(5, 52) = 1000;                     % strong gradient at row 5, col 52
    Iblur(5, 52) = -50;                     % dark region for shock
    shockRaw = [50; 50; NaN; 50; 50];
    rxnRaw   = nan(5, 1);
    prevCleaned = struct('shock', [50;50;50;50;50], 'rxn', nan(5,1));
    params = struct('useShockPrior',true,'useRxnPrior',false, ...
        'searchHalfWidth',10,'deviationTol',4,'deadband',0);
    [sOut, rOut] = temporal_prior_refine(shockRaw, rxnRaw, prevCleaned, ...
        Gmag, Iblur, yRows, params);
    verifyEqual(t, sOut, [50; 50; 52; 50; 50]);
    verifyTrue(t, all(isnan(rOut)));
end

function test_disabled_prior_passes_through(t)
    yRows = 1:3;
    Gmag = zeros(5, 50);
    Iblur = zeros(5, 50);
    shockRaw = [10; NaN; 12];
    rxnRaw   = [20; 21; NaN];
    prevCleaned = struct('shock', [10;10;10], 'rxn', [20;20;20]);
    params = struct('useShockPrior',false,'useRxnPrior',false);
    [sOut, rOut] = temporal_prior_refine(shockRaw, rxnRaw, prevCleaned, ...
        Gmag, Iblur, yRows, params);
    verifyTrue(t, isequaln(sOut, shockRaw));
    verifyTrue(t, isequaln(rOut, rxnRaw));
end

function test_consistent_current_value_unchanged(t)
    yRows = 1:3;
    Gmag = ones(5, 50) * 100;
    Iblur = -ones(5, 50);
    shockRaw = [51; 52; 49];                % all within tol of predicted 50
    rxnRaw = nan(3, 1);
    prevCleaned = struct('shock', [50;50;50], 'rxn', nan(3,1));
    params = struct('useShockPrior',true,'useRxnPrior',false, ...
        'searchHalfWidth',10,'deviationTol',4,'deadband',0);
    [sOut, ~] = temporal_prior_refine(shockRaw, rxnRaw, prevCleaned, ...
        Gmag, Iblur, yRows, params);
    verifyEqual(t, sOut, shockRaw);
end

function test_no_candidate_in_window_keeps_nan(t)
    yRows = 1:3;
    Gmag = zeros(5, 100);                   % no strong gradients anywhere
    Iblur = -ones(5, 100);
    shockRaw = [NaN; NaN; NaN];
    prevCleaned = struct('shock', [50;50;50], 'rxn', nan(3,1));
    params = struct('useShockPrior',true,'useRxnPrior',false, ...
        'searchHalfWidth',10,'deviationTol',4,'deadband',0);
    [sOut, ~] = temporal_prior_refine(shockRaw, nan(3,1), prevCleaned, ...
        Gmag, Iblur, yRows, params);
    verifyTrue(t, all(isnan(sOut)));
end
