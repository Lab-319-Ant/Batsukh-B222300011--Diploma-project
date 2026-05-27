function modelInfo = train_cod_random_forest(cfg, trainTable, inputFeatures)
%TRAIN_COD_RANDOM_FOREST Train Phase 6B COD Random Forest classifier.

classNames = {'normal','degraded','outage'};
XTrain = table2array(trainTable(:, inputFeatures));
yTrain = categorical(string(trainTable.cod_label), classNames);

rng(cfg.seed + 6300);
numTrees = cfg.phase6bNumTrees;

if exist('TreeBagger', 'file') == 2
    model = TreeBagger(numTrees, XTrain, cellstr(yTrain), ...
        'Method', 'classification', ...
        'OOBPrediction', 'on', ...
        'OOBPredictorImportance', 'on', ...
        'MinLeafSize', 1);
    algorithm = 'TreeBagger';
    classOrder = cellstr(model.ClassNames);
    try
        importance = model.OOBPermutedPredictorDeltaError(:);
    catch
        importance = nan(numel(inputFeatures), 1);
    end
else
    treeTemplate = templateTree('MinLeafSize', 1);
    model = fitcensemble(XTrain, yTrain, ...
        'Method', 'Bag', ...
        'NumLearningCycles', numTrees, ...
        'Learners', treeTemplate, ...
        'ClassNames', categorical(classNames), ...
        'Prior', 'empirical');
    algorithm = 'fitcensemble_Bag';
    classOrder = cellstr(string(model.ClassNames));
    try
        importance = predictorImportance(model)';
    catch
        importance = nan(numel(inputFeatures), 1);
    end
end

modelInfo = struct();
modelInfo.model = model;
modelInfo.algorithm = algorithm;
modelInfo.classNames = classNames;
modelInfo.classOrder = classOrder;
modelInfo.inputFeatures = inputFeatures;
modelInfo.featureImportance = importance;
modelInfo.numTrees = numTrees;
modelInfo.trainingRows = height(trainTable);
end
