%% Topology baseline map smoke-test: зөвхөн plot_topology-г шинэчлэн ажиллуулж зургийг шинэчилнэ.

clear; clc; close all;

rootDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(rootDir, 'config')));
addpath(genpath(fullfile(rootDir, 'src')));

cfg = sim_config();
cfg = configure_run_mode(cfg);
rng(cfg.seed);

ensure_folder(cfg.resultsDir);
ensure_folder(cfg.figuresDir);

[cfg.plannedRadius_m, ~] = estimate_coverage_radius(cfg);
cfg.ISD_m = sqrt(3) * cfg.plannedRadius_m;
cfg.area_m = 2.25 * 2 * (cfg.ISD_m + cfg.plannedRadius_m);

topology = create_7site21sector_topology(cfg);
ues = generate_ues(cfg, topology);
rf = calc_rsrp_sinr(cfg, topology, ues);

plot_topology(cfg, topology, ues, rf);

fprintf('Зураг хадгалагдсан: %s\n', fullfile(cfg.figuresDir, 'phase1b_topology_ue_attachment.png'));
