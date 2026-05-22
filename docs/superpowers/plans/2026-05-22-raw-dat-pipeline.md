# Raw `.dat` Pipeline + 16-bit Detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 8-bit AVI input with a raw 16-bit `.dat` reader + in-house background removal, and make the detection threshold independent of the smoothing window (decoupled step-height gradient with steepest-pixel localization).

**Architecture:** A new `.dat` reader (`load_dat_video` + `dat_frame`) produces 16-bit frames; the orchestrator subtracts a user-chosen background frame and runs the (modified) pure `detect_fronts_in_frame` on the linear difference image. The setup GUI and orchestrator are rewired from `VideoReader` to the `.dat` source and gain a "Set Background" step. `clean_front_line` and `overlay_fronts` are unchanged.

**Tech Stack:** MATLAB R2024a (`fread`/`fopen`, `matlab.unittest` function-based tests). MATLAB binary: `/Applications/MATLAB_R2024a.app/bin/matlab`.

---

## Conventions

- **Run all tests** (from project root):
  ```bash
  /Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
  ```
  `matlab -batch` exits non-zero if the assert fails. MATLAB takes ~30–60s to start; allow up to 180000 ms on every matlab command.
- Source files live in the project root; tests in `tests/`.
- This spec is the foundation for a later spline/sectioning spec — do **not** add spline logic here.
- The `.dat` format is verified: 16-bit (`uint16`), 400×250, contiguous frames after a 6336-byte header, little-endian, no per-frame headers; `NumFrames` inferred from file size.

---

## Task 1: `.dat` reader (`load_dat_video` + `dat_frame`)

**Files:**
- Create: `load_dat_video.m`
- Create: `dat_frame.m`
- Test: `tests/test_load_dat_video.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_load_dat_video.m`:

```matlab
function tests = test_load_dat_video
tests = functiontests(localfunctions);
end

function tmp = writeSyntheticDat(headerBytes, vals16)
    % vals16: uint16 row vector of the pixel payload (after the header)
    tmp = [tempname '.dat'];
    fid = fopen(tmp, 'w', 'l');
    fwrite(fid, zeros(headerBytes,1), 'uint8');     % dummy header
    fwrite(fid, uint16(vals16), 'uint16');          % little-endian payload
    fclose(fid);
end

function test_reads_dimensions_frames_and_pixels(t)
    % W=3, H=2, N=2; payload is column-major per frame
    f1 = [10 20 30 40 50 60];      % frame 1
    f2 = [110 120 130 140 150 160];% frame 2
    tmp = writeSyntheticDat(8, [f1 f2]);
    c = onCleanup(@() delete(tmp));
    fmt = struct('headerBytes',8,'width',3,'height',2);
    src = load_dat_video(tmp, fmt);
    verifyEqual(t, src.Width, 3);
    verifyEqual(t, src.Height, 2);
    verifyEqual(t, src.NumFrames, 2);
    % reshape [W H] then transpose -> frame(h,w)
    verifyEqual(t, dat_frame(src,1), [10 20 30; 40 50 60]);
    verifyEqual(t, dat_frame(src,2), [110 120 130; 140 150 160]);
end

function test_errors_on_noninteger_frame_count(t)
    f1 = [10 20 30 40 50 60];
    tmp = writeSyntheticDat(8, f1);       % only 1 frame's worth of data
    c = onCleanup(@() delete(tmp));
    fmt = struct('headerBytes',8,'width',4,'height',2);  % frame=4*2*2=16B; (20-8)/16 not integer
    verifyError(t, @() load_dat_video(tmp, fmt), 'load_dat_video:badFormat');
end

function test_dat_frame_returns_double(t)
    tmp = writeSyntheticDat(8, [1 2 3 4 5 6]);
    c = onCleanup(@() delete(tmp));
    src = load_dat_video(tmp, struct('headerBytes',8,'width',3,'height',2));
    verifyClass(t, dat_frame(src,1), 'double');
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_load_dat_video.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'load_dat_video'`.

- [ ] **Step 3: Write `load_dat_video.m`**

