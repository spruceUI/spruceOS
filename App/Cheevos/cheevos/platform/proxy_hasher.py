"""RAOfflineProxy's ROM hashing, reached through its lightweight wrapper (.agents/integration.md).

Cheevos ships no hasher of its own. It imports the installed proxy's ``rom_hashing`` module
(a ctypes binding over ``libraproxy_rchash``, rcheevos' ``rc_hash``) and nothing else from the
proxy: not ``rom_browser``, ``main``, ``menu_sdl``, its storage or its service. The proxy's
files are only read; nothing here starts, stops or writes it.

Everything used from the proxy is listed in :data:`REQUIRED_FUNCTIONS` and
:data:`EXPECTED_MODULES`. A missing or changed API is a ``dependency`` error, never a crash, and
``scripts/check_proxy_compat.py`` checks both against a proxy checkout or Spruce bundle.
"""

from __future__ import annotations

import importlib
import logging
import sys
from pathlib import Path
from types import ModuleType

from cheevos.core.identification.candidates import HashResult
from cheevos.core.identification.result import DEPENDENCY, HASH, IdentificationError

logger = logging.getLogger(__name__)

PACKAGE = "raofflineproxy"
MODULE = "raofflineproxy.rom_hashing"
REQUIRED_FUNCTIONS = (
    "load_rchash",
    "hash_rom_candidates_result",
    "list_7z_entries",
    "hash_7z_entry_candidates",
    "supported_rom_extensions",
)
# What importing rom_hashing loads from the proxy. Anything else is logged here and fails
# scripts/check_proxy_compat.py, which keeps the dependency this narrow.
EXPECTED_MODULES = frozenset(
    {
        PACKAGE,
        MODULE,
        "raofflineproxy.rvz_datasource",
        "raofflineproxy.native_codecs",
    }
)


def _strings(values: object, what: str) -> list[str]:
    """Check that the proxy returned a list of strings."""
    if not isinstance(values, (list, tuple, set, frozenset)) or not all(
        isinstance(value, str) for value in values
    ):
        raise IdentificationError(HASH, f"{what} returned {type(values).__name__}")
    return list(values)


class ProxyHasher:
    """The :class:`~cheevos.core.identification.candidates.Hasher` over ``rom_hashing``.

    Exceptions from the proxy's code become ``hash`` errors for the ROM at hand.

    Args:
        module: The imported ``raofflineproxy.rom_hashing``.
        extensions: Its supported ROM extensions.
    """

    def __init__(self, module: ModuleType, extensions: frozenset[str]) -> None:
        self._module = module
        self._extensions = extensions

    def supported_extensions(self) -> frozenset[str]:
        """Return the ROM extensions the proxy recognises inside archives."""
        return self._extensions

    def hash_file(self, path: Path) -> HashResult:
        """Hash a file with ``hash_rom_candidates_result``."""
        try:
            result = self._module.hash_rom_candidates_result(path)
            candidates = _strings(result.candidates, "hash_rom_candidates_result")
            error = result.error
        except IdentificationError:
            raise
        except Exception as exc:  # the proxy's code, any version
            raise IdentificationError(HASH, f"hashing {path.name}: {exc!r}") from exc
        return HashResult(tuple(candidates), str(error) if error else None)

    def list_7z_entries(self, path: Path) -> list[str]:
        """List a ``.7z`` with ``list_7z_entries``."""
        try:
            return _strings(self._module.list_7z_entries(path), "list_7z_entries")
        except IdentificationError:
            raise
        except Exception as exc:  # the proxy's code, any version
            raise IdentificationError(HASH, f"listing {path.name}: {exc!r}") from exc

    def hash_7z_entry(self, path: Path, entry: str) -> tuple[str, ...]:
        """Hash a ``.7z`` entry with ``hash_7z_entry_candidates``."""
        try:
            values = self._module.hash_7z_entry_candidates(path, entry)
            return tuple(_strings(values, "hash_7z_entry_candidates"))
        except IdentificationError:
            raise
        except Exception as exc:  # the proxy's code, any version
            raise IdentificationError(HASH, f"hashing {entry} in {path.name}: {exc!r}") from exc


