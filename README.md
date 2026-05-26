# Shock & Reaction Front Auto-Detection

Automatically detect the **shock front** and **reaction front** in high-speed
detonation videos, replacing manual frame-by-frame clicking. You calibrate once,
tune the detection on a preview, and the tool processes the whole frame range and
saves the results to a `.mat` file plus a review figure.

## Requirements

- **MATLAB R2024a** (or newer).
- **Image Processing Toolbox** — used for `imshow` (display); frame loading uses
  only built-in file I/O (`fread`/`reshape`), so no color-conversion toolbox
  functions are needed.
- A raw 16-bit **`.dat`** file from a Shimadzu HPV-X/X2-class (or compatible)
  high-speed camera (400×250 pixels; contiguous uint16 frames after a 6336-byte
  header; little-endian).

## Quick start

From MATLAB, with this folder on the path (or as the current folder):

```matlab
auto_detect_shock_reaction
```

This launches the full workflow. You can also capture the result:

```matlab
Detection = auto_detect_shock_reaction;
```

## Workflow (what you'll do)

1. **Pick the `.dat` file** in the file dialog.
2. **Setup window** opens on the middle frame:
   - **Direction** dropdown — choose the detonation propagation direction
     (`Left to Right` or `Right to Left`, defaults to `Right to Left`).
     Detection scans the *reverse* of propagation, so the leading shock is
     found first and the reaction front behind it.
   - **Calibrate Width (2 clicks)** — click the **top wall**, then the **bottom
     wall** of the chamber (a green crosshair guides you). A dialog then asks for
     the **actual chamber width in inches**. This sets the pixel scale *and* the
     vertical range over which detection runs (full chamber height).
   - **Detector** dropdown — choose the detection algorithm: **2D bands**
     (default) or **1D step-height** (legacy). See "How detection works" below.
   - **Set Background** — scrub to a clean pre-detonation frame and click
     **Set Background**. That frame is subtracted (linearly) from every frame
     before detection, removing fixed-pattern noise and background glow. In
     **2D bands** mode the ROI is also auto-detected at this point and shown
     as **green vertical lines** at the left/right boundaries of the active
     region.
   - **Set ROI Left** / **Set ROI Right** — optional override buttons to
     manually pin the left or right ROI boundary (overrides the auto-detected
     value). The green boundary lines update immediately.
   - **Set Start** / **Set End** — scrub with Prev/Next/±10 and mark the first
     and last frames to process.
   - **DONE** when all four are set.
3. **Tuning preview** — the detected shock (red) and reaction (cyan) fronts are
   overlaid on the calibration frame. Click **Adjust** to change thresholds and
   re-preview, or **Accept** to process the whole range.
4. The tool batch-processes every frame in your range, **saves the results**, and
   shows a **review montage** of evenly-spaced frames with the fronts overlaid.

## How detection works

Detection always runs on the **background-subtracted** image (`frame − backgroundFrame`,
linear 16-bit signed double).

**2D bands (default).** Compute the gradient magnitude of the background-subtracted
frame; the strong-edge pixels inside the ROI are split into a *dark-inside* band
(shock, red) and a *bright-inside* band (reaction, cyan) by a smoothed intensity.
Each row's interface is the **gradient-magnitude-weighted centroid of the leading
connected band segment in the scan direction** — i.e. the centerline of the
ridge, with any trailing same-class segment ignored. A small NaN-preserving
along-y smoothing (`bandYSmoothWin`) damps row-to-row centroid jitter without
inventing values at undetected rows. A **temporal prior** uses the cleaned
previous-frame curve to rescue rows where the local edge is weak (applied to the
shock by default; toggleable per front).

**1D step-height (legacy).** For each row across the calibrated chamber height,
the tool scans the background-subtracted intensity profile from the leading edge
backward:

