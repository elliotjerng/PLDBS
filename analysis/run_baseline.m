function res = run_baseline(target, method, stopTime, tag, width_ms, cfg)
%RUN_BASELINE Simulate SimulnkModel/Estimationdataset1.slx and save the outputs.
%   res = run_baseline()                     % model exactly as shipped (Target 3*pi/4, NRO)
%   res = run_baseline(target, method, stopTime, tag)
%     target   : target phase in rad (default [] = keep the hardcoded 3*pi/4)
%     method   : Multiport-switch control, 1=arHT 2=NRO 3=ZC (default [] = keep 2)
%     stopTime : seconds (default [] = keep 60)
%     tag      : name for analysis/results/<tag>.mat (default 'baseline_raw'; 'none' = don't save)
%     width_ms : Kalman blanking window in ms (default [] = keep 12 ms)
%     cfg      : struct with .model (default 'Estimationdataset1'), .dataFile
%                (default SimulnkModel/dataset1.mat), .fs (default 4096) -
%                e.g. a model built by analysis250/build_model.m
%
%   The .slx file on disk is never modified: any changes are made to the loaded
%   copy, which is closed without saving. Extra signals that the model does not
%   log itself (stim trigger, raw+artifact, Kalman output before bandpass) are
%   captured with Simulink signal logging.
%
%   Model wiring (from analysis/inspect_model.m):
%     rawNot -> Add(+artifact) -> Kalman filter [Kalman -> Chebyshev bandpass]
%            -> Manual Switch (setting 0 = Kalman path) -> Phase Estimation
%     Phase Estimation outputs: 1=arHT, 2=NRO, 3=ZC, 4=SSPE  (logged simout1..4)
%     Amplitude outputs: simout6=arHT/ecHT, simout5=NRO, simout7=moving window, simout8=SSPE
%     simout = root "Filter" (same bandpass) applied to the artifact-free rawNot
%     Multiport switch (Constant) selects which phase drives "Pulse generator2".

if nargin < 1, target = []; end
if nargin < 2, method = []; end
if nargin < 3, stopTime = []; end
if nargin < 4 || isempty(tag), tag = 'baseline_raw'; end
if nargin < 5, width_ms = []; end
if nargin < 6, cfg = struct(); end

here  = fileparts(mfilename('fullpath'));
root  = fileparts(here);
addpath(fullfile(root, 'SimulnkModel'));
if ~isfield(cfg, 'model'),    cfg.model = 'Estimationdataset1'; end
if ~isfield(cfg, 'dataFile'), cfg.dataFile = fullfile(root, 'SimulnkModel', 'dataset1.mat'); end
if ~isfield(cfg, 'fs'),       cfg.fs = 4096; end
mdl = cfg.model;
outdir = fullfile(here, 'results');
if ~exist(outdir, 'dir'), mkdir(outdir); end

S = load(cfg.dataFile, 'rawNot');
rawNot = S.rawNot;

if bdIsLoaded(mdl), close_system(mdl, 0); end
load_system(mdl);
cleanup = onCleanup(@() close_system(mdl, 0));   % never save

% ---- optional, in-memory parameter changes ----
if ~isempty(target)
    ch = find(sfroot, '-isa', 'Stateflow.EMChart', 'Path', [mdl '/Pulse generator2/MATLAB Function1']);
    assert(numel(ch) == 1, 'Pulse generator chart not found');
    new = regexprep(ch.Script, 'Target\s*=\s*[^;]*;', sprintf('Target = %.15g;', target), 'once');
    assert(~strcmp(new, ch.Script) || contains(ch.Script, sprintf('%.15g', target)), 'Target line not replaced');
    ch.Script = new;
end
if ~isempty(width_ms)
    ch = find(sfroot, '-isa', 'Stateflow.EMChart', 'Path', [mdl '/Kalman filter/MATLAB Function']);
    assert(numel(ch) == 1, 'Kalman init chart not found');
    new = regexprep(ch.Script, 'width\s*=\s*floor\(12\*10\^-3\*fs\);', sprintf('width = floor(%g*10^-3*fs);', width_ms), 'once');
    assert(~strcmp(new, ch.Script) || width_ms == 12, 'Kalman width line not replaced');
    ch.Script = new;
end
if ~isempty(method)
    set_param([mdl '/Constant'], 'Value', num2str(method));
end
if ~isempty(stopTime)
    set_param(mdl, 'StopTime', num2str(stopTime));
end

% ---- log extra signals ----
logsig(mdl, [mdl '/Pulse generator2'], 1, 'stim');        % trigger (0/1)
logsig(mdl, [mdl '/Add'], 1, 'rawArt');                   % raw + stimulation artifact
logsig(mdl, [mdl '/Kalman filter'], 1, 'kalBP');           % Kalman + bandpass (phase-estimator input)
logsig(mdl, [mdl '/Kalman filter/MATLAB Function1'], 1, 'kal'); % Kalman output before bandpass
logsig(mdl, [mdl '/Stimulation Genarator'], 1, 'artifact');% injected artifact
logsig(mdl, [mdl '/From' newline 'Workspace'], 1, 'clean'); % artifact-free input as the model sees it
set_param(mdl, 'SignalLogging', 'on', 'SignalLoggingName', 'logsout');

fprintf('Simulating %s (target=%s, method=%s, stop=%s)...\n', mdl, ...
    num2str(target), get_param([mdl '/Constant'], 'Value'), get_param(mdl, 'StopTime'));
tic;
in  = Simulink.SimulationInput(mdl);
in  = in.setVariable('rawNot', rawNot);
out = sim(in);
fprintf('Simulation finished in %.1f s\n', toc);
if ~isempty(out.ErrorMessage), error(out.ErrorMessage); end

% ---- collect ----
res = struct();
res.fs = cfg.fs;
res.model = mdl;
res.target = target; if isempty(res.target), res.target = 3*pi/4; end
res.method = str2double(get_param([mdl '/Constant'], 'Value'));
res.stopTime = str2double(get_param(mdl, 'StopTime'));
if isempty(width_ms), width_ms = 12; end
res.width_ms = width_ms;
res.width = floor(width_ms*1e-3*res.fs);
names = {'simout','simout1','simout2','simout3','simout4','simout5','simout6','simout7','simout8'};
for k = 1:numel(names)
    if any(strcmp(out.who, names{k}))
        res.(names{k}) = squeeze(tsdata(out.get(names{k})));
    end
end
ls = out.logsout;
for nm = {'stim','rawArt','kalBP','kal','artifact','clean'}
    e = ls.getElement(nm{1});
    res.(nm{1}) = squeeze(e.Values.Data);
    if strcmp(nm{1}, 'stim'), res.t = e.Values.Time; end
end
res.rawNot = rawNot;
if ~strcmp(tag, 'none')
    save(fullfile(outdir, [tag '.mat']), '-struct', 'res', '-v7.3');
    fprintf('Saved %s', fullfile(outdir, [tag '.mat']));
end
fprintf('  (%d stim triggers)\n', nnz(diff([0; res.stim(:)]) > 0));
end

function logsig(~, blk, port, name)
ph = get_param(blk, 'PortHandles');
h  = ph.Outport(port);
set_param(h, 'DataLogging', 'on', 'DataLoggingNameMode', 'Custom', 'DataLoggingName', name);
end

function d = tsdata(v)
if isa(v, 'timeseries'), d = v.Data;
elseif isstruct(v) && isfield(v, 'signals'), d = v.signals.values;
else, d = v;
end
end
