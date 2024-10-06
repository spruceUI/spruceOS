@echo off
setlocal

# This bat file will zip the spruce folder into a file named spruceV<version>.zip
# It excludes the .git directory and this script itself
# You need 7zip installed to use this script

REM Define variables
set "zipName=spruce"
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

REM Create the zip file name
set "outputZip=%zipName%V%version%.zip"

REM Create the zip file excluding this script and ".git" directories or files
echo Creating zip file "%outputZip%"...
7z a -xr!.git* -x!"%~nx0" "%outputZip%" *

REM Check if zip creation was successful
if %errorlevel% neq 0 (
    echo Error: Failed to create the zip file.
	pause
    exit /b 1
)

echo Zip file "%outputZip%" created successfully.
exit /b 0
