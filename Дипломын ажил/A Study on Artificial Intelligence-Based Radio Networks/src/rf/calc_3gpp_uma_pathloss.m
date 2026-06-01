function PL_dB = calc_3gpp_uma_pathloss(cfg, d2D_m, useShadowing)
%CALC_3GPP_UMA_PATHLOSS 3GPP UMa-style path loss for macrocell simulation.
%
% Main implemented model:
%   UMa NLOS, TR 38.901-style:
%   PL_NLOS' = 13.54 + 39.08*log10(d3D) + 20*log10(fc) - 0.6*(hUT - 1.5)
%   PL_NLOS  = max(PL_LOS, PL_NLOS')
%
%   PL_LOS is included to avoid NLOS being below LOS.
%
% Inputs:
%   d2D_m       horizontal BS-UE distance in meters
%   useShadowing logical, if true adds zero-mean lognormal shadowing in dB
%
% Notes:
%   - fc is in GHz.
%   - d3D is in meters.
%   - Minimum distance is clipped to cfg.minDistance_m to avoid singular behavior.

if nargin < 3
    useShadowing = cfg.shadowingEnabled;
end

d2D_m = max(d2D_m, cfg.minDistance_m);
fc = cfg.fc_GHz;
hBS = cfg.hBS_m;
hUT = cfg.hUE_m;
d3D_m = sqrt(d2D_m.^2 + (hBS - hUT).^2);

% Simplified UMa LOS expression. Breakpoint is included approximately.
c = 3e8;
dBP = 4 * hBS * hUT * fc * 1e9 / c;

PL_LOS_1 = 28.0 + 22 .* log10(d3D_m) + 20 .* log10(fc);
PL_LOS_2 = 28.0 + 40 .* log10(d3D_m) + 20 .* log10(fc) ...
    - 9 .* log10(dBP.^2 + (hBS - hUT).^2);

PL_LOS = PL_LOS_1;
idx2 = d2D_m > dBP;
PL_LOS(idx2) = PL_LOS_2(idx2);

PL_NLOS_prime = 13.54 + 39.08 .* log10(d3D_m) + 20 .* log10(fc) - 0.6 .* (hUT - 1.5);
PL_NLOS = max(PL_LOS, PL_NLOS_prime);

switch upper(cfg.pathlossModel)
    case '3GPP_UMA_NLOS'
        PL_dB = PL_NLOS;
    case '3GPP_UMA_LOS'
        PL_dB = PL_LOS;
    otherwise
        error('Unsupported pathloss model: %s', cfg.pathlossModel);
end

if useShadowing && cfg.shadowingEnabled
    PL_dB = PL_dB + cfg.shadowingStd_dB .* randn(size(PL_dB));
end
end
