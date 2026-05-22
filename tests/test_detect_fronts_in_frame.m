function tests = test_detect_fronts_in_frame
tests = functiontests(localfunctions);
end

function p = params(varargin)
    % defaults; gradSpan (L) and step-height thresholds in intensity counts
    p = struct('shockThresh',300,'rxnThresh',300,'whiteLevel',800, ...
               'scanSmoothWin',1,'gradSpan',1);
    for k = 1:2:numel(varargin), p.(varargin{k}) = varargin{k+1}; end
end

function img = makeFrame()
    % H x W, constant down each column.  x = column (1..100):
    %  [1..19]=500 (burned), [20..49]=900 (reaction/white),
    %  [50..79]=200 (post-shock dark), [80..100]=600 (unburned ahead)
    W = 100; H = 20;
    rp = zeros(1,W);
    rp(1:19)   = 500;
    rp(20:49)  = 900;
    rp(50:79)  = 200;
    rp(80:100) = 600;
    img = repmat(rp, H, 1);
end

function test_scan_right_to_left(t)
    % propagation L->R => scanDir = -1; shock at 600->200 (x~79),
    % reaction at 200->900 (x~49)
    [sx, rx] = detect_fronts_in_frame(makeFrame(), 5:15, -1, params());
    verifyEqual(t, numel(sx), 11);
    verifyTrue(t, all(abs(sx - 79) <= 1));
    verifyTrue(t, all(abs(rx - 49) <= 1));
end

function test_scan_left_to_right(t)
    W = 100; H = 20; rp = zeros(1,W);
    rp(1:20)=600; rp(21:50)=200; rp(51:80)=900; rp(81:100)=500;
    img = repmat(rp, H, 1);
    [sx, rx] = detect_fronts_in_frame(img, 5:15, +1, params());
    verifyTrue(t, all(abs(sx - 21) <= 1));
    verifyTrue(t, all(abs(rx - 51) <= 1));
end

function test_no_shock_returns_nan(t)
    [sx, rx] = detect_fronts_in_frame(makeFrame(), 5:15, -1, params('shockThresh',100000));
    verifyTrue(t, all(isnan(sx)));
    verifyTrue(t, all(isnan(rx)));
end

function test_reaction_needs_white_level(t)
    % reaction zone is 900; require >1000 so it cannot qualify as white
    [sx, rx] = detect_fronts_in_frame(makeFrame(), 5:15, -1, params('whiteLevel',1000));
    verifyTrue(t, all(abs(sx - 79) <= 1));
    verifyTrue(t, all(isnan(rx)));
end

function test_threshold_decoupled_from_smoothing(t)
    % A single-pixel 400-count drop at x=59->60 (scanDir +1).
    % With the SAME shockThresh and gradSpan>=smoothing, win=1 and win=5
    % must detect the SAME edge.  (A per-pixel-diff detector would miss
    % win=5 because the slope is smeared to ~80/px < threshold.)
    W = 100; H = 10; rp = zeros(1,W);
    rp(1:59) = 600; rp(60:100) = 200;
    img = repmat(rp, H, 1);
    pr = params('shockThresh',300,'rxnThresh',100000,'gradSpan',5);

    [s1, ~] = detect_fronts_in_frame(img, 3:8, +1, setfield(pr,'scanSmoothWin',1)); %#ok<SFLD>
    [s5, ~] = detect_fronts_in_frame(img, 3:8, +1, setfield(pr,'scanSmoothWin',5)); %#ok<SFLD>

    verifyFalse(t, any(isnan(s1)));      % detected at win=1
    verifyFalse(t, any(isnan(s5)));      % STILL detected at win=5
    verifyTrue(t, all(abs(s1 - 60) <= 1));
    verifyTrue(t, all(abs(s5 - s1) <= 3));
end
