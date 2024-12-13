@echo off
setlocal enabledelayedexpansion

for /f "delims=" %%a in ('dir /s /b /ad ^| sort /r') do (
    dir "%%a" /b /a | findstr "^" >nul || (
        echo Creating .gitkeep in: %%a
        type nul > "%%a\.gitkeep"
    )
)

echo Done! Empty folders now contain .gitkeep files.