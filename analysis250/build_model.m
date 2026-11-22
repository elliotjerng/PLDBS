function info = build_model(fs, opts)
%BUILD_MODEL Build a copy of Estimationdataset1.slx that runs at sampling rate fs.
%   info = build_model(250)
%   info = build_model(fs, opts)
%     opts.trigger : 'original' (|phi-target| < 0.02 rad, as shipped),
%                    'nearest'  (fire on the sample nearest the target phase), or
%                    'predict'  (nearest, aimed one sample early to cancel the 1-sample stim delay)
%     opts.aa      : 'causal' (default; 4th-order Butterworth low-pass at 100 Hz, causal,
%                    like an implant ADC) or 'ideal' (zero-phase polyphase resample)
%     opts.artifact: 'on' (default) or 'off' (templates zeroed: no-artifact control)
%     opts.bp      : 'cheby10' (default; the model's own bandpass redesigned at fs)
%                    or 'butter2wide' (low-delay variant: 2nd-order Butterworth 13-30 Hz)
%
%   The original SimulnkModel/Estimationdataset1.slx is never modified. Output:
%     SimulnkModel/<name>.slx and SimulnkModel/dataset1_fs<fs>_<aa>.mat (rawNot at fs)
%   build_model(4096) with defaults reproduces the shipped model (validation gate).
%
%   Every rate-dependent item was found by inspecting the model (analysis/README.md):
%     solver FixedStep and block SampleTimes; NRO ExSolCoefs del (x2); Kalman fs, width,
%     AR(2) matrix; Chebyshev bandpass gains (x5 FilterWizard subsystems); 25 artifact
%     templates; zero-crossing fs; SSPE Fs (x2); arHT buffers/windows/order; trigger rule.

if nargin < 2, opts = struct(); end
opts = setdef(opts, 'trigger', 'original');
opts = setdef(opts, 'aa', 'causal');
opts = setdef(opts, 'bp', 'cheby10');
opts = setdef(opts, 'artifact', 'on');
FS0 = 4096;

here = fileparts(mfilename('fullpath'));
mdir = fullfile(fileparts(here), 'SimulnkModel');
addpath(mdir);
src = 'Estimationdataset1';
name = sprintf('Estimationdataset1_fs%d', fs);
if ~strcmp(opts.trigger, 'original'), name = [name '_' opts.trigger]; end
if ~strcmp(opts.bp, 'cheby10'),       name = [name '_' opts.bp]; end
if ~strcmp(opts.aa, 'causal') && fs ~= FS0, name = [name '_' opts.aa]; end
if strcmp(opts.artifact, 'off'),      name = [name '_noart']; end

for m = {src, name}, if bdIsLoaded(m{1}), close_system(m{1}, 0); end, end
load_system(src);
save_system(src, fullfile(mdir, [name '.slx']));     % loaded model is now `name`
mdl = name;
info = struct('model', mdl, 'fs', fs, 'opts', opts, 'changes', {{}});

% ---------- 1. solver and block sample times ----------
set_param(mdl, 'FixedStep', sprintf('1/%d', fs));
for b = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'SampleTime', '1/4096')'
    set_param(b{1}, 'SampleTime', sprintf('1/%d', fs));
    note(sprintf('SampleTime 1/%d: %s', fs, clean(b{1})));
end

