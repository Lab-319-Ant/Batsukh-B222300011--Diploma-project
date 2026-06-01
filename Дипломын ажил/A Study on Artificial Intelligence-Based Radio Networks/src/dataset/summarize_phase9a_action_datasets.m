function summary = summarize_phase9a_action_datasets(cfg, datasetAll, modules)
%SUMMARIZE_PHASE9A_ACTION_DATASETS Per-module row/reward statistics.

if isempty(datasetAll)
    summary = table();
    writetable(summary, fullfile(cfg.tablesDir, 'phase9a_action_value_dataset_summary.csv'));
    return;
end

n = numel(modules);
moduleName = cell(n, 1);
total_rows = zeros(n, 1);
safe_rows = zeros(n, 1);
unsafe_rows = zeros(n, 1);
oracle_selected_rows = zeros(n, 1);
unsafe_fallback_oracle_rows = zeros(n, 1);
no_op_rows = zeros(n, 1);
mean_reward = nan(n, 1);
median_reward = nan(n, 1);
min_reward = nan(n, 1);
max_reward = nan(n, 1);
positive_reward_rows = zeros(n, 1);
negative_reward_rows = zeros(n, 1);

moduleCol = string(datasetAll.module_name);
for k = 1:n
    mName = modules{k};
    moduleName{k} = mName;
    mask = moduleCol == mName;
    sub = datasetAll(mask, :);
    total_rows(k) = height(sub);
    if isempty(sub)
        continue;
    end
    safe_rows(k) = sum(sub.safety_valid);
    unsafe_rows(k) = total_rows(k) - safe_rows(k);
    oracle_selected_rows(k) = sum(sub.oracle_selected);
    unsafe_fallback_oracle_rows(k) = sum(sub.oracle_selected & sub.unsafe_fallback_group & ~sub.safety_valid);
    no_op_rows(k) = sum(logical(sub.is_no_op) | ...
        (strcmp(sub.module_name, 'ES') & strcmp(sub.action_type, 'keep_active')));
    r = sub.reward;
    finite_r = r(isfinite(r));
    if ~isempty(finite_r)
        mean_reward(k) = mean(finite_r);
        median_reward(k) = median(finite_r);
        min_reward(k) = min(finite_r);
        max_reward(k) = max(finite_r);
    end
    positive_reward_rows(k) = sum(r > 0);
    negative_reward_rows(k) = sum(r < 0);
end

summary = table(moduleName, total_rows, safe_rows, unsafe_rows, oracle_selected_rows, ...
    unsafe_fallback_oracle_rows, no_op_rows, mean_reward, median_reward, ...
    min_reward, max_reward, positive_reward_rows, negative_reward_rows, ...
    'VariableNames', {'module_name','total_rows','safe_rows','unsafe_rows', ...
    'oracle_selected_rows','unsafe_fallback_oracle_rows','no_op_rows', ...
    'mean_reward','median_reward','min_reward','max_reward', ...
    'positive_reward_rows','negative_reward_rows'});

writetable(summary, fullfile(cfg.tablesDir, 'phase9a_action_value_dataset_summary.csv'));
end
