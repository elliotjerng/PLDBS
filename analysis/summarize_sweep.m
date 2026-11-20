function summarize_sweep(matfile)
%SUMMARIZE_SWEEP Write results/baseline_summary.md comparing the sweep to the paper.
S = load(matfile); M = S.M; W = S.W;
tols = M(1).m.tols;
paper = struct('ZC', [11.99 7.00 25.80 4.91], 'NRO', [9.55 6.12 20.58 2.14], 'arHT', [15.16 10.32 22.60 1.79]);
fid = fopen(fullfile(fileparts(matfile), 'baseline_summary.md'), 'w');
c = onCleanup(@() fclose(fid));
fprintf(fid, '# PLDBS Simulink baseline (4096 Hz, STN beta dataset1) vs. Guo et al. 2025\n\n');
fprintf(fid, 'Model `SimulnkModel/Estimationdataset1.slx` run unmodified on disk (target phase / estimator / Kalman window changed in memory only). 60 s simulated, first 2 s excluded. Gold standard: offline Hilbert transform of the artifact-free signal passed through the model''s own bandpass (`simout`). "zero-phase" = stricter reference using a zero-phase filter, which also counts the causal bandpass delay.\n\n');
fprintf(fid, '## Phase locking across 8 target phases (Table 3, STN beta)\n\n');
fprintf(fid, '| Method | bias (this) | bias (paper) | std (this) | std (paper) | acc ±30° | acc ±45° | acc ±90° | acc ±30° amp>2 | bias zero-phase |\n|---|---|---|---|---|---|---|---|---|---|\n');
for nm = {'NRO', 'ZC', 'arHT'}
    k = strcmp({M.name}, nm{1}); mm = [M(k).m]; r = [mm.ref]; z = [mm.zp];
    b = [r.bias]; s = [r.std]; A = vertcat(r.acc); A2 = vertcat(r.acc_amp2); p = paper.(nm{1});
    fprintf(fid, '| %s | %.2f° ± %.2f° | %.2f° ± %.2f° | %.2f° ± %.2f° | %.2f° ± %.2f° | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %.1f° ± %.1f° |\n', nm{1}, ...
        mean(b), std(b), p(1), p(2), mean(s), std(s), p(3), p(4), 100*mean(A(:, tols==30)), 100*mean(A(:, tols==45)), ...
        100*mean(A(:, tols==90)), 100*mean(A2(:, tols==30)), mean([z.bias]), std([z.bias]));
end
fprintf(fid, '\nPaper Sec 3.2 (NRO, STN beta): 93.24%% within ±45°; 95.42%% within ±30° when amplitude > 2 µV. SSPE (paper bias 15.45°, std 19.53°) is not selectable by the model''s trigger switch, so it is not swept.\n\n');
fprintf(fid, '### NRO per target\n\n| target (paper conv.) | target (model conv.) | pulses | signed bias | std | acc ±45° |\n|---|---|---|---|---|---|\n');
k = find(strcmp({M.name}, 'NRO'));
for i = k
    m = M(i).m;
    fprintf(fid, '| %d° | %.0f° | %d | %+.2f° | %.2f° | %.1f%% |\n', M(i).tgt_paper, m.target_model_deg, m.nPulses, m.ref.signedbias, m.ref.std, 100*m.ref.acc(tols==45));
end
fprintf(fid, '\n## Artifact suppression vs. blanking window (Table 2)\n\n');
fprintf(fid, 'Relative error of beta-band spectral amplitude (peak ± 2.5 Hz) vs. the artifact-free signal; time-domain envelope error in parentheses. Paper: Kalman 36.18 / 5.21 / 5.56 / 5.62 / 5.84 %%; irregular sampling 409.91 / 14.56 / 13.52 / 11.41 / 10.84 %% for 8–12 ms.\n\n');
fprintf(fid, '| window | Kalman | blank + interp | sample-hold | zeroing | NRO bias | NRO std | acc ±45° |\n|---|---|---|---|---|---|---|---|\n');
for i = 1:numel(W)
    a = W(i).m.art; r = W(i).m.ref;
    fprintf(fid, '| %d ms | %.2f%% (%.1f%%) | %.2f%% (%.1f%%) | %.2f%% (%.1f%%) | %.2f%% (%.1f%%) | %.2f° | %.2f° | %.1f%% |\n', W(i).width_ms, ...
        100*a.spec.kalman, 100*a.env.kalman, 100*a.spec.blank, 100*a.env.blank, 100*a.spec.hold, 100*a.env.hold, ...
        100*a.spec.zero, 100*a.env.zero, r.bias, r.std, 100*r.acc(tols==45));
end
fprintf('Wrote %s\n', fullfile(fileparts(matfile), 'baseline_summary.md'));
end
