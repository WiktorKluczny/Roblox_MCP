#Roblox MCP Bridge

A custom Model Context Protocol (MCP) bridge that connects AI assistants such as Claude directly to Roblox Studio.

The project creates a communication layer between an MCP server written in Python and a Roblox Studio plugin written in LUA, allowing an AI assistant to inspect, edit, and interact with a Roblox project through structured tools.

#Architecture
AI Assistant (Claude)
        │
        │ MCP
        ▼
Python MCP Server
        │
        │ HTTP
        ▼
Roblox Studio Plugin
        │
        ▼
Roblox Game

#Current Features
-Read and search Roblox scripts
-Edit Roblox Lua/Luau source code
-Search the Roblox game hierarchy
-Inspect instances and attributes
-Create, modify, and delete instances
-Read and modify Studio selections
-Execute Luau inside Studio
-Capture Studio console output
-Insert Roblox assets
-Communicate through a local HTTP bridge

Extensible handler-based architecture for adding new tools

#Tech Stack
Python
Model Context Protocol (MCP)
Luau
Roblox Studio Plugin API
Local HTTP communication
Claude / MCP-compatible AI assistants
Goal

The long-term goal is to create a powerful development bridge that allows AI agents to work directly with Roblox Studio rather than only generating code externally.

This project is experimental and actively evolving.
