# Auto Shock & Reaction Front Detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual frame-by-frame clicking with automatic per-row detection of the shock and reaction fronts in high-speed detonation videos, saving a self-contained `.mat` plus a review figure.

**Architecture:** Two pure, unit-tested MATLAB functions form the core — `detect_fronts_in_frame` (per-row gradient search) and `clean_front_line` (outlier rejection + smoothing). A GUI (`setup_detection_gui`) collects propagation direction, vertical width calibration (two y-clicks with a crosshair), and start/end frames. A small drawing helper (`overlay_fronts`) is shared by the tuning preview and the final review montage. The orchestrator (`auto_detect_shock_reaction`) wires it together: select video → setup → interactive threshold tuning → batch process → save `.mat` + review figure.

**Tech Stack:** MATLAB R2024a (`VideoReader`, `matlab.unittest` function-based tests). Run MATLAB via `/Applications/MATLAB_R2024a.app/bin/matlab`.

---

## Conventions

- **MATLAB binary:** `/Applications/MATLAB_R2024a.app/bin/matlab`
- **Run all tests:** from the project root:
  ```bash
  /Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
  ```
  `matlab -batch` exits non-zero if the `assert` fails, so a clean exit = all pass.
- **Source files** live in the project root (matching the existing flat layout). **Tests** live in `tests/`.
- **Grayscale convention:** images are `double` in the 0–255 range.
- **`scanDir`:** `+1` = scan left→right (increasing x), `-1` = scan right→left. It is the *reverse* of propagation: propagation L→R ⇒ `scanDir = -1`; propagation R→L ⇒ `scanDir = +1`.

---

## Task 1: Project setup

**Files:**
- Create: `.gitignore`
- Create: `tests/` (directory)

- [ ] **Step 1: Initialize git and a tests directory**

```bash
cd "/Users/dijialiu/Desktop/Research/MATLAB/Shock_Reaction_Detection_in_Experiments"
git init
mkdir -p tests
```

- [ ] **Step 2: Create `.gitignore`**

Create `.gitignore`:

```
# Generated detection outputs
*_autodetect.mat
*_autodetect_review.fig
*_autodetect_review.png
.DS_Store
```

- [ ] **Step 3: Confirm MATLAB runs headless**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "disp('matlab ok'); disp(version)"
```
Expected: prints `matlab ok` and `24.x ...`, exits 0.

- [ ] **Step 4: Commit**

```bash
git add .gitignore docs
git commit -m "chore: project setup for auto shock/reaction detection

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `clean_front_line` (pure function, TDD)

Outlier rejection (MAD-based) + light smoothing along y, preserving NaN where no detection exists.

**Files:**
- Create: `clean_front_line.m`
- Test: `tests/test_clean_front_line.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_clean_front_line.m`:

```matlab
function tests = test_clean_front_line
tests = functiontests(localfunctions);
end

function test_rejects_outlier_and_preserves_nan(t)
    xRaw = [10;10;11;9;50;10;NaN;9;10;11];
    xClean = clean_front_line(xRaw, 3, 3);
    % planted outlier at index 5 -> NaN
    verifyTrue(t, isnan(xClean(5)));
    % raw NaN at index 7 stays NaN
    verifyTrue(t, isnan(xClean(7)));
    % surviving values stay near 10
    good = xClean(~isnan(xClean));
    verifyTrue(t, all(good >= 8 & good <= 12));
end

function test_all_valid_unchanged_range(t)
    xRaw = [20;21;20;19;20;21];
    xClean = clean_front_line(xRaw, 3, 3);
    verifyEqual(t, numel(xClean), 6);
    verifyFalse(t, any(isnan(xClean)));
    verifyTrue(t, all(xClean >= 18 & xClean <= 23));
end

function test_returns_column_vector(t)
    xClean = clean_front_line([5 6 7 6 5], 3, 3); % row input
    verifyEqual(t, size(xClean,2), 1);
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_clean_front_line.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'clean_front_line'`.

- [ ] **Step 3: Write minimal implementation**

Create `clean_front_line.m`:

