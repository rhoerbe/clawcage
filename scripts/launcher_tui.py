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


# Fallback MCP servers if manifest not found
DEFAULT_MCP_MANIFEST = {
    "installed": [
        {"name": "playwright", "package": "@playwright/mcp", "description": "Browser automation"}
    ],
    "external": []
}

# All MCP servers off by default on first start (filesystem access is always on via Claude Code itself)
DEFAULT_MCP_ENABLED: list[str] = []


class SecretCheckbox(Checkbox):
    """Checkbox for secret selection with availability indicator."""

    def __init__(self, name: str, present: bool, enabled: bool) -> None:
        # Show availability status in the label
        status = "[green]✓[/]" if present else "[red]✗[/]"
        label = f"{status} {name}"
        # Only enable checkbox if secret file exists
        super().__init__(label, value=enabled and present, disabled=not present, id=f"secret-{name}", classes="mcp-checkbox")


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

    .secrets-grid Static {
        margin-right: 2;
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

            # Permission Mode + Session on same line
            with Vertical(classes="section"):
                with Horizontal(classes="inline-row"):
                    yield Label("Permission:", classes="inline-label")
                    yield Select(
                        [(mode, mode) for mode in self.config["permission_modes"]],
                        value=self.config["default_permission_mode"],
                        id="permission-mode",
                        classes="inline-select",
                    )
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

            # MCP Servers (all in one section)
            with Vertical(classes="section"):
                yield Label("MCP Servers:")
                with Horizontal(classes="mcp-grid"):
                    # Installed servers (in container)
                    for server in self.config["mcp_installed"]:
                        name = server["name"]
                        enabled = name in self.config["default_mcp_servers"]
                        yield Checkbox(
                            server["description"],
                            value=enabled,
                            id=f"mcp-{name}",
                            classes="mcp-checkbox",
                        )
                    # External servers (require auth)
                    for server in self.config["mcp_external"]:
                        name = server["name"]
                        auth = server.get("auth", "")
                        desc = server["description"]
                        if auth == "oauth":
                            desc = f"{desc} [dim](oauth)[/]"
                        enabled = name in self.config.get("default_mcp_external", [])
                        yield Checkbox(
                            desc,
                            value=enabled,
                            id=f"mcp-ext-{name}",
                            classes="mcp-checkbox",
                        )

            # Secrets (selectable - only available secrets can be enabled)
            with Vertical(classes="section"):
                yield Label("Secrets (pass to container):")
                with Horizontal(classes="mcp-grid"):
                    for secret in self.config["secrets"]:
                        name = secret["name"]
                        present = secret["present"]
                        enabled = name in self.config.get("default_secrets", [])
                        yield SecretCheckbox(name, present, enabled)
                    if not self.config["secrets"]:
                        yield Static("[dim]No secrets configured[/]")

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

        # Collect MCP servers (installed)
        mcp_servers = []
        for server in self.config["mcp_installed"]:
            checkbox = self.query_one(f"#mcp-{server['name']}", Checkbox)
            if checkbox.value:
                mcp_servers.append(server["name"])

        # Collect MCP servers (external)
        mcp_external = []
        for server in self.config["mcp_external"]:
            try:
                checkbox = self.query_one(f"#mcp-ext-{server['name']}", Checkbox)
                if checkbox.value:
                    mcp_external.append(server["name"])
            except Exception:
                pass

        # Collect secrets
        secrets = []
        for secret in self.config["secrets"]:
            try:
                checkbox = self.query_one(f"#secret-{secret['name']}", Checkbox)
                if checkbox.value:
                    secrets.append(secret["name"])
            except Exception:
                pass

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
            "mcp_external": mcp_external,
            "secrets": secrets,
            "session_arg": session_arg,
        }
        self.exit()


def load_user_preferences(prefs_path: Path) -> dict:
    """Load user preferences from file. Returns empty dict if file doesn't exist."""
    if prefs_path.exists():
        try:
            with open(prefs_path) as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    return {}


