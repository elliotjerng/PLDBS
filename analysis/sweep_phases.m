function S = sweep_phases(cfg, tag, opts)
%SWEEP_PHASES Replicate the paper's STN-beta simulation numbers (Table 2, Table 3, Sec 3.2).
%   sweep_phases()                      % shipped model -> results/sweep_metrics.mat + baseline_summary.md
%   S = sweep_phases(cfg, tag, opts)    % any model (cfg as in run_baseline), saved as results/<tag>.mat
%     opts.methods  : estimator ids to sweep (default [1 2 3] = arHT, NRO, ZC)
%     opts.widths_ms: Kalman windows for the Table 2 sweep (default 8:12)
%     opts.width_ms : Kalman window (ms) for the phase sweep (default [] = model default 12 ms)
%     opts.targets  : target phases, paper convention (default -180:45:135)
%     opts.summary  : write the markdown summary (default true for the shipped model)
%
%   Phase sweep: 8 target phases (paper convention -180:45:135, rising = 0)
%   x the phase estimators selectable by the model's Multiport Switch
%   (SSPE is computed but not wired to the trigger).
%   Width sweep: Kalman blanking window, NRO, as-shipped target.
if nargin < 1, cfg = struct(); end
if nargin < 2 || isempty(tag), tag = 'sweep_metrics'; end
if nargin < 3, opts = struct(); end
if ~isfield(opts, 'methods'),   opts.methods = [1 2 3]; end
if ~isfield(opts, 'widths_ms'), opts.widths_ms = 8:12; end
if ~isfield(opts, 'width_ms'),  opts.width_ms = []; end   % Kalman window used in the phase sweep
if ~isfield(opts, 'targets'),   opts.targets = -180:45:135; end
if ~isfield(opts, 'summary'),   opts.summary = strcmp(tag, 'sweep_metrics'); end

here = fileparts(mfilename('fullpath'));
names = {'arHT', 'NRO', 'ZC'};
methods = [num2cell(opts.methods(:)) names(opts.methods)'];
tgt_paper = opts.targets;
tgt_model = angle(exp(1i*deg2rad(tgt_paper - 90)));  % model convention = paper - 90 deg, wrapped to [-pi, pi]

M = struct('method', {}, 'name', {}, 'tgt_paper', {}, 'm', {});
for i = 1:size(methods, 1)
    for j = 1:numel(tgt_paper)
        res = run_baseline(tgt_model(j), methods{i,1}, [], 'none', opts.width_ms, cfg);
        m   = eval_phase(res, struct('verbose', true));
        M(end+1) = struct('method', methods{i,1}, 'name', methods{i,2}, 'tgt_paper', tgt_paper(j), 'm', m); %#ok<AGROW>
    end
end

W = struct('width_ms', {}, 'm', {});
for w = opts.widths_ms
    res = run_baseline([], 2, [], 'none', w, cfg);
    m   = eval_phase(res, struct('verbose', true));
    W(end+1) = struct('width_ms', w, 'm', m); %#ok<AGROW>
end
S = struct('M', M, 'W', W, 'methods', {methods}, 'tgt_paper', tgt_paper, 'cfg', cfg);
f = fullfile(here, 'results', [tag '.mat']);
save(f, '-struct', 'S');
fprintf('Saved %s\n', f);
if opts.summary, summarize_sweep(f); end
end
