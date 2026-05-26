function Detection = auto_detect_shock_reaction()
%AUTO_DETECT_SHOCK_REACTION Automatic shock & reaction front detection on raw
%   16-bit .dat data with in-house background subtraction. Supports two
%   detector modes (chosen in the setup GUI): 'band2d' (default) and 'step1d'.
%   Returns the Detection struct (also saved as <datBase>_autodetect.mat).

%% ---- USER SETTINGS ----
frameRate      = 500000;
startFolder    = pwd;
% 1D step-height detector (legacy mode 'step1d')
shockThresh    = 3000;
rxnThresh      = 3000;
whiteLevel     = 0;
scanSmoothWin  = 3;
gradSpan       = 3;
% 2D band detector (default mode 'band2d')
gaussSigma     = 1.5;
magThreshFrac  = 0.95;
intensitySigma = 5;
deadband       = 0;
minArea        = 30;
bandYSmoothWin = 5;
% Temporal prior (only applied in 'band2d')
useShockPrior   = true;
useRxnPrior     = false;
searchHalfWidth = 10;
deviationTol    = 4;
% Cleaning + output
madTol         = 3;
ySmoothWin     = 5;
minValidFrac   = 0.3;
nTuningFrames  = 6;
nOverlayFrames = 6;

%% ---- SELECT .dat ----
[fn, fp] = uigetfile({'*.dat','Raw camera .dat'}, 'Select raw detonation .dat', startFolder);
if isequal(fn,0), disp('Cancelled.'); Detection = []; return; end
src = load_dat_video(fullfile(fp, fn));
totalFrames = src.NumFrames;

%% ---- SETUP GUI ----
setup = setup_detection_gui(src, round(totalFrames/2));
if isempty(setup), disp('Setup cancelled.'); Detection = []; return; end

backRef = dat_frame(src, setup.backgroundFrame);
roiMask = setup.roiMask;

params1d   = struct('shockThresh',shockThresh,'rxnThresh',rxnThresh, ...
    'whiteLevel',whiteLevel,'scanSmoothWin',scanSmoothWin,'gradSpan',gradSpan);
emParams   = struct('gaussSigma',gaussSigma,'cannyThresh',[]);
paramsBand = struct('magThreshFrac',magThreshFrac,'intensitySigma',intensitySigma, ...
    'deadband',deadband,'minArea',minArea,'bandYSmoothWin',bandYSmoothWin);
priorParams = struct('useShockPrior',useShockPrior,'useRxnPrior',useRxnPrior, ...
    'searchHalfWidth',searchHalfWidth,'deviationTol',deviationTol,'deadband',deadband);

%% ---- MULTI-FRAME TUNING PREVIEW (raw, current-mode detector) ----
preFrames = unique(round(linspace(setup.startFrame, setup.endFrame, ...
    min(nTuningFrames, setup.endFrame-setup.startFrame+1))));
accepted = false;
while ~accepted
    hPrev = figure('Name','Tuning Preview','NumberTitle','off','Color','w', ...
        'Units','normalized','Position',[0.05 0.1 0.9 0.8]);
    tlo = tiledlayout(hPrev,'flow','TileSpacing','compact','Padding','compact');
    for j = 1:numel(preFrames)
        k = preFrames(j);
        proc = dat_frame(src, k) - backRef;
        if strcmp(setup.detectorMode, 'band2d')
            [~, Gmag, ~] = edge_map_2d(proc, emParams);
            [sx, rx] = detect_bands_in_frame(proc, Gmag, setup.yRows, setup.scanDir, roiMask, paramsBand);
        else
            [sx, rx] = detect_fronts_in_frame(proc, setup.yRows, setup.scanDir, params1d);
        end
        ax = nexttile(tlo);
        imshow(proc, [], 'Parent', ax); hold(ax,'on');
        overlay_fronts(ax, setup.yRows(:), sx, rx);
        title(ax, sprintf('F%d', k));
    end
    if strcmp(setup.detectorMode, 'band2d')
        ttl = sprintf('band2d (raw)  magThreshFrac=%.2f  intensitySigma=%g  deadband=%g  minArea=%d', ...
            paramsBand.magThreshFrac, paramsBand.intensitySigma, paramsBand.deadband, paramsBand.minArea);
    else
        ttl = sprintf('step1d (raw)  shockThresh=%.0f  rxnThresh=%.0f  whiteLevel=%.0f  scanSmoothWin=%d  gradSpan=%d', ...
            params1d.shockThresh, params1d.rxnThresh, params1d.whiteLevel, params1d.scanSmoothWin, params1d.gradSpan);
    end
    title(tlo, ttl, 'Interpreter','none');
    drawnow;

    choice = questdlg('Accept these thresholds?','Tuning','Accept','Adjust','Cancel','Accept');
    switch choice
        case 'Accept'
            accepted = true; if ishandle(hPrev), close(hPrev); end
        case 'Adjust'
            if strcmp(setup.detectorMode,'band2d')
                answer = inputdlg({'magThreshFrac (0..1)','intensitySigma','deadband','minArea','bandYSmoothWin'}, ...
                    'Adjust band2d params', [1 30], ...
                    {num2str(paramsBand.magThreshFrac), num2str(paramsBand.intensitySigma), ...
                     num2str(paramsBand.deadband), num2str(paramsBand.minArea), ...
                     num2str(paramsBand.bandYSmoothWin)});
                if ~isempty(answer)
                    v = cellfun(@str2double, answer);
                    if all(isfinite(v))
                        paramsBand.magThreshFrac  = max(0, min(1, v(1)));
                        paramsBand.intensitySigma = max(0.1, v(2));
                        paramsBand.deadband       = v(3);
                        paramsBand.minArea        = max(1, round(v(4)));
                        paramsBand.bandYSmoothWin = max(1, round(v(5)));
                    else
                        warndlg('All values must be numbers.','Invalid input');
                    end
                end
            else
                answer = inputdlg({'shockThresh','rxnThresh','whiteLevel','scanSmoothWin','gradSpan'}, ...
                    'Adjust step1d params', [1 30], ...
                    {num2str(params1d.shockThresh), num2str(params1d.rxnThresh), ...
                     num2str(params1d.whiteLevel), num2str(params1d.scanSmoothWin), num2str(params1d.gradSpan)});
                if ~isempty(answer)
                    v = cellfun(@str2double, answer);
                    if all(isfinite(v))
                        params1d.shockThresh   = v(1);
                        params1d.rxnThresh     = v(2);
                        params1d.whiteLevel    = v(3);
                        params1d.scanSmoothWin = round(v(4));
                        params1d.gradSpan      = round(v(5));
                    else
                        warndlg('All values must be numbers.','Invalid input');
                    end
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

