function [Gx, Gmag, E] = edge_map_2d(img, params)
%EDGE_MAP_2D 2D gradient and Canny edge map of a frame.
%   img    : 2-D image (double; e.g. a background-subtracted frame)
%   params : optional struct. Fields:
%            gaussSigma  - Gaussian pre-smoothing sigma (default 1)
%            cannyThresh - [] for auto, or [low high] for edge() (default [])
%   Gx   : signed x-gradient (Sobel)
%   Gmag : gradient magnitude
%   E    : logical Canny edge map
    if nargin < 2 || isempty(params), params = struct(); end
    if ~isfield(params,'gaussSigma') || isempty(params.gaussSigma), params.gaussSigma = 1; end
    if ~isfield(params,'cannyThresh'), params.cannyThresh = []; end

    Is = imgaussfilt(double(img), params.gaussSigma);
    [Gx, Gy] = imgradientxy(Is, 'sobel');
    Gmag = hypot(Gx, Gy);
    if isempty(params.cannyThresh)
        E = edge(mat2gray(Is), 'canny');
    else
        E = edge(mat2gray(Is), 'canny', params.cannyThresh);
    end
end
