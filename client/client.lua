local imgquant = require 'imgquant'
local bson = require 'bson'

local monitor = peripheral.find('monitor')
monitor.setTextScale(0.5)

local function start()
	local ws, err = http.websocket('ws://127.0.0.1:3000/attach')
	if err then
		print(err)
	elseif ws then
		while true do
			-- Request draw from server
			-- print(bson.encode({type = 'REQUEST_DRAW'}))
			ws.send(bson.encode({type = 'REQUEST_DRAW'}))
 
			-- Wait for frame
			while true do
				local response = bson.decode(ws.receive())

				if response.type == 'ERROR' then
					-- Message we recieved was an error of some sort, log it
					print('[ERROR] ' .. response.error)
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

					break -- Break out of the next-frame listen loop
				end
			end
		end
	end
end

start()