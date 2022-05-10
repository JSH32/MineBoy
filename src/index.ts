import 'dotenv/config'
import Gameboy from 'serverboy'
import express from 'express'
import expressWs from 'express-ws'
import { match } from 'ts-pattern'
import { useTry } from 'no-try'
import ws from 'ws'
import fs from 'fs'
import { serialize, deserialize } from 'bson'
import RgbQuant from 'rgbquant'
import path from 'path'

const app = expressWs(express()).app

// Gameboy resolution
const WIDTH = 160
const HEIGHT = 144

// Send an error message through socket
const sendError = (ws: ws, error: string) => 
	ws.send(serialize({ type: 'ERROR', error }))

app.ws('/attach', (ws: ws) => {
	const gameboy = new Gameboy()
	gameboy.loadRom(fs.readFileSync('./roms/Pokemon Crystal.gbc'))

	// 120fps without spamming the eventloop
	const intervalId = setInterval(() => {
		for (let i = 0; i < 2; i++)
			gameboy.doFrame()
	}, 1000 / 60)

	ws.on('message', async (msgString: string) => {
		const [error, res] = useTry<any>(() => deserialize(Buffer.from(msgString)))
		if (error) return sendError(ws, 'Invalid data provided')

		match(res)
			.with({ type: 'REQUEST_DRAW' }, async () => {
				const screenRgba = gameboy.getScreen()

				// Create 16 palette from screen
				const quant = new RgbQuant({ colors: 16 })
				quant.sample(screenRgba, WIDTH)
				const palette = quant.palette(true)

				// Fill all empty palette values with black
				for (let i = 0; i < 16; i++)
					palette[i] = palette[i] ? palette[i] : [ 0, 0, 0 ]

				// Reduced frame with color palette
				const reducedRgba = quant.reduce(screenRgba)
				
				// Convert the colors from rgba to palette indexes for smaller size
				const colorArray = []
				for (let y = 0; y < HEIGHT; y++) {
					for (let x = 0; x < WIDTH; x++) {
						const r = reducedRgba[(y * WIDTH + x) * 4]
						const g = reducedRgba[(y * WIDTH + x) * 4 + 1]
						const b = reducedRgba[(y * WIDTH + x) * 4 + 2]
						
						for (let i = 0; i < palette.length; i++) {
							if (palette[i][0] === r &&
								palette[i][1] === g &&
								palette[i][2] === b) {
								colorArray.push(i)
								break
							}
						}
					}
				}

				// The last line cuts off so we push a line to the end,
				// most likely imgquant issue on lua side, JackMacWindows is responsible.
				for (let i = 0; i < WIDTH; i++)
					colorArray.push(0)

				// 4 bit image data
				const output = Buffer.alloc(colorArray.length / 2 + WIDTH / 2)
				for (let i = 0; i < colorArray.length; i += 2) 
					output.writeUInt8(colorArray[i] << 4 | colorArray[i+1], i / 2)

				ws.send(serialize({
					type: 'SCREEN_DRAW',
					width: WIDTH,
					height: HEIGHT + 1, // Add one line to compensate for invisible line
					screen: output,
					palette: palette
				}))
			})
			.exhaustive()
	})

	ws.on('close', () => {
		console.log('WebSocket was closed')
		clearInterval(intervalId)
	})
})

app.listen(process.env.PORT, () => console.log(`Listening on http://localhost:${process.env.PORT}`))