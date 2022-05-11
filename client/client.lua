local imgquant = require 'imgquant'
local bson = require 'bson'
local config = require 'mineboy_config'

local monitor = peripheral.wrap(config.screenMonitor)
monitor.setTextScale(0.5)

local controlMonitor = peripheral.wrap(config.controlMonitor.monitorId)

-- Pretty color logging
local log = {
    rawLog = function(color, text, message)
        term.setTextColor(color)
        write('[' .. text .. '] ')
        term.setTextColor(colors.gray)
        write(message .. '\n')
    end
}

log.info = function(message)
    log.rawLog(colors.blue, "INFO", message)
end
log.error = function(message)
    log.rawLog(colors.red, "ERROR", message)
end
log.warn = function(message)
    log.rawLog(colors.yellow, "WARN", message)
end
log.query = function(message)
    log.rawLog(colors.green, "QUERY", message)
    term.setTextColor(colors.gray)
    write('> ')
    term.setTextColor(colors.white)
    return read()
end

-- Length of a table regardless of what the indexes are
function tableLen(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

local ws, err = http.websocket(config.wsUrl .. '/attach')
if err then
    log.error('Unable to open websocket: ' .. err)
    return
else
    log.info('Connected to socket: ' .. config.wsUrl)
end

-- Controller button map
local buttons = {
    {
        x = 2,
        y = 5,
        height = 2,
        width = 3,
        button = 'LEFT'
    },
    {
        x = 10,
        y = 5,
        height = 2,
        width = 3,
        button = 'RIGHT'
    },
    {
        x = 6,
        y = 2,
        height = 2,
        width = 3,
        button = 'UP'
    },
    {
        x = 6,
        y = 8,
        height = 2,
        width = 3,
        button = 'DOWN'
    },
    {
        x = 35,
        y = 4,
        height = 2,
        width = 3,
        button = 'A'
    },
    {
        x = 30,
        y = 6,
        height = 2,
        width = 3,
        button = 'B'
    },
    {
        x = 15,
        y = 10,
        height = 1,
        width = 5,
        button = 'SELECT'
    },
    {
        x = 22,
        y = 10,
        height = 1,
        width = 5,
        button = 'START'
    }
}

function buttons:render()
    if controlMonitor then
        term.redirect(controlMonitor)
        term.setBackgroundColor(colors[config.controlMonitor.backgroundColor])
        term.clear()
        for _, button in ipairs(self) do
            paintutils.drawFilledBox(
                button.x, 
                button.y,
                button.x + button.width,
                button.y + button.height,
                colors[config.controlMonitor.foregroundColor])
        end
        term.redirect(term.native())
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
            local event = {os.pullEvent()}

            if event[1] == 'websocket_message' then
                local message = bson.decode(event[3])
                if message.type == 'ERROR' then
                    -- Message we recieved was an error of some sort, log it
                    log.error(response.error)
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
            end
        end
    end
end

while true do
    --- Select a game and send a query to play the game
    log.info('Getting games list from server')
    local gameList = bson.decode(http.get(config.httpUrl .. '/listGames').readAll())
    log.info('Retrieved ' .. tableLen(gameList) .. ' games: ' .. textutils.serialize(gameList))

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
            break
        else
            log.error('Input must be a number')
        end
    end

    ws.send(bson.encode({
        type = 'SELECT_GAME',
        index = index
    }))

    local res = bson.decode(ws.receive())
    log.info('Started game: ' .. res.name)
    log.info('Press \'X\' to exit the game')

    buttons:render()
    gameLoop()
end
