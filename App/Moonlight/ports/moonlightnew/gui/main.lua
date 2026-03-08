-------------------------------------------------------------------------------------------
-- WINDOW ---------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
function setupWindow()
    love.window.setTitle("Moonlight GUI")
    love.window.setFullscreen(true)
end

-------------------------------------------------------------------------------------------
-- MENU PRESETS ---------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
local menus = {
    mainMenu = {"Settings", "Play", "Connect"},
    settingsMenu = {"Resolutions", "Bitrate", "Framerate", "Codec", "Remote Optimized", "Sfx", "Music", "Theme"},
    connectMenu = {"Pair", "IP Address", "Reload Apps"},
    playMenu = {} -- Defined dynamically later
}
local selectedMenu = "mainMenu"
local selectedOption = 2

-------------------------------------------------------------------------------------------
-- FONT SETTINGS --------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
local normalColor = {0.5, 0.5, 0.5, 1}  -- Grey for non-selected
local selectedColor = {1, 1, 1, 1}      -- White for selected
local currentColors = {}
local transitionSpeed = 2
local font, smallerFont, tinyFont, largerFont  -- Define fonts globally

-- Setup fonts based on window size
function setupFonts()
    local referenceWidth = 1050  -- Baseline res width where fontsize 32 is good
    local referenceHeight = 900  -- Baseline res height
    local displayWidth, displayHeight = love.graphics.getDimensions()  -- Get the current display dimensions

    local scaleFactor = math.min(displayWidth / referenceWidth, displayHeight / referenceHeight)

    local fontSize = 38 * scaleFactor  -- Adjust the font size based on the scale factor

    -- Create fonts with specified filter mode
    font = love.graphics.newFont("assets/font/handy-andy.otf", fontSize)
    font:setFilter("linear", "linear")  -- Set filter mode to nearest for sharp edges

    tinyFont = love.graphics.newFont("assets/font/handy-andy.otf", fontSize * 0.5)
    tinyFont:setFilter("linear", "linear")  -- Set filter mode to nearest for sharp edges

    smallerFont = love.graphics.newFont("assets/font/handy-andy.otf", fontSize * 0.8)
    smallerFont:setFilter("linear", "linear")  -- Set filter mode to nearest for sharp edges

    largerFont = love.graphics.newFont("assets/font/handy-andy.otf", fontSize * 1.3)
    largerFont:setFilter("linear", "linear")  -- Set filter mode to nearest for sharp edges

    love.graphics.setFont(font)  -- Set the default font
end

-------------------------------------------------------------------------------------------
-- SETTINGS LIST --------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
local resolutionOptions = {
    "1920x1152", "1920x1080", "1600x900", "1280x720", "720x720", 
    "960x544", "854x480", "640x480", "480x320"
}

local bitrateOptions = {
    10000, 9000, 8000, 7000, 6000, 5000, 4500, 4000, 3500, 3000,
    2500, 2000, 1500, 1000, 500
}

local framerateOptions = {
    144, 120, 100, 90, 75, 60, 50, 45, 40, 30, 24, 20
}

local codecOptions = {
    "auto", "h264", "h265"
}

local remoteOptions = {
    "auto", "yes", "no"
}

local sfxOptions = {
    "On", "Off"
}

local musicOptions = {
    "Off", "Beik Poel: En Aften Ved Svanefossen", 
	"Tekkenfede: PortMaster", 
	"Kevin macLeod: Space Jazz",
	"Kevin macLeod: Lobby Time",
	"Kevin macLeod: Cottages",
}

local themeOptions = {
    "Moonlight", "Sunshine", "Kepler-62f", "???",
}

-------------------------------------------------------------------------------------------
-- RESOURCE LOADING -----------------------------------------------------------------------
-------------------------------------------------------------------------------------------
local splashlib = require("splash")  -- Assuming "splash.lua" is the correct module name
local splash -- Declare the splash screen variable globally
local fadeParams = {
    fadeAlpha = 1,
    fadeDurationFrames = 20,
    fadeTimer = 0,
    fadeType = "in", -- can be "in" or "out"
    fadeFinished = false
}

function love.load()
    setupWindow()
    setupFonts()
    loadBackground()
    initializeColors()
    loadSettings()
    loadMusic()

    -- Initialize the splash screen with current window dimensions
    local width, height = love.graphics.getDimensions()
    initializeSplashScreen(width, height)

    -- Initialize fade parameters for fade-in effect
    fadeParams.fadeAlpha = 1
    fadeParams.fadeDurationFrames = 20
    fadeParams.fadeTimer = 0
    fadeParams.fadeType = "in"  -- Set initial fade type
    fadeParams.fadeFinished = false
end

-- Function to recall the resolution after screen is set to fullscreen
function love.resize(w, h)
    -- Initialize or update the splash screen with the new dimensions
    initializeSplashScreen(w, h)
end

function initializeSplashScreen(width, height)
    -- Configure the splash screen
    local splashConfig = {
        background = {0, 0, 0},  -- Black background
    }

    -- Initialize or update the splash screen
    splash = splashlib(splashConfig, width, height)
end

function love.keypressed(key)
    -- Handle keyboard input
    if splash and key == "space" then
        splash:skip()
    end
end

function love.gamepadpressed(joystick, button)
    -- Handle gamepad input
    if splash and button == "b" then  -- Adjust "a" to the specific button you want to use
        splash:skip()
    end
end

-------------------------------------------------------------------------------------------
-- DRAW ORDER -----------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
function love.draw()
    -- Draw the splash screen if it exists and is not done
    if splash and not splash.done then
        splash:draw()
    else
        -- Draw the background
        drawBackground()

        -- Draw other elements after the splash screen is done
        drawMenu()
        drawContent()
        if isNumberPadActive then
            drawNumberPad()
        end
        drawClock()  -- Draw the clock at the middle top of the screen

        -- Determine which fade effect to apply
        if fadeParams.fadeType == "in" then
            fadeScreenIn(fadeParams)
        elseif fadeParams.fadeType == "out" then
            fadeScreenOut(fadeParams)
        end
    end
end

-------------------------------------------------------------------------------------------
-- INPUT HANDLING -------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
local inputCooldown = 0.2
local timeSinceLastInput = 0
local escapePressed = false
local gamepadAPressed = false

-- Main input handler
function handleInput()
    local gamepad = love.joystick.getJoysticks()[1]

    if selectedMenu == "settingsMenu" then
        handleSettingsMenuInput(gamepad)
    else
        handleDefaultMenuInput(gamepad)
    end
end

