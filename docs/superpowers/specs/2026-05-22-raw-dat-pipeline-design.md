# Spec 1 — Raw `.dat` Pipeline + Background Removal + 16-bit Detection

**Date:** 2026-05-22
**Status:** Approved (pending spec review)
**Relationship:** Foundation for a later **Spec 2** (sharp-turn sectioning + per-section
spline fitting), which layers on this spec's detection output.

## Purpose

Replace the pre-processed 8-bit AVI input with the **raw 16-bit `.dat`** as the
sole data source, do **background removal in-house** on the linear data, and make
the detection threshold **independent of the smoothing window**. Cleaner source
data and a physically-meaningful threshold should markedly improve shock/reaction
detection.

## Background & motivation

- The existing pipeline reads a pre-processed AVI produced by
  `SchlierenVideoProcessing_avi.m`: `processed = frame − backRef + 128`, then an
  optional sigmoid contrast stretch `255/(1+exp(−(x−128)/sig))`, clamped to 8-bit.
  Both the 8-bit quantization and the sigmoid compress exactly the gradients the
  detector relies on.
- The raw `.dat` is **16-bit linear** (10-bit sensor data scaled into the full
  16-bit range; values to ~65504). Detecting on it preserves edge contrast and
  lets us control background removal.
- The current per-pixel gradient (`g = diff(v)` of the smoothed profile) couples
  smoothing to threshold: a step of height `H` smoothed over `W` pixels yields a
  per-pixel slope ≈ `H/W`, so increasing `scanSmoothWin` forces `shockThresh`
  down. Users hit this directly when tuning.

## `.dat` format (verified empirically)

Reading the sample `.dat` as **16-bit, 400×250, contiguous frames after a
6336-byte header** produces a clean schlieren image; the 8-bit/256-frame
interpretation is noise. File size `25,606,336 B = 6336 + 400·250·2·128`.

- `headerBytes = 6336`, `width = 400`, `height = 250`, `dtype = 'uint16'`,
  little-endian, **no per-frame headers**.
- `NumFrames` is **inferred** from file size: `(bytes − headerBytes)/(W·H·2)` → 128.
- Orientation: read the flat `uint16` stream, reshape to `[W H N]`, then transpose
  each frame to `[H W]` (validated against the rendered image).
- **Camera (informational):** header strings (`HSC3`, `BFP`, `duty80`, serial
  `I778062F0248`, pixel-gain table `W003232-002048_BFP.pgt`) and the 400×250 /
  256-frame buffer indicate a **Shimadzu HPV-X/X2-class** high-speed camera.
  Authoritative header-field parsing would need Shimadzu's format spec; we don't
  require it — size inference plus overridable constants suffice.

## Decisions (from brainstorming)

- **Data source:** `.dat` only; AVI support dropped.
- **Background:** user scrubs to a clean pre-detonation frame and clicks **Set
  Background** in the setup GUI; subtract it **linearly** (16-bit signed), no
  `+128`/sigmoid. **Detection runs on the background-subtracted image**, so
  `whiteLevel` is in subtracted-count units.
- **Gradient measure:** decoupled **step-height** over a fixed span `gradSpan`
  (`L`). `shockThresh`/`rxnThresh` are brightness changes in 16-bit counts over
  `L` px; `scanSmoothWin` becomes pure denoising.
- **Edge position:** report the **single steepest pixel within the flagged span**
  (~1px localization regardless of span/smoothing).
- **Sequencing:** this is Spec 1; spline/sectioning is Spec 2.

## File structure

| File | Change | Tested |
|------|--------|--------|
| `load_dat_video.m` | **new** — read `.dat` into a frame source | unit |
| `dat_frame.m` | **new** — accessor: `f = dat_frame(src, idx)` (2-D double) | via reader test |
| `detect_fronts_in_frame.m` | **modified** — step-height gradient + steepest-pixel localization | unit |
| `setup_detection_gui.m` | **modified** — `.dat` source + Set Background; 16-bit display | manual |
| `auto_detect_shock_reaction.m` | **modified** — `.dat` flow, background subtraction, 16-bit, struct fields | manual/integration |
| `clean_front_line.m` | **unchanged** | existing |
| `overlay_fronts.m` | **unchanged** | existing |

The pure functions stay reusable; `detect_fronts_in_frame` keeps taking a 2-D
image and returns `x(y)` per front, so its boundary is unchanged.

## Component designs

### `load_dat_video.m`

```
src = load_dat_video(path, fmt)
```

- `fmt` is an optional struct; defaults: `headerBytes=6336`, `width=400`,
  `height=250`, `dtype='uint16'`, `byteOrder='l'`.
- Reads the whole pixel payload once; computes
  `nFrames = (fileBytes − headerBytes)/(width·height·bytesPerPixel)`.
- **Errors** if `nFrames` is not a positive integer (guards a wrong format).
- Stores frames as a `[H W N]` array (transpose-per-frame applied at read).
- Returns `src` with fields `.Width .Height .NumFrames .Data .fmt .filePath`.

`dat_frame.m`:
```
f = dat_frame(src, idx)   % returns double(src.Data(:,:,idx))
```
Keeps the source representation behind an accessor so detection/orchestrator code
never indexes `Data` directly.

### Background removal

- Setup GUI gains a **Set Background** button storing `backIdx` (the displayed
  frame index) and a status readout. DONE requires a background to be set.
