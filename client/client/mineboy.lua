local imgquant = require 'mineboy_deps/imgquant'
local bson = require 'mineboy_deps/bson'
local config = require 'mineboy_config'

-- Pretty color logging
local log = {
    rawLog = function(color, text, message, useWrite)
        term.setTextColor(color)
        write('[' .. text .. '] ')
        term.setTextColor(colors.lightGray)
        if useWrite then
            write(message)
        else
            print(message)
        end
    end
}

log.info = function(message, useWrite)
    log.rawLog(colors.blue, 'INFO', message, useWrite)
end
log.error = function(message, useWrite)
    log.rawLog(colors.red, 'ERROR', message, useWrite)
end
log.warn = function(message, useWrite)
    log.rawLog(colors.yellow, 'WARN', message, useWrite)
end
log.query = function(message, useWrite)
    log.rawLog(colors.green, 'QUERY', message, useWrite)
    term.setTextColor(colors.lightGray)
    write('> ')
    term.setTextColor(colors.white)
    return read()
end

local function centerWrite(text, topX, topY, bottomX, bottomY)
    term.setCursorPos(topX + math.ceil((bottomX - topX) / 2 - (text:len() / 2)), topY + math.ceil(bottomY - topY) / 2)
    term.write(text)
end

-- Rednet for remote input
if config.rednet then
    local modem = peripheral.find("modem")
    if modem then
        rednet.open(peripheral.getName(modem))
        log.info('Rednet opened on id: ' .. os.getComputerID())
    else
        log.warn('No modem was found, rednet was not enabled!')
    end
end

local monitor = peripheral.wrap(config.screenMonitor)
monitor.setTextScale(0.5)

local controlMonitor
if config.controlMonitor.monitor ~= '' then
    controlMonitor = peripheral.wrap(config.controlMonitor.monitor)
end

local diskDrive
if config.diskDrive ~= nil or config.diskDrive ~= '' then
    diskDrive = peripheral.wrap(config.diskDrive)
end

