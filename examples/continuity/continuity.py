"""A small, local example of versioned state and verifiable task handoffs.

This example uses SQLite transactions instead of the private system's Git
transaction adapter. It needs no model, account, network, or existing memory.
"""
from __future__ import annotations

from dataclasses import dataclass
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import secrets
import sqlite3


class Conflict(ValueError):
    """The proposed handoff no longer matches the recorded task state."""


def encode(value: dict) -> str:
    if not isinstance(value, dict):
        raise ValueError("State must be a JSON object")
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


@dataclass(frozen=True)
class Turn:
    token: str
    task: str
    revision: int
    state_hash: str


class Store:
    def __init__(self, path: Path):
        self.path = Path(path)
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS tasks (
                    task TEXT PRIMARY KEY, revision INTEGER NOT NULL,
                    state TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS turns (
                    token TEXT PRIMARY KEY, task TEXT NOT NULL,
                    revision INTEGER NOT NULL, state_hash TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS receipts (
                    token TEXT PRIMARY KEY, task TEXT NOT NULL,
                    revision INTEGER NOT NULL, state_hash TEXT NOT NULL,
                    summary TEXT NOT NULL
                );
            """)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def create(self, task: str, state: dict):
        if not isinstance(task, str) or not task.strip():
            raise ValueError("Task ID must be nonempty")
        with self.connect() as db:
            db.execute("INSERT INTO tasks VALUES (?, 0, ?)", (task, encode(state)))

    def begin(self, task: str) -> Turn:
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM tasks WHERE task=?", (task,)).fetchone()
            if row is None:
                raise KeyError(task)
            turn = Turn(secrets.token_hex(16), task, row["revision"], digest(row["state"]))
            db.execute("INSERT INTO turns VALUES (?, ?, ?, ?)",
                       (turn.token, turn.task, turn.revision, turn.state_hash))
            return turn

    def complete(self, turn: Turn, state: dict, summary: str) -> dict:
        """Commit state and its handoff receipt together, or commit neither.

        An exact retry returns its original receipt. Changing the payload of a
        completed turn or submitting a stale turn is a conflict, not a new write.
        """
        if not isinstance(summary, str) or not summary.strip() or len(summary) > 500:
            raise ValueError("A handoff summary must contain 1-500 characters")
        payload = encode(state)
        state_hash = digest(payload)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            saved = db.execute("SELECT * FROM turns WHERE token=?", (turn.token,)).fetchone()
            if saved is None or (saved["task"], saved["revision"], saved["state_hash"]) != (
                turn.task, turn.revision, turn.state_hash
            ):
                raise Conflict("Unknown turn or mismatched task/version")
            previous = db.execute("SELECT * FROM receipts WHERE token=?", (turn.token,)).fetchone()
            if previous:
                if previous["state_hash"] != state_hash or previous["summary"] != summary:
                    raise Conflict("A completed turn cannot be reused for different content")
                return dict(previous)
            current = db.execute("SELECT * FROM tasks WHERE task=?", (turn.task,)).fetchone()
            if current is None or current["revision"] != turn.revision or digest(current["state"]) != turn.state_hash:
                raise Conflict("Task changed since this turn began; reload before proposing an update")
            revision = turn.revision + 1
            db.execute("UPDATE tasks SET revision=?, state=? WHERE task=?",
                       (revision, payload, turn.task))
            db.execute("INSERT INTO receipts VALUES (?, ?, ?, ?, ?)",
                       (turn.token, turn.task, revision, state_hash, summary))
            return dict(db.execute("SELECT * FROM receipts WHERE token=?", (turn.token,)).fetchone())

    def resume(self, task: str) -> dict:
        """Read one coherent snapshot; do not reconstruct state from chat logs."""
        with self.connect() as db:
            db.execute("BEGIN")
            row = db.execute("SELECT * FROM tasks WHERE task=?", (task,)).fetchone()
            if row is None:
                raise KeyError(task)
            receipt = db.execute(
                "SELECT * FROM receipts WHERE task=? AND revision=?",
                (task, row["revision"]),
            ).fetchone()
            if row["revision"] and (receipt is None or receipt["state_hash"] != digest(row["state"])):
                raise Conflict("Current state has no matching handoff receipt")
            return {"task": task, "revision": row["revision"],
                    "state": json.loads(row["state"]),
                    "summary": receipt["summary"] if receipt else "Task created"}
