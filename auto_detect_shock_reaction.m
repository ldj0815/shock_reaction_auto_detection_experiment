function Detection = auto_detect_shock_reaction()
%AUTO_DETECT_SHOCK_REACTION Automatic per-row shock & reaction front detection
%   on raw 16-bit .dat high-speed-camera data with in-house background removal.
%   Returns the Detection struct (also saved as <datBase>_autodetect.mat).

%% ---- USER SETTINGS ----
frameRate      = 500000;   % Hz (from acquisition, not a video header)
startFolder    = pwd;      % default folder for the file picker
shockThresh    = 3000;     % shock step-height (drop) in 16-bit counts over gradSpan
rxnThresh      = 3000;     % reaction step-height (rise) in counts over gradSpan
whiteLevel     = 0;        % min post-edge intensity for the reaction (subtracted-image counts)
scanSmoothWin  = 3;        % denoising window along the scan axis (px)
gradSpan       = 3;        % L: span (px) over which the step height is measured
madTol         = 3;        % MAD multiplier for per-row outlier rejection
ySmoothWin     = 5;        % smoothing window along y (cleaned curve)
minValidFrac   = 0.3;      % min fraction of detected rows for a "valid" frame
nOverlayFrames = 6;        % frames in the review montage

%% ---- SELECT .dat ----
[fn, fp] = uigetfile({'*.dat','Raw camera .dat'}, 'Select raw detonation .dat', startFolder);
if isequal(fn,0), disp('Cancelled.'); Detection = []; return; end
src = load_dat_video(fullfile(fp, fn));
totalFrames = src.NumFrames;

%% ---- SETUP GUI ----
setup = setup_detection_gui(src, round(totalFrames/2));
if isempty(setup), disp('Setup cancelled.'); Detection = []; return; end

backRef = dat_frame(src, setup.backgroundFrame);

params = struct('shockThresh',shockThresh,'rxnThresh',rxnThresh, ...
    'whiteLevel',whiteLevel,'scanSmoothWin',scanSmoothWin,'gradSpan',gradSpan);

%% ---- TUNING PREVIEW LOOP ----
calibProc = dat_frame(src, setup.calibFrame) - backRef;
accepted = false;
while ~accepted
    [sx, rx] = detect_fronts_in_frame(calibProc, setup.yRows, setup.scanDir, params);
    hPrev   = figure('Name','Tuning Preview','NumberTitle','off','Color','w');
    hPrevAx = axes(hPrev);
    imshow(calibProc, [], 'Parent', hPrevAx); hold(hPrevAx,'on');
    overlay_fronts(hPrevAx, setup.yRows(:), sx, rx);
    title(hPrevAx, sprintf(['shockThresh=%.0f  rxnThresh=%.0f  whiteLevel=%.0f  ' ...
        'scanSmoothWin=%.0f  gradSpan=%.0f'], params.shockThresh, params.rxnThresh, ...
        params.whiteLevel, params.scanSmoothWin, params.gradSpan));
    drawnow;
    choice = questdlg('Accept these detection thresholds?','Tuning', ...
        'Accept','Adjust','Cancel','Accept');
    switch choice
        case 'Accept'
            accepted = true; if ishandle(hPrev), close(hPrev); end
        case 'Adjust'
            answer = inputdlg({'shockThresh','rxnThresh','whiteLevel','scanSmoothWin','gradSpan'}, ...
                'Adjust thresholds', [1 30], ...
                {num2str(params.shockThresh), num2str(params.rxnThresh), ...
                 num2str(params.whiteLevel), num2str(params.scanSmoothWin), num2str(params.gradSpan)});
            if ~isempty(answer)
                vals = cellfun(@str2double, answer);
                if all(isfinite(vals))
                    params.shockThresh   = vals(1);
                    params.rxnThresh     = vals(2);
                    params.whiteLevel    = vals(3);
                    params.scanSmoothWin = vals(4);
                    params.gradSpan      = vals(5);
                else
                    warndlg('All values must be numbers. Thresholds unchanged.','Invalid input');
                end
            end
            if ishandle(hPrev), close(hPrev); end
        otherwise
            disp('Cancelled at tuning.');
            if ishandle(hPrev), close(hPrev); end
            Detection = []; return;
    end
