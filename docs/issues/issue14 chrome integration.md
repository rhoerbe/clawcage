## Problem Statement

Users shall have the options to use either Playwright MCP or Claude's new --chrome option (available from 2.0.28 onwards) to allow teh agent to access web pages.

The current AI agent (Claude Code) requires access to a full graphical instance of Chrome to interact with web elements. 
Headless mode is not supported.
To maintain security and environment consistency, we need to run this inside an isolated container. 
Still, Chrome needs to be run in sandbox mode (no `--no-sandbox`).
At the same time the container must be executed with minimal privileges in rootless mode (no `--cap-add=SYS_ADMIN`).
Note: Standard X11 forwarding from the host is not an option because it blows away the isolation efforts.

## Requirements

* Engine: Must run using Podman utilizing rootless mode.
* Display: Must provide a virtual display buffer (X-server) inside the container.
* Chrome Integration: Needs specific preparations to run in a containerized environment (e.g., `--no-sandbox`, `--shm-size`).
* Network: Isolated network stack with optional proxy support (implementation out of scope for this issue)
* Make the capability available to the agent by starting this service only when the environment var ENABLE_VIRT_X11=true is set

---

## Proposed Isolation Options
AI agent may visit untrusted or adversarial websites. As it is currently not feasible to defend completely against prompt injection attacks, the agent must be sandboxed with a quite high security level.

### Option A: Pure Xvfb (headless from the user perspective)
Run a virtual framebuffer in memory only.
* Pros: Lowest overhead, maximum performance.
* Cons: Zero visibility. If the agent hangs on a CAPTCHA or unexpected modal, debugging is next to impossible.

### Option B: Xvfb + VNC/noVNC (Preferred)

Run Xvfb with a VNC server (e.g., `x11VNC`) layered on top.
* Why this is preferred: * Observability: Provides the ability to "attach" a viewer to the container in real-time to monitor agent behavior.
* Low Overhead: When no VNC client is connected, the performance cost is negligible compared to pure Xvfb.
* Reliability: Easier to troubleshoot "agent-loops" or rendering issues that only appear in GUI-mode.

### Option C: Headless Wayland (Sway/Weston)
The modern alternative to X11, offering better security and native isolation between windows.
* Pros: Native window isolation (more secure than X11); future-proof.
* Cons: Higher complexity; x11vnc is incompatiblerequires Wayland-specific tools like wayvnc for observability

### Option D: Hardware-Isolated MicroVMs (Kata & libkrun)
Using a MicroVM runtime ensures the agent runs in its own dedicated virtual kernel. Podman supports this with the `--runtime` option.
1. libkrun (Performance Focused)
libkrun is a dynamic library that allows programs to run in a tiny VM as if they were a process. It is generally the easiest "MicroVM" to run rootless.
* Pros: Extremely fast boot; minimal resource footprint.
* Cons: Less mature than Kata; requires host support for KVM.

2. Kata Containers (Production Standard)
Kata Containers provides a more robust, "VM-as-a-Pod" experience. It is the enterprise standard for hardware isolation.
* Pros: Strongest security boundary; supports different hypervisors (QEMU, Firecracker).
* Cons: Slightly slower boot than libkrun; requires more complex host configuration.
---

## Proposed Implementation
- add Xvfb
- add Chrome
- add x11vnc
- install the Claude in Chrome extension
- start Chrome and x11vnc
- add the Jessie Frazelle Seccomp profile (chrome.json)


### Dockerfile based on node:22-bookworm

1. Install Chrome dependencies and X11 tools
	RUN apt-get update && apt-get install -y \
		wget \
		gnupg \
		ca-certificates \
		xvfb \
		x11vnc \
		dbus-x11 \
		libnss3 \
		libatk-bridge2.0-0 \
		libcups2 \
		libdrm2 \
		libxcomposite1 \
		libxdamage1 \
		libxrandr2 \
		libgbm1 \
		libasound2 \
		--no-install-recommends

2. Install Google Chrome Stable
	RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/google-chrome.gpg && \
		echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list && \
		apt-get update && apt-get install -y google-chrome-stable

4. Pre-configure the Extension (External Extensions Policy)
``` Dockerfile
# Replace [EXTENSION_ID] with the actual ID of the Claude Extension.
# The official Extension ID for Claude in Chrome (Beta) as of 2026 is:
#     fcoeoabgfenejglbffodgkkbkcdhcgfn
RUN mkdir -p /opt/google/chrome/extensions && \
	echo '{ \
	  "external_update_url": "https://clients2.google.com/service/update2/crx" \
	}' > /opt/google/chrome/extensions/[EXTENSION_ID].json
```


### Container Startup

The container should be initialized with an increased shared memory limit to prevent Chrome crashes.
Add following options to `podman run`:
  --shm-size=2g
  -p 5900:5900

entrypoint.sh:
``` bash
ENABLE_VIRT_X11=${ENABLE_VIRT_X11:-false}
if [ "$ENABLE_VIRT_X11" = "true" ]; then
    echo "Starting Graphical Stack (Xvfb, x11vnc)"
    Xvfb :99 -screen 0 1280x1024x24 &
    export DISPLAY=:99
    x11vnc -display :99 -forever -quiet &
else
    # Unset DISPLAY to ensure tools don't try to hunt for a screen
    unset DISPLAY
fi
exec "$@"
```


Note re `--forever`: Since the AI agent is running inside a Podman container, we want the VNC server to behave more like a system service and less like a standard interactive remote desktop.


### Chrome Seccomp Profile
Chromes sandbox fails in containers because Podman's default security profile blocks the unshare system call, which Chrome uses to create its own isolated namespaces.
A widely used profile for this purpose was created by Jessie Frazelle, whitelisting the syscalls required for the Chrome sandbox. Based on it, 
`github.com/moby/profiles/blob/seccomp/v0.1.0/seccomp/default.json` is a more recent version.

### Integration Test

This script runs inside the container to verify the stack

``` bash

#!/bin/bash
# 1. Check if the DISPLAY is active
if ! xset -q &>/dev/null; then
    echo "TEST FAILED: X-server (Xvfb) is not running."
    exit 1
fi

# 2. Open Chrome to a specific page using the Chrome DevTools Protocol (CDP)
google-chrome --remote-debugging-port=9222 "https://google.com" &
CHROME_PID=$!
sleep 5 # Give it time to render

# 3. Capture the virtual screen to a file
import -display :99 -window root /tmp/test_screenshot.png

# 4. Basic Validation: Is the file size > 0? 
if [ -s /tmp/test_screenshot.png ]; then
    echo "TEST PASSED: Browser rendered to virtual display."
    kill $CHROME_PID
    exit 0
else
    echo "TEST FAILED: Screenshot is empty."
    exit 1
fi
```

To force the test failing, start podman with `--network none`


## Next Steps
1. Update the Dockerfile to include `chromium`, `xvfb`, and `x11vnc`.
2. Verify the agent's ability to hook into the Chrome instance via `--remote-debugging-port`.
---
