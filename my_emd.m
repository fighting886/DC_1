function imfs=my_emd(signal,varargin)
    p=inputParser;
    % === Required（必选参数）===
    % 格式：addRequired(解析器, '参数名', 验证函数)
    addRequired(p,'signal',@isnumeric);
    % === Parameter（可选参数，有默认值）===
    % 格式：addParameter(解析器, '参数名', 默认值, 验证函数)
    addParameter(p,'Interpolation','pchip',@ischar); 
    addParameter(p,'MaxNumIMF',10,@isnumeric);
    addParameter(p,'SiftMaxIter',100,@isnumeric);
    addParameter(p,'SiftRelativeTolerance',0.2,@isnumeric);
    addParameter(p, 'EndPointMethod', 'mirror', @ischar);   
    addParameter(p, 'Verbose', false, @islogical); 
    parse(p,signal,varargin{:});

    % 获取参数
    interp_method = p.Results.Interpolation;
    max_imf = p.Results.MaxNumIMF;
    max_iter = p.Results.SiftMaxIter;
    tol = p.Results.SiftRelativeTolerance;
    endpoint_method = p.Results.EndPointMethod;
    verbose = p.Results.Verbose;

    %% 初始化
    signal = signal(:);
    n = length(signal);
    t_original = (1:n)';
    
    residue = signal;
    imfs = [];
    
    if verbose
        fprintf('开始EMD分解...\n');
        fprintf('插值方法: %s\n', interp_method);
        fprintf('端点处理: %s\n', endpoint_method);
    end
    
    %% 主分解循环
    for k = 1:max_imf
        if verbose
            fprintf('\n提取第%d个IMF...\n', k);
        end
        
        % 当前待分解信号
        h = residue;
        h_prev = h;
        
        % 筛选循环
        for iter = 1:max_iter
            %% 步骤1：端点处理
            if strcmp(endpoint_method, 'mirror')
                ext_len = min(20, floor(n/10));
                [h_ext, orig_len] = endpoint_mirror_extension(h, ext_len);
                t_ext = (1:length(h_ext))';
            else
                h_ext = h;
                t_ext = t_original;
            end
            
            %% 步骤2：找极值点（改进版）
            [max_locs, max_vals, min_locs, min_vals] = improved_find_extrema(h_ext);
            
            % 检查极值点数量
            if length(max_locs) + length(min_locs) < 4
                if verbose
                    fprintf('  极值点太少，停止筛选\n');
                end
                break;
            end
            
            %% 步骤3：构建包络线
            try
                upper_env = interp1(max_locs, max_vals, t_ext, interp_method, 'extrap');
                lower_env = interp1(min_locs, min_vals, t_ext, interp_method, 'extrap');
            catch
                % 如果插值失败，尝试线性插值
                upper_env = interp1(max_locs, max_vals, t_ext, 'linear', 'extrap');
                lower_env = interp1(min_locs, min_vals, t_ext, 'linear', 'extrap');
            end
            
            %% 步骤4：计算均值包络
            mean_env = (upper_env + lower_env) / 2;
            
            %% 步骤5：恢复原始长度
            if strcmp(endpoint_method, 'mirror')
                mean_env = remove_extension(mean_env, orig_len, ext_len);
                h_new = h - mean_env;
            else
                h_new = h - mean_env;
            end
            
            %% 步骤6：停止准则检查
            % 准则1：SD准则
            sd = sum((h - h_new).^2) / (sum(h.^2) + eps);
            
            % 准则2：过零点条件
            zero_crossings = sum(diff(sign(h_new)) ~= 0);
            [pks_max, ~] = findpeaks(h_new);
            [pks_min, ~] = findpeaks(-h_new);
            extrema_count = length(pks_max) + length(pks_min);
            crossing_ok = abs(zero_crossings - extrema_count) <= 1;
            
            % 准则3：均值条件
            mean_env_rms = rms(mean_env);
            signal_rms = rms(h_new);
            mean_ok = mean_env_rms < 0.05 * signal_rms;
            
            if verbose && mod(iter, 10) == 0
                fprintf('  迭代%d: SD=%.4f, 过零点=%d, 极值点=%d\n', ...
                    iter, sd, zero_crossings, extrema_count);
            end
            
            % 判断是否停止
            if sd < tol && crossing_ok && mean_ok
                if verbose
                    fprintf('  第%d次迭代满足所有停止条件\n', iter);
                end
                break;
            end
            
            if sd < tol/10  % 强制停止
                if verbose
                    fprintf('  SD非常小，强制停止\n');
                end
                break;
            end
            
            % 更新
            h_prev = h;
            h = h_new;
        end
        
        %% 保存IMF
        imf = h;
        
        % 模式混叠检测
        [is_mixing, mix_ratio] = detect_mode_mixing(imf);
        if is_mixing && verbose
            fprintf('  警告：检测到可能的模式混叠 (比率=%.2f)\n', mix_ratio);
        end
        
        imfs = [imfs, imf];
        
        %% 更新残差
        residue = residue - imf;
        
        %% 检查是否继续分解
        [~, ~, ~, ~] = improved_find_extrema(residue);
        n_extrema = length(findpeaks(residue)) + length(findpeaks(-residue));
        
        if n_extrema < 3
            if verbose
                fprintf('残差已无明显波动，添加为最后一个分量\n');
            end
            imfs = [imfs, residue];
            break;
        end
        
        % 检查残差能量
        if var(residue) < var(signal) * 1e-4
            if verbose
                fprintf('残差能量很小，停止分解\n');
            end
            imfs = [imfs, residue];
            break;
        end
    end
    
    if verbose
        fprintf('\nEMD分解完成！共提取%d个IMF\n', size(imfs, 2));
        fprintf('重构误差MSE: %.2e\n', mean((signal - sum(imfs, 2)).^2));
    end
