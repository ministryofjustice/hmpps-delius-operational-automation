from datetime import datetime
from zoneinfo import ZoneInfo

dt = datetime.now(ZoneInfo("Europe/London"))
print(dt.strftime("%Z"))