#!/usr/bin/env python3
"""Freigang container launcher TUI using textual."""

import json
import os
import sys
from pathlib import Path

from textual import on
from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Button, Checkbox, Footer, Header, Label, Select, Static


# Fallback MCP servers if environment variable is not set
DEFAULT_MCP_SERVERS_CONFIG = [
    {"name": "playwright", "package": "@playwright/mcp", "description": "Browser automation"},
    {"name": "filesystem", "package": "@anthropic/mcp-server-filesystem", "description": "File operations"},
    {"name": "memory", "package": "@anthropic/mcp-server-memory", "description": "Persistent memory"},
    {"name": "fetch", "package": "@anthropic/mcp-server-fetch", "description": "HTTP fetch"},
]


class SecretStatus(Static):
    """Display secret file status."""

    def __init__(self, name: str, present: bool) -> None:
        icon = "✓" if present else "✗"
        style = "green" if present else "red"
        super().__init__(f"[{style}]{icon}[/] {name}")


class LauncherApp(App):
    """Freigang container launcher application."""

    CSS = """
    Screen {
        layout: vertical;
    }

    #main-container {
        height: auto;
        padding: 1 2;
    }

    .section {
        height: auto;
        margin-bottom: 1;
        border: solid $primary;
        padding: 0 1;
    }

    .context-line {
        height: 1;
        padding: 0;
    }

    .inline-row {
        layout: horizontal;
        height: auto;
        align: left middle;
    }

    .inline-label {
        width: auto;
        padding-right: 1;
    }

    .inline-select {
        width: 1fr;
        max-width: 40;
    }

    .mcp-grid {
        layout: horizontal;
        height: auto;
    }

    .mcp-checkbox {
        width: auto;
        margin-right: 2;
    }

    .secrets-grid {
        layout: horizontal;
        height: auto;
    }

    #button-row {
        height: auto;
        margin-top: 1;
        align: center middle;
    }

    #button-row Button {
        margin: 0 2;
    }

    #start-button {
        background: $success;
    }

    #exit-button {
        background: $error;
    }
    """

    BINDINGS = [
        ("q", "quit", "Exit"),
        ("enter", "start", "Start"),
    ]

    def __init__(self, config: dict) -> None:
        super().__init__()
        self.config = config
        self.result = None

    def compose(self) -> ComposeResult:
        yield Header(show_clock=False)

        with Vertical(id="main-container"):
            # Context - single compact line
            with Vertical(classes="section"):
                context_str = (
                    f"Host: [bold]{self.config['hostname']}[/]  |  "
                    f"Image: [bold]{self.config['container_image']}[/]  |  "
                    f"Repo: [bold]{self.config['repo_name']}[/]"
                )
                yield Static(context_str, classes="context-line")

            # Permission Mode + Session in one box
            with Vertical(classes="section"):
                with Horizontal(classes="inline-row"):
                    yield Label("Permission:", classes="inline-label")
                    yield Select(
                        [(mode, mode) for mode in self.config["permission_modes"]],
                        value=self.config["default_permission_mode"],
                        id="permission-mode",
                        classes="inline-select",
                    )
                with Horizontal(classes="inline-row"):
                    yield Label("Session:", classes="inline-label")
                    session_options = [("Start fresh", "new"), ("Continue last", "continue")]
                    for sess in self.config.get("sessions", []):
                        session_options.append((f"Resume: {sess['date']}", sess["id"]))
                    yield Select(
                        session_options,
                        value="new",
                        id="session",
                        classes="inline-select",
                    )

            # MCP Servers
            with Vertical(classes="section"):
                yield Label("MCP Servers:")
                with Horizontal(classes="mcp-grid"):
                    for server in self.config["mcp_servers"]:
                        name = server["name"]
                        enabled = name in self.config["default_mcp_servers"]
                        yield Checkbox(
                            server["description"],
                            value=enabled,
                            id=f"mcp-{name}",
                            classes="mcp-checkbox",
                        )

            # Secrets Status
            with Vertical(classes="section"):
                with Horizontal(classes="secrets-grid"):
                    yield Label("Secrets:")
                    for secret in self.config["secrets"]:
                        yield SecretStatus(secret["name"], secret["present"])

            # Buttons
            with Horizontal(id="button-row"):
                yield Button("Start", id="start-button", variant="success")
                yield Button("Exit", id="exit-button", variant="error")

        yield Footer()

    @on(Button.Pressed, "#start-button")
    def handle_start(self) -> None:
        self.collect_and_exit(start=True)

    @on(Button.Pressed, "#exit-button")
    def handle_exit(self) -> None:
        self.collect_and_exit(start=False)

    def action_start(self) -> None:
        self.collect_and_exit(start=True)

    def action_quit(self) -> None:
        self.collect_and_exit(start=False)

    def collect_and_exit(self, start: bool) -> None:
        if not start:
            self.result = {"action": "exit"}
            self.exit()
            return

        # Collect permission mode
        permission_select = self.query_one("#permission-mode", Select)
        permission_mode = permission_select.value

        # Collect MCP servers
        mcp_servers = []
        for server in self.config["mcp_servers"]:
            checkbox = self.query_one(f"#mcp-{server['name']}", Checkbox)
            if checkbox.value:
                mcp_servers.append(server["name"])

        # Collect session
        session_select = self.query_one("#session", Select)
        session_value = session_select.value

        if session_value == "new":
            session_arg = ""
        elif session_value == "continue":
            session_arg = "--continue"
        else:
            session_arg = f"--resume {session_value}"

        self.result = {
            "action": "start",
            "permission_mode": permission_mode,
            "mcp_servers": mcp_servers,
            "session_arg": session_arg,
        }
        self.exit()


