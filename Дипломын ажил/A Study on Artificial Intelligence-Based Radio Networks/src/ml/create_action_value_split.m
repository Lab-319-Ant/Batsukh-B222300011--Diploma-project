function splitLabels = create_action_value_split(T, trainFrac, valFrac, rngSeed)
%CREATE_ACTION_VALUE_SPLIT Stratified (scenario, realization) train/test split.
%
% Returns a cell column with 'train' / 'test'.
% Splits at the (scenario_name, realization_id) group granularity so that
% no (scenario, realization) appears in more than one split, preventing
% row-level leakage between train and test.
%
% Within each scenario the realizations are shuffled (seeded for
% reproducibility) and split into train/test using the requested fraction.
% Validation is intentionally disabled for the thesis-facing action-value
% comparison so the evaluation is a simpler train/test-only protocol.

if nargin < 2 || isempty(trainFrac)
    trainFrac = 0.80;
end
if nargin < 3 || isempty(valFrac)
    valFrac = 0.0;
end
if nargin < 4 || isempty(rngSeed)
    rngSeed = 9001;
end
if valFrac ~= 0
    warning('create_action_value_split:ValidationDisabled', ...
        'Validation split is disabled; ignoring valFrac=%.3f.', valFrac);
end

n = height(T);
splitLabels = repmat({'test'}, n, 1);

scenarios = string(T.scenario_name);
realizations = T.realization_id;
uniqueScenarios = unique(scenarios);

rngState = rng();
cleanup = onCleanup(@() rng(rngState));
rng(rngSeed);

for s = 1:numel(uniqueScenarios)
    scn = uniqueScenarios(s);
    mask = scenarios == scn;
    if ~any(mask)
        continue;
    end
    realIds = unique(realizations(mask));
    nReal = numel(realIds);
    realIds = realIds(randperm(nReal));

    nTrain = max(floor(trainFrac * nReal), 1);
    if nReal >= 2 && nTrain >= nReal
        nTrain = nReal - 1;
    end

    trainRealIds = realIds(1:nTrain);
    testRealIds = realIds(nTrain + 1 : end);

    splitLabels(mask & ismember(realizations, trainRealIds)) = {'train'};
    splitLabels(mask & ismember(realizations, testRealIds)) = {'test'};
end

% Mirror unused parameters into the workspace to silence linters.
trainFrac = trainFrac; %#ok<NASGU,ASGSL>
valFrac = valFrac; %#ok<NASGU,ASGSL>
end
