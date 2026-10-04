import asyncio
import json
import logging
import queue
import threading
import uuid

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from mcp.server.fastmcp import FastMCP

PORT = 8767
mcp = FastMCP("roblox-studio")
commands = queue.Queue()
pending = {}

class Bridge(BaseHTTPRequestHandler):

    def log_message(self, *args):
        """
        Disable the default HTTP server logging.
        """
        pass

    def _send(self, code: int, body: str = ""):
        """
        Send an HTTP response.
        """

        body_bytes = body.encode("utf-8")

        self.send_response(code)

        self.send_header(
            "Content-Type",
            "application/json"
        )

        self.send_header(
            "Content-Length",
            str(len(body_bytes))
        )

        self.end_headers()

        self.wfile.write(body_bytes)

    def do_GET(self):
        """
        Handle GET requests from the Roblox Studio plugin.
        """

        if self.path != "/poll":
            self._send(
                404,
                json.dumps({
                    "error": "Not found"
                })
            )
            return

        try:
            command = commands.get(timeout=20)

        except queue.Empty:

            self._send(204)
            return

        self._send(
            200,
            json.dumps(command)
        )

    def do_POST(self):
        """
        Handle results coming back from Roblox Studio.
        """

        if self.path != "/result":
            self._send(
                404,
                json.dumps({
                    "error": "Not found"
                })
            )
            return

        try:

            content_length = int(
                self.headers.get(
                    "Content-Length",
                    0
                )
            )

            body = self.rfile.read(
                content_length
            )

            data = json.loads(body)

            command_id = data["id"]
            if command_id not in pending:
                self._send(
                    404,
                    json.dumps({
                        "error": "Unknown command ID"
                    })
                )
                return
            pending[command_id]["result"] = data.get(
                "result"
            )
            pending[command_id]["event"].set()
            self._send(
                200,
                json.dumps({
                    "ok": True
                })
            )
        except Exception as error:
            self._send(
                400,
                json.dumps({
                    "error": str(error)
                })
            )

# SEND COMMAND TO ROBLOX STUDIO

async def send_to_studio(
    action: str,
    args: dict,
    timeout: float = 30
) -> str:
    """
    Send a command to the Roblox Studio plugin
    and wait for the result.
    """

    command_id = uuid.uuid4().hex
    event = threading.Event()

    pending[command_id] = {
        "event": event,
        "result": None
    }

    commands.put({
        "id": command_id,
        "action": action,
        "args": args
    })

    try:
        completed = await asyncio.to_thread(
            event.wait,
            timeout
        )
        if not completed:

            return (
                f"Timeout waiting for Roblox Studio: "
                f"{action}"
            )
        result = pending[command_id]["result"]
        if isinstance(result, dict):
            if "error" in result:
                return (
                    "Roblox Studio error: "
                    f"{result['error']}"
                )
            return result.get(
                "output",
                json.dumps(result)
            )
        return str(result)

    finally:
        pending.pop(
            command_id,
            None
        )


# SCRIPTING

@mcp.tool()
async def script_read(path: str) -> str:
    """
    Read the source code of a Roblox script.

    Args:
        path: Roblox instance path to the script.
    """

    return await send_to_studio(
        "script_read",
        {
            "path": path
        }
    )


@mcp.tool()
async def multi_edit(
    path: str,
    edits: list[dict]
) -> str:
    """
    Apply multiple edits to a Roblox script.

    Args:
        path: Roblox instance path.
        edits: List of edit operations.
    """

    return await send_to_studio(
        "multi_edit",
        {
            "path": path,
            "edits": edits
        }
    )


@mcp.tool()
async def script_search(
    query: str
) -> str:
    """
    Search Roblox scripts for a text or pattern.

    Args:
        query: Text or pattern to search for.
    """

    return await send_to_studio(
        "script_search",
        {
            "query": query
        }
    )


@mcp.tool()
async def script_grep(
    query: str,
    path: str = ""
) -> str:
    """
    Search scripts recursively.

    Args:
        query: Text or pattern to search for.
        path: Optional root path.
    """

    return await send_to_studio(
        "script_grep",
        {
            "query": query,
            "path": path
        }
    )

# ASSETS

@mcp.tool()
async def generate_mesh(
    parameters: dict
) -> str:
    """
    Generate a mesh in Roblox Studio.

    Args:
        parameters: Mesh generation parameters.
    """

    return await send_to_studio(
        "generate_mesh",
        {
            "parameters": parameters
        }
    )

@mcp.tool()
async def generate_material(
    parameters: dict
) -> str:
    """
    Generate or configure a material.

    Args:
        parameters: Material configuration.
    """

    return await send_to_studio(
        "generate_material",
        {
            "parameters": parameters
        }
    )

@mcp.tool()
async def generate_procedural_model(
    parameters: dict
) -> str:
    """
    Generate a procedural 3D model.

    Args:
        parameters: Model generation parameters.
    """

    return await send_to_studio(
        "generate_procedural_model",
        {
            "parameters": parameters
        }
    )

