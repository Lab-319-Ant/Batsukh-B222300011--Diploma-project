function forecast = run_tp_site_user_forecast(cleanKpi, vcfg)
%RUN_TP_SITE_USER_FORECAST Сайтын идэвхтэй хэрэглэгчдийн +1 цагийн таамаглал.
%
% Сайт тус бүрийн 3 сектороор active_users-ыг нийлбэрлэж, сүүлийн
% testDays өдрийг тестийн зориулалтаар хадгална. Үлдсэн өгөгдөл дээр
% шугаман регресс загвар сургана.
%
% Overfit-ыг бууруулах арга хэмжээ:
%   1) Feature багасгасан (lag 0, lag 4, lag 92, цагийн sin/cos).
%   2) Feature-уудыг z-score-оор стандартчилсан.
%   3) Ridge λ параметрийг train дотроос walk-forward CV-р сонгоно.
%   4) Таамаглалыг сургалтын өгөгдлийн дээд утгаар clamp хийнэ.

forecast = struct('predictions', table(), 'metrics', table(), ...
    'featureWeights', table(), 'siteTimeseries', table(), 'splitSummary', table());

selected = cleanKpi(cleanKpi.selected_for_21cell_topology, :);
if isempty(selected)
    return;
end

horizon = vcfg.tpUserForecastHorizonSteps;
lagSteps = vcfg.tpUserForecastLagSteps;
stepMinutes = vcfg.expectedGranularityMinutes;
lambdaGrid = vcfg.tpUserForecastRidgeLambdaGrid;
cvHoldout = vcfg.tpUserForecastCvHoldoutSteps;
cvTol = vcfg.tpUserForecastCvToleranceRatio;
clampMult = vcfg.tpUserForecastPredictionClampMultiplier;
nonNeg = vcfg.tpUserForecastNonNegativeWeights;
biasEnabled = vcfg.tpUserForecastBiasCorrectionEnabled;
biasAlpha = vcfg.tpUserForecastBiasCorrectionAlpha;
biasShrink = vcfg.tpUserForecastBiasCorrectionShrink;

siteTimeseries = aggregate_site_users(selected, stepMinutes);

sites = unique(siteTimeseries.sim_site_id);
predRows = {};
metricRows = {};
weightRows = {};
splitRows = {};