- **Shock** = the first span where the **step height** over `gradSpan` pixels
  is ≤ `−shockThresh`: i.e. `g(i) = v(i+gradSpan) − v(i) ≤ −shockThresh`.
  The leading compression darkens the gas relative to background.
- **Reaction front** = the first span where `g(i) ≥ +rxnThresh` **and** the
  pixel intensity is ≥ `whiteLevel`: the luminous combustion zone brightening
  above background.

The thresholds are **brightness changes in raw 16-bit counts** over `gradSpan`
pixels. `scanSmoothWin` only denoises the profile — it does not rescale the
threshold. The front is localized to the **steepest single pixel** within each
flagged span, so sub-window precision is preserved.

Each per-row result becomes a front curve `x(y)`. A cleaned copy is also stored,
with outlier rows rejected (MAD-based) and the curve lightly smoothed along `y`.

## Tuning the thresholds (top of `auto_detect_shock_reaction.m`)

These are the defaults; adjust in the preview loop or edit the `USER SETTINGS`
block:

| Setting | Meaning |
|---|---|
| `frameRate` | Camera frame rate in Hz (from your acquisition, **not** derived from the `.dat` file — that metadata is not stored in the raw format). |
| `shockThresh` | Minimum darkening step height (in 16-bit raw counts on the background-subtracted image) to count as the shock. Values are typically in the thousands. Raise if noise triggers false shocks; lower if the shock is missed. |
| `rxnThresh` | Minimum brightening step height (raw counts, background-subtracted) for the reaction front. |
| `whiteLevel` | Absolute brightness floor in background-subtracted 16-bit counts the reaction front must reach. `0` accepts any pixel at or above background; raise to require a stronger glow. |
| `gradSpan` | Span in pixels over which the step height is measured: `g(i)=v(i+gradSpan)−v(i)`. Make it ≥ the edge width (or ≥ the smoothing window) to capture the full transition. |
| `scanSmoothWin` | Smoothing window along the scan axis — **only denoises**, does not rescale thresholds. Larger = more noise rejection without changing the count-unit threshold values. |
| `madTol` | Outlier rejection strictness for the cleaned curve (smaller = stricter). |
| `ySmoothWin` | Smoothing window along the chamber height for the cleaned curve. |
| `minValidFrac` | Fraction of rows that must yield a shock for a frame to be flagged "valid". |
| `nOverlayFrames` | Number of frames shown in the review montage. |
| `magThreshFrac` | Fraction of the max gradient magnitude used as the strong-edge threshold (2D bands). |
| `intensitySigma` | Gaussian blur sigma (pixels) applied before the dark/bright split (2D bands). |
| `deadband` | Minimum pixel gap between shock and reaction band assignments (2D bands). |
| `minArea` | Minimum connected-component area (pixels) to keep a band (2D bands). |
| `bandYSmoothWin` | Odd window length for an NaN-preserving moving-mean of the per-row centroid along y, applied inside the 2D band detector to damp row-to-row oscillation. `1` disables. Default 5. |
| `gaussSigma` | Gaussian sigma for the gradient magnitude computation (2D bands). |
| `useShockPrior` | Use the temporal prior for the shock front (default: `true`). |
| `useRxnPrior` | Use the temporal prior for the reaction front (default: `false`). |
| `searchHalfWidth` | Half-width (pixels) of the search window around the prior prediction. |
| `deviationTol` | Maximum allowed deviation (pixels) from the prior before falling back to raw detection. |
| `nTuningFrames` | Number of frames shown independently in the multi-frame tuning preview montage (default: 6). |

If the preview shows blank or wrong fronts: lower `shockThresh`/`rxnThresh`, or
lower `whiteLevel` if the reaction front isn't detected. Because units are raw
16-bit counts (values in the thousands), be sure thresholds are in the same scale
as your data when tuning.

## Outputs (saved next to the input file)

