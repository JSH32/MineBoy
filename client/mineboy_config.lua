return {
	httpUrl = 'http://localhost:3000',
	wsUrl = 'ws://localhost:3000',
	screenMonitor = '',
	diskDrive = '', -- this can be nothing if you don't want save files
	rednet = false, -- remote controller functionality, requires wireless modem
	controlMonitor = {
		monitor = '', -- this can be blank if you don't want a gamepad

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