function result = signal_processing(signal, fps)
% 信号处理主函数：EEMD 分解 + 心率计算
% 输入：
%   signal: 一维绿色通道信号（列向量）
%   fps: 实际帧率
% 输出：
%   result: 结构体，包含 raw_signal, noise_signal, denoised_signal, heart_rate

% 初始化结果
result.raw_signal = signal;
result.noise_signal = [];
result.denoised_signal = [];
result.heart_rate = NaN;
result.error = '';

% === 检查信号长度 ===
if length(signal) < 30
    result.error = '信号长度不足（<30帧）';
    return;
end

% === 步骤1：EEMD 分解 ===
try
 
   imfs = my_emd(signal, 'Interpolation', 'pchip');
   
catch ME
    % 如果 EMD 失败，使用备用方案（直接 FFT 滤波）
    warning('EMD 分解失败，使用备用滤波方案: %s', ME.message);
    result = fallback_filter(signal, fps);
    return;
end

% 如果 imfs 是矩阵，确保每一列是一个 IMF
if size(imfs, 1) < size(imfs, 2)%如果行数小于列数
    imfs = imfs';% 转置矩阵
end
n_imfs = size(imfs, 2);% 获取列数（IMF个数）

% === 步骤2：分离心率相关 IMF（频率在 0.8~3.0 Hz）===
hr_imfs = [];
noise_imfs = [];
n = length(signal);

for i = 1:n_imfs
    imf = imfs(:, i);
    
    % 计算该 IMF 的主频率
    fft_vals = fft(imf);
    fft_freqs = (0:n-1) * fps / n;
    
    % 找最大幅值对应的频率（跳过直流分量）
    [~, idx] = max(abs(fft_vals(2:end)));
    main_freq = fft_freqs(idx + 1);
    
    % 判断是否在心率范围内（0.8~3.0 Hz）
    if main_freq >= 0.8 && main_freq <= 3.0
        hr_imfs = [hr_imfs, imf];
        fprintf('IMF %d 保留（主频率：%.2f Hz → %.1f BPM）\n', ...
                i, main_freq, main_freq * 60);
    else
        noise_imfs = [noise_imfs, imf];
        fprintf('IMF %d 剔除（主频率：%.2f Hz → %.1f BPM）\n', ...
                i, main_freq, main_freq * 60);
    end
end

% === 步骤3：重组信号 ===
if ~isempty(hr_imfs)
    result.denoised_signal = sum(hr_imfs, 2);
else
    result.denoised_signal = signal;  % 如果没有心率 IMF，就用原始信号
end

if ~isempty(noise_imfs)
    result.noise_signal = sum(noise_imfs, 2);
else
    result.noise_signal = zeros(size(signal));
end

% === 步骤4：计算心率（从降噪信号）===
denoised = result.denoised_signal;
denoised = denoised - mean(denoised);  % 去除直流
windowed = denoised .* hanning(length(denoised));  % 加汉宁窗

% FFT 分析
n = length(windowed);
fft_vals = fft(windowed);
fft_freqs = (0:n-1) * fps / n;

% 只关注心率范围（0.8~3.0 Hz）
hr_mask = fft_freqs >= 0.8 & fft_freqs <= 3.0;
if ~any(hr_mask)
    result.error = '无有效心率频率分量';
    return;
end

hr_fft = abs(fft_vals(hr_mask));
hr_freqs = fft_freqs(hr_mask);
[~, peak_idx] = max(hr_fft);
heart_rate_bpm = hr_freqs(peak_idx) * 60;

% 验证心率合理性（40~180 BPM）
if heart_rate_bpm >= 40 && heart_rate_bpm <= 180
    result.heart_rate = heart_rate_bpm;
else
    result.error = sprintf('心率值异常（%.1f BPM）', heart_rate_bpm);
end

% === 步骤5：绘图（可选）===
plot_signal_comparison(result, fps);

end


