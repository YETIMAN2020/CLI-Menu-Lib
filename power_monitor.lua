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

-- Global for the energy peripheral and its capabilities
local energyCell = nil
local energyCellCapabilities = {
    hasEnergyStorage = false, -- Generic getEnergy/getMaxEnergy
    hasAdvancedIO = false    -- AP-style getLastInput/getLastOutput
}

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
        currentEnergyNumY = 0, maxEnergyY = 0,
        inputRateY = 0, outputRateY = 0 -- New fields
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
    currentY = currentY + 1
    positions.inputRateY = currentY
    mon.setCursorPos(5, currentY) ; mon.write("Input Rate:")
    currentY = currentY + 1
    positions.outputRateY = currentY
    mon.setCursorPos(5, currentY) ; mon.write("Output Rate:")
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
    energyCell = nil
    energyCellCapabilities.hasEnergyStorage = false
    energyCellCapabilities.hasAdvancedIO = false

    local pNames = peripheral.getNames()
    local candidates = {}

    for i = 1, #pNames do
        local name = pNames[i]
        local pType = peripheral.getType(name)
        local wrapped = peripheral.wrap(name)

        if wrapped then
            -- Check for specific Mekanism types first, then generic energy_storage
            -- Common Mekanism port/valve names might include "induction_port", "induction_valve"
            -- or types provided by Mekanism's own integration if AP is not the provider.
            -- Advanced Peripherals might name it something like "mekanism_induction_port" or similar.

            local hasIO = wrapped.getLastInput and wrapped.getLastOutput
            local hasStorage = wrapped.getEnergy and wrapped.getMaxEnergy

            if pType and (string.find(pType, "mekanism") or string.find(pType, "induction")) then
                if hasIO and hasStorage then -- Ideal candidate
                    table.insert(candidates, 1, {name=name, wrapped=wrapped, io=true, storage=true, type=pType}) -- Prioritize
                elseif hasStorage then
                    table.insert(candidates, {name=name, wrapped=wrapped, io=false, storage=true, type=pType})
                end
            elseif peripheral.hasType(name, "energy_storage") and hasStorage then
                 table.insert(candidates, {name=name, wrapped=wrapped, io=false, storage=true, type="energy_storage"})
            end
        end
    end

    if #candidates > 0 then
        -- Select the best candidate (prioritizing those with I/O)
        local bestCandidate = candidates[1] -- Already sorted by insertion logic roughly
        for i = 2, #candidates do
            if candidates[i].io and not bestCandidate.io then
                bestCandidate = candidates[i]
            end
        end

        energyCell = bestCandidate.wrapped
        energyCellCapabilities.hasAdvancedIO = bestCandidate.io
        energyCellCapabilities.hasEnergyStorage = bestCandidate.storage

        -- If it has advanced I/O, we assume it also has basic storage functions
        -- or that the advanced functions are preferred.
        -- If only basic storage is found, that's fine too.
        return true
    end

    -- Fallback to generic peripheral.find if no named ones matched criteria but had the type
    -- This part is a bit redundant if the loop above correctly wraps and checks types/methods.
    -- Let's try to find a generic one if the specific search yields nothing with methods.
    local genericEnergy = peripheral.find("energy_storage")
    if genericEnergy then
        if genericEnergy.getLastInput and genericEnergy.getLastOutput and genericEnergy.getEnergy and genericEnergy.getMaxEnergy then
            energyCell = genericEnergy
            energyCellCapabilities.hasAdvancedIO = true
            energyCellCapabilities.hasEnergyStorage = true
            return true
        elseif genericEnergy.getEnergy and genericEnergy.getMaxEnergy then
            energyCell = genericEnergy
            energyCellCapabilities.hasAdvancedIO = false
            energyCellCapabilities.hasEnergyStorage = true
            return true
        end
    end

    return false
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
        -- Peripheral Name
        clearLine(p.peripheralNameY, dataStartX)
        mon.setCursorPos(dataStartX, p.peripheralNameY)
        local pName = peripheral.getName(energyCell)
        mon.write(pName or peripheral.getType(energyCell) or "Unknown")

        -- Status
        clearLine(p.statusY, dataStartX)
        mon.setCursorPos(dataStartX, p.statusY)
        mon.setTextColor(colors.green)
        mon.write("Online")
        mon.setTextColor(mainTextColor)

        local currentEnergy, maxEnergy, percentage
        local inputRate, outputRate
        local hasStorageData = false
        local hasIOData = false

        -- Fetch Basic Energy Storage Data
        if energyCellCapabilities.hasEnergyStorage then
            local currentE, errE = pcall(function() return energyCell.getEnergy() end)
            local maxE, errMaxE = pcall(function() return energyCell.getMaxEnergy() end)

            if currentE and maxE and type(currentE) == "number" and type(maxE) == "number" then
                currentEnergy = currentE
                maxEnergy = maxE
                if maxEnergy > 0 then
                    percentage = (currentEnergy / maxEnergy) * 100
                else
                    percentage = 0
                end
                hasStorageData = true
            else
                -- Error fetching basic storage, display on progress bar line
                mon.setTextColor(errorColor)
                clearLine(p.progressBarY, dataStartX)
                mon.setCursorPos(dataStartX, p.progressBarY)
                mon.write("Storage Error")
                mon.setTextColor(mainTextColor)
                -- Clear other related fields too
                clearLine(p.currentEnergyNumY, dataStartX)
                clearLine(p.maxEnergyY, dataStartX)
            end
        end

        -- Fetch Advanced I/O Data
        if energyCellCapabilities.hasAdvancedIO then
            local inputR, errIn = pcall(function() return energyCell.getLastInput() end)
            local outputR, errOut = pcall(function() return energyCell.getLastOutput() end)

            if inputR and outputR and type(inputR) == "number" and type(outputR) == "number" then
                inputRate = inputR
                outputRate = outputR
                hasIOData = true
            else
                 -- Error fetching I/O, display on I/O lines (to be added in UI step)
                 -- For now, just means inputRate/outputRate will be nil
            end
        end

        -- Display Stored Energy if available
        if hasStorageData then
            -- Progress Bar
            local barAreaWidth = w - dataStartX - 1 - 5
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

        -- Numerical Values for Stored Energy
        clearLine(p.currentEnergyNumY, dataStartX)
        mon.setCursorPos(dataStartX, p.currentEnergyNumY)
        mon.write(formatEnergyValue(currentEnergy))

        clearLine(p.maxEnergyY, dataStartX)
        mon.setCursorPos(dataStartX, p.maxEnergyY)
        mon.write(formatEnergyValue(maxEnergy))
    elseif not energyCellCapabilities.hasEnergyStorage and energyCell then
        -- Has a cell, but no storage data (maybe only I/O if that was possible, or error'd)
        mon.setTextColor(errorColor)
        clearLine(p.progressBarY, dataStartX)
        mon.setCursorPos(dataStartX, p.progressBarY)
        mon.write("No storage data")
        mon.setTextColor(mainTextColor)
        clearLine(p.currentEnergyNumY, dataStartX)
        clearLine(p.maxEnergyY, dataStartX)
    end

    -- Display I/O Rates if available (Y positions for these will be added in drawLayout next)
    if energyCellCapabilities.hasAdvancedIO then
        if hasIOData then
            clearLine(p.inputRateY, dataStartX) -- Assuming p.inputRateY will be defined
            mon.setCursorPos(dataStartX, p.inputRateY)
            mon.write(formatEnergyValue(inputRate) .. "/t")

            clearLine(p.outputRateY, dataStartX) -- Assuming p.outputRateY will be defined
            mon.setCursorPos(dataStartX, p.outputRateY)
            mon.write(formatEnergyValue(outputRate) .. "/t")
        else
            -- Error fetching I/O data or methods don't exist though capability was true (should be rare)
            mon.setTextColor(errorColor)
            clearLine(p.inputRateY, dataStartX)
            mon.setCursorPos(dataStartX, p.inputRateY)
            mon.write("I/O Error")

            clearLine(p.outputRateY, dataStartX)
            mon.setCursorPos(dataStartX, p.outputRateY)
            mon.write("I/O Error")
            mon.setTextColor(mainTextColor)
        end
    elseif energyCell then -- No advanced I/O, but we have a cell, so clear I/O fields
        if p.inputRateY and p.outputRateY then -- Check if UI fields exist for I/O
            clearLine(p.inputRateY, dataStartX)
            mon.setCursorPos(dataStartX, p.inputRateY)
            mon.write("N/A")
            clearLine(p.outputRateY, dataStartX)
            mon.setCursorPos(dataStartX, p.outputRateY)
            mon.write("N/A")
        end
    end


    if not energyCell then -- Complete absence of a peripheral
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
        local percentageTextWidth = #(" ---%") -- Width of " ---%"
        local barWidth = math.max(10, barAreaWidth - percentageTextWidth)
        mon.write(string.rep(progressBarEmptyChar, barWidth) .. " ---%") -- Use progressBarEmptyChar for consistency

        clearLine(p.currentEnergyNumY, dataStartX)
        mon.setCursorPos(dataStartX, p.currentEnergyNumY)
        mon.write(formatEnergyValue(nil))

        clearLine(p.maxEnergyY, dataStartX)
        mon.setCursorPos(dataStartX, p.maxEnergyY)
        mon.write(formatEnergyValue(nil))

        -- Clear I/O fields as well if they exist in layout
        if p.inputRateY then
            clearLine(p.inputRateY, dataStartX)
            mon.setCursorPos(dataStartX, p.inputRateY)
            mon.write(formatEnergyValue(nil)) -- formatEnergyValue handles nil to "N/A"
        end
        if p.outputRateY then
            clearLine(p.outputRateY, dataStartX)
            mon.setCursorPos(dataStartX, p.outputRateY)
            mon.write(formatEnergyValue(nil))
        end
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
