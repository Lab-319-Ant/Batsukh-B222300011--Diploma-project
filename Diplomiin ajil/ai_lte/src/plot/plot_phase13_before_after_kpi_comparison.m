function plot_phase13_before_after_kpi_comparison(beforeAfter, baselineAiOracle, outputPath)
%PLOT_PHASE13_BEFORE_AFTER_KPI_COMPARISON Grouped bar chart for thesis package.
%
% Inputs:
%   beforeAfter      - struct from build_before_after_kpi_tables
%   baselineAiOracle - optional table from build_final_thesis_summary_tables.baselineAiOracle
%   outputPath       - destination PNG path (under thesis_package/)

if isempty(beforeAfter.summary)
    return;
end

S = beforeAfter.summary;
kpis = S.kpi_name;
baseline = S.baseline_kpi_t;
aiPost = S.ai_ml_kpi_t_plus_1;
n = numel(kpis);

oraclePost = nan(n, 1);
if nargin >= 2 && ~isempty(baselineAiOracle)
    O = baselineAiOracle;
    for k = 1:n
        scopeKey = sprintf('ALL_%s', kpis{k});
        idx = find(strcmp(O.comparison_scope, scopeKey), 1, 'first');
        if ~isempty(idx)
            oraclePost(k) = O.oracle_metric(idx);
        end
    end
end

fig = figure('Visible', 'off', 'Position', [100 100 1100 520]);
data = [baseline, aiPost, oraclePost];
bar(data, 'grouped');
set(gca, 'XTick', 1:n, 'XTickLabel', kpis, 'XTickLabelRotation', 25);
ylabel('KPI value (baseline vs AI/ML vs oracle)');
legend({'baseline KPI(t)','AI/ML KPI(t+1)','oracle KPI(t+1)'}, 'Location', 'best');
title('Phase 13: baseline vs AI/ML vs oracle - mean KPI over applied actions');
grid on;

save_figure(fig, outputPath);
end
