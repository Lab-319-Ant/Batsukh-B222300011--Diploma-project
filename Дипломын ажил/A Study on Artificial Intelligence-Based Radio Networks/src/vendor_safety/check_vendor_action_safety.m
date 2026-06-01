function [safeFlag, rejectionReason] = check_vendor_action_safety(sourceRow, targetRows, vcfg)
%CHECK_VENDOR_ACTION_SAFETY Safety gate for KPI-only COC suggestions.

if isempty(targetRows)
    safeFlag = false;
    rejectionReason = "no_target_neighbor_kpi_available";
    return;
end

badAvailability = targetRows.cell_availability < vcfg.cocMinAvailabilityForTarget;
badLoad = targetRows.dl_prb_utilization > vcfg.cocNeighborLoadHardRejectThreshold;
highDrop = targetRows.erab_drop_rate > vcfg.cocMaxDropRateForTarget | ...
    targetRows.rrc_drop_rate > vcfg.codRrcDropHighThreshold;
targetBad = badAvailability | badLoad | highDrop;

if all(targetBad)
    safeFlag = false;
    rejectionReason = "all_candidate_targets_unsafe";
elseif sourceRow.cell_availability <= vcfg.codAvailabilityOutageThreshold && ...
        sourceRow.tx_power_w <= 0.01
    safeFlag = false;
    rejectionReason = "source_off_air_check_alarm_power_backhaul_first";
else
    safeFlag = true;
    rejectionReason = "ok";
end
end