-- Settings menu input handler
function handleSettingsMenuInput(gamepad)
    if love.keyboard.isDown("up") or (gamepad and gamepad:isGamepadDown("dpup")) then
        scrollSettingsMenu(-1)
        playUISound("up")  -- Play up sound for upward movement
    elseif love.keyboard.isDown("down") or (gamepad and gamepad:isGamepadDown("dpdown")) then
        scrollSettingsMenu(1)
        playUISound("down")  -- Play down sound for downward movement
    elseif love.keyboard.isDown("left") or (gamepad and gamepad:isGamepadDown("dpleft")) then
        selectPreviousOption()
        playUISound("side")  -- Play side sound for leftward movement
    elseif love.keyboard.isDown("right") or (gamepad and gamepad:isGamepadDown("dpright")) then
        selectNextOption()
        playUISound("side")  -- Play side sound for rightward movement
    elseif love.keyboard.isDown("escape") or (gamepad and gamepad:isGamepadDown("b")) then  -- Switched to 'b' for back action
        handleBackNavigation()
    end
end

-- Scroll settings menu
function scrollSettingsMenu(direction)
    if selectedOption == 1 then
        scrollResolutions(direction)
    elseif selectedOption == 2 then
        scrollBitrate(direction)
    elseif selectedOption == 3 then
        scrollFramerate(direction)
    elseif selectedOption == 4 then
        scrollCodec(direction)
    elseif selectedOption == 5 then
        scrollRemote(direction)  
    elseif selectedOption == 6 then
        scrollSfx(direction)
    elseif selectedOption == 7 then
        scrollMusic(direction)
    elseif selectedOption == 8 then
        scrollTheme(direction)
    end
    timeSinceLastInput = 0
end


-- Select previous option
function selectPreviousOption()
    selectedOption = selectedOption - 1
    if selectedOption < 1 then
        selectedOption = #menus[selectedMenu]
    end
    timeSinceLastInput = 0
end

-- Select next option
function selectNextOption()
    selectedOption = selectedOption + 1
    if selectedOption > #menus[selectedMenu] then
        selectedOption = 1
    end
    timeSinceLastInput = 0
end

-- Default menu input handler
function handleDefaultMenuInput(gamepad)
    if love.keyboard.isDown("left") or (gamepad and gamepad:isGamepadDown("dpleft")) then
        selectPreviousOption()
        playUISound("side")  -- Play side sound for leftward movement
    elseif love.keyboard.isDown("right") or (gamepad and gamepad:isGamepadDown("dpright")) then
        selectNextOption()
        playUISound("side")  -- Play side sound for rightward movement
    elseif love.keyboard.isDown("return") or (gamepad and gamepad:isGamepadDown("a")) then  -- Switched to 'a' for selection action
        handleSelection()
        playUISound("enter")  -- Play enter sound for selection
    elseif love.keyboard.isDown("escape") and not escapePressed then
        escapePressed = true
        handleBackNavigation()
        playUISound("back")  -- Play back sound for back action
    elseif not love.keyboard.isDown("escape") then
        escapePressed = false
    end

    if gamepad and gamepad:isGamepadDown("b") then  -- Switched to 'b' for back action
        if not gamepadAPressed then
            handleBackNavigation()
            playUISound("back")  -- Play back sound for back action
        end
        gamepadAPressed = true
    else
        gamepadAPressed = false
    end
end

-- Handle back navigation
function handleBackNavigation()
    if selectedMenu == "mainMenu" then
        -- Exit the game or do nothing
    else
        selectedMenu = "mainMenu"
        selectedOption = 2  -- Default to "Play" option in main menu
        updateCurrentColors()
    end
end

-- Handle selection based on current menu
function handleSelection()
    timeSinceLastInput = 0

    if selectedMenu == "mainMenu" then
        handleMainMenuSelection()
    elseif selectedMenu == "settingsMenu" then
        handleSettingsMenuSelection()
    elseif selectedMenu == "connectMenu" then
        handleConnectMenuSelection()
    elseif selectedMenu == "playMenu" then
        handlePlayMenuSelection()
    end
end

-- Handle selection in the main menu
function handleMainMenuSelection()
    if selectedOption == 1 then
        -- Open settings menu
        selectedMenu = "settingsMenu"
        selectedOption = 2
    elseif selectedOption == 2 then
        -- Start game
        selectedMenu = "playMenu"
        selectedOption = 2
    elseif selectedOption == 3 then
        -- Connect to PC
        selectedMenu = "connectMenu"
        selectedOption = 1
    end
    updateCurrentColors()
end

-- numpad input handler
numberPad = {
    "1", "2", "3",
    "4", "5", "6",
    "7", "8", "9",
    ".", "0", "-",
	"Back", ":", "Done" 
}
function handleNumberPadInput()
    if not numberPad or #numberPad == 0 then return end

    local gamepad = love.joystick.getJoysticks()[1]

    if love.keyboard.isDown("up") or (gamepad and gamepad:isGamepadDown("dpup")) then
        numberPadSelection = numberPadSelection - 3
        if numberPadSelection < 1 then numberPadSelection = #numberPad end
        timeSinceLastInput = 0
    elseif love.keyboard.isDown("down") or (gamepad and gamepad:isGamepadDown("dpdown")) then
        numberPadSelection = numberPadSelection + 3
        if numberPadSelection > #numberPad then numberPadSelection = numberPadSelection % 3 end
        timeSinceLastInput = 0
    elseif love.keyboard.isDown("left") or (gamepad and gamepad:isGamepadDown("dpleft")) then
        numberPadSelection = numberPadSelection - 1
        if numberPadSelection < 1 then numberPadSelection = #numberPad end
        timeSinceLastInput = 0
    elseif love.keyboard.isDown("right") or (gamepad and gamepad:isGamepadDown("dpright")) then
        numberPadSelection = numberPadSelection + 1
        if numberPadSelection > #numberPad then numberPadSelection = 1 end
        timeSinceLastInput = 0
    elseif (love.keyboard.isDown("return") or (gamepad and gamepad:isGamepadDown("b"))) and not isNumberPadActive then
        isNumberPadActive = true
        timeSinceLastInput = 0
    elseif love.keyboard.isDown("escape") or (gamepad and gamepad:isGamepadDown("b")) and isNumberPadActive then
        isNumberPadActive = false
        saveIPAddress(ipAddress)
        timeSinceLastInput = 0
    elseif (gamepad and gamepad:isGamepadDown("start")) and not isNumberPadActive then
        isNumberPadActive = true
        timeSinceLastInput = 0
    elseif (gamepad and gamepad:isGamepadDown("back")) and isNumberPadActive then
        isNumberPadActive = false
        saveIPAddress(ipAddress)
        timeSinceLastInput = 0
    elseif (love.keyboard.isDown("return") or (gamepad and gamepad:isGamepadDown("a"))) and isNumberPadActive then
        handleNumberPadSelection()
        timeSinceLastInput = 0
    end
end

