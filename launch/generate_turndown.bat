@echo off
rem Generate the 10 MW turndown family (about 12 h; resumable)
rem Run from anywhere; resolves the repo root from this file location. Re-running resumes; nothing is regenerated.
set "REPO=%~dp0.."
matlab -batch "cd(getenv('REPO')); run('setup_paths.m'); diary(fullfile(AvonLogDir(),'turndown_run.log')); diary on; GenerateTurndownParallel(); diary off"
pause
