# 2D Edge-Detection Spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small, visual experiment to evaluate 2D edge detection (Canny + Sobel gradient-magnitude) against the existing 1D step-height detector for locating the shock and (weak/oblique) reaction fronts.

**Architecture:** A pure `extract_first_two_edges` recovers shock/reaction semantics from a generic edge map (first darkening edge → shock, next brightening edge → reaction). `edge_map_2d` wraps MATLAB's gradient/Canny. `edge2d_experiment` ties them to the real `.dat` (background = frame 2) and renders comparison montages (Canny+2D fronts / gradient-magnitude / 1D detector) for visual evaluation.

**Tech Stack:** MATLAB R2024a (Image Processing Toolbox: `imgaussfilt`, `imgradientxy`, `edge`; `matlab.unittest`). MATLAB binary: `/Applications/MATLAB_R2024a.app/bin/matlab`.

---

## Conventions

- Run tests (from project root):
  ```bash
  /Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
  ```
  MATLAB takes ~30–60s to start; allow up to 180000 ms on every matlab command. `matlab -batch` exits non-zero if the assert fails.
- Source in project root; tests in `tests/`.
- This is an exploratory spike — keep it self-contained; do NOT modify the production pipeline (`auto_detect_shock_reaction.m`, `detect_fronts_in_frame.m`, etc.).
- Directional convention: walking in `scanDir`, the per-step intensity change ≈ `Gx*scanDir`. Darkening (shock) ⇒ `Gx*scanDir < 0`; brightening (reaction) ⇒ `Gx*scanDir > 0`.

---

## Task 1: `extract_first_two_edges` (pure, TDD)

**Files:**
- Create: `extract_first_two_edges.m`
- Test: `tests/test_extract_first_two_edges.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_extract_first_two_edges.m`:

```matlab
function tests = test_extract_first_two_edges
tests = functiontests(localfunctions);
end

function test_scan_right_to_left(t)
    % Walking R->L (scanDir=-1): shock = darkening (Gx>0 here) at col 15,
    % reaction = brightening (Gx<0) at col 8.
    W = 20; Gx = zeros(1,W); E = false(1,W);
    Gx(15) =  50; E(15) = true;   % shock edge
    Gx(8)  = -60; E(8)  = true;   % reaction edge
    [sx, rx] = extract_first_two_edges(Gx, E, 1, -1, 10);
    verifyEqual(t, sx, 15);
    verifyEqual(t, rx, 8);
end

function test_scan_left_to_right(t)
    % Walking L->R (scanDir=+1): shock = darkening (Gx<0) at col 5,
    % reaction = brightening (Gx>0) at col 12.
    W = 20; Gx = zeros(1,W); E = false(1,W);
    Gx(5)  = -50; E(5)  = true;
    Gx(12) =  60; E(12) = true;
    [sx, rx] = extract_first_two_edges(Gx, E, 1, +1, 10);
    verifyEqual(t, sx, 5);
    verifyEqual(t, rx, 12);
end

function test_no_edges_returns_nan(t)
    Gx = zeros(1,20); E = false(1,20);
    [sx, rx] = extract_first_two_edges(Gx, E, 1, -1, 10);
    verifyTrue(t, isnan(sx));
    verifyTrue(t, isnan(rx));
end

function test_minmag_rejects_weak_edges(t)
    W = 20; Gx = zeros(1,W); E = false(1,W);
    Gx(15) = 5; E(15) = true;     % below minMag=10
    [sx, rx] = extract_first_two_edges(Gx, E, 1, -1, 10);
    verifyTrue(t, isnan(sx));
    verifyTrue(t, isnan(rx));
end

function test_multiple_rows(t)
    W = 20; H = 3; Gx = zeros(H,W); E = false(H,W);
    Gx(:,15) =  50; E(:,15) = true;
    Gx(:,8)  = -60; E(:,8)  = true;
    [sx, rx] = extract_first_two_edges(Gx, E, 1:3, -1, 10);
    verifyEqual(t, sx, [15;15;15]);
    verifyEqual(t, rx, [8;8;8]);
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_extract_first_two_edges.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'extract_first_two_edges'`.

- [ ] **Step 3: Write the implementation**

Create `extract_first_two_edges.m`:

