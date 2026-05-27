function [splitPlan, splitSummary] = create_walk_forward_split(featureTable)
%CREATE_WALK_FORWARD_SPLIT Split each scenario-sector sequence by time.
%
% The split is ordered within each scenario-sector group:
% earliest 70% train, next 15% validation, final 15% test.

split = strings(height(featureTable), 1);
scenarioNames = unique(featureTable.scenario_name, 'stable');

for s = 1:numel(scenarioNames)
    scenarioName = scenarioNames{s};
    scenarioIdx = strcmp(featureTable.scenario_name, scenarioName);
    sectorIds = unique(featureTable.sector_id(scenarioIdx));
    for sec = sectorIds(:)'
        idx = find(scenarioIdx & featureTable.sector_id == sec);
        [~, order] = sort(featureTable.time_step(idx));
        idx = idx(order);
        n = numel(idx);
        nTrain = floor(0.70 * n);
        nValidation = floor(0.15 * n);
        trainIdx = idx(1:nTrain);
        validationIdx = idx(nTrain + 1:nTrain + nValidation);
        testIdx = idx(nTrain + nValidation + 1:end);
        split(trainIdx) = "train";
        split(validationIdx) = "validation";
        split(testIdx) = "test";
    end
end

splitPlan = table(featureTable.temporal_sample_id, featureTable.scenario_name, ...
    featureTable.site_id, featureTable.sector_id, featureTable.time_step, cellstr(split), ...
    'VariableNames', {'temporal_sample_id','scenario_name','site_id','sector_id','time_step','split'});

splitSummary = summarize_split(splitPlan);
end

function splitSummary = summarize_split(splitPlan)
scenarioNames = unique(splitPlan.scenario_name, 'stable');
splits = {'train','validation','test'};
rows = {};
for s = 1:numel(scenarioNames)
    for i = 1:numel(splits)
        idx = strcmp(splitPlan.scenario_name, scenarioNames{s}) & strcmp(splitPlan.split, splits{i});
        rows(end+1, :) = {scenarioNames{s}, splits{i}, sum(idx)}; %#ok<AGROW>
    end
end
for i = 1:numel(splits)
    idx = strcmp(splitPlan.split, splits{i});
    rows(end+1, :) = {'ALL', splits{i}, sum(idx)}; %#ok<AGROW>
end
splitSummary = cell2table(rows, 'VariableNames', {'scenario_name','split','row_count'});
end
