# Antigravity Touch Bar & Menu Bar Monitor

Show your live Google Antigravity TUI/CLI (`agy`) model limits and API costs on your MacBook Touch Bar and macOS Menu Bar.

---

## Quick Start (Launch in 3 Steps)

### 1. Install the Backend
Run this in the project directory to install the Python helper library:
```bash
pip install -e .
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

## How to Manage the App

- **View Live Logs**: Keep track of connection status, parsed costs, and background updates:
  ```bash
  tail -f /tmp/agy-touchbar.log
  ```
- **Stop the App**: Choose **Quit** from the Antigravity menu icon in your macOS Menu Bar, or run:
  ```bash
  pkill -f agy-touchbar-app
  ```

---

## What It Does

- **Menu Bar Indicator**: Shows the Antigravity logo next to your current Gemini Weekly and 5-Hour remaining percentages (e.g., `85% | 23%`).
- **Expanded Touch Bar detail**: Tap the Control Strip button to open a custom Touch Bar view showing detailed remaining progress bars and reset countdowns.
- **Offline Mode**: If the local server goes offline, it keeps showing your last known active percentages (caching them locally) instead of resetting to `100%`.
- **API Cost Tracking**: Safely sums up all-time costs across your conversation databases using SQLite read-only mode so it never locks your active database.
- **CPU Friendly**: Idle background checks poll once every 60 seconds to save battery, but it updates instantly whenever you expand the Touch Bar widget.
- **Color Indicators**: Percentages change color based on usage levels:
  - **Green** (>= 50% remaining)
  - **Yellow** (30% to 50% remaining)
  - **Red** (< 30% remaining)
