# Robust Detection v2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a band-based 2D detector + ROI + temporal prior as a switchable mode alongside the existing 1D step-height detector, with multi-frame tuning preview.

**Architecture:** Three new pure functions (`auto_roi_mask`, `detect_bands_in_frame`, `temporal_prior_refine`) form the band-detection core. `setup_detection_gui` gains a detector dropdown and ROI auto-detection + override clicks. `auto_detect_shock_reaction` branches on `setup.detectorMode`, carries a `prevCleaned` buffer between frames in `band2d`, and renders a multi-frame raw tuning preview. The 1D path stays as `step1d`.

**Tech Stack:** MATLAB R2024a (Image Processing Toolbox: `graythresh`, `imclose`, `imfill`, `bwconncomp`, `bwareaopen`, `imdilate`, `imgaussfilt`, `imgradientxy`; `matlab.unittest`). Binary: `/Applications/MATLAB_R2024a.app/bin/matlab`.

---

## Conventions

- Run full suite:
  ```bash
  /Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
  ```
  MATLAB ~30–60s start; allow up to 180000 ms.
- Source in project root; tests in `tests/`.
- Directional convention unchanged: `scanDir = +1` walks L→R (reverse of R→L propagation).

---

## Task 1: `auto_roi_mask` (pure, TDD)

**Files:**
- Create: `auto_roi_mask.m`
- Test: `tests/test_auto_roi_mask.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_auto_roi_mask.m`:

```matlab
function tests = test_auto_roi_mask
tests = functiontests(localfunctions);
end

function test_bright_disk_kept_corners_excluded(t)
    H = 100; W = 200;
    [X, Y] = meshgrid(1:W, 1:H);
    cx = W/2; cy = H/2; r = 40;
    backRef = zeros(H, W);
    backRef((X - cx).^2 + (Y - cy).^2 <= r^2) = 1.0;
    rng(0); backRef = backRef + 0.01 * randn(H, W);
    roi = auto_roi_mask(backRef);
    verifyEqual(t, size(roi), [H W]);
    verifyTrue(t, roi(round(cy), round(cx)));   % center of disk
    verifyFalse(t, roi(1, 1));                  % far corner outside disk
    verifyFalse(t, roi(end, end));
end

function test_all_dark_returns_false_mask(t)
    roi = auto_roi_mask(zeros(20, 30));
    verifyFalse(t, any(roi(:)));
    verifyEqual(t, size(roi), [20 30]);
end

function test_returns_logical(t)
    roi = auto_roi_mask(rand(15, 20));
    verifyTrue(t, islogical(roi));
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_auto_roi_mask.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'auto_roi_mask'`.

- [ ] **Step 3: Write the implementation**

Create `auto_roi_mask.m`:

```matlab
function roi = auto_roi_mask(backRef, params)
%AUTO_ROI_MASK Illuminated-test-section ROI from a background frame.
%   roi = auto_roi_mask(backRef)
%   roi = auto_roi_mask(backRef, params)
%   params: dilatePx (default 3), minFrac (default 0.2 — keep components
%           covering at least this fraction of the largest one).
%   Otsu threshold on a normalized backRef, then close, fill holes,
%   area-filter, dilate. An all-dark / constant input returns all-false.
    if nargin < 2 || isempty(params), params = struct(); end
    if ~isfield(params,'dilatePx') || isempty(params.dilatePx), params.dilatePx = 3; end
    if ~isfield(params,'minFrac')  || isempty(params.minFrac),  params.minFrac  = 0.2; end

    bk = double(backRef);
    if max(bk(:)) <= min(bk(:))
        roi = false(size(bk)); return;
    end
    g = mat2gray(bk);
    t = graythresh(g);
    if t <= 0
        roi = false(size(bk)); return;
    end
    m = g >= t;
    m = imclose(m, strel('disk', 2));
    m = imfill(m, 'holes');
    cc = bwconncomp(m);
    if cc.NumObjects == 0
        roi = false(size(m)); return;
    end
    areas = cellfun(@numel, cc.PixelIdxList);
    keep  = areas >= params.minFrac * max(areas);
    m2 = false(size(m));
    for i = 1:cc.NumObjects
        if keep(i), m2(cc.PixelIdxList{i}) = true; end
    end
    if params.dilatePx > 0
        m2 = imdilate(m2, strel('disk', round(params.dilatePx)));
    end
    roi = m2;
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_auto_roi_mask.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add auto_roi_mask.m tests/test_auto_roi_mask.m
git commit -m "feat: add auto_roi_mask (Otsu-based illuminated-region detector)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `detect_bands_in_frame` (pure, TDD)

**Files:**
- Create: `detect_bands_in_frame.m`
- Test: `tests/test_detect_bands_in_frame.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_detect_bands_in_frame.m`:

```matlab
function tests = test_detect_bands_in_frame
tests = functiontests(localfunctions);
end

