%% Smoke-test the new site-level user forecast.
% Loads vendor KPI, runs run_tp_site_user_forecast, writes its CSVs and
% figures. Intended for quick verification — not a replacement for the
% full vendor recommendation pipeline.

clear; clc; close all;

rootDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(rootDir, 'config')));
addpath(genpath(fullfile(rootDir, 'src')));

vcfg = vendor_kpi_config();
ensure_folder(vcfg.processedDir);
ensure_folder(vcfg.tablesDir);
ensure_folder(vcfg.figuresDir);

fprintf('Loading vendor KPI from %s\n', vcfg.rawKpiDir);
rawKpi = load_vendor_kpi(vcfg);
cleanKpi = standardize_vendor_kpi(rawKpi, vcfg);

fprintf('Running site-level user forecast (6d train / 1d test)\n');
forecast = run_tp_site_user_forecast(cleanKpi, vcfg);

if isempty(forecast.predictions)
    error('Forecast produced no predictions. Check data coverage.');
end

writetable(forecast.predictions, fullfile(vcfg.tablesDir, 'vendor_tp_user_forecast_test_predictions.csv'));
writetable(forecast.metrics, fullfile(vcfg.tablesDir, 'vendor_tp_user_forecast_metrics.csv'));
writetable(forecast.featureWeights, fullfile(vcfg.tablesDir, 'vendor_tp_user_forecast_feature_weights.csv'));
writetable(forecast.splitSummary, fullfile(vcfg.tablesDir, 'vendor_tp_user_forecast_split_summary.csv'));

fprintf('\nPer-site test metrics:\n');
disp(forecast.metrics);

plot_vendor_tp_user_forecast(vcfg, forecast);

fprintf('\nFigures saved under %s\n', vcfg.figuresDir);
fprintf('  - vendor_tp_user_forecast_timeseries.png\n');
fprintf('  - vendor_tp_user_forecast_scatter.png\n');
fprintf('  - vendor_tp_user_forecast_mae_comparison.png\n');
fprintf('  - vendor_tp_user_forecast_summary.png\n');
