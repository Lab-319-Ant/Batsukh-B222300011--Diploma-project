function qpTable = run_qp_from_vendor_kpi(tpTable, codTable, vcfg)
%RUN_QP_FROM_VENDOR_KPI Vendor KPI QoS degradation-risk advisory.
%
% This is not a live QoS controller. It combines the one-hour TP forecast
% with real KPI evidence and COD state to flag rows where QoS degradation is
% plausible enough for engineering review.

qpTable = table();
if isempty(tpTable)
    return;
end

T = sortrows(tpTable, {'sim_sector_id','timestamp'});
n = height(T);

[codState, codReason, rrcSetup, erabSetup, rrcDrop, erabDrop, dlBler, rssiAvg] = ...
    align_cod_evidence(T, codTable);

currentThr = get_num(T, 'current_dl_throughput_mbps', NaN);
predThr = get_num(T, 'predicted_dl_throughput_mbps_1h', NaN);
actualThr = get_num(T, 'actual_dl_throughput_mbps_1h', NaN);
predPrb = get_num(T, 'predicted_dl_prb_utilization_1h', NaN);
actualAvailable = logical(get_num(T, 'actual_1h_available', 0));

predDrop = throughput_drop_ratio(currentThr, predThr, vcfg.qpMinThroughputForDropMbps);
actualDrop = throughput_drop_ratio(currentThr, actualThr, vcfg.qpMinThroughputForDropMbps);
actualDrop(~actualAvailable) = NaN;

loadComponent = normalize_above(predPrb, vcfg.qpCongestionPrbStartThreshold, 0.95);
throughputComponent = normalize_above(predDrop, ...
    vcfg.qpThroughputDropWarningRatio, vcfg.qpThroughputDropCriticalRatio);
blerComponent = normalize_above(dlBler, vcfg.qpDlBlerWarningThreshold, ...
    vcfg.qpDlBlerCriticalThreshold);
dropComponent = max(normalize_above(erabDrop, 0.01, 0.05), ...
    normalize_above(rrcDrop, 0.02, 0.08));
setupComponent = max(normalize_above(1 - erabSetup, 0.01, 0.05), ...
    normalize_above(1 - rrcSetup, 0.01, 0.05));
rssiComponent = normalize_below(rssiAvg, -100, -115);
kpiComponent = max([blerComponent, dropComponent, setupComponent, rssiComponent], [], 2);

codComponent = zeros(n, 1);
codComponent(strcmp(codState, "degraded_kpi")) = 0.65;
codComponent(strcmp(codState, "outage_like")) = 1.00;

riskScore = 0.42 * loadComponent + 0.28 * throughputComponent + ...
    0.18 * kpiComponent + 0.12 * codComponent;
riskScore = max(riskScore, 0.70 * strcmp(codState, "outage_like"));
riskScore = max(riskScore, 0.52 * strcmp(codState, "degraded_kpi"));
riskScore = clamp_value(riskScore, 0, 1);

riskClass = repmat("normal", n, 1);
decision = repmat("no_qp_action", n, 1);
reason = strings(n, 1);

for i = 1:n
    [riskClass(i), decision(i), reason(i)] = classify_qp_row( ...
        codState(i), codReason(i), predPrb(i), predDrop(i), rrcSetup(i), ...
        erabSetup(i), rrcDrop(i), erabDrop(i), dlBler(i), rssiAvg(i), riskScore(i), vcfg);
end

affectedSector = compose('S%d', T.sim_sector_id);
displayCell = compose('S%d | cell %s', T.sim_sector_id, string(T.cell_uid));

qpTable = table(T.timestamp, T.sim_site_id, T.sim_sector_id, cellstr(affectedSector), ...
    cellstr(string(T.cell_uid)), T.cell_id, cellstr(displayCell), ...
    T.current_dl_prb_utilization, predPrb, T.current_active_users, ...
    T.predicted_active_users_1h, currentThr, predThr, actualThr, ...
    predDrop, actualDrop, actualAvailable, rrcSetup, erabSetup, rrcDrop, ...
    erabDrop, dlBler, rssiAvg, cellstr(codState), riskScore, ...
    cellstr(riskClass), cellstr(decision), cellstr(reason), ...
    'VariableNames', {'timestamp','sim_site_id','sim_sector_id','affected_sector', ...
    'cell_uid','cell_id','display_cell','current_dl_prb_utilization', ...
    'predicted_dl_prb_utilization_1h','current_active_users', ...
    'predicted_active_users_1h','current_dl_throughput_mbps', ...
    'predicted_dl_throughput_mbps_1h','actual_dl_throughput_mbps_1h', ...
    'predicted_throughput_drop_ratio','actual_throughput_drop_ratio_1h', ...
    'actual_1h_available','rrc_setup_success_rate','erab_setup_success_rate', ...
    'rrc_drop_rate','erab_drop_rate','dl_bler','rssi_avg_dbm','cod_state', ...
    'qp_risk_score','qp_risk_class','qp_decision','qp_reason'});
end

function [state, reason, rrcSetup, erabSetup, rrcDrop, erabDrop, dlBler, rssiAvg] = ...
    align_cod_evidence(T, codTable)
