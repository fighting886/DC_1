%% main.m - 主程序（摄像头实时采集 + 心率计算）
clear; clc; close all;

% 加载配置
run('config.m');

fprintf('\n================================================\n');
fprintf('心率检测系统 - MATLAB 版本\n');
fprintf('================================================\n');
fprintf('需要采集 %d 帧数据（对应 %d 秒 @ %d fps）\n', TOTAL_FRAMES, DURATION, FPS);

%% ========== 初始化摄像头 ==========
% 检查是否安装了 Webcam 工具箱
if ~exist('webcam', 'file')
    error('未安装 Webcam 工具箱。请运行：supportPackageInstaller 安装 MATLAB Support Package for USB Webcams');
end

% 列出所有摄像头
camList = webcamlist;
if isempty(camList)
    error('未检测到摄像头');
end
fprintf('检测到摄像头：%s\n', camList{1});

% 打开摄像头
cam = webcam(1);  % 使用第一个摄像头
% 注意：MATLAB webcam 不支持像 OpenCV 那样设置曝光、亮度等参数
% 如需调整，可以在 Windows 的摄像头属性中设置

%% ========== 初始化人脸检测器 ==========
faceDetector = vision.CascadeObjectDetector();

%% ========== 主循环 ==========
green_signals = [];  % 存储绿色通道信号
frame_count = 0;
prev_face = [];  % 上一帧的人脸位置

% 创建显示窗口
figure('Name', '心率检测系统', 'NumberTitle', 'off', 'Position', [100, 100, 800, 600]);

while frame_count < TOTAL_FRAMES
    % 采集一帧
    frame = snapshot(cam);
    gray = rgb2gray(frame);
    
    % 人脸检测
    bboxes = step(faceDetector, gray);
    
    % 如果有检测到人脸，选择面积最大的
    if ~isempty(bboxes)
        areas = bboxes(:, 3) .* bboxes(:, 4);
        [~, idx] = max(areas);
        face_rect = bboxes(idx, :);  % [x, y, width, height]
        
        % 计算太阳穴 ROI
        [left_roi, right_roi] = face_detection(face_rect, size(frame));
        
        % 提取绿色通道信号
        green_val = extract_green_signal(frame, left_roi, right_roi);
        
        if ~isnan(green_val)
            green_signals(end+1) = green_val;
            frame_count = frame_count + 1;
        end
        
        % === 绘制检测结果 ===
        % 人脸框
        frame = insertShape(frame, 'Rectangle', face_rect, 'Color', 'green', 'LineWidth', 2);
        frame = insertText(frame, [face_rect(1), face_rect(2)-10], 'Face', ...
                          'FontSize', 14, 'TextColor', 'green', 'BoxOpacity', 0);
        
        % 左太阳穴 ROI
        frame = insertShape(frame, 'Rectangle', left_roi, 'Color', 'red', 'LineWidth', 1);
        % 右太阳穴 ROI
        frame = insertShape(frame, 'Rectangle', right_roi, 'Color', 'red', 'LineWidth', 1);
        
        % 显示实时 SNR（如果信号足够）
        if length(green_signals) > 30
            temp_snr = calculate_snr(green_signals(end-29:end));
            frame = insertText(frame, [10, 120], sprintf('SNR: %.1f dB', temp_snr), ...
                              'FontSize', 14, 'TextColor', 'yellow', 'BoxOpacity', 0.5);
        end
    end
    
    % 显示采集进度
    progress = round(frame_count / TOTAL_FRAMES * 100);
    frame = insertText(frame, [10, 30], sprintf('Progress: %d%%', progress), ...
                      'FontSize', 14, 'TextColor', 'green', 'BoxOpacity', 0.5);
    frame = insertText(frame, [10, 60], sprintf('Signal points: %d', frame_count), ...
                      'FontSize', 14, 'TextColor', 'green', 'BoxOpacity', 0.5);
    
    % 显示图像
    imshow(frame);
    drawnow;
end

%% ========== 释放摄像头 ==========
clear cam;
fprintf('\n采集完成！共采集 %d 帧数据\n', length(green_signals));

%% ========== 信号分析 ==========
if length(green_signals) < 30
    error('采集的信号不足，请检查摄像头或人脸检测是否正常');
end

signal = green_signals(:);  % 转为列向量
actual_fps = length(signal) / DURATION;
fprintf('实际采样率: %.1f fps\n', actual_fps);

% 调用信号处理函数
result = signal_processing(signal, actual_fps);

% 输出结果
fprintf('\n================================================\n');
fprintf('📊 最终检测结果\n');
fprintf('================================================\n');
fprintf('信噪比: %.2f dB\n', calculate_snr(signal));
if ~isnan(result.heart_rate)
    fprintf('最终心率值: %.1f BPM\n', result.heart_rate);
else
    fprintf('心率计算失败: %s\n', result.error);
end
fprintf('================================================\n');

% 保存信号到文件
save('signal_results.mat', 'signal', 'result');
fprintf('\n💾 信号已保存到 signal_results.mat\n');


%% ========== 辅助函数：计算 SNR ==========
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