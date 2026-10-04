from __future__ import annotations

import hashlib
import re
from urllib.parse import parse_qsl, quote_plus, unquote_plus, urlencode, urlsplit

from .config import FALLBACK_USER_AGENT, PROXY_UA_TAG


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse_form_params(body: str) -> dict[str, str]:
    if not body:
        return {}
    return dict(parse_qsl(body, keep_blank_values=True))


def extract_form_param(body: str, name: str) -> str | None:
    return parse_form_params(body).get(name)


def extract_query_param(path: str, name: str) -> str | None:
    query = urlsplit(path).query
    if not query:
        return None
    return dict(parse_qsl(query, keep_blank_values=True)).get(name)


def extract_request_param(path: str, body: str, name: str) -> str | None:
    return extract_query_param(path, name) or extract_form_param(body, name)


def extract_action(path: str, body: str) -> str | None:
    return extract_request_param(path, body, "r")


def is_hardcore_request(path: str, body: str) -> bool:
    return extract_request_param(path, body, "h") == "1"


def replace_or_append_form_param(body: str, name: str, value: str) -> str:
    params = parse_qsl(body, keep_blank_values=True)
    encoded = quote_plus(value)
    replaced = False
    updated: list[str] = []

    for key, current_value in params:
        if key == name and not replaced:
            updated.append(f"{key}={encoded}")
            replaced = True
        elif key == name:
            continue
        else:
            updated.append(f"{key}={quote_plus(current_value)}")

    if not replaced:
        updated.append(f"{name}={encoded}")

    return "&".join(updated)


def build_form_body(params: dict[str, str]) -> str:
    return urlencode(params)


def proxy_user_agent(original: str) -> str:
    if PROXY_UA_TAG in original:
        return original
    return f"{original} {PROXY_UA_TAG}"


def self_user_agent() -> str:
    """User-Agent for requests the proxy makes on its own behalf.

    Never reuse a cached client User-Agent here. RetroAchievements reads the
    first token as the client identity and rejects blocked clients with 403 on
    every endpoint, so borrowing an emulator's identity makes our own lookups
    fail whenever that emulator is blocked. Only forwarded requests should
    carry a client's User-Agent.
    """
    return proxy_user_agent(FALLBACK_USER_AGENT)


def canonical_reason_phrase(code: int) -> str:
    phrases = {
        200: "OK",
        400: "Bad Request",
        401: "Unauthorized",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        413: "Payload Too Large",
        500: "Internal Server Error",
        501: "Not Implemented",
        503: "Service Unavailable",
    }
    return phrases.get(code, "Response")


# Only a t=/p= that actually starts a query parameter, hence the leading delimiter: a bare
# substring match also fires on the "t=" inside host=, port= and checked_at=, and with no
# "&" left on the line to stop at it swallows everything after it. That silently shredded
# whole support logs, which are redacted line by line before upload.
#
# The delimiter class is deliberately wider than "?&": these run over free-text log lines,
# where a secret can also follow a quote or a comma. Letters are what must not qualify, so
# host=/port=/checked_at= stay readable.
_QUERY_SECRET_PATTERN = re.compile(r"""(^|[?&,;\s"'\[({])([tp])=([^&\s"'\])}]*)""")


def redact_query_tokens(value: str) -> str:
    return _QUERY_SECRET_PATTERN.sub(
        lambda match: f"{match.group(1)}{match.group(2)}=<token>", value
    )


def redact_form_tokens(value: str) -> str:
    params = parse_qsl(value, keep_blank_values=True)
    redacted = [
        (key, "<token>" if key in {"t", "p"} else current) for key, current in params
    ]
    return urlencode(redacted)


def query_params_from_path(path: str) -> dict[str, str]:
    return dict(parse_qsl(urlsplit(path).query, keep_blank_values=True))


def decode_value(value: str) -> str:
    return unquote_plus(value)
