import "dotenv/config";
import Gameboy from "serverboy";
import ws from "ws";
import fs from "fs";
import { serialize } from "bson";
import path from "path";
import { Logger } from "tslog";
import { Worker } from "worker_threads";

import Fastify from "fastify";
import FastifyWebsocket from "@fastify/websocket";

const fastify = Fastify();
fastify.register(FastifyWebsocket);

// Pretty colors
new Logger({ name: "console", overwriteConsole: true });

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

fastify.get("/listGames", async () =>
    serialize(Object.keys(games)));

// Any API that does operations on the gameboy should be completely asynchronous and require a WS session
fastify.register(async (fastify) => {
    fastify.get("/attach", { websocket: true }, (conn, req) => {
        console.info(`Client connected (${fastify.websocketServer.clients.size} online)`);

        const worker = new Worker(path.join(__dirname, "worker.js"), { workerData: { games, id: req.id } });

        // Handle messages from worker.
        worker.on("message", message => conn.socket.send(message));

        // Send messages to worker.
        conn.socket.on("message", (message: ws.RawData) => worker.postMessage(message));

        conn.socket.on("close", () => {
            worker.terminate();
            console.info(`Client disconnected (${fastify.websocketServer.clients.size} online)`);
        });
    });
});

fastify.listen({ port: parseInt(process.env.PORT, 10) }, err => {
    if (err) {
        console.error(err);
        process.exit(1);
    }

    console.info(`Listening on http://0.0.0.0:${process.env.PORT}`);
});
