import 'dotenv/config'
import Gameboy from 'serverboy'
import express from 'express'
import expressWs from 'express-ws'
import { match, P } from 'ts-pattern'
import { useTry } from 'no-try'
import ws from 'ws'
import fs from 'fs'
import zlib from 'zlib'
import bmp from 'bmp-js'
import palettext from 'palettext'

const app = expressWs(express()).app

app.get('/', (req, res) => {
	res.send('Hello World!')
})

// enum ButtonKey {
//     Right = 'RIGHT',
//     Left = 'LEFT',
//     Up = 'UP',
//     Down = 'DOWN',
//     A = 'A',
//     B = 'B',
//     Select = 'SELECT',
//     Start = 'START'
// }

const WIDTH = 160
const HEIGHT = 144

// Send a socket er
const sendError = (ws: ws, error: string) => 
	ws.send(JSON.stringify({ type: 'ERROR', error }))

app.ws('/attach', (ws: ws, req) => {
	const gameboy = new Gameboy()
	gameboy.loadRom(fs.readFileSync('./roms/Pokemon Crystal.gbc'))

	// ws.on('open', msg => {
	// 	console.log('Attached')
	// })

	// ws.on('upgrade', msg => {
	// 	console.log('upgraded')
	// })

	const intervalId = setInterval(() => {
		gameboy.doFrame()
		gameboy.doFrame()
		gameboy.doFrame()
	}, 1000 / 60)

	ws.on('message', async (msgString: string) => {
		const [error, res] = useTry(() => JSON.parse(msgString))
		if (error) return sendError(ws, 'Invalid data provided')

		match(res)
			.with({ type: 'REQUEST_DRAW' }, () => {
				const screenRgba = gameboy.getScreen()
				const colors = palettext(screenRgba, {
					width: WIDTH,
					qtyMax: 16
				})

				const palette = []
				for (let i = 0; i < 16; i++)
					if (colors[i])
						palette[i] = colors[i].hex.substr(1)

				// We wouldn't need to do this if bmp-js did RGBA and not ABGR 
				const agbrBuffer = []
				for (let i = 0; i < screenRgba.length / 4; i++)
					agbrBuffer.push(
						screenRgba[i * 4 + 3],
						screenRgba[i * 4 + 2],
						screenRgba[i * 4 + 1],
						screenRgba[i * 4])
				
				const oldBuffer = bmp.encode({
					height: HEIGHT,
					width: WIDTH,
					data: agbrBuffer
				}).data

				zlib.deflate(oldBuffer, (err, buffer) => {
					if (err) return sendError(ws, 'There was a problem compressing the frame')
					
					ws.send(JSON.stringify({
						type: 'SCREEN_DRAW',
						screen: buffer.toString('binary'),
						palette
					}))
				})
			})
			.exhaustive()
	})

	ws.on('close', () => {
		console.log('WebSocket was closed')
		clearInterval(intervalId)
	})
})

app.listen(process.env.PORT, () => console.log(`Listening on http://localhost:${process.env.PORT}`))