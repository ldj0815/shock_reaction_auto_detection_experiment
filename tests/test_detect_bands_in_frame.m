function tests = test_detect_bands_in_frame
tests = functiontests(localfunctions);
end

function img = makeBandFrame()
    H = 50; W = 200;
    img = zeros(H, W);
    img(:, 30:50) = -100;   % dark band (shock side)
    img(:, 70:90) = +100;   % bright band (reaction side)
end

function test_detects_band_leading_edges(t)
    proc = makeBandFrame();
    [~, Gmag, ~] = edge_map_2d(proc, struct('gaussSigma', 1));
    H = size(proc, 1); W = size(proc, 2);
    roi = true(H, W);
    yRows = 10:40;
    params = struct('magThreshFrac', 0.9, 'intensitySigma', 5, 'deadband', 0, 'minArea', 5);
    [sx, rx] = detect_bands_in_frame(proc, Gmag, yRows, +1, roi, params);
    verifyFalse(t, any(isnan(sx)));
    verifyFalse(t, any(isnan(rx)));
    verifyTrue(t, all(abs(sx - 30) <= 3));   % shock = dark band leading edge
    verifyTrue(t, all(abs(rx - 70) <= 3));   % reaction = bright band leading edge
end

function test_roi_blocks_bands_outside(t)
    proc = makeBandFrame();
    [~, Gmag, ~] = edge_map_2d(proc, struct('gaussSigma', 1));
    H = size(proc, 1); W = size(proc, 2);
    roi = false(H, W); roi(:, 95:end) = true;   % ROI past both bands
    yRows = 10:40;
    params = struct('magThreshFrac', 0.9, 'intensitySigma', 5, 'deadband', 0, 'minArea', 5);
    [sx, rx] = detect_bands_in_frame(proc, Gmag, yRows, +1, roi, params);
    verifyTrue(t, all(isnan(sx)));
    verifyTrue(t, all(isnan(rx)));
end

function test_blank_frame_returns_all_nan(t)
    proc = zeros(50, 200);
    [~, Gmag, ~] = edge_map_2d(proc, struct('gaussSigma', 1));
    roi = true(50, 200);
    [sx, rx] = detect_bands_in_frame(proc, Gmag, 10:40, +1, roi, struct());
    verifyTrue(t, all(isnan(sx)));
    verifyTrue(t, all(isnan(rx)));
end
