import argparse
import sys
import json
from agy_touchbar.client import get_live_touchbar_data, get_mock_touchbar_data
from agy_touchbar.parser import get_today_cost

def make_ansi_bar(percent: float) -> str:
    filled = round(percent / 10.0)
    filled = max(0, min(10, filled))
    bar_chars = "█" * filled + "░" * (10 - filled)
    
    if percent > 50.0:
        color = "\033[32m"  # Green
    elif percent > 30.0:
        color = "\033[33m"  # Yellow
    else:
        color = "\033[31m"  # Red
        
    return f"{color}{bar_chars}\033[0m"

def format_plain_text(data: dict, cost: float) -> str:
    gemini_weekly = data["gemini"]["weekly"]["percent_remaining"]
    gemini_5h = data["gemini"]["five_hour"]["percent_remaining"]

    g_weekly_cd = data["gemini"]["weekly"]["countdown"]
    g_5h_cd = data["gemini"]["five_hour"]["countdown"]

    g_weekly_bar = make_ansi_bar(gemini_weekly)
    g_5h_bar = make_ansi_bar(gemini_5h)

    # Gemini formatting
    g_weekly_str = f"{gemini_weekly:.0f}%"
    if g_weekly_cd != "Available" and g_weekly_cd != "0m" and g_weekly_cd != "N/A":
        g_weekly_str += f"({g_weekly_cd})"
        
    g_5h_str = f"{gemini_5h:.0f}%"
    if g_5h_cd != "Available" and g_5h_cd != "0m" and g_5h_cd != "N/A":
        g_5h_str += f"({g_5h_cd})"

    return f"Gemini: [Wk {g_weekly_bar} {g_weekly_str} / 5h {g_5h_bar} {g_5h_str}]"

def format_btt_json(data: dict, cost: float, warning_threshold: float = 70.0, critical_threshold: float = 90.0) -> str:
    gemini_weekly = data["gemini"]["weekly"]["percent_remaining"]
    gemini_5h = data["gemini"]["five_hour"]["percent_remaining"]
    claude_weekly = data["claude"]["weekly"]["percent_remaining"]
    claude_5h = data["claude"]["five_hour"]["percent_remaining"]

    g_pct = min(gemini_weekly, gemini_5h)
    c_pct = min(claude_weekly, claude_5h)

    g_used = 100.0 - g_pct
    c_used = 100.0 - c_pct

    # Determine colors
    # Default: Green/white, Warning: Yellow, Critical: Red
    max_used = max(g_used, c_used)
    
    if max_used >= critical_threshold:
        # Red warning background
        bg_color = "150,0,0,255"
        font_color = "255,255,255,255"
    elif max_used >= warning_threshold:
        # Yellow warning background
        bg_color = "180,140,0,255"
        font_color = "255,255,255,255"
    else:
        # Dark premium background with neon-violet font accents
        bg_color = "15,15,20,255"
        font_color = "200,180,255,255"

    text = format_plain_text(data, cost)
    
    btt_payload = {
        "text": text,
        "background_color": bg_color,
        "font_color": font_color,
        "font_size": 11
    }
    return json.dumps(btt_payload)

def print_instructions():
    print("""
========================================================================
Antigravity Touch Bar Integration Instructions
========================================================================

You can display this widget on your MacBook Touch Bar using:

1. BetterTouchTool (Recommended)
   - Open BetterTouchTool Preferences.
   - Go to "Touch Bar" section.
   - Click "+ Add Trigger" -> "Touch Bar Widget" -> "Run Shell Script and Show Return Value".
   - Set Name to "Antigravity Quotas".
   - Set the Script input to:
       /usr/local/bin/agy-touchbar --btt
     (Or specify the absolute path to your environment's agy-touchbar)
   - Set the Refresh Interval to e.g., 30 seconds.
   - Check "Always run when widget becomes visible".
   - Enjoy dynamic colors matching your remaining quota and usage costs!

2. MTMR (My TouchBar My Rules)
   - Open MTMR preferences JSON (typically ~/.config/MTMR/items.json).
   - Add a shell widget block:
     {
       "type": "shellScript",
       "width": 180,
       "interval": 30,
       "source": {
         "filePath": "/usr/local/bin/agy-touchbar"
       },
       "align": "right"
     }
========================================================================
""")

def main():
    parser = argparse.ArgumentParser(description="Antigravity Touchbar Helper CLI")
    parser.add_argument("--mock", "-m", action="store_true", help="Use mock data for testing")
    parser.add_argument("--btt", action="store_true", help="Output BTT JSON format")
    parser.add_argument("--json", action="store_true", help="Output raw JSON data for TouchBarApp")
    parser.add_argument("--warning", "-w", type=float, default=70.0, help="Warning threshold used percentage (default: 70)")
    parser.add_argument("--critical", "-c", type=float, default=90.0, help="Critical threshold used percentage (default: 90)")
    parser.add_argument("--instructions", action="store_true", help="Show BetterTouchTool / MTMR setup instructions")
    
    args = parser.parse_args()

    if args.instructions:
        print_instructions()
        sys.exit(0)

    # Fetch cost
    try:
        cost = get_today_cost()
    except Exception:
        cost = 0.0

    # Fetch quota details
    is_offline = False
    if args.mock:
        data = get_mock_touchbar_data()
    else:
        live_data = get_live_touchbar_data()
        if live_data is None:
            is_offline = True
            data = None
        else:
            data = live_data

    if is_offline or data is None:
        if args.json:
            print(json.dumps({
                "gemini_weekly": 100.0, "gemini_5h": 100.0,
                "claude_weekly": 100.0, "claude_5h": 100.0,
                "gemini_weekly_reset": "N/A", "gemini_5h_reset": "N/A",
                "claude_weekly_reset": "N/A", "claude_5h_reset": "N/A",
                "cost": cost, "status": "offline"
            }))
        elif args.btt:
            fallback_payload = {
                "text": f"Offline | ${cost:.2f}",
                "background_color": "30,30,30,255",
                "font_color": "150,150,150,255"
            }
            print(json.dumps(fallback_payload))
        else:
            print("Gemini: Offline")
        sys.exit(0)

    # Resolve values
    gemini_weekly = data["gemini"]["weekly"]["percent_remaining"]
    gemini_5h = data["gemini"]["five_hour"]["percent_remaining"]
    claude_weekly = data["claude"]["weekly"]["percent_remaining"]
    claude_5h = data["claude"]["five_hour"]["percent_remaining"]

    g_weekly_cd = data["gemini"]["weekly"]["countdown"]
    g_5h_cd = data["gemini"]["five_hour"]["countdown"]
    c_weekly_cd = data["claude"]["weekly"]["countdown"]
    c_5h_cd = data["claude"]["five_hour"]["countdown"]

    if args.json:
        print(json.dumps({
            "gemini_weekly": gemini_weekly,
            "gemini_5h": gemini_5h,
            "claude_weekly": claude_weekly,
            "claude_5h": claude_5h,
            "gemini_weekly_reset": g_weekly_cd,
            "gemini_5h_reset": g_5h_cd,
            "claude_weekly_reset": c_weekly_cd,
            "claude_5h_reset": c_5h_cd,
            "cost": cost,
            "status": "online"
        }))
    elif args.btt:
        print(format_btt_json(data, cost, args.warning, args.critical))
    else:
        print(format_plain_text(data, cost))

if __name__ == "__main__":
    main()