function img = makeBandFrame()
    H = 50; W = 200;
    img = zeros(H, W);
    img(:, 30:50) = -100;   % dark band (shock side)
    img(:, 70:90) = +100;   % bright band (reaction side)
end

function test_detects_band_leading_edges(t)
    proc = makeBandFrame();
    [~, Gmag, ~] = edge_map_2d(proc, struct('gaussSigma', 1));
    H = size(proc, 1); W = size(proc, 2);
    roi = true(H, W);
    yRows = 10:40;
    params = struct('magThreshFrac', 0.9, 'intensitySigma', 5, 'deadband', 0, 'minArea', 5);
    [sx, rx] = detect_bands_in_frame(proc, Gmag, yRows, +1, roi, params);
    verifyFalse(t, any(isnan(sx)));
    verifyFalse(t, any(isnan(rx)));
    verifyTrue(t, all(abs(sx - 30) <= 3));   % shock = dark band leading edge
    verifyTrue(t, all(abs(rx - 70) <= 3));   % reaction = bright band leading edge
end

function test_roi_blocks_bands_outside(t)
    proc = makeBandFrame();
    [~, Gmag, ~] = edge_map_2d(proc, struct('gaussSigma', 1));
    H = size(proc, 1); W = size(proc, 2);
    roi = false(H, W); roi(:, 95:end) = true;   % ROI past both bands
    yRows = 10:40;
    params = struct('magThreshFrac', 0.9, 'intensitySigma', 5, 'deadband', 0, 'minArea', 5);
    [sx, rx] = detect_bands_in_frame(proc, Gmag, yRows, +1, roi, params);
    verifyTrue(t, all(isnan(sx)));
    verifyTrue(t, all(isnan(rx)));
end

function test_blank_frame_returns_all_nan(t)
    proc = zeros(50, 200);
    [~, Gmag, ~] = edge_map_2d(proc, struct('gaussSigma', 1));
    roi = true(50, 200);
    [sx, rx] = detect_bands_in_frame(proc, Gmag, 10:40, +1, roi, struct());
    verifyTrue(t, all(isnan(sx)));
    verifyTrue(t, all(isnan(rx)));
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_detect_bands_in_frame.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'detect_bands_in_frame'`.

- [ ] **Step 3: Write the implementation**

Create `detect_bands_in_frame.m`:

```matlab
function [shockX, rxnX, shockMask, rxnMask] = detect_bands_in_frame( ...
    proc, Gmag, yRows, scanDir, roiMask, params)
%DETECT_BANDS_IN_FRAME Band-based shock/reaction detection.
%   Strong-gradient pixels (within roiMask) are split into a DARK-region band
%   (shock) and a BRIGHT-region band (reaction) by a smoothed proc, then each
%   row's interface is the LEADING band pixel in scanDir.
%
%   proc, Gmag : HxW double (background-subtracted frame and its gradient magnitude)
%   yRows      : row indices to scan
%   scanDir    : +1 = scan left->right (reverse of right->left propagation)
%   roiMask    : HxW logical; only ROI pixels are eligible
%   params     : magThreshFrac (default 0.95), intensitySigma (5),
%                deadband (0), minArea (30)
    if nargin < 6 || isempty(params), params = struct(); end
    if ~isfield(params,'magThreshFrac') || isempty(params.magThreshFrac), params.magThreshFrac = 0.95; end
    if ~isfield(params,'intensitySigma') || isempty(params.intensitySigma), params.intensitySigma = 5; end
    if ~isfield(params,'deadband') || isempty(params.deadband), params.deadband = 0; end
    if ~isfield(params,'minArea')  || isempty(params.minArea),  params.minArea  = 30; end

    [H, W] = size(proc);
    n = numel(yRows);
    shockX = nan(n, 1);
    rxnX   = nan(n, 1);
    shockMask = false(H, W);
    rxnMask   = false(H, W);

    rowsMask = false(H, W); rowsMask(yRows, :) = true;
    sample = Gmag(rowsMask & roiMask);
    if isempty(sample) || ~any(sample > 0), return; end
    sv  = sort(sample(:));
    idx = max(1, round(params.magThreshFrac * numel(sv)));
    magThresh = sv(idx);

    Iblur = imgaussfilt(proc, params.intensitySigma);
    strong = (Gmag >= magThresh) & roiMask;
    shockMask = strong & (Iblur < -params.deadband);
    rxnMask   = strong & (Iblur >  params.deadband);
    if params.minArea > 0
        shockMask = bwareaopen(shockMask, params.minArea);
        rxnMask   = bwareaopen(rxnMask,   params.minArea);
    end

    if scanDir > 0, cols = 1:W; else, cols = W:-1:1; end
    for i = 1:n
        y = yRows(i);
        shockX(i) = leadingX(shockMask(y, cols), cols);
        rxnX(i)   = leadingX(rxnMask(y, cols),  cols);
    end