```matlab
function src = load_dat_video(path, fmt)
%LOAD_DAT_VIDEO Read a raw high-speed-camera .dat into a frame source.
%   src = load_dat_video(path)        uses default format constants
%   src = load_dat_video(path, fmt)   overrides any of the format fields
%
%   fmt fields (defaults): headerBytes=6336, width=400, height=250,
%   dtype='uint16', byteOrder='l' (little-endian). NumFrames is INFERRED
%   from the file size and the function errors if it is not a positive integer.
%
%   src has fields: Width, Height, NumFrames, Data ([H x W x N] of dtype),
%   fmt, filePath. Use dat_frame(src, idx) to get a single 2-D double frame.
    if nargin < 2 || isempty(fmt), fmt = struct(); end
    d = struct('headerBytes',6336,'width',400,'height',250, ...
               'dtype','uint16','byteOrder','l');
    fn = fieldnames(d);
    for k = 1:numel(fn)
        if ~isfield(fmt, fn{k}), fmt.(fn{k}) = d.(fn{k}); end
    end

    info = dir(path);
    if isempty(info)
        error('load_dat_video:notFound', 'File not found: %s', path);
    end
    bpp = bytesPerPixel(fmt.dtype);
    frameBytes = fmt.width * fmt.height * bpp;
    nf = (info.bytes - fmt.headerBytes) / frameBytes;
    if nf <= 0 || mod(nf,1) ~= 0
        error('load_dat_video:badFormat', ...
            ['File size %d B with header %d B and frame %d B does not yield ' ...
             'an integer frame count (got %.3f).'], info.bytes, fmt.headerBytes, frameBytes, nf);
    end
    nf = round(nf);

    fid = fopen(path, 'r', fmt.byteOrder);
    if fid < 0, error('load_dat_video:open', 'Could not open %s', path); end
    closer = onCleanup(@() fclose(fid));
    fseek(fid, fmt.headerBytes, 'bof');
    raw = fread(fid, fmt.width*fmt.height*nf, [fmt.dtype '=>' fmt.dtype]);

    A = reshape(raw, [fmt.width, fmt.height, nf]);
    A = permute(A, [2 1 3]);   % -> [H W N]

    src = struct('Width',fmt.width, 'Height',fmt.height, 'NumFrames',nf, ...
                 'Data',A, 'fmt',fmt, 'filePath',path);
end

function b = bytesPerPixel(dtype)
    switch dtype
        case {'uint8','int8'},               b = 1;
        case {'uint16','int16'},             b = 2;
        case {'uint32','int32','single'},    b = 4;
        case {'double','uint64','int64'},    b = 8;
        otherwise, error('load_dat_video:dtype', 'Unsupported dtype %s', dtype);
    end
end
```

- [ ] **Step 4: Write `dat_frame.m`**

```matlab
function f = dat_frame(src, idx)
%DAT_FRAME Return one frame from a load_dat_video source as a 2-D double.
%   f = dat_frame(src, idx)  ->  src.Height x src.Width double image.
    f = double(src.Data(:,:,idx));
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_load_dat_video.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add load_dat_video.m dat_frame.m tests/test_load_dat_video.m
git commit -m "feat: add raw .dat reader (load_dat_video + dat_frame)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Decoupled step-height detection (`detect_fronts_in_frame` rewrite)

**Files:**
- Modify: `detect_fronts_in_frame.m` (full replacement)
- Modify: `tests/test_detect_fronts_in_frame.m` (full replacement)

- [ ] **Step 1: Replace the test file with the new behavior**

Overwrite `tests/test_detect_fronts_in_frame.m`:

```matlab
function tests = test_detect_fronts_in_frame
tests = functiontests(localfunctions);
end

function p = params(varargin)
    % defaults; gradSpan (L) and step-height thresholds in intensity counts
    p = struct('shockThresh',300,'rxnThresh',300,'whiteLevel',800, ...
               'scanSmoothWin',1,'gradSpan',1);
    for k = 1:2:numel(varargin), p.(varargin{k}) = varargin{k+1}; end
end

