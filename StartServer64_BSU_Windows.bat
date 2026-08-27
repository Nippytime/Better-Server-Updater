@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "JAVA_EXE=.\jre64\bin\java.exe"
set "PZ_CLASSPATH=java/;java/projectzomboid.jar"
set "RESTART_DELAY_SECONDS=15"
set "STOP_FILE=BSU_STOP_RESTART.flag"
set "QUICK_EXIT_LIMIT_SECONDS=60"
set "QUICK_EXIT_MAX=3"
set "QUICK_EXIT_COUNT=0"

if not exist "%JAVA_EXE%" (
    echo [BSU] Could not find %JAVA_EXE%.
    echo [BSU] Put this file in your Project Zomboid Dedicated Server folder and run it from there.
    pause
    goto end
)

if not exist ".\java\projectzomboid.jar" (
    echo [BSU] Could not find .\java\projectzomboid.jar.
    echo [BSU] This script is for the Build 42 dedicated server layout.
    echo [BSU] Verify or update your Project Zomboid Dedicated Server install.
    pause
    goto end
)

:restart
if exist "%STOP_FILE%" (
    echo.
    echo [BSU] Stop file found: %STOP_FILE%
    echo [BSU] Delete "%STOP_FILE%" to allow automatic restarts again.
    goto end
)

for /f %%A in ('powershell -NoProfile -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()"') do set "START_SECONDS=%%A"

cls
echo ============================================================
echo [%date% %time%] Starting Project Zomboid dedicated server
echo ============================================================
echo [BSU] Classpath: %PZ_CLASSPATH%
echo [BSU] To stop the restart loop, create: %STOP_FILE%
echo.

"%JAVA_EXE%" ^
    -Djava.awt.headless=true ^
    -Dzomboid.steam=1 ^
    -Dzomboid.znetlog=1 ^
    -XX:+UseZGC ^
    -XX:-CreateCoredumpOnCrash ^
    -XX:-OmitStackTraceInFastThrow ^
    -Xms12g ^
    -Xmx13g ^
    -Djava.library.path=natives/;natives/win64/;. ^
    -cp "%PZ_CLASSPATH%" ^
    zombie.network.GameServer ^
    -statistic 0 ^
    %*

set "EXIT_CODE=%ERRORLEVEL%"
for /f %%A in ('powershell -NoProfile -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()"') do set "END_SECONDS=%%A"
set /a RUN_SECONDS=END_SECONDS-START_SECONDS 2>nul
if not defined RUN_SECONDS set "RUN_SECONDS=0"

if "%EXIT_CODE%"=="0" (
    set "QUICK_EXIT_COUNT=0"
) else (
    if !RUN_SECONDS! LSS %QUICK_EXIT_LIMIT_SECONDS% (
        set /a QUICK_EXIT_COUNT+=1
    ) else (
        set "QUICK_EXIT_COUNT=0"
    )
)

echo.
echo ============================================================
echo [%date% %time%] Server exited with code %EXIT_CODE% after !RUN_SECONDS! seconds.
echo ============================================================

if not "%EXIT_CODE%"=="0" if !QUICK_EXIT_COUNT! GEQ %QUICK_EXIT_MAX% (
    echo [BSU] The server failed quickly !QUICK_EXIT_COUNT! times in a row.
    echo [BSU] Stopping the restart loop so it does not spam-crash forever.
    echo [BSU] Check server-console.txt, Java memory settings, Workshop files, and the B42 install.
    pause
    goto end
)

echo [BSU] Restarting in %RESTART_DELAY_SECONDS% seconds.
echo [BSU] Create "%STOP_FILE%" before the timer ends to stop the loop.
timeout /t %RESTART_DELAY_SECONDS% /nobreak

goto restart

:end
echo.
echo [BSU] Restart loop stopped.
endlocal
