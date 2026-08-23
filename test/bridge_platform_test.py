import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock


def load_bridge(home):
    web = types.SimpleNamespace(json_response=lambda data, status=200, **_: data)
    aiohttp = types.ModuleType("aiohttp")
    aiohttp.web = web
    sys.modules["aiohttp"] = aiohttp
    os.environ["BRIDGE_HERMES_HOME"] = str(home)
    os.environ["BRIDGE_TOKEN"] = "platform-test-token"
    path = Path(__file__).resolve().parents[1] / "assets/bridge/hermes_bridge.py"
    spec = importlib.util.spec_from_file_location("bridge_platform_test_module", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BridgePlatformTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bridge-platform-test-")
        self.home = Path(self.temp.name)
        self.bridge = load_bridge(self.home)

    def tearDown(self):
        self.temp.cleanup()

    def test_restart_commands_cover_systemd_launchd_and_windows_tasks(self):
        linux = self.bridge._managed_service_restart_command("bridge")
        self.assertEqual(
            linux, ["systemctl", "--user", "restart", "hermes-bridge"]
        )

        with mock.patch.object(self.bridge.sys, "platform", "darwin"), mock.patch.object(
            self.bridge.os, "getuid", return_value=501
        ):
            mac = self.bridge._managed_service_restart_command("dashboard")
        self.assertEqual(
            mac,
            [
                "launchctl",
                "kickstart",
                "-k",
                "gui/501/dev.xpetalab.hermes-console.dashboard",
            ],
        )

        with mock.patch.object(self.bridge.os, "name", "nt"):
            windows = self.bridge._managed_service_restart_command("bridge", 0.5)
        self.assertEqual(
            windows,
            [
                "schtasks.exe",
                "/Run",
                "/TN",
                "HermesConsole-Restart-MobileBridge",
            ],
        )

    def test_non_termux_environment_does_not_inject_android_paths(self):
        with mock.patch.dict(
            self.bridge.os.environ,
            {"PREFIX": "", "TERMUX_VERSION": ""},
            clear=False,
        ):
            env = self.bridge._hermes_env()
        self.assertNotIn("LD_PRELOAD", env)
        self.assertNotIn("LD_LIBRARY_PATH", env)
        self.assertNotIn("/data/data/com.termux", env.get("TMPDIR", ""))

    def test_service_names_are_closed_allowlist(self):
        self.assertIsNone(
            self.bridge._managed_service_restart_command("../../untrusted")
        )

    def test_portable_helper_must_be_a_regular_file_below_hermes_home(self):
        helper = self.home / "console-services" / "service-manager.sh"
        helper.parent.mkdir(parents=True)
        helper.write_text("#!/bin/sh\n", encoding="utf-8")
        with mock.patch.dict(
            self.bridge.os.environ,
            {"BRIDGE_SERVICE_HELPER": str(helper)},
        ):
            command = self.bridge._managed_service_restart_command("bridge")
        self.assertEqual(command, [str(helper), "restart", "bridge"])

        linked_helper = helper.with_name("linked-service-manager.sh")
        linked_helper.symlink_to(helper)
        with mock.patch.dict(
            self.bridge.os.environ,
            {"BRIDGE_SERVICE_HELPER": str(linked_helper)},
        ):
            command = self.bridge._managed_service_restart_command("bridge")
        self.assertEqual(
            command, ["systemctl", "--user", "restart", "hermes-bridge"]
        )


if __name__ == "__main__":
    unittest.main()