end

function x = leadingX(maskRowWalk, cols)
    j = find(maskRowWalk, 1, 'first');
    if isempty(j), x = NaN; else, x = cols(j); end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_detect_bands_in_frame.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add detect_bands_in_frame.m tests/test_detect_bands_in_frame.m
git commit -m "feat: add detect_bands_in_frame (band-based 2D detector with ROI)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `temporal_prior_refine` (pure, TDD)

**Files:**
- Create: `temporal_prior_refine.m`
- Test: `tests/test_temporal_prior_refine.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_temporal_prior_refine.m`:

```matlab
function tests = test_temporal_prior_refine
tests = functiontests(localfunctions);
end

function test_refines_nan_row_using_prior(t)
    H = 10; W = 100;
    yRows = 3:7;
    Gmag = zeros(H, W);
    Iblur = ones(H, W);                     % default bright
    Gmag(5, 52) = 1000;                     % strong gradient at row 5, col 52
    Iblur(5, 52) = -50;                     % dark region for shock
    shockRaw = [50; 50; NaN; 50; 50];
    rxnRaw   = nan(5, 1);
    prevCleaned = struct('shock', [50;50;50;50;50], 'rxn', nan(5,1));
    params = struct('useShockPrior',true,'useRxnPrior',false, ...
        'searchHalfWidth',10,'deviationTol',4,'deadband',0);
    [sOut, rOut] = temporal_prior_refine(shockRaw, rxnRaw, prevCleaned, ...
        Gmag, Iblur, yRows, params);
    verifyEqual(t, sOut, [50; 50; 52; 50; 50]);
    verifyTrue(t, all(isnan(rOut)));
end

function test_disabled_prior_passes_through(t)
    yRows = 1:3;
    Gmag = zeros(5, 50);
    Iblur = zeros(5, 50);
    shockRaw = [10; NaN; 12];
    rxnRaw   = [20; 21; NaN];
    prevCleaned = struct('shock', [10;10;10], 'rxn', [20;20;20]);
    params = struct('useShockPrior',false,'useRxnPrior',false);
    [sOut, rOut] = temporal_prior_refine(shockRaw, rxnRaw, prevCleaned, ...
        Gmag, Iblur, yRows, params);
    verifyTrue(t, isequaln(sOut, shockRaw));
    verifyTrue(t, isequaln(rOut, rxnRaw));
end

function test_consistent_current_value_unchanged(t)
    yRows = 1:3;
    Gmag = ones(5, 50) * 100;
    Iblur = -ones(5, 50);
    shockRaw = [51; 52; 49];                % all within tol of predicted 50
    rxnRaw = nan(3, 1);
    prevCleaned = struct('shock', [50;50;50], 'rxn', nan(3,1));
    params = struct('useShockPrior',true,'useRxnPrior',false, ...
        'searchHalfWidth',10,'deviationTol',4,'deadband',0);
    [sOut, ~] = temporal_prior_refine(shockRaw, rxnRaw, prevCleaned, ...
        Gmag, Iblur, yRows, params);
    verifyEqual(t, sOut, shockRaw);
end

function test_no_candidate_in_window_keeps_nan(t)
    yRows = 1:3;
    Gmag = zeros(5, 100);                   % no strong gradients anywhere
    Iblur = -ones(5, 100);
    shockRaw = [NaN; NaN; NaN];
    prevCleaned = struct('shock', [50;50;50], 'rxn', nan(3,1));
    params = struct('useShockPrior',true,'useRxnPrior',false, ...
        'searchHalfWidth',10,'deviationTol',4,'deadband',0);
    [sOut, ~] = temporal_prior_refine(shockRaw, nan(3,1), prevCleaned, ...
        Gmag, Iblur, yRows, params);
    verifyTrue(t, all(isnan(sOut)));
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_temporal_prior_refine.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'temporal_prior_refine'`.

