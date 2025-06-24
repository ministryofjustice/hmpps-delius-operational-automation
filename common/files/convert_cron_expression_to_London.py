#!/usr/bin/env python3
"""
convert_cron_expression_to_London.py

Increment the hour field of a cron schedule (five fields) passed as a parameter,
but only if Europe/London is currently observing BST (British Summer Time).
If not in BST, the schedule is printed unchanged.
If any hour token rolls over from 23→0, the day-of-month and day-of-week
fields are also incremented by one, preserving input case for day names.

Usage:
  ./convert_cron_expression_to_London.py "0 23 * * fri-SAT"
# → if in BST: "0 0 * * sat-SUN"
# → if not BST:  "0 23 * * fri-SAT"

Features:
  - Lists (e.g., 2,8,14)
  - Ranges (e.g., 9-17)
  - Wildcards (*) left unchanged
  - Day-of-month numeric or ranges
  - Day-of-week numeric (0-7) or names (Sun,Mon,...) in any case/input style

Note: Numeric dom wraps 1–31; dow wraps Sun–Sat.
"""
import sys
import re
from datetime import datetime, timedelta
try:
    from zoneinfo import ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo 
    
# Reference names for day-of-week mapping (Title case)
DOW_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


def match_case(original: str, new: str) -> str:
    """Return new formatted to match the case pattern of original."""
    if original.islower():
        return new.lower()
    if original.isupper():
        return new.upper()
    if original.istitle():
        return new.title()
    return new


def shift_hour_field(hour_field: str) -> (str, bool):
    tokens = hour_field.split(',')
    new_tokens = []
    rolled = False
    for tok in tokens:
        if tok == '*':
            new_tokens.append(tok)
        else:
            m_num = re.fullmatch(r"(\d+)", tok)
            m_range = re.fullmatch(r"(\d+)-(\d+)", tok)
            if m_num:
                h = int(m_num.group(1))
                nh = (h + 1) % 24
                new_tokens.append(str(nh))
                if h == 23:
                    rolled = True
            elif m_range:
                start, end = map(int, m_range.groups())
                new_start = (start + 1) % 24
                new_end = (end + 1) % 24
                new_tokens.append(f"{new_start}-{new_end}")
                if start <= 23 <= end:
                    rolled = True
            else:
                new_tokens.append(tok)
    return ','.join(new_tokens), rolled


def shift_dom_field(dom_field: str) -> str:
    tokens = dom_field.split(',')
    new = []
    for tok in tokens:
        if tok == '*':
            new.append(tok)
        else:
            m_num = re.fullmatch(r"(\d+)", tok)
            m_range = re.fullmatch(r"(\d+)-(\d+)", tok)
            if m_num:
                d = int(m_num.group(1))
                nd = d + 1 if d < 31 else 1
                new.append(str(nd))
            elif m_range:
                s, e = map(int, m_range.groups())
                ns = s + 1 if s < 31 else 1
                ne = e + 1 if e < 31 else 1
                new.append(f"{ns}-{ne}")
            else:
                new.append(tok)
    return ','.join(new)


def shift_dow_field(dow_field: str) -> str:
    tokens = dow_field.split(',')
    new = []
    for tok in tokens:
        if tok == '*':
            new.append(tok)
            continue
        m_num = re.fullmatch(r"(\d+)", tok)
        m_range = re.fullmatch(r"(\d+)-(\d+)", tok)
        if m_num:
            d = int(m_num.group(1)) % 7
            nd = (d + 1) % 7
            new.append(str(nd))
        elif m_range:
            s, e = map(int, m_range.groups())
            ns = (s + 1) % 7
            ne = (e + 1) % 7
            new.append(f"{ns}-{ne}")
        else:
            parts = tok.split('-')
            shifted_parts = []
            for part in parts:
                idx = next((i for i, name in enumerate(DOW_NAMES) if name.lower() == part.lower()), None)
                if idx is not None:
                    new_name = DOW_NAMES[(idx + 1) % 7]
                    shifted_parts.append(match_case(part, new_name))
                else:
                    shifted_parts.append(part)
            new.append('-'.join(shifted_parts))
    return ','.join(new)


def process_schedule(schedule: str) -> str:
    parts = schedule.strip().split()
    if len(parts) != 5:
        sys.exit("Error: schedule must have exactly 5 fields (minute hour dom month dow)")
    minute, hour, dom, month, dow = parts
    new_hour, rolled = shift_hour_field(hour)
    new_dom = shift_dom_field(dom) if rolled else dom
    new_dow = shift_dow_field(dow) if rolled else dow
    return f"{minute} {new_hour} {new_dom} {month} {new_dow}"


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} \"<cron schedule>\"", file=sys.stderr)
        sys.exit(1)
    schedule = sys.argv[1]
    # Check if Europe/London is in BST
    tz = ZoneInfo('Europe/London')
    now = datetime.now(tz)
    if now.dst() == timedelta(0):
        # Not BST: print unchanged
        print(schedule)
        sys.exit(0)
    # In BST: shift
    try:
        print(process_schedule(schedule))
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
