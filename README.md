# Roblox Studio MCP Bridge

An [MCP](https://modelcontextprotocol.io) server that lets AI clients such as Cursor/Claude Code
control Roblox Studio: read and edit scripts, inspect the data model, run Luau, start playtests, read the
console etc..

It works as a bridge, meaning the AI client talks to this server over stdio, and a small Studio plugin polls the
server over local HTTP to receive commands and send results back.


```
AI client --MCP/stdio--> main.py (HTTP 127.0.0.1:8767) <--poll/result-- Roblox Studio plugin
```

## Features

23 tools, grouped by area:

| Area | Tools |
|---|---|
| Scripting | `script_read`, `multi_edit`, `script_search`, `script_grep` |
| Assets | `generate_mesh`, `generate_material`, `generate_procedural_model`, `wait_job_finished`, `search_asset`, `insert_asset`, `upload_image`, `store_image` |
| Data model | `subagent`, `search_game_tree`, `inspect_instance` |
| Luau | `execute_luau` |
| Playtesting | `get_studio_state`, `start_stop_play`, `get_console_output`, `screen_capture` |
| Input | `character_navigation`, `user_keyboard_input`, `user_mouse_input` |

The server only forwards commands. What each tool actually does is implemented by the Studio plugin
(see [docs/PROTOCOL.md](docs/PROTOCOL.md)).

## Requirements

- Python 3.10+
- Roblox Studio with **Allow HTTP Requests** enabled (Home -> Game Settings -> Security)
- An MCP client that supports local stdio servers

## Installation

```powershell
git clone https://github.com/YOUR-USER/roblox-studio-mcp.git
cd roblox-studio-mcp
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
```

Quick check (should print `Roblox HTTP bridge running on 127.0.0.1:8767` and then wait; stop with Ctrl+C):

```powershell
.venv\Scripts\python.exe main.py
```

## Connect your AI client

Use the **absolute** paths of the venv's `python.exe` and of `main.py`. Do not leave a manual `main.py`
running while the client starts its own copy, otherwise port 8767 is already taken.

### Cursor

Create or edit `C:\Users\<you>\.cursor\mcp.json` (or Settings -> Tools & MCP -> Add new MCP server):

```json
{
  "mcpServers": {
    "roblox-bridge": {
      "command": "C:\\path\\to\\roblox-studio-mcp\\.venv\\Scripts\\python.exe",
      "args": ["C:\\path\\to\\roblox-studio-mcp\\main.py"]
    }
  }
}
```

### Claude Desktop

Settings -> Developer -> Edit Config, then add the same block (see
[examples/claude_desktop_config.json](examples/claude_desktop_config.json)). Fully quit Claude Desktop
(system tray -> Quit) and reopen it.

### Claude Code

```powershell
claude mcp add roblox-bridge --scope user -- "C:\path\to\roblox-studio-mcp\.venv\Scripts\python.exe" "C:\path\to\roblox-studio-mcp\main.py"
claude mcp list
```

## Studio plugin

Put your plugin in [`plugin/`](plugin/) and install it in Studio (save it as a local plugin). It must poll
`GET /poll` and answer with `POST /result`. A minimal Luau polling loop is in
[docs/PROTOCOL.md](docs/PROTOCOL.md).

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `ROBLOX_MCP_PORT` | `8767` | Port of the local HTTP bridge. Change it in the plugin too. |

## Troubleshooting

| Problem | Fix |
|---|---|
| Server not listed in the client | Wrong config file, or the client was not fully restarted. Use the client's own "Edit Config" button. |
| `No module named 'mcp'` | Install into the same venv the client launches: `pip install -r requirements.txt`. |
| Server crashes right away / `Could not bind port` | Port 8767 is in use. Check `netstat -ano \| findstr 8767` and stop the other process. |
| Tools appear but calls time out (`Timeout waiting for Roblox Studio`) | The plugin is not polling. Check Studio's Output window and that HTTP requests are allowed. |
| Client disconnects immediately | Something wrote to stdout. Only log to stderr (already done in `main.py`). |

## Security

The bridge listens on `127.0.0.1` only and has **no authentication**. Any local program can send commands
that the plugin will execute inside Studio, including `execute_luau`. Do not expose the port to a network,
and only use it on machines you trust.
