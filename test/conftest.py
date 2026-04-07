"""
conftest.py — pytest configuration for the hummingbot-api test suite.

Stubs out Cython-compiled hummingbot modules that are not compiled in the
development environment (only .pyx / .pxd sources exist, no .so files).
This must run before any test module is imported so that subsequent
``from hummingbot.*`` imports inside test files succeed.
"""
import glob
import sys
import types
from unittest.mock import MagicMock


def _make_mock_module(name: str) -> types.ModuleType:
    m = types.ModuleType(name)

    def _getattr(n):
        return MagicMock()

    m.__getattr__ = _getattr
    sys.modules[name] = m
    return m


def _stub_cython_modules() -> None:
    """
    Find every .pyx file under the hummingbot source tree and register a
    lightweight mock module so that Python-level imports don't fail with
    ModuleNotFoundError when the Cython extension hasn't been compiled.
    """
    import os

    hb_root = os.path.join(
        os.path.dirname(__file__), "..", "..", "hummingbot", "hummingbot"
    )
    hb_root = os.path.normpath(hb_root)

    if not os.path.isdir(hb_root):
        return  # hummingbot source not present; skip

    for pyx_path in glob.glob(f"{hb_root}/**/*.pyx", recursive=True):
        rel = pyx_path[len(hb_root) + 1:].replace("/", ".").replace(".pyx", "")
        mod_name = f"hummingbot.{rel}"
        if mod_name not in sys.modules:
            _make_mock_module(mod_name)

    # Some pure-Python modules pull in Cython bases and trigger metaclass
    # conflicts at class-body parse time; stub them out entirely.
    _PURE_PY_STUBS = [
        "hummingbot.connector.connector_metrics_collector",
    ]
    for mod_name in _PURE_PY_STUBS:
        if mod_name not in sys.modules:
            _make_mock_module(mod_name)


# Run once at collection time.
_stub_cython_modules()
