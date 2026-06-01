function rawTable = load_vendor_kpi(vcfg)
%LOAD_VENDOR_KPI Read all configured vendor KPI workbooks.

rawTable = table();
for i = 1:height(vcfg.siteMap)
    fp = fullfile(vcfg.rawKpiDir, vcfg.siteMap.vendor_file{i});
    if ~isfile(fp)
        error('Vendor KPI file missing: %s', fp);
    end

    T = readtable(fp, 'Sheet', 1, 'VariableNamingRule', 'preserve');
    T.vendor_site_key = repmat(vcfg.siteMap.vendor_site_key(i), height(T), 1);
    T.vendor_file = repmat(vcfg.siteMap.vendor_file(i), height(T), 1);
    T.sim_site_id = repmat(vcfg.siteMap.sim_site_id(i), height(T), 1);
    T.sim_position = repmat(vcfg.siteMap.sim_position(i), height(T), 1);
    rawTable = [rawTable; T]; %#ok<AGROW>
end
end
