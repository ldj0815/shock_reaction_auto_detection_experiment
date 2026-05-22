function tests = test_clean_front_line
tests = functiontests(localfunctions);
end

function test_rejects_outlier_and_preserves_nan(t)
    xRaw = [10;10;11;9;50;10;NaN;9;10;11];
    xClean = clean_front_line(xRaw, 3, 3);
    % planted outlier at index 5 -> NaN
    verifyTrue(t, isnan(xClean(5)));
    % raw NaN at index 7 stays NaN
    verifyTrue(t, isnan(xClean(7)));
    % surviving values stay near 10
    good = xClean(~isnan(xClean));
    verifyTrue(t, all(good >= 8 & good <= 12));
end

function test_all_valid_unchanged_range(t)
    xRaw = [20;21;20;19;20;21];
    xClean = clean_front_line(xRaw, 3, 3);
    verifyEqual(t, numel(xClean), 6);
    verifyFalse(t, any(isnan(xClean)));
    verifyTrue(t, all(xClean >= 18 & xClean <= 23));
end

function test_returns_column_vector(t)
    xClean = clean_front_line([5 6 7 6 5], 3, 3); % row input
    verifyEqual(t, size(xClean,2), 1);
end
