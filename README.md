# Shock & Reaction Front Auto-Detection

Automatically detect the **shock front** and **reaction front** in high-speed
detonation videos, replacing manual frame-by-frame clicking. You calibrate once,
tune the detection on a preview, and the tool processes the whole frame range and
saves the results to a `.mat` file plus a review figure.

## Requirements

- **MATLAB R2024a** (or newer).
- **Image Processing Toolbox** — used for `rgb2gray` (color frames) and `imshow`.
- A detonation video in **`.avi`** format.

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

1. **Pick the video** in the file dialog (`.avi`).
2. **Setup window** opens on the middle frame:
   - **Direction** dropdown — choose the detonation propagation direction
     (`Left to Right` or `Right to Left`). Detection scans the *reverse* of
     propagation, so the leading shock is found first and the reaction front
     behind it.
   - **Calibrate Width (2 clicks)** — click the **top wall**, then the **bottom
     wall** of the chamber (a green crosshair guides you). A dialog then asks for
     the **actual chamber width in inches**. This sets the pixel scale *and* the
     vertical range over which detection runs (full chamber height).
   - **Set Start** / **Set End** — scrub with Prev/Next/±10 and mark the first
     and last frames to process.
   - **DONE** when all three are set.
3. **Tuning preview** — the detected shock (red) and reaction (cyan) fronts are
   overlaid on the calibration frame. Click **Adjust** to change thresholds and
   re-preview, or **Accept** to process the whole range.
4. The tool batch-processes every frame in your range, **saves the results**, and
   shows a **review montage** of evenly-spaced frames with the fronts overlaid.

## How detection works

For each row across the calibrated chamber height, the tool scans the intensity
profile from the leading edge backward:

- **Shock** = the first sharp drop in brightness (gradient ≤ `−shockThresh`):
  the leading compression darkens the gas.
- **Reaction front** = the first sharp jump *toward white* behind the shock
  (gradient ≥ `+rxnThresh` **and** intensity ≥ `whiteLevel`): the luminous
  combustion zone.

Each per-row result becomes a front curve `x(y)`. A cleaned copy is also stored,
with outlier rows rejected (MAD-based) and the curve lightly smoothed along `y`.

## Tuning the thresholds (top of `auto_detect_shock_reaction.m`)

These are the defaults; adjust in the preview loop or edit the `USER SETTINGS`
block:

| Setting | Meaning |
|---|---|
| `frameRate` | Camera frame rate in Hz (from your acquisition, **not** the AVI header — those are unreliable at high speed). |
| `shockThresh` | Minimum darkening gradient to count as the shock. Raise if noise triggers false shocks; lower if the shock is missed. |
| `rxnThresh` | Minimum brightening gradient for the reaction front. |
| `whiteLevel` | Absolute brightness floor (0–255) the reaction front must reach. Raise to require a stronger glow. |
| `scanSmoothWin` | Smoothing window along the scan axis. Larger = more noise rejection, but **may require lower thresholds** (smoothing reduces gradient magnitude). |
| `madTol` | Outlier rejection strictness for the cleaned curve (smaller = stricter). |
| `ySmoothWin` | Smoothing window along the chamber height for the cleaned curve. |
| `minValidFrac` | Fraction of rows that must yield a shock for a frame to be flagged "valid". |
| `nOverlayFrames` | Number of frames shown in the review montage. |

If the preview shows blank or wrong fronts: lower `shockThresh`/`rxnThresh`, or
lower `whiteLevel` if the reaction front isn't detected.

## Outputs (saved next to the video)

- **`<video>_autodetect.mat`** — a `Detection` struct:

  | Field | Contents |
  |---|---|
  | `video` | `fileName`, `filePath`, `frameRate`, `width`, `height`, `totalFrames` |
  | `calibration` | `chamberWidth_in`, `pixelHeight`, `mperpix`, `yTop`, `yBottom`, `yPixels`, `calibFrame` |
  | `propagationDirection` | `'LtoR'` or `'RtoL'` |
  | `scanDirection` | `+1` (L→R scan) or `−1` (R→L scan) |
  | `thresholds` | all detection/cleanup parameters used |
  | `frameRange` | `[startFrame endFrame]` |
  | `frames` | processed frame indices (1×N) |
  | `shockX_raw`, `shockX_clean` | shock front x-positions, pixels, `[numRows × N]` |
  | `rxnX_raw`, `rxnX_clean` | reaction front x-positions, pixels, `[numRows × N]` |
  | `valid` | per-frame confidence flag (1×N logical) |

  Convert pixels to meters with `mperpix` (e.g. `x_m = shockX_clean * Detection.calibration.mperpix`).
  `NaN` marks rows/frames where no front was found.

- **`<video>_autodetect_review.png`** / **`.fig`** — the overlay montage.

## Files

| File | Role |
|---|---|
| `auto_detect_shock_reaction.m` | Main entry point — run this. |
| `setup_detection_gui.m` | Setup window: direction, width calibration, frame range. |
| `detect_fronts_in_frame.m` | Per-row shock/reaction detection (pure function). |
| `clean_front_line.m` | Outlier rejection + smoothing of a front curve (pure function). |
| `overlay_fronts.m` | Draws the red/cyan front overlay. |
| `tests/` | Unit tests for the pure functions. |
| `docs/superpowers/` | Design spec and implementation plan. |

## Running the tests

```bash
matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```

All 8 tests should pass.

## Notes & limitations

- Calibration assumes **square pixels**: the vertical (two-click) scale is applied
  to horizontal distances too.
- **Velocity computation is out of scope** here — the saved `.mat` is the input for
  downstream speed analysis.
- The setup GUI and the end-to-end run require a display (they can't run headless).