```matlab
function xClean = clean_front_line(xRaw, madTol, ySmoothWin)
%CLEAN_FRONT_LINE Reject outliers and lightly smooth a per-row front line.
%   xRaw       : vector of x positions (pixels); may contain NaN (no detection)
%   madTol     : MAD multiplier for outlier rejection (e.g. 3)
%   ySmoothWin : odd window length for movmedian smoothing along y (e.g. 5)
%   xClean     : column vector, same length as xRaw. Outliers and original
%                NaNs are set to NaN; surviving values are median-smoothed.
    xRaw = xRaw(:);
    med  = median(xRaw, 'omitnan');
    madv = median(abs(xRaw - med), 'omitnan');

    spread = 1.4826 * madv;
    if isnan(spread) || spread == 0
        spread = std(xRaw, 'omitnan');   % fallback when MAD degenerates
    end

    x = xRaw;
    if ~isnan(spread) && spread > 0
        isOut = abs(xRaw - med) > madTol * spread;
        isOut(isnan(xRaw)) = false;
        x(isOut) = NaN;
    end

    validMask = ~isnan(x);
    win = max(1, round(ySmoothWin));
    sm = movmedian(x, win, 'omitnan');
    xClean = sm;
    xClean(~validMask) = NaN;   % keep gaps where there was no valid detection
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_clean_front_line.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add clean_front_line.m tests/test_clean_front_line.m
git commit -m "feat: add clean_front_line outlier rejection + smoothing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `detect_fronts_in_frame` (pure function, TDD)

Per-row gradient search: shock = first sharp darkening; reaction = first sharp brightening to white *behind* the shock.

**Files:**
- Create: `detect_fronts_in_frame.m`
- Test: `tests/test_detect_fronts_in_frame.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_detect_fronts_in_frame.m`. The helper builds a synthetic frame whose intensity (left→right, x = column) is:
`[1..19]=150, [20..49]=250 (white reaction), [50..79]=80 (post-shock dark), [80..100]=200 (bright unburned ahead)`.

```matlab
function tests = test_detect_fronts_in_frame
tests = functiontests(localfunctions);
end

function img = makeFrame()
    % H x W grayscale (double, 0-255), constant down each column
    W = 100; H = 20;
    rowProfile = zeros(1, W);
    rowProfile(1:19)   = 150;
    rowProfile(20:49)  = 250;   % reaction zone (white)
    rowProfile(50:79)  = 80;    % post-shock (dark)
    rowProfile(80:100) = 200;   % unburned ahead (bright)
    img = repmat(rowProfile, H, 1);
end

function p = params(varargin)
    p = struct('shockThresh',40,'rxnThresh',50,'whiteLevel',200,'scanSmoothWin',1);
    for k = 1:2:numel(varargin), p.(varargin{k}) = varargin{k+1}; end
end

function test_scan_right_to_left(t)
    % propagation L->R => leading edge right => scanDir = -1
    img = makeFrame();
    yRows = 5:15;
    [sx, rx] = detect_fronts_in_frame(img, yRows, -1, params());
    % shock at the 200->80 boundary (x ~ 79); reaction at 80->250 (x ~ 49)
    verifyEqual(t, numel(sx), numel(yRows));
    verifyTrue(t, all(abs(sx - 79) <= 1));
    verifyTrue(t, all(abs(rx - 49) <= 1));
end

function test_scan_left_to_right(t)
    % mirror layout: leading edge on the left, scanDir = +1
    W = 100; H = 20;
    rp = zeros(1,W);
    rp(1:20)   = 200;   % unburned ahead (bright)
    rp(21:50)  = 80;    % post-shock (dark)
    rp(51:80)  = 250;   % reaction (white)
    rp(81:100) = 150;
    img = repmat(rp, H, 1);
    yRows = 5:15;
    [sx, rx] = detect_fronts_in_frame(img, yRows, +1, params());
    verifyTrue(t, all(abs(sx - 21) <= 1));
    verifyTrue(t, all(abs(rx - 51) <= 1));
end

function test_no_shock_returns_nan(t)
    img = makeFrame();
    [sx, rx] = detect_fronts_in_frame(img, 5:15, -1, params('shockThresh',300));
    verifyTrue(t, all(isnan(sx)));
    verifyTrue(t, all(isnan(rx)));  % no reaction without a shock
end

