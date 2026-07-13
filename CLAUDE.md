# Antigravity Touch Bar AI Instructions (`CLAUDE.md`)

This file contains build commands, system configurations, and architectural guidelines for developers and AI coding assistants working on the `agy-touchbar` project.

---

## 1. System Commands & Workflows

### Build & Run
- **Compile Swift App**:
  ```bash
  swiftc -o agy-touchbar-app TouchBarApp.swift
  ```
- **Install Python Backend**:
  ```bash
  pip install -e .
  ```
- **Test Backend CLI Output**:
  ```bash
  agy-touchbar --json
  # or
  python3 -m agy_touchbar.cli --json
  ```

### Daemon Management
- **Start Daemon (Background)**:
  ```bash
  nohup ./agy-touchbar-app >/dev/null 2>&1 &
  ```
- **Start Foreground (Debug Mode)**:
  ```bash
  ./agy-touchbar-app
  ```
- **Stop Daemon**:
  ```bash
  pkill -f agy-touchbar-app
  ```
- **Tail Logs**:
  ```bash
  tail -f /tmp/agy-touchbar.log
  ```

---

## 2. Core Architectural & Code Rules

### SQLite Database Reader Safety
When reading user history or token metadata databases from `~/.gemini/antigravity-cli/conversations/*.db`:
- **Read-Only WAL Mode**: You **MUST** open database connections in read-only mode using URIs to bypass active WAL database locks held by the main client:
  ```python
  conn = sqlite3.connect("file:" + db_file + "?mode=ro", uri=True)
  ```
- Do not make changes to databases or write files to them.

### Active Process Port Discovery
- Locate the language server port by scanning for active `agy` binary processes in `ps aux` and discovering their active listening TCP ports via `lsof -nP -iTCP -sTCP:LISTEN -a -p <pid>`.
- The `agy` CLI binary's RPC endpoints **do not** require a CSRF token.

### RPC Quota & Bucket Mapping
- Query the Connect RPC method `/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` to resolve live weekly/5-hour quota data.
- Fallback to `/exa.language_server_pb.LanguageServerService/GetUserStatus` only if the primary summary method is unavailable.

### Percentage Color Thresholds
Always format quota percentages on both the Touch Bar labels and Menu Bar text according to the following color brackets:
- **`>= 50%`**: Green (`red: 0.2, green: 0.8, blue: 0.2`)
- **`30% - 50%`**: Yellow/Orange (`red: 0.9, green: 0.8, blue: 0.1`)
- **`< 30%`**: Red (`red: 0.9, green: 0.2, blue: 0.2`)
