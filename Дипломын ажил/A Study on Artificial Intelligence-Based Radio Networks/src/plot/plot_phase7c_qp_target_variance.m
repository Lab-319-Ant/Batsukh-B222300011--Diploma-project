function plot_phase7c_qp_target_variance(cfg, diagnosticTable)
%PLOT_PHASE7C_QP_TARGET_VARIANCE Plot QP target standard deviation.

labels = categorical(strrep(diagnosticTable.scenario_name, '_', ' '));
labels = reordercats(labels, strrep(diagnosticTable.scenario_name, '_', ' '));
fig = figure('Color', 'w', 'Name', 'Phase 7C QP target variance');
bar(labels, diagnosticTable.target_std);
yline(0.05, 'r--', 'Low variance threshold');
grid on;
ylabel('QoS target standard deviation');
title('QP target variance by scenario');
xtickangle(30);
save_figure(fig, fullfile(cfg.figuresDir, 'phase7c_qp_target_variance_by_scenario.png'));
end