function test_reaction_needs_white_level(t)
    img = makeFrame();
    % reaction zone is 250; require >300 so it cannot qualify as "white"
    [sx, rx] = detect_fronts_in_frame(img, 5:15, -1, params('whiteLevel',300));
    verifyTrue(t, all(abs(sx - 79) <= 1));  % shock still found
    verifyTrue(t, all(isnan(rx)));          % reaction rejected
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_detect_fronts_in_frame.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'detect_fronts_in_frame'`.

- [ ] **Step 3: Write minimal implementation**

Create `detect_fronts_in_frame.m`:

```matlab
function [shockX, rxnX] = detect_fronts_in_frame(grayImg, yRows, scanDir, params)
%DETECT_FRONTS_IN_FRAME Per-row detection of shock and reaction fronts.
%   grayImg : HxW double grayscale image (0-255 range)
%   yRows   : vector of row indices to scan (the calibrated chamber height)
%   scanDir : +1 to scan left->right, -1 to scan right->left
%             (this is the REVERSE of the propagation direction)
%   params  : struct with fields shockThresh, rxnThresh, whiteLevel, scanSmoothWin
%   shockX  : numel(yRows)x1 vector of shock x positions (pixels), NaN if none
%   rxnX    : numel(yRows)x1 vector of reaction-front x positions, NaN if none
%
%   Walking from the leading edge along scanDir: the shock is the first sharp
%   darkening (gradient <= -shockThresh); the reaction front is the first sharp
%   brightening behind the shock (gradient >= +rxnThresh AND intensity >= whiteLevel).
    W = size(grayImg, 2);
    if scanDir > 0
        cols = 1:W;
    else
        cols = W:-1:1;
    end
    n = numel(yRows);
    shockX = nan(n, 1);
    rxnX   = nan(n, 1);
    win = max(1, round(params.scanSmoothWin));

    for i = 1:n
        row = double(grayImg(yRows(i), :));
        sm  = movmean(row, win);
        v   = sm(cols);          % intensity in walk order
        g   = diff(v);           % g(k) = v(k+1) - v(k)

        kS = find(g <= -params.shockThresh, 1, 'first');
        if isempty(kS)
            continue;            % no shock -> leave both NaN
        end
        shockX(i) = cols(kS + 1);

        % search reaction strictly behind the shock
        gTail = g(kS+1:end);
        vTail = v(kS+2:end);     % v(k+1) aligned to gTail
        kR = find(gTail >= params.rxnThresh & vTail >= params.whiteLevel, 1, 'first');
        if ~isempty(kR)
            kRabs = kS + kR;     % index into g
            rxnX(i) = cols(kRabs + 1);
        end
    end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_detect_fronts_in_frame.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add detect_fronts_in_frame.m tests/test_detect_fronts_in_frame.m
git commit -m "feat: add detect_fronts_in_frame per-row gradient detection

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `overlay_fronts` drawing helper

Shared by the tuning preview and the final montage (DRY).

**Files:**
- Create: `overlay_fronts.m`
- Test: `tests/test_overlay_fronts.m`

- [ ] **Step 1: Write the failing test (smoke / handle test, headless)**

Create `tests/test_overlay_fronts.m`:

```matlab
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_overlay_fronts.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'overlay_fronts'`.

- [ ] **Step 3: Write minimal implementation**

Create `overlay_fronts.m`:

