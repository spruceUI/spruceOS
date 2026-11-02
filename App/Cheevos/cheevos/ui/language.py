"""The app's language: Spruce's UI language, where Cheevos has a translation for it.

Translations ship with the app, one JSON file per language in ``res/lang``, named as PyUI names
its own language files (``Catalan.json``, ``Chinese (S).json``). A file maps the names in
:mod:`cheevos.ui.strings` to translated values. Anything missing, and any value that wouldn't
format like the English one, stays English (.agents/product.md, "Languages").

A session applies its language over the English values when it starts (:func:`use`). PyUI drops
the app's modules when the session ends, so each session starts from English; tests go back to
English with :func:`reset`.
"""

from __future__ import annotations

import json
import logging
import string
from pathlib import Path

from cheevos.ui import plurals, strings

logger = logging.getLogger(__name__)

ENGLISH = "English"
LANG_DIR = Path(__file__).resolve().parents[1] / "res" / "lang"

Value = str | strings.Plural | dict[str, str] | tuple[str, ...]

_ENGLISH: dict[str, Value] = {
    name: value
    for name, value in vars(strings).items()
    if name.isupper() and isinstance(value, (str, strings.Plural, dict, tuple))
}
_rule: plurals.Rule = plurals.rule(ENGLISH)


def english() -> dict[str, Value]:
    """Return every string by name, in English, in the order ``strings`` defines them.

    Returns:
        A copy of the English values.
    """
    return dict(_ENGLISH)


def plural_category(count: int) -> str:
    """Return the plural category the current language uses for ``count``.

    Args:
        count: The number.

    Returns:
        ``"one"``, ``"few"``, ``"many"`` or ``"other"``.
    """
    return _rule(count)


def reset() -> None:
    """Put every string back to English."""
    apply(ENGLISH, {})


def use(name: str | None, lang_dir: Path = LANG_DIR) -> None:
    """Show the app in a language: its translation over English, or English when there's none.

    Args:
        name: The language, as PyUI names its files; ``None`` for English.
        lang_dir: Where the translations are.
    """
    reset()
    if not name or name == ENGLISH:
        return
    path = lang_dir / f"{name}.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        logger.info("No %s translation; showing English", name)
        return
    except (OSError, ValueError) as exc:  # ValueError: not JSON, or not UTF-8
        logger.warning("Could not read %s, showing English: %s", path.name, exc)
        return
    translations, problems = parse(data)
    for problem in problems:
        logger.warning("%s: %s", path.name, problem)
    apply(name, translations)
    logger.info("Showing %s: %d of %d strings translated", name, len(translations), len(_ENGLISH))


def apply(name: str, translations: dict[str, Value]) -> None:
    """Show checked translations, and English for everything else.

    Args:
        name: The language (its plural rule).
        translations: Values by name, from :func:`parse`.
    """
    global _rule  # noqa: PLW0603 — one language per session, like the strings module's values
    for key, value in _ENGLISH.items():
        setattr(strings, key, translations.get(key, value))
    _rule = plurals.rule(name)


def parse(data: object) -> tuple[dict[str, Value], list[str]]:
    """Check a translation file's contents against the English strings.

    Keys starting with ``_`` are notes and are skipped, as is ``""`` (not translated yet).

    Args:
        data: The parsed JSON.

    Returns:
        ``(translations, problems)``: the values that can be shown, and what was left out and
        why, e.g. ``"SYNC_DONE_AGO: unknown field {when}"``.
    """
    if not isinstance(data, dict):
        return {}, ["expected a JSON object of names and translations"]
    translations: dict[str, Value] = {}
    problems: list[str] = []
    for key, value in data.items():
        if key.startswith("_") or value == "":
            continue
        english_value = _ENGLISH.get(key)
        if english_value is None:
            problems.append(f"{key}: no such string (renamed or removed?)")
            continue
        parsed, found = _parse_value(value, english_value)
        problems.extend(f"{key}: {problem}" for problem in found)
        if parsed is not None:
            translations[key] = parsed
    return translations, problems


def _parse_value(value: object, english_value: Value) -> tuple[Value | None, list[str]]:
    """Check one translated value against its English value.

    Args:
        value: The translation, as parsed from JSON.
        english_value: The English value it replaces.

    Returns:
        ``(value to show or None, problems)``.
    """
    if isinstance(english_value, strings.Plural):
        return _parse_plural(value, english_value)
    if isinstance(english_value, dict):
        return _parse_mapping(value, english_value)
    if isinstance(english_value, tuple):
        return _parse_sequence(value, english_value)
    problem = check_text(value, english_value)
    return (None, [problem]) if problem else (str(value), [])


