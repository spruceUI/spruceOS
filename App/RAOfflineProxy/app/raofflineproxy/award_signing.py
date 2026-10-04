from __future__ import annotations

import base64
import hashlib
import hmac
import secrets

from .config import AWARD_SECRET_FILE, ensure_config_dir


def load_or_create_secret() -> bytes:
    if AWARD_SECRET_FILE.exists():
        return AWARD_SECRET_FILE.read_bytes()

    ensure_config_dir()
    secret = secrets.token_bytes(32)
    AWARD_SECRET_FILE.write_bytes(secret)
    return secret


def sign_award(data: bytes) -> str:
    secret = load_or_create_secret()
    digest = hmac.new(secret, data, hashlib.sha256).digest()
    return base64.b64encode(digest).decode("ascii")


def verify_award(data: bytes, signature: str) -> bool:
    expected = sign_award(data)
    return hmac.compare_digest(expected, signature)


def public_key_base64() -> str:
    key_id = hashlib.sha256(load_or_create_secret()).hexdigest()
    return base64.b64encode(key_id.encode("ascii")).decode("ascii")
