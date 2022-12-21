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
import chalk from "chalk";


// Pretty colors
const logger = new Logger({ name: "main", overwriteConsole: true });

/**
 * Optionally you can enable encryption for public servers.
 * This is a simple key/password encryption.
 */
let securityPolicies: {
	name: string,
	password: string,
	connections?: number
}[] = [];

if (process.env["SECURITY"] || fs.existsSync("./security.json")) {
  securityPolicies = JSON.parse(process.env["SECURITY"] || fs.readFileSync("./security.json", { encoding:"utf8", flag:"r" }));

  // Make sure no duplicate entries exist.
  for (const current of securityPolicies) {
    const matches = securityPolicies.filter(e => e.name === current.name || e.password === current.password);
    if (matches.length > 1) {
      logger.fatal(`Security policy ${chalk.yellow(current.name)} has either a duplicate name or password with another entry.`);
      process.exit(1);
    }
  }
}

console.info(`Mineboy started${securityPolicies.length && ` with ${securityPolicies.length} security policies`}.`);

const fastify = Fastify();
fastify.register(FastifyWebsocket);

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

// All currently connected sessions.
const sessions: Record<string, {
	id: string,
	// Name of used security policy.
	securityPolicy?: string;
}> = {};

// Any API that does operations on the gameboy should be completely asynchronous and require a WS session
fastify.register(async (fastify) => {
  fastify.addHook<{
    Headers: { password?: string }
  }>("preValidation", async (req, res) => {
    if (securityPolicies.length) {
      if (!req?.headers?.password)
        return await res.code(401).send("Password is required");

      const securityPolicy = securityPolicies.find(e => e.password === req.headers.password);

      // Check if connections exceed limit.
      if (
        securityPolicy.connections
        && Object.values(sessions).filter(s => s.securityPolicy === securityPolicy.name).length >= securityPolicy.connections
      ) {
        await res.code(401).send(`The security policy ${chalk.yellow(securityPolicy.name)} has a concurrent limit of ${securityPolicy.connections} connections.`);
      }
    }
  });

  fastify.get<{
    Headers: { password?: string }
  }>("/attach", { websocket: true }, (conn, req) => {
    const securityPolicy = securityPolicies.find(e => e.password === req?.headers?.password);

    const loggerPrefix = chalk.gray(`[id: ${chalk.yellow(req.id)}${securityPolicy ? `, security: ${chalk.yellow(securityPolicy.name)}` : ""}]`);
    const clientLogger = logger.getChildLogger({
      overwriteConsole: false,
      name: `main-${req.id}`,
      prefix: [loggerPrefix]
    });

    const worker = new Worker(path.join(__dirname, "worker.js"), { workerData: { games, id: req.id, loggerPrefix } });

    sessions[req.id] = {
      id: req.id,
      securityPolicy: securityPolicy?.name,
    };

    clientLogger.info(`Client connected (${fastify.websocketServer.clients.size} online)`);

    // Handle messages from worker.
    worker.on("message", message => conn.socket.send(message));

    // Send messages to worker.
    conn.socket.on("message", (message: ws.RawData) => worker.postMessage(message));

    conn.socket.on("close", () => {
      worker.terminate();
      delete sessions[req.id];
      clientLogger.info(`Client disconnected (${fastify.websocketServer.clients.size} online)`);
    });
  });
});

fastify.listen({ host: "0.0.0.0", port: parseInt(process.env.PORT, 10) }, err => {
  if (err) {
    console.error(err);
    process.exit(1);
  }

  console.info(`Listening on http://0.0.0.0:${process.env.PORT}`);
});
