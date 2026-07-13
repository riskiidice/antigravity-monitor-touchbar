# Antigravity Touch Bar & Menu Bar Monitor (`agy-touchbar`)

A premium, lightweight utility that displays your live Google Antigravity TUI/CLI (`agy`) model quotas and cumulative token costs directly on your MacBook Touch Bar and macOS Menu Bar.

---

## Features

- **macOS Menu Bar Quota Indicator**: Displays the Antigravity logo next to your current remaining quota percentages (e.g., `Weekly% | 5-Hour%`).
- **Expanded Touch Bar Modal**: Displays detailed progress bars and reset countdowns for Gemini and third-party models when the Touch Bar Control Strip item is tapped.
- **Persistent Offline Cache**: Persists and displays your last known online quota percentages when the language server goes offline, avoiding flashing `100%`.
- **All-Time Cost Tracker**: Dynamically reads all local SQLite conversation databases using read-only WAL mode to safely display your cumulative spend (matching the `/usage` command) without locking active databases.
- **Resource Optimized**: Runs as a lightweight native accessory app with a **60-second** background update timer, while instantly updating quotas on-tap.

---

## Directory Structure

```
agy-touchbar/
├── README.md             # This instruction manual
├── TouchBarApp.swift     # Native macOS App (Swift UI, Menu Bar, and Touch Bar controller)
├── agy-touchbar-app      # Compiled native application executable
├── agy_touchbar/         # Python helper library
│   ├── cli.py            # CLI entry point
│   ├── client.py         # Connect RPC client (queries RetrieveUserQuotaSummary)
│   └── parser.py         # SQLite WAL cost parser (calculates all-time costs)
├── setup.py              # Python package configuration
└── pyproject.toml        # Build specifications
```

---

## Installation & Setup

### 1. Build and Install the Python Backend
The Python helper queries the local RPC endpoints and parses conversation databases.

```bash
# Install the package in editable mode
pip install -e .

# Verify the CLI command works and prints the live status
agy-touchbar --json
```

### 2. Compile the Swift Frontend
Compile the Swift controller into a native macOS command-line application:

```bash
swiftc -o agy-touchbar-app TouchBarApp.swift
```

---

## How to Launch and Manage the App

### Launch in Background (Recommended)
Launch the application as a detached background daemon:
```bash
nohup ./agy-touchbar-app >/dev/null 2>&1 &
```

### Launch in Foreground (For Debugging & Logs)
Run the application interactively in your terminal:
```bash
./agy-touchbar-app
```

### Check Status Logs
Tail the live application logs to view background queries, connection status, and Touch Bar updates:
```bash
tail -f /tmp/agy-touchbar.log
```

### Quit / Stop the Application
To stop the daemon, select **Quit** from the Antigravity menu icon in the macOS Menu Bar, or run:
```bash
pkill -f agy-touchbar-app
```

---

## Technical Details

- **Port Discovery**: Automatically scans running processes for `agy` or `antigravity-language-server`, mapping listening ports dynamically to route Connect RPC requests.
- **Zero Lockups**: SQLite readers use `file:path.db?mode=ro` URI connections to bypass active WAL write locks.
- **Togglable Modal**: The Touch Bar modal features a close (`✕`) button and re-registers the Control Strip button presence on dismissal via the private `DFRFoundation` framework category extensions.
