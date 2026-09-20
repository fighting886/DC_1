%% config.m - 心率采集参数配置

function cfg = config()
cfg.DURATION = 10;
cfg.FPS = 25;
cfg.TOTAL_FRAMES = cfg.DURATION * cfg.FPS;
cfg.TEST_DISTANCES = [30, 40, 50, 60, 70, 80, 100];
cfg.TESTS_PER_DISTANCE = 3;
cfg.AUTO_SAVE_PLOTS = true;
end
