function tpTable = run_tp_from_vendor_kpi(cleanKpi, vcfg)
%RUN_TP_FROM_VENDOR_KPI Short-term traffic/load prediction from vendor KPI.
%
% This is a one-hour-ahead KPI predictor for 15-minute vendor data.
% It blends current load, short rolling history, and previous-day same-time
% behavior where available. One week of KPI supports short-term operational
% warning only, not robust long-term forecasting claims.

T = cleanKpi(cleanKpi.selected_for_21cell_topology, :);
tpTable = table();
if isempty(T)
    return;
end

T = sortrows(T, {'sim_sector_id','timestamp'});
rows = cell(height(T), 22);
rowIdx = 0;
sectors = unique(T.sim_sector_id);
for s = sectors(:)'
    S = T(T.sim_sector_id == s, :);
    S = sortrows(S, 'timestamp');
    n = height(S);
    for i = 1:n
        histStart = max(1, i - vcfg.tpRollingWindowSteps + 1);
        histIdx = histStart:i;
        actualIdx = i + vcfg.tpForecastHorizonSteps;

        rollingPrb = mean(S.dl_prb_utilization(histIdx), 'omitnan');
        rollingUsers = mean(S.active_users(histIdx), 'omitnan');
        rollingTraffic = mean(S.traffic_volume_dl_kbyte(histIdx), 'omitnan');
        rollingThr = mean(S.dl_throughput_mbps(histIdx), 'omitnan');

        prevDayIdx = find(S.timestamp == S.timestamp(i) - days(1), 1, 'last');
        if ~isempty(prevDayIdx)
            predPrb = blend_short_term(S.dl_prb_utilization(i), rollingPrb, S.dl_prb_utilization(prevDayIdx), 0, 1);
            predUsers = blend_short_term(S.active_users(i), rollingUsers, S.active_users(prevDayIdx), 0, inf);
            predTraffic = blend_short_term(S.traffic_volume_dl_kbyte(i), rollingTraffic, S.traffic_volume_dl_kbyte(prevDayIdx), 0, inf);
            predThr = blend_short_term(S.dl_throughput_mbps(i), rollingThr, S.dl_throughput_mbps(prevDayIdx), 0, inf);
            method = 'one_hour_ahead_hybrid_current_rolling_previous_day';
        else
            predPrb = clamp_value(0.65 * S.dl_prb_utilization(i) + 0.35 * rollingPrb, 0, 1);
            predUsers = clamp_value(0.65 * S.active_users(i) + 0.35 * rollingUsers, 0, inf);
            predTraffic = clamp_value(0.65 * S.traffic_volume_dl_kbyte(i) + 0.35 * rollingTraffic, 0, inf);
            predThr = clamp_value(0.65 * S.dl_throughput_mbps(i) + 0.35 * rollingThr, 0, inf);
            method = 'one_hour_ahead_hybrid_current_rolling';
        end

        if actualIdx <= n && minutes(S.timestamp(actualIdx) - S.timestamp(i)) == ...
                vcfg.tpForecastHorizonSteps * vcfg.expectedGranularityMinutes
            actualPrb = S.dl_prb_utilization(actualIdx);
            actualUsers = S.active_users(actualIdx);
            actualTraffic = S.traffic_volume_dl_kbyte(actualIdx);
            actualThr = S.dl_throughput_mbps(actualIdx);
            actualAvailable = true;
        else
            actualPrb = NaN;
            actualUsers = NaN;
            actualTraffic = NaN;
            actualThr = NaN;
            actualAvailable = false;
        end

        rowIdx = rowIdx + 1;
        rows(rowIdx, :) = {S.timestamp(i), S.sim_site_id(i), char(string(S.sim_position(i))), ...
            S.sim_sector_id(i), char(string(S.vendor_site_key(i))), char(string(S.cell_uid(i))), ...
            S.cell_id(i), char(string(S.vendor_cell_name(i))), ...
            S.dl_prb_utilization(i), S.active_users(i), S.traffic_volume_dl_kbyte(i), ...
            S.dl_throughput_mbps(i), predPrb, predUsers, predTraffic, predThr, ...
            actualPrb, actualUsers, actualTraffic, actualThr, actualAvailable, method};
    end
end

tpTable = cell2table(rows(1:rowIdx, :), 'VariableNames', ...
    {'timestamp','sim_site_id','sim_position','sim_sector_id','vendor_site_key', ...
    'cell_uid','cell_id','vendor_cell_name','current_dl_prb_utilization', ...
    'current_active_users','current_traffic_volume_dl_kbyte','current_dl_throughput_mbps', ...
    'predicted_dl_prb_utilization_1h','predicted_active_users_1h', ...
    'predicted_traffic_volume_dl_kbyte_1h','predicted_dl_throughput_mbps_1h', ...
    'actual_dl_prb_utilization_1h','actual_active_users_1h', ...
    'actual_traffic_volume_dl_kbyte_1h','actual_dl_throughput_mbps_1h', ...
    'actual_1h_available','prediction_method'});
end

function y = blend_short_term(currentValue, rollingValue, previousDayValue, lowerBound, upperBound)
y = 0.45 * currentValue + 0.20 * rollingValue + 0.35 * previousDayValue;
y = clamp_value(y, lowerBound, upperBound);
end

function y = clamp_value(x, lowerBound, upperBound)
if ~isfinite(x)
    y = NaN;
    return;
end
y = max(x, lowerBound);
if isfinite(upperBound)
    y = min(y, upperBound);
end
end
