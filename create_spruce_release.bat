@echo off
setlocal

REM This bat file will create a 7z archive of the spruce folder named spruceV<version>.7z
REM It excludes all git-related files and this script itself
REM You need 7zip installed to use this script

REM Define variables
set "archiveName=spruce"
set "version="

REM Check for the spruce file
if not exist "spruce\spruce" (
    echo Error: Could not find the file "spruce\spruce".
	pause
    exit /b 1
)

REM Read the content of "spruce/spruce" file
set /p version=<spruce\spruce

REM Validate that we have the version
if "%version%"=="" (
    echo Error: Failed to retrieve the version from "spruce\spruce".
	pause
    exit /b 1
)

REM Create the 7z file name
set "output7z=%archiveName%V%version%.7z"

REM Create the 7z file excluding this script and all git-related files
echo Creating 7z archive "%output7z%"...
7z a -t7z -mx=9 -xr!.git* -x!.gitignore -x!.gitattributes -x!"%~nx0" -x!create_spruce_release.sh "%output7z%" *

REM Check if 7z creation was successful
if %errorlevel% neq 0 (
    echo Error: Failed to create the 7z archive.
	pause
    exit /b 1
)

echo 7z archive "%output7z%" created successfully.
pause
exit /b 0
