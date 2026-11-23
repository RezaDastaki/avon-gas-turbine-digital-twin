@echo off
rem Read-only progress report for all families
rem Run from anywhere; resolves the repo root from this file location. Re-running resumes; nothing is regenerated.
set "REPO=%~dp0.."
matlab -batch "cd(getenv('REPO')); run('setup_paths.m'); AvonProgress"
pause
