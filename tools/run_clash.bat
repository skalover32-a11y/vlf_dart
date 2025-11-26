@echo off
cd /d %~dp0

echo === VLF Clash TUN ===
echo 1) Генерируем config.yaml из подписки...
powershell -ExecutionPolicy Bypass -File build_config_clash.ps1
if errorlevel 1 (
    echo Ошибка генерации конфига.
    pause
    exit /b 1
)

echo 2) Запускаем Clash Meta (нужны права администратора для TUN)...
echo.
clash.exe -f config.yaml
pause
