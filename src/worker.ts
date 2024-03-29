import { parentPort, workerData } from "worker_threads";
import Gameboy from "serverboy";
import { deserialize, serialize } from "bson";
import { useTry } from "no-try";
import { match, P } from "ts-pattern";
import zlib from "zlib";
import { promisify } from "util";
import { quantizeFrame } from "./utils";
import { Logger } from "tslog";
import chalk from "chalk";

new Logger({
  name: `worker-${workerData.id}`,
  overwriteConsole: true,
  prefix: [workerData.loggerPrefix]
});

console.info("Started worker");

const gameboy = new Gameboy();
const keysPressed = new Map<number, number>();

// Name of game that is currently being played.
let gameName = null;

// Gameboy resolution
const WIDTH = 160;
const HEIGHT = 144;

// Interval of the Gameboy CPU cycle loop.
// Should be emulated to 120 cycles per second.
let intervalId = null;

// Send error to the client.
const sendError = (error: string) =>
  sendClient({ type: "ERROR", error });

// Send a BSON encoded message to the client.
const sendClient = (data: object) =>
  parentPort.postMessage(serialize(data));

// We use a worker since the GameBoy emulation loop is not performant when using more than one emulator instance.
parentPort.on("message", message => {
  const [error, res] = useTry<any>(() => deserialize(message as any));
  if (error) return sendError("Invalid data provided");

  match(res)
    .with({ type: "SELECT_GAME", index: P.number, save: P.optional(P.any), autoSave: P.boolean }, async () => {
      if (res.index > workerData.games.length)
        return sendError("Invalid game index selected");

      const saveData = res.save ? await promisify(zlib.inflate)(Buffer.from(res.save, "base64")) : undefined;
      gameName = Object.keys(workerData.games)[res.index];
      gameboy.loadRom(workerData.games[gameName], saveData);

      // Serverboy is built like hot garbage and they feel the need to obfuscte anything stored on the gameboy
      // behind a private object. This is a dumb hack because there is only one element in the public object.
      // TODO: Replace this stupid shit with something else.
      const gameboyPrivate = gameboy[Object.keys(gameboy)[0]].gameboy;

      // Create a proxy listener for MBCRam
      if (res.autoSave && gameboyPrivate.cBATT && gameboyPrivate.MBCRam.length != 0) {
        const saveRam = gameboyPrivate.MBCRam;

        // After first save change this is changed to a timeout, it will be
        // cancelled and overridden on every byte until it finally runs and sends the SAVE_DATA
        let throttleId = null;

        // Set the internal ram to the proxy of the actual save array.
        gameboyPrivate.MBCRam = new Proxy(saveRam, {
          set(target, property, value) {
            target[property] = value;

            // Clear timeout just in case it hasn't finished yet.
            clearTimeout(throttleId);

            // Set new timeout that will run after no changes have been made for 1 second.
            throttleId = setTimeout(() => {
              // Send save when change made to MBC save ram.
              zlib.deflate(Buffer.from(saveRam), (_, buffer) => {
                sendClient({
                  type: "SAVE_DATA",
                  gameName,
                  auto: true,
                  data: buffer.toString("base64")
                });
              });
            }, 1000);

            return true;
          }
        });
      }

      if (!intervalId) {
        intervalId = setInterval(() => {
          const keysToPress = [];

          // A single tap doesn't always register as holding down a button for long enough to do anything.
          // We can assume that holding down for three updates is a good emulation of actually pressing a button.
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

      console.info(`Client is playing ${chalk.magenta(gameName)}`);
      sendClient({ type: "GAME_STARTED", name: gameName });
    })
    // Handler for other routes which require game to be running
    .otherwise(() => {
      if (!intervalId)
        return sendError("No game running");

      match(res)
        .with({ type: "EXIT_GAME" }, () => {
          clearInterval(intervalId);
          intervalId = null;

          console.info(`Client has stopped playing ${chalk.magenta(gameName)}`);
          sendClient({ type: "GAME_EXITED" });
        })
        .with({ type: "GET_SAVE" }, () => {
          // Compress save due to limited disk storage
          zlib.deflate(Buffer.from(gameboy.getSaveData()), (_, buffer) => {
            sendClient({
              type: "SAVE_DATA",
              gameName,
              auto: false,
              data: buffer.toString("base64")
            });
          });
        })
        .with({ type: "PRESS_BUTTON", button: P.string }, () => {
          keysPressed.set(Gameboy.KEYMAP[res.button], 10);
        })
        .with({ type: "REQUEST_DRAW" }, async () => {
          const [palette, output] = quantizeFrame(gameboy.getScreen(), [WIDTH, HEIGHT]);

          sendClient({
            type: "SCREEN_DRAW",
            width: WIDTH,
            height: HEIGHT + 1, // Add one line to compensate for invisible line
            screen: output,
            palette: palette
          });
        })
        .otherwise(() => console.warn("Caught invalid request:", res));
    });
});