- [ ] **Step 3: Write the implementation**

Create `temporal_prior_refine.m`:

```matlab
function [shockOut, rxnOut] = temporal_prior_refine( ...
    shockRawNow, rxnRawNow, prevCleaned, Gmag, Iblur, yRows, params)
%TEMPORAL_PRIOR_REFINE Rescue per-row detections using the CLEANED previous-
%   frame curve. For each enabled front, predict each row's x as
%   prevCleaned.<front>(row) + medianDisplacement (from one earlier frame if
%   present); if the current raw value is NaN or deviates from the prediction
%   by more than deviationTol, search [pred-W, pred+W] for the strongest Gmag
%   pixel also in the correct brightness region (dark for shock / bright for
%   reaction) — no global magThresh applied within the window. If a toggle is
%   off, that front passes through unchanged.
%
%   shockRawNow, rxnRawNow : numel(yRows)x1 current raw detections
%   prevCleaned : struct with .shock, .rxn (numel(yRows)x1, NaN allowed) and
%                 optionally .shockPrev, .rxnPrev (one earlier cleaned frame)
%   Gmag, Iblur : HxW (Iblur = smoothed proc used for brightness labeling)
%   yRows       : row indices the per-row arrays correspond to
%   params      : useShockPrior (true), useRxnPrior (false),
%                 searchHalfWidth (10), deviationTol (4), deadband (0)
    if ~isfield(params,'useShockPrior') || isempty(params.useShockPrior), params.useShockPrior = true; end
    if ~isfield(params,'useRxnPrior')   || isempty(params.useRxnPrior),   params.useRxnPrior   = false; end
    if ~isfield(params,'searchHalfWidth') || isempty(params.searchHalfWidth), params.searchHalfWidth = 10; end
    if ~isfield(params,'deviationTol')  || isempty(params.deviationTol),  params.deviationTol  = 4; end
    if ~isfield(params,'deadband')      || isempty(params.deadband),      params.deadband      = 0; end

    shockOut = shockRawNow;
    rxnOut   = rxnRawNow;

    if params.useShockPrior && isfield(prevCleaned,'shock') && ~isempty(prevCleaned.shock) && ~all(isnan(prevCleaned.shock))
        shockOut = refineOne(shockRawNow, prevCleaned.shock, ...
            optField(prevCleaned,'shockPrev'), Gmag, Iblur, yRows, 'dark', params);
    end
    if params.useRxnPrior && isfield(prevCleaned,'rxn') && ~isempty(prevCleaned.rxn) && ~all(isnan(prevCleaned.rxn))
        rxnOut = refineOne(rxnRawNow, prevCleaned.rxn, ...
            optField(prevCleaned,'rxnPrev'), Gmag, Iblur, yRows, 'bright', params);
    end
end

function v = optField(s, f)
    if isfield(s, f), v = s.(f); else, v = []; end
end

function out = refineOne(rawNow, prevC, prev2C, Gmag, Iblur, yRows, side, params)
    n = numel(rawNow);
    out = rawNow;
    [H, W] = size(Gmag);
    if ~isempty(prev2C) && numel(prev2C) == numel(prevC)
        d  = prevC - prev2C;
        dx = median(d(~isnan(d)));
        if isnan(dx), dx = 0; end
    else
        dx = 0;
    end
    for i = 1:n
        if isnan(prevC(i)), continue; end
        pred = prevC(i) + dx;
        cur  = rawNow(i);
        if ~isnan(cur) && abs(cur - pred) <= params.deviationTol
            continue;
        end
        lo = max(1, round(pred - params.searchHalfWidth));
        hi = min(W, round(pred + params.searchHalfWidth));
        if lo > hi, continue; end
        y = yRows(i);
        if y < 1 || y > H, continue; end
        g  = Gmag(y, lo:hi);
        Ib = Iblur(y, lo:hi);
        if strcmp(side, 'dark')
            ok = Ib < -params.deadband;
        else
            ok = Ib >  params.deadband;
        end
        candMag = g;
        candMag(~ok) = -Inf;
        [bestVal, j] = max(candMag);
        if isinf(bestVal) || bestVal <= 0, continue; end
        out(i) = lo + j - 1;
    end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_temporal_prior_refine.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add temporal_prior_refine.m tests/test_temporal_prior_refine.m
git commit -m "feat: add temporal_prior_refine (rescue from cleaned previous curve)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Setup GUI — detector mode + ROI

**Files:**
- Modify (full replacement): `setup_detection_gui.m`

Cannot be run headless; verified by `checkcode` + the user's manual walkthrough.

- [ ] **Step 1: Replace `setup_detection_gui.m`** with EXACTLY this content:

```matlab
function setup = setup_detection_gui(src, defaultFrame)
%SETUP_DETECTION_GUI Direction, detector mode, calibration, background, ROI, frame range.
%   setup fields (or [] if cancelled):
%     propagationDirection ('LtoR'|'RtoL'), scanDir (+1|-1),
%     detectorMode ('band2d'|'step1d'),
%     calibFrame, yTop, yBottom, pixelHeight, yRows, chamberWidth_in, mperpix,
%     backgroundFrame, roiMask (HxW logical), roiClipLeft, roiClipRight,
%     startFrame, endFrame
    setup = [];
    totalFrames = src.NumFrames;
    if nargin < 2 || isempty(defaultFrame)
        defaultFrame = round(totalFrames/2);
    end
    frameNumber = max(1, min(defaultFrame, totalFrames));

    yTop = []; yBottom = []; calibFrame = [];
    startFrame = []; endFrame = []; chamberWidth_in = []; backIdx = [];
    roiAuto = []; roiClipLeft = []; roiClipRight = [];
    calibMode = false; calibClicks = []; roiPickMode = '';
    doneFlag = false; cancelled = false;
    hCalibLines = gobjects(0); hRoiLines = gobjects(0);

    hFig = figure('Name','Detection Setup','NumberTitle','off', ...
        'WindowState','maximized','Color','w','CloseRequestFcn',@cbClose);
    hAx = axes('Parent',hFig,'Units','normalized','Position',[0.02 0.22 0.96 0.76]);
    axis(hAx,'off');
    hImg = imshow(dat_frame(src,frameNumber), [], 'Parent', hAx);
    hold(hAx,'on');

    set(hFig,'Pointer','custom','PointerShapeCData',NaN(16,16),'PointerShapeHotSpot',[8 8]);
    crossHair = createCrossHair(hFig);
    set(hFig,'WindowButtonMotionFcn', @(s,e) updateCrossHair(hFig, crossHair));

    uicontrol(hFig,'Style','text','String','Direction:','Units','normalized', ...
        'Position',[0.02 0.135 0.07 0.035],'BackgroundColor','w','FontSize',10);
    hDir = uicontrol(hFig,'Style','popupmenu','String',{'Left to Right','Right to Left'}, ...
        'Units','normalized','Position',[0.09 0.135 0.12 0.045],'FontSize',10);
    uicontrol(hFig,'Style','text','String','Detector:','Units','normalized', ...
        'Position',[0.23 0.135 0.07 0.035],'BackgroundColor','w','FontSize',10);
    hMode = uicontrol(hFig,'Style','popupmenu','String',{'2D bands','1D step-height'}, ...
        'Units','normalized','Position',[0.30 0.135 0.12 0.045],'FontSize',10);

    uicontrol(hFig,'Style','pushbutton','String','< Prev','Units','normalized', ...
        'Position',[0.02 0.06 0.05 0.05],'Callback',@(s,e) changeFrame(-1));
    uicontrol(hFig,'Style','pushbutton','String','Next >','Units','normalized', ...
        'Position',[0.08 0.06 0.05 0.05],'Callback',@(s,e) changeFrame(1));
    uicontrol(hFig,'Style','pushbutton','String','<< -10','Units','normalized', ...
        'Position',[0.14 0.06 0.05 0.05],'Callback',@(s,e) changeFrame(-10));
    uicontrol(hFig,'Style','pushbutton','String','+10 >>','Units','normalized', ...
        'Position',[0.20 0.06 0.05 0.05],'Callback',@(s,e) changeFrame(10));
    uicontrol(hFig,'Style','pushbutton','String','Set Start','Units','normalized', ...
        'Position',[0.27 0.06 0.07 0.05],'Callback',@cbSetStart);
    uicontrol(hFig,'Style','pushbutton','String','Set End','Units','normalized', ...
        'Position',[0.35 0.06 0.07 0.05],'Callback',@cbSetEnd);
    uicontrol(hFig,'Style','pushbutton','String','Set Background','Units','normalized', ...
        'Position',[0.43 0.06 0.10 0.05],'Callback',@cbSetBackground);
    uicontrol(hFig,'Style','pushbutton','String','Calibrate Width','Units','normalized', ...
        'Position',[0.54 0.06 0.10 0.05],'Callback',@cbCalibrate);
    uicontrol(hFig,'Style','pushbutton','String','Set ROI Left','Units','normalized', ...
        'Position',[0.65 0.06 0.09 0.05],'Callback',@(s,e) cbSetRoi('left'));
    uicontrol(hFig,'Style','pushbutton','String','Set ROI Right','Units','normalized', ...
        'Position',[0.75 0.06 0.09 0.05],'Callback',@(s,e) cbSetRoi('right'));
    uicontrol(hFig,'Style','pushbutton','String','DONE','Units','normalized', ...
        'Position',[0.86 0.06 0.10 0.05],'FontWeight','bold','Callback',@cbDone);

    hStatus = uicontrol(hFig,'Style','text','Units','normalized', ...
        'Position',[0.02 0.005 0.94 0.045],'BackgroundColor','w','FontSize',9, ...
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
    if get(hMode,'Value') == 1
        setup.detectorMode = 'band2d';
    else
        setup.detectorMode = 'step1d';
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
    colMask = false(1, src.Width);
    colMask(round(roiClipLeft):round(roiClipRight)) = true;
    setup.roiMask = roiAuto & repmat(colMask, src.Height, 1);
    setup.roiClipLeft  = round(roiClipLeft);
    setup.roiClipRight = round(roiClipRight);

    if ishandle(hFig), delete(hFig); end

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
    function cbSetBackground(~,~)
        backIdx = frameNumber;
        backRef = dat_frame(src, backIdx);
        try
            roiAuto = auto_roi_mask(backRef);
        catch
            roiAuto = true(src.Height, src.Width);
        end
        cols = find(any(roiAuto, 1));
        if isempty(cols)
            roiClipLeft = 1; roiClipRight = src.Width;
            roiAuto = true(src.Height, src.Width);
        else
            roiClipLeft = cols(1); roiClipRight = cols(end);
        end
        drawRoiLines();
        refreshStatus();
    end
    function cbCalibrate(~,~)
        calibMode = true; roiPickMode = ''; calibClicks = [];
        delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
        set(hStatus,'String','CALIBRATE: click the TOP wall, then the BOTTOM wall.');
    end
    function cbSetRoi(side)
        if isempty(roiAuto)
            set(hStatus,'String','ERROR: Set Background first (auto-ROI needs it).'); return;
        end
        calibMode = false; roiPickMode = side;
        set(hStatus,'String', sprintf('Click a column to set the ROI %s boundary.', side));
    end
    function cbClick(~,~)
        if ~strcmp(get(hFig,'SelectionType'),'normal'), return; end
        if calibMode
            cp = get(hAx,'CurrentPoint'); yClick = cp(1,2);
            calibClicks(end+1) = yClick; %#ok<AGROW>
            hCalibLines(end+1) = plot(hAx, get(hAx,'XLim'), [yClick yClick], ...
                'y-', 'LineWidth', 1.2, 'HitTest','off','PickableParts','none'); %#ok<AGROW>
            if numel(calibClicks) == 2
                yTop = calibClicks(1); yBottom = calibClicks(2);
                calibFrame = frameNumber;
                answer = inputdlg('Actual chamber width (inches):','Chamber Width', ...
                    [1 40], {'2'});
                if isempty(answer), w = NaN; else, w = str2double(answer{1}); end
                if ~isfinite(w) || w <= 0
                    yTop=[]; yBottom=[]; calibFrame=[];
                    delete(hCalibLines(ishandle(hCalibLines))); hCalibLines = gobjects(0);
                    set(hStatus,'String','Calibration cancelled — click Calibrate again.');
                else
                    chamberWidth_in = w;
                end
                calibMode = false;
                refreshStatus();
            end
            return;
        end
        if ~isempty(roiPickMode)
            cp = get(hAx,'CurrentPoint');
            xClick = max(1, min(src.Width, round(cp(1,1))));
            if strcmp(roiPickMode,'left')
                roiClipLeft = xClick;
            else
                roiClipRight = xClick;
            end
            if roiClipLeft > roiClipRight
                tmp = roiClipLeft; roiClipLeft = roiClipRight; roiClipRight = tmp;
            end
            roiPickMode = '';
            drawRoiLines();
            refreshStatus();
        end
    end
    function drawRoiLines()
        delete(hRoiLines(ishandle(hRoiLines))); hRoiLines = gobjects(0);
        if isempty(roiClipLeft) || isempty(roiClipRight), return; end
        yl = get(hAx,'YLim');
        hRoiLines(end+1) = plot(hAx, [roiClipLeft roiClipLeft], yl, ...
            'g-', 'LineWidth', 1.2, 'HitTest','off','PickableParts','none'); %#ok<AGROW>
        hRoiLines(end+1) = plot(hAx, [roiClipRight roiClipRight], yl, ...
            'g-', 'LineWidth', 1.2, 'HitTest','off','PickableParts','none'); %#ok<AGROW>
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
        if isempty(roiAuto) || isempty(roiClipLeft) || isempty(roiClipRight)
            set(hStatus,'String','ERROR: ROI not set (re-Set Background).'); return;
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
            ['Frame %d/%d  |  Start: %s  End: %s  Bg: %s  |  yTop: %s yBot: %s  W(in): %s  ' ...
             '|  ROI cols: [%s, %s]'], ...
            frameNumber, totalFrames, num2str(startFrame), num2str(endFrame), num2str(backIdx), ...
            num2str(yTop), num2str(yBottom), num2str(chamberWidth_in), ...
            num2str(roiClipLeft), num2str(roiClipRight)));
    end

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

