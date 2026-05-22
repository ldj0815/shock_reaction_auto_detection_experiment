# Auto Shock & Reaction Front Detection — Design

**Date:** 2026-05-21
**Status:** Approved (pending spec review)

## Purpose

Replace the manual, frame-by-frame point-clicking in the existing toolchain
(`wave_speed_gui_v16.m` + `run_wave_tracking_v17.m`) with **automatic per-row
detection** of the shock front and the reaction front in high-speed detonation
videos. Output a self-contained `.mat` for future processing and a review
figure overlaying detections on a few frames.

## Context: the existing pipeline (starting point)

- `wave_speed_gui_v16.m`: interactive GUI. User scrubs frames, picks
  start/end reference points, then clicks one point per frame along a wave
  feature. Includes a green full-screen crosshair cursor
  (`createCrossHair` / `updateCrossHair`, lines 369-403) — reused here.
- `run_wave_tracking_v17.m`: converts clicked pixels to meters and computes
  velocities. Calibration is **horizontal**: `frameWidth_in = 13.13`,
  `mperpix = frameWidth / video.Width`.
- **There is no chamber-height calibration anywhere in the current code.** The
  new vertical two-y-click calibration is a new axis.
- Sample clip: 500 kFPS, 256 frames (per filename).

## Requirements (from user)

1. Ask detonation propagation direction (L→R or R→L); detection scans the
   reverse direction.
2. Ask for actual chamber width via a middle frame: click two y-positions to
   specify the channel height; cursor shows a cross guide line.
3. Detect the **shock** as the first large gradient to darker color; detect the
   **reaction front** as the first gradient jump to white. Detection applies
   the full width in y.
4. After processing all frames, plot a few frames with detected shock and
   reaction front overlaid; save detection data as a `.mat`.

## Decisions (from brainstorming)

- **Output shape:** full curve only — store `x(y)` per front per frame (no
  separate representative value; downstream computes those).
- **Calibration units:** dialog prompt, **inches** (editable default). Vertical
  two-y-click is the **sole** calibration; assume **square pixels** so the
  scale applies to the horizontal travel axis too.
- **Frame range:** user picks start/end frames.
- **mat format:** new self-contained structure (not the legacy `Tracks` struct).
- **Tuning:** interactive preview on the middle frame; adjust threshold(s) and
  re-preview until satisfied, then batch-process.
- **Front cleanup:** store raw `x(y)` AND a cleaned version (outlier rejection
  + light smoothing along y).
- **Confirmed interpretation:** the shock is the *leading* feature — scanning
  from the unburned/leading side backward, the shock is hit first and the
  reaction front lies behind it. The two calibration y-clicks also define the
  full y detection range (rows scanned).

## File structure

| File | Role | Testable |
|------|------|----------|
| `auto_detect_shock_reaction.m` | Main orchestrator: USER SETTINGS, video select, setup, tuning loop, batch, plotting, save | via integration |
| `detect_fronts_in_frame.m` | Pure fn: `(grayImg, yRows, scanDir, thresholds) -> shockX(y), rxnX(y)` | unit |
| `clean_front_line.m` | Pure fn: raw `x(y)` -> outlier-rejected + smoothed `x(y)` | unit |
| `setup_detection_gui.m` | Interactive setup window (scrub, direction, width calibration w/ crosshair, start/end) -> calibration + range + direction | manual |

The two pure functions are the core and are isolated from all GUI/IO so they can
be unit-tested against synthetic frames with a known dark step and white step.

## USER SETTINGS (top of `auto_detect_shock_reaction.m`)

- `frameRate` (Hz, default 500000)
- `startFolder` (default folder for `uigetfile`)
- `shockThresh` — darkening gradient magnitude (default tuned during preview)
- `rxnThresh` — brightening gradient magnitude
- `whiteLevel` — absolute intensity floor for "white" reaction front
- `scanSmoothWin` — smoothing window along the scan axis
- `madTol` — MAD multiplier for per-row outlier rejection
- `ySmoothWin` — smoothing window along y for the cleaned curve
- `nOverlayFrames` — number of frames in the review figure (default 6)

## Interactive flow