- The orchestrator builds `backRef = dat_frame(src, backIdx)` once.
- Per processed frame: `proc = dat_frame(src, k) − backRef` (double, signed).
- Detection consumes `proc`. Display uses `imshow(proc, [])` (auto min–max to
  8-bit) for the GUI, preview, and montage.

### `detect_fronts_in_frame.m` (modified)

Signature unchanged: `[shockX, rxnX] = detect_fronts_in_frame(grayImg, yRows, scanDir, params)`.
`params` now includes **`gradSpan`** (L) alongside `shockThresh, rxnThresh,
whiteLevel, scanSmoothWin`.

Per row, in walk order (`cols` per `scanDir`):
1. `sm = movmean(row, max(1,round(scanSmoothWin)))`; `v = sm(cols)`.
2. Step-height over span: `g(i) = v(i+L) − v(i)` for `i = 1 … numel(v)−L`.
3. **Shock** = first `i` with `g(i) ≤ −shockThresh`. Localize: within the window
   `k ∈ [i, i+L−1]`, take the most-negative single-step diff `v(k+1)−v(k)`; report
   `shockX = cols(kEdge+1)` (first pixel past the steepest drop).
4. **Reaction** = first `i` strictly behind the shock with `g(i) ≥ +rxnThresh`
   **and** `v(i+L) ≥ whiteLevel`. Localize to the steepest positive single-step
   diff in `[i, i+L−1]`; report `rxnX = cols(kEdge+1)`.
5. No shock → both `NaN` for that row (reaction requires a shock).

`L` is clamped to `≥1` and rows shorter than `L+1` yield `NaN`.

### `setup_detection_gui.m` (modified)

- Replace `VideoReader`/`read(video,·)` with `src`/`dat_frame(src,·)`;
  `totalFrames = src.NumFrames`; `video.Height → src.Height`.
- Display frames via `imshow(dat_frame(src,frameNumber), [], 'Parent', ...)`.
- Add **Set Background** button + `backIdx` state; show it in the status line;
  `cbDone` requires `backIdx` set (in addition to width calibration + range).
- Crosshair, two-y-click width calibration, frame range, direction: unchanged.
- `setup` struct gains `backgroundFrame = backIdx`. Existing fields unchanged.

### `auto_detect_shock_reaction.m` (modified)

- File picker → `*.dat`; `src = load_dat_video(path)`.
- USER SETTINGS: add `gradSpan` (default e.g. 3); thresholds/`whiteLevel` are now
  in 16-bit subtracted-count units (defaults are starting points, set live in the
  preview). Drop AVI-specific assumptions.
- `backRef = dat_frame(src, setup.backgroundFrame)`.
- Tuning preview + batch operate on `proc = dat_frame(src,k) − backRef`; display
  with `imshow(proc, [])`.
- `Detection` struct **adds**: `datFormat` (the `fmt` used), `backgroundFrame`,
  and `thresholds.gradSpan`. Existing fields/shapes unchanged
  (`shockX_raw/clean`, `rxnX_raw/clean` `[numRows×N]`, `valid`, `calibration`,
  `mperpix`, etc.). Saved as `<datBase>_autodetect.mat`.
- Docs (`README.md`, `CLAUDE.md`) updated for the `.dat` pipeline.

## Testing strategy

- **`detect_fronts_in_frame` (rewrite tests):**
  - Step detection both scan directions; shock/reaction at known columns within ±1
    (steepest-pixel localization).
  - **Decoupling test:** a fixed-height step detected with the *same* `shockThresh`
    at `scanSmoothWin = 1` and `5` (with `gradSpan ≥` the smoothing spread) lands
    at the same position — the core win over per-pixel `diff`.
  - No-shock → both `NaN`; reaction rejected when below `whiteLevel`.
- **`load_dat_video` (new test):** write a tiny synthetic `.dat` (small header +
  known 16-bit frames, e.g. W=3,H=2,N=2) to a temp file with `fmt` overrides;
  assert `NumFrames` inferred, dimensions, and specific pixel values (orientation);
  assert it **errors** on a size that doesn't divide evenly. Clean up the temp file.
- **`clean_front_line`, `overlay_fronts`:** unchanged; existing tests must still pass.
- **Manual:** GUI walkthrough (scrub, Set Background, calibrate, range) and an
  end-to-end run on the real `.dat`, eyeballing the preview/montage and `.mat`.

## Out of scope (YAGNI / later)

- **Sharp-turn sectioning + spline fitting** → Spec 2.
- Authoritative Shimadzu header-field parsing (we infer `NumFrames` from size).
- Velocity computation (downstream consumer of the `.mat`).
- Multi-format ingestion (only the verified `.dat` layout; AVI removed).
- **2D / front-normal detection.** Detection here is intentionally 1D, directional,
  and semantic (per-row scan: shock = darkening, reaction = brightening behind it).
  This is well-suited to mostly-vertical fronts but loses sensitivity where the
  front turns oblique/horizontal (a likely gap source near the sharp turn). A
  targeted upgrade — measuring the gradient along the local **front-normal**
  rather than along `x` — is the right tool *if* oblique under-detection persists.
  Defer it: the clean 16-bit data + decoupled threshold may resolve most of it;
  re-evaluate after Spec 1, likely alongside Spec 2's geometry work. Full 2D edge
  detection (Canny/Sobel) is rejected — it gives an undifferentiated edge map with
  no shock/reaction ordering.