for s = sites(:)'
    S = siteTimeseries(siteTimeseries.sim_site_id == s, :);
    S = sortrows(S, 'timestamp');
    if height(S) < vcfg.tpUserForecastMinTrainRows + horizon
        continue;
    end

    intervalsPerDay = round(24 * 60 / stepMinutes);
    [trainMask, testMask, splitTs] = split_train_test(S.timestamp, ...
        vcfg.tpUserForecastTestDays * intervalsPerDay);
    if ~any(trainMask) || ~any(testMask)
        continue;
    end

    [X, y, validRows, featureNames] = build_lag_features(S, lagSteps, horizon);
    if isempty(y)
        continue;
    end

    trainSampleMask = trainMask(validRows);
    testSampleMask = testMask(validRows);
    targetTimestamps = S.timestamp(validRows) + minutes(horizon * stepMinutes);

    if sum(trainSampleMask) < vcfg.tpUserForecastMinTrainRows || ~any(testSampleMask)
        continue;
    end

    Xtrain = X(trainSampleMask, :);
    ytrain = y(trainSampleMask);
    Xtest = X(testSampleMask, :);
    ytest = y(testSampleMask);

    % NNLS-д стандартчилал шаардлагагүй (масштабаар хязгаарлагдсан
    % feature нь жинг үнэн зөв тайлбарлахад тус болно). Хадгалж явна.
    mu = zeros(1, size(Xtrain, 2));
    sigma = ones(1, size(Xtrain, 2));

    bestLambda = pick_ridge_lambda_walk_forward(Xtrain, ytrain, lambdaGrid, cvHoldout, cvTol, nonNeg);

    [beta, intercept] = fit_constrained_ridge(Xtrain, ytrain, bestLambda, nonNeg);

    yhatTrain = intercept + Xtrain * beta;
    yhatTest  = intercept + Xtest  * beta;

    % Глобал clamp (сургалтын дээд утгаас clampMult-ийн дахин).
    upperClamp = clampMult * max(ytrain, [], 'omitnan');
    yhatTrain = clamp_range(yhatTrain, 0, upperClamp);
    yhatTest  = clamp_range(yhatTest,  0, upperClamp);
    % Локал clamp: таамаглал нь тухайн мөрийн оролтын feature-уудаас
    % хамгийн ихээс 1.20 дахин их байх боломжгүй. Энэ нь "өчигдөр их
    % байсан тул өнөөдөр их" гэсэн buruu локал хазайлтыг дардна.
    rowMaxTrain = max(Xtrain, [], 2);
    rowMaxTest  = max(Xtest,  [], 2);
    yhatTrain = min(yhatTrain, 1.20 * rowMaxTrain);
    yhatTest  = min(yhatTest,  1.20 * rowMaxTest);

    % Causal adaptive bias correction (зөвхөн тестийн дарааллын дотор).
    % horizon мөрийн өмнө хийсэн таамаглал болон одоо ажиглагдсан бодит
    % утгын зөрүүг exponential smoothing-аар хянана. Шинэ row дээр уг
    % хазайлтыг шууд буулгана. Энэ нь future leakage үүсгэхгүй — i-р
    % мөрийн таамаглалд зөвхөн 1..i-horizon мөрийн residual ашиглагдана.
    if biasEnabled
        yhatTest = apply_causal_bias_correction(ytest, yhatTest, ...
            horizon, biasAlpha, biasShrink);
        yhatTest = clamp_range(yhatTest, 0, upperClamp);
    end

    sitePos = char(string(S.sim_position(1)));
    siteKey = char(string(S.vendor_site_key(1)));
    testTimestamps = targetTimestamps(testSampleMask);

    for k = 1:numel(ytest)
        predRows(end+1, :) = { ...
            S.sim_site_id(1), sitePos, siteKey, testTimestamps(k), ...
            ytest(k), yhatTest(k)}; %#ok<AGROW>
    end

    metricRows(end+1, :) = build_metric_row(s, sitePos, siteKey, ...
        ytrain, yhatTrain, ytest, yhatTest, splitTs, bestLambda); %#ok<AGROW>

    for f = 1:numel(featureNames)
        weightRows(end+1, :) = {s, sitePos, siteKey, ...
            featureNames{f}, beta(f), mu(f), sigma(f)}; %#ok<AGROW>
    end
    weightRows(end+1, :) = {s, sitePos, siteKey, 'intercept', intercept, NaN, NaN}; %#ok<AGROW>

    splitRows(end+1, :) = {s, sitePos, siteKey, ...
        S.timestamp(find(trainMask, 1, 'first')), ...
        S.timestamp(find(trainMask, 1, 'last')), ...
        S.timestamp(find(testMask, 1, 'first')), ...
        S.timestamp(find(testMask, 1, 'last')), ...
        sum(trainSampleMask), sum(testSampleMask), bestLambda}; %#ok<AGROW>
end

if isempty(predRows)
    return;
end

forecast.predictions = cell2table(predRows, 'VariableNames', ...
    {'sim_site_id','sim_position','vendor_site_key','forecast_timestamp', ...
    'actual_active_users_site','predicted_active_users_site'});

forecast.metrics = cell2table(metricRows, 'VariableNames', ...
    {'sim_site_id','sim_position','vendor_site_key','train_rows','test_rows', ...
    'train_mae','train_rmse','train_r2', ...
    'test_mae','test_rmse','test_r2', ...
    'generalization_gap_mae','split_timestamp','ridge_lambda'});

forecast.featureWeights = cell2table(weightRows, 'VariableNames', ...
    {'sim_site_id','sim_position','vendor_site_key','feature_name', ...
    'standardized_coefficient','feature_mean','feature_std'});

forecast.siteTimeseries = siteTimeseries;