- [ ] **Step 3: Commit**

```bash
git add setup_detection_gui.m
git commit -m "feat: add detector-mode + ROI controls to setup GUI

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Orchestrator — mode switch, prev-state, multi-frame tuning

**Files:**
- Modify (full replacement): `auto_detect_shock_reaction.m`

- [ ] **Step 1: Replace `auto_detect_shock_reaction.m`** with EXACTLY this content:

```matlab
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
    'deadband',deadband,'minArea',minArea);
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
                answer = inputdlg({'magThreshFrac (0..1)','intensitySigma','deadband','minArea'}, ...
                    'Adjust band2d params', [1 30], ...
                    {num2str(paramsBand.magThreshFrac), num2str(paramsBand.intensitySigma), ...
                     num2str(paramsBand.deadband), num2str(paramsBand.minArea)});
                if ~isempty(answer)
                    v = cellfun(@str2double, answer);
                    if all(isfinite(v))
                        paramsBand.magThreshFrac  = max(0, min(1, v(1)));
                        paramsBand.intensitySigma = max(0.1, v(2));
                        paramsBand.deadband       = v(3);
                        paramsBand.minArea        = max(1, round(v(4)));
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
```

- [ ] **Step 2: Syntax-check headless + full suite**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); checkcode('auto_detect_shock_reaction.m'); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```
Expected: `parsed ok` (style warnings acceptable) and all tests pass (the new test files for Tasks 1–3 plus the existing suite).

