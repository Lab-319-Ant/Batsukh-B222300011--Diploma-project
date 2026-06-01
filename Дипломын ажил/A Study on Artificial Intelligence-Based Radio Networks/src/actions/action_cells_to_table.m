function actions = action_cells_to_table(rows)
%ACTION_CELLS_TO_TABLE Convert preallocated action cell rows to typed table.

schema = empty_action_table();
names = schema.Properties.VariableNames;
if isempty(rows)
    actions = schema;
    return;
end

actions = table();
textCols = [4 19 20 28];
for c = 1:numel(names)
    col = rows(:, c);
    if ismember(c, textCols)
        actions.(names{c}) = cellstr(string(col));
    else
        actions.(names{c}) = cell2mat(col);
    end
end
end