function img = makeFrame()
    % H x W, constant down each column.  x = column (1..100):
    %  [1..19]=500 (burned), [20..49]=900 (reaction/white),
    %  [50..79]=200 (post-shock dark), [80..100]=600 (unburned ahead)
    W = 100; H = 20;
    rp = zeros(1,W);
    rp(1:19)   = 500;
    rp(20:49)  = 900;
    rp(50:79)  = 200;
    rp(80:100) = 600;
    img = repmat(rp, H, 1);
end

function test_scan_right_to_left(t)
    % propagation L->R => scanDir = -1; shock at 600->200 (x~79),
    % reaction at 200->900 (x~49)
    [sx, rx] = detect_fronts_in_frame(makeFrame(), 5:15, -1, params());
    verifyEqual(t, numel(sx), 11);
    verifyTrue(t, all(abs(sx - 79) <= 1));
    verifyTrue(t, all(abs(rx - 49) <= 1));
end

function test_scan_left_to_right(t)
    W = 100; H = 20; rp = zeros(1,W);
    rp(1:20)=600; rp(21:50)=200; rp(51:80)=900; rp(81:100)=500;
    img = repmat(rp, H, 1);
    [sx, rx] = detect_fronts_in_frame(img, 5:15, +1, params());
    verifyTrue(t, all(abs(sx - 21) <= 1));
    verifyTrue(t, all(abs(rx - 51) <= 1));
end

function test_no_shock_returns_nan(t)
    [sx, rx] = detect_fronts_in_frame(makeFrame(), 5:15, -1, params('shockThresh',100000));
    verifyTrue(t, all(isnan(sx)));
    verifyTrue(t, all(isnan(rx)));
end

function test_reaction_needs_white_level(t)
    % reaction zone is 900; require >1000 so it cannot qualify as white
    [sx, rx] = detect_fronts_in_frame(makeFrame(), 5:15, -1, params('whiteLevel',1000));
    verifyTrue(t, all(abs(sx - 79) <= 1));
    verifyTrue(t, all(isnan(rx)));
end

function test_threshold_decoupled_from_smoothing(t)
    % A single-pixel 400-count drop at x=59->60 (scanDir +1).
    % With the SAME shockThresh and gradSpan>=smoothing, win=1 and win=5
    % must detect the SAME edge.  (A per-pixel-diff detector would miss
    % win=5 because the slope is smeared to ~80/px < threshold.)
    W = 100; H = 10; rp = zeros(1,W);
    rp(1:59) = 600; rp(60:100) = 200;
    img = repmat(rp, H, 1);
    pr = params('shockThresh',300,'rxnThresh',100000,'gradSpan',5);

    [s1, ~] = detect_fronts_in_frame(img, 3:8, +1, setfield(pr,'scanSmoothWin',1)); %#ok<SFLD>
    [s5, ~] = detect_fronts_in_frame(img, 3:8, +1, setfield(pr,'scanSmoothWin',5)); %#ok<SFLD>

    verifyFalse(t, any(isnan(s1)));      % detected at win=1
    verifyFalse(t, any(isnan(s5)));      % STILL detected at win=5
    verifyTrue(t, all(abs(s1 - 60) <= 1));
    verifyTrue(t, all(abs(s5 - s1) <= 3));
end
```

- [ ] **Step 2: Run the test to verify the new tests fail against the old implementation**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_detect_fronts_in_frame.m'); disp(r)"
```
Expected: FAILS — at minimum `test_threshold_decoupled_from_smoothing` fails (the old per-pixel-diff implementation misses the edge at `scanSmoothWin=5`). Do not proceed until you see a failure here.

- [ ] **Step 3: Replace `detect_fronts_in_frame.m`**

Overwrite `detect_fronts_in_frame.m`:

