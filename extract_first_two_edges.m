function [shockX, rxnX] = extract_first_two_edges(Gx, edgeMask, yRows, scanDir, minMag)
%EXTRACT_FIRST_TWO_EDGES Recover shock/reaction fronts from a 2D edge map.
%   Gx       : HxW signed x-gradient (d/dx; +x = increasing column)
%   edgeMask : HxW logical edge map (e.g. Canny), or any boolean strength mask
%   yRows    : row indices to scan
%   scanDir  : +1 walk left->right, -1 walk right->left (reverse of propagation)
%   minMag   : minimum |Gx| at an edge pixel to accept it
%   shockX, rxnX : numel(yRows)x1 columns of x positions (pixels), NaN if none.
%
%   Walking in scanDir, the per-step intensity change ~= Gx*scanDir. The shock is
%   the first edge pixel that darkens (Gx*scanDir < 0); the reaction front is the
%   next edge pixel behind it that brightens (Gx*scanDir > 0). No shock -> both NaN.
    W = size(Gx, 2);
    if scanDir > 0, cols = 1:W; else, cols = W:-1:1; end
    n = numel(yRows);
    shockX = nan(n, 1);
    rxnX   = nan(n, 1);
    for i = 1:n
        y   = yRows(i);
        gxr = Gx(y, cols);                 % gradient in walk order
        er  = edgeMask(y, cols);           % edge mask in walk order
        dirChange = gxr * scanDir;         % intensity change per walk step
        isEdge = er & (abs(gxr) >= minMag);

        kS = find(isEdge & (dirChange < 0), 1, 'first');   % first darkening edge
        if isempty(kS), continue; end
        shockX(i) = cols(kS);

        tail = (kS+1):numel(cols);
        kR = find(isEdge(tail) & (dirChange(tail) > 0), 1, 'first');  % brightening behind
        if ~isempty(kR)
            rxnX(i) = cols(kS + kR);
        end
    end
end
