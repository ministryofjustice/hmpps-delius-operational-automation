#!/usr/bin/env python3
"""
convert_cron_expression_to_London.py

We convert a UTC Cron Expression supplied as the (only) parameter to correspond
to the equivalent expression in the Europe/London timezone.

This is to provide a workaround for the lack of support for timezones in
the GitHub Action Schedule event.

The following logic applies:

(1) If it is British Summer Time (BST) then the hour field of the expression
(if defined) is advanced by 1.
(2) Otherwise the Cron Expression is returned unchanged since UTC = GMT.

NB: If the hour is 23 then advancing it by 1 hour will change it to the
next day, so the Day-of-Month (dom) or Day-of-Week (dow) fields of the
expression will need to also be updated by 1.

Note that GHA supports Day-of-Week in Numeric (0-6) or Names (SUN-SAT)

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

"""
Reference names for day-of-week mapping (Title case)
Note that we need to handle all case formats for GHA expressions
"""
DOW_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


""""
This function detects the format of the original day names
in the Cron expression so that this can eb preserved.
"""


def match_case(original: str, new: str) -> str:
    """Return new formatted to match the case pattern of original."""
    if original.islower():
        return new.lower()
    if original.isupper():
        return new.upper()
    if original.istitle():
        return new.title()
    return new


"""
   Shift the hour field forward by 1 hour.  Note that we need to handle
   some variations:

   Single Hour:  e.g. 1
   List of Hours:  e.g. 1,5
   Range of Hours:  e.g. 1-5

   We use the Split() function to loop through lists to create tokens
   which may either be single hours or ranges.  If it is an hour then
   add one to the value.  If it is a range then add one to both the
   start and end values.

   If the original hour is 23 then set the "rolled" flag to indicate that
   we have rolled into the next day.

   No change is needed for a wildcard (*)

"""


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


"""
   Shift the Day-of-Month (dom) field forward by 1 day.
   This function is called if the "rolled" flag is set above.

   Similar to the shift_hour_field function we need to handle
   a variety of formats:

   Single Day: e.g. 1
   List of Days: e.g. 1,5
   Range of Days: e.g. 1-5

   Therefore we can use similar functionality to the preceding
   function for update the dom.

   Note that Cron does not incorporate any knowledge of different
   month lengths, so we only loop if we are already on the 31st
   day of the month.   This is a limitation of Cron itself so
   we should not be scheduling things to explicitly run (only) on
   doms higher than the 28th of any month.

"""


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


"""
   Shift the Day-of-Week (dow) field forward by 1 day.
   This function is called if the "rolled" flag is set above.

   Similar to the shift_hour_field function we need to handle
   a variety of formats:

   Single Day: e.g. 0 or SUN
   List of Days: e.g. 0,5 or SUN,THU
   Range of Days: e.g. 0-5 or SUN-THU

   Therefore we can use similar functionality to the preceding
   function for update the dow.   However we need to have too
   versions of the logic depending on if we are using numeric
   or string day names.   If the latter, we use the enumerate
   function to switch back to names after incrementing.

   If we reach the end of the week, we swap back to the start.

"""


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
                idx = next((i for i, name in enumerate(DOW_NAMES)
                           if name.lower() == part.lower()), None)
                if idx is not None:
                    new_name = DOW_NAMES[(idx + 1) % 7]
                    shifted_parts.append(match_case(part, new_name))
                else:
                    shifted_parts.append(part)
            new.append('-'.join(shifted_parts))
    return ','.join(new)


"""
  Process each part of the Cron expression.

  1. The Minute field is ignored.
  2. The Hour field is advanced by 1.
  3. The Day-of-Month (dom) field is advanced by 1 only if the Hour field "rolled" over (was > 23h).
  4. The Month field is ignored (we do not use cron expressions for specific months).
  5. The Day-of-Week (dow) field is advanced by 1 only the Hour field "rolled" over (was > 23h).

"""


def process_schedule(schedule: str) -> str:
    parts = schedule.strip().split()
    if len(parts) != 5:
        sys.exit(
            "Error: schedule must have exactly 5 fields (minute hour dom month dow)")
    minute, hour, dom, month, dow = parts
    new_hour, rolled = shift_hour_field(hour)
    new_dom = shift_dom_field(dom) if rolled else dom
    new_dow = shift_dow_field(dow) if rolled else dow
    return f"{minute} {new_hour} {new_dom} {month} {new_dow}"


"""

  Main entry point.  Update the Cron Schedule expression only
  if it is currently BST in London.  Otherwise return the schedule unchanged.

"""


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