@mcp.tool()
async def wait_job_finished(
    job_id: str
) -> str:
    """
    Wait for an asynchronous Studio job.

    Args:
        job_id: Job ID.
    """

    return await send_to_studio(
        "wait_job_finished",
        {
            "job_id": job_id
        }
    )

@mcp.tool()
async def search_asset(
    query: str
) -> str:
    """
    Search for a Roblox asset.

    Args:
        query: Asset search query.
    """

    return await send_to_studio(
        "search_asset",
        {
            "query": query
        }
    )

@mcp.tool()
async def insert_asset(
    asset_id: str,
    parent: str = "Workspace"
) -> str:
    """
    Insert an asset into Roblox Studio.

    Args:
        asset_id: Asset ID.
        parent: Parent instance path.
    """

    return await send_to_studio(
        "insert_asset",
        {
            "asset_id": asset_id,
            "parent": parent
        }
    )

@mcp.tool()
async def upload_image(
    path: str
) -> str:
    """
    Upload an image.

    Args:
        path: Local image path.
    """

    return await send_to_studio(
        "upload_image",
        {
            "path": path
        }
    )


@mcp.tool()
async def store_image(
    image_id: str,
    path: str
) -> str:
    """
    Store an uploaded image.

    Args:
        image_id: Image ID.
        path: Roblox destination path.
    """

    return await send_to_studio(
        "store_image",
        {
            "image_id": image_id,
            "path": path
        }
    )

# DATA MODEL

@mcp.tool()
async def subagent(
    task: str
) -> str:
    """
    Delegate a task to a subagent.

    Args:
        task: Task description.
    """

    return await send_to_studio(
        "subagent",
        {
            "task": task
        }
    )

@mcp.tool()
async def search_game_tree(
    query: str
) -> str:
    """
    Search the Roblox game hierarchy.

    Args:
        query: Search query.
    """

    return await send_to_studio(
        "search_game_tree",
        {
            "query": query
        }
    )

@mcp.tool()
async def inspect_instance(
    path: str
) -> str:
    """
    Inspect a Roblox instance.

    Args:
        path: Roblox instance path.
    """

    return await send_to_studio(
        "inspect_instance",
        {
            "path": path
        }
    )

# LUAU

@mcp.tool()
async def execute_luau(
    code: str
) -> str:
    """
    Execute Luau code inside Roblox Studio.

    Args:
        code: Luau source code.
    """

    return await send_to_studio(
        "execute_luau",
        {
            "code": code
        }
    )

# PLAYTESTING

@mcp.tool()
async def get_studio_state() -> str:
    """
    Get the current Roblox Studio state.
    """

    return await send_to_studio(
        "get_studio_state",
        {}
    )


@mcp.tool()
async def start_stop_play(
    action: str
) -> str:
    """
    Start or stop Roblox Studio play mode.

    Args:
        action: 'start' or 'stop'.
    """

    return await send_to_studio(
        "start_stop_play",
        {
            "action": action
        }
    )


@mcp.tool()
async def get_console_output() -> str:
    """
    Get Roblox Studio console output.
    """

    return await send_to_studio(
        "get_console_output",
        {}
    )


@mcp.tool()
async def screen_capture() -> str:
    """
    Capture the Roblox Studio screen.
    """

    return await send_to_studio(
        "screen_capture",
        {}
    )


# INPUT

@mcp.tool()
async def character_navigation(
    direction: str,
    duration: float = 1.0
) -> str:
    """
    Move the player character.

    Args:
        direction: Direction to move.
        duration: Movement duration in seconds.
    """

    return await send_to_studio(
        "character_navigation",
        {
            "direction": direction,
            "duration": duration
        }
    )

@mcp.tool()
async def user_keyboard_input(
    key: str,
    action: str = "press"
) -> str:
    """
    Send keyboard input.

    Args:
        key: Keyboard key.
        action: press, release, or hold.
    """

    return await send_to_studio(
        "user_keyboard_input",
        {
            "key": key,
            "action": action
        }
    )

@mcp.tool()
async def user_mouse_input(
    action: str,
    x: int,
    y: int
) -> str:
    """
    Send mouse input.

    Args:
        action: Mouse action.
        x: Screen X coordinate.
        y: Screen Y coordinate.
    """

    return await send_to_studio(
        "user_mouse_input",
        {
            "action": action,
            "x": x,
            "y": y
        }
    )

async def test():
    result = await send_to_studio(
    "search_game_tree",
        {
            "query": "Part",
            "path": "game.Workspace"
        }
    )
    print(result)

# START SERVER

if __name__ == "__main__":

    http_server = ThreadingHTTPServer(
        ("127.0.0.1", PORT),
        Bridge
    )

    thread = threading.Thread(
        target=http_server.serve_forever,
        daemon=True
    )

    thread.start()

    logging.info(
        f"Roblox HTTP bridge running "
        f"on 127.0.0.1:{PORT}"
    )

    mcp.run(
        transport="stdio"
    )