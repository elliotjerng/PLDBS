# PLDBS Simulink baseline (4096 Hz, STN beta dataset1) vs. Guo et al. 2025

Model `SimulnkModel/Estimationdataset1.slx` run unmodified on disk (target phase / estimator / Kalman window changed in memory only). 60 s simulated, first 2 s excluded. Gold standard: offline Hilbert transform of the artifact-free signal passed through the model's own bandpass (`simout`). "zero-phase" = stricter reference using a zero-phase filter, which also counts the causal bandpass delay.

## Phase locking across 8 target phases (Table 3, STN beta)

| Method | bias (this) | bias (paper) | std (this) | std (paper) | acc ±30° | acc ±45° | acc ±90° | acc ±30° amp>2 | bias zero-phase |
|---|---|---|---|---|---|---|---|---|---|
| NRO | 0.70° ± 0.66° | 9.55° ± 6.12° | 22.76° ± 1.08° | 20.58° ± 2.14° | 88.8% | 94.2% | 98.3% | 97.3% | 94.2° ± 4.4° |
| ZC | 1.77° ± 1.33° | 11.99° ± 7.00° | 28.73° ± 2.18° | 25.80° ± 4.91° | 83.0% | 90.2% | 96.9% | 92.6% | 88.4° ± 3.0° |
| arHT | 7.78° ± 4.21° | 15.16° ± 10.32° | 26.39° ± 2.49° | 22.60° ± 1.79° | 81.5% | 91.2% | 97.9% | 90.2% | 81.3° ± 9.0° |

Paper Sec 3.2 (NRO, STN beta): 93.24% within ±45°; 95.42% within ±30° when amplitude > 2 µV. SSPE (paper bias 15.45°, std 19.53°) is not selectable by the model's trigger switch, so it is not swept.

### NRO per target

| target (paper conv.) | target (model conv.) | pulses | signed bias | std | acc ±45° |
|---|---|---|---|---|---|
| -180° | 90° | 1253 | +0.24° | 22.18° | 93.8% |
| -135° | 135° | 1243 | -1.06° | 22.70° | 94.7% |
| -90° | -180° | 762 | +0.86° | 21.12° | 95.7% |
| -45° | -135° | 1244 | +0.09° | 22.36° | 94.4% |
| 0° | -90° | 1257 | +2.07° | 22.85° | 93.9% |
| 45° | -45° | 1251 | +0.38° | 23.06° | 93.6% |
| 90° | 0° | 1237 | -0.15° | 22.84° | 94.3% |
| 135° | 45° | 1251 | +0.73° | 24.98° | 93.4% |

## Artifact suppression vs. blanking window (Table 2)

Relative error of beta-band spectral amplitude (peak ± 2.5 Hz) vs. the artifact-free signal; time-domain envelope error in parentheses. Paper: Kalman 36.18 / 5.21 / 5.56 / 5.62 / 5.84 %; irregular sampling 409.91 / 14.56 / 13.52 / 11.41 / 10.84 % for 8–12 ms.

| window | Kalman | blank + interp | sample-hold | zeroing | NRO bias | NRO std | acc ±45° |
|---|---|---|---|---|---|---|---|
| 8 ms | 2.16% (6.6%) | 5.97% (16.1%) | 1.97% (8.5%) | 14.75% (18.4%) | 1.10° | 14.68° | 97.9% |
| 9 ms | 1.99% (7.5%) | 7.84% (10.1%) | 2.37% (10.0%) | 16.27% (20.5%) | 1.15° | 15.36° | 97.3% |
| 10 ms | 2.52% (9.5%) | 2.94% (6.1%) | 3.00% (11.6%) | 17.63% (22.1%) | 0.40° | 17.83° | 96.8% |
| 11 ms | 3.04% (11.7%) | 3.96% (7.9%) | 3.83% (13.7%) | 19.21% (24.1%) | 0.51° | 20.19° | 95.8% |
| 12 ms | 3.93% (13.8%) | 4.84% (9.3%) | 4.50% (15.0%) | 20.12% (25.5%) | 1.06° | 22.70° | 94.7% |