def load_config() -> dict:
    """Load configuration from environment and filesystem."""
    agent_home = os.environ.get("AGENT_HOME", "/home/ha_agent")
    repo_name = os.environ.get("REPO_NAME", "hadmin")
    container_image = os.environ.get("CONTAINER_IMAGE", "claude-ha-agent")

    # Permission modes
    permission_modes_str = os.environ.get(
        "PERMISSION_MODES", "default,acceptEdits,bypassPermissions,plan,dontAsk"
    )
    permission_modes = [m.strip() for m in permission_modes_str.split(",") if m.strip()]
    default_permission_mode = os.environ.get("DEFAULT_PERMISSION_MODE", "bypassPermissions")

    # MCP servers from environment (format: "name:package:description|...")
    mcp_servers_str = os.environ.get("AVAILABLE_MCP_SERVERS", "")
    mcp_servers = []
    if mcp_servers_str:
        for entry in mcp_servers_str.split("|"):
            entry = entry.strip()
            if entry:
                parts = entry.split(":", 2)
                if len(parts) >= 3:
                    mcp_servers.append({"name": parts[0], "package": parts[1], "description": parts[2]})

    # Use fallback if no servers parsed
    if not mcp_servers:
        mcp_servers = DEFAULT_MCP_SERVERS_CONFIG

    default_mcp_str = os.environ.get("DEFAULT_MCP_SERVERS", "playwright")
    default_mcp_servers = [m.strip() for m in default_mcp_str.split(",") if m.strip()]

    # Secrets status
    secrets_dir = Path(agent_home) / "workspace" / ".secrets"
    required_secrets_str = os.environ.get("REQUIRED_SECRETS", "github_token|ha_access_token")
    optional_secrets_str = os.environ.get("OPTIONAL_SECRETS", "")

    secrets = []
    for entry in (required_secrets_str + "|" + optional_secrets_str).split("|"):
        entry = entry.strip()
        if entry:
            parts = entry.split(":", 1)
            name = parts[0]
            present = (secrets_dir / name).exists()
            secrets.append({"name": name, "present": present})

    # Sessions
    sessions_dir = Path(agent_home) / "workspace" / repo_name / ".claude" / "projects"
    sessions = []
    if sessions_dir.exists():
        for f in sorted(sessions_dir.glob("**/*.jsonl"), key=lambda x: x.stat().st_mtime, reverse=True)[:5]:
            from datetime import datetime
            mtime = datetime.fromtimestamp(f.stat().st_mtime)
            sessions.append({"id": f.stem, "date": mtime.strftime("%Y-%m-%d %H:%M")})

    import socket
    hostname = socket.gethostname()

    return {
        "hostname": hostname,
        "container_image": container_image,
        "repo_name": repo_name,
        "permission_modes": permission_modes,
        "default_permission_mode": default_permission_mode,
        "mcp_servers": mcp_servers,
        "default_mcp_servers": default_mcp_servers,
        "secrets": secrets,
        "sessions": sessions,
    }


def main() -> int:
    config = load_config()
    app = LauncherApp(config)
    app.title = "Freigang Agent Launcher"
    app.run()

    if app.result:
        # Write JSON to file (env var set by start_container.sh)
        output_file = os.environ.get("TUI_OUTPUT_FILE", "/tmp/launcher_tui_result.json")
        with open(output_file, "w") as f:
            json.dump(app.result, f)
        return 0 if app.result.get("action") == "start" else 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
