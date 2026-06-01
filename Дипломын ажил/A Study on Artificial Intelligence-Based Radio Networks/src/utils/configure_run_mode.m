function cfg = configure_run_mode(cfg)
%CONFIGURE_RUN_MODE Apply reproducible run-mode settings.
%
% The default cfg.runMode is defined in sim_config.m. It can be overridden
% without editing source by setting the environment variable:
%   LTE_SON_RUN_MODE=full

envRunMode = strtrim(getenv('LTE_SON_RUN_MODE'));
if ~isempty(envRunMode)
    cfg.runMode = envRunMode;
end

validModes = {'full','phase4_only','phase8a_only','reuse_phase4_to_phase8a','fast_debug'};
if ~ismember(cfg.runMode, validModes)
    error('Unknown cfg.runMode "%s". Valid modes: %s', cfg.runMode, strjoin(validModes, ', '));
end

if strcmp(cfg.runMode, 'fast_debug')
    cfg.phase4NumRealizationsPerScenario = 3;
    cfg.phase6NumCODRealizationsPerClass = 30;
    cfg.phase7NumDays = 1;
    cfg.phase7bNumLearningCycles = 30;
    cfg.phase6bNumTrees = 50;
    cfg.phase8bMaxActions = 5000;
end
end