-- Handle selection in the number pad
function handleNumberPadSelection()
    if numberPad[numberPadSelection] ~= "Done" then
        if numberPad[numberPadSelection] == "Back" then
            ipAddress = string.sub(ipAddress, 1, -2)
        elseif numberPad[numberPadSelection] == "Clear" then
            ipAddress = ""
        else
            ipAddress = ipAddress .. numberPad[numberPadSelection]
        end
    else
        isNumberPadActive = false
        saveIPAddress(ipAddress)
    end
end

-------------------------------------------------------------------------------------------
-- CONNECT MENU ---------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
local appsFileName = "conf/apps.txt"
local pairFileName = "conf/pair.txt"  -- Added pair file name
local ipFilePath = "conf/ip.txt"
local settingsFilePath = "conf/settings.txt"
local hasReloadedContent = false  -- Track whether the command has been executed




-- Function to read all app names from apps.txt
local function readAppsFromFile(filename)
    local apps = {}
    local file = io.open(filename, "r")
    if file then
        for line in file:lines() do
            local appName = line:match("%d+%.%s(.+)")
            if appName then
                table.insert(apps, appName)
            end
        end
        file:close()
    else
        print("Could not open file " .. filename)
    end
    return apps
end

-- just to be sure
menus.playMenu = readAppsFromFile(appsFileName)

function handleConnectMenuSelection()
    if selectedOption == 2 then
        isNumberPadActive = true
        numberPadSelection = 1
        timeSinceLastInput = 0
    else
        -- Read IP address from ip.txt
        local ipFile = io.open(ipFilePath, "r")  -- Adjusted IP file path
        local ipAddress = ""
        if ipFile then
            ipAddress = ipFile:read("*all")
            ipFile:close()
        else
            print("Error: Could not read IP address from ip.txt")
            return  -- Exit the function if IP reading fails
        end
        
        -- Trim any leading or trailing whitespace
        ipAddress = ipAddress:match("^%s*(.-)%s*$")

        -- Construct the command based on the selected option and the read IP address
        local command
        if selectedOption == 1 then
            command = "moonlight pair " .. ipAddress
        elseif selectedOption == 3 then
            command = "moonlight list " .. ipAddress
        end

        -- Execute the command asynchronously and save its output
        coroutineThread = coroutine.create(executeCommandAndSaveOutput)
        coroutine.resume(coroutineThread, command, selectedOption == 1 and pairFileName or appsFileName)
    end
end

function executeCommandAndSaveOutput(command, fileName)
    local currentDir = love.filesystem.getSourceBaseDirectory()
    local outputFileName = fileName
    local keydirOption = string.format("-keydir %s/keys", currentDir)  -- Option to add

    -- Construct the full command including the keydir option
    local fullCommand = string.format("LD_LIBRARY_PATH=%s/moonlight/libs:/usr/lib/compat %s/moonlight/%s %s > %s 2>&1 &", currentDir, currentDir, command, keydirOption, outputFileName)

    -- Execute the command in the background
    os.execute(fullCommand)

    -- Update the flag to indicate that content reloading has started
    hasReloadedContent = true
    messageStartTime = love.timer.getTime()  -- Reset message start time

    -- Reload the apps list
    menus.playMenu = readAppsFromFile(appsFileName)
end



-- Function to draw the content of apps.txt or pair.txt on the screen based on the selected option
function drawContent()
    -- Check if the selected option has changed since the last draw
    if selectedOption ~= lastSelectedOption then
        hasReloadedContent = false  -- Reset the flag
        lastSelectedOption = selectedOption  -- Update last selected option
    end
    
    -- Only draw if the content has been reloaded
    if hasReloadedContent then
        -- Calculate the position and dimensions for the black rectangle
        local rectWidth = love.graphics.getWidth() * 0.7
        local rectHeight = love.graphics.getHeight() * 0.5
        local rectX = (love.graphics.getWidth() - rectWidth) / 2
        local rectY = (love.graphics.getHeight() - rectHeight) / 4
        local cornerRadius = 20  -- Radius for rounding corners
        
        -- Draw a semi-transparent black rectangle with rounded corners
        love.graphics.setColor(0, 0, 0, 0.8)  -- Adjust alpha value for less transparency
        love.graphics.rectangle("fill", rectX, rectY, rectWidth, rectHeight, cornerRadius, cornerRadius)
        
        -- Determine which file to read based on the selected option
        local fileName = selectedOption == 1 and pairFileName or appsFileName
        
        -- Check if the file exists and read its content
        local file = io.open(fileName, "r")
        if file then
            local content = file:read("*a")
            file:close()
            
            -- Set color
            love.graphics.setColor(1, 1, 1, 1)
       
            -- Draw the content
            love.graphics.printf(content, rectX + 25, rectY + 25, rectWidth - 50, "center")
			
		 menus.playMenu = readAppsFromFile(appsFileName)
        end
    end
end


-- Function to save the IP address to a file
function saveIPAddress(ipAddress)
    local file = io.open(ipFilePath, "w")
    if file then
        file:write(ipAddress)
        file:close()
    else
        print("Error: Could not open file for writing.")
    end
end


-- Function to read the IP address from a file
function readIPAddress()
    local file = io.open(ipFilePath, "r")
    local ipAddress = ""
    if file then
        ipAddress = file:read("*all")
        file:close()
    else
        print("Error: Could not open file for reading.")
    end
    return ipAddress
end

numberPadSelection = 1
ipAddress = readIPAddress() -- Initialize the IP address string
isNumberPadActive = false
timeSinceLastInput = 0

