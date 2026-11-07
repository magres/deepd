@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
title deepd installer for Android TV boxes
cd /d "%~dp0"

rem adb search order: platform-tools inside the repo root, next to the script,
rem then plain adb from PATH
set ADB=..\platform-tools\adb.exe
if not exist "%ADB%" set ADB=%~dp0..\platform-tools\adb.exe
if not exist "%ADB%" set ADB=..\adb.exe
if not exist "%ADB%" set ADB=adb

echo =====================================================================
echo   deepd - deep sleep for Android TV boxes (Amlogic etc.)
echo   Installs the daemon, enables HDMI-CEC, reboots the box.
echo   Requires root on the box firmware.
echo.
echo   [1] INSTALL (install + automatic reboot)
echo   [0] UNINSTALL (rollback: removes deepd, restores CEC setting)
echo   [Q] EXIT
echo =====================================================================
choice /c 10Q /n /m "= Select action [1/0/Q]: "
if errorlevel 3 goto end
if errorlevel 2 set ACT=uninstall& goto ip
set ACT=install
goto ip

:ip
if "%1"=="" ( set /p IP=Box IP (example 192.168.1.100): ) else ( set "IP=%1" )
if "%IP%"=="" ( echo IP is not set. & pause & goto end )
if not "%IP::=%"=="%IP%" ( set CONNECT=%IP% ) else ( set CONNECT=%IP%:5555 )

echo.
echo == Connecting to %CONNECT% ...
"%ADB%" connect %CONNECT% >nul 2>&1
timeout /t 1 /nobreak >nul 2>&1
"%ADB%" connect %CONNECT%
"%ADB%" devices

echo == Checking root access ...
"%ADB%" root >nul 2>&1
"%ADB%" shell id -u 2>nul | findstr "=0" >nul
if errorlevel 1 (
  "%ADB%" shell "su -c 'id -u'" 2>nul | findstr "=0" >nul
  if errorlevel 1 (
    echo [ОШИБКА] Нет root-доступа через ADB.
    echo     Прошивка должна иметь root. Попробуйте: %ADB% root
    echo     или включите su в настройках прошивки приставки.
    pause
    goto end
  )
  set SU=su
) else (
  set SU=
)

if "%ACT%"=="uninstall" goto uninstall

echo == Uploading payload ...
if not exist "%TEMP%\deepd-payload" mkdir "%TEMP%\deepd-payload" 2>nul
"%ADB%" push ..\deepd.sh /data/local/tmp/deepd-installer/deepd.sh >nul
"%ADB%" push ..\deepd.conf /data/local/tmp/deepd-installer/deepd.conf >nul
"%ADB%" push ..\deepd.rc /data/local/tmp/deepd-installer/deepd.rc >nul
"%ADB%" push device-install.sh /data/local/tmp/deepd-installer/device-install.sh >nul
"%ADB%" push device-uninstall.sh /data/local/tmp/deepd-installer/device-uninstall.sh >nul

echo == Installing ...
if "%SU%"=="su" (
  "%ADB%" shell "su -c 'sh /data/local/tmp/deepd-installer/device-install.sh'"
) else (
  "%ADB%" shell "sh /data/local/tmp/deepd-installer/device-install.sh"
)

echo == Rebooting the box (1-2 minutes) ...
"%ADB%" reboot
echo.
echo == После перезагрузки:
echo    выключите ТВ - приставка уйдёт в глубокий сон (около 10 сек),
echo    включите ТВ - ATV вернётся сам.
echo ~ Done! Close the window.
(timeout /t 8 >nul)
goto end

:uninstall
"%ADB%" push device-uninstall.sh /data/local/tmp/deepd-installer/device-uninstall.sh >nul
echo == Uninstalling ...
if "%SU%"=="su" (
  "%ADB%" shell "su -c 'sh /data/local/tmp/deepd-installer/device-uninstall.sh'"
) else (
  "%ADB%" shell "sh /data/local/tmp/deepd-installer/device-uninstall.sh"
)
"%ADB%" reboot
echo ~ Done! Close the window.
(timeout /t 8 >nul)
goto end

:end
endlocal