- **`<datBase>_autodetect.mat`** — a `Detection` struct:

  | Field | Contents |
  |---|---|
  | `video` | `fileName`, `filePath`, `frameRate`, `width`, `height`, `totalFrames` |
  | `datFormat` | raw `.dat` layout constants (`headerBytes`, `width`, `height`, `dtype`, `byteOrder`) |
  | `backgroundFrame` | frame **index** (integer) of the pre-detonation background that was subtracted before detection; reload the pixels with `dat_frame(load_dat_video(fullfile(Detection.video.filePath, Detection.video.fileName)), Detection.backgroundFrame)` |
  | `calibration` | `chamberWidth_in`, `pixelHeight`, `mperpix`, `yTop`, `yBottom`, `yPixels`, `calibFrame` |
  | `propagationDirection` | `'LtoR'` or `'RtoL'` |
  | `scanDirection` | `+1` (L→R scan) or `−1` (R→L scan) |
  | `detectorMode` | `'band2d'` (default) or `'step1d'` — which algorithm was used |
  | `roiMask` | logical mask (`[height × width]`) of the active detection ROI (2D bands) |
  | `roiClipLeft` | left x-boundary (pixels) of the ROI |
  | `roiClipRight` | right x-boundary (pixels) of the ROI |
  | `thresholds` | all detection/cleanup parameters used, including `gradSpan`; also includes band + prior params when `detectorMode='band2d'` |
  | `frameRange` | `[startFrame endFrame]` |
  | `frames` | processed frame indices (1×N) |
  | `shockX_raw`, `shockX_clean` | shock front x-positions, pixels, `[numRows × N]` |
  | `rxnX_raw`, `rxnX_clean` | reaction front x-positions, pixels, `[numRows × N]` |
  | `valid` | per-frame confidence flag (1×N logical) |

  Convert pixels to meters with `mperpix` (e.g. `x_m = shockX_clean * Detection.calibration.mperpix`).
  `NaN` marks rows/frames where no front was found.

- **`<datBase>_autodetect_review.png`** / **`.fig`** — the overlay montage.

## Files

| File | Role |
|---|---|
| `auto_detect_shock_reaction.m` | Main entry point — run this. |
| `load_dat_video.m` | Reads the raw `.dat` into a frame source struct (`src`). |
| `dat_frame.m` | Returns one frame from `src` as a 2-D double array. |
| `setup_detection_gui.m` | Setup window: direction, detector mode dropdown, ROI controls, width calibration, background selection, frame range. |
| `detect_fronts_in_frame.m` | Per-row shock/reaction detection — 1D step-height algorithm (pure function). |
| `detect_bands_in_frame.m` | Per-row shock/reaction detection — 2D gradient-band algorithm (pure function). |
| `auto_roi_mask.m` | Computes the auto-detected ROI mask and clip boundaries from the raw background frame via Otsu thresholding (pure function). |
| `temporal_prior_refine.m` | Refines a raw front curve using the cleaned previous-frame curve as a temporal prior (pure function). |
| `edge_map_2d.m` | Computes the gradient magnitude map used by the 2D band detector (pure function). |
| `clean_front_line.m` | Outlier rejection + smoothing of a front curve (pure function). |
| `overlay_fronts.m` | Draws the red/cyan front overlay. |
| `tests/` | Unit tests for the pure functions. |
| `docs/superpowers/` | Design spec and implementation plan. |

## Running the tests

```bash
matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```

All 32 tests should pass.

## Notes & limitations

- **Input is the raw `.dat` only** — the pre-processed AVI input path was removed.
  The `.dat` layout is auto-sized from file length; `width`, `height`,
  `headerBytes`, and `dtype` are overridable constants in `load_dat_video.m`
  (verified for a Shimadzu HPV-class 16-bit 400×250 clip).
- Calibration assumes **square pixels**: the vertical (two-click) scale is applied
  to horizontal distances too.
- **Velocity computation is out of scope** here — the saved `.mat` is the input for
  downstream speed analysis.
- The setup GUI and the end-to-end run require a display (they can't run headless).
