% Re-run sweep entries whose model-convention target was outside [-pi, pi]
% (bug in the first sweep run: targets -270/-225 deg never trigger).
here = fileparts(mfilename('fullpath')); f = fullfile(here, 'results', 'sweep_metrics.mat');
S = load(f); M = S.M;
for i = 1:numel(M)
    if M(i).m.nPulses == 0
        t = angle(exp(1i*deg2rad(M(i).tgt_paper - 90)));
        res = run_baseline(t, M(i).method, [], 'none');
        M(i).m = eval_phase(res, struct('verbose', true));
    end
end
S.M = M; save(f, '-struct', 'S');
summarize_sweep(f);
