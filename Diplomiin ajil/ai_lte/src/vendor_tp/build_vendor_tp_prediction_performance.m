function performance = build_vendor_tp_prediction_performance(tpTable)
%BUILD_VENDOR_TP_PREDICTION_PERFORMANCE Per-sector TP accuracy summary.

performance = table();
if isempty(tpTable)
    return;
end

sectors = unique(tpTable.sim_sector_id);
rows = cell(numel(sectors), 14);
rowIdx = 0;
for s = sectors(:)'
    S = tpTable(tpTable.sim_sector_id == s & logical(tpTable.actual_1h_available), :);
    S = S(isfinite(S.predicted_dl_prb_utilization_1h) & isfinite(S.actual_dl_prb_utilization_1h), :);
    if isempty(S)
        continue;
    end

    err = S.predicted_dl_prb_utilization_1h - S.actual_dl_prb_utilization_1h;
    mae = mean(abs(err), 'omitnan');
    rmse = sqrt(mean(err.^2, 'omitnan'));
    bias = mean(err, 'omitnan');
    r2 = compute_r2(S.actual_dl_prb_utilization_1h, S.predicted_dl_prb_utilization_1h);
    maxActual = max(S.actual_dl_prb_utilization_1h, [], 'omitnan');
    maxPredicted = max(S.predicted_dl_prb_utilization_1h, [], 'omitnan');
    quality = classify_prediction_quality(mae, r2);
    displayCell = sprintf('S%d | cell %s', s, char(string(S.cell_uid(1))));
    interpretation = sprintf('MAE %.1f%%, R2 %.2f: %s', 100 * mae, r2, quality);

    rowIdx = rowIdx + 1;
    rows(rowIdx, :) = {compose('S%d', s), s, char(string(S.cell_uid(1))), ...
        S.cell_id(1), char(string(S.vendor_cell_name(1))), displayCell, height(S), ...
        mae, rmse, bias, r2, maxActual, maxPredicted, interpretation};
end

performance = cell2table(rows(1:rowIdx, :), 'VariableNames', ...
    {'affected_sector','sim_sector_id','cell_uid','cell_id','vendor_cell_name', ...
    'display_cell','metric_rows','mae_dl_prb_1h','rmse_dl_prb_1h', ...
    'bias_dl_prb_1h','r2_dl_prb_1h','max_actual_dl_prb_1h', ...
    'max_predicted_dl_prb_1h','interpretation'});
performance = sortrows(performance, {'mae_dl_prb_1h','r2_dl_prb_1h'}, {'ascend','descend'});
end

function r2 = compute_r2(actual, predicted)
err = predicted - actual;
sse = sum(err.^2, 'omitnan');
actualMean = mean(actual, 'omitnan');
sst = sum((actual - actualMean).^2, 'omitnan');
if sst <= eps
    r2 = NaN;
else
    r2 = 1 - sse / sst;
end
end

function quality = classify_prediction_quality(mae, r2)
if ~isfinite(r2)
    quality = 'insufficient variance for R2';
elseif r2 >= 0.70 && mae <= 0.12
    quality = 'usable short-term evidence';
elseif r2 >= 0.45 && mae <= 0.18
    quality = 'moderate evidence, use with caution';
else
    quality = 'weak TP fit, do not overclaim';
end
end
