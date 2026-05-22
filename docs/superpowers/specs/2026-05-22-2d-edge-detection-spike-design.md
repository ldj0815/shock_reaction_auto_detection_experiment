# 2D Edge-Detection Spike — Design

**Date:** 2026-05-22
**Status:** Approved (pending spec review)
**Type:** Exploratory spike (evaluation, not production integration)

## Purpose

Evaluate whether **2D edge detection** locates the shock and (especially the
weakening / oblique) reaction front better than the current 1D step-height
detector — judged **visually** on real frames. The 2D edge map is generic; the
shock/reaction *semantics* are recovered afterward by a "first two edges per row"
extractor. Outcome informs how much of the planned 1D temporal/adaptive tracker
to build.

## Background

The 1D detector (`detect_fronts_in_frame`) scans each row along x and thresholds a
step height. Where the reaction front weakens and turns oblique (induction zone
grows as the wave runs), a near-horizontal front produces a small along-x step and
is under-detected. A 2D operator measures the gradient regardless of orientation,
so it may catch oblique segments — at the cost of an undifferentiated edge map
that needs semantic post-processing.

## Decisions

- **Both** edge representations rendered for comparison: **Canny** (binary edges)
  and **Sobel gradient-magnitude** (heatmap).
- Detection runs on the **background-subtracted** image (`frame − backRef`), with
  **`backRef` = frame 2** (the lab's usual background choice).
- Scan direction and the handful of frame indices are chosen at run time by the
  implementer (so the spike runs end-to-end headless, no GUI).
- The "first two edges" extractor **keeps shock/reaction semantics**: first
  darkening edge = shock, next brightening edge behind it = reaction.
- Spike only — **no** orchestrator integration, temporal tracker, or spline here.

## Components

| File | Role | Tested |
|------|------|--------|
| `edge_map_2d.m` | Compute `Gx` (signed x-gradient), `Gmag` (gradient magnitude), `E` (Canny binary map) from a 2-D frame + params | smoke |
| `extract_first_two_edges.m` | Pure: per-row, scan in `scanDir`; first darkening edge → shock, next brightening edge → reaction | unit |
| `edge2d_experiment.m` | Script: load `.dat`, subtract frame 2, run the above on several frames, render comparison montages (Canny / Gmag / 1D), save PNG+`.fig` | manual/visual |

### `edge_map_2d.m`
```
[Gx, Gmag, E] = edge_map_2d(img, params)
```
- `img`: 2-D double (background-subtracted frame).
- `params`: `gaussSigma` (pre-smoothing), `cannyThresh` (`[]` for auto or `[low high]`).
- Steps: `Is = imgaussfilt(img, gaussSigma)`; `[Gx, Gy] = imgradientxy(Is,'sobel')`;
  `Gmag = hypot(Gx, Gy)`; `E = edge(mat2gray(Is), 'canny', cannyThresh)`.
- Returns the three arrays (same size as `img`).

### `extract_first_two_edges.m`
```
[shockX, rxnX] = extract_first_two_edges(Gx, edgeMask, yRows, scanDir, minMag)
```
- `edgeMask`: logical edge map (Canny `E`, or `Gmag >= minMag`).
- Walk each row in `scanDir`. Directional change per walk step ≈ `Gx*scanDir`.
- **Shock** = first edge pixel (in walk order) on `edgeMask` with `Gx*scanDir < 0`
  (darkening) and `|Gx| >= minMag`.
- **Reaction** = next edge pixel behind the shock with `Gx*scanDir > 0`
  (brightening) and `|Gx| >= minMag`.
- No qualifying edge → `NaN`. Returns `numel(yRows)x1` columns.

### `edge2d_experiment.m`
- `src = load_dat_video(path)`; `backRef = dat_frame(src, 2)`.
- Choose `scanDir`, a `yRows` band, and ~6 frame indices spanning the active
  window (implementer locates the wave first with a quick scan).
- For each frame: `proc = dat_frame(src,k) - backRef`; `[Gx,Gmag,E] = edge_map_2d(...)`;
  `extract_first_two_edges` on the Canny map (and separately on a `Gmag` threshold);
  also run the existing `detect_fronts_in_frame` for the 1D baseline.
- Render, per frame, a `tiledlayout` row: (1) `proc` + Canny edges + extracted
  fronts, (2) `proc` + `Gmag` heatmap, (3) `proc` + 1D-detector fronts.
- Save `edge2d_compare.png` / `.fig` for review.

## Evaluation (the actual deliverable)

Run `edge2d_experiment.m` headless on the real `.dat`; the implementer/controller
**views the saved montages** and reports how Canny vs Sobel-magnitude vs the 1D
detector locate the shock and reaction across early and late frames (focus: the
late frames where the reaction decouples). The saved images are kept for the user.

## Testing strategy

- **`extract_first_two_edges`**: synthetic image with a known dark step then bright
  step (both scan directions); assert shock/reaction columns within ±1, and NaN
  when no edge passes `minMag`.
- **`edge_map_2d`**: smoke test on a synthetic step image — outputs are the right
  size and an obvious edge appears in `E`/`Gmag` at the expected column.
- **`edge2d_experiment`**: visual/manual (produces the comparison montages).

## Out of scope

- Integrating 2D detection into `auto_detect_shock_reaction` (decided after results).
- Temporal/adaptive reaction tracking (next spec, informed by this).
- Sharp-turn sectioning + spline (deferred).