```matlab
function h = overlay_fronts(ax, yPixels, shockX, rxnX)
%OVERLAY_FRONTS Draw shock (red) and reaction (cyan) front lines on axes ax.
%   yPixels : column vector of row indices
%   shockX, rxnX : matching x positions (pixels); NaN gaps are not drawn
%   h : 1x2 array of line handles [shock, reaction]
    hold(ax, 'on');
    h(1) = plot(ax, shockX(:), yPixels(:), 'r-', 'LineWidth', 1.5);
    h(2) = plot(ax, rxnX(:),   yPixels(:), 'c-', 'LineWidth', 1.5);
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_overlay_fronts.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add overlay_fronts.m tests/test_overlay_fronts.m
git commit -m "feat: add overlay_fronts drawing helper

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `setup_detection_gui` interactive setup

Collects propagation direction, vertical width calibration (two y-clicks with a green crosshair), chamber width in inches, and start/end frames. GUI — verified manually.

**Files:**
- Create: `setup_detection_gui.m`

- [ ] **Step 1: Write the implementation**

Create `setup_detection_gui.m`:

```matlab
function setup = setup_detection_gui(video, defaultFrame)
%SETUP_DETECTION_GUI Collect direction, vertical width calibration, frame range.
%   video        : VideoReader object
%   defaultFrame : frame to show initially (default: middle frame)
%   setup        : struct, or [] if cancelled. Fields:
%     propagationDirection ('LtoR'|'RtoL'), scanDir (+1|-1),
%     calibFrame, yTop, yBottom, pixelHeight, yRows, chamberWidth_in,
%     mperpix, startFrame, endFrame
    setup = [];
    totalFrames = video.NumFrames;
    if nargin < 2 || isempty(defaultFrame)
        defaultFrame = round(totalFrames/2);
    end
    frameNumber = max(1, min(defaultFrame, totalFrames));

    % --- state shared with callbacks ---
    yTop = []; yBottom = []; calibFrame = [];
    startFrame = []; endFrame = []; chamberWidth_in = [];
    calibMode = false; calibClicks = [];
    doneFlag = false; cancelled = false;
    hCalibLines = gobjects(0);

    hFig = figure('Name','Detection Setup','NumberTitle','off', ...
        'WindowState','maximized','Color','w','CloseRequestFcn',@cbClose);
    hAx = axes('Parent',hFig,'Units','normalized','Position',[0.02 0.20 0.96 0.78]);
    axis(hAx,'off');
    hImg = imshow(read(video, frameNumber), 'Parent', hAx);
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
        'Position',[0.02 0.04 0.07 0.05],'Callback',@(s,e) changeFrame(-1));
    uicontrol(hFig,'Style','pushbutton','String','Next >','Units','normalized', ...
        'Position',[0.10 0.04 0.07 0.05],'Callback',@(s,e) changeFrame(1));
    uicontrol(hFig,'Style','pushbutton','String','<< -10','Units','normalized', ...
        'Position',[0.18 0.04 0.07 0.05],'Callback',@(s,e) changeFrame(-10));
    uicontrol(hFig,'Style','pushbutton','String','+10 >>','Units','normalized', ...
        'Position',[0.26 0.04 0.07 0.05],'Callback',@(s,e) changeFrame(10));
    uicontrol(hFig,'Style','pushbutton','String','Set Start','Units','normalized', ...
        'Position',[0.36 0.04 0.10 0.05],'Callback',@cbSetStart);
    uicontrol(hFig,'Style','pushbutton','String','Set End','Units','normalized', ...
        'Position',[0.47 0.04 0.10 0.05],'Callback',@cbSetEnd);
    uicontrol(hFig,'Style','pushbutton','String','Calibrate Width (2 clicks)', ...
        'Units','normalized','Position',[0.58 0.04 0.18 0.05],'Callback',@cbCalibrate);
    uicontrol(hFig,'Style','pushbutton','String','DONE','Units','normalized', ...
        'Position',[0.86 0.04 0.10 0.05],'FontWeight','bold','Callback',@cbDone);

    hStatus = uicontrol(hFig,'Style','text','Units','normalized', ...
        'Position',[0.36 0.105 0.60 0.04],'BackgroundColor','w','FontSize',9, ...
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
    setup.chamberWidth_in = chamberWidth_in;
    setup.mperpix         = (chamberWidth_in * 0.0254) / setup.pixelHeight;
    setup.startFrame      = startFrame;
    setup.endFrame        = endFrame;

    if ishandle(hFig), delete(hFig); end

    % ---------- nested callbacks ----------
    function changeFrame(d)
        frameNumber = max(1, min(totalFrames, frameNumber + d));
        set(hImg,'CData', read(video, frameNumber));
        refreshStatus();
    end
    function cbSetStart(~,~), startFrame = frameNumber; refreshStatus(); end
    function cbSetEnd(~,~),   endFrame   = frameNumber; refreshStatus(); end
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
            calibMode = false;
            yTop = calibClicks(1); yBottom = calibClicks(2);
            calibFrame = frameNumber;
            answer = inputdlg('Actual chamber width (inches):','Chamber Width', ...
                [1 40], {'2'});
            if isempty(answer) || isnan(str2double(answer{1}))
                yTop = []; yBottom = []; calibFrame = [];
                delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
                set(hStatus,'String','Calibration cancelled — click Calibrate again.');
            else
                chamberWidth_in = str2double(answer{1});
            end
            refreshStatus();
        end
    end
    function cbDone(~,~)
        if isempty(yTop) || isempty(chamberWidth_in)
            set(hStatus,'String','ERROR: calibrate width first.'); return;
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
            'Frame %d/%d  |  Start: %s  End: %s  |  yTop: %s  yBot: %s  Width(in): %s', ...
            frameNumber, totalFrames, num2str(startFrame), num2str(endFrame), ...
            num2str(yTop), num2str(yBottom), num2str(chamberWidth_in)));
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