end

%% ---- BATCH PROCESS ----
frames  = setup.startFrame:setup.endFrame;
N       = numel(frames);
numRows = numel(setup.yRows);
shockX_raw   = nan(numRows, N);
shockX_clean = nan(numRows, N);
rxnX_raw     = nan(numRows, N);
rxnX_clean   = nan(numRows, N);
valid        = false(1, N);

fprintf('Processing %d frames (%d to %d)...\n', N, setup.startFrame, setup.endFrame);
for k = 1:N
    proc = dat_frame(src, frames(k)) - backRef;
    [sx, rx] = detect_fronts_in_frame(proc, setup.yRows, setup.scanDir, params);
    shockX_raw(:,k)   = sx;
    rxnX_raw(:,k)     = rx;
    shockX_clean(:,k) = clean_front_line(sx, madTol, ySmoothWin);
    rxnX_clean(:,k)   = clean_front_line(rx, madTol, ySmoothWin);
    valid(k) = mean(~isnan(sx)) >= minValidFrac;
end
fprintf('Done. %d/%d frames valid.\n', sum(valid), N);

%% ---- BUILD STRUCT ----
Detection.video = struct('fileName',fn,'filePath',fp,'frameRate',frameRate, ...
    'width',src.Width,'height',src.Height,'totalFrames',totalFrames);
Detection.datFormat   = src.fmt;
Detection.calibration = struct('chamberWidth_in',setup.chamberWidth_in, ...
    'pixelHeight',setup.pixelHeight,'mperpix',setup.mperpix, ...
    'yTop',setup.yTop,'yBottom',setup.yBottom,'yPixels',setup.yRows(:), ...
    'calibFrame',setup.calibFrame);
Detection.backgroundFrame      = setup.backgroundFrame;
Detection.propagationDirection = setup.propagationDirection;
Detection.scanDirection        = setup.scanDir;
Detection.thresholds = struct('shockThresh',params.shockThresh,'rxnThresh',params.rxnThresh, ...
    'whiteLevel',params.whiteLevel,'scanSmoothWin',params.scanSmoothWin, ...
    'gradSpan',params.gradSpan,'madTol',madTol,'ySmoothWin',ySmoothWin, ...
    'minValidFrac',minValidFrac);
Detection.frameRange   = [setup.startFrame setup.endFrame];
Detection.frames       = frames;
Detection.shockX_raw   = shockX_raw;
Detection.shockX_clean = shockX_clean;
Detection.rxnX_raw     = rxnX_raw;
Detection.rxnX_clean   = rxnX_clean;
Detection.valid        = valid;

%% ---- SAVE MAT ----
[~, base] = fileparts(fn);
matFile = fullfile(fp, [base '_autodetect.mat']);
save(matFile, 'Detection');
fprintf('Saved: %s\n', matFile);

%% ---- OVERLAY REVIEW FIGURE ----
idx = unique(round(linspace(1, N, min(nOverlayFrames, N))));
hRev = figure('Name','Detection Review','NumberTitle','off','Color','w', ...
    'Units','normalized','Position',[0.05 0.1 0.9 0.8]);
tlo = tiledlayout(hRev,'flow','TileSpacing','compact','Padding','compact');
for j = 1:numel(idx)
    k  = idx(j);
    ax = nexttile(tlo);
    imshow(dat_frame(src, frames(k)) - backRef, [], 'Parent', ax); hold(ax,'on');
    overlay_fronts(ax, setup.yRows(:), shockX_clean(:,k), rxnX_clean(:,k));
    title(ax, sprintf('Frame %d%s', frames(k), tern(valid(k),'',' (low conf.)')));
end
title(tlo, sprintf('%s — shock (red) / reaction (cyan)', base), 'Interpreter','none');
savefig(hRev, fullfile(fp, [base '_autodetect_review.fig']));
exportgraphics(hRev, fullfile(fp, [base '_autodetect_review.png']), 'Resolution', 200);
fprintf('Review figure saved.\n');

end

%% ===== local helpers =====
function s = tern(cond, a, b)
    if cond, s = a; else, s = b; end
end
