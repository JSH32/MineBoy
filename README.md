<p align="center">
	<img width="550" src="https://raw.githubusercontent.com/JSH32/Mineboy/master/.github/assets/logo.png"><br>
	<img src="https://img.shields.io/badge/license-MIT-blue.svg">
	<img src="https://img.shields.io/badge/contributions-welcome-orange.svg">
	<img src="https://img.shields.io/badge/Made%20with-%E2%9D%A4-ff69b4?logo=love">
</p>

## Mineboy
Mineboy is an open source gameboy emulator designed for ComputerCraft. It uses a streaming server and client because the lua runtime in CC is slow.

<details open>
  <summary>Screenshots</summary>

  <table>
    <tr>
      <td><img src="https://raw.githubusercontent.com/JSH32/MineBoy/master/.github/assets/screenshots/2024-04-07_18.36.37.png"  alt="1" width = 500px></td>
      <td><img src="https://raw.githubusercontent.com/JSH32/MineBoy/master/.github/assets/screenshots/2024-04-07_19.10.52.png" alt="2" width = 500px></td>
    </tr> 
  </table>
</details>

[![MineBoy showcase video](https://img.youtube.com/vi/cBW4aGlNsOE/0.jpg)](https://www.youtube.com/watch?v=cBW4aGlNsOE)

## Install guide
### Server
1. Install either [docker and docker compose](https://docs.docker.com/engine/install/) or [NodeJS](https://nodejs.org/en/)
2. Clone this repository.
3. Copy `.env.example` to `.env` and edit with proper config vars.
    - If you are running Mineboy on a public server, you may want to secure the server with a password or prevent abuse from other players. Mineboy has a built-in security policy feature which can limit the number of connections. To use this feature, you must set the `SECURITY` environment variable or fill the `security.json` file with the following information:
      ```json
      [
        {
          "name": "TestPolicy",
          "password": "testpassword",
          "connections": 2
        }
      ]
      ```
      This will ensure that only two connections are allowed using that password/policy at any given time. Additionally, if you set a password, only users who know the password will be able to connect to the server. If the security policy configuration is nonexistant or `[]` it will be unsecured.
4. Create `roms` folder with all GB/GBC roms.
5. Run the script
	* For Node
		* Run `npm install && npm build` to install dependencies.
		* Run `node dist/index.js` to run.
	* For Docker (proffered for headless)
		* Run `docker-compose up -d`
6. Edit all clients `mineboy_config.lua` files with proper `httpUrl` and `wsUrl` settings.
### Client
1. Run `pastebin run JubutEmL` and select the number with a `client`.
2. Edit `mineboy_config.lua` with proper config options.
3. Run `mineboy.lua` (rename to `startup` if you want to run this on startup).

### Controller
1. Make sure the computer you are installing this on has a wireless modem and `rednet` is enabled in `mineboy_config.lua`
2. Run `pastebin run JubutEmL` and select the number with `controller`.
3. Type the rednet ID in the controller (this will be printed on the client).
