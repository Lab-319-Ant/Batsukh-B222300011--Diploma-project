function plot_vendor_tp_user_forecast(vcfg, forecast)
%PLOT_VENDOR_TP_USER_FORECAST Сайтын идэвхтэй хэрэглэгчдийн таамаглалын
% үнэлгээний графикууд (бүрэн монгол хэл дээр, baseline-гүй).

if isempty(forecast.predictions) || isempty(forecast.metrics)
    return;
end

plot_site_timeseries_grid(vcfg, forecast);
plot_actual_vs_predicted_scatter(vcfg, forecast);
plot_mae_bar(vcfg, forecast);
plot_metrics_text_summary(vcfg, forecast);
end

function plot_site_timeseries_grid(vcfg, forecast)
preds = forecast.predictions;
sites = unique(preds.sim_site_id);
nSites = numel(sites);
nCols = min(3, nSites);
nRows = ceil(nSites / nCols);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1500 220 * nRows + 140]);
tl = tiledlayout(fig, nRows, nCols, 'TileSpacing', 'compact', 'Padding', 'compact');
for s = sites(:)'
    nexttile;
    P = preds(preds.sim_site_id == s, :);
    P = sortrows(P, 'forecast_timestamp');
    hold on; grid on;
    plot(P.forecast_timestamp, P.actual_active_users_site, '-', ...
        'Color', [0.10 0.10 0.10], 'LineWidth', 1.6);
    plot(P.forecast_timestamp, P.predicted_active_users_site, '-', ...
        'Color', [0.10 0.45 0.85], 'LineWidth', 1.4);
    xlabel('Хугацаа');
    ylabel('Идэвхтэй хэрэглэгчийн тоо');
    metricRow = forecast.metrics(forecast.metrics.sim_site_id == s, :);
    if ~isempty(metricRow)
        title(sprintf('Сайт %d | MAE %.2f | RMSE %.2f | R^2 %.2f', ...
            s, metricRow.test_mae, metricRow.test_rmse, metricRow.test_r2), ...
            'Interpreter', 'tex', 'FontSize', 10);
    else
        title(sprintf('Сайт %d', s), 'Interpreter', 'none');
    end
end
lgd = legend({'Бодит утга', 'Таамагласан утга'}, ...
    'Interpreter', 'none', 'FontSize', 10);
lgd.Layout.Tile = 'south';
title(tl, 'Сайт тус бүрийн 1 цагийн дараах идэвхтэй хэрэглэгчдийн таамаглал', ...
    'FontWeight', 'bold', 'FontSize', 14);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_tp_user_forecast_timeseries.png'));
end

function plot_actual_vs_predicted_scatter(vcfg, forecast)
preds = forecast.predictions;
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [120 120 620 540]);

hold on; grid on;
scatter(preds.actual_active_users_site, preds.predicted_active_users_site, ...
    24, [0.10 0.45 0.85], 'filled', 'MarkerFaceAlpha', 0.55);
lim = max([preds.actual_active_users_site; preds.predicted_active_users_site], [], 'omitnan');
if ~isfinite(lim) || lim <= 0
    lim = 1;
end
plot([0 lim], [0 lim], '--k', 'LineWidth', 1.0);
xlim([0 lim]); ylim([0 lim]);
axis square;
xlabel('Бодит хэрэглэгчийн тоо (1 цагийн дараа)');
ylabel('Таамагласан хэрэглэгчийн тоо (1 цагийн дараа)');
title('Бодит ба таамагласан утгуудын харьцуулалт (тест өдөр)', ...
    'FontWeight', 'bold', 'FontSize', 13);
legend({'Сайтын тест мөр', 'Төгс шугам (y = x)'}, ...
    'Location', 'northwest', 'Interpreter', 'none', 'FontSize', 10);

save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_tp_user_forecast_scatter.png'));
end

function plot_mae_bar(vcfg, forecast)
M = sortrows(forecast.metrics, 'sim_site_id');
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [140 140 1100 520]);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

labels = strings(height(M), 1);
for i = 1:height(M)
    labels(i) = sprintf('Сайт %d', M.sim_site_id(i));