1. **Select video** (`uigetfile *.avi`) → `VideoReader`.
2. **Setup GUI** (`setup_detection_gui.m`), one window with frame scrubbing:
   - Propagation direction (L→R / R→L). `scanDir` = reverse of propagation.
     - L→R propagation → leading edge at right → scan right→left.
     - R→L propagation → leading edge at left → scan left→right.
   - Width calibration: green crosshair follows cursor; user clicks two
     y-positions (top & bottom chamber walls) on the displayed (middle) frame.
     Dialog prompts for actual chamber width in inches (editable default).
     `pixelHeight = |y2 - y1|`; `mperpix = width_in*0.0254 / pixelHeight`.
     `yRows = round(min(y)) : round(max(y))` = full detection range.
   - Start/End frame: scrub + "Set Start" / "Set End" buttons.
3. **Tuning preview**: run `detect_fronts_in_frame` on the middle frame; overlay
   shock (red) and reaction (cyan). Adjust `shockThresh`/`rxnThresh` and
   re-preview in a loop until accepted.

## Detection algorithm (`detect_fronts_in_frame.m`)

Input: grayscale image (double), `yRows`, `scanDir` (+1 or -1 along x),
thresholds `(shockThresh, rxnThresh, whiteLevel, scanSmoothWin)`.

For each row `y` in `yRows`, walking from the leading edge along `scanDir`:
- Smooth the row intensity along the scan axis (`scanSmoothWin`).
- Compute the signed intensity gradient along the scan direction.
- **Shock** = first x where gradient ≤ −`shockThresh` (sharp darkening).
- **Reaction front** = first x *behind* the shock where gradient ≥ +`rxnThresh`
  and intensity ≥ `whiteLevel` (sharp jump to white).
- No qualifying location → `NaN` for that row/front.

Returns `shockX(y)`, `rxnX(y)` in pixel coordinates.

## Cleanup (`clean_front_line.m`)

Input: raw `x(y)` vector (may contain NaN).
- Reject rows whose `x` deviates from the column median beyond `madTol` × MAD.
- Lightly smooth the surviving values along `y` (`ySmoothWin`).
- Return cleaned `x(y)` (NaN preserved where no data).

A **frame is flagged invalid** if the fraction of rows with a valid detection
falls below a minimum (e.g. < some `minValidFrac`).

## Batch processing

For each frame in `[startFrame, endFrame]`: read, grayscale, run
`detect_fronts_in_frame`, then `clean_front_line` for each front. Accumulate
into `[numRows × numFrames]` matrices.

## Outputs

### Review figure
`nOverlayFrames` evenly-spaced frames across the range in a `tiledlayout`, each
showing the frame with shock (red) and reaction (cyan) fronts overlaid. Saved
as `.fig` and `.png` next to the video.

### `<videoBaseName>_autodetect.mat` — `Detection` struct
- `video`: fileName, filePath, frameRate, width, height, totalFrames
- `calibration`: chamberWidth_in, pixelHeight, mperpix, yTop, yBottom,
  yPixels (`yRows`), calibFrame
- `propagationDirection`, `scanDirection`
- `thresholds`: shockThresh, rxnThresh, whiteLevel, scanSmoothWin, madTol,
  ySmoothWin, minValidFrac
- `frameRange` = [startFrame endFrame]
- `frames` (1×N frame indices)
- `shockX_raw`, `shockX_clean`, `rxnX_raw`, `rxnX_clean` — each `[numRows × N]`
  pixel coords
- `valid` (1×N logical) per-frame validity flags

## Testing strategy

- **`detect_fronts_in_frame`**: synthetic grayscale images with a known dark
  step (shock) and a known bright step (reaction) at controlled x positions and
  both scan directions; assert detected x within tolerance, and NaN when no
  step exceeds threshold.
- **`clean_front_line`**: vector with planted outliers and NaNs; assert
  outliers removed, NaNs preserved, smoothing bounded.
- **Integration**: run end-to-end on the sample clip; eyeball the overlay
  figure and confirm the `.mat` structure/fields.

## Out of scope (YAGNI)

- Computing velocities from the detections (the existing
  `run_wave_tracking`-style speed analysis can consume the `.mat` later).
- Backward-compatibility with the legacy `Tracks` struct.
- Sub-pixel front fitting, triple-point/cell tracking.
