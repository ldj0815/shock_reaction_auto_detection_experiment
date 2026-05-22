function Detection = auto_detect_shock_reaction()
%AUTO_DETECT_SHOCK_REACTION Automatic per-row shock & reaction front detection.
%   Returns the Detection struct (also saved as <video>_autodetect.mat).

%% ---- USER SETTINGS ----
frameRate      = 500000;   % Hz (video frame rate)
startFolder    = pwd;      % default folder for the file picker
shockThresh    = 25;       % darkening gradient magnitude (0-255 scale)
rxnThresh      = 25;       % brightening gradient magnitude
whiteLevel     = 180;      % absolute intensity floor for "white" reaction
scanSmoothWin  = 5;        % smoothing window along the scan axis
madTol         = 3;        % MAD multiplier for per-row outlier rejection
ySmoothWin     = 5;        % smoothing window along y (cleaned curve)
minValidFrac   = 0.3;      % min fraction of detected rows for a "valid" frame
nOverlayFrames = 6;        % frames in the review montage

%% ---- SELECT VIDEO ----
[fn, fp] = uigetfile({'*.avi','AVI video'}, 'Select detonation video', startFolder);
if isequal(fn,0), disp('Cancelled.'); Detection = []; return; end
video = VideoReader(fullfile(fp, fn));
totalFrames = video.NumFrames;

%% ---- SETUP GUI ----
setup = setup_detection_gui(video, round(totalFrames/2));
if isempty(setup), disp('Setup cancelled.'); Detection = []; return; end

params = struct('shockThresh',shockThresh,'rxnThresh',rxnThresh, ...
    'whiteLevel',whiteLevel,'scanSmoothWin',scanSmoothWin);

%% ---- TUNING PREVIEW LOOP ----
calibGray = toGray(read(video, setup.calibFrame));
accepted = false;
while ~accepted
    [sx, rx] = detect_fronts_in_frame(calibGray, setup.yRows, setup.scanDir, params);
    hPrev = figure('Name','Tuning Preview','NumberTitle','off','Color','w');
    imshow(read(video, setup.calibFrame)); hold on;
    overlay_fronts(gca, setup.yRows(:), sx, rx);
    title(sprintf('shockThresh=%.0f  rxnThresh=%.0f  whiteLevel=%.0f  scanSmoothWin=%.0f', ...
        params.shockThresh, params.rxnThresh, params.whiteLevel, params.scanSmoothWin));
    drawnow;
    choice = questdlg('Accept these detection thresholds?','Tuning', ...
        'Accept','Adjust','Cancel','Accept');
    switch choice
        case 'Accept'
            accepted = true; if ishandle(hPrev), close(hPrev); end
        case 'Adjust'
            answer = inputdlg({'shockThresh','rxnThresh','whiteLevel','scanSmoothWin'}, ...
                'Adjust thresholds', [1 30], ...
                {num2str(params.shockThresh), num2str(params.rxnThresh), ...
                 num2str(params.whiteLevel), num2str(params.scanSmoothWin)});
            if ~isempty(answer)
                params.shockThresh   = str2double(answer{1});
                params.rxnThresh     = str2double(answer{2});
                params.whiteLevel    = str2double(answer{3});
                params.scanSmoothWin = str2double(answer{4});
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
    g = toGray(read(video, frames(k)));
    [sx, rx] = detect_fronts_in_frame(g, setup.yRows, setup.scanDir, params);
    shockX_raw(:,k)   = sx;
    rxnX_raw(:,k)     = rx;
    shockX_clean(:,k) = clean_front_line(sx, madTol, ySmoothWin);
    rxnX_clean(:,k)   = clean_front_line(rx, madTol, ySmoothWin);
    valid(k) = mean(~isnan(sx)) >= minValidFrac;
end
fprintf('Done. %d/%d frames valid.\n', sum(valid), N);

%% ---- BUILD STRUCT ----
Detection.video = struct('fileName',fn,'filePath',fp,'frameRate',frameRate, ...
    'width',video.Width,'height',video.Height,'totalFrames',totalFrames);
Detection.calibration = struct('chamberWidth_in',setup.chamberWidth_in, ...
    'pixelHeight',setup.pixelHeight,'mperpix',setup.mperpix, ...
    'yTop',setup.yTop,'yBottom',setup.yBottom,'yPixels',setup.yRows(:), ...
    'calibFrame',setup.calibFrame);
Detection.propagationDirection = setup.propagationDirection;
Detection.scanDirection        = setup.scanDir;
Detection.thresholds = struct('shockThresh',params.shockThresh,'rxnThresh',params.rxnThresh, ...
    'whiteLevel',params.whiteLevel,'scanSmoothWin',params.scanSmoothWin, ...
    'madTol',madTol,'ySmoothWin',ySmoothWin,'minValidFrac',minValidFrac);
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
    imshow(read(video, frames(k)),'Parent',ax); hold(ax,'on');
    overlay_fronts(ax, setup.yRows(:), shockX_clean(:,k), rxnX_clean(:,k));
    title(ax, sprintf('Frame %d%s', frames(k), tern(valid(k),'',' (low conf.)')));
end
title(tlo, sprintf('%s — shock (red) / reaction (cyan)', base), 'Interpreter','none');
savefig(hRev, fullfile(fp, [base '_autodetect_review.fig']));
exportgraphics(hRev, fullfile(fp, [base '_autodetect_review.png']), 'Resolution', 200);
fprintf('Review figure saved.\n');

end

%% ===== local helpers =====
function g = toGray(f)
    if size(f,3) == 3
        g = double(rgb2gray(f));
    else
        g = double(f);
    end
end

function s = tern(cond, a, b)
    if cond, s = a; else, s = b; end
end