end

%% 辅助函数
function [extended_signal, original_length] = endpoint_mirror_extension(signal, ext_length)
    signal = signal(:);
    n = length(signal);
    original_length = n;
    
    % 左端镜像
    left_ext = 2*signal(1) - signal(min(ext_length+1, n):-1:2);
    if length(left_ext) < ext_length
        left_ext = [left_ext; repmat(left_ext(end), ext_length-length(left_ext), 1)];
    end
    
    % 右端镜像
    right_ext = 2*signal(end) - signal(end-1:-1:max(1, end-ext_length));
    if length(right_ext) < ext_length
        right_ext = [repmat(right_ext(end), ext_length-length(right_ext), 1); right_ext];
    end
    
    extended_signal = [left_ext(:); signal; right_ext(:)];
end

function original_signal = remove_extension(extended_signal, original_length, ext_length)
    original_signal = extended_signal(ext_length+1:ext_length+original_length);
end

function [maxima_idx, maxima_val, minima_idx, minima_val] = improved_find_extrema(signal)
    % 改进的极值点检测（已在前面定义）
    n = length(signal);
    signal = signal(:);
    
    maxima_idx = [];
    maxima_val = [];
    minima_idx = [];
    minima_val = [];
    
    for i = 2:n-1
        if signal(i) > signal(i-1) && signal(i) >= signal(i+1)
            maxima_idx = [maxima_idx; i];
            maxima_val = [maxima_val; signal(i)];
        end
        if signal(i) < signal(i-1) && signal(i) <= signal(i+1)
            minima_idx = [minima_idx; i];
            minima_val = [minima_val; signal(i)];
        end
    end
end

function [is_mixing, mixing_ratio] = detect_mode_mixing(imf)
    % 模式混叠检测
    n = length(imf);
    
    % 简化的Hilbert变换
    X = fft(imf);
    h = zeros(n,1);
    if mod(n,2) == 0
        h([1, n/2+1]) = 1;
        h(2:n/2) = 2;
    else
        h(1) = 1;
        h(2:(n+1)/2) = 2;
    end
    
    Y = X .* h;
    y = ifft(Y);
    
    % 瞬时频率
    phase = unwrap(angle(y));
    inst_freq = abs(diff(phase) / (2*pi));
    inst_freq = [inst_freq; inst_freq(end)];
    
    % 检测
    freq_std = std(inst_freq);
    freq_mean = mean(inst_freq);
    mixing_ratio = freq_std / (freq_mean + eps);
    is_mixing = mixing_ratio > 0.5;
end