function drawNumberPad()
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local buttonWidth = windowWidth / 10  -- Adjusted to account for spacing
    local buttonHeight = windowHeight / 16  -- Adjusted to account for spacing
    local buttonSpacing = windowWidth / 100  -- Adjust the spacing as needed
    local padX = (windowWidth - (3 * buttonWidth + 2 * buttonSpacing)) / 2
    local padY = (windowHeight - (5 * buttonHeight + 4 * buttonSpacing)) / 3   -- Adjusting the starting Y position
    local cornerRadius = 5  -- Radius for rounding corners
    local borderThickness = 2  -- Thickness for the border
    local backgroundMargin = 4  -- Margin between buttons and background

    -- Calculate background dimensions with margin
    local backgroundWidth = 3 * buttonWidth + 2 * buttonSpacing + 2 * backgroundMargin
    local backgroundHeight = 5 * buttonHeight + 4 * buttonSpacing + 2 * backgroundMargin
    local backgroundX = padX - backgroundMargin
    local backgroundY = padY - backgroundMargin

    -- Draw white border around the semi-transparent background
    love.graphics.setColor(1, 1, 1, 1)  -- White color for the border
    love.graphics.setLineWidth(borderThickness)
    love.graphics.rectangle("line", backgroundX - borderThickness / 2, backgroundY - borderThickness / 2, backgroundWidth + borderThickness, backgroundHeight + borderThickness, cornerRadius, cornerRadius)

    -- Draw semi-transparent background
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", backgroundX, backgroundY, backgroundWidth, backgroundHeight, cornerRadius, cornerRadius)

    -- Draw light gray grid lines to indicate button positions
    love.graphics.setColor(0.7, 0.7, 0.7, 1)  -- Light gray color
    love.graphics.setLineWidth(1)

    -- Draw vertical lines
    for i = 1, 2 do
        local x = padX + i * (buttonWidth + buttonSpacing) - buttonSpacing / 2
        love.graphics.line(x, padY, x, padY + 5 * buttonHeight + 4 * buttonSpacing)
    end

    -- Draw horizontal lines
    for i = 1, 4 do
        local y = padY + i * (buttonHeight + buttonSpacing) - buttonSpacing / 2
        love.graphics.line(padX, y, padX + 3 * buttonWidth + 2 * buttonSpacing, y)
    end

    -- Draw individual buttons
    for i, button in ipairs(numberPad) do
        local x = padX + ((i - 1) % 3) * (buttonWidth + buttonSpacing)
        local y = padY + math.floor((i - 1) / 3) * (buttonHeight + buttonSpacing)
        
        -- Draw button background if selected
        if i == numberPadSelection then
            love.graphics.setColor(0.7, 0.7, 0.7, 0.4)  -- Semi-transparent white color
            love.graphics.rectangle("fill", x, y, buttonWidth, buttonHeight, cornerRadius, cornerRadius)
        end
        
        -- Draw button text
        love.graphics.setColor(1, 1, 1, 1)  -- White color for the text
		love.graphics.setFont(smallerFont)
        love.graphics.printf(button, x, y + buttonHeight / 4, buttonWidth, "center")
    end

    -- Draw IP Address text
    love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setFont(largerFont)
    local textOffset = buttonHeight * 1.5  -- Adjust the text offset as needed
    love.graphics.printf("IP: " .. ipAddress, 0, backgroundY - textOffset, windowWidth, "center")
end


-------------------------------------------------------------------------------------------
-- SETTINGS MENU --------------------------------------------------------------------------
-------------------------------------------------------------------------------------------

-- Scroll through resolution options
function scrollResolutions(direction)
    local resolutionCount = #resolutionOptions
    selectedResolutionIndex = selectedResolutionIndex + direction
    if selectedResolutionIndex < 1 then
        selectedResolutionIndex = resolutionCount
    elseif selectedResolutionIndex > resolutionCount then
        selectedResolutionIndex = 1
    end
    timeSinceLastInput = 0

    -- Save settings to config file after selecting resolution
    saveSettings()
end

-- Scroll through bitrate options
function scrollBitrate(direction)
    local bitrateCount = #bitrateOptions
    selectedBitrateIndex = selectedBitrateIndex + direction  -- Adjusted the direction here
    if selectedBitrateIndex < 1 then
        selectedBitrateIndex = bitrateCount
    elseif selectedBitrateIndex > bitrateCount then
        selectedBitrateIndex = 1
    end
    timeSinceLastInput = 0

    -- Save settings to config file after selecting bitrate
    saveSettings()
end



-- Scroll through framerate options
function scrollFramerate(direction)
    local framerateCount = #framerateOptions
    selectedFramerateIndex = selectedFramerateIndex + direction
    if selectedFramerateIndex < 1 then
        selectedFramerateIndex = framerateCount
    elseif selectedFramerateIndex > framerateCount then
        selectedFramerateIndex = 1
    end
    timeSinceLastInput = 0

    -- Save settings to config file after selecting framerate
    saveSettings()
end

-- Scroll through codec options
function scrollCodec(direction)
    local codecCount = #codecOptions
    selectedCodecIndex = selectedCodecIndex + direction
    if selectedCodecIndex < 1 then
        selectedCodecIndex = codecCount
    elseif selectedCodecIndex > codecCount then
        selectedCodecIndex = 1
    end
    timeSinceLastInput = 0

    -- Save settings to config file after selecting codec
    saveSettings()
end

-- Scroll through remote options
function scrollRemote(direction)
    local remoteCount = #remoteOptions
    selectedRemoteIndex = selectedRemoteIndex + direction
    if selectedRemoteIndex < 1 then
        selectedRemoteIndex = remoteCount
    elseif selectedRemoteIndex > remoteCount then
        selectedRemoteIndex = 1
    end
    timeSinceLastInput = 0

    -- Save settings to config file after selecting remote
    saveSettings()
end



-- Scroll through sfx options
function scrollSfx(direction)
    local sfxCount = #sfxOptions
    selectedSfxIndex = selectedSfxIndex + direction
    if selectedSfxIndex < 1 then
        selectedSfxIndex = sfxCount
    elseif selectedSfxIndex > sfxCount then
        selectedSfxIndex = 1
    end
    timeSinceLastInput = 0

    -- Save settings to config file after selecting sfx
    saveSettings()
end



-- Scroll through music options
function scrollMusic(direction)
    local musicCount = #musicOptions
    selectedMusicIndex = selectedMusicIndex + direction
    if selectedMusicIndex < 1 then
        selectedMusicIndex = musicCount
    elseif selectedMusicIndex > musicCount then
        selectedMusicIndex = 1
    end
    timeSinceLastInput = 0

    -- Save settings to config file after selecting music
    saveSettings()
	-- Update background based on the new theme
    loadMusic()
end

-- Function to scroll through theme options
function scrollTheme(direction)
    local themeCount = #themeOptions
    selectedThemeIndex = selectedThemeIndex + direction
    if selectedThemeIndex < 1 then
        selectedThemeIndex = themeCount
    elseif selectedThemeIndex > themeCount then
        selectedThemeIndex = 1
    end
    timeSinceLastInput = 0

    -- Save settings to settings file after selecting theme
    saveSettings()
    
    -- Update background based on the new theme
    loadBackground(themeOptions[selectedThemeIndex])
end

function saveSettings()
    local file = io.open(settingsFilePath, "w")  -- Open file for writing
    if file then
        file:write(selectedResolutionIndex .. "\n")
        file:write(selectedBitrateIndex .. "\n")
        file:write(selectedFramerateIndex .. "\n")
        file:write(selectedCodecIndex .. "\n") 
        file:write(selectedRemoteIndex .. "\n") 
        file:write(selectedSfxIndex .. "\n")
        file:write(selectedMusicIndex .. "\n")
        file:write(selectedThemeIndex .. "\n")
        file:close()  -- Close the file
    else
        print("Error: Could not open settings file for writing")
    end
end