prevCleaned = struct('shock',[],'rxn',[],'shockPrev',[],'rxnPrev',[]);

fprintf('Processing %d frames (%d to %d) [%s]...\n', N, setup.startFrame, setup.endFrame, setup.detectorMode);
for k = 1:N
    proc = dat_frame(src, frames(k)) - backRef;
    if strcmp(setup.detectorMode, 'band2d')
        [~, Gmag, ~] = edge_map_2d(proc, emParams);
        [sx, rx] = detect_bands_in_frame(proc, Gmag, setup.yRows, setup.scanDir, roiMask, paramsBand);
        if ~isempty(prevCleaned.shock) || ~isempty(prevCleaned.rxn)
            Iblur = imgaussfilt(proc, paramsBand.intensitySigma);
            [sx, rx] = temporal_prior_refine(sx, rx, prevCleaned, Gmag, Iblur, setup.yRows, priorParams);
        end
    else
        [sx, rx] = detect_fronts_in_frame(proc, setup.yRows, setup.scanDir, params1d);
    end
    shockX_raw(:,k)   = sx;
    rxnX_raw(:,k)     = rx;
    shockX_clean(:,k) = clean_front_line(sx, madTol, ySmoothWin);
    rxnX_clean(:,k)   = clean_front_line(rx, madTol, ySmoothWin);
    valid(k) = mean(~isnan(sx)) >= minValidFrac;
    prevCleaned.shockPrev = prevCleaned.shock;
    prevCleaned.rxnPrev   = prevCleaned.rxn;
    prevCleaned.shock     = shockX_clean(:,k);
    prevCleaned.rxn       = rxnX_clean(:,k);
end
fprintf('Done. %d/%d frames valid.\n', sum(valid), N);

%% ---- BUILD STRUCT ----
Detection.video = struct('fileName',fn,'filePath',fp,'frameRate',frameRate, ...
    'width',src.Width,'height',src.Height,'totalFrames',totalFrames);
Detection.datFormat            = src.fmt;
Detection.detectorMode         = setup.detectorMode;
Detection.calibration = struct('chamberWidth_in',setup.chamberWidth_in, ...
    'pixelHeight',setup.pixelHeight,'mperpix',setup.mperpix, ...
    'yTop',setup.yTop,'yBottom',setup.yBottom,'yPixels',setup.yRows(:), ...
    'calibFrame',setup.calibFrame);
Detection.backgroundFrame      = setup.backgroundFrame;
Detection.roiMask              = setup.roiMask;
Detection.roiClipLeft          = setup.roiClipLeft;
Detection.roiClipRight         = setup.roiClipRight;
Detection.propagationDirection = setup.propagationDirection;
Detection.scanDirection        = setup.scanDir;
Detection.thresholds = struct( ...
    'shockThresh',params1d.shockThresh,'rxnThresh',params1d.rxnThresh, ...
    'whiteLevel',params1d.whiteLevel,'scanSmoothWin',params1d.scanSmoothWin, ...
    'gradSpan',params1d.gradSpan, ...
    'gaussSigma',gaussSigma,'magThreshFrac',paramsBand.magThreshFrac, ...
    'intensitySigma',paramsBand.intensitySigma,'deadband',paramsBand.deadband, ...
    'minArea',paramsBand.minArea, ...
    'bandYSmoothWin',paramsBand.bandYSmoothWin, ...
    'useShockPrior',priorParams.useShockPrior,'useRxnPrior',priorParams.useRxnPrior, ...
    'searchHalfWidth',priorParams.searchHalfWidth,'deviationTol',priorParams.deviationTol, ...
    'madTol',madTol,'ySmoothWin',ySmoothWin,'minValidFrac',minValidFrac, ...
    'nTuningFrames',nTuningFrames);
Detection.frameRange   = [setup.startFrame setup.endFrame];
Detection.frames       = frames;
Detection.shockX_raw   = shockX_raw;
Detection.shockX_clean = shockX_clean;
Detection.rxnX_raw     = rxnX_raw;
Detection.rxnX_clean   = rxnX_clean;
Detection.valid        = valid;

%% ---- SAVE ----
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
title(tlo, sprintf('%s — %s — shock(red)/reaction(cyan)', base, setup.detectorMode), 'Interpreter','none');
savefig(hRev, fullfile(fp, [base '_autodetect_review.fig']));
exportgraphics(hRev, fullfile(fp, [base '_autodetect_review.png']), 'Resolution', 200);
fprintf('Review figure saved.\n');

end

function s = tern(cond, a, b)
    if cond, s = a; else, s = b; end
end
