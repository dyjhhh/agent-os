"""Run a synthetic handoff, an exact retry, and a competing stale write."""
from dataclasses import replace
from pathlib import Path
from tempfile import TemporaryDirectory

from continuity import Conflict, Store


def main():
    with TemporaryDirectory(prefix="continuity-demo-") as directory:
        path = Path(directory) / "state.sqlite"
        first = Store(path)
        first.create("release-notes", {"phase": "draft", "reviewed": False})
        turn = first.begin("release-notes")
        stale_turn = first.begin("release-notes")
        state = {"phase": "review", "reviewed": False}
        receipt = first.complete(turn, state, "Draft ready; editorial review is next.")
        print("PASS: state and handoff receipt committed together")

        later = Store(path)  # New session, same persisted state, no transcript.
        resumed = later.resume("release-notes")
        assert resumed["revision"] == 1 and resumed["state"] == state
        print("PASS: a new session resumes revision 1 and its next step")
        assert later.complete(turn, state, receipt["summary"]) == receipt
        print("PASS: an exact retry returns the same receipt without another revision")

        for label, candidate in [("stale competing write", stale_turn),
                                 ("turn reused for another task", replace(turn, task="other-task"))]:
            try:
                later.complete(candidate, {"phase": "published"}, "Premature completion")
            except Conflict:
                print(f"BLOCKED: {label}")
            else:
                raise AssertionError(f"Expected conflict: {label}")
        assert later.resume("release-notes") == resumed
        print("PASS: rejected updates left the saved state unchanged")
    print("Temporary demo state removed. No external actions occurred.")


if __name__ == "__main__":
    main()
