function cleanTable = standardize_vendor_kpi(rawTable, vcfg)
%STANDARDIZE_VENDOR_KPI Convert raw vendor workbook rows into project schema.

cleanTable = map_vendor_kpi_to_project_schema(rawTable, vcfg);
cleanTable = sortrows(cleanTable, {'sim_site_id','sim_sector_id','cell_id','timestamp'});
end
