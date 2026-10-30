@echo off
REM Usage: build.cmd [server] [rebuild 0|1]
REM Vi du: build.cmd localhost 1      (dung lai tu dau)
set SERVER=%1
if "%SERVER%"=="" set SERVER=localhost
set REBUILD=%2
if "%REBUILD%"=="" set REBUILD=1
cd /d "%~dp0database"
sqlcmd -S %SERVER% -E -b -C -f 65001 -v ROOT="." REBUILD=%REBUILD% -i 99_run_all.sql
if errorlevel 1 (echo BUILD FAILED & exit /b 1)
cd /d "%~dp0tests"
sqlcmd -S %SERVER% -E -b -C -f 65001 -i 00_smoke_test.sql
if errorlevel 1 (echo SMOKE FAILED & exit /b 1)
sqlcmd -S %SERVER% -E -b -C -f 65001 -i 01_schema_check.sql