function loadSettings()
    local file = io.open(settingsFilePath, "r")  -- Open file for reading
    if file then
        selectedResolutionIndex = tonumber(file:read("*l")) or selectedResolutionIndex
        selectedBitrateIndex = tonumber(file:read("*l")) or selectedBitrateIndex
        selectedFramerateIndex = tonumber(file:read("*l")) or selectedFramerateIndex
        selectedCodecIndex = tonumber(file:read("*l")) or selectedCodecIndex  
        selectedRemoteIndex = tonumber(file:read("*l")) or selectedRemoteIndex  
        selectedSfxIndex = tonumber(file:read("*l")) or selectedSfxIndex
        selectedMusicIndex = tonumber(file:read("*l")) or selectedMusicIndex
        selectedThemeIndex = tonumber(file:read("*l")) or selectedThemeIndex
        file:close()  -- Close the file
        
        -- Load background based on selected theme
        loadBackground(themeOptions[selectedThemeIndex])
    else
        print("Error: Could not open settings file for reading")
    end
end



-- Update currentColors array for the selected menu
function updateCurrentColors()
    currentColors = {}
    for i = 1, #menus[selectedMenu] do
        currentColors[i] = {unpack(normalColor)}
    end
end

-- Smoothly update colors for all menu options
function updateColors(dt)
    if selectedMenu ~= "settingsMenu" and selectedMenu ~= "playMenu" then
        for i = 1, #menus[selectedMenu] do
            local targetColor = normalColor
            if i == selectedOption then
                targetColor = selectedColor
            end

            for j = 1, 4 do
                if currentColors[i][j] < targetColor[j] then
                    currentColors[i][j] = math.min(currentColors[i][j] + transitionSpeed * dt, targetColor[j])
                elseif currentColors[i][j] > targetColor[j] then
                    currentColors[i][j] = math.max(currentColors[i][j] - transitionSpeed * dt, targetColor[j])
                end
            end
        end
    else
        -- For "settingsMenu" and "playMenu", instantly transition to the target color
        for i = 1, #menus[selectedMenu] do
            if i == selectedOption then
                currentColors[i] = selectedColor
            else
                currentColors[i] = normalColor
            end
        end
    end
end


-- Initialize currentColors with normalColor for all menu options
function initializeColors()
    for i = 1, #menus[selectedMenu] do
        currentColors[i] = {unpack(normalColor)}
    end
end
-------------------------------------------------------------------------------------------
-- DRAW FUNC MENU -------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-- Define a variable to store the percentage of the display height for menu positioning
local menuPositionPercentage = 0.85

function drawMenu()
    love.graphics.setColor(1, 1, 1, 1)  -- Reset color to white

    local windowHeight = love.graphics.getHeight()  -- Get the height of the window
    local windowWidth = love.graphics.getWidth()  -- Get the width of the window
    local optionY = windowHeight * menuPositionPercentage  -- Calculate the vertical position based on the percentage
    local optionSpacing = windowWidth / #menus[selectedMenu]  -- Calculate the spacing between options

    -- Draw the main menu options (ignore "settingsMenu" and "playMenu" when they are the selected menu)
    if selectedMenu ~= "settingsMenu" and selectedMenu ~= "playMenu" then
        for i, option in ipairs(menus[selectedMenu]) do
            if option == "Settings" or option == "Play" or option == "Connect" then
                love.graphics.setFont(largerFont)  -- Use larger font for main menu options
                love.graphics.setColor(currentColors[i])
                love.graphics.print(option, (i - 1) * optionSpacing + (optionSpacing / 2) - largerFont:getWidth(option) / 2, optionY)
                love.graphics.setFont(font)  -- Reset font to default
            else
                love.graphics.setColor(currentColors[i])
                love.graphics.print(option, (i - 1) * optionSpacing + (optionSpacing / 2) - font:getWidth(option) / 2, optionY)
            end
        end
    end

    -- Draw line under "Settings", "Play", and "Connect" menus
    if selectedMenu ~= "mainMenu" then
        local lineY = optionY + font:getHeight() + 3  -- Calculate the vertical position of the line
        love.graphics.setColor(1, 1, 1)  -- Set line color to white

        -- Scale the line thickness based on the window height
        local lineThickness = windowWidth * 0.002  -- Adjust the 0.005 factor as needed
        love.graphics.setLineWidth(lineThickness)  -- Set line thickness

        love.graphics.line(0, lineY, windowWidth, lineY)  -- Draw line
    end

    -- Draw the IP address under the "IP Address" option in the "Connect" menu
    if selectedMenu == "connectMenu" then
        local offsetY = optionY + font:getHeight() + 10  -- Calculate the offset for other options
        local ipAddressText = readIPAddress()  -- Get the IP address from the file
        love.graphics.setColor(normalColor)
        love.graphics.print(ipAddressText, (2 - 1) * optionSpacing + (optionSpacing / 2) - font:getWidth(ipAddressText) / 2, offsetY)
    end

    -- Draw the Settings and Play menu content (dynamic)
    if selectedMenu == "settingsMenu" or selectedMenu == "playMenu" then
        drawMovingMenu() -- Call a separate function to handle settings-specific and play-specific drawing
    end

    love.graphics.setColor(1, 1, 1, 1) -- Reset color to white
end