def import_hashing_module(package_root: Path) -> ModuleType:
    """Import the proxy's ``rom_hashing`` module, and only that, from its package root.

    Args:
        package_root: The directory holding the ``raofflineproxy`` package
            (``App/RAOfflineProxy/app`` on a device).

    Returns:
        The module.

    Raises:
        IdentificationError: ``dependency`` when the proxy is missing or doesn't import.
    """
    package_dir = package_root / PACKAGE
    if not (package_dir / "rom_hashing.py").is_file():
        raise IdentificationError(DEPENDENCY, f"no RAOfflineProxy hashing module in {package_root}")
    if str(package_root) not in sys.path:
        sys.path.insert(0, str(package_root))
    # Write no __pycache__ into the proxy's directory: its files are read, never changed.
    # Python still uses the bytecode the proxy compiled for itself.
    writes_bytecode = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        module = importlib.import_module(MODULE)
    except Exception as exc:  # an incompatible proxy may fail in any way
        raise IdentificationError(DEPENDENCY, f"importing {MODULE}: {exc!r}") from exc
    finally:
        sys.dont_write_bytecode = writes_bytecode
    origin = Path(getattr(module, "__file__", "") or "")
    if origin.parent.resolve() != package_dir.resolve():
        raise IdentificationError(DEPENDENCY, f"{MODULE} came from {origin}, not {package_dir}")
    unexpected = sorted(
        name for name in sys.modules if name.startswith(PACKAGE) and name not in EXPECTED_MODULES
    )
    if unexpected:
        logger.warning("RAOfflineProxy's hashing module also loaded %s", ", ".join(unexpected))
    return module


def check_api(module: ModuleType) -> frozenset[str]:
    """Check the functions the adapter calls, and read the supported ROM extensions.

    Loads no native library, so ``scripts/check_proxy_compat.py`` can run it off the device.

    Args:
        module: The imported ``rom_hashing``.

    Returns:
        The lower-case supported ROM extensions.

    Raises:
        IdentificationError: ``dependency`` when a function is missing or misbehaves.
    """
    missing = [name for name in REQUIRED_FUNCTIONS if not callable(getattr(module, name, None))]
    if missing:
        raise IdentificationError(DEPENDENCY, f"{MODULE} lacks {', '.join(missing)}")
    try:
        values = _strings(module.supported_rom_extensions(), "supported_rom_extensions")
    except Exception as exc:  # the proxy's code, any version
        raise IdentificationError(DEPENDENCY, f"{MODULE}: {exc!r}") from exc
    return frozenset(value.lower() for value in values)


def load_proxy_hasher(proxy_app_dir: Path) -> ProxyHasher:
    """Load the installed proxy's hashing wrapper and its native library.

    Args:
        proxy_app_dir: ``App/RAOfflineProxy``.

    Returns:
        The hasher.

    Raises:
        IdentificationError: ``dependency`` when the proxy, an API we use or its native
            library is missing or incompatible.
    """
    module = import_hashing_module(proxy_app_dir / "app")
    extensions = check_api(module)
    try:
        library = module.load_rchash()
    except Exception as exc:  # the proxy's code, any version
        raise IdentificationError(DEPENDENCY, f"{MODULE}.load_rchash: {exc!r}") from exc
    if library is None:
        # _LIBRCHASH_ERROR is read for the log only; nothing else depends on it.
        detail = getattr(module, "_LIBRCHASH_ERROR", None) or "libraproxy_rchash not loaded"
        raise IdentificationError(DEPENDENCY, str(detail))
    logger.info("Using RAOfflineProxy's hasher from %s", module.__file__)
    return ProxyHasher(module, extensions)