```matlab
function [shockX, rxnX] = detect_fronts_in_frame(grayImg, yRows, scanDir, params)
%DETECT_FRONTS_IN_FRAME Per-row detection of shock and reaction fronts.
%   grayImg : HxW double image (any linear intensity scale, e.g. 16-bit counts)
%   yRows   : vector of row indices to scan (the calibrated chamber height).
%             Must be within [1, size(grayImg,1)]; out-of-range indices are not validated.
%   scanDir : +1 to scan left->right, -1 to scan right->left
%             (this is the REVERSE of the propagation direction)
%   params  : struct with fields shockThresh, rxnThresh, whiteLevel,
%             scanSmoothWin, gradSpan
%   shockX  : numel(yRows)x1 vector of shock x positions (pixels), NaN if none
%   rxnX    : numel(yRows)x1 vector of reaction-front x positions, NaN if none
%
%   Detection uses a STEP-HEIGHT measure over a fixed span L = gradSpan:
%   g(i) = v(i+L) - v(i).  shockThresh / rxnThresh are therefore brightness
%   CHANGES in intensity counts (over L px), nearly independent of scanSmoothWin
%   (which only denoises).  The shock is the first span with g <= -shockThresh;
%   the reaction front is the first span behind the shock with g >= +rxnThresh
%   AND post-edge intensity >= whiteLevel.  Each front is localized to the
%   single steepest pixel within its flagged span (~1px). No shock -> both NaN.
    W = size(grayImg, 2);
    if scanDir > 0
        cols = 1:W;
    else
        cols = W:-1:1;
    end
    n   = numel(yRows);
    shockX = nan(n, 1);
    rxnX   = nan(n, 1);
    win = max(1, round(params.scanSmoothWin));
    L   = max(1, round(params.gradSpan));

    for i = 1:n
        row = double(grayImg(yRows(i), :));
        sm  = movmean(row, win);
        v   = sm(cols);            % intensity in walk order
        m   = numel(v);
        if m < L+1, continue; end  % too short to measure a step

        d = diff(v);               % single-step diffs, length m-1
        g = v(1+L:m) - v(1:m-L);   % step height over span L, length m-L
        bright = v(1+L:m);         % post-edge intensity aligned with g

        kS = find(g <= -params.shockThresh, 1, 'first');
        if isempty(kS), continue; end                 % no shock -> both NaN
        ws = kS:(kS+L-1);                              % localize within span
        [~, rel] = min(d(ws));                         % steepest single drop
        shockX(i) = cols(ws(rel) + 1);

        rmask = (g >= params.rxnThresh) & (bright >= params.whiteLevel);
        rmask(1:kS) = false;                           % strictly behind the shock
        kR = find(rmask, 1, 'first');
        if ~isempty(kR)
            wr = kR:(kR+L-1);
            [~, rel2] = max(d(wr));                    % steepest single rise
            rxnX(i) = cols(wr(rel2) + 1);
        end
    end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_detect_fronts_in_frame.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (5 tests), including `test_threshold_decoupled_from_smoothing`.

- [ ] **Step 5: Run the full suite (nothing else regressed)**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (all tests across test_load_dat_video, test_detect_fronts_in_frame, test_clean_front_line, test_overlay_fronts).

- [ ] **Step 6: Commit**

```bash
git add detect_fronts_in_frame.m tests/test_detect_fronts_in_frame.m
git commit -m "feat: decouple detection threshold from smoothing (step-height gradient)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Rewire setup GUI to `.dat` + add Set Background

**Files:**
- Modify: `setup_detection_gui.m` (full replacement)

- [ ] **Step 1: Replace `setup_detection_gui.m`**

Overwrite `setup_detection_gui.m`:

