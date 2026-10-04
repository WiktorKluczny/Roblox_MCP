# Studio plugin

Put your Roblox Studio plugin (Luau) in this folder, for example `RobloxMCP.server.lua`.

The plugin must implement the protocol described in [`docs/PROTOCOL.md`](../docs/PROTOCOL.md):
poll `GET http://127.0.0.1:8767/poll`, run the received action, and send the result to
`POST http://127.0.0.1:8767/result`.

Requirements in Studio:
- Home -> Game Settings -> Security -> **Allow HTTP Requests** enabled
- Accept the HTTP permission prompt for the plugin the first time
