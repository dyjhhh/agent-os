from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest

from continuity import Conflict, Store


class ContinuityTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "state.sqlite"
        self.store = Store(self.path)
        self.store.create("task", {"phase": "draft"})

    def test_new_session_resumes_the_committed_state_and_summary(self):
        turn = self.store.begin("task")
        self.store.complete(turn, {"phase": "review"}, "Review next")
        self.assertEqual(Store(self.path).resume("task"), {
            "task": "task", "revision": 1, "state": {"phase": "review"}, "summary": "Review next"})

    def test_stale_worker_cannot_overwrite_newer_state(self):
        one, two = self.store.begin("task"), self.store.begin("task")
        self.store.complete(one, {"phase": "review"}, "Review next")
        with self.assertRaises(Conflict):
            self.store.complete(two, {"phase": "published"}, "Wrong update")
        self.assertEqual(self.store.resume("task")["state"], {"phase": "review"})

    def test_simultaneous_writers_have_one_winner(self):
        turns = [self.store.begin("task"), self.store.begin("task")]
        def finish(turn):
            try:
                self.store.complete(turn, {"phase": "review"}, "Review next")
                return "committed"
            except Conflict:
                return "conflict"
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertCountEqual(list(pool.map(finish, turns)), ["committed", "conflict"])
        self.assertEqual(self.store.resume("task")["revision"], 1)

    def test_exact_retry_is_idempotent_even_after_later_progress(self):
        turn = self.store.begin("task")
        receipt = self.store.complete(turn, {"phase": "review"}, "Review next")
        self.store.complete(self.store.begin("task"), {"phase": "ready"}, "Ready locally")
        self.assertEqual(self.store.complete(turn, {"phase": "review"}, "Review next"), receipt)
        self.assertEqual(self.store.resume("task")["revision"], 2)

    def test_completed_turn_cannot_change_content(self):
        turn = self.store.begin("task")
        self.store.complete(turn, {"phase": "review"}, "Review next")
        for state, summary in [({"phase": "published"}, "Review next"), ({"phase": "review"}, "Changed")]:
            with self.assertRaises(Conflict):
                self.store.complete(turn, state, summary)

    def test_receipt_failure_rolls_back_the_state_write(self):
        turn = self.store.begin("task")
        with self.store.connect() as db:
            db.execute("CREATE TRIGGER reject_receipt BEFORE INSERT ON receipts "
                       "BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END")
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.complete(turn, {"phase": "review"}, "Review next")
        self.assertEqual(self.store.resume("task")["revision"], 0)

    def test_mismatched_task_token_or_version_is_rejected(self):
        turn = self.store.begin("task")
        for invalid in [replace(turn, task="other"), replace(turn, token="unknown"),
                        replace(turn, revision=99), replace(turn, state_hash="wrong")]:
            with self.assertRaises(Conflict):
                self.store.complete(invalid, {"phase": "review"}, "Review next")

    def test_unrecorded_state_change_is_detected(self):
        turn = self.store.begin("task")
        with self.store.connect() as db:
            db.execute("UPDATE tasks SET state=? WHERE task='task'", ('{"phase":"tampered"}',))
        with self.assertRaises(Conflict):
            self.store.complete(turn, {"phase": "review"}, "Review next")

    def test_resume_rejects_a_receipt_that_does_not_match_the_state(self):
        self.store.complete(self.store.begin("task"), {"phase": "review"}, "Review next")
        with self.store.connect() as db:
            db.execute("UPDATE receipts SET state_hash='wrong'")
        with self.assertRaises(Conflict):
            self.store.resume("task")

    def test_missing_task_and_invalid_inputs_do_not_commit(self):
        with self.assertRaises(KeyError):
            self.store.begin("missing")
        turn = self.store.begin("task")
        for state, summary in [([], "Bad state"), ({"value": float('nan')}, "Bad JSON"), ({}, " ")]:
            with self.assertRaises(ValueError):
                self.store.complete(turn, state, summary)
        self.assertEqual(self.store.resume("task")["revision"], 0)


if __name__ == "__main__":
    unittest.main()