def _parse_plural(value: object, english_value: strings.Plural) -> tuple[Value | None, list[str]]:
    """Check a translation of a :class:`~cheevos.ui.strings.Plural`.

    Plain text serves every count. A form other than ``other`` may leave fields out ("one
    minute ago" needs no ``{count}``).

    Args:
        value: Text, or forms by category (``other`` required).
        english_value: The English forms.

    Returns:
        ``(value to show or None, problems)``.
    """
    if isinstance(value, str):
        problem = check_text(value, english_value.other)
        return (None, [problem]) if problem else (strings.Plural(other=value), [])
    if not isinstance(value, dict) or not value.get("other"):
        return None, ['expected text, or forms like {"one": ..., "other": ...}']
    problems = [f"no plural form {form!r}" for form in value if form not in plurals.CATEGORIES]
    forms: dict[str, str] = {}
    for form in plurals.CATEGORIES:
        text = value.get(form)
        if text is None or text == "":
            continue
        problem = check_text(text, english_value.other, every_field=form == "other")
        if problem is None:
            forms[form] = str(text)
        elif form == "other":
            return None, [*problems, f"other: {problem}"]
        else:
            problems.append(f"{form}: {problem}")
    return strings.Plural(**forms), problems


def _parse_mapping(value: object, english_value: dict[str, str]) -> tuple[Value | None, list[str]]:
    """Check a translation of a dict of labels (filters, sorts, ...): any of its entries.

    Args:
        value: Translations by the English dict's keys.
        english_value: The English labels.

    Returns:
        ``(the labels, translated where possible, or None; problems)``.
    """
    if not isinstance(value, dict):
        return None, [f"expected an object with the keys {', '.join(english_value)}"]
    merged = dict(english_value)
    problems: list[str] = []
    for key, text in value.items():
        if key not in english_value:
            problems.append(f"{key}: no such entry")
        elif text != "":
            problem = check_text(text, english_value[key])
            if problem:
                problems.append(f"{key}: {problem}")
            else:
                merged[key] = str(text)
    return merged, problems


def _parse_sequence(
    value: object, english_value: tuple[str, ...]
) -> tuple[Value | None, list[str]]:
    """Check a translation of a fixed list (month names, the About lines).

    Args:
        value: A list as long as the English one.
        english_value: The English items.

    Returns:
        ``(the items, translated where possible, or None; problems)``.
    """
    if not isinstance(value, list) or len(value) != len(english_value):
        return None, [f"expected a list of {len(english_value)}"]
    items: list[str] = []
    problems: list[str] = []
    for index, (text, english_text) in enumerate(zip(value, english_value, strict=True), start=1):
        problem = None if text == "" else check_text(text, english_text)
        if problem:
            problems.append(f"item {index}: {problem}")
        items.append(english_text if problem or text == "" else str(text))
    return tuple(items), problems


def check_text(value: object, english_text: str, *, every_field: bool = True) -> str | None:
    """Check that a translated template formats with the English one's fields.

    A field the code doesn't pass would stop the screen; one left out loses information.

    Args:
        value: The translation.
        english_text: The English template.
        every_field: Require every English field (plural forms other than ``other`` may drop
            some).

    Returns:
        What's wrong, or ``None``.
    """
    if not isinstance(value, str):
        return "expected text"
    fields = _fields(value)
    if fields is None:
        return "braces must hold a field name like {count} (write {{ and }} for braces)"
    expected = _fields(english_text) or {}
    if unknown := sorted(fields.keys() - expected.keys()):
        return "unknown field " + ", ".join(f"{{{name}}}" for name in unknown)
    if every_field and (missing := sorted(expected.keys() - fields.keys())):
        return "missing field " + ", ".join(f"{{{name}}}" for name in missing)
    for name, spec in fields.items():
        if spec not in ("", expected[name]):
            return f"write {{{name}}} or {{{name}:{expected[name]}}}, not {{{name}:{spec}}}"
    return None


def _fields(template: str) -> dict[str, str] | None:
    """List a template's named fields and their format specs.

    Args:
        template: A ``str.format`` template.

    Returns:
        Spec by field name, or ``None`` if the braces don't parse or a field isn't a plain name.
    """
    try:
        parsed = list(string.Formatter().parse(template))
    except ValueError:
        return None
    fields: dict[str, str] = {}
    for _literal, name, spec, conversion in parsed:
        if name is None:
            continue
        if not name.isidentifier() or conversion or "{" in (spec or ""):
            return None
        fields[name] = spec or ""
    return fields