```matlab
function setup = setup_detection_gui(src, defaultFrame)
%SETUP_DETECTION_GUI Collect direction, width calibration, background, frame range.
%   src          : frame source from load_dat_video (fields Width/Height/NumFrames)
%   defaultFrame : frame to show initially (default: middle frame)
%   setup        : struct, or [] if cancelled. Fields:
%     propagationDirection ('LtoR'|'RtoL'), scanDir (+1|-1),
%     calibFrame, yTop, yBottom, pixelHeight, yRows, chamberWidth_in,
%     mperpix, backgroundFrame, startFrame, endFrame
    setup = [];
    totalFrames = src.NumFrames;
    if nargin < 2 || isempty(defaultFrame)
        defaultFrame = round(totalFrames/2);
    end
    frameNumber = max(1, min(defaultFrame, totalFrames));

    % --- state shared with callbacks ---
    yTop = []; yBottom = []; calibFrame = [];
    startFrame = []; endFrame = []; chamberWidth_in = []; backIdx = [];
    calibMode = false; calibClicks = [];
    doneFlag = false; cancelled = false;
    hCalibLines = gobjects(0);

    hFig = figure('Name','Detection Setup','NumberTitle','off', ...
        'WindowState','maximized','Color','w','CloseRequestFcn',@cbClose);
    hAx = axes('Parent',hFig,'Units','normalized','Position',[0.02 0.20 0.96 0.78]);
    axis(hAx,'off');
    hImg = imshow(dat_frame(src,frameNumber), [], 'Parent', hAx);
    hold(hAx,'on');

    % green full-screen crosshair cursor
    set(hFig,'Pointer','custom','PointerShapeCData',NaN(16,16),'PointerShapeHotSpot',[8 8]);
    crossHair = createCrossHair(hFig);
    set(hFig,'WindowButtonMotionFcn', @(s,e) updateCrossHair(hFig, crossHair));

    uicontrol(hFig,'Style','text','String','Direction:','Units','normalized', ...
        'Position',[0.02 0.115 0.07 0.035],'BackgroundColor','w','FontSize',10);
    hDir = uicontrol(hFig,'Style','popupmenu','String',{'Left to Right','Right to Left'}, ...
        'Units','normalized','Position',[0.09 0.115 0.14 0.045],'FontSize',10);

    uicontrol(hFig,'Style','pushbutton','String','< Prev','Units','normalized', ...
        'Position',[0.02 0.04 0.06 0.05],'Callback',@(s,e) changeFrame(-1));
    uicontrol(hFig,'Style','pushbutton','String','Next >','Units','normalized', ...
        'Position',[0.09 0.04 0.06 0.05],'Callback',@(s,e) changeFrame(1));
    uicontrol(hFig,'Style','pushbutton','String','<< -10','Units','normalized', ...
        'Position',[0.16 0.04 0.06 0.05],'Callback',@(s,e) changeFrame(-10));
    uicontrol(hFig,'Style','pushbutton','String','+10 >>','Units','normalized', ...
        'Position',[0.23 0.04 0.06 0.05],'Callback',@(s,e) changeFrame(10));
    uicontrol(hFig,'Style','pushbutton','String','Set Start','Units','normalized', ...
        'Position',[0.34 0.04 0.075 0.05],'Callback',@cbSetStart);
    uicontrol(hFig,'Style','pushbutton','String','Set End','Units','normalized', ...
        'Position',[0.42 0.04 0.075 0.05],'Callback',@cbSetEnd);
    uicontrol(hFig,'Style','pushbutton','String','Set Background','Units','normalized', ...
        'Position',[0.50 0.04 0.10 0.05],'Callback',@cbSetBackground);
    uicontrol(hFig,'Style','pushbutton','String','Calibrate Width (2 clicks)', ...
        'Units','normalized','Position',[0.61 0.04 0.16 0.05],'Callback',@cbCalibrate);
    uicontrol(hFig,'Style','pushbutton','String','DONE','Units','normalized', ...
        'Position',[0.86 0.04 0.10 0.05],'FontWeight','bold','Callback',@cbDone);

    hStatus = uicontrol(hFig,'Style','text','Units','normalized', ...
        'Position',[0.34 0.105 0.62 0.04],'BackgroundColor','w','FontSize',9, ...
        'HorizontalAlignment','left','String','');

    set(hImg,'ButtonDownFcn',@cbClick,'HitTest','on','PickableParts','all');
    set(hAx,'ButtonDownFcn',@cbClick);

    refreshStatus();
    uiwait(hFig);

    if cancelled || ~doneFlag
        if ishandle(hFig), delete(hFig); end
        return;
    end

    if get(hDir,'Value') == 1
        setup.propagationDirection = 'LtoR'; setup.scanDir = -1;
    else
        setup.propagationDirection = 'RtoL'; setup.scanDir = +1;
    end
    setup.calibFrame      = calibFrame;
    setup.yTop            = min(yTop, yBottom);
    setup.yBottom         = max(yTop, yBottom);
    setup.pixelHeight     = abs(yBottom - yTop);
    setup.yRows           = round(setup.yTop):round(setup.yBottom);
    setup.yRows           = setup.yRows(setup.yRows >= 1 & setup.yRows <= src.Height);
    setup.chamberWidth_in = chamberWidth_in;
    setup.mperpix         = (chamberWidth_in * 0.0254) / setup.pixelHeight;
    setup.backgroundFrame = backIdx;
    setup.startFrame      = startFrame;
    setup.endFrame        = endFrame;

    if ishandle(hFig), delete(hFig); end

    % ---------- nested callbacks ----------
    function changeFrame(d)
        frameNumber = max(1, min(totalFrames, frameNumber + d));
        fr = dat_frame(src, frameNumber);
        set(hImg, 'CData', fr);
        lo = min(fr(:)); hi = max(fr(:));
        if hi <= lo, hi = lo + 1; end
        set(hAx, 'CLim', [lo hi]);
        drawnow limitrate;
        refreshStatus();
    end
    function cbSetStart(~,~), startFrame = frameNumber; refreshStatus(); end
    function cbSetEnd(~,~),   endFrame   = frameNumber; refreshStatus(); end
    function cbSetBackground(~,~), backIdx = frameNumber; refreshStatus(); end
    function cbCalibrate(~,~)
        calibMode = true; calibClicks = [];
        delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
        set(hStatus,'String','CALIBRATE: click the TOP wall, then the BOTTOM wall.');
    end
    function cbClick(~,~)
        if ~calibMode, return; end
        if ~strcmp(get(hFig,'SelectionType'),'normal'), return; end
        cp = get(hAx,'CurrentPoint');
        yClick = cp(1,2);
        calibClicks(end+1) = yClick; %#ok<AGROW>
        hCalibLines(end+1) = plot(hAx, get(hAx,'XLim'), [yClick yClick], ...
            'y-', 'LineWidth', 1.2, 'HitTest','off','PickableParts','none'); %#ok<AGROW>
        if numel(calibClicks) == 2
            yTop = calibClicks(1); yBottom = calibClicks(2);
            calibFrame = frameNumber;
            answer = inputdlg('Actual chamber width (inches):','Chamber Width', ...
                [1 40], {'2'});
            if isempty(answer)
                w = NaN;
            else
                w = str2double(answer{1});
            end
            if ~isfinite(w) || w <= 0
                yTop = []; yBottom = []; calibFrame = [];
                delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
                set(hStatus,'String','Calibration cancelled — click Calibrate again.');
            else
                chamberWidth_in = w;
            end
            calibMode = false;
            refreshStatus();
        end
    end
    function cbDone(~,~)
        if isempty(yTop) || isempty(chamberWidth_in)
            set(hStatus,'String','ERROR: calibrate width first.'); return;
        end
        if abs(yBottom - yTop) < 1
            set(hStatus,'String','ERROR: calibration clicks too close — recalibrate.'); return;
        end
        if isempty(backIdx)
            set(hStatus,'String','ERROR: set a background frame first.'); return;
        end
        if isempty(startFrame) || isempty(endFrame)
            set(hStatus,'String','ERROR: set start and end frames.'); return;
        end
        if startFrame > endFrame
            set(hStatus,'String','ERROR: start frame must be <= end frame.'); return;
        end
        doneFlag = true; uiresume(hFig);
    end
    function cbClose(~,~), cancelled = true; doneFlag = false; uiresume(hFig); end
    function refreshStatus()
        set(hStatus,'String', sprintf( ...
            ['Frame %d/%d  |  Start: %s  End: %s  Bg: %s  |  ' ...
             'yTop: %s  yBot: %s  Width(in): %s'], ...
            frameNumber, totalFrames, num2str(startFrame), num2str(endFrame), ...
            num2str(backIdx), num2str(yTop), num2str(yBottom), num2str(chamberWidth_in)));
    end

    % ---------- crosshair helpers (adapted from wave_speed_gui_v16) ----------
    function ch = createCrossHair(fig)
        for k = 1:4
            ch(k) = uicontrol(fig,'Style','text','Visible','off','Units','pixels', ...
                'HandleVisibility','off','HitTest','off','BackgroundColor',[0 1 0], ...
                'Enable','inactive'); %#ok<AGROW>
        end
    end
    function updateCrossHair(fig, ch)
        gap = 3;
        cp = hgconvertunits(fig, [fig.CurrentPoint 0 0], fig.Units, 'pixels', fig);
        cp = cp(1:2);
        figPos = hgconvertunits(fig, fig.Position, fig.Units, 'pixels', fig.Parent);
        figW = figPos(3); figH = figPos(4);
        if cp(1) < gap || cp(2) < gap || cp(1) > figW-gap || cp(2) > figH-gap
            set(ch,'Visible','off'); return;
        end
        set(ch,'Visible','on'); thickness = 1;
        set(ch(1),'Position',[0, cp(2), max(1, cp(1)-gap), thickness]);
        set(ch(2),'Position',[cp(1)+gap, cp(2), max(1, figW-cp(1)-gap), thickness]);
        set(ch(3),'Position',[cp(1), 0, thickness, max(1, cp(2)-gap)]);
        set(ch(4),'Position',[cp(1), cp(2)+gap, thickness, max(1, figH-cp(2)-gap)]);
    end
end
```

