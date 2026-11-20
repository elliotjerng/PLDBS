function m = eval_phase(res, opts)
%EVAL_PHASE Phase-locking accuracy and artifact suppression for one simulation.
%   m = eval_phase(res)            res = output of run_baseline (struct or .mat path)
%   m = eval_phase(res, opts)      opts.verbose (true), opts.fig ('' = none, else png path)
%
% Phase convention: the model's estimators (NRO etc.) output angle(hilbert(x)),
% i.e. 0 = peak, +90 = falling zero crossing, +/-180 = trough, -90 = rising.
% The paper's figures use rising = 0, peak = 90 (paper = model + 90 deg).
% All errors are convention-independent; targets are reported in both.
%
% Gold standards (offline Hilbert transform, "oHT", on the ARTIFACT-FREE signal):
%   ref   : hilbert of `simout` = the model's own Chebyshev bandpass applied to the
%           artifact-free rawNot. This is the reference the model was built to log
%           and matches the paper's numbers (filter delay not counted as error).
%   zp    : hilbert of a zero-phase (filtfilt) 4th-order Butterworth bandpass,
%           peak +/- 2.5 Hz (paper Sec. 2.8). Stricter: also counts the group
%           delay of the causal real-time bandpass.
%
% Metrics (paper Sec. 2.3):
%   bias = |circular mean(phi_delivered - phi_target)|
%   std  = circular std of phi_delivered (deg)
%   acc(tol) = fraction of pulses with |phi_delivered - phi_target| < tol
%   amplitude gating at 2 and 5 (data units, uV) using the oHT envelope
%   Artifact suppression: relative error of the beta-band amplitude envelope,
%   mean|A_x - A_clean| / mean(A_clean), for the Kalman output vs. blanking with
%   linear interpolation ("irregular sampling") vs. no removal.

if ischar(res) || isstring(res), res = load(res); end
if nargin < 2, opts = struct(); end
if ~isfield(opts, 'verbose'), opts.verbose = true; end
if ~isfield(opts, 'fig'), opts.fig = ''; end

fs = res.fs;
N  = numel(res.stim);
x  = res.rawNot(1:N, 2);
skip = round(2*fs);                      % ignore filter/estimator start-up (2 s)

% ---------- gold standards ----------
[b, a]   = butter(2, 2/(fs/2), 'high');  x_hp = filtfilt(b, a, x);   % 2 Hz HP (Sec 2.4)
[P, f]   = pwelch(x_hp(skip:end), 2*fs, fs, [], fs);
sel      = f >= 13 & f <= 30;  fpk = f(sel);  [~, i] = max(P(sel));  fpk = fpk(i);
[b, a]   = butter(2, [fpk-2.5 fpk+2.5]/(fs/2));
y_zp     = filtfilt(b, a, x_hp);
an_zp    = hilbert(y_zp);
an_ref   = hilbert(res.simout(:));
gold.ref = struct('ph', angle(an_ref), 'amp', abs(an_ref));
gold.zp  = struct('ph', angle(an_zp),  'amp', abs(an_zp));

% ---------- delivered pulses ----------
onAll = find(diff([0; res.stim(:) > 0.5]) > 0);
on = onAll(onAll > skip);
tgt = wrapToPi(res.target);
tols = [0 2 5 10 15 20 25 30 45 60 90];

m = struct('target_model_deg', rad2deg(tgt), 'target_paper_deg', rad2deg(wrapToPi(tgt + pi/2)), ...
           'method', res.method, 'nPulses', numel(on), 'rate_Hz', numel(on)/((N-skip)/fs), ...
           'fpeak', fpk, 'tols', tols);
for g = {'ref', 'zp'}
    G   = gold.(g{1});
    err = wrapToPi(G.ph(on) - tgt);
    amp = G.amp(on);
    s   = struct();
    s.err_deg  = rad2deg(err);
    s.amp      = amp;
    s.bias     = abs(rad2deg(angle(mean(exp(1i*err)))));
    s.signedbias = rad2deg(angle(mean(exp(1i*err))));
    R          = abs(mean(exp(1i*err)));
    s.std      = rad2deg(sqrt(-2*log(R)));
    s.R        = R;
    s.acc      = arrayfun(@(t) mean(abs(s.err_deg) < t), tols);
    for th = [2 5]
        k = amp > th;
        s.(sprintf('acc_amp%d', th)) = arrayfun(@(t) mean(abs(s.err_deg(k)) < t), tols);
        s.(sprintf('frac_amp%d', th)) = mean(k);
    end
    m.(g{1}) = s;
end

% ---------- artifact suppression ----------
% Primary (paper Fig 1B / Table 2 framing): spectral amplitude error in the
% individual beta band (peak +/- 2.5 Hz), mean|sqrt(P_x) - sqrt(P_clean)| / mean sqrt(P_clean).
% Secondary: time-domain beta-envelope error (stricter: waveform inside the gaps).
win = artifactWindow(res, fs);
m.art.width_samples = win;
cands = struct('kalman', res.kal(:), ...
               'blank',  blankInterp(res.rawArt(:), onAll, win), ...   % drop + linear interp
               'hold',   holdLast(res.rawArt(:), onAll, win), ...      % sample-and-hold
               'zero',   zeroOut(res.rawArt(:), onAll, win), ...       % zeroing
               'none',   res.rawArt(:));
