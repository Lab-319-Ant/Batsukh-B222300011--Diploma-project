function labelDistribution = summarize_cod_dataset_balance(codTable)
%SUMMARIZE_COD_DATASET_BALANCE Count COD labels.

labels = categorical(codTable.cod_label, {'normal','degraded','outage'});
labelNames = categories(labels);
rowCount = zeros(numel(labelNames), 1);
for i = 1:numel(labelNames)
    rowCount(i) = sum(labels == labelNames{i});
end
rowFraction = rowCount / max(sum(rowCount), 1);
labelDistribution = table(labelNames, rowCount, rowFraction, ...
    'VariableNames', {'cod_label','row_count','row_fraction'});
end