% ---------- 2. MATLAB Function (Stateflow EMChart) scripts ----------
charts = find(sfroot, '-isa', 'Stateflow.EMChart');
charts = charts(arrayfun(@(c) startsWith(c.Path, [mdl '/']), charts));
nHit = containers.Map();
for c = charts'
    s0 = c.Script; s = s0; p = c.Path;
    % NRO exact-solution coefficients (phase + amplitude devices)
    s = rep(s, 'del = 1/4096;', sprintf('del = 1/%d;', fs), 'ExSolCoefs');
    % zero-crossing and SSPE sampling rates
    s = rep(s, 'fs = 4096;', sprintf('fs = %d;', fs), 'fs');
    s = rep(s, 'Fs = 4096;', sprintf('Fs = %d;', fs), 'Fs');
    % Kalman AR(2): map the poles so the continuous-time model is unchanged
    if contains(s, 'A = [1.9979830,-0.99963582;1,0];')
        A = arMap([1.9979830 -0.99963582], FS0, fs);
        s = rep(s, 'A = [1.9979830,-0.99963582;1,0];', sprintf('A = [%.12g,%.12g;1,0];', A(1), A(2)), 'KalmanA');
        info.kalmanA = A;
    end
    % arHT windows (secondary estimator): re-tuned in time units for low fs
    if fs ~= FS0 && contains(s, 'Hilbet_length = 128;')
        s = rep(s, 'if length(input) >= 500', sprintf('if length(input) >= %d', arht(fs).buf), 'arHT');
        s = rep(s, 'order = 24;', sprintf('order = %d;', arht(fs).order), 'arHT');
        s = rep(s, 'Hilbet_length = 128;', sprintf('Hilbet_length = %d;', arht(fs).hil), 'arHT');
        s = rep(s, 'edge_length = 64;', sprintf('edge_length = %d;', arht(fs).edge), 'arHT');
    end
    % artifact templates
    if startsWith(strtrim(s), 'function Stimulation = Generator')
        T0 = templates(s);
        T  = decimateTemplates(T0, FS0, fs, opts.aa);
        if strcmp(opts.artifact, 'off'), T = zeros(size(T)); end
        s  = sprintf('function Stimulation = Generator\n\nStimulation = %s;\n', mat2str(T, 10));
        info.templates = struct('orig', T0, 'new', T);
        note(sprintf('artifact templates %dx%d -> %dx%d', size(T0), size(T)));
    end
    % trigger rule
    if contains(s, 'Target = 3*pi/4;') && any(strcmp(opts.trigger, {'nearest', 'predict'}))
        s = nearestTrigger(fs, strcmp(opts.trigger, 'predict'));
        note(['trigger: ' opts.trigger ' rule']);
    end
    if ~strcmp(s, s0)
        c.Script = s;
        k = clean(p); nHit(k) = 1;
    end
end
info.chartsChanged = nHit.keys;

% ---------- 2b. template Selector: row indices hard-coded to the template length ----------
if isfield(info, 'templates')
    sel = [mdl '/Stimulation Genarator/Enabled Subsystem/Selector'];
    L = size(info.templates.new, 1);
    set_param(sel, 'IndexParamArray', {sprintf('[1:%d]', L), '[1 42]'});
    note(sprintf('template Selector rows 1:%d', L));
end

% ---------- 3. Buffer blocks feeding arHT / moving window ----------
if fs ~= FS0
    for b = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', 'Buffer')'
        N0 = str2double(get_param(b{1}, 'N'));
        N  = ifelse(N0 == 500, arht(fs).buf, max(8, round(N0*fs/FS0)));
        set_param(b{1}, 'N', num2str(N), 'V', num2str(N-1));
        note(sprintf('Buffer N %d -> %d: %s', N0, N, clean(b{1})));
    end
end

% ---------- 4. bandpass gains (5 biquads, numerator [1 0 -1]) ----------
[sos, sv] = bandpass(fs, opts.bp);
info.sos = sos; info.scale = sv;
for f = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Tag', 'FilterWizardSubSystem')'
    for k = 1:5
        g = @(n) [f{1} '/' n];
        setGain(g(sprintf('a(2)(%d)', k)), sos(k, 5));
        setGain(g(sprintf('a(3)(%d)', k)), sos(k, 6));
        setGain(g(sprintf('s(%d)', k)),    sv(k));
    end
    note(sprintf('bandpass gains (%s): %s', opts.bp, clean(f{1})));
end

save_system(mdl);
close_system(mdl, 0);

% ---------- 5. data at fs ----------
S = load(fullfile(mdir, 'dataset1.mat'), 'rawNot');
dataFile = fullfile(mdir, sprintf('dataset1_fs%d_%s.mat', fs, opts.aa));
if fs == FS0
    rawNot = S.rawNot;                                   %#ok<NASGU>  unchanged
else
    rawNot = resampleData(S.rawNot, FS0, fs, opts.aa);   %#ok<NASGU>
end
save(dataFile, 'rawNot');
info.dataFile = dataFile;
fprintf('Built %s (%d changes); data %s\n', mdl, numel(info.changes), dataFile);

    function note(msg), info.changes{end+1} = msg; end
end

% ===========================================================================
function s = rep(s, old, new, ~)
s = strrep(s, old, new);
end

function A = arMap(a, fsFrom, fsTo)
% x_t = a1 x_{t-1} + a2 x_{t-2}; poles z -> z^(fsFrom/fsTo) keeps the analog model
p = roots([1 -a(1) -a(2)]);
q = p.^(fsFrom/fsTo);
c = real(poly(q));
A = [-c(2) -c(3)];
end

