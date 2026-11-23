@echo off
rem Validate the pipeline configuration (about 1 minute)
rem Run from anywhere; resolves the repo root from this file location. Re-running resumes; nothing is regenerated.
set "REPO=%~dp0.."
matlab -batch "cd(getenv('REPO')); run('setup_paths.m'); ValidatePipelineConfig"
pause
