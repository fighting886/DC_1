function green_val = extract_green_signal(frame, left_roi, right_roi)
% 从左右太阳穴 ROI 提取绿色通道均值
% 输入：
%   frame: RGB 图像（height x width x 3）
%   left_roi, right_roi: [x, y, width, height]

% 提取 ROI 区域（注意：MATLAB 索引是 (y, x)）
lx = left_roi(1); ly = left_roi(2);
lw = left_roi(3); lh = left_roi(4);
left_temple = frame(ly:ly+lh-1, lx:lx+lw-1, :);

rx = right_roi(1); ry = right_roi(2);
rw = right_roi(3); rh = right_roi(4);
right_temple = frame(ry:ry+rh-1, rx:rx+rw-1, :);

% 提取绿色通道（第 2 通道）并求均值
if ~isempty(left_temple) && ~isempty(right_temple)
    green_left = mean(left_temple(:, :, 2), 'all');
    green_right = mean(right_temple(:, :, 2), 'all');
    green_val = mean([green_left, green_right]);
else
    green_val = NaN;  % 无效值
end
end