end

nexttile;
maeMatrix = [M.train_mae, M.test_mae];
bh = bar(categorical(labels, labels), maeMatrix, 'grouped');
bh(1).FaceColor = [0.35 0.65 0.35];
bh(2).FaceColor = [0.10 0.45 0.85];
grid on;
ylabel('MAE (хэрэглэгчийн тоо)');
title('Сургалт ба тестийн MAE', 'Interpreter', 'none');
legend({'Сургалтын MAE','Тестийн MAE'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal');

nexttile;
r2Matrix = [M.train_r2, M.test_r2];
bh2 = bar(categorical(labels, labels), r2Matrix, 'grouped');
bh2(1).FaceColor = [0.35 0.65 0.35];
bh2(2).FaceColor = [0.10 0.45 0.85];
grid on;
ylabel('R^2');
title('Сургалт ба тестийн R^2', 'Interpreter', 'tex');
yline(0, '-k', 'LineWidth', 1.0);
legend({'Сургалтын R^2','Тестийн R^2'}, ...
    'Location', 'northoutside', 'Orientation', 'horizontal', ...
    'Interpreter', 'tex');

title(tl, 'TP таамаглалын үнэлгээ — сайт тус бүр', ...
    'FontWeight', 'bold', 'FontSize', 14);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_tp_user_forecast_mae_comparison.png'));
end

function plot_metrics_text_summary(vcfg, forecast)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [160 160 1100 540]);
axis off;
M = sortrows(forecast.metrics, 'sim_site_id');
lines = strings(0, 1);
lines(end+1) = "TP сайтын идэвхтэй хэрэглэгчдийн таамаглал | таамаглах хүрээ: +1 цаг";
lines(end+1) = "----------------------------------------------------------------------";
lines(end+1) = "Сайт    | Сургалт | Тест  | Сург.MAE | Тест MAE | Тест R^2 | Lambda";
for i = 1:height(M)
    lines(end+1) = sprintf('Сайт %-2d | %7d | %5d | %8.2f | %8.2f | %8.2f | %6g', ...
        M.sim_site_id(i), ...
        M.train_rows(i), M.test_rows(i), ...
        M.train_mae(i), M.test_mae(i), M.test_r2(i), M.ridge_lambda(i)); %#ok<AGROW>
end
lines(end+1) = "----------------------------------------------------------------------";
meanTestMae = mean(M.test_mae, 'omitnan');
meanTestR2 = mean(M.test_r2, 'omitnan');
meanGap = mean(M.generalization_gap_mae, 'omitnan');
goodSites = sum(M.test_r2 >= 0.5);
lines(end+1) = sprintf('Дундаж тест MAE: %.2f | Дундаж тест R^2: %.2f | R^2 >= 0.5 байгаа сайт: %d/%d', ...
    meanTestMae, meanTestR2, goodSites, height(M));
lines(end+1) = sprintf('Дундаж generalization gap (тест MAE - сургалт MAE): %.2f', meanGap);
lines(end+1) = "";
lines(end+1) = "Тайлбар: Тест R^2 өндөр (0.5+) бөгөөд generalization gap бага сайтуудад";
lines(end+1) = "таамаглал найдвартай ажиллаж байна. Бусад сайтад зөвхөн чиг хандлагын";
lines(end+1) = "зөвлөмж болгон хэрэглэнэ. Overfit-ыг бууруулахаар feature тоог цөөлж,";
lines(end+1) = "stand­ardize хийж, ridge λ-г walk-forward CV-р автоматаар сонголоо.";

y = 0.95;
for i = 1:numel(lines)
    weight = 'normal';
    if i <= 2
        weight = 'bold';
    end
    text(0.02, y, lines(i), 'Units', 'normalized', 'FontSize', 10, ...
        'FontWeight', weight, 'Interpreter', 'none', 'FontName', 'Consolas');
    y = y - 0.05;
end
sgtitle(fig, 'TP таамаглал — сайт бүрийн үзүүлэлтийн хүснэгт', ...
    'FontWeight', 'bold', 'FontSize', 14);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_tp_user_forecast_summary.png'));
end