```matlab
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_extract_first_two_edges.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add extract_first_two_edges.m tests/test_extract_first_two_edges.m
git commit -m "feat: add extract_first_two_edges (shock/reaction from 2D edge map)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `edge_map_2d` (Canny + Sobel magnitude, smoke-tested)

**Files:**
- Create: `edge_map_2d.m`
- Test: `tests/test_edge_map_2d.m`

- [ ] **Step 1: Write the failing test**

Create `tests/test_edge_map_2d.m`:

```matlab
function tests = test_edge_map_2d
tests = functiontests(localfunctions);
end

function test_sizes_and_finds_vertical_step(t)
    img = zeros(20, 40); img(:, 21:end) = 100;   % vertical step between col 20 and 21
    [Gx, Gmag, E] = edge_map_2d(img, struct('gaussSigma',1));
    verifyEqual(t, size(Gx), size(img));
    verifyEqual(t, size(Gmag), size(img));
    verifyEqual(t, size(E), size(img));
    % strongest gradient column is near the step
    [~, pk] = max(sum(Gmag,1));
    verifyTrue(t, abs(pk - 20.5) <= 2);
    % Canny marks edges near the step
    verifyTrue(t, any(E(:)));
    verifyTrue(t, any(any(E(:, 18:23))));
end

function test_default_params_run(t)
    img = rand(15, 15) * 50;
    [Gx, Gmag, E] = edge_map_2d(img);   % no params -> defaults
    verifyEqual(t, size(Gx), size(img));
    verifyTrue(t, islogical(E));
    verifyTrue(t, all(Gmag(:) >= 0));
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_edge_map_2d.m'); assert(all([r.Passed]))"
```
Expected: FAIL — `Unrecognized function or variable 'edge_map_2d'`.

- [ ] **Step 3: Write the implementation**

Create `edge_map_2d.m`:

```matlab
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests/test_edge_map_2d.m'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add edge_map_2d.m tests/test_edge_map_2d.m
git commit -m "feat: add edge_map_2d (Sobel gradient + Canny edge map)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `edge2d_experiment` comparison script

**Files:**
- Create: `edge2d_experiment.m`

This is a visual experiment — verified by a headless parse check + the full suite, then the controller runs it on the real `.dat` and inspects the saved montage.

- [ ] **Step 1: Write the script**

Create `edge2d_experiment.m`:

```matlab
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
```

- [ ] **Step 2: Syntax-check headless**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); checkcode('edge2d_experiment.m'); disp('parsed ok')"
```
Expected: prints `parsed ok` (style warnings acceptable; fix only genuine syntax errors).

- [ ] **Step 3: Run the full suite (no regression)**

Run:
```bash
/Applications/MATLAB_R2024a.app/bin/matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```
Expected: PASS (all tests, including the two new test files).

- [ ] **Step 4: Commit**

```bash
git add edge2d_experiment.m
git commit -m "feat: add edge2d_experiment 2D-vs-1D comparison script

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Controller-run evaluation (not a subagent step)**

The controller runs `edge2d_experiment` on the real `.dat` — first a coarse scan to locate the wave / confirm `scanDir` and the `yRows` band, then a comparison across ~6 frames spanning early→late (where the reaction decouples) — and inspects the saved `edge2d_compare.png`. The generated PNG/`.fig` are scratch (gitignored pattern or removed), not committed.

---

## Self-Review (completed by plan author)

**Spec coverage:**
- `edge_map_2d` (Canny + Sobel magnitude) → Task 2. ✓
- `extract_first_two_edges` (first darkening = shock, next brightening = reaction; semantics preserved) → Task 1. ✓
- `edge2d_experiment` (background = frame 2; Canny / Gmag / 1D comparison montage; saved image) → Task 3. ✓
- Evaluation by viewing montages → Task 3 Step 5 (controller). ✓
- No production-pipeline changes; spike isolated. ✓

**Placeholder scan:** Tasks 1–3 contain complete code. No TBD/TODO.

**Type consistency:** `edge_map_2d` returns `[Gx, Gmag, E]`; `extract_first_two_edges(Gx, edgeMask, yRows, scanDir, minMag)` consumes `Gx` and `E`; `edge2d_experiment` calls both with matching argument order, plus `load_dat_video`/`dat_frame`/`detect_fronts_in_frame`/`overlay_fronts` per their existing signatures. Directional convention (`Gx*scanDir`) consistent between Task 1 code, its tests, and the spec.
```
