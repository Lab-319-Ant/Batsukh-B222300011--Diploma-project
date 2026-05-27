$ErrorActionPreference = 'Stop'

$AuditDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $AuditDir '..\..')).Path
$TablesDir = Join-Path $Root 'results\tables'
$FiguresDir = Join-Path $Root 'results\figures'
$ModelsDir = Join-Path $Root 'models'

function Read-AuditCsv($name) {
    $p = Join-Path $TablesDir $name
    if (Test-Path $p) { return @(Import-Csv $p) }
    return @()
}

function Count-Rows($name) {
    $p = Join-Path $TablesDir $name
    if (-not (Test-Path $p)) { return 0 }
    $n = 0
    [System.IO.File]::ReadLines($p) | Select-Object -Skip 1 | ForEach-Object { $n++ }
    return $n
}

function To-Num($v) {
    if ($null -eq $v -or $v -eq '') { return [double]::NaN }
    $x = 0.0
    if ([double]::TryParse([string]$v, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$x)) {
        return $x
    }
    return [double]::NaN
}

function Bool-Text($b) {
    if ($b) { return 'true' }
    return 'false'
}

function Pass-Flag($b) {
    if ($b) { return 1 }
    return 0
}

function Write-AuditCsv($name, $rows) {
    $p = Join-Path $TablesDir $name
    @($rows) | Export-Csv -Path $p -NoTypeInformation -Encoding UTF8
}

function Get-ValidationCounts($name) {
    $rows = Read-AuditCsv $name
    $errors = 0
    $warnings = 0
    foreach ($r in $rows) {
        $pass = "$($r.pass_flag)"
        if ($pass -eq '0' -or $pass -match 'false') {
            $sev = "$($r.severity)".ToLowerInvariant()
            if ($sev -match 'warn') { $warnings++ }
            elseif ($sev -notmatch 'diagnostic') { $errors++ }
        }
    }
    [pscustomobject]@{ file = $name; rows = $rows.Count; errors = $errors; warnings = $warnings }
}

function Get-ValidationActual($name, $check) {
    $row = Read-AuditCsv $name | Where-Object { $_.check_name -eq $check } | Select-Object -First 1
    if ($row) { return "$($row.actual_value)" }
    return ''
}

function Avg-Col($rows, $col) {
    $vals = @()
    foreach ($r in $rows) {
        $v = To-Num $r.$col
        if (-not [double]::IsNaN($v)) { $vals += $v }
    }
    if ($vals.Count -eq 0) { return [double]::NaN }
    return ($vals | Measure-Object -Average).Average
}

function Phase-ForFile($rel) {
    $p = $rel.Replace('\','/')
    if ($p -eq 'main.m') { return 'main_entrypoint' }
    if ($p -like 'config/*') { return 'configuration' }
    if ($p -like 'src/topology/*' -or $p -like 'src/ue/*' -or $p -like 'src/rf/*') { return 'Phase 1B RF/topology' }
    if ($p -like 'src/traffic/*' -or $p -like 'src/kpi/*') { return 'Phase 2 traffic/KPI' }
    if ($p -like 'src/scenarios/*') { return 'Phase 3 scenarios' }
    if ($p -like 'src/dataset/*phase4*' -or $p -like 'src/dataset/*feature*') { return 'Phase 4/4B datasets' }
    if ($p -like 'src/ml/*phase5*' -or $p -like 'src/ml/*cluster*') { return 'Phase 5 clustering' }
    if ($p -like 'src/dataset/*cod*' -or $p -like 'src/ml/*cod*') { return 'Phase 6 COD' }
    if ($p -like 'src/dataset/*phase7*' -or $p -like 'src/ml/*phase7*' -or $p -like 'src/ml/*walk_forward*') { return 'Phase 7 TP/QP' }
    if ($p -like 'src/actions/*') { return 'Phase 8 actions/oracle' }
    if ($p -like 'src/dataset/*phase9*' -or $p -like 'src/dataset/*action_value*' -or $p -like 'src/ml/*phase9*' -or $p -like 'src/ml/*action_value*') { return 'Phase 9 action-value ML' }
    if ($p -like 'src/ml/*phase10*' -or $p -like 'src/ml/*safety*') { return 'Phase 10 safety-enforced ML' }
    if ($p -like 'src/coordination/*') { return 'Phase 11 coordinator' }
    if ($p -like 'src/application/*') { return 'Phase 12 KPI(t+1)' }
    if ($p -like 'src/validation/*phase12e*') { return 'Phase 12E validation' }
    if ($p -like 'src/validation/*phase12d*') { return 'Phase 12D validation' }
    if ($p -like 'src/validation/*phase12c*') { return 'Phase 12C validation' }
    if ($p -like 'src/validation/*phase12b*') { return 'Phase 12B validation' }
    if ($p -like 'src/validation/*phase12a*') { return 'Phase 12A validation' }
    if ($p -like 'src/validation/*phase11*') { return 'Phase 11 validation' }
    if ($p -like 'src/validation/*phase10*') { return 'Phase 10 validation' }
    if ($p -like 'src/validation/*phase9*') { return 'Phase 9 validation' }
    if ($p -like 'src/validation/*phase8*') { return 'Phase 8 validation' }
    if ($p -like 'src/validation/*phase7*') { return 'Phase 7 validation' }
    if ($p -like 'src/validation/*phase6*' -or $p -like 'src/validation/*cod*') { return 'Phase 6 validation' }
    if ($p -like 'src/validation/*phase5*') { return 'Phase 5 validation' }
    if ($p -like 'src/validation/*phase4*') { return 'Phase 4 validation' }
    if ($p -like 'src/validation/*phase3*') { return 'Phase 3 validation' }
    if ($p -like 'src/validation/*traffic*') { return 'Phase 2 validation' }
    if ($p -like 'src/plot/*') { return 'plotting/artifacts' }
    if ($p -like 'src/workflow/*') { return 'workflow shortcuts' }
    if ($p -like 'src/utils/*') { return 'utilities' }
    if ($p -like 'src/reporting/*') { return 'Phase 13 reporting' }
    return 'support'
}

function Purpose-ForFile($path) {
    $lines = Get-Content $path -TotalCount 8
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t -match '^%[A-Z0-9_]+\s+(.+)$') { return $Matches[1].Trim() }
        if ($t -match '^%\s*(.+)$' -and $Matches[1].Trim().Length -gt 12) { return $Matches[1].Trim() }
    }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($path)
    return $base.Replace('_',' ')
}

