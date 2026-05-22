function tests = test_extract_first_two_edges
tests = functiontests(localfunctions);
end

function test_scan_right_to_left(t)
    % Walking R->L (scanDir=-1): shock = darkening (Gx>0 here) at col 15,
    % reaction = brightening (Gx<0) at col 8.
    W = 20; Gx = zeros(1,W); E = false(1,W);
    Gx(15) =  50; E(15) = true;   % shock edge
    Gx(8)  = -60; E(8)  = true;   % reaction edge
    [sx, rx] = extract_first_two_edges(Gx, E, 1, -1, 10);
    verifyEqual(t, sx, 15);
    verifyEqual(t, rx, 8);
end

function test_scan_left_to_right(t)
    % Walking L->R (scanDir=+1): shock = darkening (Gx<0) at col 5,
    % reaction = brightening (Gx>0) at col 12.
    W = 20; Gx = zeros(1,W); E = false(1,W);
    Gx(5)  = -50; E(5)  = true;
    Gx(12) =  60; E(12) = true;
    [sx, rx] = extract_first_two_edges(Gx, E, 1, +1, 10);
    verifyEqual(t, sx, 5);
    verifyEqual(t, rx, 12);
end

function test_no_edges_returns_nan(t)
    Gx = zeros(1,20); E = false(1,20);
    [sx, rx] = extract_first_two_edges(Gx, E, 1, -1, 10);
    verifyTrue(t, isnan(sx));
    verifyTrue(t, isnan(rx));
end

function test_minmag_rejects_weak_edges(t)
    W = 20; Gx = zeros(1,W); E = false(1,W);
    Gx(15) = 5; E(15) = true;     % below minMag=10
    [sx, rx] = extract_first_two_edges(Gx, E, 1, -1, 10);
    verifyTrue(t, isnan(sx));
    verifyTrue(t, isnan(rx));
end

function test_multiple_rows(t)
    W = 20; H = 3; Gx = zeros(H,W); E = false(H,W);
    Gx(:,15) =  50; E(:,15) = true;
    Gx(:,8)  = -60; E(:,8)  = true;
    [sx, rx] = extract_first_two_edges(Gx, E, 1:3, -1, 10);
    verifyEqual(t, sx, [15;15;15]);
    verifyEqual(t, rx, [8;8;8]);
end