forecast.splitSummary = cell2table(splitRows, 'VariableNames', ...
    {'sim_site_id','sim_position','vendor_site_key', ...
    'train_first_timestamp','train_last_timestamp', ...
    'test_first_timestamp','test_last_timestamp', ...
    'train_sample_rows','test_sample_rows','ridge_lambda'});
end

function siteTs = aggregate_site_users(selected, stepMinutes)
[uniq, ~, idx] = unique(selected(:, {'sim_site_id','timestamp'}), 'rows');
n = height(uniq);
activeSum = accumarray(idx, selected.active_users, [n 1], @(v) sum(v, 'omitnan'));
trafficSum = accumarray(idx, selected.traffic_volume_dl_kbyte, [n 1], @(v) sum(v, 'omitnan'));
prbMean = accumarray(idx, selected.dl_prb_utilization, [n 1], @(v) mean(v, 'omitnan'));

[~, firstIdx] = unique(idx, 'first');
sitePos = selected.sim_position(firstIdx);
siteKey = selected.vendor_site_key(firstIdx);

siteTs = table(uniq.sim_site_id, uniq.timestamp, sitePos, siteKey, ...
    activeSum, trafficSum, prbMean, ...
    'VariableNames', {'sim_site_id','timestamp','sim_position','vendor_site_key', ...
    'active_users_site','traffic_volume_dl_kbyte_site','dl_prb_utilization_site_mean'});
siteTs = sortrows(siteTs, {'sim_site_id','timestamp'});

gaps = minutes(diff(siteTs.timestamp));
sameSite = siteTs.sim_site_id(1:end-1) == siteTs.sim_site_id(2:end);
if any(gaps(sameSite) ~= stepMinutes)
    warning('run_tp_site_user_forecast:irregularGrid', ...
        'Зарим интервал %d минут биш байна; таамаглал үргэлжилнэ.', stepMinutes);
end
end

function [trainMask, testMask, splitTs] = split_train_test(timestamps, testRowCount)
[sortedTs, sortIdx] = sort(timestamps);
n = numel(sortedTs);
testRowCount = min(testRowCount, max(n - 1, 0));
splitIdx = n - testRowCount;
trainMask = false(n, 1);
testMask = false(n, 1);
trainMask(sortIdx(1:splitIdx)) = true;
testMask(sortIdx(splitIdx + 1:end)) = true;
if splitIdx >= 1 && splitIdx <= n
    splitTs = sortedTs(min(splitIdx + 1, n));
else
    splitTs = NaT;
end
end

function [X, y, validRows, featureNames] = build_lag_features(S, lagSteps, horizon)
n = height(S);
users = S.active_users_site;

maxLag = max(lagSteps);
firstValid = maxLag + 1;
lastValid = n - horizon;
if lastValid < firstValid
    X = []; y = []; validRows = []; featureNames = {}; return;
end
validRows = (firstValid:lastValid)';

nLags = numel(lagSteps);
nFeatures = nLags;
featureNames = cell(nFeatures, 1);
X = zeros(numel(validRows), nFeatures);
for k = 1:nLags
    X(:, k) = users(validRows - lagSteps(k));
    featureNames{k} = sprintf('users_lag_%dsteps', lagSteps(k));
end

y = users(validRows + horizon);

finiteMask = all(isfinite(X), 2) & isfinite(y);
X = X(finiteMask, :);
y = y(finiteMask);
validRows = validRows(finiteMask);
end

function [Z, mu, sigma] = zscore_fit(X)
mu = mean(X, 1);
sigma = std(X, 0, 1);
sigma(sigma == 0 | ~isfinite(sigma)) = 1;
Z = (X - mu) ./ sigma;
end

function Z = zscore_apply(X, mu, sigma)
Z = (X - mu) ./ sigma;
end

function [beta, intercept] = fit_constrained_ridge(X, y, lambda, nonNeg)
% Ridge регрессийг сөрөг бус хязгаарлалттай эсвэл хязгаарлалтгүйгээр
% бодно. Хязгаарлалттай тохиолдолд augmented матриц [X; sqrt(λ)I],
% [y_c; 0] дээр lsqnonneg ажилуулна — энэ нь base MATLAB-д суурилуулсан
% бөгөөд гадны toolbox хэрэггүй.
p = size(X, 2);
yMean = mean(y, 'omitnan');
xMean = mean(X, 1, 'omitnan');
Xc = X - xMean;
yc = y - yMean;
if nonNeg
    Xaug = [Xc; sqrt(lambda) * eye(p)];
    yaug = [yc; zeros(p, 1)];
    beta = lsqnonneg(Xaug, yaug);