- [ ] **Step 2: Syntax-check headless**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); checkcode('setup_detection_gui.m'); disp('parsed ok')"
```
Expected: prints `parsed ok` (style warnings acceptable; fix only genuine syntax errors).

- [ ] **Step 3: Manual GUI verification (human step)**

In interactive MATLAB (`cd` to the project root):
```matlab
src = load_dat_video('26_04_02-test12-7kPa-2_H2-1_O2-17_Ar-2kPaC2H4start-0.2usec-0.5MFPS-10ns-256Fr-0.5c-10in-g.dat');
s = setup_detection_gui(src, round(src.NumFrames/2))
```
Verify: frames display (16-bit auto-scaled); Prev/Next/±10 scrub; Set Start/End/Background capture the current frame; Calibrate → two clicks + inches; DONE refuses until width, background, and range are all set; closing returns `[]`. Returned `s` has `backgroundFrame` plus the usual fields.

- [ ] **Step 4: Commit**

```bash
git add setup_detection_gui.m
git commit -m "feat: rewire setup GUI to .dat source and add Set Background

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Rewire orchestrator to `.dat` + background subtraction

**Files:**
- Modify: `auto_detect_shock_reaction.m` (full replacement)

- [ ] **Step 1: Replace `auto_detect_shock_reaction.m`**

