# Mineboy protocol
This is the Mineboy communication protocol used between the server and client.
# REST
#### `GET /listGames`
**Description:** Get a list of all games on the server.\
**Example Response:**
```js
[
	"GAME1",
	"GAME2"
]
```
#### `GET /attach`
**Description:** Initiate a socket session, refer to [connection](#connection) for session protocol.

# Connection
The connection is fully asyncronous, no job IDs are provided. When you send messages you will recieve the corresponding reply at any moment in the future. Only one emulation is run per session and the emulation runs in the background, updates are not manually requested.

This connection is initiated as a websocket by [`attach`](#get-attach).

## Requests

---

#### `SELECT_GAME`
**Description**: Select game based on index provided from [listGames](#get-listgames). Save data can be retrieved with [`GET_SAVE`](#getsave).\
**Response:** [`GAME_STARTED`](#gamestarted)\
**Example:**
```js
{
	"type": "SELECT_GAME",
	"index": 0, // Index from listGames
	"save": [], // Zlib compressed save data retrieved by GET_SAVE.
	"autoSave": true // Should the game listen for memory bank writing and send SAVE_DATA when save is triggered.
}
```

---

#### `EXIT_GAME`
**Description:** Exit the currently running game.\
**Response**: [`GAME_EXITED`](#gameexited)\
**Example**:
```js
{ "type": "EXIT_GAME" }
```

---

#### `GET_SAVE`
**Description:** Get zlib compressed save data.\
**Response**: [`SAVE_DATA`](#savedata)\
**Example**:
```js
{ "type": "GET_SAVE" }
```

---

#### `PRESS_BUTTON`
**Description:** Press a button.\
**Response**: None\
**Example**:
```js
{ 
	"type": "PRESS_BUTTON",
	// One of ["LEFT", "RIGHT", "UP", "DOWN", "A", "B", "SELECT", "START]
	"button": "A"
}
```

---

#### `REQUEST_DRAW`
**Description:** Request a frame from the emulator.\
**Response**: [`SCREEN_DRAW`](#screendraw)\
**Example**:
```js
{ "type": "REQUEST_DRAW" }
```

---

## Responses

---

#### `GAME_STARTED`
**Description:** Game has been started.\
**Request**: [`SELECT_GAME`](#selectgame)\
**Example**:
```js
{
	"type": "GAME_STARTED",
	"name": "Game Name"
}
```

---

#### `GAME_EXITED`
**Description:** Game has been exited.\
**Request**: [`EXIT_GAME`](#exitgame)\
**Example**:
```js
{ "type": "GAME_EXITED" }
```

---

#### `SAVE_DATA`
**Description:** Zlib compressed buffer of the save memory.\
**Request**: [`GET_SAVE`](#getsave)\
**Example**:
```js
{ 
	"type": "SAVE_DATA",
	"data": [], // zlib compressed save data.
	"auto": true // Is this save an autosave? Autosaves are sent without SAVE_DATA requests by the server.
}
```

---

#### `SCREEN_DRAW`
**Description:** Rendered frame and palette of emulator.\
**Request**: [`REQUEST_DRAW`](#requestdraw)\
**Example**:
```js
{ 
	"type": "SCREEN_DRAW",
	"width": 160, // This is always 160
	"height": 145, // This is always 145
	// Palette with 16 colors
	"palette": [
		[ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ],
		[ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ],
		[ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ],
		[ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ], [ 0, 0, 0 ],
	],
	// Screen buffer of indexes corresponding to palette color.
	// This is a buffer of size (height * width / 2).
	// Each value in the buffer is an 8 bit number that stores two 4 bit indexes from 0-15.
	"screen": []
}
```

---
