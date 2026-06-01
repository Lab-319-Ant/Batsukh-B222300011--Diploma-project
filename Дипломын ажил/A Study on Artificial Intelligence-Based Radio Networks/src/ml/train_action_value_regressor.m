function model = train_action_value_regressor(trainTable, inputFeatures, targetName, cfg)
%TRAIN_ACTION_VALUE_REGRESSOR LSBoost ensemble for reward regression.
%
% Tries fitrensemble with LSBoost first (preferred). Falls back to
% TreeBagger regression if fitrensemble is unavailable in the current
% MATLAB toolbox set.
%
% Returns a struct with fields:
%   model           - the underlying regressor (CompactRegressionEnsemble or TreeBagger)
%   modelType       - 'LSBoost' or 'TreeBagger'
%   inputFeatures   - cell array of feature names used
%   featureImportance - numeric column, length = numel(inputFeatures)

if nargin < 4 || isempty(cfg)
    numLearningCycles = 200;
    learnRate = 0.05;
    maxNumSplits = 32;
else
    numLearningCycles = get_or_default(cfg, 'phase9bNumLearningCycles', 200);
    learnRate = get_or_default(cfg, 'phase9bLearnRate', 0.05);
    maxNumSplits = get_or_default(cfg, 'phase9bMaxNumSplits', 32);
end

X = trainTable(:, inputFeatures);
y = trainTable.(targetName);

model = struct();
model.inputFeatures = inputFeatures;

if exist('fitrensemble', 'file') == 2
    template = templateTree('MaxNumSplits', maxNumSplits, 'Surrogate', 'off');
    ens = fitrensemble(X, y, ...
        'Method', 'LSBoost', ...
        'NumLearningCycles', numLearningCycles, ...
        'LearnRate', learnRate, ...
        'Learners', template);
    model.model = ens;
    model.modelType = 'LSBoost';
    try
        model.featureImportance = predictorImportance(ens)';
    catch
        model.featureImportance = zeros(numel(inputFeatures), 1);
    end
elseif exist('TreeBagger', 'class') == 8
    Xmat = table2array(X);
    tb = TreeBagger(numLearningCycles, Xmat, y, 'Method', 'regression', ...
        'OOBPrediction', 'on', 'OOBPredictorImportance', 'on', ...
        'MaxNumSplits', maxNumSplits);
    model.model = tb;
    model.modelType = 'TreeBagger';
    try
        model.featureImportance = tb.OOBPermutedPredictorDeltaError(:);
    catch
        model.featureImportance = zeros(numel(inputFeatures), 1);
    end
else
    error('No regression ensemble learner available (fitrensemble or TreeBagger).');
end
end

function v = get_or_default(cfg, name, default)
if isfield(cfg, name)
    v = cfg.(name);
else
    v = default;
end
end
