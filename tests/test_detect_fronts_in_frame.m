function tests = test_detect_fronts_in_frame
tests = functiontests(localfunctions);
end

function img = makeFrame()
    % H x W grayscale (double, 0-255), constant down each column
    W = 100; H = 20;
    rowProfile = zeros(1, W);
    rowProfile(1:19)   = 150;
    rowProfile(20:49)  = 250;   % reaction zone (white)
    rowProfile(50:79)  = 80;    % post-shock (dark)
    rowProfile(80:100) = 200;   % unburned ahead (bright)
    img = repmat(rowProfile, H, 1);
end

function p = params(varargin)
    p = struct('shockThresh',40,'rxnThresh',50,'whiteLevel',200,'scanSmoothWin',1);
    for k = 1:2:numel(varargin), p.(varargin{k}) = varargin{k+1}; end
end

function test_scan_right_to_left(t)
    % propagation L->R => leading edge right => scanDir = -1
    img = makeFrame();
    yRows = 5:15;
    [sx, rx] = detect_fronts_in_frame(img, yRows, -1, params());
    % shock at the 200->80 boundary (x ~ 79); reaction at 80->250 (x ~ 49)
    verifyEqual(t, numel(sx), numel(yRows));
    verifyTrue(t, all(abs(sx - 79) <= 1));
    verifyTrue(t, all(abs(rx - 49) <= 1));
end

function test_scan_left_to_right(t)
    % mirror layout: leading edge on the left, scanDir = +1
    W = 100; H = 20;
    rp = zeros(1,W);
    rp(1:20)   = 200;   % unburned ahead (bright)
    rp(21:50)  = 80;    % post-shock (dark)
    rp(51:80)  = 250;   % reaction (white)
    rp(81:100) = 150;
    img = repmat(rp, H, 1);
    yRows = 5:15;
    [sx, rx] = detect_fronts_in_frame(img, yRows, +1, params());
    verifyTrue(t, all(abs(sx - 21) <= 1));
    verifyTrue(t, all(abs(rx - 51) <= 1));
end

function test_no_shock_returns_nan(t)
    img = makeFrame();
    [sx, rx] = detect_fronts_in_frame(img, 5:15, -1, params('shockThresh',300));
    verifyTrue(t, all(isnan(sx)));
    verifyTrue(t, all(isnan(rx)));  % no reaction without a shock
end

function test_reaction_needs_white_level(t)
    img = makeFrame();
    % reaction zone is 250; require >300 so it cannot qualify as "white"
    [sx, rx] = detect_fronts_in_frame(img, 5:15, -1, params('whiteLevel',300));
    verifyTrue(t, all(abs(sx - 79) <= 1));  % shock still found
    verifyTrue(t, all(isnan(rx)));          % reaction rejected
end
