import 'dotenv/config'
import Gameboy from 'serverboy'
import express from 'express'
import expressWs from 'express-ws'
import { match, P } from 'ts-pattern'
import { useTry } from 'no-try'
import ws from 'ws'
import fs from 'fs'
import palettext from 'palettext'
import { serialize, deserialize } from 'bson'

const app = expressWs(express()).app

const WIDTH = 160
const HEIGHT = 144

// Send an error message through socket
const sendError = (ws: ws, error: string) => 
	ws.send(serialize({ type: 'ERROR', error }))

app.ws('/attach', (ws: ws) => {
	const gameboy = new Gameboy()
	gameboy.loadRom(fs.readFileSync('./roms/Pokemon Crystal.gbc'))

	const intervalId = setInterval(() => {
		for (let i = 0; i < 2; i++)
			gameboy.doFrame()
	}, 1000 / 60)

	ws.on('message', async (msgString: string) => {
		const [error, res] = useTry<any>(() => deserialize(Buffer.from(msgString)))
		if (error) return sendError(ws, 'Invalid data provided')

		match(res)
			.with({ type: 'REQUEST_DRAW' }, () => {
				const screenRgba = gameboy.getScreen()
				const colors = palettext(screenRgba, {
					width: WIDTH,
					qtyMax: 16
				})

				// Must have 16 colors in the palette, even if we don't have 16 colors
				// We set all leftover colors to black
				const palette = []
				for (let i = 0; i < 16; i++)
					palette[i] = colors[i] ? colors[i].color : [ 0, 0, 0 ]
				
				// Clamp all the colors to colors generated in the palette
				const colorArray = []
				for (let y = 0; y < HEIGHT; y++) {
					for (let x = 0; x < WIDTH; x++) {
						const r = screenRgba[(y * WIDTH + x) * 4]
						const g = screenRgba[(y * WIDTH + x) * 4 + 1]
						const b = screenRgba[(y * WIDTH + x) * 4 + 2]
						let minDistance = Infinity
						let color = 0
						
						// We use colors and not palette here because palette sets unused values to black
						for (let i = 0; i < colors.length; i++) {
							const distance = colorDistance(colors[i].color, [r, g, b])
							if (distance < minDistance) {
								minDistance = distance
								color = i
							}
						}
						
						colorArray.push(color)
					}
				}

				// 4 bit image data
				const output = Buffer.alloc(colorArray.length / 2)
				for (let i = 0; i < colorArray.length; i += 2) 
					output.writeUInt8(colorArray[i] << 4 | colorArray[i+1], i / 2)

				ws.send(serialize({
					type: 'SCREEN_DRAW',
					width: WIDTH,
					height: HEIGHT,
					screen: output,
					palette
				}))
			})
			.exhaustive()
	})

	ws.on('close', () => {
		console.log('WebSocket was closed')
		clearInterval(intervalId)
	})
})

const colorDistance = (color1: [number, number, number], color2: [number, number, number]) => 
	Math.pow(color2[0] - color1[0], 2) + Math.pow(color2[1] - color1[1], 2) + Math.pow(color2[2] - color1[2], 2)

app.listen(process.env.PORT, () => console.log(`Listening on http://localhost:${process.env.PORT}`))