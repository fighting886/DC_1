clear; clc; close all;

% 加载配置
cfg = config();
% 用 cfg.FPS 而不是裸 FPS

fprintf('\n================================================\n');
fprintf('心率检测系统 - 视频文件模式\n');
fprintf('================================================\n');

video_path = 'D:\PPL\Videos\v1.mp4';

%% ========== 初始化视频读取 ==========
% 创建视频读取对象
v = VideoReader(video_path);

% 获取视频信息
fps = v.FrameRate;                    % 实际帧率
total_frames = floor(v.Duration * fps); % 总帧数
process_frames = min(total_frames, cfg.TOTAL_FRAMES);
frame_step = max(1, round(fps / cfg.FPS));

%% ========== 初始化人脸检测器 ==========
faceDetector = vision.CascadeObjectDetector();

%% ========== 主循环 ==========
green_signals = [];  % 存储绿色通道信号
frame_count = 0;
frame_idx = 0;
prev_face = [];  % 上一帧的人脸位置
tracking_counter = 0;    % ✅ 新增：追踪持续帧数
tracking_mode = false;   % ✅ 新增：是否处于追踪模式

% 创建显示窗口
figure('Name', '心率检测系统', 'NumberTitle', 'off', 'Position', [100, 50, 800, 600]);
v.CurrentTime = 0;

while frame_count < process_frames && hasFrame(v)
    % 采集一帧
    frame = readFrame(v);
    frame_idx = frame_idx + 1;

    if mod(frame_idx, frame_step) ~= 0
        continue;
    end

    gray = rgb2gray(frame);
    
    %% ====== 智能检测（带追踪） ======
    if tracking_mode && tracking_counter < 8
        % 在上一帧位置附近检测
        search_margin = 25;
        if ~isempty(prev_face)
            x = max(1, prev_face(1) - search_margin);
            y = max(1, prev_face(2) - search_margin);
            w = min(size(gray,2)-x, prev_face(3) + 2*search_margin);
            h = min(size(gray,1)-y, prev_face(4) + 2*search_margin);
            
            roi_gray = imcrop(gray, [x, y, w, h]);
            bboxes = faceDetector(roi_gray);
            
            if ~isempty(bboxes)
                bboxes(:,1) = bboxes(:,1) + x - 1;
                bboxes(:,2) = bboxes(:,2) + y - 1;
                tracking_counter = tracking_counter + 1;
            else
                tracking_mode = false;
                bboxes = faceDetector(gray);
            end
        end
    else
        % 全图检测（每8帧重新检测一次）
        bboxes = faceDetector(gray);
        if ~isempty(bboxes)
            tracking_mode = true;
            tracking_counter = 0;
        else
            tracking_mode = false;
        end
    end

    
    %% 处理检测结果 如果有检测到人脸，选择面积最大的
    if ~isempty(bboxes)
        areas = bboxes(:, 3) .* bboxes(:, 4);
        [~, idx] = max(areas);
        face_rect = bboxes(idx, :);  % [x, y, width, height]
        
        % ✅ 更新 prev_face
        prev_face = face_rect;

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
        % 左太阳穴 ROI
        frame = insertShape(frame, 'Rectangle', left_roi, 'Color', 'red', 'LineWidth', 1);
        % 右太阳穴 ROI
        frame = insertShape(frame, 'Rectangle', right_roi, 'Color', 'red', 'LineWidth', 1);
        
        frame = insertText(frame, [face_rect(1), face_rect(2)-10], 'Face', ...
                          'FontSize', 14, 'TextColor', 'green', 'BoxOpacity', 0);
        frame = insertText(frame, [10, 180], sprintf('追踪: %d帧', tracking_counter), ...
            'FontSize', 12, 'TextColor', 'cyan', 'BoxOpacity', 0.5,...
            'Font', 'SimHei');
    else
        frame = insertText(frame, [10, 90], '⚠️ 未检测到人脸', ...
            'FontSize', 14, 'TextColor', 'red', 'BoxOpacity', 0.5,...
            'Font', 'SimHei');
    end

        % 显示实时 SNR（如果信号足够）
        if length(green_signals) > 30
            temp_snr = calculate_snr(green_signals(end-29:end));
            frame = insertText(frame, [10, 120], sprintf('SNR: %.1f dB', temp_snr), ...
                              'FontSize', 14, 'TextColor', 'yellow', 'BoxOpacity', 0.5);
        end
    
    % 显示采集进度
    progress = round(frame_count / cfg.TOTAL_FRAMES * 100);
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
actual_fps = fps/frame_step;
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

