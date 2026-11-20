# Baseline replication: PLDBS Simulink model at 4096 Hz

Replicates the simulation results of Guo et al. 2025, *Brain Stimulation* 18:1705–1717
(doi:10.1016/j.brs.2025.09.002) with the repo's `SimulnkModel/Estimationdataset1.slx`.
This is the reference point for the planned 250 Hz port.

## Requirements
MATLAB R2025b with **Simulink, Stateflow, DSP System Toolbox** (Buffer blocks) and
Signal Processing Toolbox (analysis). The model was saved in R2023b and opens without changes.

## How to run
```
cd analysis
matlab -batch "run_baseline"        % model as shipped -> results/baseline_raw.mat (~20 s)
matlab -batch "m = eval_phase('results/baseline_raw.mat', struct('fig','results/baseline_asis.png'))"
matlab -batch "sweep_phases"        % 8 targets x 3 estimators + Kalman window 8-12 ms (~15 min)
```
`run_baseline(target, method, stopTime, tag, width_ms)` changes the target phase, estimator
(1 = arHT, 2 = NRO, 3 = ZC) or Kalman window **in memory only**. The `.slx` file is never saved.
`inspect_model.m` prints the model's wiring.

## What the model is
`rawNot` (artifact-free STN LFP, PD patient, 4096 Hz) passes through these stages:
1. A recorded stimulation artifact is added at every trigger (25 templates, chosen at random).
2. Kalman filter (AR(2), measurements ignored for 12 ms after each trigger).
3. 4th-order Chebyshev-I bandpass (18–24 Hz).
4. Phase estimator (NRO by default, 22 Hz). It triggers when the phase is within ±0.02 rad of `Target`.

Notes on the model:
- The estimators output `angle(hilbert(x))` (0 = peak). The paper's figures use rising = 0, peak = 90°, so paper = model + 90°.
- `simout` is the same bandpass applied to the artifact-free signal, which makes it the model's built-in gold-standard reference.

## Results: see `results/baseline_summary.md`
- **The model runs as-is**: 1287 phase-locked pulses in 60 s (~21.5 Hz, one per beta cycle).
- **Phase locking reproduces the paper** when measured against the model's reference (NRO, mean over 8 targets):
  - Within ±45°: 94.2% (paper 93.24%).
  - Within ±30° with amplitude > 2 µV: 97.3% (paper 95.42%).
  - std 22.8° ± 1.1° (paper 20.6° ± 2.1°).
  - Estimator ranking matches: NRO has the lowest bias and std; ZC has the highest std; arHT has the highest bias.
  - Bias is smaller than reported (0.7° vs 9.6°).
- **Artifact suppression, qualitatively:**
  - Kalman beats blank+interpolate most clearly at short windows (8–9 ms: ~2% vs 6–8% beta spectral-amplitude error).
  - Kalman error grows with window length (2.0% → 3.9% from 9 to 12 ms), as in Table 2 (5.2% → 5.8%).
  - The paper's large errors at 8 ms (36% / 410%) are **not** reproduced. In this model's artifact template most energy ends by ~10 ms.
  - Simple sample-and-hold performs about as well as Kalman on the spectral metric.
  - The paper does not define its "relative error" exactly. I use the spectral-amplitude error in the individual beta band (peak ± 2.5 Hz) as the main metric. The time-domain envelope error is reported too; on that metric blanking beats Kalman at ≥ 10 ms.

## Important caveat: the bandpass delay
The real-time Chebyshev bandpass has a **group delay of about 210 ms in its passband**
(470–670 ms at the band edges). That is about 5 beta cycles; it was measured from the model's
impulse response. The hardware scripts (`Beta_2CycleByCycle_30s.m`) design the same kind of filter.

The "gold standard" `simout` passes through that same causal filter. So the accuracy above
measures how well NRO tracks the *delayed* filtered signal. Against any zero-phase reference of
the artifact-free signal, the delivered phases are at chance:

- R ≈ 0.1–0.17 and ~50% within ±90°.
- This holds for Butterworth 20–25, 18–24 and 13–30 Hz references and an FIR 18–26 Hz reference.
- Reproduce with the `zp` fields of `eval_phase`.

Small changes in beta frequency turn a 210 ms delay into large phase errors (±1 Hz ≈ ±75°).
It is unclear whether the paper's in-vivo oHT validation used a zero-phase reference.
**For the 250 Hz port, the filter delay is a bigger accuracy limit than the sampling rate**, because
the delay depends on the filter's bandwidth and order, not on fs. Both references should be reported.

## Hard-coded 4096 Hz values (to change for 250 Hz)
- `del = 1/4096` (NRO ExSolCoefs)
- `fs = 4096` and `width = floor(12e-3*fs)` (Kalman init; 12 ms is 3 samples at 250 Hz)
- AR(2) coefficients `A = [1.99798, -0.99964]` (refit at 250 Hz)
- Chebyshev coefficients
- The 25 recorded artifact templates
- All `SampleTime` settings and the solver `FixedStep`
- The ±0.02 rad trigger window: one 22 Hz sample at 250 Hz is ~32°, so a crossing or prediction rule is needed.
