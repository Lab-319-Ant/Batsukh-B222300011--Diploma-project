function topology = create_single_site3sector_topology(cfg)
%CREATE_SINGLE_SITE3SECTOR_TOPOLOGY Build one macro LTE site with three sectors.

siteId = 1;
sites = table(siteId, 0, 0, cfg.hBS_m, 'VariableNames', {'siteId','x_m','y_m','h_m'});

numSectors = numel(cfg.sectorAzimuths_deg);
sectorId = (1:numSectors).';
siteIdCol = ones(numSectors, 1);
xCol = zeros(numSectors, 1);
yCol = zeros(numSectors, 1);
azCol = cfg.sectorAzimuths_deg(:);
txPwrCol = cfg.txPower_dBm * ones(numSectors, 1);
rsPwrCol = cfg.refSignalPower_dBm * ones(numSectors, 1);
gainCol = cfg.antennaGain_dBi * ones(numSectors, 1);
tiltCol = cfg.electricalTilt_deg * ones(numSectors, 1);
status = repmat({'normal'}, numSectors, 1);

sectors = table(sectorId, siteIdCol, xCol, yCol, azCol, txPwrCol, rsPwrCol, gainCol, tiltCol, status, ...
    'VariableNames', {'sectorId','siteId','x_m','y_m','azimuth_deg','txPower_dBm', ...
    'refSignalPower_dBm','antennaGain_dBi','electricalTilt_deg','status'});

topology.sites = sites;
topology.sectors = sectors;
end
