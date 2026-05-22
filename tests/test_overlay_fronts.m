function tests = test_overlay_fronts
tests = functiontests(localfunctions);
end

function test_returns_two_line_handles(t)
    f = figure('Visible','off');
    c = onCleanup(@() close(f));
    ax = axes('Parent', f);
    yPixels = (1:10)';
    shockX  = 5 + zeros(10,1);
    rxnX    = 8 + zeros(10,1);
    h = overlay_fronts(ax, yPixels, shockX, rxnX);
    verifyEqual(t, numel(h), 2);
    verifyTrue(t, all(isgraphics(h, 'line')));
end
