@echo off
rem Generate/continue the run-to-failure family (multi-day; resumable)
rem Run from anywhere; resolves the repo root from this file location. Re-running resumes; nothing is regenerated.
set "REPO=%~dp0.."
matlab -batch "cd(getenv('REPO')); run('setup_paths.m'); diary(fullfile(AvonLogDir(),'rtf_run.log')); diary on; GenerateRTFParallel(); diary off"
pause