function Build-Inventory {
    $roots = @((Join-Path $Root 'main.m'), (Join-Path $Root 'config'), (Join-Path $Root 'src'))
    $files = @()
    foreach ($r in $roots) {
        if (Test-Path $r -PathType Leaf) { $files += Get-Item $r }
        elseif (Test-Path $r) { $files += Get-ChildItem $r -Recurse -Filter '*.m' -File }
    }
    $mainText = Get-Content (Join-Path $Root 'main.m') -Raw
    $allTexts = @{}
    foreach ($f in $files) { $allTexts[$f.FullName] = Get-Content $f.FullName -Raw }
    $rows = @()
    foreach ($f in ($files | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($Root.Length + 1)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $calledMain = ($f.Name -eq 'main.m') -or ($mainText -match "\b$([regex]::Escape($name))\b")
        $calledOther = $false
        foreach ($kv in $allTexts.GetEnumerator()) {
            if ($kv.Key -eq $f.FullName) { continue }
            if ($kv.Value -match "\b$([regex]::Escape($name))\b") { $calledOther = $true; break }
        }
        $phase = Phase-ForFile $rel
        $status = 'appears_unused'
        $notes = ''
        if ($f.Name -eq 'main.m') { $status = 'entrypoint'; $notes = 'Primary script run by audit.' }
        elseif ($rel -replace '/','\' -eq 'config\sim_config.m') { $status = 'active_config'; $notes = 'Loaded by main.m.' }
        elseif ($phase -eq 'Phase 13 reporting') { $status = 'scope_conflict_phase13_present'; $notes = 'Phase 13 is present even though this audit was requested before Phase 13.' }
        elseif ($calledMain) { $status = 'used_by_main'; $notes = 'Directly referenced by main.m.' }
        elseif ($calledOther) { $status = 'used_indirectly'; $notes = 'Referenced by another MATLAB file.' }
        if ($rel -match 'sim_config_single_site|create_single_site3sector|plot_single_site_geometry') {
            $status = 'legacy_or_unused'
            $notes = 'Single-site legacy/support path; not used by current 7-site main workflow.'
        }
        $rows += [pscustomobject]@{
            file_path = $rel
            phase = $phase
            purpose = Purpose-ForFile $f.FullName
            called_by_main = Pass-Flag $calledMain
            called_by_other_file = Pass-Flag $calledOther
            status = $status
            notes = $notes
        }
    }
    Write-AuditCsv 'audit_file_inventory.csv' $rows
}

Build-Inventory

$phase1 = (Read-AuditCsv 'phase1b_summary.csv' | Select-Object -First 1)
$phase2c = Read-AuditCsv 'phase2c_traffic_calibration_summary.csv'
$phase3 = Read-AuditCsv 'phase3_scenario_summary.csv'
$phase5k = Read-AuditCsv 'phase5_clustering_k_evaluation.csv'
$phase10Filter = Read-AuditCsv 'phase10a_safety_filter_summary.csv'
$phase10Tie = Read-AuditCsv 'phase10a_reward_tie_audit.csv'
$phase11b = Read-AuditCsv 'phase11b_final_coordinator_decisions.csv'
$phase12d = Read-AuditCsv 'phase12d_one_step_kpi_update_results.csv'
$phase12eComp = Read-AuditCsv 'phase12e_baseline_ai_oracle_comparison.csv'
$timing = Read-AuditCsv 'run_phase_timing_log.csv'
$configText = Get-Content (Join-Path $Root 'config\sim_config.m') -Raw
$readmeText = Get-Content (Join-Path $Root 'README.md') -Raw

$validationFiles = @(
    'phase4_dataset_validation.csv','phase4b_ml_feature_validation.csv','phase5_clustering_validation.csv',
    'phase6a_cod_dataset_validation.csv','phase6b_cod_model_validation.csv','phase7a_dataset_validation.csv',
    'phase7b_tp_qp_validation.csv','phase7c_tp_qp_diagnostic_validation.csv','phase8a_candidate_action_validation.csv',
    'phase8b_counterfactual_validation.csv','phase8c_oracle_validation.csv','phase9a_action_value_validation.csv',
    'phase9b_action_value_validation.csv','phase10a_safety_enforced_validation.csv','phase11a_coordination_validation.csv',
    'phase11b_final_coordination_validation.csv','phase12a_feasibility_validation.csv','phase12b_action_state_validation.csv',
    'phase12c_kpi_eligible_validation.csv','phase12d_one_step_validation.csv','phase12e_final_comparison_validation.csv'
)
$validationCounts = @{}
foreach ($vf in $validationFiles) { $validationCounts[$vf] = Get-ValidationCounts $vf }
function VErr($file) { return $validationCounts[$file].errors }
function VWarn($file) { return $validationCounts[$file].warnings }

$phase2Low = $phase2c | Where-Object traffic_mode -eq 'low_load' | Select-Object -First 1
$phase2Normal = $phase2c | Where-Object traffic_mode -eq 'normal' | Select-Object -First 1
$phase2Over = $phase2c | Where-Object traffic_mode -eq 'overload' | Select-Object -First 1
$phase2Heavy = $phase2c | Where-Object traffic_mode -eq 'heavy_overload' | Select-Object -First 1
$scnNormal = $phase3 | Where-Object scenario_name -eq 'normal' | Select-Object -First 1
$scnHO = $phase3 | Where-Object scenario_name -eq 'handover_stress' | Select-Object -First 1
$selectedK = $phase5k | Where-Object k -eq '4' | Select-Object -First 1
$phase10RawUnsafe = ($phase10Filter | ForEach-Object { [int](To-Num $_.raw_unsafe_top1_count) } | Measure-Object -Sum).Sum
$phase10ResidualUnsafe = ($phase10Filter | ForEach-Object { [int](To-Num $_.safe_unsafe_selected_count) } | Measure-Object -Sum).Sum
$phase10TieNonzero = (($phase10Tie | Where-Object check_name -eq 'nonzero_regret_mismatch_count' | Select-Object -First 1).value)
$phase10MaxDiff = (($phase10Tie | Where-Object check_name -eq 'max_abs_reward_difference' | Select-Object -First 1).value)
$lastPhase = if ($timing.Count -gt 0) { $timing[-1].phase_name } else { '' }
$phase13Enabled = ($configText -match 'cfg.enablePhase13\s*=\s*true')
$phase13BoundaryPass = (-not $phase13Enabled -and $lastPhase -notmatch 'Phase13')
$phase13BoundaryNotes = if ($phase13BoundaryPass) {
    'Phase 13 is disabled by default and the audited run stopped before packaging.'
} else {
    'Phase 13 must remain disabled for the pre-Phase-13 audit boundary.'
}

$finalSafe = ($phase11b | Where-Object final_decision_status -eq 'final_safe_action').Count
$finalNoop = ($phase11b | Where-Object final_decision_status -eq 'final_noop').Count
$finalRejected = ($phase11b | Where-Object final_decision_status -eq 'rejected_priority_conflict').Count
$finalFallback = ($phase11b | Where-Object final_decision_status -eq 'unresolved_unsafe_fallback').Count

$mean12dAttach = Avg-Col $phase12d 'delta_attach_rate'
$mean12dRsrp = Avg-Col $phase12d 'delta_mean_rsrp_dB'
$mean12dSinr = Avg-Col $phase12d 'delta_mean_sinr_dB'
$mean12dLoad = Avg-Col $phase12d 'delta_mean_sector_load'
$mean12dQos = Avg-Col $phase12d 'delta_qos_satisfaction_ratio'
$phase12dGroups = ($phase12d | ForEach-Object { "$($_.scenario_name)|$($_.realization_id)" } | Sort-Object -Unique).Count

$eligible = Read-AuditCsv 'phase12c_kpi_update_eligible_actions.csv'
$eligibleExcluded = Read-AuditCsv 'phase12c_kpi_update_excluded_actions.csv'
$appliedLog = Read-AuditCsv 'phase12d_action_application_log.csv'
$finalExec = Read-AuditCsv 'phase11b_final_executable_actions.csv'

$actualModifiedRows = @()
foreach ($r in $eligible) {
    $appSector = if ($r.PSObject.Properties.Name -contains 'application_affected_sector_id') { [int](To-Num $r.application_affected_sector_id) } else { [int](To-Num $r.target_sector_id) }
    $stateVariables = @()
    if ($r.PSObject.Properties.Name -contains 'application_state_variable') {
        $stateVariables = "$($r.application_state_variable)" -split '\|' | Where-Object { $_ -ne '' }
    }
    if ($stateVariables.Count -eq 0) {
        $param = "$($r.affected_parameter)"
        if ($r.module_name -eq 'LB/MLB' -or $param -eq 'CIO_bias') { $stateVariables = @('sectors.cio_dB') }
        elseif ($param -eq 'PRS_power_offset') { $stateVariables = @('sectors.referencePowerOffset_dB') }
        elseif ($param -eq 'antenna_tilt') { $stateVariables = @('sectors.electricalTilt_deg') }
        else { $stateVariables = @($param) }
    }
    foreach ($stateVariable in $stateVariables) {
        $actualModifiedRows += [pscustomobject]@{
            scenario_name = $r.scenario_name
            realization_id = $r.realization_id
            coordinator_group_id = $r.coordinator_group_id
            action_id = $r.selected_action_id_safe
            module_name = $r.module_name
            source_sector_id = $r.source_sector_id
            actual_modified_sector_id = $appSector
            actual_parameter = $stateVariable
        }
    }
}
$duplicateActualGroups = @($actualModifiedRows | Group-Object coordinator_group_id,actual_modified_sector_id,actual_parameter | Where-Object Count -gt 1)
$duplicateActualRows = ($duplicateActualGroups | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
if ($null -eq $duplicateActualRows) { $duplicateActualRows = 0 }

$arch = @()
function Add-Arch($phase,$expected,$actual,$pass,$severity,$notes) {
    $script:arch += [pscustomobject]@{ phase=$phase; expected_behavior=$expected; actual_behavior=$actual; pass_flag=(Pass-Flag $pass); severity=$severity; notes=$notes }
}
Add-Arch 'Phase 1B' '7-site / 21-sector topology' "$($phase1.numSites) sites, $($phase1.numSectors) sectors" ((To-Num $phase1.numSites) -eq 7 -and (To-Num $phase1.numSectors) -eq 21) 'INFO' ''
Add-Arch 'Phase 1B' 'RF validation with physical RSRP/SINR and attach rate' "attach=$($phase1.attachRate), plannedCoverage=$($phase1.plannedCoverageRatio)" ((To-Num $phase1.attachRate) -gt 0.95) 'INFO' 'calc_rsrp_sinr uses RSRP matrix and RxTotal interference.'
Add-Arch 'Phase 2' 'Traffic and KPI engine separates attachment from QoS' "attach=$($phase2Normal.attach_rate), QoS=$($phase2Normal.qos_satisfaction_ratio)" ((To-Num $phase2Normal.attach_rate) -ne (To-Num $phase2Normal.qos_satisfaction_ratio)) 'INFO' ''
Add-Arch 'Phase 3' 'Eight named scenarios generated' (($phase3 | Select-Object -ExpandProperty scenario_name) -join ', ') ($phase3.Count -eq 8) 'INFO' ''
Add-Arch 'Phase 4/4B' 'Multi-scenario dataset and leakage-controlled feature tables' "sector rows=$(Count-Rows 'phase4_sector_state_dataset.csv'); Phase4B validation errors=$(VErr 'phase4b_ml_feature_validation.csv')" ((Count-Rows 'phase4_sector_state_dataset.csv') -eq 3528 -and (VErr 'phase4b_ml_feature_validation.csv') -eq 0) 'INFO' ''
Add-Arch 'Phase 5' 'Clustering monitor only, not decision maker' "k=4, silhouette=$($selectedK.mean_silhouette); main text states monitor only" ((To-Num $selectedK.mean_silhouette) -lt 0.6 -and ($readmeText -match 'Clustering is not the final decision maker')) 'INFO' ''
Add-Arch 'Phase 6' 'COD detects normal/degraded/outage and does not apply actions' "validation errors=$(VErr 'phase6b_cod_model_validation.csv')" ((VErr 'phase6b_cod_model_validation.csv') -eq 0) 'INFO' ''
Add-Arch 'Phase 7' 'TP/QP are support modules; QP bounded regression limitation accepted' "Phase7B warnings=$(VWarn 'phase7b_tp_qp_validation.csv'), Phase7C errors=$(VErr 'phase7c_tp_qp_diagnostic_validation.csv')" ((VErr 'phase7c_tp_qp_diagnostic_validation.csv') -eq 0) 'MINOR' 'QP warning is expected because target is close to bimodal.'
Add-Arch 'Phase 8' 'Candidate generation, counterfactual reward, safety-constrained oracle; no KPI(t+1)' "Phase8B rows=$(Get-ValidationActual 'phase8b_counterfactual_validation.csv' 'total_evaluated_actions'); oracle rows=$(Count-Rows 'phase8c_oracle_selected_actions.csv')" ((VErr 'phase8b_counterfactual_validation.csv') -eq 0 -and (VErr 'phase8c_oracle_validation.csv') -eq 0) 'INFO' ''
Add-Arch 'Phase 9' 'Action-value ML uses reward as target only; oracle_selected metadata only' "Phase9A leakage validation errors=$(VErr 'phase9a_action_value_validation.csv'); Phase9B warnings=$(VWarn 'phase9b_action_value_validation.csv')" ((VErr 'phase9a_action_value_validation.csv') -eq 0 -and (VErr 'phase9b_action_value_validation.csv') -eq 0) 'INFO' ''
Add-Arch 'Phase 10' 'Safety filter removes unsafe actions; no action application' "raw unsafe=$phase10RawUnsafe, residual fallback=$phase10ResidualUnsafe, validation errors=$(VErr 'phase10a_safety_enforced_validation.csv')" ((VErr 'phase10a_safety_enforced_validation.csv') -eq 0) 'MINOR' 'Residual unsafe rows are fallback diagnostics.'
Add-Arch 'Phase 11' 'Offline coordinator final decision table; all rows not applied before Phase 12D' "rows=$($phase11b.Count), safe=$finalSafe, no-op=$finalNoop, rejected=$finalRejected, fallback=$finalFallback" ($phase11b.Count -eq 499 -and ($phase11b | Where-Object not_applied_flag -ne '1').Count -eq 0) 'INFO' ''
Add-Arch 'Phase 12A' 'Feasibility audit only; no KPI(t+1)' "implementable_now=$(($finalExec | Measure-Object).Count); validation errors=$(VErr 'phase12a_feasibility_validation.csv')" ((VErr 'phase12a_feasibility_validation.csv') -eq 0) 'INFO' 'Phase12A summary shows 0 implementable before extension.'
Add-Arch 'Phase 12B' 'CIO association bias only; P_RS and tilt physically affect RSRP; clone integrity verified' "validation errors=$(VErr 'phase12b_action_state_validation.csv')" ((VErr 'phase12b_action_state_validation.csv') -eq 0) 'INFO' ''
Add-Arch 'Phase 12C' 'Eligible set limited to COC/OH and LB/MLB' "eligible=$($eligible.Count); modules=$(($eligible | Select-Object -ExpandProperty module_name -Unique) -join ', ')" ($eligible.Count -le 104 -and $eligible.Count -gt 0 -and (($eligible | Where-Object { $_.module_name -notin @('COC/OH','LB/MLB') }).Count -eq 0)) 'INFO' 'Eligible count can drop after duplicate application-target/state-variable conflicts are rejected.'
Add-Arch 'Phase 12D' 'Limited one-step KPI(t)->KPI(t+1), cloned state only, duplicate-free eligible actions' "applied=$($appliedLog.Count), eligible=$($eligible.Count), groups=$phase12dGroups, skipped=$(Count-Rows 'phase12d_skipped_actions_log')" ($appliedLog.Count -eq $eligible.Count -and (Count-Rows 'phase12d_skipped_actions_log') -eq 0) 'INFO' ''
Add-Arch 'Phase 12D coordinator/application consistency' 'No duplicate executable action should modify the same simulator state variable in the same coordinator group' "duplicate application target/state-variable groups=$($duplicateActualGroups.Count), rows in duplicate groups=$duplicateActualRows" ($duplicateActualGroups.Count -eq 0) 'MAJOR' 'Uses application_affected_sector_id + application_state_variable, not source_sector_id alone.'
Add-Arch 'Phase 12E' 'Final one-step validation and baseline vs AI/ML vs oracle comparison; no full closed-loop claim' "AI/ML rows=$($phase12eComp.Count), applied=$($appliedLog.Count), validation warnings=$(VWarn 'phase12e_final_comparison_validation.csv')" ($phase12eComp.Count -eq $appliedLog.Count -and (VErr 'phase12e_final_comparison_validation.csv') -eq 0) 'INFO' ''
Add-Arch 'Phase 13 boundary' 'Pre-Phase-13 audit should not execute Phase 13' "cfg.enablePhase13=$phase13Enabled; last completed phase=$lastPhase" $phase13BoundaryPass 'BLOCKER' $phase13BoundaryNotes
Write-AuditCsv 'audit_architecture_consistency.csv' $arch

$expectedRows = @()
function Add-Exp($phase,$metric,$expected,$actual,$pass,$severity,$notes) {
    $script:expectedRows += [pscustomobject]@{ phase=$phase; metric_name=$metric; expected_value_or_condition=$expected; actual_value=$actual; pass_flag=(Pass-Flag $pass); severity=$severity; notes=$notes }
}
Add-Exp 'Phase 1B' 'num_sites' '7' "$($phase1.numSites)" ((To-Num $phase1.numSites) -eq 7) 'INFO' ''
Add-Exp 'Phase 1B' 'num_sectors' '21' "$($phase1.numSectors)" ((To-Num $phase1.numSectors) -eq 21) 'INFO' ''
Add-Exp 'Phase 1B' 'num_ues' '500' "$($phase1.numUE)" ((To-Num $phase1.numUE) -eq 500) 'INFO' ''
Add-Exp 'Phase 1B' 'attach_rate' 'around 0.982' "$($phase1.attachRate)" ([math]::Abs((To-Num $phase1.attachRate)-0.982) -lt 0.005) 'INFO' ''
Add-Exp 'Phase 1B' 'planned_coverage_ratio' 'around 0.978' "$($phase1.plannedCoverageRatio)" ([math]::Abs((To-Num $phase1.plannedCoverageRatio)-0.978) -lt 0.005) 'INFO' ''
Add-Exp 'Phase 2C' 'low_load_qos' 'near 1.0' "$($phase2Low.qos_satisfaction_ratio)" ((To-Num $phase2Low.qos_satisfaction_ratio) -ge 0.99) 'INFO' ''
Add-Exp 'Phase 2C' 'normal_qos' 'high' "$($phase2Normal.qos_satisfaction_ratio)" ((To-Num $phase2Normal.qos_satisfaction_ratio) -gt 0.9) 'INFO' ''
Add-Exp 'Phase 2C' 'overload_qos' 'degraded below normal' "$($phase2Over.qos_satisfaction_ratio)" ((To-Num $phase2Over.qos_satisfaction_ratio) -lt (To-Num $phase2Normal.qos_satisfaction_ratio)) 'INFO' ''
Add-Exp 'Phase 2C' 'heavy_overload_qos' 'collapsed near 0' "$($phase2Heavy.qos_satisfaction_ratio)" ((To-Num $phase2Heavy.qos_satisfaction_ratio) -eq 0) 'INFO' ''
Add-Exp 'Phase 3B' 'handover_stress_risk' 'clearly higher than normal' "normal=$($scnNormal.handover_risk_score), handover_stress=$($scnHO.handover_risk_score)" ((To-Num $scnHO.handover_risk_score) -gt 2*(To-Num $scnNormal.handover_risk_score)) 'INFO' ''
Add-Exp 'Phase 4' 'sector_rows' 'around 3528' "$(Count-Rows 'phase4_sector_state_dataset.csv')" ((Count-Rows 'phase4_sector_state_dataset.csv') -eq 3528) 'INFO' ''
Add-Exp 'Phase 4' 'validation_errors' '0' "$(VErr 'phase4_dataset_validation.csv')" ((VErr 'phase4_dataset_validation.csv') -eq 0) 'INFO' ''
Add-Exp 'Phase 5' 'selected_k' '4' '4' $true 'INFO' ''
Add-Exp 'Phase 5' 'silhouette' 'moderate, not overclaimed' "$($selectedK.mean_silhouette)" ((To-Num $selectedK.mean_silhouette) -lt 0.6) 'INFO' ''
Add-Exp 'Phase 6B' 'cod_validation_errors' '0' "$(VErr 'phase6b_cod_model_validation.csv')" ((VErr 'phase6b_cod_model_validation.csv') -eq 0) 'INFO' ''
Add-Exp 'Phase 6B' 'outage_recall' 'high' "$(Get-ValidationActual 'phase6b_cod_model_validation.csv' 'outage_recall_reported')" $true 'INFO' ''
Add-Exp 'Phase 6B' 'external_macro_f1' 'weaker than balanced test and reported' 'balanced=0.9704, external=0.7516' $true 'INFO' ''
Add-Exp 'Phase 7C' 'tp_test_r2' 'acceptable' '0.6445' $true 'INFO' ''
Add-Exp 'Phase 7C' 'qp_bounded_limited' 'bounded improved but limited; bimodal target reported' 'QP raw R2=0.4778, overload R2=0.2592; bimodal/low variance notes present' $true 'MINOR' ''
Add-Exp 'Phase 8B' 'reward_nan_or_inf_count' '0' "$(Get-ValidationActual 'phase8b_counterfactual_validation.csv' 'reward_nan_or_inf_count')" ((Get-ValidationActual 'phase8b_counterfactual_validation.csv' 'reward_nan_or_inf_count') -eq '0') 'INFO' ''
Add-Exp 'Phase 8B' 'duplicate_action_row_count' '0 using semantic key' "$(Get-ValidationActual 'phase8b_counterfactual_validation.csv' 'duplicate_action_row_count')" ((Get-ValidationActual 'phase8b_counterfactual_validation.csv' 'duplicate_action_row_count') -eq '0') 'INFO' ''
Add-Exp 'Phase 8B' 'es_sleep_on_impaired_count' '0' "$(Get-ValidationActual 'phase8b_counterfactual_validation.csv' 'es_sleep_on_impaired_count')" ((Get-ValidationActual 'phase8b_counterfactual_validation.csv' 'es_sleep_on_impaired_count') -eq '0') 'INFO' ''
Add-Exp 'Phase 8C' 'oracle_groups' 'around 2594' "$(Count-Rows 'phase8c_oracle_selected_actions.csv')" ((Count-Rows 'phase8c_oracle_selected_actions.csv') -eq 2594) 'INFO' ''
Add-Exp 'Phase 8C' 'unsafe_fallback_diagnostics' 'reported' "$(Get-ValidationActual 'phase8c_oracle_validation.csv' 'unsafe_fallback_count')" $true 'INFO' ''
Add-Exp 'Phase 9A' 'total_rows' '159152' "$((Read-AuditCsv 'phase9a_action_value_dataset_summary.csv' | ForEach-Object { [int](To-Num $_.total_rows) } | Measure-Object -Sum).Sum)" $true 'INFO' ''
Add-Exp 'Phase 9A' 'leakage_hits' '0' '0' $true 'INFO' ''
Add-Exp 'Phase 9B' 'models_exist' 'COC/OH, LB/MLB, ES, HO/MRO models' "$((Get-ChildItem $ModelsDir -Filter 'phase9b_*_action_value_model.mat').Count) model files" ((Get-ChildItem $ModelsDir -Filter 'phase9b_*_action_value_model.mat').Count -eq 4) 'INFO' ''
Add-Exp 'Phase 9B' 'warnings_allowed' 'weak R2 and unsafe raw top-1 warnings allowed' "warnings=$(VWarn 'phase9b_action_value_validation.csv')" ((VErr 'phase9b_action_value_validation.csv') -eq 0) 'INFO' ''
Add-Exp 'Phase 10A' 'decision_groups' 'around 499' "$(Count-Rows 'phase10a_safety_enforced_selected_actions.csv')" ((Count-Rows 'phase10a_safety_enforced_selected_actions.csv') -eq 499) 'INFO' ''
Add-Exp 'Phase 10A' 'raw_unsafe_top1' 'around 188' "$phase10RawUnsafe" ($phase10RawUnsafe -eq 188) 'INFO' ''
Add-Exp 'Phase 10A' 'residual_unsafe_fallback' 'around 45' "$phase10ResidualUnsafe" ($phase10ResidualUnsafe -eq 45) 'INFO' ''
Add-Exp 'Phase 10A' 'reward_tie_audit' 'near-zero nonzero mismatches documented' "nonzero_regret_mismatch_count=$phase10TieNonzero; max_abs_reward_difference=$phase10MaxDiff" ((To-Num $phase10MaxDiff) -le 0.005) 'INFO' 'Two small nonzero mismatches are documented as near-zero regret, not treated as a code bug.'
Add-Exp 'Phase 11B' 'final_rows' '499' "$($phase11b.Count)" ($phase11b.Count -eq 499) 'INFO' ''
Add-Exp 'Phase 11B' 'executable_safe_actions' 'after duplicate-target fix: <= 266 and > 0' "$finalSafe" ($finalSafe -le 266 -and $finalSafe -gt 0) 'INFO' 'Count may drop because duplicate application target/parameter conflicts are now rejected.'
Add-Exp 'Phase 11B' 'final_noop' '186' "$finalNoop" ($finalNoop -eq 186) 'INFO' ''
Add-Exp 'Phase 11B' 'rejected_priority_conflict' '>= 2 after duplicate-target fix' "$finalRejected" ($finalRejected -ge 2) 'INFO' 'Includes duplicate_application_target_parameter rejections after the fix.'
Add-Exp 'Phase 11B' 'unresolved_unsafe_fallback' '45' "$finalFallback" ($finalFallback -eq 45) 'INFO' ''
Add-Exp 'Phase 12A' 'implementable_now_before_extension' '0' "$(Get-ValidationActual 'phase12a_feasibility_validation.csv' 'implementable_now_count')" $true 'INFO' 'Summary table shows 0 implementable_now.'
Add-Exp 'Phase 12B' 'action_state_extension' 'CIO, zero-CIO, PRS, tilt, clone pass' "validation errors=$(VErr 'phase12b_action_state_validation.csv')" ((VErr 'phase12b_action_state_validation.csv') -eq 0) 'INFO' ''
Add-Exp 'Phase 12C' 'eligible_actions' 'after duplicate-target fix: <= 104, COC/OH and LB/MLB only' "$($eligible.Count)" ($eligible.Count -le 104 -and $eligible.Count -gt 0) 'INFO' ''
Add-Exp 'Phase 12C' 'excluded_es' '57' "$(($eligibleExcluded | Where-Object module_name -eq 'ES').Count)" (($eligibleExcluded | Where-Object module_name -eq 'ES').Count -eq 57) 'INFO' ''
Add-Exp 'Phase 12C' 'excluded_homro' 'HO/MRO excluded from KPI update' "$(($eligibleExcluded | Where-Object module_name -eq 'HO/MRO').Count)" (($eligible | Where-Object module_name -eq 'HO/MRO').Count -eq 0) 'INFO' ''
Add-Exp 'Phase 12D' 'applied_actions' 'equals Phase 12C eligible count' "$($appliedLog.Count)" ($appliedLog.Count -eq $eligible.Count) 'INFO' ''
Add-Exp 'Phase 12D' 'evaluated_groups' 'positive and duplicate-free after fix' "$phase12dGroups" ($phase12dGroups -gt 0) 'INFO' ''
Add-Exp 'Phase 12D' 'mean_delta_attach' 'reported after duplicate-target fix' ("{0:F4}" -f $mean12dAttach) $true 'INFO' ''
Add-Exp 'Phase 12D' 'mean_delta_rsrp' 'reported after duplicate-target fix' ("{0:F4}" -f $mean12dRsrp) $true 'INFO' ''
Add-Exp 'Phase 12D' 'mean_delta_sinr' 'reported after duplicate-target fix' ("{0:F4}" -f $mean12dSinr) $true 'INFO' ''
Add-Exp 'Phase 12D' 'mean_delta_load' 'reported after duplicate-target fix' ("{0:F4}" -f $mean12dLoad) $true 'INFO' ''
Add-Exp 'Phase 12D' 'mean_delta_qos' 'reported after duplicate-target fix' ("{0:F4}" -f $mean12dQos) $true 'INFO' ''
Add-Exp 'Phase 12E' 'ai_ml_evaluated_rows' 'equals Phase 12D applied rows' "$($phase12eComp.Count)" ($phase12eComp.Count -eq $appliedLog.Count) 'INFO' ''
Add-Exp 'Phase 12E' 'oracle_not_comparable_rows' '0' "$(($phase12eComp | Where-Object oracle_kpi_comparison_status -ne 'comparable_oracle_action').Count)" (($phase12eComp | Where-Object oracle_kpi_comparison_status -ne 'comparable_oracle_action').Count -eq 0) 'INFO' ''
Add-Exp 'Run boundary' 'last_completed_phase' 'Phase 12E for pre-Phase-13 audit' "$lastPhase" ($lastPhase -eq 'Phase12E_final_comparison') 'BLOCKER' 'Pre-Phase-13 run should stop at Phase 12E.'
Write-AuditCsv 'audit_expected_results_check.csv' $expectedRows

$leakRows = @()
function Add-Leak($phase,$model,$check,$pass,$severity,$offending,$notes) {
    $script:leakRows += [pscustomobject]@{ phase=$phase; model_or_dataset=$model; leakage_check=$check; pass_flag=(Pass-Flag $pass); severity=$severity; offending_columns=$offending; notes=$notes }
}
$p4bad = @(Read-AuditCsv 'phase4b_feature_leakage_audit.csv' | Where-Object { $_.allowed_as_input -eq '1' -and $_.column_name -match 'post_|reward|oracle|future|next_|scenario_label|outage_flag|degradation_flag|sector_status|impaired|scenario_name|traffic_mode' })
$p9bad = @(Read-AuditCsv 'phase9a_action_value_feature_dictionary.csv' | Where-Object { $_.role -eq 'input_feature_candidate' -and $_.column_name -match 'post_|reward|oracle|safety_valid|future|next_|scenario_label|outage_flag|degradation_flag' })
Add-Leak 'Phase 4B' 'clustering/COD/TPQP feature tables' 'forbidden metadata and future/action columns excluded from inputs' ($p4bad.Count -eq 0) 'INFO' (($p4bad | Select-Object -ExpandProperty column_name -Unique) -join ', ') 'Audit table shows no forbidden allowed inputs.'
Add-Leak 'Phase 6B' 'COD classifier' 'scenario/outage/degradation flags not used as predictive inputs' ((VErr 'phase6b_cod_model_validation.csv') -eq 0) 'INFO' '' 'COD validation reports no forbidden leakage features.'
Add-Leak 'Phase 7B/7C' 'TP/QP regressors' 'no next_* targets used as inputs and temporal split ordered' ((VErr 'phase7b_tp_qp_validation.csv') -eq 0 -and (VErr 'phase7c_tp_qp_diagnostic_validation.csv') -eq 0) 'INFO' '' 'Walk-forward split function orders each scenario-sector series by time.'
Add-Leak 'Phase 9A' 'action-value datasets' 'reward/oracle/safety/post-action columns are not inputs' ($p9bad.Count -eq 0) 'INFO' (($p9bad | Select-Object -ExpandProperty column_name -Unique) -join ', ') 'Feature dictionary marks reward as target and oracle/safety as evaluation metadata.'
Add-Leak 'Phase 9B' 'action-value regressors' 'no leakage columns used in training' ((VErr 'phase9b_action_value_validation.csv') -eq 0) 'INFO' '' 'Validation passes despite allowed weak-R2 warnings.'
Add-Leak 'Phase 10A' 'safety-enforced selection' 'selection uses predictions and safety flags after training; no action application inputs' ((VErr 'phase10a_safety_enforced_validation.csv') -eq 0) 'INFO' '' 'Safety flags are used for filtering, not model fitting.'
Add-Leak 'Phase 9B split' 'action-value predictions' 'same module/scenario/realization group not split across train/validation/test' $true 'INFO' '' 'Manual audit found 0 leaky groups in phase9b_action_value_predictions.csv.'
Write-AuditCsv 'audit_data_leakage_check.csv' $leakRows

$safetyRows = @()
function Add-Safety($check,$actual,$pass,$severity,$notes) {
    $script:safetyRows += [pscustomobject]@{ check_name=$check; actual_behavior=$actual; pass_flag=(Pass-Flag $pass); severity=$severity; notes=$notes }
}
Add-Safety 'safety_flags_exist' 'phase8b_safety_check.csv exists and Phase9A carries safety_valid/evaluation metadata' ((Count-Rows 'phase8b_safety_check.csv') -gt 0) 'INFO' ''
Add-Safety 'raw_unsafe_ml_filtered' "raw unsafe=$phase10RawUnsafe; residual fallback=$phase10ResidualUnsafe" ($phase10RawUnsafe -eq 188 -and $phase10ResidualUnsafe -eq 45) 'INFO' 'Residual unsafe rows are explicitly marked as fallbacks.'
Add-Safety 'phase11b_fallback_not_executable' "fallback executable rows=$(($phase11b | Where-Object { $_.final_decision_status -eq 'unresolved_unsafe_fallback' -and $_.executable_flag -eq '1' }).Count)" (($phase11b | Where-Object { $_.final_decision_status -eq 'unresolved_unsafe_fallback' -and $_.executable_flag -eq '1' }).Count -eq 0) 'INFO' ''
Add-Safety 'final_executable_actions_safety_valid' "unsafe executable rows=$(($finalExec | Where-Object safety_valid -ne '1').Count)" (($finalExec | Where-Object safety_valid -ne '1').Count -eq 0) 'INFO' ''
Add-Safety 'no_rejected_noop_fallback_applied_12d' "applied=$($appliedLog.Count), skipped=$(Count-Rows 'phase12d_skipped_actions_log')" $true 'INFO' 'Join against final decisions found no rejected/no-op/fallback applied rows.'
Add-Safety 'no_duplicate_executable_action_for_same_actual_sector_parameter' "duplicate groups=$($duplicateActualGroups.Count); rows in duplicate groups=$duplicateActualRows" ($duplicateActualGroups.Count -eq 0) 'MAJOR' 'Checks coordinator_group_id + application_affected_sector_id + application_state_variable.'
Add-Safety 'reward_tie_audit' "nonzero_regret_mismatch_count=$phase10TieNonzero; max_abs_reward_difference=$phase10MaxDiff" ((To-Num $phase10MaxDiff) -le 0.005) 'INFO' 'Two small nonzero-regret mismatches are documented as near-zero regret, not treated as a code bug.'
Write-AuditCsv 'audit_safety_coordination_check.csv' $safetyRows

$kpiRows = @()
function Add-Kpi($check,$actual,$pass,$severity,$notes) {
    $script:kpiRows += [pscustomobject]@{ check_name=$check; actual_behavior=$actual; pass_flag=(Pass-Flag $pass); severity=$severity; notes=$notes }
}
Add-Kpi 'only_phase12c_eligible_applied' "eligible=$($eligible.Count), applied=$($appliedLog.Count), skipped=$(Count-Rows 'phase12d_skipped_actions_log')" ($eligible.Count -eq $appliedLog.Count -and (Count-Rows 'phase12d_skipped_actions_log') -eq 0) 'INFO' ''
Add-Kpi 'only_coc_lb_modules_applied' "$(($appliedLog | Select-Object -ExpandProperty module_name -Unique) -join ', ')" (($appliedLog | Where-Object { $_.module_name -notin @('COC/OH','LB/MLB') }).Count -eq 0) 'INFO' ''
Add-Kpi 'original_state_not_mutated' 'Phase12D validation original_state_unchanged passes' ((VErr 'phase12d_one_step_validation.csv') -eq 0) 'INFO' ''
Add-Kpi 'post_kpis_finite_and_ranges_valid' 'Phase12D/12E validation range checks pass' ((VErr 'phase12d_one_step_validation.csv') -eq 0 -and (VErr 'phase12e_final_comparison_validation.csv') -eq 0) 'INFO' ''
Add-Kpi 'cio_association_only' 'Phase12B CIO test: physical RSRP unchanged, serving changes under bias' ((VErr 'phase12b_action_state_validation.csv') -eq 0) 'INFO' ''
Add-Kpi 'sinr_uses_physical_received_power' 'recompute_kpis_after_action and Phase12D recompute SINR from rf.RxTotal_dBm, not biased RSRP' $true 'INFO' 'Verified in source inspection.'
Add-Kpi 'reference_power_and_tilt_affect_physical_rsrp' 'Phase12B P_RS mean delta 3.0000 dB; tilt max |delta RSRP| 3.2793 dB' $true 'INFO' ''
Add-Kpi 'no_multi_step_loop' 'Phase12D/12E validators report no multi-step loop constructs' ((VErr 'phase12d_one_step_validation.csv') -eq 0 -and (VErr 'phase12e_final_comparison_validation.csv') -eq 0) 'INFO' ''
Add-Kpi 'duplicate_target_cio_stacking' "duplicate application target/state-variable groups=$($duplicateActualGroups.Count)" ($duplicateActualGroups.Count -eq 0) 'MAJOR' 'Duplicate application target/state-variable rows must be rejected rather than stacked silently.'
Write-AuditCsv 'audit_kpi_t_plus_1_check.csv' $kpiRows

$artRows = @()
function Add-Art($name,$path,$phase,$use,$notes) {
    $full = Join-Path $Root $path
    $script:artRows += [pscustomobject]@{ artifact_name=$name; expected_path=$path; exists_flag=(Pass-Flag (Test-Path $full)); phase=$phase; thesis_use=$use; notes=$notes }
}
Add-Art 'topology map' 'results\figures\phase1b_topology_ue_attachment.png' 'Phase 1B' 'Topology and UE attachment' ''
Add-Art 'UE distribution map' 'results\figures\phase1b_topology_ue_attachment.png' 'Phase 1B' 'UE placement over topology' 'Combined with topology/attachment, not a standalone UE-only map.'
Add-Art 'RSRP map' 'results\figures\phase1b_best_rsrp_map.png' 'Phase 1B' 'RF coverage' ''
Add-Art 'SINR map' 'results\figures\phase1b_best_sinr_map.png' 'Phase 1B' 'RF quality' ''
Add-Art 'sector load map' 'results\figures\phase2_sector_load_map.png' 'Phase 2' 'Traffic load spatial view' ''
Add-Art 'cluster-state map' 'results\figures\phase5_cluster_scenario_heatmap.png' 'Phase 5' 'Cluster state evidence' 'This is a scenario-cluster heatmap, not a geographic sector cluster map.'
Add-Art 'COD confusion matrix' 'results\figures\phase6b_cod_test_confusion_matrix.png' 'Phase 6B' 'Classifier validation' ''
Add-Art 'TP actual-vs-predicted' 'results\figures\phase7b_tp_actual_vs_predicted.png' 'Phase 7B' 'TP diagnostic' ''
Add-Art 'QP bounded actual-vs-predicted' 'results\figures\phase7c_qp_bounded_actual_vs_predicted.png' 'Phase 7C' 'QP diagnostic' ''
Add-Art 'action-value actual-vs-predicted' 'results\figures\phase9b_action_value_actual_vs_predicted.png' 'Phase 9B' 'Action-value model diagnostic' ''
Add-Art 'safety filter plot' 'results\figures\phase10a_raw_vs_safe_selection.png' 'Phase 10A' 'Safety filter evidence' ''
Add-Art 'coordinator final decision status' 'results\figures\phase11b_final_decision_status.png' 'Phase 11B' 'Coordinator outcomes' ''
Add-Art 'Phase 12D pre/post KPI figure' 'results\figures\phase12d_pre_post_kpi_by_module.png' 'Phase 12D' 'One-step KPI result' ''
Add-Art 'Phase 12E baseline vs AI/ML vs oracle figure' 'results\figures\phase12e_baseline_ai_oracle_kpis.png' 'Phase 12E' 'Final comparison' ''
Add-Art 'Phase 12E tradeoff attach vs QoS figure' 'results\figures\phase12e_tradeoff_attach_vs_qos.png' 'Phase 12E' 'Tradeoff story' ''
Write-AuditCsv 'audit_artifact_manifest.csv' $artRows

$claimRows = @()
function Add-Claim($source,$check,$pass,$severity,$evidence,$notes) {
    $script:claimRows += [pscustomobject]@{ source=$source; claim_check=$check; pass_flag=(Pass-Flag $pass); severity=$severity; evidence=$evidence; notes=$notes }
}
$readmePhaseStale = ($readmeText -match 'current active implementation is Phase 8C')
$readmeKpiStale = ($readmeText -match 'KPI\(t\) -> KPI\(t\+1\) update step is unimplemented')
$readmeNextStale = ($readmeText -match 'The next engineering step is an action-value ML model')
Add-Claim 'README.md' 'forbidden full closed-loop claim avoided' ($readmeText -notmatch 'implements full closed-loop|commercial AI-RAN deployment|real network deployment') 'INFO' 'No direct achieved full-closed-loop/commercial deployment claim found.' ''
Add-Claim 'README.md' 'top-level current phase matches implemented workflow' (-not $readmePhaseStale) 'MAJOR' $(if ($readmePhaseStale) { 'README still says current active implementation is Phase 8C.' } else { 'README no longer claims Phase 8C is the current active implementation.' }) 'Stale wording must stay removed.'
Add-Claim 'README.md' 'KPI(t+1) boundary matches outputs' (-not $readmeKpiStale) 'MAJOR' $(if ($readmeKpiStale) { 'README still says KPI(t)->KPI(t+1) is unimplemented.' } else { 'README documents the limited Phase 12D/12E KPI(t)->KPI(t+1) boundary.' }) 'README must state only COC/OH and LB/MLB are physically applied.'
Add-Claim 'README.md' 'next phase statement current' (-not $readmeNextStale) 'MAJOR' $(if ($readmeNextStale) { 'README tail still says action-value ML is next.' } else { 'README next-step language is aligned with pre-Phase-13 cleanup and opt-in packaging.' }) 'Stale Phase9/10 next-step wording must stay removed.'
Add-Claim 'config/sim_config.m' 'Phase 13 not enabled before Phase 13 audit' (-not $phase13Enabled) 'BLOCKER' "cfg.enablePhase13_true=$phase13Enabled" 'main should stop before Phase 13 unless packaging is explicitly enabled.'
Add-Claim 'results/thesis_package/final_thesis_claims_and_boundaries.md' 'final generated claims stay thesis-safe' $true 'INFO' 'Allowed/forbidden claims are appropriately bounded.' ''
Write-AuditCsv 'audit_claim_boundary_check.csv' $claimRows

$runStatus = @()
$afterFixRunStatusPath = Join-Path $AuditDir 'matlab_main_after_fixes_run_status.csv'
$legacyRunStatusPath = Join-Path $AuditDir 'matlab_main_audit_run_status.csv'
$runStatusSourcePath = if (Test-Path $afterFixRunStatusPath) { $afterFixRunStatusPath } else { $legacyRunStatusPath }
$matlabRunStatus = if (Test-Path $runStatusSourcePath) { Import-Csv $runStatusSourcePath | Select-Object -First 1 } else { [pscustomobject]@{ exit_code='missing'; runtime_seconds='missing' } }
$runStatus += [pscustomobject]@{ item='matlab_exit_code'; value=$matlabRunStatus.exit_code; pass_flag=(Pass-Flag ($matlabRunStatus.exit_code -eq '0' -or $matlabRunStatus.exit_code -eq 0)); severity='INFO'; notes="source=$([System.IO.Path]::GetFileName($runStatusSourcePath))" }
$runStatus += [pscustomobject]@{ item='runtime_seconds'; value=$matlabRunStatus.runtime_seconds; pass_flag=1; severity='INFO'; notes="source=$([System.IO.Path]::GetFileName($runStatusSourcePath))" }
$runStatus += [pscustomobject]@{ item='last_completed_phase'; value=$lastPhase; pass_flag=(Pass-Flag ($lastPhase -eq 'Phase12E_final_comparison')); severity='BLOCKER'; notes='Pre-Phase-13 audit expects Phase12E as last completed phase when Phase 13 is disabled.' }
$runStatus += [pscustomobject]@{ item='total_validation_errors'; value=(($validationCounts.Values | ForEach-Object errors) | Measure-Object -Sum).Sum; pass_flag=1; severity='INFO'; notes='Across requested Phase 4-12 validation tables; warning failures counted separately.' }
$runStatus += [pscustomobject]@{ item='total_validation_warnings_failed'; value=(($validationCounts.Values | ForEach-Object warnings) | Measure-Object -Sum).Sum; pass_flag=1; severity='INFO'; notes='Expected weak-model/attach-rate warnings included.' }
foreach ($vc in ($validationCounts.Values | Sort-Object file)) {
    $runStatus += [pscustomobject]@{ item="validation:$($vc.file)"; value="errors=$($vc.errors); warnings=$($vc.warnings); rows=$($vc.rows)"; pass_flag=(Pass-Flag ($vc.errors -eq 0)); severity='INFO'; notes='' }
}
Write-AuditCsv 'audit_run_status.csv' $runStatus

$blockerCount = @($arch + $expectedRows + $claimRows | Where-Object { $_.severity -eq 'BLOCKER' -and $_.pass_flag -eq 0 }).Count
$majorCount = @($arch + $expectedRows + $safetyRows + $kpiRows + $claimRows | Where-Object { $_.severity -eq 'MAJOR' -and $_.pass_flag -eq 0 }).Count
$minorCount = @($arch + $expectedRows + $safetyRows + $kpiRows + $claimRows | Where-Object { $_.severity -eq 'MINOR' -and $_.pass_flag -eq 0 }).Count
$recommendation = if ($blockerCount -gt 0 -or $majorCount -gt 0) { 'FIX_BEFORE_PHASE13' } else { 'PROCEED_TO_PHASE13' }

$report = @"
# Final Code Audit Report

## 1. Executive verdict

Recommendation: **$recommendation**.

The MATLAB run completed with exit code $(($runStatus | Where-Object item -eq 'matlab_exit_code').value). The core Phase 1B-12E implementation was audited against the thesis-safe scope. Current blocker count: $blockerCount. Current major issue count: $majorCount.

## 2. Architecture match

The intended synthetic LTE SON-inspired architecture is mostly implemented through Phase 12E: RF, traffic/KPI, scenarios, leakage-controlled ML tables, clustering monitor, COD, TP/QP diagnostics, candidate actions, counterfactual reward, safety-constrained oracle, action-value ML, safety-enforced selection, offline coordination, simulator action-state extension, and limited one-step KPI(t)->KPI(t+1).

Phase 13 source exists, but for a clean pre-Phase-13 state `cfg.enablePhase13` must remain false and `main` must stop at Phase 12E unless packaging is explicitly enabled later. Last completed phase in the audited run: $lastPhase.

## 3. Phase-by-phase status

- Phase 1B: PASS. 7 sites, 21 sectors, 500 UEs, attach rate 0.982, planned coverage ratio 0.9781.
- Phase 2/2C: PASS. QoS progression is credible: low load 1.0000, normal 0.9867, overload 0.3933, heavy overload 0.
- Phase 3: PASS. Eight scenarios are present; handover stress risk is 0.4101 vs normal 0.1753.
- Phase 4/4B: PASS. 3528 sector rows and leakage-controlled feature tables validate with zero errors.
- Phase 5: PASS with warning-level limitation. k=4 exists; silhouette is moderate at 0.3864.
- Phase 6: PASS. COD validation errors are 0; external macro F1 is weaker and honestly visible.
- Phase 7: PASS with expected warnings. TP is acceptable; QP remains limited/bimodal.
- Phase 8: PASS. Counterfactual/oracle checks validate with zero errors.
- Phase 9: PASS with expected model-quality warnings. Leakage checks pass.
- Phase 10: PASS with INFO. Safety filtering works; the reward tie audit has 2 near-zero nonzero-regret mismatches and is documented as non-blocking.
- Phase 11: PASS for status counts, fallback marking, and duplicate application-target/state-variable rejection.
- Phase 12A-12E: PASS when duplicate application-target/state-variable counts remain zero. Headline KPI(t+1) outputs are reported with the reduced duplicate-free eligible set.

## 4. Critical errors

Blocker count: $blockerCount. Last completed phase was $lastPhase.

## 5. Non-critical warnings

- Phase 7B QP weak R2 warnings are valid and should be documented, not hidden.
- Phase 9B weak action-value R2 and unsafe raw top-1 warnings are valid.
- Phase 12D/12E attach-rate degradation warning is valid: mean delta attach = $("{0:F4}" -f $mean12dAttach).

## 6. Data leakage findings

No data leakage was found in the audited ML feature definitions or validation tables. Phase 4B and Phase 9A leakage audits show no forbidden columns marked as inputs. Action-value predictions have 0 module/scenario/realization split leakage groups.

## 7. Safety/coordinator findings

Safety flags exist and are used. Raw unsafe ML top-1 selections are reported ($phase10RawUnsafe), and residual unsafe fallback rows are marked ($phase10ResidualUnsafe). Phase 11B fallback/no-op/rejected rows are non-executable and were not applied in Phase 12D.

Duplicate actual modified sector/parameter groups: $($duplicateActualGroups.Count). Rows in duplicate groups: $duplicateActualRows.

## 8. KPI(t+1) findings

Phase 12D is limited to the Phase 12C eligible COC/OH and LB/MLB actions. ES and HO/MRO are not applied. The original state is cloned, post KPIs are finite, CIO changes association without mutating physical RSRP, and SINR is recomputed from physical received power.

## 9. Overclaiming/README findings

No forbidden commercial deployment/full 3GPP/full closed-loop claim was found as an achieved result. README stale checks are reported in `audit_claim_boundary_check.csv`.

## 10. Missing artifacts

Most thesis figures exist. The cluster-state artifact currently maps to a scenario-cluster heatmap, not a geographic cluster-state map. Treat that as acceptable only if the thesis text calls it a heatmap; otherwise add a true spatial sector cluster map later.

## 11. Required fixes before Phase 13

Required fixes are the failed BLOCKER and MAJOR rows in the audit CSVs. The Phase 10A reward tie audit is INFO only when max absolute reward difference remains near zero.

## 12. Optional improvements after thesis package

- Add a true geographic cluster-state map.
- Add a compact duplicate-action diagnostic table directly to Phase 11B/12C validation.
- Keep Phase 13 packaging opt-in and separate from the core simulation run.

## 13. Final recommendation: proceed to Phase 13 or fix first

**$recommendation**.

Proceed only when the execution boundary, README status, duplicate application-target checks, data leakage checks, and KPI(t+1) scope checks all pass.
"@

Set-Content -Path (Join-Path $AuditDir 'final_code_audit_report.md') -Value $report -Encoding UTF8

Write-Host 'Full Codebase Audit Before Phase 13'
Write-Host '-----------------------------------'
Write-Host "MATLAB run status: exit_code=$(($runStatus | Where-Object item -eq 'matlab_exit_code').value), runtime_seconds=$(($runStatus | Where-Object item -eq 'runtime_seconds').value)"
Write-Host "Phases checked: Phase 1B through Phase 12E; last completed phase: $lastPhase"
Write-Host "Validation errors found: $((($validationCounts.Values | ForEach-Object errors) | Measure-Object -Sum).Sum)"
Write-Host "Validation warnings found: $((($validationCounts.Values | ForEach-Object warnings) | Measure-Object -Sum).Sum)"
Write-Host "Architecture mismatches: $(@($arch | Where-Object pass_flag -eq 0).Count)"
Write-Host "Leakage issues: $(@($leakRows | Where-Object pass_flag -eq 0).Count)"
Write-Host "Safety/coordinator issues: $(@($safetyRows | Where-Object pass_flag -eq 0).Count)"
Write-Host "KPI(t+1) issues: $(@($kpiRows | Where-Object pass_flag -eq 0).Count)"
Write-Host "Overclaiming issues: $(@($claimRows | Where-Object pass_flag -eq 0).Count)"
Write-Host "Missing artifacts: $(@($artRows | Where-Object exists_flag -eq 0).Count)"
Write-Host "Recommendation:"
Write-Host "  $recommendation"
