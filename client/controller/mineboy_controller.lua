-- Key map, the left side is the keys you press on keyboard.
-- These can be changed to any keys on this list https://computercraft.info/wiki/Keys_(API)
local keyMap = {
	[keys.up] = 'UP',
	[keys.down] = 'DOWN',
	[keys.right] = 'RIGHT',
	[keys.left] = 'LEFT',
	[keys.z] = 'B',
	[keys.x] = 'A',
	[keys.leftBracket] = 'SELECT',
	[keys.rightBracket] = 'START'
}

-- This program is designed to run on a pocket computer only
peripheral.find("modem", rednet.open)

-- Query a computer ID
local computerId
while true do
	term.setTextColor(colors.lightGray)
	write('Mineboy computer ID: ')
	term.setTextColor(colors.white)
	computerId = tonumber(read())

	if computerId == nil then
		term.setTextColor(colors.red)
		print('Input must be a number')
	else
		break
	end
end

local function showUi() 
	-- Top bar
	term.clear()
	term.setBackgroundColor(colors.cyan)
	term.setCursorPos(1, 1)
	term.clearLine()
	print('[MineBoy Controller]')
	term.setBackgroundColor(colors.black)

	term.setTextColor(colors.cyan)
	write('\nComputer ID: ')
	term.setTextColor(colors.lightGray)
	print(computerId)
	
	term.setTextColor(colors.cyan)
	write('Key Map: {\n')
	term.setTextColor(colors.lightGray)

	for key, consoleKey in pairs(keyMap) do
		term.setTextColor(colors.red)
        write('  ' .. keys.getName(key))
        term.setTextColor(colors.lightGray)
        write(' - ' .. consoleKey .. '\n')
	end
	write('}\n')

	term.setBackgroundColor(colors.cyan)
	local w, h = term.getSize()
	term.setCursorPos(w, h)
	term.clearLine()
	term.setCursorPos(w, h - 1)
	term.setTextColor(colors.white)
	write('Press CTRL+X to exit')

	term.setBackgroundColor(colors.black)
end

showUi()

-- When both are pushed it should exit
local exitKeys = { 
	[keys.x] = false, 
	[keys.leftCtrl] = false 
}

while true do
	local event = { os.pullEvent() }
	if event[1] == 'key' then
		local button = keyMap[event[2]]
		if event[2] == keys.x or event[2] == keys.leftCtrl then
			-- Only set buttons when not held
			exitKeys[event[2]] = not event[3]

			-- All exit keys pressed
			if exitKeys[keys.x] and exitKeys[keys.leftCtrl] then
				term.clear()
				term.setCursorPos(1, 1)
				return
			end
		end

		if button ~= nil then
			rednet.send(computerId, button, 'mineboy_input')
		end
	elseif event[1] == 'key_up' then
		if event[2] == keys.x or event[2] == keys.leftCtrl then
			exitKeys[event[2]] = false
		end
	end
end