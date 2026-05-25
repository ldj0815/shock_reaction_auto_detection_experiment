function tests = test_auto_roi_mask
tests = functiontests(localfunctions);
end

function test_bright_disk_kept_corners_excluded(t)
    H = 100; W = 200;
    [X, Y] = meshgrid(1:W, 1:H);
    cx = W/2; cy = H/2; r = 40;
    backRef = zeros(H, W);
    backRef((X - cx).^2 + (Y - cy).^2 <= r^2) = 1.0;
    rng(0); backRef = backRef + 0.01 * randn(H, W);
    roi = auto_roi_mask(backRef);
    verifyEqual(t, size(roi), [H W]);
    verifyTrue(t, roi(round(cy), round(cx)));   % center of disk
    verifyFalse(t, roi(1, 1));                  % far corner outside disk
    verifyFalse(t, roi(end, end));
end

function test_all_dark_returns_false_mask(t)
    roi = auto_roi_mask(zeros(20, 30));
    verifyFalse(t, any(roi(:)));
    verifyEqual(t, size(roi), [20 30]);
end

function test_returns_logical(t)
    roi = auto_roi_mask(rand(15, 20));
    verifyTrue(t, islogical(roi));
end