%% ========== 备用滤波方案（当 EMD 不可用时）==========
function result = fallback_filter(signal, fps)
% 使用带通滤波器替代 EEMD
result.raw_signal = signal;
result.noise_signal = [];
result.denoised_signal = [];
result.heart_rate = NaN;
result.error = '';

% 设计带通滤波器（0.8~3.0 Hz）
nyquist = fps / 2;
if nyquist <= 0
    result.error = '帧率过低，无法滤波';
    return;
end

low_cut = max(0.8 / nyquist, 0.01);
high_cut = min(3.0 / nyquist, 0.99);

if low_cut >= high_cut
    result.error = '通带频率不合理';
    return;
end

% 使用 4 阶巴特沃斯带通滤波器
[b, a] = butter(4, [low_cut, high_cut], 'band');
denoised = filtfilt(b, a, signal);

result.denoised_signal = denoised;
result.noise_signal = signal - denoised;  % 噪声 = 原始 - 滤波后

% 计算心率
denoised_centered = denoised - mean(denoised);
windowed = denoised_centered .* hanning(length(denoised_centered));
n = length(windowed);
fft_vals = fft(windowed);
fft_freqs = (0:n-1) * fps / n;

hr_mask = fft_freqs >= 0.8 & fft_freqs <= 3.0;
if ~any(hr_mask)
    result.error = '无有效心率频率分量';
    return;
end

hr_fft = abs(fft_vals(hr_mask));
hr_freqs = fft_freqs(hr_mask);
[~, peak_idx] = max(hr_fft);
heart_rate_bpm = hr_freqs(peak_idx) * 60;

if heart_rate_bpm >= 40 && heart_rate_bpm <= 180
    result.heart_rate = heart_rate_bpm;
else
    result.error = sprintf('心率值异常（%.1f BPM）', heart_rate_bpm);
end
end


%% ========== 绘图函数 ==========
function plot_signal_comparison(result, fps)
% 可视化原始信号、噪声信号、降噪信号及频谱
raw = result.raw_signal;
noise = result.noise_signal;
denoised = result.denoised_signal;
hr = result.heart_rate;

figure('Position', [100, 100, 1200, 800]);

% 子图1：原始信号
subplot(2, 2, 1);
plot(raw, 'g-', 'LineWidth', 1.2);
title('原始绿色通道信号');
xlabel('帧');
ylabel('信号值');
grid on;

% 子图2：噪声信号
subplot(2, 2, 2);
if ~isempty(noise)
    plot(noise, 'r-', 'LineWidth', 1.2);
else
    text(0.5, 0.5, '无噪声信号', 'HorizontalAlignment', 'center');
end
title('分离出的非心率信号（噪声）');
xlabel('帧');
ylabel('信号值');
grid on;

% 子图3：降噪信号
subplot(2, 2, 3);
if ~isempty(denoised)
    plot(denoised, 'b-', 'LineWidth', 1.2);
else
    text(0.5, 0.5, '无降噪信号', 'HorizontalAlignment', 'center');
end
title('重组后的心率相关信号');
xlabel('帧');
ylabel('信号值');
grid on;

% 子图4：频谱
subplot(2, 2, 4);
if ~isempty(denoised)
    denoised_centered = denoised - mean(denoised);
    windowed = denoised_centered .* hanning(length(denoised_centered));
    n = length(windowed);
    fft_vals = fft(windowed);
    fft_freqs = (0:n-1) * fps / n;
    hr_mask = fft_freqs >= 0.8 & fft_freqs <= 3.0;
    plot(fft_freqs(hr_mask) * 60, abs(fft_vals(hr_mask)), 'b-', 'LineWidth', 2);
    if ~isnan(hr)
        hold on;
        plot(hr, max(abs(fft_vals(hr_mask))), 'ro', 'MarkerSize', 10, 'LineWidth', 2);
        legend(sprintf('峰值 = %.1f BPM', hr));
        hold off;
    end
    xlabel('心率（BPM）');
    ylabel('频谱强度');
    grid on;
end

sgtitle(sprintf('信号分析结果（心率 = %.1f BPM）', hr));
end