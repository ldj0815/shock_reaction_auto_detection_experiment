function tests = test_detect_bands_in_frame
tests = functiontests(localfunctions);
end

function img = makeBandFrame()
    H = 50; W = 200;
    img = zeros(H, W);
    img(:, 30:50) = -100;   % dark band (shock side)
    img(:, 70:90) = +100;   % bright band (reaction side)
end

function test_detects_band_centerlines(t)
    proc = makeBandFrame();
    [~, Gmag, ~] = edge_map_2d(proc, struct('gaussSigma', 1));
    H = size(proc, 1); W = size(proc, 2);
    roi = true(H, W);
    yRows = 10:40;
    params = struct('magThreshFrac', 0.9, 'intensitySigma', 5, 'deadband', 0, 'minArea', 5);
    [sx, rx] = detect_bands_in_frame(proc, Gmag, yRows, +1, roi, params);
    verifyFalse(t, any(isnan(sx)));
    verifyFalse(t, any(isnan(rx)));
    verifyTrue(t, all(abs(sx - 30) <= 3));   % shock centerline near col 30 transition
    verifyTrue(t, all(abs(rx - 70) <= 3));   % reaction centerline near col 70 transition
end

function test_centroid_is_gradient_weighted(t)
    % Controlled centroid math: dark band cols 20-24 with linearly-increasing
    % Gmag weights [1 2 4 8 16]. The detected x must equal the Gmag-weighted
    % centroid, NOT the leading edge (which would be col 20).
    H = 5; W = 50;
    proc = zeros(H, W);
    proc(:, 20:24) = -100;
    Gmag = zeros(H, W);
    Gmag(:, 20:24) = repmat([1 2 4 8 16], H, 1);
    roi = true(H, W);
    yRows = 1:H;
    params = struct('magThreshFrac', 0.0, 'intensitySigma', 0.5, 'deadband', 0, 'minArea', 1);
    [sx, ~] = detect_bands_in_frame(proc, Gmag, yRows, +1, roi, params);
    expected = (20*1 + 21*2 + 22*4 + 23*8 + 24*16) / (1+2+4+8+16);   % 718/31 ≈ 23.16
    verifyTrue(t, all(abs(sx - expected) < 0.5));
    verifyFalse(t, any(abs(sx - 20) < 0.5));   % NOT the leading edge
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
