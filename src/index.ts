import 'dotenv/config'
import Gameboy from 'serverboy'
import express from 'express'
import expressWs from 'express-ws'
import { match, P } from 'ts-pattern'
import { useTry } from 'no-try'
import ws from 'ws'
import fs from 'fs'
import { serialize, deserialize } from 'bson'
import RgbQuant from 'rgbquant'
import path from 'path'
import { Logger } from 'tslog'
import { FixedArray } from './utils'
import zlib from 'zlib'
import { promisify } from 'util'

// Pretty colors
new Logger({ name: 'console', overwriteConsole: true })

const wsInstance = expressWs(express())
const app = wsInstance.app

// Gameboy resolution
const WIDTH = 160
const HEIGHT = 144

// Send an error message through socket
const sendError = (ws: ws, error: string) => 
	ws.send(serialize({ type: 'ERROR', error }))

const getGames = (romDir: string): Record<string, Buffer> => {
	const games = {}

	for (const file of fs.readdirSync(romDir)) {
		const gameboy = new Gameboy()
		const gameBuffer = fs.readFileSync(path.join(romDir, file))

		gameboy.loadRom(gameBuffer)

		// Why the fuck is it hidden like this in serverboy
		games[gameboy[Object.keys(gameboy)[0]].gameboy.name] = gameBuffer
	}

	return games
}

/**
 * Quantizes the frame and compresses into a small package
 * 
 * @param rgbaBuf RGBA buffer of the frame
 * @param dimensions width and height of the image
 * @returns A palette and a 4-bit buffer of index references to the palette.
 * The returned image has one higher height than provided because of a CC bug.
 */
const quantizeFrame = (
	rgbaBuf: number[], 
	dimensions: [number, number]
): [FixedArray<number, 16>, Buffer] => {
	// Create 16 palette from screen
	const quant = new RgbQuant({ colors: 16 })
	quant.sample(rgbaBuf, dimensions[0])
	const palette = quant.palette(true)

	// Fill all empty palette values with black
	for (let i = 0; i < 16; i++)
		palette[i] = palette[i] ? palette[i] : [ 0, 0, 0 ]

	// Reduced frame with color palette
	const reducedRgba = quant.reduce(rgbaBuf)
						
	// Convert the colors from rgba to palette indexes for smaller size
	const colorArray = []
	for (let y = 0; y < dimensions[1]; y++) {
		for (let x = 0; x < dimensions[0]; x++) {
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
	// most likely imgquant issue on lua side.
	for (let i = 0; i < dimensions[0]; i++)
		colorArray.push(0)

	// Compress the indexes to 4-bit buffer
	const output = Buffer.alloc(colorArray.length / 2)
	for (let i = 0; i < colorArray.length; i += 2) 
		output.writeUInt8(colorArray[i] << 4 | colorArray[i+1], i / 2)

	return [ palette, output ]
}

// Load games at startup
const games = getGames(path.join(process.cwd(), 'roms'))
console.info(`Loaded ${Object.keys(games).length} roms:`, Object.keys(games))

app.get('/listGames', (_, res) => 
	res.send(serialize(Object.keys(games))))

// Any API that does operations on the gameboy should be completely asynchronous and require a WS session
app.ws('/attach', (ws: ws) => {
	console.info(`Client connected (${wsInstance.getWss().clients.size} online)`)
	
	const gameboy = new Gameboy()
	const keysPressed = new Map<number, number>()
	let gameName = null

	// 120fps without spamming the eventloop
	// This is null util a game is running
	let intervalId = null

	ws.on('message', async (msgString: string) => {
		const [error, res] = useTry<any>(() => deserialize(Buffer.from(msgString)))
		if (error) return sendError(ws, 'Invalid data provided')

		match(res)
			.with({ type: 'SELECT_GAME', index: P.number, save: P.optional(P.any) }, async () => {
				if (res.index > games.length)
					return sendError(ws, 'Invalid game index selected')

				const saveData = res.save ? await promisify(zlib.inflate)(Buffer.from(res.save, 'base64')) : undefined
				gameName = Object.keys(games)[res.index]
				gameboy.loadRom(games[gameName], saveData)

				if (!intervalId) {
					intervalId = setInterval(() => {
						const keysToPress = []

						// For some reason not every keystroke will register the first time so we make it click on three updates
						for (const [key, count] of keysPressed) {
							if (count > 0) {
								keysToPress.push(key)
								keysPressed.set(key, count - 1)
							}
						}

						gameboy.pressKeys(keysToPress)
						gameboy.doFrame()
					}, 1000 / 120)
				}

				ws.send(serialize({ type: 'GAME_STARTED', name: gameName }))
			})
			// Handler for other routes which require game to be running
			.otherwise(() => {
				if (!intervalId)
					return sendError(ws, 'No game running')
					
				match(res)
					.with({ type: 'EXIT_GAME' }, () => {
						clearInterval(intervalId)
						intervalId = null
		
						ws.send(serialize({ type: 'GAME_EXITED' }))
					})
					.with({ type: 'GET_SAVE' }, () => {
						// Compress save due to limited disk storage
						zlib.deflate(Buffer.from(gameboy.getSaveData()), (_, buffer) => {
							ws.send(serialize({ 
								type: 'SAVE_DATA',
								gameName,
								data: buffer.toString('base64')
							}))
						})
					})
					.with({ type: 'PRESS_BUTTON', button: P.string }, () => {
						keysPressed.set(Gameboy.KEYMAP[res.button], 10)
					})
					.with({ type: 'REQUEST_DRAW' }, async () => {
						const [palette, output] = quantizeFrame(gameboy.getScreen(), [WIDTH, HEIGHT])
		
						ws.send(serialize({
							type: 'SCREEN_DRAW',
							width: WIDTH,
							height: HEIGHT + 1, // Add one line to compensate for invisible line
							screen: output,
							palette: palette
						}))
					})
					.otherwise(() => console.warn('Caught invalid request:', res))
			})
	})

	ws.on('close', () => {
		console.info(`Client disconnected (${wsInstance.getWss().clients.size} online)`)
		if (intervalId)
			clearInterval(intervalId)
	})
})

app.listen(process.env.PORT, () => console.info(`Listening on http://localhost:${process.env.PORT}`))