Overwrite `auto_detect_shock_reaction.m`:

```matlab
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
```

- [ ] **Step 2: Syntax-check headless**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); checkcode('auto_detect_shock_reaction.m'); disp('parsed ok')"
```
Expected: prints `parsed ok` (style warnings acceptable).

- [ ] **Step 3: Run the full suite (confirm no regression)**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (all tests).

- [ ] **Step 4: Manual end-to-end verification (human step)**

In interactive MATLAB:
```matlab
D = auto_detect_shock_reaction
```
Pick the `.dat`; in setup choose direction, set start/end, **Set Background** on a clean pre-event frame, calibrate width, DONE; tune thresholds (now in 16-bit counts) on the background-subtracted preview; let the batch run. Verify: `*_autodetect.mat` + `*_autodetect_review.png/.fig` appear; `D.backgroundFrame`, `D.datFormat`, and `D.thresholds.gradSpan` are set; overlays sit on the fronts.

- [ ] **Step 5: Commit**

```bash
git add auto_detect_shock_reaction.m
git commit -m "feat: rewire orchestrator to .dat pipeline with background subtraction

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Update docs for the `.dat` pipeline

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update `README.md`**

Make these changes to `README.md`:
- Title/overview unchanged, but replace AVI references with the raw `.dat`.
- **Requirements:** input is now a raw 16-bit `.dat` (e.g. Shimadzu HPV-X/X2-class, 400×250); `rgb2gray` is no longer needed (frames are single-channel).
- **Quick start** unchanged (`auto_detect_shock_reaction`).
- **Workflow:** in the setup step, add **"Set Background — scrub to a clean pre-detonation frame and click Set Background; it is subtracted (linearly) from every frame before detection."** Note detection runs on the background-subtracted image.
- **How detection works:** state thresholds are a **brightness change in raw counts over `gradSpan` pixels** (step-height), so `scanSmoothWin` only denoises and no longer rescales the threshold; the front is localized to the steepest pixel in the flagged span.
- **Tuning table:** add a `gradSpan` row ("span in px over which the step height is measured; make it ≥ the edge width / smoothing"); note `shockThresh`/`rxnThresh`/`whiteLevel` are in 16-bit-count units on the background-subtracted image.
- **Outputs:** add `datFormat` and `backgroundFrame` to the `Detection` field table; note the save file is `<datBase>_autodetect.mat`.
- **Files table:** add `load_dat_video.m` ("reads the raw .dat into a frame source") and `dat_frame.m` ("returns one frame as a 2-D double"); update the entry for `setup_detection_gui.m` to mention background selection.
- **Notes & limitations:** add "Input is the raw `.dat` only (the pre-processed AVI path was removed). The `.dat` layout is auto-sized from file length; `width/height/header/dtype` are overridable constants in `load_dat_video.m`."

