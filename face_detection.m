function [left_roi, right_roi] = face_detection(face_rect, frame_shape)
% 根据人脸边界框计算左右太阳穴 ROI
% 输入：
%   face_rect: [x, y, width, height]（MATLAB 的检测器输出格式）
%   frame_shape: [height, width, channels]
% 输出：
%   left_roi, right_roi: [x, y, width, height] 格式

x = face_rect(1); 
y = face_rect(2);
w = face_rect(3);
h = face_rect(4);

h_frame = frame_shape(1);
w_frame = frame_shape(2);

% === 左太阳穴 ROI ===
lx1 = max(1, round(x + w * 0.05));
lx2 = min(w_frame, round(x + w * 0.22));
ly1 = max(1, round(y + h * 0.20));
ly2 = min(h_frame, round(y + h * 0.43));
left_roi = [lx1, ly1, lx2 - lx1, ly2 - ly1];  % [x, y, width, height]

% === 右太阳穴 ROI ===
rx1 = max(1, round(x + w * 0.78));
rx2 = min(w_frame, round(x + w * 0.95));
ry1 = max(1, round(y + h * 0.20));
ry2 = min(h_frame, round(y + h * 0.43));
right_roi = [rx1, ry1, rx2 - rx1, ry2 - ry1];
end