def save_user_preferences(prefs_path: Path, prefs: dict) -> None:
    """Save user preferences to file."""
    prefs_path.parent.mkdir(parents=True, exist_ok=True)
    with open(prefs_path, "w") as f:
        json.dump(prefs, f, indent=2)


def load_config() -> dict:
    """Load configuration from environment, filesystem, and user preferences."""
    agent_home = os.environ.get("AGENT_HOME", "/home/ha_agent")
    repo_name = os.environ.get("REPO_NAME", "hadmin")
    container_image = os.environ.get("CONTAINER_IMAGE", "claude-ha-agent")

    # User preferences path
    prefs_path = Path(os.environ.get("LAUNCHER_PREFS_PATH", f"{agent_home}/workspace/{repo_name}/.claude/launcher_preferences.json"))
    user_prefs = load_user_preferences(prefs_path)

    # Permission modes
    permission_modes_str = os.environ.get(
        "PERMISSION_MODES", "default,acceptEdits,bypassPermissions,plan,dontAsk"
    )
    permission_modes = [m.strip() for m in permission_modes_str.split(",") if m.strip()]
    # Use saved preference or fall back to config default
    default_permission_mode = user_prefs.get("permission_mode", os.environ.get("DEFAULT_PERMISSION_MODE", "bypassPermissions"))

    # Load MCP manifest
    manifest_path = os.environ.get("MCP_MANIFEST_PATH", "")
    mcp_manifest = DEFAULT_MCP_MANIFEST.copy()

    if manifest_path and Path(manifest_path).exists():
        try:
            with open(manifest_path) as f:
                mcp_manifest = json.load(f)
        except (json.JSONDecodeError, IOError):
            pass

    mcp_installed = mcp_manifest.get("installed", [])
    mcp_external = mcp_manifest.get("external", [])

    # Use saved MCP selections or fall back to config defaults (empty = all off on first start)
    if "mcp_servers" in user_prefs:
        default_mcp_servers = user_prefs["mcp_servers"]
    else:
        default_mcp_str = os.environ.get("DEFAULT_MCP_SERVERS", "")
        default_mcp_servers = [m.strip() for m in default_mcp_str.split(",") if m.strip()] if default_mcp_str else DEFAULT_MCP_ENABLED

    # External MCP servers from preferences
    default_mcp_external = user_prefs.get("mcp_external", [])

    # Selectable secrets (shown in TUI for user selection)
    secrets_dir = Path(agent_home) / "workspace" / ".secrets"
    selectable_secrets_str = os.environ.get("SELECTABLE_SECRETS", "github_token:GitHub token|mqtt_username:MQTT user|mqtt_password:MQTT pass")

    secrets = []
    for entry in selectable_secrets_str.split("|"):
        entry = entry.strip()
        if entry:
            parts = entry.split(":", 1)
            name = parts[0]
            present = (secrets_dir / name).exists()
            secrets.append({"name": name, "present": present})

    # Default secrets from preferences (only github_token enabled by default on first start)
    default_secrets = user_prefs.get("secrets", ["github_token"])

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
        "mcp_installed": mcp_installed,
        "mcp_external": mcp_external,
        "default_mcp_servers": default_mcp_servers,
        "default_mcp_external": default_mcp_external,
        "secrets": secrets,
        "default_secrets": default_secrets,
        "sessions": sessions,
        "prefs_path": prefs_path,
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

        # Save user preferences for next invocation (only on successful start)
        if app.result.get("action") == "start":
            prefs = {
                "permission_mode": app.result.get("permission_mode"),
                "mcp_servers": app.result.get("mcp_servers", []),
                "mcp_external": app.result.get("mcp_external", []),
                "secrets": app.result.get("secrets", []),
            }
            save_user_preferences(config["prefs_path"], prefs)

        return 0 if app.result.get("action") == "start" else 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