- [ ] **Step 2: Update `CLAUDE.md`**

Make these changes to `CLAUDE.md`:
- **Architecture & data flow:** add `load_dat_video.m` / `dat_frame.m` as the frame source feeding the orchestrator; note `VideoReader`/AVI was removed.
- **Key conventions:** add "Detection runs on the **background-subtracted** image (`frame − backRef`, linear 16-bit); `whiteLevel` is in subtracted-count units." Add "Thresholds are **step heights over `gradSpan` px** in raw counts — independent of `scanSmoothWin`, which only denoises. The front is the steepest pixel within the flagged span."
- **The `setup` struct contract:** add `backgroundFrame`.
- **The `Detection` struct contract:** add `datFormat` and `backgroundFrame`; note `thresholds` now includes `gradSpan`.
- **Where to make common changes:** add ".dat format → `load_dat_video.m` (overridable `fmt` constants; `NumFrames` inferred from file size)."
- **Gotchas:** add "The `.dat` is 16-bit linear (10-bit sensor scaled into 16-bit). It is read as `uint16`, reshaped `[W H N]` then transposed to `[H W N]`; verified against a rendered frame. There are no per-frame headers."

- [ ] **Step 3: Sanity check the docs render**

Run:
```bash
cd "/Users/dijialiu/Desktop/Research/MATLAB/Shock_Reaction_Detection_in_Experiments" && grep -c "load_dat_video" README.md CLAUDE.md
```
Expected: a non-zero count in both files.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: update README and CLAUDE.md for the raw .dat pipeline

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- `.dat` reader (16-bit, 400×250, size-inferred frames, overridable constants, error on bad size) → Task 1. ✓
- Background removal (user-picked frame, linear subtraction, detection on subtracted image) → Set Background in Task 3 + subtraction in Task 4. ✓
- Decoupled step-height threshold + steepest-pixel localization → Task 2 (with an explicit decoupling test). ✓
- GUI rewire to `.dat` + display 16-bit → Task 3. ✓
- Orchestrator rewire, `Detection` struct additions (`datFormat`, `backgroundFrame`, `thresholds.gradSpan`) → Task 4. ✓
- Docs update → Task 5. ✓
- AVI dropped (file picker `*.dat`, no `VideoReader`, `toGray` removed) → Tasks 3–4. ✓
- Spline/2D explicitly out of scope. ✓

**Placeholder scan:** Tasks 1–4 contain complete code. Task 5 is doc prose with explicit, itemized edits (no code), which is appropriate for documentation. No TBD/TODO.

**Type consistency:** `load_dat_video` returns `src` with `Width/Height/NumFrames/Data/fmt/filePath`; `dat_frame(src,idx)` used consistently in Tasks 3–4. `params` fields (`shockThresh,rxnThresh,whiteLevel,scanSmoothWin,gradSpan`) consistent between Task 2 (detector + tests) and Task 4 (orchestrator + tuning dialog). `setup` fields including `backgroundFrame` produced in Task 3 and consumed in Task 4. `Detection` field names match the spec.
