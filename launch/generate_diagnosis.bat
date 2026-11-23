@echo off
rem Generate the diagnosis family (multi-day; resumable)
rem Run from anywhere; resolves the repo root from this file location. Re-running resumes; nothing is regenerated.
set "REPO=%~dp0.."
matlab -batch "cd(getenv('REPO')); run('setup_paths.m'); diary(fullfile(AvonLogDir(),'diag_run.log')); diary on; GenerateDiagnosisParallel(); diary off"
pause
