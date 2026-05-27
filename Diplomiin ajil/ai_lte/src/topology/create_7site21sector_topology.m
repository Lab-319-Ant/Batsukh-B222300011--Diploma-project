function topology = create_7site21sector_topology(cfg)
%CREATE_7SITE21SECTOR_TOPOLOGY Build a 7-site / 21-sector LTE macro topology.
%
% The layout uses one center site and six first-tier neighbors. The
% center-to-center site distance is cfg.ISD_m, derived from the planned
% cell radius by ISD = sqrt(3) * R_cell.

if ~isfield(cfg, 'ISD_m') || ~isfinite(cfg.ISD_m) || cfg.ISD_m <= 0
    error('cfg.ISD_m must be defined and positive before creating the 7-site topology.');
end

ISD = cfg.ISD_m;
siteId = (1:7).';

% 0 deg is north and 90 deg is east, consistent with calc_antenna_gain.
siteBearing_deg = [0; 0; 60; 120; 180; 240; 300];
siteRadius_m = [0; repmat(ISD, 6, 1)];
x_m = siteRadius_m .* sind(siteBearing_deg);
y_m = siteRadius_m .* cosd(siteBearing_deg);
h_m = cfg.hBS_m * ones(7, 1);

sites = table(siteId, x_m, y_m, h_m, ...
    'VariableNames', {'siteId','x_m','y_m','h_m'});

numSites = height(sites);
numAz = numel(cfg.sectorAzimuths_deg);
numSectors = numSites * numAz;

sectorId = (1:numSectors).';
siteIdCol = zeros(numSectors, 1);
xCol = zeros(numSectors, 1);
yCol = zeros(numSectors, 1);
azCol = zeros(numSectors, 1);
txPwrCol = cfg.txPower_dBm * ones(numSectors, 1);
rsPwrCol = cfg.refSignalPower_dBm * ones(numSectors, 1);
gainCol = cfg.antennaGain_dBi * ones(numSectors, 1);
tiltCol = cfg.electricalTilt_deg * ones(numSectors, 1);
status = repmat({'normal'}, numSectors, 1);

row = 0;
for i = 1:numSites
    for a = 1:numAz
        row = row + 1;
        siteIdCol(row) = sites.siteId(i);
        xCol(row) = sites.x_m(i);
        yCol(row) = sites.y_m(i);
        azCol(row) = cfg.sectorAzimuths_deg(a);
    end
end

sectors = table(sectorId, siteIdCol, xCol, yCol, azCol, txPwrCol, rsPwrCol, ...
    gainCol, tiltCol, status, ...
    'VariableNames', {'sectorId','siteId','x_m','y_m','azimuth_deg','txPower_dBm', ...
    'refSignalPower_dBm','antennaGain_dBi','electricalTilt_deg','status'});

topology = struct();
topology.sites = sites;
topology.sectors = sectors;
topology.ISD_m = ISD;
topology.plannedRadius_m = cfg.plannedRadius_m;
end
