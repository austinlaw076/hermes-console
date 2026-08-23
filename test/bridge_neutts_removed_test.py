import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest


def load_bridge(home):
    web = types.SimpleNamespace(
        json_response=lambda data, status=200, **_kwargs: (data, status)
    )
    aiohttp = types.ModuleType("aiohttp")
    aiohttp.web = web
    sys.modules["aiohttp"] = aiohttp

    os.environ["BRIDGE_HERMES_HOME"] = str(home)
    os.environ["BRIDGE_TOKEN"] = "test-token"
    os.environ["BRIDGE_SCOPES"] = "read,config"
    os.environ["BRIDGE_READ_ONLY"] = "false"
    path = Path(__file__).resolve().parents[1] / "assets/bridge/hermes_bridge.py"
    spec = importlib.util.spec_from_file_location("bridge_neutts_removed_module", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module._audit = lambda *_args, **_kwargs: None
    return module


class NeuttsRemovedContractTest(unittest.TestCase):
    """Contrato: NeuTTS quedó retirado por completo del Bridge empaquetado."""

    BRIDGE = Path(__file__).resolve().parents[1] / "assets/bridge/hermes_bridge.py"

    def test_neutts_handlers_are_absent(self):
        temp = tempfile.TemporaryDirectory(prefix="bridge-neutts-removed-")
        self.addCleanup(temp.cleanup)
        bridge = load_bridge(Path(temp.name))
        for name in (
            "neutts_status",
            "neutts_install",
            "neutts_configure",
            "neutts_test",
            "neutts_activate",
        ):
            self.assertFalse(
                hasattr(bridge, name),
                f"El handler NeuTTS '{name}' debe estar retirado del bridge",
            )

    def test_no_neutts_routes_flags_or_constants_in_source(self):
        src = self.BRIDGE.read_text(encoding="utf-8")
        self.assertNotIn("/bridge/tts/neutts/", src)
        self.assertNotIn("tts_neutts", src)
        self.assertNotIn("NEUTTS_", src)
        self.assertNotIn("neutts", src.lower())


if __name__ == "__main__":
    unittest.main()
