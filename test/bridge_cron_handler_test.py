import asyncio
import importlib.util
import json
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
    def __init__(self, job_id, profile=None):
        self.match_info = {"job_id": job_id}
        self.query = {} if profile is None else {"profile": profile}
        self.headers = {"Authorization": "Bearer test-token"}


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
    os.environ["BRIDGE_SCOPES"] = "read,cron"
    os.environ["BRIDGE_READ_ONLY"] = "false"
    path = Path(__file__).resolve().parents[1] / "assets/bridge/hermes_bridge.py"
    spec = importlib.util.spec_from_file_location("bridge_cron_test_module", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module._audit = lambda *_args, **_kwargs: None
    return module


class CronRemoveContractTest(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="bridge-cron-test-")
        cls.home = Path(cls.temp.name)
        cls.bridge = load_bridge(cls.home)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        for path in sorted(self.home.rglob("*"), reverse=True):
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                path.rmdir()

    def jobs_path(self, profile=None):
        base = self.home if profile is None else self.home / "profiles" / profile
        return base / "cron" / "jobs.json"

    def write_jobs(self, ids, profile=None):
        path = self.jobs_path(profile)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"jobs": [{"id": job_id} for job_id in ids]}),
            encoding="utf-8",
        )

    def install_run(self, *, remove=True, rc=0, log="Removed job"):
        calls = []

        async def fake_run(command, **_kwargs):
            calls.append(command)
            profile = None
            if "--profile" in command:
                profile = command[command.index("--profile") + 1]
            job_id = command[-1]
            if remove:
                path = self.jobs_path(profile)
                data = json.loads(path.read_text(encoding="utf-8"))
                data["jobs"] = [
                    job for job in data["jobs"] if job.get("id") != job_id
                ]
                path.write_text(json.dumps(data), encoding="utf-8")
            return rc, log

        self.bridge._run = fake_run
        return calls

    async def test_default_profile_uses_default_store(self):
        self.write_jobs(["job-default"])
        calls = self.install_run()

        response = await self.bridge.cron_remove(FakeRequest("job-default"))

        self.assertEqual(response.status, 200)
        self.assertTrue(response.data["ok"])
        self.assertNotIn("--profile", calls[0])
        self.assertFalse(self.bridge._cron_job_present("job-default", None))

    async def test_named_profile_uses_scoped_cli_and_store_only(self):
        self.write_jobs(["job-shared"])
        self.write_jobs(["job-shared"], profile="coder")
        calls = self.install_run()

        response = await self.bridge.cron_remove(
            FakeRequest("job-shared", profile="coder")
        )

        self.assertEqual(response.status, 200)
        self.assertEqual(calls[0][-5:-3], ["--profile", "coder"])
        self.assertTrue(self.bridge._cron_job_present("job-shared", None))
        self.assertFalse(self.bridge._cron_job_present("job-shared", "coder"))

    async def test_named_profile_absence_does_not_consult_default_store(self):
        self.write_jobs(["job-shared"])
        self.write_jobs([], profile="coder")
        calls = self.install_run(remove=False, rc=1, log="not found")

        response = await self.bridge.cron_remove(
            FakeRequest("job-shared", profile="coder")
        )

        self.assertEqual(response.status, 200)
        self.assertTrue(response.data["ok"])
        self.assertTrue(response.data["already_absent"])
        self.assertEqual(calls[0][-5:-3], ["--profile", "coder"])
        self.assertTrue(self.bridge._cron_job_present("job-shared", None))

    async def test_absent_poststate_without_confirmation_log_is_rejected(self):
        self.write_jobs(["job-scoped"], profile="coder")
        self.install_run(remove=True, rc=1, log="unexpected CLI response")

        response = await self.bridge.cron_remove(
            FakeRequest("job-scoped", profile="coder")
        )

        self.assertEqual(response.status, 502)
        self.assertEqual(response.data["error"], "cron_remove_failed")
        self.assertFalse(self.bridge._cron_job_present("job-scoped", "coder"))

    async def test_ambiguous_success_is_rejected_if_job_remains(self):
        self.write_jobs(["job-still-there"], profile="coder")
        self.install_run(remove=False, rc=0, log="Removed job")

        response = await self.bridge.cron_remove(
            FakeRequest("job-still-there", profile="coder")
        )

        self.assertEqual(response.status, 502)
        self.assertEqual(response.data["error"], "cron_remove_failed")

    async def test_unreadable_scoped_store_never_trusts_rc_or_log(self):
        (self.home / "profiles" / "coder").mkdir(parents=True)
        calls = []

        async def fake_run(command, **_kwargs):
            calls.append(command)
            return 0, "Removed job"

        self.bridge._run = fake_run

        response = await self.bridge.cron_remove(
            FakeRequest("job-unknown", profile="coder")
        )

        self.assertEqual(response.status, 502)
        self.assertEqual(len(calls), 1)

    async def test_invalid_or_missing_named_profile_is_rejected_before_run(self):
        calls = []

        async def fake_run(command, **_kwargs):
            calls.append(command)
            return 0, "not found"

        self.bridge._run = fake_run

        for profile in ("../coder", "Coder", "missing"):
            response = await self.bridge.cron_remove(
                FakeRequest("job-1", profile=profile)
            )
            self.assertEqual(response.status, 400)
            self.assertEqual(response.data["error"], "bad_profile")
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