function P = arht(fs)
% arHT windows at low fs (original at 4096: buffer 500, order 24, Hilbert 128, edge 64)
P = struct('buf', round(0.256*fs), 'order', 8, 'hil', 2^nextpow2(round(0.128*fs)), 'edge', round(0.032*fs));
end

function T = templates(s)
tok = regexp(s, 'Stimulation\s*=\s*\[(.*?)\];', 'tokens', 'once');
T = str2num(['[' tok{1} ']']); %#ok<ST2NM>
end

function T = decimateTemplates(T0, fs0, fs, aa)
% What a fs-rate ADC with anti-alias filter `aa` records of each 4096 Hz template.
if fs == fs0, T = T0; return; end
pad = zeros(round(0.1*fs0), size(T0, 2));
X = [T0; pad];
X = aaFilter(X, fs0, aa);
t = (0:floor((size(X,1)-1)*fs/fs0))';
T = interp1((0:size(X,1)-1)', X, t*fs0/fs, 'linear');
last = find(max(abs(T), [], 2) > 1e-3*max(abs(T(:))), 1, 'last');   % trim tail
T = T(1:last+1, :);
end

function X = aaFilter(X, fs0, aa)
[b, a] = butter(4, 100/(fs0/2));
switch aa
    case 'causal', X = filter(b, a, X);
    case 'ideal',  X = filtfilt(b, a, X);
    otherwise, error('unknown aa %s', aa);
end
end

function R = resampleData(R0, fs0, fs, aa)
x = R0(:, 2);
switch aa
    case 'causal'
        x = aaFilter(x, fs0, 'causal');
        n = (1:floor(numel(x)*fs/fs0))';
        y = interp1((1:numel(x))'/fs0, x, n/fs, 'linear', 'extrap');
    case 'ideal'
        [p, q] = rat(fs/fs0);
        y = resample(x, p, q);
        n = (1:numel(y))';
end
R = [n/fs y(:)];
end

function [sos, sv] = bandpass(fs, kind)
switch kind
    case 'cheby10'   % identified exactly from the shipped model's gains
        d = fdesign.bandpass('N,Fp1,Fp2,Ap', 10, 18, 24, 1, fs);
        Hd = design(d, 'cheby1');
    case 'butter2wide'
        % A low-order filter does not fit the 5-section structure; needs a
        % structural edit (optional plan step 6) - not implemented yet.
        error('build_model:notImplemented', 'low-delay bandpass variant not implemented yet');
    otherwise, error('unknown bp %s', kind);
end
sos = Hd.sosMatrix; sv = Hd.ScaleValues;
assert(size(sos, 1) == 5, 'bandpass must have 5 sections to fit the model structure');
assert(all(abs(sos(:,1:3) - [1 0 -1]) < 1e-9, 'all'), 'numerators must be [1 0 -1]');
assert(abs(sv(end) - 1) < 1e-12, 'unexpected output scale value');
end

function setGain(b, v)
set_param(b, 'Gain', sprintf('%.18g', v));
end

function s = nearestTrigger(fs, lead)
% Fire on the sample nearest the target phase. Phase advance per sample is
% estimated from consecutive phase estimates; a half-cycle lockout (at 22 Hz)
% prevents double triggers. Works at any fs.
% lead = 1 ('predict'): aim one sample early, compensating the model's one-sample
% decision-to-stimulation delay (Delay5 in Pulse generator2): ~32 deg at 250 Hz.
s = sprintf([ ...
'function out  = fcn(input,previous)\n' ...
'persistent lastPhase lock\n' ...
'Target = 3*pi/4;\n' ...
'fs = %d; f0 = 22;\n' ...
'if isempty(lastPhase), lastPhase = input; lock = 0; end\n' ...
'dphi = angle(exp(1i*(input - lastPhase)));\n' ...
'if dphi <= 0 || dphi > pi/2, dphi = 2*pi*f0/fs; end\n' ...
'err = angle(exp(1i*(Target - input))) - %d*dphi;\n' ...
'out = 0;\n' ...
'if lock > 0\n' ...
'    lock = lock - 1;\n' ...
'elseif previous == 0 && err > -dphi/2 && err <= dphi/2\n' ...
'    out = 1;\n' ...
'    lock = round(0.5*fs/f0);\n' ...
'end\n' ...
'lastPhase = input;\n' ...
'end\n'], fs, lead);
end

function o = setdef(o, f, v)
if ~isfield(o, f) || isempty(o.(f)), o.(f) = v; end
end

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end

function s = clean(s)
s = strrep(s, newline, ' ');
end
