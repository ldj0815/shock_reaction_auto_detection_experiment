# Robust Detection v2 — Design

**Date:** 2026-05-25
**Status:** Approved (pending spec review)
**Relationship:** Builds on Spec 1 (raw `.dat` pipeline + 16-bit step-height
detection). Adds a band-based 2D detection mode + ROI + temporal prior, with
multi-frame tuning. Spline / sharp-turn sectioning remains a follow-up spec.

## Purpose

Add a **band-based 2D detection mode** that exploits the gradient-magnitude /
region-brightness structure to track curved/oblique fronts more robustly than
the per-row 1D step-height detector. Add a **region of interest** so detection
ignores chamber walls and dark field borders. Add a **temporal prior** (applied
to the shock by default) to rescue rows where the front is locally weak —
seeded from the **cleaned previous-frame curve** so spikes do not propagate.
Make the existing 1D detector a switchable mode rather than replacing it.

## Spike findings that motivate this design

A spike (commits `36f81af`..`31fb2bd`) compared per-row 1D step-height
detection, Canny, and Sobel gradient-magnitude on real `.dat` frames. Results:
- Sobel **gradient magnitude is the right 2D signal** — it traces the curved
  shock front including the sharp bend; Canny is too noisy for naive
  "first-two-edges" extraction.