A0  = envBeta(x, fpk, fs);
[P0, fw] = pwelch(x(skip:end), 2*fs, fs, [], fs);
band = fw >= fpk-2.5 & fw <= fpk+2.5;
for c = fieldnames(cands)'
    s = cands.(c{1});
    Px = pwelch(s(skip:end), 2*fs, fs, [], fs);
    m.art.spec.(c{1}) = mean(abs(sqrt(Px(band)) - sqrt(P0(band)))) / mean(sqrt(P0(band)));
    m.art.env.(c{1})  = relerr(envBeta(s, fpk, fs), A0, skip);
end
m.art.kalBP_vs_simout_r = min(corrcoef(res.kalBP(skip:end), res.simout(skip:end)), [], 'all');

if opts.verbose
    fprintf('\n=== method %d | target %.0f deg (model conv.) = %.0f deg (paper conv.) | %d pulses (%.1f Hz), beta peak %.1f Hz\n', ...
        m.method, m.target_model_deg, m.target_paper_deg, m.nPulses, m.rate_Hz, fpk);
    for g = {'ref', 'zp'}
        s = m.(g{1});
        fprintf('  [%-3s] bias %6.2f deg (signed %+6.1f)  std %6.2f deg | acc +/-30 %.1f%%  +/-45 %.1f%%  +/-90 %.1f%% | amp>2: +/-30 %.1f%%\n', ...
            g{1}, s.bias, s.signedbias, s.std, 100*s.acc(tols==30), 100*s.acc(tols==45), 100*s.acc(tols==90), 100*s.acc_amp2(tols==30));
    end
    a = m.art;
    fprintf('  artifact rel. error, window %d samples = %.1f ms\n', win, 1000*win/fs);
    fprintf('    beta spectral amp : Kalman %5.2f%% | blank+interp %5.2f%% | hold %5.2f%% | zero %5.2f%% | none %.0f%%\n', ...
        100*[a.spec.kalman a.spec.blank a.spec.hold a.spec.zero a.spec.none]);
    fprintf('    beta envelope     : Kalman %5.2f%% | blank+interp %5.2f%% | hold %5.2f%% | zero %5.2f%% | none %.0f%%\n', ...
        100*[a.env.kalman a.env.blank a.env.hold a.env.zero a.env.none]);
    fprintf('    corr(Kalman+bandpass, clean+bandpass) = %.3f\n', a.kalBP_vs_simout_r);
end

if ~isempty(opts.fig)
    fig = figure('Visible', 'off', 'Position', [0 0 1200 380]);
    subplot(1,3,1);
    polarhistogram(deg2rad(m.ref.err_deg) + tgt, 36, 'FaceColor', [.2 .4 .7]); hold on;
    polarplot([tgt tgt], [0 max(histcounts(wrapToPi(deg2rad(m.ref.err_deg)+tgt), 36))], 'r--', 'LineWidth', 1.5);
    title(sprintf('Delivered phase (ref oHT), target %.0f\\circ', m.target_model_deg));
    subplot(1,3,2);
    histogram(m.ref.err_deg, -180:10:180, 'FaceColor', [.2 .4 .7]); hold on;
    histogram(m.zp.err_deg, -180:10:180, 'FaceColor', [.8 .4 .2], 'FaceAlpha', .4);
    legend('ref (model filter)', 'zero-phase'); xlabel('phase error (deg)'); ylabel('pulses'); title('Phase error');
    subplot(1,3,3);
    [P0, f0] = pwelch(x(skip:end), 2*fs, fs, [], fs);
    [P1, ~]  = pwelch(res.rawArt(skip:end), 2*fs, fs, [], fs);
    [P2, ~]  = pwelch(res.kal(skip:end), 2*fs, fs, [], fs);
    semilogy(f0, P1, 'Color', [.7 .7 .7]); hold on; semilogy(f0, P0, 'k'); semilogy(f0, P2, 'r--');
    xlim([1 100]); xlabel('Hz'); ylabel('PSD'); legend('raw + artifact', 'artifact-free', 'Kalman');
    title('Artifact suppression');
    exportgraphics(fig, opts.fig, 'Resolution', 120); close(fig);
end
end

% ---------------------------------------------------------------------------
function w = artifactWindow(res, fs)
% Kalman blanking width used by the model: floor(12e-3*fs) unless overridden
if isfield(res, 'width') && ~isempty(res.width), w = res.width; else, w = floor(12e-3*fs); end
end

function A = envBeta(x, fpk, fs)
[b, a] = butter(2, [fpk-2.5 fpk+2.5]/(fs/2));
A = abs(hilbert(filtfilt(b, a, x)));
end

function e = relerr(A, A0, skip)
e = mean(abs(A(skip:end) - A0(skip:end))) / mean(A0(skip:end));
end

function y = blankInterp(x, on, w)
% "irregular sampling"/blanking: drop the samples in the artifact window, then interpolate
y = x; keep = true(size(x));
for k = 1:numel(on), keep(on(k):min(on(k)+w-1, numel(x))) = false; end
idx = (1:numel(x))';
y(~keep) = interp1(idx(keep), x(keep), idx(~keep), 'linear', 'extrap');
end

function y = holdLast(x, on, w)
y = x;
% hold the last *output* sample so overlapping windows (double triggers) keep a clean value
for k = 1:numel(on), s = on(k); y(s:min(s+w-1, numel(x))) = y(max(s-1, 1)); end
end

function y = zeroOut(x, on, w)
y = x;
for k = 1:numel(on), y(on(k):min(on(k)+w-1, numel(x))) = 0; end
end

function p = wrapToPi(p)
p = angle(exp(1i*p));
end