function drawMovingMenu()
    love.graphics.setColor(1, 1, 1, 1)  -- Reset color to white
    local windowHeight = love.graphics.getHeight()  -- Get the height of the window
    local windowWidth = love.graphics.getWidth()  -- Get the width of the window
    local optionY = windowHeight * menuPositionPercentage  -- Calculate the vertical position based on the percentage

    -- Calculate the number of visible options (maximum 3)
    local visibleOptions = 3  -- Always display 3 options with the selected option in the middle
    local optionSpacing = windowWidth / visibleOptions  -- Calculate the spacing between options

    -- Calculate the index of the selected option
    local selectedOptionIndex = selectedOption

    -- Draw the menu options
    for i = -1, 1 do
        local optionIndex = selectedOptionIndex + i
        if optionIndex > 0 and optionIndex <= #menus[selectedMenu] then
            local option = menus[selectedMenu][optionIndex]
            local optionX = (i + 1) * optionSpacing + (optionSpacing / 2) - font:getWidth(option) / 2
            love.graphics.setColor(currentColors[optionIndex])
            love.graphics.print(option, optionX, optionY)
        end
    end

    -- Draw the selected options under the "Settings" and "Play" menus
    if selectedMenu == "settingsMenu" then
        local offsetY = optionY + font:getHeight() + 10  -- Calculate the offset for other options

        -- Adjust the X position of each setting to be in the center
        local optionXCenter = windowWidth / 2

        -- Draw all the options
        for i = 1, #menus[selectedMenu] do
            local optionX = (i - (selectedOption - math.floor(visibleOptions / 2))) * optionSpacing + (optionSpacing / 2)

            if i == 1 then  -- Resolutions
                local resolutionOptionX = optionX - font:getWidth(resolutionOptions[selectedResolutionIndex]) / 2
                love.graphics.setColor(normalColor)
                love.graphics.print(resolutionOptions[selectedResolutionIndex], resolutionOptionX, offsetY)
            elseif i == 2 then  -- Bitrate
                local bitrateOptionX = optionX - font:getWidth(bitrateOptions[selectedBitrateIndex]) / 2
                love.graphics.setColor(normalColor)
                love.graphics.print(bitrateOptions[selectedBitrateIndex], bitrateOptionX, offsetY)
            elseif i == 3 then  -- Framerate
                local framerateOptionX = optionX - font:getWidth(framerateOptions[selectedFramerateIndex]) / 2
                love.graphics.setColor(normalColor)
                love.graphics.print(framerateOptions[selectedFramerateIndex], framerateOptionX, offsetY)
            elseif i == 4 then  -- Codec
                local codecOptionX = optionX - font:getWidth(codecOptions[selectedCodecIndex]) / 2
                love.graphics.setColor(normalColor)
                love.graphics.print(codecOptions[selectedCodecIndex], codecOptionX, offsetY)
            elseif i == 5 then  -- Remote
                local remoteOptionX = optionX - font:getWidth(remoteOptions[selectedRemoteIndex]) / 2
                love.graphics.setColor(normalColor)
                love.graphics.print(remoteOptions[selectedRemoteIndex], remoteOptionX, offsetY)
            elseif i == 6 then  -- Sfx
                local sfxOptionX = optionX - font:getWidth(sfxOptions[selectedSfxIndex]) / 2
                love.graphics.setColor(normalColor)
                love.graphics.print(sfxOptions[selectedSfxIndex], sfxOptionX, offsetY)
            elseif i == 7 then  -- Music
                local musicOption = musicOptions[selectedMusicIndex]
                local maxLineLength = math.floor(#musicOption / 2)
                local splitIndex = maxLineLength + 5

                -- Find the last space before the maximum line length to split the text at a whole word
                while splitIndex > 0 and musicOption:sub(splitIndex, splitIndex) ~= " " do
                    splitIndex = splitIndex - 1
                end

                -- If no space found, use the full text on the first line
                if splitIndex == 0 then
                    splitIndex = #musicOption
                end

                -- Split the music option into two lines
                local line1 = musicOption:sub(1, splitIndex)
                local line2 = musicOption:sub(splitIndex + 1)

                -- Calculate the starting y-coordinate to center the broken-up text vertically under the menu option
                local line1X = optionX - font:getWidth(line1) / 2
                love.graphics.setColor(normalColor)
                love.graphics.print(line1, line1X, offsetY)

                -- Draw the second line if it exists and has content
                if line2 and line2:gsub("%s+", "") ~= "" then
                    local line2X = optionX - font:getWidth(line2) / 2
                    love.graphics.print(line2, line2X, offsetY + font:getHeight())
                end

            elseif i == 8 then  -- Theme
                local themeOptionX = optionX - font:getWidth(themeOptions[selectedThemeIndex]) / 2
                love.graphics.setColor(normalColor)
                love.graphics.print(themeOptions[selectedThemeIndex], themeOptionX, offsetY)
            end
        end
    elseif selectedMenu == "playMenu" then
        -- Draw play menu specific options here
        -- You can customize the drawing logic for playMenu similar to the settingsMenu
    end
end



-------------------------------------------------------------------------------------------
-- AUDIO ----------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------

-- Load background music
function loadMusic()
    -- Stop the background music if it's playing
    if backgroundMusic and backgroundMusic:isPlaying() then
        love.audio.stop(backgroundMusic)
    end

    -- Reload music only when the music option changes
    if selectedMusicIndex ~= previousMusicIndex then
        if selectedMusicIndex == 1 then
            backgroundMusic = nil  -- No music for "Off" option
        elseif selectedMusicIndex == 2 then
            backgroundMusic = love.audio.newSource("assets/audio/music/svanefossen.ogg", "stream")
        elseif selectedMusicIndex == 3 then
            backgroundMusic = love.audio.newSource("assets/audio/music/portmaster.ogg", "stream")
        elseif selectedMusicIndex == 4 then
            backgroundMusic = love.audio.newSource("assets/audio/music/spacejazz.ogg", "stream")
		elseif selectedMusicIndex == 5 then
            backgroundMusic = love.audio.newSource("assets/audio/music/lobbytime.ogg", "stream")
        elseif selectedMusicIndex == 6 then
            backgroundMusic = love.audio.newSource("assets/audio/music/cottages.ogg", "stream")
        end

        -- Set the music to loop and play it if it is not nil
        if backgroundMusic then
            backgroundMusic:setLooping(true)
            love.audio.play(backgroundMusic)
        end

        -- Update previous index to current index
        previousMusicIndex = selectedMusicIndex
    end
end

function fadeOutBackgroundMusic()
    local fadeDuration = 0.5  -- Fade duration in seconds

    if backgroundMusic and backgroundMusic:isPlaying() then
        local initialVolume = backgroundMusic:getVolume()

        -- Perform gradual volume reduction
        local startTime = love.timer.getTime()
        local elapsedTime = 0

        while elapsedTime < fadeDuration do
            elapsedTime = love.timer.getTime() - startTime
            local progress = elapsedTime / fadeDuration
            local currentVolume = initialVolume * (1 - progress)

            backgroundMusic:setVolume(currentVolume)
            love.timer.sleep(0.01)  -- Adjust sleep time for smoother effect
        end

        love.audio.stop(backgroundMusic)
    end
end


	
-- Function to play a UI sound based on the action type
function playUISound(actionType)
    local soundPath = nil

    -- Determine which sound to play based on actionType
    if actionType == "up" then
        soundPath = "assets/audio/fx/up.ogg"
    elseif actionType == "down" then
        soundPath = "assets/audio/fx/down.ogg"
    elseif actionType == "back" then
        soundPath = "assets/audio/fx/back.ogg"
    elseif actionType == "enter" then
        soundPath = "assets/audio/fx/enter.ogg"
    elseif actionType == "numpad" then
        soundPath = "assets/audio/fx/numpad.ogg"
    elseif actionType == "side" then
        soundPath = "assets/audio/fx/side.ogg"
    elseif actionType == "select" then
        soundPath = "assets/audio/fx/select.ogg"
    end

    -- Check if soundPath is valid and play the sound only if SFX is enabled
    if soundPath and selectedSfxIndex == 1 then
        love.audio.play(love.audio.newSource(soundPath, "static"))
    end
end

-------------------------------------------------------------------------------------------
-- THEMES ---------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
math.randomseed(os.time()) -- needed for randomness

-- Variables for star animation
local starSpriteSheet
local starFrameWidth = 64
local starFrameHeight = 64
local starNumFrames = 9
local starAnimationDuration = 0.4 -- Duration for the entire animation in seconds
local starAppearInterval = math.random(2, 6) -- Initial random interval between 2 and 5 seconds
local starTimer = 0
local starPositionX, starPositionY
local starVisible = false
local starAnimationStartTime = 0

-- Background and animated sprite variables
local sky, background, animatedSpriteSheet
local spriteWidth = 80
local spriteHeight = 80
local numColumns = 25
local numRows = 25
local totalFrames = numColumns * numRows

function loadBackground(theme)
    -- Release previously loaded images
    if sky then
        sky:release()
        sky = nil
    end
    if background then
        background:release()
        background = nil
    end
    if animatedSpriteSheet then
        animatedSpriteSheet:release()
        animatedSpriteSheet = nil
    end
    
    -- Load images with nearest-neighbor filtering
    love.graphics.setDefaultFilter("nearest", "nearest")

    if theme == "Sunshine" then
        sky = love.graphics.newImage("assets/video/sunshine_sky.png")
        sky:setFilter("nearest", "nearest")
        background = love.graphics.newImage("assets/video/sunshine_background.png")
        background:setFilter("nearest", "nearest")
        animatedSpriteSheet = love.graphics.newImage("assets/video/sunshine_tiles.png")
        animatedSpriteSheet:setFilter("nearest", "nearest")
        starSpriteSheet = nil
    elseif theme == "Moonlight" then
        sky = love.graphics.newImage("assets/video/moonlight_sky.png")
        sky:setFilter("nearest", "nearest")
        background = love.graphics.newImage("assets/video/moonlight_background.png")
        background:setFilter("nearest", "nearest")
        animatedSpriteSheet = love.graphics.newImage("assets/video/moonlight_tiles.png")
        animatedSpriteSheet:setFilter("nearest", "nearest")
        starSpriteSheet = love.graphics.newImage("assets/video/star_tiles.png")
    elseif theme == "Kepler-62f" then
        sky = love.graphics.newImage("assets/video/kepler_sky.png")
        sky:setFilter("nearest", "nearest")
        animatedSpriteSheet = love.graphics.newImage("assets/video/kepler_tiles.png")
        animatedSpriteSheet:setFilter("nearest", "nearest")
		starSpriteSheet = love.graphics.newImage("assets/video/star_tiles.png")
    elseif theme == "???" then
		sky = love.graphics.newImage("assets/video/unknown_sky.png")
		sky:setFilter("nearest", "nearest")
		animatedSpriteSheet = love.graphics.newImage("assets/video/unknown_tiles.png")
        animatedSpriteSheet:setFilter("nearest", "nearest")
		starSpriteSheet = love.graphics.newImage("assets/video/star_tiles.png")
    end	
    -- Restore default filter settings
    love.graphics.setDefaultFilter("linear", "linear")
end


function updateStar(dt)
    starTimer = starTimer + dt
    
    if starTimer >= starAppearInterval then
        starTimer = starTimer - starAppearInterval
        starAppearInterval = math.random(2, 6) -- Reset interval to a new random value between 2 and 6 seconds
        starVisible = true
        
        local windowWidth, windowHeight = love.graphics.getDimensions()
        local skyScale = windowHeight / sky:getHeight()
        local starScale = skyScale
        
        -- Calculate star position ensuring it stays within visible bounds
        if selectedThemeIndex == 1 then
            -- Moonlight theme: stars spawn in the top 25% of the display
            starPositionX = math.random(starFrameWidth, windowWidth - starFrameWidth * starScale)
            starPositionY = math.random(0, windowHeight * 0.4 - starFrameHeight * starScale)
        else
            -- Other themes: stars spawn randomly across the screen
            starPositionX = math.random(starFrameWidth, windowWidth - starFrameWidth * starScale)
            starPositionY = math.random(starFrameHeight, windowHeight - starFrameHeight * starScale)
        end
        
        starAnimationStartTime = love.timer.getTime()
    end

    if starVisible and love.timer.getTime() - starAnimationStartTime >= starAnimationDuration then
        starVisible = false
    end
end

function drawBackground()
    if not sky or not animatedSpriteSheet then
        return
    end

    local windowWidth, windowHeight = love.graphics.getDimensions()

    -- Set the default filter to nearest for sharp pixel scaling
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Draw the sky layer
    local skyScale = windowHeight / sky:getHeight()
    local skyWidth = sky:getWidth() * skyScale
    local skyOffsetX = math.floor((windowWidth - skyWidth) / 2)
    love.graphics.draw(sky, math.floor(skyOffsetX), 0, 0, skyScale, skyScale)
    
    -- Draw the star sprite if visible and starSpriteSheet is not nil
    if starSpriteSheet and starVisible then
        local currentTime = love.timer.getTime()
        local starFrameIndex = math.floor((currentTime - starAnimationStartTime) / starAnimationDuration * starNumFrames) % starNumFrames
        local starQuad = love.graphics.newQuad(starFrameIndex * starFrameWidth, 0, starFrameWidth, starFrameHeight, starSpriteSheet:getDimensions())
        
        -- Calculate star position and scale based on background scaling
        local starScale = skyScale -- Use the same scale as the background
        local starX = math.floor(skyOffsetX + starPositionX)
        local starY = math.floor(starPositionY)
        
        love.graphics.draw(starSpriteSheet, starQuad, starX, starY, 0, starScale, starScale)
    end

    -- Calculate the frame index based on time for the animated sprite
    local frameIndex = math.floor(love.timer.getTime() * 30) % totalFrames

    -- Calculate the position of the animated sprite relative to the background
    local spriteScale = skyScale -- Use the same scale as the background
    local spriteX = math.floor(skyOffsetX + skyWidth - 145 * spriteScale) -- 195 pixels from the right edge (scaled)
    local spriteY = math.floor(5 * spriteScale) -- 20 pixels from the top edge (scaled)

    -- Draw the animated sprite with the same scaling as the background
    local frameX = (frameIndex % numColumns) * spriteWidth
    local frameY = math.floor(frameIndex / numColumns) * spriteHeight
    love.graphics.draw(animatedSpriteSheet, love.graphics.newQuad(frameX, frameY, spriteWidth, spriteHeight, spriteWidth * numColumns, spriteHeight * numRows), spriteX, spriteY, 0, spriteScale, spriteScale)

    -- Draw the background layer if it exists and not in Space theme
    if background then
        local backgroundScale = windowHeight / background:getHeight()
        local backgroundWidth = background:getWidth() * backgroundScale
        local backgroundOffsetX = math.floor((windowWidth - backgroundWidth) / 2)
        love.graphics.draw(background, math.floor(backgroundOffsetX), 0, 0, backgroundScale, backgroundScale)
    end
end

-------------------------------------------------------------------------------------------
-- ENDING SEQUENCE ------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-- ENDING SEQUENCE ------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-- Function to handle selection in the play menu
function handlePlayMenuSelection()
    local selectedApp = menus.playMenu[selectedOption]
    local selectedBitrate = bitrateOptions[selectedBitrateIndex]
    local selectedResolution = resolutionOptions[selectedResolutionIndex]
    local selectedFramerate = framerateOptions[selectedFramerateIndex]
    local selectedCodec = codecOptions[selectedCodecIndex]
    local selectedRemote = remoteOptions[selectedRemoteIndex]
    local selectedSfx = sfxOptions[selectedSfxIndex]

    -- Check if any of the required parameters is nil
    if selectedApp and selectedBitrate and selectedResolution and selectedFramerate and selectedCodec and selectedRemote and selectedSfx then
        writeSelectedApp(selectedApp, selectedBitrate, selectedResolution, selectedFramerate, selectedCodec, selectedRemote, selectedSfx)

        -- Fade out music smoothly before quitting
        fadeOutBackgroundMusic()

        -- Initiate fade-out effect
        fadeParams.fadeTimer = 0
        fadeParams.fadeType = "out"
        fadeParams.fadeFinished = false

        -- Define a function to check and quit after fade-out
        local function quitAfterFade()
            if fadeParams.fadeFinished then
                love.event.quit()  -- Quit LOVE2D after fade-out completes
            end
        end

        -- Update function to handle quitting after fade-out
        function love.update(dt)
            if fadeParams.fadeFinished then
                quitAfterFade()  -- Call quit function when fade-out is finished
            end
        end
    else
        -- Print an error message indicating which parameter is nil
        if not selectedApp then print("Error: Selected app is nil") end
        if not selectedBitrate then print("Error: Selected bitrate is nil") end
        if not selectedResolution then print("Error: Selected resolution is nil") end
        if not selectedFramerate then print("Error: Selected framerate is nil") end
        if not selectedCodec then print("Error: Selected codec is nil") end
        if not selectedRemote then print("Error: Selected remote is nil") end
        if not selectedSfx then print("Error: Selected sfx is nil") end
    end
end



-------------------------------------------------------------------------------------------
-- COMMAND CREATOR ------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-- Function to write the selected app name, bitrate, resolution, framerate and IP address to command.txt
function writeSelectedApp(selectedApp, bitrate, resolution, framerate, codec, remote)
    -- Split resolution string into width and height
    local width, height = resolution:match("(%d+)x(%d+)")
    
    -- Read IP address from ip.txt
    local ipFile = io.open(ipFilePath, "r")  -- Adjusted IP file path
    local ipAddress = ""
    if ipFile then
        ipAddress = ipFile:read("*all")
        ipFile:close()
    else
        print("Error: Could not read IP address from ip.txt")
        return  -- Exit the function if IP reading fails
    end
    
    
    -- Construct the command string with app name, bitrate, resolution, framerate, codec, remote, and IP address
    local command = 'stream -app "' .. selectedApp .. '" ' ..
                    '-keydir "$GAMEDIR/keys" ' ..  
                    '-bitrate ' .. bitrate .. ' ' ..
                    '-width ' .. width .. ' ' ..
                    '-height ' .. height .. ' ' ..
                    '-fps ' .. framerate .. ' ' ..
                    '-codec ' .. codec .. ' ' ..
                    '-remote ' .. remote .. ' ' ..
                    '-quitappafter ' .. ipAddress

    local file = io.open("moonlight/command.txt", "w")
    if file then
        file:write(command)
        file:close()
    else
        print("Error: Could not write to command.txt")
    end
end

-------------------------------------------------------------------------------------------
-- CLOCK ----------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-- Function to draw the clock at the middle top of the screen
function drawClock()
    local time = os.date("%H:%M")  -- Get current time in HHMM format
    
    love.graphics.setFont(font)  -- Use the smaller font
    
    local textWidth = font:getWidth(time)
    local screenWidth = love.graphics.getWidth()
    local x = (screenWidth - textWidth) / 2  -- Calculate x position to center the clock
    local y = 10  -- Set y position to top of the screen with some margin

    love.graphics.setColor(1, 1, 1, 1)  -- Set color to white
    love.graphics.print(time, x, y)

    love.graphics.setFont(font)  -- Restore the default font
end

-------------------------------------------------------------------------------------------
-- MINOR FUNCTIONS --------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-- Function to handle fade-in effect
function fadeScreenIn(params)
    params.fadeTimer = params.fadeTimer + 1
    local progress = params.fadeTimer / params.fadeDurationFrames

    params.fadeAlpha = 1 - progress

    if params.fadeTimer >= params.fadeDurationFrames then
        params.fadeAlpha = 0
        params.fadeFinished = true
    end

    love.graphics.setColor(0, 0, 0, params.fadeAlpha)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(1, 1, 1, 1)  -- Reset color to white
end

-- Function to handle fade-out effect
function fadeScreenOut(params)
    params.fadeTimer = params.fadeTimer + 1
    local progress = params.fadeTimer / params.fadeDurationFrames

    params.fadeAlpha = progress

    if params.fadeTimer >= params.fadeDurationFrames then
        params.fadeAlpha = 1
        params.fadeFinished = true
    end

    love.graphics.setColor(0, 0, 0, params.fadeAlpha)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(1, 1, 1, 1)  -- Reset color to white
end

-- Function to check for quit combinations
function checkForQuitCombination()
    -- Check if Z and X are pressed simultaneously
    if love.keyboard.isDown("z") and love.keyboard.isDown("x") then
        love.event.quit()
    end

    -- Check if rightshoulder and leftshoulder are pressed simultaneously
    local gamepad = love.joystick.getJoysticks()[1]
    if gamepad and gamepad:isGamepadDown("rightshoulder") and gamepad:isGamepadDown("leftshoulder") then
        love.event.quit()
    end
end

-------------------------------------------------------------------------------------------
-- UPDATE LOGIC ---------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-- Main update function
function love.update(dt)
	timeSinceLastInput = timeSinceLastInput + dt
    -- Check for quit combinations
    checkForQuitCombination()

    -- Update the splash screen if it's not done
    if splash and not splash.done then
        splash:update(dt)
        return
    end

    -- Transition from splash screen to main content
    if splash and splash.done and not splash.skipped then
        splash = nil
        fadeParams.fadeTimer = 0  -- Reset fade timer when splash is done
        fadeParams.fadeFinished = false
        fadeParams.fadeType = "in"  -- Set fade type to "in" for fade-in effect
    end

       -- Handle user input
		if timeSinceLastInput >= inputCooldown then
        if isNumberPadActive then
            handleNumberPadInput()
        else
            handleInput()
        end
		end

    -- Update color transitions
    updateColors(dt)

    -- Update stars (or other background elements)
    updateStar(dt)
end