- [ ] **Step 3: Commit**

```bash
git add auto_detect_shock_reaction.m
git commit -m "feat: orchestrator mode switch + multi-frame tuning + temporal prior

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Cleanup superseded spike files + update docs

**Files:**
- Delete (untracked): `extract_bands.m`, `edge2d_bands_experiment.m`
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: Remove the superseded spike scratch**

```bash
cd "/Users/dijialiu/Desktop/Research/MATLAB/Shock_Reaction_Detection_in_Experiments"
rm -f extract_bands.m edge2d_bands_experiment.m edge2d_bands2.png edge2d_late.png
```
(These files are untracked; this removes them from the working tree only.)

- [ ] **Step 2: Update `README.md`**

Make these surgical edits to `README.md` (preserve existing structure/tone):
- **Workflow / Setup window**: add **Detector** dropdown (`2D bands` default / `1D step-height`) and **Set ROI Left**/**Set ROI Right** buttons; mention the ROI is auto-detected after Set Background and displayed as green vertical lines.
- **How detection works**: in addition to the existing 1D paragraph, add: "**2D bands (default).** Compute the gradient magnitude of the background-subtracted frame; the strong-edge pixels inside the ROI are split into a *dark-inside* band (shock, red) and a *bright-inside* band (reaction, cyan) by a smoothed intensity. Each row's interface is the **leading band pixel in the scan direction**. A **temporal prior** uses the cleaned previous-frame curve to rescue rows where the local edge is weak (applied to the shock by default; toggleable per front)."
- **Tuning table**: add rows for `magThreshFrac`, `intensitySigma`, `deadband`, `minArea`, `gaussSigma`, `useShockPrior` (default true), `useRxnPrior` (default false), `searchHalfWidth`, `deviationTol`, `nTuningFrames` (default 6).
- **Outputs**: add to the `Detection` table: `detectorMode`, `roiMask`, `roiClipLeft`, `roiClipRight`; note `thresholds` now also includes the band+prior params.
- **Files**: add rows for `auto_roi_mask.m`, `detect_bands_in_frame.m`, `temporal_prior_refine.m`, `edge_map_2d.m`. Update `setup_detection_gui.m` row to mention the detector mode and ROI controls.
- **Tests count**: the suite gains ~10 tests across the three new pure functions; update "All N tests should pass" to reflect the new count after the suite is run (state "22+" or the actual count from the implementer's run).

- [ ] **Step 3: Update `CLAUDE.md`**

Make these surgical edits to `CLAUDE.md`:
- **Architecture & data flow**: add `auto_roi_mask.m`, `detect_bands_in_frame.m`, `temporal_prior_refine.m`, `edge_map_2d.m` to the diagram; note the orchestrator branches on `setup.detectorMode` (`'band2d'` default, `'step1d'` legacy).
- **Key conventions**: add "**Detector mode** is chosen in the setup GUI (`band2d`/`step1d`). In `band2d`: detection runs on a Gmag strong-edge mask intersected with `roiMask`, split into a dark-region shock band and a bright-region reaction band, and the per-row interface is the **leading band pixel in `scanDir`**." And: "**Temporal prior** uses the *cleaned* previous-frame curve as the prediction basis (prevents spike propagation). Default: shock-on, reaction-off."
- **The `setup` struct contract**: add `detectorMode`, `roiMask`, `roiClipLeft`, `roiClipRight`.
- **The `Detection` struct contract**: add `detectorMode`, `roiMask`, `roiClipLeft`, `roiClipRight`; note `thresholds` also includes the band+prior params.
- **Where to make common changes**: add a row for the band detector → `detect_bands_in_frame.m`, ROI → `auto_roi_mask.m`, temporal prior → `temporal_prior_refine.m`.
- **Gotchas**: add "The temporal prior is applied **in the batch run only**, not in the tuning preview, so tuning shows raw per-frame behavior."

- [ ] **Step 4: Sanity check + full suite**

```bash
cd "/Users/dijialiu/Desktop/Research/MATLAB/Shock_Reaction_Detection_in_Experiments"
grep -c "detect_bands_in_frame" README.md CLAUDE.md
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```
Expected: both grep counts > 0; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: README + CLAUDE.md for detection v2 (bands + ROI + temporal prior)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- `auto_roi_mask` (Otsu + close + fill + area filter + dilate) → Task 1. ✓
- `detect_bands_in_frame` (strong-edge ∧ ROI, brightness-labeled bands, leading edge in scanDir) → Task 2. ✓
- `temporal_prior_refine` (cleaned previous curve + median displacement + local search; toggleable per front) → Task 3. ✓
- Setup GUI: detector dropdown + ROI auto-detect on Set Background + Set ROI Left/Right overrides + validation → Task 4. ✓
- Orchestrator: mode switch, prev-state buffer, multi-frame raw tuning preview, struct additions → Task 5. ✓
- Spline / sectioning explicitly out of scope. ✓
- 1D detector kept as a switchable mode. ✓
- Docs updated. ✓

**Placeholder scan:** Tasks 1–5 contain complete code. Task 6 has explicit, itemized doc edits (no code) — appropriate for documentation prose. No TBD/TODO.

**Type consistency:** `detect_bands_in_frame(proc, Gmag, yRows, scanDir, roiMask, params)` consistent across Tasks 2 and 5. `temporal_prior_refine(shockRaw, rxnRaw, prevCleaned, Gmag, Iblur, yRows, params)` consistent across Tasks 3 and 5. `prevCleaned` struct fields `.shock/.rxn/.shockPrev/.rxnPrev` consistent. Setup struct adds `detectorMode, roiMask, roiClipLeft, roiClipRight` — produced in Task 4, consumed in Task 5. `Detection` struct field names match the spec.
