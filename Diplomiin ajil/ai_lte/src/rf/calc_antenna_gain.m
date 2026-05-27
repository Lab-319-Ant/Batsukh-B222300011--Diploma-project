function gain_dBi = calc_antenna_gain(cfg, sectorAzimuth_deg, sectorTilt_deg, dx_m, dy_m)
%CALC_ANTENNA_GAIN Simplified 3D sector antenna pattern.
%
% Horizontal attenuation:
%   A_h = min(12*(angleOffset/HPBW)^2, A_m)
%
% Vertical attenuation:
%   A_v = min(12*(verticalOffset/V_HPBW)^2, SLA_v)
%
% Total gain:
%   G = G_max - min(A_h + A_v, A_m)
%
% This is a simplified planning-grade pattern for RF validation phases.

azToUE_deg = atan2d(dx_m, dy_m);  % 0 deg = north, 90 deg = east
azOffset_deg = wrap_to_180(azToUE_deg - sectorAzimuth_deg);

Ah_dB = min(12 .* (azOffset_deg ./ cfg.horizontalHPBW_deg).^2, cfg.frontBackAtten_dB);

d2D_m = sqrt(dx_m.^2 + dy_m.^2);
elev_deg = atan2d(cfg.hUE_m - cfg.hBS_m, max(d2D_m, cfg.minDistance_m));
boresightElev_deg = -sectorTilt_deg;
vertOffset_deg = elev_deg - boresightElev_deg;

Av_dB = min(12 .* (vertOffset_deg ./ cfg.verticalHPBW_deg).^2, cfg.sideLobeAtten_dB);
A_dB = min(Ah_dB + Av_dB, cfg.frontBackAtten_dB);

gain_dBi = cfg.antennaGain_dBi - A_dB;
end

function wrapped = wrap_to_180(angle_deg)
wrapped = mod(angle_deg + 180, 360) - 180;
end
