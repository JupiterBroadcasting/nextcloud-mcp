#!/usr/bin/env python3
"""Test script to connect to Nextcloud MCP server using streamable-http."""

import asyncio
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


async def main():
    # Connect to the running MCP server using streamable-http transport
    async with streamable_http_client("http://localhost:8001/mcp") as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # List available tools
            tools = await session.list_tools()
            print("Available WebDAV tools:")
            for tool in tools.tools:
                if "webdav" in tool.name.lower():
                    print(f"  - {tool.name}")

            # Try to list files in the authenticated user's home folder
            print("\n--- Listing files in authenticated user's home folder via MCP ---")
            result = await session.call_tool(
                "nc_webdav_list_directory", {"path": ""}
            )
            print(result)


if __name__ == "__main__":
    asyncio.run(main())
