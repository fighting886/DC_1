%% config.m - 心率采集参数配置
% 这个文件相当于 Python 的 config.py
DURATION = 10;          % 采集时间（秒）
FPS = 25;               % 目标帧率
TOTAL_FRAMES = DURATION * FPS;

% 距离测试配置（可选）
TEST_DISTANCES = [30, 40, 50, 60, 70, 80, 100];
TESTS_PER_DISTANCE = 3;
AUTO_SAVE_PLOTS = true;