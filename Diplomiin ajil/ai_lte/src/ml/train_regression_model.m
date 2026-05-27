function modelInfo = train_regression_model(cfg, trainTable, inputFeatures, targetName, modelName)
%TRAIN_REGRESSION_MODEL Train an ensemble regression model for TP/QP.

XTrain = table2array(trainTable(:, inputFeatures));
yTrain = trainTable.(targetName);

rng(cfg.seed + 7100);
if exist('fitrensemble', 'file') == 2
    treeTemplate = templateTree('MinLeafSize', 5);
    model = fitrensemble(XTrain, yTrain, ...
        'Method', 'LSBoost', ...
        'NumLearningCycles', cfg.phase7bNumLearningCycles, ...
        'Learners', treeTemplate);
    algorithm = 'fitrensemble_LSBoost';
    try
        importance = predictorImportance(model)';
    catch
        importance = nan(numel(inputFeatures), 1);
    end
elseif exist('TreeBagger', 'file') == 2
    model = TreeBagger(cfg.phase7bNumLearningCycles, XTrain, yTrain, ...
        'Method', 'regression', ...
        'OOBPrediction', 'on', ...
        'OOBPredictorImportance', 'on', ...
        'MinLeafSize', 5);
    algorithm = 'TreeBagger_regression';
    try
        importance = model.OOBPermutedPredictorDeltaError(:);
    catch
        importance = nan(numel(inputFeatures), 1);
    end
else
    model = local_linear_regression(XTrain, yTrain);
    algorithm = 'local_linear_regression';
    importance = abs(model.beta(2:end));
end

modelInfo = struct();
modelInfo.model = model;
modelInfo.algorithm = algorithm;
modelInfo.modelName = modelName;
modelInfo.targetName = targetName;
modelInfo.inputFeatures = inputFeatures;
modelInfo.featureImportance = importance(:);
modelInfo.trainingRows = height(trainTable);
end

function model = local_linear_regression(X, y)
Xb = [ones(size(X, 1), 1), X];
beta = Xb \ y;
model = struct('beta', beta);
end
