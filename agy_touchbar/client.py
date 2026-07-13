import os
import sys
import re
import subprocess
import urllib.request
import ssl
import json
from datetime import datetime, timezone
from typing import TypedDict, Optional

class QuotaLimit(TypedDict):
    percent_remaining: float
    countdown: str
    is_exhausted: bool

class GroupedQuota(TypedDict):
    weekly: QuotaLimit
    five_hour: QuotaLimit

class TouchbarData(TypedDict):
    gemini: GroupedQuota
    claude: GroupedQuota
    email: str
    source: str

def find_lsp_process() -> Optional[dict[str, str | int]]:
    """Scan running processes to locate the Antigravity Language Server/CLI and extract PID and optional CSRF token."""
    try:
        res = subprocess.run(["ps", "aux"], capture_output=True, text=True, check=True)
        for line in res.stdout.splitlines():
            lower = line.lower()
            is_match = False
            if "antigravity" in lower and ("language-server" in lower or "lsp" in lower or "server" in lower):
                is_match = True
            else:
                # Also match the "agy" CLI binary directly
                parts = line.strip().split()
                if len(parts) >= 11:
                    cmd = parts[10]
                    if os.path.basename(cmd) == "agy":
                        is_match = True
            
            if is_match:
                parts = line.strip().split()
                if len(parts) < 11:
                    continue
                pid = int(parts[1])
                cmdline = " ".join(parts[10:])
                
                # Extract --csrf_token
                csrf_token = ""
                eq_match = re.search(r'--csrf_token=(\S+)', cmdline)
                if eq_match:
                    csrf_token = eq_match.group(1)
                else:
                    idx = cmdline.find('--csrf_token')
                    if idx != -1:
                        after = cmdline[idx + len('--csrf_token'):].strip()
                        csrf_token = after.split()[0] if after else ""
                
                if pid:
                    return {"pid": pid, "csrf_token": csrf_token}
    except Exception:
        pass
    return None

def discover_ports(pid: int) -> list[int]:
    """Find listening TCP ports for the given PID using lsof."""
    try:
        res = subprocess.run(
            ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", str(pid)],
            capture_output=True,
            text=True,
            check=True
        )
        ports = []
        for line in res.stdout.splitlines():
            match = re.search(r':(\d+)\s+\(LISTEN\)', line)
            if match:
                port = int(match.group(1))
                if port not in ports:
                    ports.append(port)
        return ports
    except Exception:
        return []

def make_lsp_request(
    port: int, 
    endpoint: str, 
    body: dict, 
    csrf_token: str, 
    protocol: str = "http", 
    timeout: float = 1.5
) -> Optional[dict]:
    """Make HTTP POST request to the local Connect API."""
    url = f"{protocol}://127.0.0.1:{port}{endpoint}"
    data = json.dumps(body).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Connect-Protocol-Version": "1",
    }
    if csrf_token:
        headers["X-Codeium-Csrf-Token"] = csrf_token
        
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as res:
            return json.loads(res.read().decode("utf-8"))
    except Exception:
        return None

def probe_and_connect(ports: list[int], csrf_token: str) -> Optional[dict]:
    """Probe ports to find the active Connect API endpoint."""
    for port in ports:
        for proto in ["https", "http"]:
            res = make_lsp_request(
                port, 
                "/exa.language_server_pb.LanguageServerService/GetUnleashData", 
                {"wrapper_data": {}}, 
                csrf_token, 
                proto,
                timeout=0.8
            )
            if res is not None:
                return {"port": port, "protocol": proto, "csrf_token": csrf_token}
    return None

def detect_lsp_connection() -> Optional[dict]:
    """Detect and return connection info for a running Language Server."""
    proc = find_lsp_process()
    if not proc:
        return None
    
    ports = discover_ports(int(proc["pid"]))
    if not ports:
        return None
        
    conn = probe_and_connect(ports, str(proc["csrf_token"]))
    if conn:
        conn["pid"] = proc["pid"]
        return conn
    return None

