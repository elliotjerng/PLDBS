%RUN_PORT250 Build all model variants and run every sweep for the 250 Hz port.
%   Results: analysis/results/port_*.mat, then summarize_port250 writes
%   analysis250/results/summary_250_vs_4096.md (+ figure).
%   The 4096 Hz shipped-model sweep (analysis/results/sweep_metrics.mat) is reused.
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
d = fullfile(root, 'SimulnkModel');
addpath(here, fullfile(root, 'analysis'));

% ---- build ----
cd(here);
build_model(4096, struct('trigger', 'nearest'));
build_model(4096, struct('trigger', 'nearest', 'artifact', 'off'));
build_model(250);
build_model(250, struct('trigger', 'nearest'));
build_model(250, struct('trigger', 'nearest', 'artifact', 'off'));
build_model(250, struct('trigger', 'nearest', 'aa', 'ideal'));
build_model(250, struct('trigger', 'predict'));
build_model(250, struct('trigger', 'predict', 'artifact', 'off'));

W250 = 28;   % ms = 7 samples: the measured length of the anti-aliased artifact at 250 Hz
c = @(m, fs, f) struct('model', m, 'fs', fs, 'dataFile', fullfile(d, f));
runs = {
  % tag                    cfg                                                                              opts
  'port_4096n',         c('Estimationdataset1_fs4096_nearest', 4096, 'dataset1.mat'),               struct('methods', [2 1 3], 'widths_ms', 8:12)
  'port_4096n_noart',   c('Estimationdataset1_fs4096_nearest_noart', 4096, 'dataset1.mat'),         struct('methods', 2, 'widths_ms', [])
  'port_250n',          c('Estimationdataset1_fs250_nearest', 250, 'dataset1_fs250_causal.mat'),    struct('methods', [2 1 3], 'width_ms', W250, 'widths_ms', 4:4:40)
  'port_250n_noart',    c('Estimationdataset1_fs250_nearest_noart', 250, 'dataset1_fs250_causal.mat'), struct('methods', 2, 'widths_ms', [])
  'port_250n_ideal',    c('Estimationdataset1_fs250_nearest_ideal', 250, 'dataset1_fs250_ideal.mat'),  struct('methods', 2, 'width_ms', W250, 'widths_ms', [])
  'port_250p',          c('Estimationdataset1_fs250_predict', 250, 'dataset1_fs250_causal.mat'),    struct('methods', 2, 'width_ms', W250, 'widths_ms', [])
  'port_250p_noart',    c('Estimationdataset1_fs250_predict_noart', 250, 'dataset1_fs250_causal.mat'), struct('methods', 2, 'widths_ms', [])
  'port_250orig',       c('Estimationdataset1_fs250', 250, 'dataset1_fs250_causal.mat'),            struct('methods', 2, 'width_ms', W250, 'widths_ms', [])
};
for k = 1:size(runs, 1)
    fprintf('\n##### %s\n', runs{k,1});
    o = runs{k,3}; o.summary = false;
    sweep_phases(runs{k,2}, runs{k,1}, o);
end
summarize_port250();
