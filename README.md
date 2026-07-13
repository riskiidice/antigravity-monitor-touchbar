# agy-touchbar

A lightweight, developer-friendly Touch Bar integration helper for Google Antigravity TUI/CLI (`agy`). It monitors model quotas and tracks estimated API call costs, showing key summaries right on your MacBook Touch Bar.

## Features

- **Concise Quotas & Limits**: Shows lowest remaining Gemini and Claude/GPT percentages with reset countdowns (e.g. `G:56%(48m) | C:100%`).
- **Cost Tracking**: Reads local SQLite metadata databases under `~/.gemini/antigravity-cli/conversations/` to compute daily usage costs in real-time.
- **BetterTouchTool Integration**: Supports native BTT JSON wrapper output (`--btt`) to dynamically change the touchbar widget background and text colors based on threshold values.
- **MTMR Support**: Outputs standard plain-text format compatible with MTMR JSON script widgets.
- **Offline / Serverless fallback**: Safely displays offline status with cached local cost calculations when the local LSP process isn't running.

## Installation

1. Clone or navigate to the repository directory:
   ```bash
   cd /Users/ampamp/Programs/DV_Space/agy-touchbar
   ```

2. Install the package in editable mode:
   ```bash
   pip install -e .
   ```

3. Verify installation:
   ```bash
   agy-touchbar --help
   ```

## Touch Bar Setup Instructions

To print setup instructions directly to your shell, run:
```bash
agy-touchbar --instructions
```

### 1. BetterTouchTool Configuration
1. Open BetterTouchTool Settings.
2. Select **Touch Bar** in the sidebar.
3. Click **+ Add Trigger** -> **Touch Bar Widget** -> **Run Shell Script and Show Return Value**.
4. In the Widget Config:
   - **Name**: `Antigravity Quota`
   - **Shell Script**:
     ```bash
     # Find which python/pip environment you installed agy-touchbar into
     /usr/local/bin/agy-touchbar --btt
     ```
   - **Execute every**: `30` seconds.
   - **Font Size**: `11`
   - Check **Always run when widget becomes visible**.

### 2. MTMR Configuration
Add the following widget entry to your `~/.config/MTMR/items.json`:
```json
{
  "type": "shellScript",
  "width": 180,
  "interval": 30,
  "source": {
    "filePath": "/usr/local/bin/agy-touchbar"
  },
  "align": "right"
}
```