def parse_iso_time(time_str: str) -> Optional[datetime]:
    if not time_str:
        return None
    try:
        t_str = time_str.replace("Z", "+00:00")
        return datetime.fromisoformat(t_str)
    except Exception:
        try:
            return datetime.strptime(time_str[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
        except Exception:
            return None

def format_countdown(reset_dt: Optional[datetime]) -> str:
    if not reset_dt:
        return "N/A"
    now = datetime.now(timezone.utc)
    diff = reset_dt - now
    total_seconds = int(diff.total_seconds())
    if total_seconds <= 0:
        return "0m"
    
    total_minutes = total_seconds // 60
    hours, minutes = divmod(total_minutes, 60)
    
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"

def get_live_touchbar_data() -> Optional[TouchbarData]:
    """Connect to the Antigravity server and fetch touchbar-relevant quota data."""
    conn = detect_lsp_connection()
    if not conn:
        return None
        
    # 1. Fetch user email via GetUserStatus
    email = "unknown@example.com"
    status_raw = make_lsp_request(
        int(conn["port"]), 
        "/exa.language_server_pb.LanguageServerService/GetUserStatus", 
        {
            "metadata": {
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "locale": "en",
            }
        }, 
        str(conn["csrf_token"]), 
        str(conn["protocol"])
    )
    if status_raw:
        email = status_raw.get("userStatus", status_raw).get("email", email)

    # 2. Fetch live quotas via RetrieveUserQuotaSummary
    quota_raw = make_lsp_request(
        int(conn["port"]), 
        "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary", 
        {}, 
        str(conn["csrf_token"]), 
        str(conn["protocol"])
    )
    
    # Initialize groups
    gemini_weekly: QuotaLimit = {"percent_remaining": 100.0, "countdown": "Available", "is_exhausted": False}
    gemini_five_hour: QuotaLimit = {"percent_remaining": 100.0, "countdown": "Available", "is_exhausted": False}
    claude_weekly: QuotaLimit = {"percent_remaining": 100.0, "countdown": "Available", "is_exhausted": False}
    claude_five_hour: QuotaLimit = {"percent_remaining": 100.0, "countdown": "Available", "is_exhausted": False}
    
    now = datetime.now(timezone.utc)
    
    if quota_raw and "response" in quota_raw:
        groups = quota_raw["response"].get("groups", [])
        for g in groups:
            g_name = g.get("displayName", "").lower()
            buckets = g.get("buckets", [])
            
            is_gemini_group = "gemini" in g_name
            
            for b in buckets:
                b_id = b.get("bucketId", "").lower()
                b_window = b.get("window", "").lower()
                remaining_fraction = b.get("remainingFraction", 1.0)
                reset_time = b.get("resetTime")
                
                percent_remaining = remaining_fraction * 100.0
                reset_dt = parse_iso_time(reset_time) if reset_time else None
                
                countdown = "Available"
                if reset_dt and percent_remaining < 100.0:
                    countdown = format_countdown(reset_dt)
                    
                is_exhausted = (percent_remaining <= 0)
                
                target: QuotaLimit = {
                    "percent_remaining": percent_remaining,
                    "countdown": countdown,
                    "is_exhausted": is_exhausted
                }
                
                is_weekly = ("weekly" in b_id or "weekly" in b_window)
                
                if is_gemini_group:
                    if is_weekly:
                        gemini_weekly = target
                    else:
                        gemini_five_hour = target
                else:
                    if is_weekly:
                        claude_weekly = target
                    else:
                        claude_five_hour = target
                        
    elif status_raw:
        # Fallback to parsing GetUserStatus models if RetrieveUserQuotaSummary is unavailable
        user_status = status_raw.get("userStatus", status_raw)
        models_raw = user_status.get("cascadeModelConfigData", {}).get("clientModelConfigs", [])
        
        for m in models_raw:
            label = m.get("label", "").lower() or m.get("displayName", "").lower()
            quota_info = m.get("quotaInfo", {})
            remaining_fraction = quota_info.get("remainingFraction", 1.0)
            reset_time = quota_info.get("resetTime")
            is_exhausted = m.get("isExhausted", remaining_fraction == 0)
            
            percent_remaining = remaining_fraction * 100.0
            reset_dt = parse_iso_time(reset_time) if reset_time else None
            
            is_weekly = False
            if any(x in label for x in ["pro", "opus", "sonnet"]):
                is_weekly = True
            elif reset_dt:
                diff = reset_dt - now
                if diff.total_seconds() > 86400:
                    is_weekly = True
                    
            countdown = "Available"
            if reset_dt and percent_remaining < 100.0:
                countdown = format_countdown(reset_dt)
                
            target_limit: QuotaLimit = {
                "percent_remaining": percent_remaining,
                "countdown": countdown,
                "is_exhausted": is_exhausted
            }
            
            if "gemini" in label:
                if is_weekly:
                    if percent_remaining < gemini_weekly["percent_remaining"]:
                        gemini_weekly = target_limit
                else:
                    if percent_remaining < gemini_five_hour["percent_remaining"]:
                        gemini_five_hour = target_limit
            else:
                if is_weekly:
                    if percent_remaining < claude_weekly["percent_remaining"]:
                        claude_weekly = target_limit
                else:
                    if percent_remaining < claude_five_hour["percent_remaining"]:
                        claude_five_hour = target_limit
    else:
        return None
        
    return {
        "gemini": {"weekly": gemini_weekly, "five_hour": gemini_five_hour},
        "claude": {"weekly": claude_weekly, "five_hour": claude_five_hour},
        "email": email,
        "source": "live"
    }

def get_mock_touchbar_data() -> TouchbarData:
    """Provide realistic mock data for testing."""
    return {
        "gemini": {
            "weekly": {"percent_remaining": 56.69, "countdown": "134h 50m", "is_exhausted": False},
            "five_hour": {"percent_remaining": 1.08, "countdown": "48m", "is_exhausted": False}
        },
        "claude": {
            "weekly": {"percent_remaining": 100.0, "countdown": "Available", "is_exhausted": False},
            "five_hour": {"percent_remaining": 100.0, "countdown": "Available", "is_exhausted": False}
        },
        "email": "thesecondstageshow@gmail.com",
        "source": "mock"
    }