- Splitting the strong-edge mask by **region brightness** ("dark inside =
  shock, bright inside = reaction") gives two clean spatially-coherent bands.
- The interface curve = the **leading edge of each band in the scan
  direction** is much cleaner than per-row peak picking.
- Chamber walls and dark field borders leak into the bands without a
  region-of-interest mask.
- Late frames show the reaction band physically fading — the decoupling the
  user flagged. Temporal prior is needed there.
- Naive temporal prior using raw per-row positions propagates spikes. Using
  the **cleaned curve** as the prior basis avoids that.

## Decisions (from brainstorming)

- **ROI:** auto-derived from the background frame, with a GUI override (click
  to adjust left/right boundary).
- **Detector mode:** **coexist** — `step1d` (current) and `band2d` (new), chosen
  via a dropdown in the setup GUI. `band2d` is the default.
- **Temporal prior:** included in this spec; applies to **shock by default
  (`true`), reaction off by default (`false`)** — per the user's empirical
  finding. Both toggles are user settings.
- **Prior basis = cleaned previous curve** (not raw) to suppress spike
  propagation.
- **Tuning preview = raw detection on a multi-frame montage**, no temporal
  prior. The prior is applied in the batch run.
- **Spline / sharp-turn sectioning:** out of scope; follow-up spec.

## File structure

| File | Change | Tested |
|------|--------|--------|
| `auto_roi_mask.m` | **new** — backRef → logical ROI mask | unit |
| `detect_bands_in_frame.m` | **new** — pure band-based front detector | unit |
| `temporal_prior_refine.m` | **new** — pure: rescue rows using prev cleaned curve | unit |
| `setup_detection_gui.m` | **modify** — detector-mode dropdown + ROI overlay/override | manual |
| `auto_detect_shock_reaction.m` | **modify** — mode switch, prev-state buffer, multi-frame tuning | manual / suite |
| `edge_map_2d.m` | **existing** (from the spike, already on `main`) | existing |
| `clean_front_line.m`, `overlay_fronts.m`, `load_dat_video.m`, `dat_frame.m`, `detect_fronts_in_frame.m` | **unchanged** | existing |

The spike's exploratory `extract_bands.m` and `edge2d_bands_experiment.m` will
be **deleted**; their logic is superseded by `detect_bands_in_frame.m` (with
tests + ROI support).

## Component designs

### `auto_roi_mask.m`
```
roi = auto_roi_mask(backRef, params)
```
- `params`: `dilatePx` (default 3), `minFrac` (default 0.2 — keep components
  covering at least this fraction of the largest one).
- Otsu threshold (`graythresh` on `mat2gray(backRef)`) splits illuminated test
  section from dark border.
- `imclose` with a small disk, then `imfill(holes)`, then keep components
  passing the area filter, then dilate by `dilatePx`.
- Returns `roi` (logical `[H × W]`). An all-dark input produces an all-false
  mask; tested.

### `detect_bands_in_frame.m`
```
[shockX, rxnX, shockMask, rxnMask] = detect_bands_in_frame( ...
    proc, Gmag, yRows, scanDir, roiMask, params)
```
- `params`: `magThreshFrac` (default 0.95 — percentile of `Gmag(yRows,:)`
  within ROI), `intensitySigma` (5), `deadband` (0), `minArea` (30).
- `magThresh` = chosen quantile of `Gmag` within `yRows ∧ roiMask`.
- `strong = (Gmag ≥ magThresh) ∧ roiMask`.
- `Iblur = imgaussfilt(proc, intensitySigma)`.
- `shockMask = strong ∧ (Iblur < −deadband)`; `rxnMask = strong ∧ (Iblur >
  deadband)`. (Dark inside → shock; bright inside → reaction.)
- `bwareaopen(·, minArea)` on each.
- Per row `y ∈ yRows`, walking columns in `scanDir`: `shockX(y)` = column of
  the **first** `shockMask` pixel; `rxnX(y)` similarly. NaN where none.
- Returns the per-row arrays **and** the band masks (used for display/QA).

### `temporal_prior_refine.m`
```
[shockOut, rxnOut] = temporal_prior_refine( ...
    shockRawNow, rxnRawNow, prevCleaned, Gmag, Iblur, scanDir, params)
```
- `prevCleaned`: struct of the previous frame's *cleaned* curves
  `prevCleaned.shock`, `prevCleaned.rxn` (length = `numel(yRows)`, NaN where
  none); plus optionally one earlier frame for velocity.
- `params`: `useShockPrior` (default `true`), `useRxnPrior` (default
  `false`), `searchHalfWidth` (default 10 px), `deviationTol` (default 4 px —
  beyond this, the current row's value is replaced).
- Per front (if its toggle is on):
  1. Compute the global displacement `Δx` between the two previous cleaned
     curves (median over non-NaN rows). If only one prev frame exists, `Δx = 0`.
  2. For each row, **predicted x** = `prevCleaned.<front>(row) + Δx`.
  3. If the current raw detection is NaN, or differs from the prediction by
     more than `deviationTol`: search the column range `[pred − searchHalfWidth,
     pred + searchHalfWidth]` for the strongest `Gmag` pixel that **also lies
     in the right brightness region** (dark for shock, bright for reaction)
     — without requiring the global `magThresh`. Use that as the refined x. If
     no candidate exists in the window, leave NaN.
- If a toggle is off, that front passes through unchanged (raw stays raw).
- Returns the refined per-row arrays for the orchestrator to clean.

### `setup_detection_gui.m` (modifications)
- New **Detector** dropdown: `1D step-height` / `2D bands` → sets
  `setup.detectorMode`.
- When **Set Background** is clicked: call `auto_roi_mask(backRef)` and display
  the ROI as a translucent overlay (e.g. brighten outside the ROI subtly so the
  active region is visible).
- Two new buttons: **Set ROI Left** and **Set ROI Right**. They enter a click
  mode (similar to calibration) where the next click's x replaces the
  corresponding boundary of the ROI (e.g. the user can cut off a wall that
  leaked in). Internally these become `roiClipLeft` / `roiClipRight` — the
  final `setup.roiMask` is `auto_roi_mask(backRef) ∧ (cols ≥ roiClipLeft ∧ cols
  ≤ roiClipRight)`.
- The vertical bounds reuse the existing two-y-click calibration.
- DONE validates the new fields like the existing ones.
- `setup` struct gains: `detectorMode`, `roiMask`, `roiClipLeft`, `roiClipRight`.

### `auto_detect_shock_reaction.m` (modifications)
- USER SETTINGS gain:
  - Band-detector: `magThreshFrac`, `intensitySigma`, `deadband`, `minArea`.
  - Temporal prior: `useShockPrior=true`, `useRxnPrior=false`, `searchHalfWidth`,
    `deviationTol`.
  - Tuning: `nTuningFrames` (default 6).
- After the GUI returns, `backRef` and `roiMask` are taken from `setup`.
- **Tuning preview (multi-frame, raw only):** pick `nTuningFrames` indices
  evenly spaced over `[startFrame, endFrame]`. For each, render the
  background-subtracted frame with the **current-mode detector** applied
  *independently* (no temporal prior in the preview) — shock(red) /
  reaction(cyan) overlaid in a tiled montage. The Adjust dialog re-renders.
- **Batch loop (with prev-state buffer):**
  ```
  prevCleaned = empty
  for k = startFrame..endFrame:
    proc = dat_frame(src,k) - backRef
    if mode == 'step1d':
        raw = detect_fronts_in_frame(proc, yRows, scanDir, params1d)
    else: % 'band2d'
        [Gx,Gmag,~] = edge_map_2d(proc, emParams)
        [sx_raw, rx_raw, sMask, rMask] = detect_bands_in_frame(...)
        Iblur = imgaussfilt(proc, intensitySigma)
        [sx_raw, rx_raw] = temporal_prior_refine( ...
            sx_raw, rx_raw, prevCleaned, Gmag, Iblur, scanDir, priorParams)
    [sx_clean, rx_clean] = clean_front_line each
    store raw + clean
    prevCleaned = struct('shock',sx_clean, 'rxn',rx_clean)
  ```
  (For mode `step1d`, the prev-state path is skipped; the temporal prior is
  only applied in `band2d`.)
- Detection struct additions:
  - `detectorMode` (`'step1d'`/`'band2d'`)
  - `roiMask` (logical `[H×W]`); `roiClipLeft`, `roiClipRight`
  - `thresholds` gains `magThreshFrac`, `intensitySigma`, `deadband`, `minArea`,
    `useShockPrior`, `useRxnPrior`, `searchHalfWidth`, `deviationTol`,
    `nTuningFrames`.
  - Existing fields/shapes unchanged.

## Testing strategy

- **`auto_roi_mask`** — synthetic `backRef`: a 200×100 image with a bright disk
  of radius 60 centered, dark elsewhere; assert the mask covers the disk
  interior (≥ some fraction), is false in the dark corners, and grows by the
  `dilatePx` margin. All-zero input → all-false mask.
- **`detect_bands_in_frame`** — synthetic `proc`: dark band columns 30..50,
  bright band columns 70..90 (else 0), constant down rows. Make `Gmag` peak
  along the band edges. ROI excludes columns 1..10 (a "wall"). Assert
  `shockX ≈ 30` (leading edge of dark band, scanDir=+1), `rxnX ≈ 70` (leading
  edge of bright band), and that detections in the masked-out wall don't
  appear. Plus an all-blank input → all NaN.
- **`temporal_prior_refine`** — synthetic case: 5 rows; current `shockRawNow`
  has NaN at row 3; `prevCleaned.shock = [50;50;50;50;50]`; `Δx = 2`; place a
  strong `Gmag` peak in dark region at column 52 of row 3 only inside the
  search window. Assert `shockOut(3) = 52`, others unchanged. With
  `useShockPrior=false`, assert output equals input unchanged.
- **`clean_front_line`**, **`overlay_fronts`**, **`detect_fronts_in_frame`**,
  **`load_dat_video`**: existing tests must still pass.
- **GUI / orchestrator**: headless `checkcode` parse + the full unit suite;
  manual end-to-end run on the real `.dat` (the user) for both modes.

## Out of scope

- Sharp-turn sectioning + spline fitting (next spec).
- Authoritative Shimadzu header parsing.
- Velocity / downstream physics.
- A *combined* mode that fuses 1D and 2D results (defer).
