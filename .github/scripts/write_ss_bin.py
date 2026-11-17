import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "App", "PyUI", "main-ui"))
from utils.boxart.screenscraper import DEV_FILE, _load_dev, encode_dev

credentials = {"devid": os.environ["SS_DEVID"], "devpassword": os.environ["SS_DEVPASSWORD"]}
with open(DEV_FILE, "wb") as f:
    f.write(encode_dev(credentials))
if _load_dev(DEV_FILE) != credentials:
    sys.exit(f"{DEV_FILE} does not decode back to the credentials")
