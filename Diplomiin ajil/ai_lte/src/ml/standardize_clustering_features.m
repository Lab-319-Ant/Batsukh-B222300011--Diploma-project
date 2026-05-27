function [Xz, selectedFeatureTable, standardizationInfo] = standardize_clustering_features(featureTable, inputFeatures)
%STANDARDIZE_CLUSTERING_FEATURES Z-score normalize selected clustering features.

missingFeatures = setdiff(inputFeatures, featureTable.Properties.VariableNames);
if ~isempty(missingFeatures)
    error('Phase5:MissingClusteringFeatures', ...
        'Missing clustering input features: %s', strjoin(missingFeatures, ', '));
end

selectedFeatureTable = featureTable(:, inputFeatures);
nonNumeric = {};
for i = 1:numel(inputFeatures)
    values = selectedFeatureTable.(inputFeatures{i});
    if ~(isnumeric(values) || islogical(values))
        nonNumeric{end+1} = inputFeatures{i}; %#ok<AGROW>
    end
end
if ~isempty(nonNumeric)
    error('Phase5:NonNumericClusteringFeatures', ...
        'Non-numeric clustering features: %s', strjoin(nonNumeric, ', '));
end

X = table2array(selectedFeatureTable);
if any(ismissing(X), 'all')
    error('Phase5:MissingFeatureValues', 'Selected clustering features contain missing values.');
end
if any(isinf(X), 'all')
    error('Phase5:InfiniteFeatureValues', 'Selected clustering features contain infinite values.');
end

mu = mean(X, 1, 'omitnan');
sigma = std(X, 0, 1, 'omitnan');
zeroVarianceMask = sigma == 0 | isnan(sigma);
usedFeatureNames = inputFeatures(~zeroVarianceMask);
removedFeatureNames = inputFeatures(zeroVarianceMask);

if isempty(usedFeatureNames)
    error('Phase5:NoUsableFeatures', 'All clustering features have zero variance.');
end

X = X(:, ~zeroVarianceMask);
mu = mu(:, ~zeroVarianceMask);
sigma = sigma(:, ~zeroVarianceMask);
Xz = (X - mu) ./ sigma;
selectedFeatureTable = selectedFeatureTable(:, usedFeatureNames);

standardizationInfo = struct();
standardizationInfo.usedFeatureNames = usedFeatureNames;
standardizationInfo.removedZeroVarianceFeatures = removedFeatureNames;
standardizationInfo.mean = mu;
standardizationInfo.std = sigma;
end
