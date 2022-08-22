return {
	-- HTTP Server URL.
	httpUrl = 'http://localhost:3000',
	-- Socket Server URL.
	wsUrl = 'ws://localhost:3000',
	screenMonitor = '',
	-- Disk drive ID or orientation for save files.
	-- Saves are automatically loaded but not saved, you must press "s" in the terminal to copy save files.
	diskDrive = '',
	-- Remote controller functionality, requires wireless modem.
	rednet = false,
	controlMonitor = {
		-- Monitor ID or orientation for gamepad.
		-- This can be blank if you don't want a gamepad.
		monitor = '',

		-- Colors of the controller, this is set to the basic black/red/white scheme
		colors = {
			bg = 'gray',
			dpad = {
				bg = 'black',
				fg = 'gray'
			},
			ab = {
				bg = 'red',
				fg = 'black',
			},
			startSelect = {
				bg = 'lightGray',
				fg = 'white'
			}
		}
	}
}