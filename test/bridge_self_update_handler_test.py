import asyncio
import base64
import hashlib
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest


class FakeResponse:
    def __init__(self, data, status=200):
        self.data = data
        self.status = status


class FakeRequest:
    def __init__(self, body, token="test-token"):
        self._body = body
        self.headers = {"Authorization": f"Bearer {token}"}

    async def json(self):
        return self._body


def load_bridge(home):
    web = types.SimpleNamespace(
        json_response=lambda data, status=200, **_kwargs: FakeResponse(
            data, status=status
        )
    )
    aiohttp = types.ModuleType("aiohttp")
    aiohttp.web = web
    sys.modules["aiohttp"] = aiohttp

    os.environ["BRIDGE_HERMES_HOME"] = str(home)
    os.environ["BRIDGE_TOKEN"] = "test-token"
    os.environ["BRIDGE_SCOPES"] = "read,config"
    os.environ["BRIDGE_READ_ONLY"] = "false"
    path = Path(__file__).resolve().parents[1] / "assets/bridge/hermes_bridge.py"
    spec = importlib.util.spec_from_file_location("bridge_update_test_module", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module._audit = lambda *_args, **_kwargs: None
    module.BRIDGE_SCRIPT_PATH = (home / "hermes_bridge.py").resolve()
    return module


class SelfUpdateContractTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bridge-update-test-")
        self.home = Path(self.temp.name)
        self.bridge = load_bridge(self.home)
        self.target = self.home / "hermes_bridge.py"
        self.old_source = 'VERSION = "1.18.0"\nprint("old")\n'
        self.target.write_text(self.old_source, encoding="utf-8")
        self.watchdogs = []
        self.restarts = 0

        def fake_watchdog(target, backup, version):
            self.watchdogs.append((target, backup, version))

        async def fake_restart():
            self.restarts += 1

        self.bridge._launch_self_update_watchdog = fake_watchdog
        self.bridge._restart_bridge_service = fake_restart

    def tearDown(self):
        self.temp.cleanup()

    def body(self, source, version="1.19.0"):
        raw = source.encode("utf-8")
        return {
            "version": version,
            "sha256": hashlib.sha256(raw).hexdigest(),
            "source_b64": base64.b64encode(raw).decode("ascii"),
        }

    async def test_valid_update_is_compiled_backed_up_and_replaced_atomically(self):
        source = 'VERSION = "1.19.0"\nprint("new")\n'

        response = await self.bridge.self_update(FakeRequest(self.body(source)))
        await asyncio.sleep(0)

        self.assertEqual(response.status, 202)
        self.assertTrue(response.data["ok"])
        self.assertEqual(self.target.read_text(encoding="utf-8"), source)
        backup = self.target.with_name("hermes_bridge.py.rollback")
        self.assertEqual(backup.read_text(encoding="utf-8"), self.old_source)
        self.assertEqual(self.watchdogs, [(self.target, backup, "1.19.0")])
        self.assertEqual(self.restarts, 1)
        self.assertFalse(self.target.with_name("hermes_bridge.py.new").exists())

    async def test_bad_hash_syntax_or_version_never_mutates(self):
        invalid = [
            {**self.body('VERSION = "1.19.0"\n'), "sha256": "0" * 64},
            self.body('VERSION = "1.19.0"\ndef broken(:\n'),
            self.body('VERSION = "1.20.0"\n', version="1.19.0"),
            self.body('VERSION = "1.18.0"\n', version="1.18.0"),
        ]

        for body in invalid:
            response = await self.bridge.self_update(FakeRequest(body))
            self.assertEqual(response.status, 400)
            self.assertEqual(self.target.read_text(encoding="utf-8"), self.old_source)
        self.assertEqual(self.watchdogs, [])
        self.assertEqual(self.restarts, 0)

    async def test_auth_read_only_and_missing_scope_fail_before_write(self):
        source = 'VERSION = "1.19.0"\n'
        body = self.body(source)

        response = await self.bridge.self_update(FakeRequest(body, token="wrong"))
        self.assertEqual(response.status, 401)

        self.bridge.READ_ONLY = True
        response = await self.bridge.self_update(FakeRequest(body))
        self.assertEqual(response.status, 403)
        self.bridge.READ_ONLY = False

        self.bridge.SCOPES = {"read"}
        response = await self.bridge.self_update(FakeRequest(body))
        self.assertEqual(response.status, 403)
        self.assertEqual(self.target.read_text(encoding="utf-8"), self.old_source)

    async def test_symlinked_canonical_path_is_rejected(self):
        real_target = self.home / "real_bridge.py"
        real_target.write_text(self.old_source, encoding="utf-8")
        self.target.unlink()
        self.target.symlink_to(real_target)
        self.bridge.BRIDGE_SCRIPT_PATH = self.target.resolve()

        source = 'VERSION = "1.19.0"\nprint("new")\n'
        response = await self.bridge.self_update(FakeRequest(self.body(source)))

        self.assertEqual(response.status, 400)
        self.assertEqual(real_target.read_text(encoding="utf-8"), self.old_source)
        self.assertEqual(self.watchdogs, [])
        self.assertEqual(self.restarts, 0)


if __name__ == "__main__":
    unittest.main()
