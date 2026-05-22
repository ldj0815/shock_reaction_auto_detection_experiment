function edge2d_experiment(datPath, frameList, scanDir, yRows, outPng)
%EDGE2D_EXPERIMENT Visual comparison of 2D edge detection vs the 1D detector.
%   edge2d_experiment(datPath, frameList, scanDir, yRows, outPng)
%   Background is frame 2 (the lab's usual choice). For each frame in frameList
%   renders three panels: (1) background-subtracted frame with Canny edges and the
%   extracted shock(red)/reaction(cyan); (2) Sobel gradient-magnitude heatmap;
%   (3) the same frame with the 1D detector's fronts. Saves outPng (+ .fig).
%
%   Defaults: scanDir=-1, yRows=40:210, outPng='edge2d_compare.png'.
    if nargin < 3 || isempty(scanDir), scanDir = -1; end
    if nargin < 4 || isempty(yRows),  yRows = 40:210; end
    if nargin < 5 || isempty(outPng), outPng = 'edge2d_compare.png'; end

    src     = load_dat_video(datPath);
    backRef = dat_frame(src, 2);

    emParams = struct('gaussSigma',1.5,'cannyThresh',[]);
    minMag   = 0;     % accept any Canny edge regardless of |Gx|; raise to filter
    p1d = struct('shockThresh',3000,'rxnThresh',3000,'whiteLevel',0, ...
                 'scanSmoothWin',3,'gradSpan',3);

    nF  = numel(frameList);
    hFig = figure('Color','w','Units','normalized','Position',[0.03 0.05 0.94 0.9]);
    tlo  = tiledlayout(hFig, nF, 3, 'TileSpacing','compact','Padding','compact');
    for i = 1:nF
        k    = frameList(i);
        proc = dat_frame(src, k) - backRef;
        [Gx, Gmag, E] = edge_map_2d(proc, emParams);
        [sx2, rx2] = extract_first_two_edges(Gx, E, yRows, scanDir, minMag);
        [sx1, rx1] = detect_fronts_in_frame(proc, yRows, scanDir, p1d);

        ax = nexttile(tlo); imshow(proc, [], 'Parent', ax); hold(ax,'on');
        [er, ec] = find(E);
        plot(ax, ec, er, '.', 'Color',[1 1 0], 'MarkerSize', 1);
        overlay_fronts(ax, yRows(:), sx2, rx2);
        title(ax, sprintf('F%d  Canny + 2D fronts', k));

        ax = nexttile(tlo); imshow(Gmag, [], 'Parent', ax); colormap(ax, 'hot');
        title(ax, sprintf('F%d  |grad| (Sobel)', k));

        ax = nexttile(tlo); imshow(proc, [], 'Parent', ax); hold(ax,'on');
        overlay_fronts(ax, yRows(:), sx1, rx1);
        title(ax, sprintf('F%d  1D detector', k));
    end
    title(tlo, 'red=shock  cyan=reaction   |   columns: Canny+2D  /  |grad|  /  1D', ...
        'Interpreter','none');
    savefig(hFig, strrep(outPng, '.png', '.fig'));
    exportgraphics(hFig, outPng, 'Resolution', 150);
    fprintf('Saved %s\n', outPng);
end
