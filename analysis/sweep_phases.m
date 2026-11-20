%SWEEP_PHASES Replicate the paper's STN-beta simulation numbers (Table 2, Table 3, Sec 3.2).
%   Phase sweep: 8 target phases (paper convention -180:45:135, rising = 0)
%   x 3 phase estimators selectable by the model's Multiport Switch
%   (1 = arHT, 2 = NRO, 3 = ZC; SSPE is computed but not wired to the trigger).
%   Width sweep: Kalman blanking window 8..12 ms (Table 2), NRO, as-shipped target.
%   Writes results/sweep_metrics.mat and results/baseline_summary.md.
here = fileparts(mfilename('fullpath'));
cd(here);
methods = {1, 'arHT'; 2, 'NRO'; 3, 'ZC'};
tgt_paper = -180:45:135;                 % deg, paper convention
tgt_model = angle(exp(1i*deg2rad(tgt_paper - 90)));  % model convention = paper - 90 deg, wrapped to [-pi, pi]

M = struct('method', {}, 'name', {}, 'tgt_paper', {}, 'm', {});
for i = 1:size(methods, 1)
    for j = 1:numel(tgt_paper)
        res = run_baseline(tgt_model(j), methods{i,1}, [], 'none');
        m   = eval_phase(res, struct('verbose', true));
        M(end+1) = struct('method', methods{i,1}, 'name', methods{i,2}, 'tgt_paper', tgt_paper(j), 'm', m); %#ok<SAGROW>
    end
end

W = struct('width_ms', {}, 'm', {});
for w = 8:12
    res = run_baseline([], 2, [], 'none', w);
    m   = eval_phase(res, struct('verbose', true));
    W(end+1) = struct('width_ms', w, 'm', m); %#ok<SAGROW>
end
save(fullfile(here, 'results', 'sweep_metrics.mat'), 'M', 'W', 'methods', 'tgt_paper');
summarize_sweep(fullfile(here, 'results', 'sweep_metrics.mat'));
