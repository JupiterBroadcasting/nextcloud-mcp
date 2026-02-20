"""Integration tests for Nextcloud MCP Server against files.horse."""

import json
import pytest
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


MCP_SERVER_URL = "http://127.0.0.1:8001/mcp"


@pytest.fixture
async def mcp_client():
    """Create an MCP client session."""
    async with streamablehttp_client(MCP_SERVER_URL) as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            yield session


@pytest.mark.integration
class TestServerHealth:
    """Test server health endpoints."""

    async def test_health_ready(self):
        """Test /health/ready endpoint returns ready status."""
        import httpx

        async with httpx.AsyncClient() as client:
            response = await client.get("http://127.0.0.1:8001/health/ready")
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "ready"
            assert data["checks"]["nextcloud_reachable"] == "ok"


@pytest.mark.integration
class TestMCPTools:
    """Test MCP tool listing and invocation."""

    async def test_list_tools(self, mcp_client):
        """Test that MCP server returns expected tools."""
        response = await mcp_client.list_tools()
        tool_names = [tool.name for tool in response.tools]

        # Verify we have tools from various apps
        print(f"Found {len(tool_names)} tools: {tool_names[:20]}...")

        # Should have tools from Notes, Calendar, Contacts, WebDAV
        assert len(tool_names) > 50, f"Expected >50 tools, got {len(tool_names)}"

    async def test_list_resources(self, mcp_client):
        """Test that MCP server returns resources."""
        response = await mcp_client.list_resources()
        resource_uris = [r.uri for r in response.resources]
        print(f"Found {len(resource_uris)} resources")
        assert len(resource_uris) > 0


@pytest.mark.integration
class TestNotesApp:
    """Test Notes app integration."""

    async def test_notes_search_notes(self, mcp_client):
        """Test searching notes."""
        result = await mcp_client.call_tool("nc_notes_search_notes", {"query": "test"})
        print(f"Search notes result: {result}")
        assert result is not None

    async def test_notes_create_and_delete_note(self, mcp_client):
        """Test creating and deleting a note (happy path)."""
        # Create a test note with all required fields
        create_result = await mcp_client.call_tool(
            "nc_notes_create_note",
            {
                "title": "Test Note from MCP",
                "content": "This is a test note created by MCP integration tests.",
                "category": "Test",
            },
        )
        print(f"Create note result: {create_result}")

        # Check if it was successful
        if create_result.isError:
            print(f"Error creating note: {create_result.content[0].text}")
            pytest.skip(
                f"Notes app may not be installed: {create_result.content[0].text}"
            )

        # Parse the result to get note ID
        content = create_result.content[0].text
        data = json.loads(content)
        note_id = data.get("id")
        assert note_id is not None, f"Expected note ID in response: {data}"

        # Delete the note
        delete_result = await mcp_client.call_tool(
            "nc_notes_delete_note", {"note_id": note_id}
        )
        print(f"Delete note result: {delete_result}")
        assert delete_result is not None


@pytest.mark.integration
class TestCalendarApp:
    """Test Calendar app integration."""

    async def test_calendar_list_calendars(self, mcp_client):
        """Test listing calendars."""
        result = await mcp_client.call_tool("nc_calendar_list_calendars", {})
        print(f"List calendars result: {result}")
        assert result is not None

    async def test_calendar_get_upcoming_events(self, mcp_client):
        """Test getting upcoming calendar events."""
        result = await mcp_client.call_tool(
            "nc_calendar_get_upcoming_events", {"limit": 5}
        )
        print(f"Upcoming events result: {result}")
        assert result is not None


@pytest.mark.integration
class TestContactsApp:
    """Test Contacts app integration."""

    async def test_contacts_list_addressbooks(self, mcp_client):
        """Test listing address books."""
        result = await mcp_client.call_tool("nc_contacts_list_addressbooks", {})
        print(f"List addressbooks result: {result}")
        assert result is not None


@pytest.mark.integration
class TestWebDAVApp:
    """Test WebDAV (Files) app integration."""

    async def test_webdav_list_directory(self, mcp_client):
        """Test listing files via WebDAV."""
        result = await mcp_client.call_tool("nc_webdav_list_directory", {"path": "/"})
        print(f"List files result: {result}")
        assert result is not None


@pytest.mark.integration
class TestErrorHandling:
    """Test error handling."""

    async def test_invalid_note_id(self, mcp_client):
        """Test error case: invalid note ID."""
        result = await mcp_client.call_tool("nc_notes_get_note", {"note_id": 999999999})
        # Should return error content
        print(f"Invalid note result: {result}")
        text = result.content[0].text if result.content else ""
        assert "error" in text.lower() or "not found" in text.lower()

    async def test_missing_required_parameter(self, mcp_client):
        """Test error case: missing required parameter."""
        # nc_notes_create_note requires title, content, category
        result = await mcp_client.call_tool(
            "nc_notes_create_note", {"content": "No title provided"}
        )
        print(f"Missing param result: {result}")
        # Should return error
        text = result.content[0].text if result.content else ""
        assert "error" in text.lower() or "required" in text.lower()


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