- [ ] **Step 2: Syntax-check headless (function must parse, not run)**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); checkcode('setup_detection_gui.m'); disp('parsed ok')"
```
Expected: prints `parsed ok` with no syntax errors (style warnings acceptable).

- [ ] **Step 3: Manual GUI verification**

Run in interactive MATLAB (open the app, `cd` to the project):
```matlab
v = VideoReader('26_04_02-test12-7kPa-2_H2-1_O2-17_Ar-2kPaC2H4start-0.2usec-0.5MFPS-10ns-256Fr-0.5c-10in-g_contrast_25.00-sig.avi');
s = setup_detection_gui(v, 128)
```
Verify: a green crosshair tracks the cursor; Prev/Next/±10 scrub frames; "Set Start"/"Set End" capture the current frame; "Calibrate Width" then two clicks draws two yellow lines and prompts for inches; "DONE" returns a struct with sensible `scanDir`, `yRows`, `mperpix`, `startFrame`, `endFrame`. Closing the window returns `[]`.

- [ ] **Step 4: Commit**

```bash
git add setup_detection_gui.m
git commit -m "feat: add setup_detection_gui (direction, width calibration, range)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `auto_detect_shock_reaction` orchestrator

Wires everything together: select video → setup → tuning preview loop → batch process → save `.mat` → review montage. Integration — verified manually on the sample clip.

**Files:**
- Create: `auto_detect_shock_reaction.m`

- [ ] **Step 1: Write the implementation**

Create `auto_detect_shock_reaction.m`:

```matlab
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
```

- [ ] **Step 2: Syntax-check headless**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); checkcode('auto_detect_shock_reaction.m'); disp('parsed ok')"
```
Expected: prints `parsed ok` (style warnings acceptable).

- [ ] **Step 3: Run the full suite to confirm nothing regressed**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (all tests across the 3 test files).

- [ ] **Step 4: Manual end-to-end verification**

In interactive MATLAB (`cd` to the project root):
```matlab
D = auto_detect_shock_reaction
```
Walk through: pick the sample `.avi`; in setup, choose a direction, set start/end frames, calibrate width (two y-clicks + inches), DONE; tune thresholds on the preview until the red shock line and cyan reaction line sit on the right features; let the batch run.
Verify: a `*_autodetect.mat` and `*_autodetect_review.png/.fig` appear next to the video; the montage shows fronts overlaid on ~6 frames; `D.shockX_clean` / `D.rxnX_clean` are `[numRows × N]` with NaN gaps where appropriate; `D.valid` flags frames.

- [ ] **Step 5: Commit**

```bash
git add auto_detect_shock_reaction.m
git commit -m "feat: add auto_detect_shock_reaction orchestrator

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Req 1 (propagation direction → reverse scan): Task 5 popupmenu sets `scanDir` = reverse of propagation; Task 3 consumes it. ✓
- Req 2 (chamber width via two y-clicks, crosshair, middle frame): Task 5 calibration mode + crosshair + inches dialog. ✓
- Req 3 (shock = first darkening, reaction = first jump to white, full y width): Task 3 algorithm over `yRows` spanning the calibrated height. ✓
- Req 4 (plot a few frames with overlay, save `.mat`): Task 6 montage + `_autodetect.mat`. ✓
- Decisions (full curve only, inches dialog, user start/end, self-contained mat, tuning preview, raw+clean curves): covered in Tasks 3/5/6. ✓

**Placeholder scan:** No TBD/TODO; every code step contains complete code. ✓

**Type consistency:** `setup` fields (`scanDir`, `yRows`, `calibFrame`, `mperpix`, `startFrame`, `endFrame`, `chamberWidth_in`, `pixelHeight`, `yTop`, `yBottom`, `propagationDirection`) produced in Task 5 match consumption in Task 6. `params` struct fields (`shockThresh`, `rxnThresh`, `whiteLevel`, `scanSmoothWin`) consistent between Tasks 3 and 6. `detect_fronts_in_frame`/`clean_front_line`/`overlay_fronts` signatures match their call sites. ✓
