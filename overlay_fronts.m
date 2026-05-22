function h = overlay_fronts(ax, yPixels, shockX, rxnX)
%OVERLAY_FRONTS Draw shock (red) and reaction (cyan) front lines on axes ax.
%   yPixels : column vector of row indices
%   shockX, rxnX : matching x positions (pixels); NaN gaps are not drawn
%   h : 1x2 array of line handles [shock, reaction]
    hold(ax, 'on');
    h(1) = plot(ax, shockX(:), yPixels(:), 'r-', 'LineWidth', 1.5);
    h(2) = plot(ax, rxnX(:),   yPixels(:), 'c-', 'LineWidth', 1.5);
end
