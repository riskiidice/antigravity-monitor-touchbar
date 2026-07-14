# Antigravity Touch Bar & Menu Bar Monitor

[![Platform](https://img.shields.io/badge/platform-macOS%2010.12.2%2B-blue.svg)](https://apple.com)
[![Python Version](https://img.shields.io/badge/python-3.11%2B-green.svg)](https://python.org)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

Track your live Google Antigravity TUI/CLI (`agy`) model quotas and cumulative token spend directly from your MacBook Touch Bar and macOS Menu Bar.

---

## Quick Start (3 Steps)

### 1. Install the Backend
Run this in the project directory to install the Python helper (using `--break-system-packages` to bypass PEP 668 restrictions on macOS):
```bash
python3 -m pip install -e . --break-system-packages
```

### 2. Build the App
Compile the Swift app into a native macOS executable:
```bash
swiftc -o agy-touchbar-app TouchBarApp.swift
```

### 3. Launch the App
Run the app in the background:
```bash
nohup ./agy-touchbar-app >/dev/null 2>&1 &
```

---

## Online vs. Offline Behavior

Here is how the widgets update depending on whether your terminal `agy` session is active:

| Metric | Online State | Offline State (Idle / Terminal Closed) |
| :--- | :--- | :--- |
| **Gemini Weekly %** | Live remaining percentage | Persists last known online value |
| **Gemini 5-Hour %** | Live remaining percentage | Persists last known online value |
| **Model Reset Times** | Dynamic countdowns (e.g., `4h 5m`) | Swaps to `(Offline)` indicator |
| **Daily Cost ($)** | Cumulative all-time database cost | Cumulative database cost |
| **Menu Bar Icon** | Standard Antigravity logo | Standard Antigravity logo |

---

## Managing the App

- **Check Background Logs**: Read status reports, query timers, and parsed databases:
  ```bash
  tail -f /tmp/agy-touchbar.log
  ```
- **Stop the Daemon**: Select **Quit** from the Menu Bar icon, or kill the process:
  ```bash
  pkill -f agy-touchbar-app
  ```

---

## Troubleshooting

### The Menu Bar icon shows up, but the percentages say 100%
- **Why it happens**: The local server is not running or the connection scanner couldn't find the active `agy` process.
- **Fix**: Launch your `agy` CLI in a terminal window. The widget will detect the process and update within 60 seconds (or instantly if you tap the Touch Bar).

### The Touch Bar widget isn't showing up at all
- **Why it happens**: macOS sometimes resets the Control Strip configuration.
- **Fix**: Open **System Settings -> Keyboard -> Touch Bar Settings** and ensure **App Controls** or **Show Control Strip** is enabled. You can also force a refresh by restarting the app.

### Cost calculation does not match `/usage` in the CLI
- **Why it happens**: A write lock on the active database might have skipped the current conversation.
- **Fix**: The app automatically uses read-only URI connections to prevent WAL database locks, but you can force an instant refresh by tapping the Touch Bar button.

---

## Uninstalling the App

If you ever need to clean up and remove the application, run these commands:

1. **Stop the daemon**:
   ```bash
   pkill -f agy-touchbar-app
   ```
2. **Uninstall the Python package**:
   ```bash
   python3 -m pip uninstall agy-touchbar -y --break-system-packages
   ```
3. **Delete the compiled executable and temporary log file**:
   ```bash
   rm -f ./agy-touchbar-app /tmp/agy-touchbar.log
   ```
