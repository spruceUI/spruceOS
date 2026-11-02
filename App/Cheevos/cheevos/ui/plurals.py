"""Which plural form a count takes in each language PyUI offers (CLDR's rules, for whole numbers).

A :class:`~cheevos.ui.strings.Plural` has a form per category; a language's rule picks one for a
count. Languages are named as PyUI names its language files; one without a rule here uses
English's, which most of PyUI's languages share.
"""

from __future__ import annotations

from collections.abc import Callable

CATEGORIES = ("one", "few", "many", "other")

Rule = Callable[[int], str]


def _one_other(count: int) -> str:
    """Pick the form for English and most European languages: 1 is ``one``.

    Args:
        count: The number.

    Returns:
        The category.
    """
    return "one" if count == 1 else "other"


def _zero_one_other(count: int) -> str:
    """Pick the form for French, Brazilian Portuguese and Hindi: 0 and 1 are ``one``.

    Args:
        count: The number.

    Returns:
        The category.
    """
    return "one" if count in (0, 1) else "other"


def _other(_count: int) -> str:
    """Pick the only form of languages without plurals (Chinese, Japanese, Korean, ...).

    Args:
        _count: The number.

    Returns:
        ``"other"``.
    """
    return "other"


def _few(count: int) -> bool:
    """Report whether a count ends in 2-4 but not 12-14, the Slavic ``few``.

    Args:
        count: The number.

    Returns:
        ``True`` for 2, 3, 4, 22, 23, 24, 32, ...
    """
    return 2 <= count % 10 <= 4 and not 12 <= count % 100 <= 14  # noqa: PLR2004


def _east_slavic(count: int) -> str:
    """Pick the form for Russian and Ukrainian: 1, 21, 31 ``one``; 2-4 ``few``; else ``many``.

    Args:
        count: The number.

    Returns:
        The category.
    """
    if count % 10 == 1 and count % 100 != 11:  # noqa: PLR2004
        return "one"
    return "few" if _few(count) else "many"


def _south_slavic(count: int) -> str:
    """Pick the form for Bosnian, Croatian and Serbian: as Russian, with ``other`` for ``many``.

    Args:
        count: The number.

    Returns:
        The category.
    """
    if count % 10 == 1 and count % 100 != 11:  # noqa: PLR2004
        return "one"
    return "few" if _few(count) else "other"


def _polish(count: int) -> str:
    """Pick the form for Polish: 1 ``one``; 2-4, 22-24, ... ``few``; else ``many``.

    Args:
        count: The number.

    Returns:
        The category.
    """
    if count == 1:
        return "one"
    return "few" if _few(count) else "many"


def _romanian(count: int) -> str:
    """Pick the form for Romanian: 1 ``one``; 0 and 2-19 (also 102-119, ...) ``few``.

    Args:
        count: The number.

    Returns:
        The category.
    """
    if count == 1:
        return "one"
    return "few" if count == 0 or 2 <= count % 100 <= 19 else "other"  # noqa: PLR2004


def _tagalog(count: int) -> str:
    """Pick the form for Tagalog: ``one`` unless the count ends in 4, 6 or 9.

    Args:
        count: The number.

    Returns:
        The category.
    """
    return "other" if count % 10 in (4, 6, 9) else "one"


RULES: dict[str, Rule] = {
    "Bosnian": _south_slavic,
    "Chinese (S)": _other,
    "Chinese (T)": _other,
    "Croatian": _south_slavic,
    "French": _zero_one_other,
    "Hindi": _zero_one_other,
    "Japanese": _other,
    "Khmer": _other,
    "Korean": _other,
    "Lao": _other,
    "Polish": _polish,
    "Portuguese (BR)": _zero_one_other,
    "Romanian": _romanian,
    "Russian": _east_slavic,
    "Serbian": _south_slavic,
    "Tagalog": _tagalog,
    "Thai": _other,
    "Toki Pona": _other,
    "Ukrainian": _east_slavic,
    "Vietnamese": _other,
}


def rule(language: str) -> Rule:
    """Return a language's plural rule.

    Args:
        language: The language, as PyUI names its file (``"Polish"``, ``"Chinese (S)"``).

    Returns:
        The rule; English's for a language not listed.
    """
    return RULES.get(language, _one_other)