else
    G = (Xc' * Xc) + lambda * eye(p);
    beta = G \ (Xc' * yc);
end
intercept = yMean - xMean * beta;
end

function bestLambda = pick_ridge_lambda_walk_forward(X, y, lambdaGrid, holdoutSteps, tolRatio, nonNeg)
% Walk-forward CV: эхний хэсэг дээр сургаад, сүүлийн holdoutSteps мөр
% дээр MAE-г тооцно. "Хамгийн томоохон λ хэдий нь MAE нь best-ээс
% tolRatio хүртэлх алдагдалтай байх" дүрмээр сонгоно — overfit-ыг
% дарах талд хазайлгасан.
n = size(X, 1);
holdoutSteps = min(holdoutSteps, max(1, floor(n / 3)));
trainEnd = n - holdoutSteps;
if trainEnd < 32
    bestLambda = max(lambdaGrid);
    return;
end
Xfit = X(1:trainEnd, :);
yfit = y(1:trainEnd);
Xval = X(trainEnd + 1:end, :);
yval = y(trainEnd + 1:end);

maeList = zeros(size(lambdaGrid));
for k = 1:numel(lambdaGrid)
    [b, c] = fit_constrained_ridge(Xfit, yfit, lambdaGrid(k), nonNeg);
    yhat = c + Xval * b;
    yhat = max(yhat, 0);
    maeList(k) = mean(abs(yhat - yval), 'omitnan');
end

bestMae = min(maeList);
tolerable = maeList <= bestMae * (1 + tolRatio);
candidates = lambdaGrid(tolerable);
bestLambda = max(candidates);
end

function y = clamp_range(x, lo, hi)
y = max(x, lo);
if isfinite(hi)
    y = min(y, hi);
end
end

function corrected = apply_causal_bias_correction(yTrue, yHat, horizon, alpha, shrink)
% i-р мөрийн таамаглалд зөвхөн 1..i-horizon мөрийн residual ашиглагдана
% (causal). Exponential smoothing: s_t = (1-α) s_{t-1} + α r_t, дараа нь
% shrink-р хэмжээг бууруулна (overshoot-аас сэргийлнэ).
n = numel(yHat);
corrected = yHat;
smoothed = 0;
applied = 0;
for i = 1:n
    if i > horizon
        idx = i - horizon;
        residual = yTrue(idx) - yHat(idx);
        if isfinite(residual)
            if applied == 0
                smoothed = residual;
            else
                smoothed = (1 - alpha) * smoothed + alpha * residual;
            end
            applied = applied + 1;
        end
    end
    corrected(i) = yHat(i) + shrink * smoothed;
end
end

function row = build_metric_row(s, sitePos, siteKey, ytrain, yhatTrain, ...
    ytest, yhatTest, splitTs, bestLambda)
[trainMae, trainRmse, trainR2] = regression_scores(ytrain, yhatTrain);
[testMae,  testRmse,  testR2]  = regression_scores(ytest,  yhatTest);
gap = testMae - trainMae;
row = {s, sitePos, siteKey, numel(ytrain), numel(ytest), ...
    trainMae, trainRmse, trainR2, ...
    testMae, testRmse, testR2, ...
    gap, splitTs, bestLambda};
end

function [mae, rmse, r2] = regression_scores(actual, predicted)
err = predicted - actual;
mae = mean(abs(err), 'omitnan');
rmse = sqrt(mean(err.^2, 'omitnan'));
sse = sum(err.^2, 'omitnan');
sst = sum((actual - mean(actual, 'omitnan')).^2, 'omitnan');
if sst <= eps
    r2 = NaN;
else
    r2 = 1 - sse / sst;
end
end