n = height(T);
state = repmat("missing_cod_evidence", n, 1);
reason = repmat("missing_cod_evidence", n, 1);
rrcSetup = nan(n, 1);
erabSetup = nan(n, 1);
rrcDrop = nan(n, 1);
erabDrop = nan(n, 1);
dlBler = nan(n, 1);
rssiAvg = nan(n, 1);

if isempty(codTable)
    return;
end

[tf, loc] = ismember(make_key(T), make_key(codTable));
idxT = find(tf);
idxC = loc(tf);
if isempty(idxT)
    return;
end

state(idxT) = string(codTable.cod_state(idxC));
reason(idxT) = string(codTable.cod_reason(idxC));
rrcSetup(idxT) = codTable.rrc_setup_success_rate(idxC);
erabSetup(idxT) = codTable.erab_setup_success_rate(idxC);
rrcDrop(idxT) = codTable.rrc_drop_rate(idxC);
erabDrop(idxT) = codTable.erab_drop_rate(idxC);
dlBler(idxT) = codTable.dl_bler(idxC);
rssiAvg(idxT) = codTable.rssi_avg_dbm(idxC);
end

function key = make_key(T)
key = string(T.sim_sector_id) + "|" + string(cellstr(datestr(T.timestamp, 'yyyymmddHHMMSS')));
end

function x = get_num(T, name, defaultValue)
x = repmat(defaultValue, height(T), 1);
if ismember(name, T.Properties.VariableNames)
    x = T.(name);
end
end

function r = throughput_drop_ratio(currentThr, nextThr, minThr)
r = nan(size(currentThr));
valid = isfinite(currentThr) & isfinite(nextThr) & currentThr >= minThr;
r(valid) = (currentThr(valid) - nextThr(valid)) ./ max(currentThr(valid), eps);
r(valid) = clamp_value(r(valid), 0, 1);
r(~valid) = 0;
end

function y = normalize_above(x, startValue, fullValue)
y = (x - startValue) ./ max(fullValue - startValue, eps);
y = clamp_value(y, 0, 1);
y(~isfinite(x)) = 0;
end

function y = normalize_below(x, startValue, fullValue)
y = (startValue - x) ./ max(startValue - fullValue, eps);
y = clamp_value(y, 0, 1);
y(~isfinite(x)) = 0;
end

function [riskClass, decision, reason] = classify_qp_row(codState, codReason, predPrb, ...
    predDrop, rrcSetup, erabSetup, rrcDrop, erabDrop, dlBler, rssiAvg, riskScore, vcfg)
if ismember(codState, ["outage_like","degraded_kpi"])
    riskClass = "blocked_by_cod_incident";
    decision = "resolve_cod_coc_before_qp";
    reason = "COD is already abnormal: " + codReason;
    return;
end

highLoad = predPrb >= vcfg.qpHighPrbThreshold;
warnLoad = predPrb >= vcfg.tpOverloadPrbThreshold;
throughputDrop = predDrop >= vcfg.qpThroughputDropWarningRatio;
criticalDrop = predDrop >= vcfg.qpThroughputDropCriticalRatio;
poorSetup = rrcSetup < 0.98 | erabSetup < 0.98;
highDrop = rrcDrop > 0.03 | erabDrop > 0.02;
highBler = dlBler >= vcfg.qpDlBlerWarningThreshold;
weakRssi = rssiAvg <= -100;

if riskScore >= vcfg.qpHighRiskThreshold || (highLoad && criticalDrop)
    riskClass = "critical_qos_risk";
elseif riskScore >= vcfg.qpModerateRiskThreshold || (warnLoad && throughputDrop)
    riskClass = "degradation_risk";
elseif riskScore >= 0.25
    riskClass = "monitor";
else
    riskClass = "normal";
end

if strcmp(riskClass, "normal")
    decision = "no_qp_action";
elseif warnLoad && throughputDrop
    decision = "review_capacity_lb_scheduler";
elseif highLoad
    decision = "prepare_lb_capacity_help";
elseif throughputDrop && (poorSetup || highDrop || highBler || weakRssi)
    decision = "review_radio_quality_before_capacity";
else
    decision = "monitor_qos_kpi_trend";
end

tags = strings(0, 1);
if highLoad, tags(end+1) = sprintf('predicted PRB %.1f%%', 100 * predPrb); end %#ok<AGROW>
if throughputDrop, tags(end+1) = sprintf('predicted throughput drop %.1f%%', 100 * predDrop); end %#ok<AGROW>
if poorSetup, tags(end+1) = "setup success below 98%"; end %#ok<AGROW>
if highDrop, tags(end+1) = "RRC/ERAB drop elevated"; end %#ok<AGROW>
if highBler, tags(end+1) = sprintf('DL BLER %.1f%%', 100 * dlBler); end %#ok<AGROW>
if weakRssi, tags(end+1) = sprintf('RSSI %.1f dBm', rssiAvg); end %#ok<AGROW>
if isempty(tags), tags = "risk score from combined KPI evidence"; end
reason = strjoin(tags, "|");
end

function y = clamp_value(x, lowerBound, upperBound)
y = min(max(x, lowerBound), upperBound);
end
