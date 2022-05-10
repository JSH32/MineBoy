local imgquant = require 'imgquant'
local bson = require 'bson'

local monitor = peripheral.find('monitor')
monitor.setTextScale(0.5)

-- Pretty color logging
local log = {
	rawLog = function(color, text, message)
		term.setTextColor(color)
		write('[' .. text .. '] ')
		term.setTextColor(colors.gray)
		write(message .. '\n')
	end
}

log.info = function(message) log.rawLog(colors.blue, "INFO", message) end
log.error = function(message) rawLog(colors.red, "ERROR", message) end
log.warn = function(message) rawLog(colors.yellow, "WARN", message) end

-- Length of a table regardless of anything
function tableLen(T)
	local count = 0
	for _ in pairs(T) do count = count + 1 end
	return count
end

log.info('Getting games list from server')
local gameList = bson.decode(http.get('http://127.0.0.1:3000/listGames').readAll())
log.info('Retrieved ' .. tableLen(gameList) .. ' games: ' .. textutils.serialize(gameList))

local function start()
	local ws, err = http.websocket('ws://127.0.0.1:3000/attach')
	if err then
		print(err)
	elseif ws then
		while true do
			-- Request draw from server
			ws.send(bson.encode({type = 'REQUEST_DRAW'}))
 
			-- Wait for frame
			while true do
				local response = bson.decode(ws.receive())

				if response.type == 'ERROR' then
					-- Message we recieved was an error of some sort, log it
					log.error('[ERROR] ' .. response.error)
				elseif response.type == 'SCREEN_DRAW' then
					-- Extract image data
					local pos = 1
					local img = {}
					for y = 1, response.height do
						img[y] = {}
						for x = 1, response.width, 2 do
							local c = response.screen:byte(pos)
							pos = pos + 1
							img[y][x] = bit32.rshift(c, 4) + 1
							img[y][x+1] = bit32.band(c, 15) + 1
						end
					end

					local ccImage = imgquant.toCCImage(img, response.palette)
					imgquant.drawBlitImage(1, 1, ccImage, response.palette, monitor)

					break -- Break out of the listener loop
				end
			end
		end
	end
end

start()