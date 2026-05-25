# CLAUDE.md

Guidance for AI assistants (and developers) modifying this MATLAB codebase.
For end-user usage, see `README.md`.

## What this project is

Automatic detection of the **shock front** and **reaction front** in high-speed
detonation recordings. Input is a raw 16-bit **`.dat`** file (Shimadzu HPV-class
camera). The user calibrates the chamber, selects a background frame, tunes
detection on a preview frame, and the tool batch-processes a frame range and saves
a `Detection` struct (`<datBase>_autodetect.mat`) plus a review montage.

It replaces the older manual-clicking workflow still present in the repo
(`run_wave_tracking_v17.m`, `wave_speed_gui_v16.m` — kept for reference, not part
of the new pipeline).

## Architecture & data flow

```
auto_detect_shock_reaction.m   (orchestrator: the only entry point)
   │                            branches on setup.detectorMode:
   │                              'band2d' (default) → 2D gradient-band pipeline
   │                              'step1d' (legacy)  → 1D step-height pipeline
   │
   ├─ load_dat_video.m         → reads raw .dat → `src` struct (Width/Height/NumFrames/Data/fmt)
   ├─ dat_frame.m              → src + index → one 2-D double frame
   ├─ setup_detection_gui.m    → returns `setup` struct (direction, detectorMode, ROI, calibration, background, frame range)
   ├─ auto_roi_mask.m          → background-subtracted frame → roiMask, roiClipLeft, roiClipRight (PURE)
   ├─ edge_map_2d.m            → frame → gradient magnitude map (PURE)
   ├─ detect_bands_in_frame.m  → per-row detection via 2D gradient bands (PURE)
   ├─ temporal_prior_refine.m  → refines raw front curve using cleaned previous-frame curve (PURE)
   ├─ detect_fronts_in_frame.m → per-row detection via 1D step-height (PURE, legacy mode)
   ├─ clean_front_line.m       → outlier rejection + smoothing of one front curve (PURE)
   └─ overlay_fronts.m         → draws shock(red)/reaction(cyan) on an axes
```

`VideoReader`/AVI was removed; all frame I/O goes through `load_dat_video` +
`dat_frame`.

The **pure functions** (`detect_bands_in_frame`, `detect_fronts_in_frame`,
`auto_roi_mask`, `edge_map_2d`, `temporal_prior_refine`, `clean_front_line`) hold
the core logic and are the only unit-tested pieces. Keep them pure (no GUI, no
file I/O, no `figure`/`imshow`) so they stay testable. The GUI and orchestrator
can't run headless (they need a display), so logic worth testing belongs in a pure
function, not in them.

## Key conventions (do not break these silently)

- **Detector mode** is chosen in the setup GUI (`band2d`/`step1d`). In `band2d`:
  detection runs on a Gmag strong-edge mask intersected with `roiMask`, split into
  a dark-region shock band and a bright-region reaction band, and the per-row
  interface is the **leading band pixel in `scanDir`**.
- **Temporal prior** uses the *cleaned* previous-frame curve as the prediction
  basis (prevents spike propagation). Default: shock-on (`useShockPrior=true`),
  reaction-off (`useRxnPrior=false`). The prior is applied **in the batch run
  only**, not in the tuning preview — tuning shows raw per-frame behavior.
- **`scanDir` is the reverse of propagation.** Propagation L→R ⇒ `scanDir = -1`
  (scan right-to-left from the leading edge); R→L ⇒ `scanDir = +1`. This mapping
  lives in `setup_detection_gui.m` and is consumed by `detect_fronts_in_frame.m`
  and `detect_bands_in_frame.m`.
- **Detection order:** scanning from the leading edge, the **shock is found first**
  (first darkening), the **reaction front behind it** (first jump to white). If no
  shock is found in a row, both fronts are `NaN` for that row.
- **Detection runs on the background-subtracted image** (`frame − backRef`, linear
  16-bit signed double). `whiteLevel`, `shockThresh`, and `rxnThresh` are all in
  background-subtracted count units.
- **Thresholds are step heights over `gradSpan` px** in raw counts:
  `g(i) = v(i+gradSpan) − v(i)`. They are independent of `scanSmoothWin`, which
  only denoises. The front is localized to the **steepest pixel within the flagged
  span**.
- **Front curves are `x(y)`:** for each image row `y` (across the calibrated
  chamber height `yRows`), the front is an x-position in pixels. "Smoothing along
  y" means across rows — that's why `clean_front_line`'s window param is
  `ySmoothWin` even though the values are x-positions. **This name is correct.**
- **Calibration is vertical and assumes square pixels.** Two y-clicks set both the
  scale (`mperpix = chamberWidth_in*0.0254/pixelHeight`) and the detection row
  range (`yRows`). The same `mperpix` applies to horizontal distances.
- **`NaN` is the "not detected" sentinel** everywhere; it must survive through
  `clean_front_line` (gaps are preserved) and renders as line breaks in
  `overlay_fronts` (MATLAB `plot` skips NaN).
- **`frameRate` is a USER SETTING**, not derived from the `.dat` file — that
  metadata is not stored in the raw format.

## The `setup` struct (GUI → orchestrator contract)

