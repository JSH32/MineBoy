import "dotenv/config";
import Gameboy from "serverboy";
import { match, P } from "ts-pattern";
import { useTry } from "no-try";
import ws from "ws";
import fs from "fs";
import { serialize, deserialize } from "bson";
import path from "path";
import { Logger } from "tslog";
import { quantizeFrame } from "./utils";
import zlib from "zlib";
import { promisify } from "util";

import Fastify from "fastify";
import FastifyWebsocket from "@fastify/websocket";

const fastify = Fastify();
fastify.register(FastifyWebsocket);

// Pretty colors
new Logger({ name: "console", overwriteConsole: true });

// Gameboy resolution
const WIDTH = 160;
const HEIGHT = 144;

// Send an error message through socket
const sendError = (ws: ws, error: string) =>
    ws.send(serialize({ type: "ERROR", error }));

const getGames = (romDir: string): Record<string, Buffer> => {
    const games = {};

    for (const file of fs.readdirSync(romDir)) {
        const gameboy = new Gameboy();
        const gameBuffer = fs.readFileSync(path.join(romDir, file));

        gameboy.loadRom(gameBuffer);

        // Why the fuck is it hidden like this in serverboy
        games[gameboy[Object.keys(gameboy)[0]].gameboy.name] = gameBuffer;
    }

    return games;
};

// Load games at startup
const games = getGames(path.join(process.cwd(), "roms"));
console.info(`Loaded ${Object.keys(games).length} roms:`, Object.keys(games));

// app.get("/listGames", (_, res) =>
//     res.send(serialize(Object.keys(games))));

fastify.get("/listGames", async () =>
    serialize(Object.keys(games)));

// Any API that does operations on the gameboy should be completely asynchronous and require a WS session
fastify.register(async (fastify) => {
    fastify.get("/*", { websocket: true }, (conn) => {
        console.info(`Client connected (${fastify.websocketServer.clients.size} online)`);

        const gameboy = new Gameboy();
        const keysPressed = new Map<number, number>();
        let gameName = null;

        // 120fps without spamming the eventloop
        // This is null util a game is running
        let intervalId = null;

        conn.socket.on("message", (message: ws.RawData) => {
            const [error, res] = useTry<any>(() => deserialize(message as any));
            if (error) return sendError(conn.socket, "Invalid data provided");

            match(res)
                .with({ type: "SELECT_GAME", index: P.number, save: P.optional(P.any) }, async () => {
                    if (res.index > games.length)
                        return sendError(conn.socket, "Invalid game index selected");

                    const saveData = res.save ? await promisify(zlib.inflate)(Buffer.from(res.save, "base64")) : undefined;
                    gameName = Object.keys(games)[res.index];
                    gameboy.loadRom(games[gameName], saveData);

                    if (!intervalId) {
                        intervalId = setInterval(() => {
                            const keysToPress = [];

                            // For some reason not every keystroke will register the first time so we make it click on three updates
                            for (const [key, count] of keysPressed) {
                                if (count > 0) {
                                    keysToPress.push(key);
                                    keysPressed.set(key, count - 1);
                                }
                            }

                            gameboy.pressKeys(keysToPress);
                            gameboy.doFrame();
                        }, 1000 / 120);
                    }

                    conn.socket.send(serialize({ type: "GAME_STARTED", name: gameName }));
                })
                // Handler for other routes which require game to be running
                .otherwise(() => {
                    if (!intervalId)
                        return sendError(conn.socket, "No game running");

                    match(res)
                        .with({ type: "EXIT_GAME" }, () => {
                            clearInterval(intervalId);
                            intervalId = null;

                            conn.socket.send(serialize({ type: "GAME_EXITED" }));
                        })
                        .with({ type: "GET_SAVE" }, () => {
                        // Compress save due to limited disk storage
                            zlib.deflate(Buffer.from(gameboy.getSaveData()), (_, buffer) => {
                                conn.socket.send(serialize({
                                    type: "SAVE_DATA",
                                    gameName,
                                    data: buffer.toString("base64")
                                }));
                            });
                        })
                        .with({ type: "PRESS_BUTTON", button: P.string }, () => {
                            keysPressed.set(Gameboy.KEYMAP[res.button], 10);
                        })
                        .with({ type: "REQUEST_DRAW" }, async () => {
                            const [palette, output] = quantizeFrame(gameboy.getScreen(), [WIDTH, HEIGHT]);

                            conn.socket.send(serialize({
                                type: "SCREEN_DRAW",
                                width: WIDTH,
                                height: HEIGHT + 1, // Add one line to compensate for invisible line
                                screen: output,
                                palette: palette
                            }));
                        })
                        .otherwise(() => console.warn("Caught invalid request:", res));
                });
        });

        conn.socket.on("close", () => {
            console.info(`Client disconnected (${fastify.websocketServer.clients.size} online)`);
            if (intervalId)
                clearInterval(intervalId);
        });
    });
});

fastify.listen({ port: parseInt(process.env.PORT, 10) }, err => {
    if (err) {
        console.error(err);
        process.exit(1);
    }

    console.info(`Listening on http://localhost:${process.env.PORT}`);
});