-- Length of a table regardless of what the indexes are
function tableLen(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

local ws, err = http.websocket(config.wsUrl .. '/attach', { ["password"] = config.password })
if err then
    log.error('Unable to open websocket: ' .. err)
    return
else
    log.info('Connected to socket: ' .. config.wsUrl)
end

-- Controller button map
local buttons = {
    {
        x = 3,
        y = 5,
        height = 2,
        width = 2,
        button = 'LEFT',
        display = '\x1B',
        colors = config.controlMonitor.colors.dpad
    },
    {
        x = 9,
        y = 5,
        height = 2,
        width = 2,
        button = 'RIGHT',
        display = '\x1A',
        colors = config.controlMonitor.colors.dpad
    },
    {
        x = 6,
        y = 2,
        height = 2,
        width = 2,
        button = 'UP',
        display = '\x18',
        colors = config.controlMonitor.colors.dpad
    },
    -- Square in the middle so it doesn't look stupid
    {
        x = 6,
        y = 5,
        height = 2,
        width = 2,
        colors = config.controlMonitor.colors.dpad
    },
    {
        x = 6,
        y = 8,
        height = 2,
        width = 2,
        button = 'DOWN',
        display = '\x19',
        colors = config.controlMonitor.colors.dpad
    },
    {
        x = 35,
        y = 4,
        height = 2,
        width = 2,
        button = 'A',
        colors = config.controlMonitor.colors.ab
    },
    {
        x = 30,
        y = 6,
        height = 2,
        width = 2,
        button = 'B',
        bg = config.controlMonitor.colors.abBg,
        colors = config.controlMonitor.colors.ab
    },
    {
        x = 15.25,
        y = 11,
        height = 0.25,
        width = 5,
        button = 'SELECT',
        colors = config.controlMonitor.colors.startSelect
    },
    {
        x = 22.25,
        y = 11,
        height = 0.25,
        width = 4.5,
        button = 'START',
        colors = config.controlMonitor.colors.startSelect
    }
}

function buttons:render()
    if controlMonitor then
        local oldTerm = term.redirect(controlMonitor)
        term.setBackgroundColor(colors[config.controlMonitor.colors.bg])
        term.setCursorBlink(false)
        term.clear()
        for _, button in ipairs(self) do
            paintutils.drawFilledBox(
                button.x,
                button.y,
                button.x + button.width,
                button.y + button.height,
                colors[button.colors.bg])

            local text = button.display or button.button
            if text then
                term.setTextColor(colors[button.colors.fg])
                centerWrite(text,
                    button.x,
                    button.y,
                    button.x + button.width,
                    button.y + button.height)
            end
        end
        term.redirect(oldTerm)
    end
end

function buttons:updateButtons(x, y)
    for _, button in ipairs(self) do
        if button.x <= x and x <= button.x + button.width and button.y <= y and y <= button.y + button.height then
            ws.send(bson.encode({
                type = 'PRESS_BUTTON',
                button = button.button
            }))
        end
    end
end

--- Render the received frame to the screen
-- @param width of the image
-- @param height of the image
-- @param color palette used to render the image (length of 16)
-- @param screen to render, array of 4-bit values (0-16)
local function blitFrame(width, height, palette, screen)
    -- Extract image data
    local pos = 1
    local img = {}
    for y = 1, height do
        img[y] = {}
        for x = 1, width, 2 do
            local c = screen:byte(pos)
            pos = pos + 1
            img[y][x] = bit32.rshift(c, 4) + 1
            img[y][x + 1] = bit32.band(c, 15) + 1
        end
    end

    local ccImage = imgquant.toCCImage(img, palette)
    imgquant.drawBlitImage(1, 1, ccImage, palette, monitor)
end

-- Should run when game session is active
local function gameLoop()
    while true do
        -- Request draw from server
        ws.send(bson.encode({
            type = 'REQUEST_DRAW'
        }))

        -- Wait for frame
        while true do
            local event = { os.pullEvent() }

            if event[1] == 'websocket_message' then
                local message = bson.decode(event[3])
                if message.type == 'ERROR' then
                    -- Message we recieved was an error of some sort, log it
                    log.error(response.error)
                elseif message.type == 'SAVE_DATA' then
                    if diskDrive and diskDrive.isDiskPresent() then
                        local savePath = diskDrive.getMountPath() .. '/mineboy/' .. message.gameName
                        local handle = fs.open(savePath, 'w')
                        handle.write(message.data)
                        handle.close()
                        if message.auto then
                            log.info('Autosaved SRAM to: ' .. savePath)
                        else
                            log.info('Saved SRAM to: ' .. savePath)
                        end
                    end
                elseif message.type == 'SCREEN_DRAW' then
                    blitFrame(message.width, message.height, message.palette, message.screen)

                    -- Break out of the listener loop so we can request another frame
                    break
                end
            elseif event[1] == 'monitor_touch' then
                buttons:updateButtons(event[3], event[4])
            elseif event[1] == 'key' then
                local character = event[2]

                -- Exit game session
                if character == keys.x then
                    ws.send(bson.encode({
                        type = 'EXIT_GAME'
                    }))

                    -- Wait for event to signal game exited
                    while true do
                        local res = bson.decode(ws.receive())
                        if res.type == 'GAME_EXITED' then
                            break
                        end
                    end

                    log.info('Game session was terminated')
                    return
                end

                if character == keys.s and diskDrive and diskDrive.isDiskPresent() then
                    ws.send(bson.encode({
                        type = 'GET_SAVE'
                    }))
                end
            elseif event[1] == 'rednet_message' then
                -- Protocol must be 'mineboy_input'
                if event[4] == 'mineboy_input' then
                    ws.send(bson.encode({
                        type = 'PRESS_BUTTON',
                        button = event[3]
                    }))
                end
            end
        end
    end
end

while true do
    --- Select a game and send a query to play the game
    log.info('Getting games list from server')
    local gameList = bson.decode(http.get(config.httpUrl .. '/listGames').readAll())
    log.info('Retrieved ' .. tableLen(gameList) .. ' games: {', true)
    
    write('\n')
    for k, v in pairs(gameList) do
        term.setTextColor(colors.red)
        write('  '  .. k)
        term.setTextColor(colors.lightGray)
        write(' - ' .. v .. '\n')
    end
    write("}\n")

    local index
    while true do
        local query = log.query('Select a game to play (0-' .. tableLen(gameList) - 1 .. ') or type "exit"')
        if string.lower(query) == 'exit' then
            ws.close()
            log.info('Goodbye :)')
            return
        end

        index = tonumber(query)
        if index then
            if index > tableLen(gameList) - 1 then
                log.error('Invalid input')
            else
                break
            end
        else
            log.error('Input must be a number')
        end
    end

    local saveData
    if diskDrive and diskDrive.isDiskPresent() then
        local savePath = diskDrive.getMountPath() .. '/mineboy/' .. gameList[tostring(index)]
        if fs.exists(savePath) then
            local handle = fs.open(savePath, 'r')
            saveData = handle.readAll()
            handle.close()
        end
    end

    ws.send(bson.encode({
        type = 'SELECT_GAME',
        index = index,
        autoSave = config.autoSave,
        -- Don't send an empty save
        save = saveData
    }), true)

    log.info('Started game: ' .. bson.decode(ws.receive()).name)
    log.info('Press \'X\' to exit the game' .. (diskDrive and ', Press \'S\' to save SRAM to disk' or ''))

    buttons:render()
    gameLoop()
end
