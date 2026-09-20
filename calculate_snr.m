function snr = calculate_snr(signal)
% 简单 SNR 计算（用于实时显示）
signal = signal(:);
if length(signal) < 10
    snr = 0;
    return;
end

signal_centered = signal - mean(signal);
signal_power = var(signal_centered);
diff_signal = diff(signal_centered);
noise_power = (std(diff_signal) / sqrt(2))^2;

if noise_power < 1e-10
    noise_power = 1e-10;
end
if signal_power < 1e-10
    snr = 0;
else
    snr = 10 * log10(signal_power / noise_power);
    snr = max(0, min(30, snr));
end
end