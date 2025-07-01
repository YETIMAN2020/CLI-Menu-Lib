-- BIOS-style Power Monitor for CC: Tweaked
-- Jules (AI Software Engineer)

-- Configuration
local appVersion = "1.0"
local appAuthor = "Jules"
local refreshRate = 1 -- seconds

-- API Aliases
local term = term
local peripheral = peripheral
local colors = colors
local textutils = textutils
local os = os
local string = string
local math = math

-- Global variable for the monitor
local mon = term.current()

-- UI Design Parameters
local mainBgColor = colors.blue
local mainTextColor = colors.white
-- Title bar will use mainBgColor, with mainTextColor or a highlight like yellow
local titleHighlightColor = colors.white -- Or colors.yellow for more "BIOS" feel
local borderColor = colors.lightGray
local accentColor = colors.cyan
local errorColor = colors.red
local progressBarColor = colors.cyan
local progressBarBgColor = colors.black -- Or a darker gray
local progressBarChar = "█"
local progressBarEmptyChar = " " -- Use space with background color

-- Global for the energy peripheral
local energyCell = nil

local function clearScreen()
    mon.setBackgroundColor(mainBgColor)
    mon.setTextColor(mainTextColor)
    mon.clear()
    mon.setCursorPos(1, 1)
end

local function drawLayout()
    local w, h = mon.getSize()

    -- Draw border
    mon.setBackgroundColor(mainBgColor) -- Ensure border background is main
    mon.setTextColor(borderColor)

    -- Top border
    mon.setCursorPos(1, 1)
    mon.write(textutils.string.getChar("┌") .. string.rep(textutils.string.getChar("─"), w - 2) .. textutils.string.getChar("┐"))
    -- Side borders (excluding top and bottom line already drawn)
    for y = 2, h - 1 do
        mon.setCursorPos(1, y)
        mon.write(textutils.string.getChar("│"))
        mon.setCursorPos(w, y)
        mon.write(textutils.string.getChar("│"))
    end
    -- Bottom border
    mon.setCursorPos(1, h)
    mon.write(textutils.string.getChar("└") .. string.rep(textutils.string.getChar("─"), w - 2) .. textutils.string.getChar("┘"))

    -- Title Text (on line 1, inside border characters)
    mon.setBackgroundColor(mainBgColor) -- Ensure background for text is main
    mon.setTextColor(titleHighlightColor)

    local titleStr = "SYSTEM POWER MONITOR"
    local versionStr = "BIOS v" .. appVersion .. " (" .. appAuthor .. ")"

    -- Clear line 1 between borders (from column 2 to w-1)
    mon.setCursorPos(2,1)
    mon.write(string.rep(" ", w-2))

    -- Centered Title on Line 1
    local titleStartX = math.floor(( (w-2) - #titleStr ) / 2) + 2 -- +2 because cursor starts at col 2
    if titleStartX < 2 then titleStartX = 2 end
    mon.setCursorPos(titleStartX, 1)
    mon.write(titleStr)

    -- Right Aligned Version on Line 1
    local versionStartX = (w - 1) - #versionStr -- Place it ending before the right border char
    if versionStartX >= 2 and versionStartX > titleStartX + #titleStr then -- Check it fits and no overlap
        mon.setCursorPos(versionStartX, 1)
        mon.write(versionStr)
    end

    mon.setTextColor(mainTextColor) -- Reset to main text color

    -- Layout positions, content starts effectively at Y=3 (after a blank line separator)
    local positions = {
        peripheralNameY = 0, statusY = 0, progressBarY = 0,
        currentEnergyNumY = 0, maxEnergyY = 0
    }
    local currentY = 3 -- Start content sections at line 3

    -- Section: MAIN POWER MONITOR
    mon.setCursorPos(3, currentY)
    mon.setTextColor(accentColor) ; mon.write("MAIN POWER MONITOR")
    currentY = currentY + 1 -- Next line for labels

    mon.setTextColor(mainTextColor)
    positions.peripheralNameY = currentY
    mon.setCursorPos(5, currentY) ; mon.write("Connected Peripheral: ")
    currentY = currentY + 1
    positions.statusY = currentY
    mon.setCursorPos(5, currentY) ; mon.write("Status: ")
    currentY = currentY + 2 -- Add a blank line spacer after this section's content

    -- Section: ENERGY LEVELS
    mon.setCursorPos(3, currentY)
    mon.setTextColor(accentColor) ; mon.write("ENERGY LEVELS")
    currentY = currentY + 1 -- Next line for labels

    mon.setTextColor(mainTextColor)
    positions.progressBarY = currentY
    mon.setCursorPos(5, currentY) ; mon.write("Current Storage:") -- Progress bar and % will be here
    currentY = currentY + 1
    positions.currentEnergyNumY = currentY -- Numerical current energy value will be here
    -- Label for Max Capacity is on the next line, its value too
    currentY = currentY + 1
    positions.maxEnergyY = currentY
    mon.setCursorPos(5, currentY) ; mon.write("Max Capacity:")
    currentY = currentY + 2 -- Blank line spacer

    -- Section: SYSTEM INFORMATION
    mon.setCursorPos(3, currentY)
    mon.setTextColor(accentColor) ; mon.write("SYSTEM INFORMATION")
    currentY = currentY + 1

    mon.setTextColor(mainTextColor)
    mon.setCursorPos(5, currentY) ; mon.write("Refresh Rate: " .. refreshRate .. "s")
    currentY = currentY + 1
    mon.setCursorPos(5, currentY) ; mon.write("API: energy_storage (Forge)")

    drawLayout.positions = positions -- Store for updateDynamicData
end

local function findEnergyPeripheral()
    local names = peripheral.getNames()
    for i = 1, #names do
        if peripheral.hasType(names[i], "energy_storage") then
            energyCell = peripheral.wrap(names[i])
            if energyCell then
                return true
            end
        end
    end
    -- Fallback: try finding any peripheral of type "energy_storage" without knowing its name
    energyCell = peripheral.find("energy_storage")
    return energyCell ~= nil
end

local function formatEnergyValue(value)
    if value == nil then return "N/A" end
    -- Simple formatting, could be expanded (e.g., to kFE, MFE)
    return textutils.stringify(value) .. " FE"
end

local function updateDynamicData()
    local w, h = mon.getSize()
    mon.setBackgroundColor(mainBgColor) -- Ensure drawing happens on main background

    -- Clear previous dynamic values
    local function clearLine(y, xStart)
        mon.setCursorPos(xStart, y)
        mon.write(string.rep(" ", w - xStart - 1)) -- Leave space for border
    end

    local p = drawLayout.positions
    if not p then
        -- This should not happen if drawLayout was called, but as a safeguard:
        printError("Layout positions not initialized!")
        return
    end

    -- Define X starting positions for data fields (after labels)
    local dataStartX = 5 + #("Connected Peripheral: ") + 1 -- Longest label for X alignment start
                                                          -- "Current Storage: " is also long.
    dataStartX = math.max(dataStartX, 5 + #("Current Storage: ") + 1)


    if energyCell then
        mon.setTextColor(mainTextColor)
        clearLine(p.peripheralNameY, dataStartX)
        mon.setCursorPos(dataStartX, p.peripheralNameY)
        local pName = peripheral.getName(energyCell)
        mon.write(pName or peripheral.getType(energyCell) or "Unknown")

        clearLine(p.statusY, dataStartX)
        mon.setCursorPos(dataStartX, p.statusY)
        mon.setTextColor(colors.green) -- Or another status color
        mon.write("Online")
        mon.setTextColor(mainTextColor)

        local currentEnergy, errEnergy = energyCell.getEnergy()
        local maxEnergy, errCapacity = energyCell.getEnergyCapacity()

        if currentEnergy == nil or maxEnergy == nil then -- Check for nil specifically
            mon.setTextColor(errorColor)
            clearLine(p.progressBarY, dataStartX)
            mon.setCursorPos(dataStartX, p.progressBarY)
            mon.write("Error reading data")

            clearLine(p.currentEnergyNumY, dataStartX)

            clearLine(p.maxEnergyY, dataStartX)
            mon.setCursorPos(dataStartX, p.maxEnergyY)
            mon.write(errEnergy or errCapacity or "Peripheral error")
            mon.setTextColor(mainTextColor)
            return
        end

        local percentage = 0
        if maxEnergy > 0 then
            percentage = (currentEnergy / maxEnergy) * 100
        end

        -- Progress Bar
        local barAreaWidth = w - dataStartX - 1 - 5 -- Available width for bar + percentage text
        local percentageTextWidth = #string.format(" %.0f%%", percentage)
        local barWidth = math.max(10, barAreaWidth - percentageTextWidth)
        local filledWidth = math.floor((percentage / 100) * barWidth)

        clearLine(p.progressBarY, dataStartX)
        mon.setCursorPos(dataStartX, p.progressBarY)

        -- Draw filled part of the bar
        mon.setTextColor(progressBarColor)
        mon.setBackgroundColor(progressBarColor)
        mon.write(string.rep(progressBarChar, filledWidth))

        -- Draw empty part of the bar
        mon.setTextColor(progressBarBgColor)
        mon.setBackgroundColor(progressBarBgColor)
        mon.write(string.rep(progressBarEmptyChar, barWidth - filledWidth))

        mon.setBackgroundColor(mainBgColor) -- Restore main background for text after bar
        mon.setTextColor(mainTextColor)
        mon.write(string.format(" %.0f%%", percentage))

        -- Numerical Values
        clearLine(p.currentEnergyNumY, dataStartX)
        mon.setCursorPos(dataStartX, p.currentEnergyNumY)
        mon.write(formatEnergyValue(currentEnergy))

        clearLine(p.maxEnergyY, dataStartX)
        mon.setCursorPos(dataStartX, p.maxEnergyY)
        mon.write(formatEnergyValue(maxEnergy))

    else
        mon.setTextColor(errorColor)
        clearLine(p.peripheralNameY, dataStartX)
        mon.setCursorPos(dataStartX, p.peripheralNameY)
        mon.write("N/A")

        clearLine(p.statusY, dataStartX)
        mon.setCursorPos(dataStartX, p.statusY)
        mon.write("No energy storage detected")
        mon.setTextColor(mainTextColor)

        -- Clear energy level fields
        clearLine(p.progressBarY, dataStartX)
        mon.setCursorPos(dataStartX, p.progressBarY)
        local barAreaWidth = w - dataStartX - 1 - 5
        local percentageTextWidth = #(" ---%")
        local barWidth = math.max(10, barAreaWidth - percentageTextWidth)
        mon.write(string.rep(" ", barWidth) .. " ---%")

        clearLine(p.currentEnergyNumY, dataStartX)
        mon.setCursorPos(dataStartX, p.currentEnergyNumY)
        mon.write(formatEnergyValue(nil))

        clearLine(p.maxEnergyY, dataStartX)
        mon.setCursorPos(dataStartX, p.maxEnergyY)
        mon.write(formatEnergyValue(nil))
    end
end

local function main()
    if not mon.isColor() then
        mon.setTextColor(colors.red)
        mon.setBackgroundColor(colors.black)
        mon.clear()
        mon.setCursorPos(1,1)
        print("Error: Color monitor required for this program.")
        return
    end

    mon.setCursorBlink(false)
    clearScreen()
    drawLayout()

    if not findEnergyPeripheral() then
        updateDynamicData() -- Show "No peripheral found" message
        -- Optionally, could retry finding peripheral here or just wait for event
    end

    local refreshTimer = os.startTimer(refreshRate)

    while true do
        updateDynamicData() -- Update display

        local event, p1, p2, p3 = os.pullEvent()

        if event == "timer" and p1 == refreshTimer then
            refreshTimer = os.startTimer(refreshRate) -- Restart timer for next refresh
        elseif event == "key" then
            if p1 == keys.q or p1 == keys.escape then -- Added q and escape for exit
                break
            end
        elseif event == "terminate" then
            break
        elseif event == "monitor_touch" then -- Example: exit on touch
            break
        elseif event == "peripheral" or event == "peripheral_detach" then
            -- A peripheral was attached or detached, try to find energy peripheral again
            findEnergyPeripheral()
            -- No need to call updateDynamicData here, it's called at the start of the loop
        end
    end
end

-- Entry point
local ok, err = pcall(main)
if not ok then
    -- If main errors, clear screen and print error in a safe way
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1,1)
    print("A critical error occurred:")
    print(err)
    print("Please report this to " .. appAuthor)
end

-- Restore terminal state
mon.setBackgroundColor(colors.black) -- Default CC terminal bg
mon.setTextColor(colors.white)     -- Default CC terminal text
mon.clear()
mon.setCursorPos(1,1)
mon.setCursorBlink(true)
print("Power Monitor terminated.")
