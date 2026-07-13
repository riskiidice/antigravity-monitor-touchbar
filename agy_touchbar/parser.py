import os
import sqlite3
import glob
import json
from collections import defaultdict
from datetime import datetime, date

def parse_varint(data: bytes, index: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while index < len(data):
        byte = data[index]
        index += 1
        value |= (byte & 0x7f) << shift
        if not (byte & 0x80):
            break
        shift += 7
    return value, index

def parse_proto(data: bytes) -> dict[int, int | bytes]:
    fields: dict[int, int | bytes] = {}
    index = 0
    limit = len(data)
    while index < limit:
        try:
            tag, index = parse_varint(data, index)
            field_num = tag >> 3
            wire_type = tag & 0x07
            
            if wire_type == 0:  # Varint
                val, index = parse_varint(data, index)
                fields[field_num] = val
            elif wire_type == 1:  # 64-bit
                index += 8
            elif wire_type == 2:  # Length-delimited
                length, index = parse_varint(data, index)
                subdata = data[index:index+length]
                index += length
                fields[field_num] = subdata
            elif wire_type == 5:  # 32-bit
                index += 4
            else:
                break
        except Exception:
            break
    return fields

def extract_generation_stats(data: bytes) -> dict[str, str | int | None] | None:
    top = parse_proto(data)
    model_name = "Unknown Model"
    timestamp = None
    
    # Inside Field 1 (Length-delimited)
    if 1 in top:
        val = top[1]
        assert isinstance(val, bytes)
        inner = parse_proto(val)
        if 21 in inner:
            try:
                model_name = inner[21].decode('utf-8')
            except Exception:
                pass
        
        # Extract timestamp from Field 9 -> Field 4 -> Field 1
        if 9 in inner:
            f9_val = inner[9]
            assert isinstance(f9_val, bytes)
            field9 = parse_proto(f9_val)
            if 4 in field9:
                f4_val = field9[4]
                assert isinstance(f4_val, bytes)
                field4 = parse_proto(f4_val)
                if 1 in field4:
                    timestamp = field4[1]  # UNIX seconds
        
        # Inside Field 4 (Length-delimited)
        if 4 in inner:
            f4_inner_val = inner[4]
            assert isinstance(f4_inner_val, bytes)
            stats = parse_proto(f4_inner_val)
            # Field 1: Model ID, Field 2: New Input Tokens, Field 3: Output Tokens, Field 5: Cached Tokens
            new_input = stats.get(2, 0)
            output = stats.get(3, 0)
            cached = stats.get(5, 0)
            
            assert isinstance(new_input, int)
            assert isinstance(output, int)
            assert isinstance(cached, int)
            
            return {
                "model": model_name,
                "prompt_tokens": new_input,
                "cached_tokens": cached,
                "output_tokens": output,
                "total_tokens": new_input + cached + output,
                "timestamp": timestamp
            }
    return None

def get_pricing_tier(model_name: str) -> str:
    name_lower = model_name.lower()
    if any(k in name_lower for k in ["pro", "ultra", "claude"]):
        return "pro"
    return "flash"

def calculate_cost(model_name: str, prompt: int, cached: int, output: int) -> float:
    tier = get_pricing_tier(model_name)
    total_input = prompt + cached
    is_over_128k = total_input > 128_000
    
    if tier == "pro":
        # Pro Pricing (e.g. Gemini 1.5 Pro)
        input_rate = 2.50 / 1e6 if is_over_128k else 1.25 / 1e6
        cached_rate = 0.625 / 1e6 if is_over_128k else 0.3125 / 1e6
        output_rate = 7.50 / 1e6 if is_over_128k else 3.75 / 1e6
    else:
        # Flash Pricing (e.g. Gemini 1.5/3.5 Flash)
        input_rate = 0.15 / 1e6 if is_over_128k else 0.075 / 1e6
        cached_rate = 0.0375 / 1e6 if is_over_128k else 0.01875 / 1e6
        output_rate = 0.60 / 1e6 if is_over_128k else 0.30 / 1e6
        
    cost = (prompt * input_rate) + (cached * cached_rate) + (output * output_rate)
    return cost

def get_today_cost(cli_dir: str = None) -> float:
    """Calculate the total cost of all API calls executed across all history (all time)."""
    if cli_dir is None:
        cli_dir = os.path.expanduser("~/.gemini/antigravity-cli")
        
    db_pattern = os.path.join(cli_dir, "conversations", "*.db")
    db_files = glob.glob(db_pattern)
    
    total_cost = 0.0
    for db_file in db_files:
        try:
            # Open in read-only mode with URI to bypass active WAL database locks
            conn = sqlite3.connect("file:" + db_file + "?mode=ro", uri=True)
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='gen_metadata'")
            if cursor.fetchone():
                cursor.execute("SELECT data FROM gen_metadata")
                for (data,) in cursor.fetchall():
                    stats = extract_generation_stats(data)
                    if stats:
                        cost = calculate_cost(
                            str(stats["model"]), 
                            int(stats["prompt_tokens"]), 
                            int(stats["cached_tokens"]), 
                            int(stats["output_tokens"])
                        )
                        total_cost += cost
            conn.close()
        except Exception:
            pass
            
    return total_cost