`setup_detection_gui` returns (or `[]` if cancelled): `propagationDirection`,
`scanDir`, `calibFrame`, `yTop`, `yBottom`, `pixelHeight`, `yRows`,
`chamberWidth_in`, `mperpix`, `startFrame`, `endFrame`, `backgroundFrame`,
`detectorMode`, `roiMask`, `roiClipLeft`, `roiClipRight`. If you add/rename a
field, update both the GUI and `auto_detect_shock_reaction.m`.

## The `Detection` struct (saved output contract)

Top-level fields: `video`, `datFormat`, `backgroundFrame`, `calibration`,
`propagationDirection`, `scanDirection`, `detectorMode`, `roiMask`, `roiClipLeft`,
`roiClipRight`, `thresholds`, `frameRange`, `frames`, `shockX_raw`, `shockX_clean`,
`rxnX_raw`, `rxnX_clean`, `valid`. The `*_raw`/`*_clean` matrices are
`[numRows × N]` in pixels. `thresholds` includes `gradSpan` (1D mode) and also
the band + prior params (`magThreshFrac`, `intensitySigma`, `deadband`, `minArea`,
`gaussSigma`, `useShockPrior`, `useRxnPrior`, `searchHalfWidth`, `deviationTol`,
`nTuningFrames`) when `detectorMode='band2d'`. **Downstream code reads this file**
— treat field names and shapes as a stable contract; if you change them, note it
prominently (it's a breaking change for any analysis script that loads the `.mat`).

## Where to make common changes

- **2D band detection algorithm** → `detect_bands_in_frame.m`. Add a test in
  `tests/test_detect_bands_in_frame.m` first (see TDD below).
- **ROI computation** → `auto_roi_mask.m` (+ its test in `tests/test_auto_roi_mask.m`).
- **Temporal prior logic** → `temporal_prior_refine.m` (+ its test in
  `tests/test_temporal_prior_refine.m`).
- **1D detection algorithm / gradient logic** → `detect_fronts_in_frame.m`. Add a
  test in `tests/test_detect_fronts_in_frame.m` first (see TDD below).
- **Outlier/smoothing behavior** → `clean_front_line.m` (+ its test).
- **New tunable parameter** → add to the `USER SETTINGS` block in
  `auto_detect_shock_reaction.m`, thread it into the `params` struct (if used by
  `detect_bands_in_frame`/`detect_fronts_in_frame`) and into the tuning
  `inputdlg`, and record it in `Detection.thresholds`.
- **GUI behavior (calibration, scrubbing, background selection, detector dropdown,
  ROI controls, validation)** → `setup_detection_gui.m`. Nested
  `createCrossHair`/`updateCrossHair` were adapted from `wave_speed_gui_v16.m`.
- **Plot styling / overlay** → `overlay_fronts.m` (shared by the preview and the
  montage — change once, both update).
- **`.dat` format** → `load_dat_video.m`. Overridable `fmt` constants
  (`headerBytes`, `width`, `height`, `dtype`, `byteOrder`); `NumFrames` is inferred
  from file size. Errors on non-integer frame count or truncated file.

## Testing (do this before claiming a change works)

Pure functions are tested with MATLAB function-based tests in `tests/`. Run:

```bash
matlab -batch "addpath(pwd); r = runtests('tests'); disp(r); assert(all([r.Passed]))"
```

(On this machine MATLAB is at `/Applications/MATLAB_R2024a.app/bin/matlab`.)
`matlab -batch` exits non-zero if the assert fails, so a clean exit = all pass.
For GUI/orchestrator edits, also `checkcode('<file>.m')` to catch parse errors,
since they can't be exercised headless.

## Workflow expectations

- **TDD for the pure functions:** write/extend the failing test, confirm it fails
  for the right reason, implement, confirm it passes.
- The tests build **synthetic frames** (a row profile with a known dark step and
  white step) — extend that pattern rather than depending on a real video.
- Keep each file single-purpose. If a pure function starts doing I/O or drawing,
  that's a smell — split it.
- Commit messages: imperative mood; this repo uses `feat:`/`fix:`/`docs:`/`chore:`
  prefixes.

## Gotchas

- The temporal prior is applied **in the batch run only**, not in the tuning
  preview, so tuning shows raw per-frame behavior. This is intentional: the prior
  needs a preceding cleaned frame, which isn't available during single-frame
  preview.
- `scanSmoothWin > 1` only denoises — it does **not** reduce threshold effective
  magnitude, because thresholds are step heights (not point gradients). Tests use
  `scanSmoothWin = 1` for exact, deterministic edge positions.
- `imshow`/`overlay_fronts` use image coordinates (y increases downward); the
  calibration math uses `min`/`max`/`abs`, so click order (top-first vs
  bottom-first) doesn't matter.
- Saving **overwrites** existing `<datBase>_autodetect.*` without prompting.
- The `.dat` is **16-bit linear** (10-bit sensor data scaled into 16-bit range).
  Read as `uint16`, reshaped `[Width Height NumFrames]`, then transposed to
  `[Height Width NumFrames]`; this layout has been verified against a rendered
  reference frame. There are **no per-frame headers** — frames are contiguous after
  the single 6336-byte file header.
