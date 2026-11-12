"""Run after rex config reload. Requires the Rex app and Remote Control."""

import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
from tempfile import TemporaryDirectory
import time


rex = (
    shutil.which("rex")
    or "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
)
database = Path.home() / "Library/Application Support/rex/session-roots.sqlite3"
sessions = []


def run(*args, check=True):
    return subprocess.run([rex, *args], capture_output=True, text=True, check=check)


def call(*args):
    output = run(*args).stdout.strip()
    return json.loads(output) if output else None


def saved_root(session):
    with sqlite3.connect(database) as connection:
        row = connection.execute(
            "SELECT root FROM session_roots WHERE session_id = ?", (session,)
        ).fetchone()
        return row[0] if row else None


def action(session, name, **args):
    view = call("session", "inspect", session, "--json")
    block = next(
        w["focused_block_id"]
        for w in view["windows"]
        if w["window_id"] == view["active_window_id"]
    )
    request = {
        "session_id": session,
        "block_id": block,
        "action": name,
        "args": args,
        "origin": "key",
    }
    return run("api", "call", "client.action", json.dumps(request), check=False)


def check_new_tab(response, session, directory):
    assert response.returncode == 0, response.stderr
    envelope = json.loads(response.stdout)
    window = envelope["result"]
    assert envelope["client_actions"] == [
        {
            "action": "session.select",
            "args": {"session_id": session, "window_id": window["window_id"]},
        }
    ]
    wait_for_directory(session, window["block_ids"][0], directory)


def wait_for_directory(session, block, expected):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        process = call("block", "call", "-s", session, "-b", block, "process")
        if (process.get("foreground") or {}).get("cwd") == str(expected):
            return
        time.sleep(0.1)
    raise AssertionError(f"Terminal did not start in {expected}: {process}")


def applescript(code):
    return subprocess.check_output(
        ["/usr/bin/osascript", "-e", 'tell application "Rex Beta" to ' + code],
        text=True,
        timeout=20,
    ).strip()


assert (
    subprocess.check_output(
        ["/usr/bin/sqlite3", ":memory:", "SELECT 1 WHERE 1 NOT IN ();"], text=True
    ).strip()
    == "1"
)
apps = [
    c
    for c in call("client", "ls", "--json")["clients"]
    if c.get("info", {}).get("kind") == "app"
    and c.get("connection_state") == "connected"
]
assert len(apps) == 1, "This check needs exactly one connected Rex app"
app = apps[0]["client_id"]
original = applescript("get id of current session").rsplit("/", 1)[-1]
original_window = call("session", "inspect", original, "--json")["active_window_id"]

with TemporaryDirectory(prefix="rex-root-test-") as temporary:
    base = Path(temporary).resolve()
    project = base / "project 'quoted'; DROP TABLE session_roots; -- $(literal)"
    project.mkdir()
    other = base / "other"
    other.mkdir()
    try:
        for directory in (project, other):
            created = call(
                "new",
                "rex-root-check",
                "--json",
                "--shell=none",
                "-c",
                str(directory),
                "--",
                "/bin/sleep",
                "120",
            )
            session = created["session_id"]
            sessions.append(session)
            wait_for_directory(
                session, created["initial_windows"][0]["block_ids"][0], directory
            )

        first, second = sessions
        fallback = action(second, "new_session_tab")
        assert fallback.returncode == 0, fallback.stderr
        assert json.loads(fallback.stdout)["client_actions"] == [
            {"action": "client.tab.new"}
        ]

        for session, directory in zip(sessions, (project, other)):
            result = action(session, "set_session_root")
            assert result.returncode == 0, result.stderr
            assert saved_root(session) == str(directory)
            check_new_tab(action(session, "new_session_tab"), session, directory)

        run("session", "rename", first, "rex-root-renamed-check")
        check_new_tab(action(first, "new_session_tab"), first, project)
        invalid = action(first, "set_session_root", directory=str(base / "missing"))
        assert invalid.returncode != 0
        assert saved_root(first) == str(project)

        before = {s["session_id"] for s in call("ls", "--json")["sessions"]}
        invalid = action(first, "new_folder_session", directory=str(base / "missing"))
        assert invalid.returncode != 0
        assert {s["session_id"] for s in call("ls", "--json")["sessions"]} == before

        chosen = base / "chosen folder 'quoted'"
        chosen.mkdir()
        response = action(first, "new_folder_session", directory=str(chosen))
        assert response.returncode == 0, response.stderr
        envelope = json.loads(response.stdout)
        created = envelope["result"]
        created_id = created["session_id"]
        sessions.append(created_id)
        assert call("session", "inspect", created_id, "--json")["label"] == chosen.name
        assert saved_root(created_id) == str(chosen)
        assert envelope["client_actions"] == [
            {
                "action": "session.select",
                "args": {
                    "session_id": created_id,
                    "window_id": created["initial_windows"][0]["window_id"],
                },
            }
        ]
        wait_for_directory(
            created_id, created["initial_windows"][0]["block_ids"][0], chosen
        )
        check_new_tab(action(created_id, "new_session_tab"), created_id, chosen)

        first_window = call("session", "inspect", first, "--json")["windows"][0][
            "window_id"
        ]
        run(
            "-C",
            app,
            "do",
            "session.select",
            "--args",
            json.dumps({"session_id": first, "window_id": first_window}),
        )
        before = {s["session_id"] for s in call("ls", "--json")["sessions"]}
        applescript('perform "new_folder_session"')
        created = [
            s
            for s in call("ls", "--json")["sessions"]
            if s["session_id"] not in before
            and saved_root(s["session_id"]) == str(project)
        ]
        assert len(created) == 1, "Folder command did not create the expected session"
        created_id = created[0]["session_id"]
        sessions.append(created_id)
        assert created[0]["label"] == project.name
        assert applescript("get id of current session").rsplit("/", 1)[-1] == created_id

        for index in range(8):
            target = base / f"selection-{index}"
            target.mkdir()
            run(
                "-C",
                app,
                "do",
                "session.select",
                "--args",
                json.dumps({"session_id": first, "window_id": first_window}),
            )
            result = action(first, "set_session_root", directory=str(target))
            assert result.returncode == 0, result.stderr
            applescript('perform "new_session_tab"')
            # Save the app's selected terminal directory within our test session only.
            applescript('perform "set_session_root"')
            assert saved_root(first) == str(target), "App did not select the new tab"
            assert saved_root(second) == str(other), (
                "Changing one root affected another session"
            )

        restored = action(first, "set_session_root", directory=str(project))
        assert restored.returncode == 0, restored.stderr
        before = call("session", "inspect", first, "--json")
        project.rename(base / "moved-project")
        assert action(first, "new_session_tab").returncode != 0
        after = call("session", "inspect", first, "--json")
        assert len(before["windows"]) == len(after["windows"])
    finally:
        try:
            run(
                "-C",
                app,
                "do",
                "session.select",
                "--args",
                json.dumps({"session_id": original, "window_id": original_window}),
            )
        finally:
            for session in sessions:
                run("kill", session)
            deadline = time.monotonic() + 5
            while (
                any(saved_root(session) is not None for session in sessions)
                and time.monotonic() < deadline
            ):
                time.sleep(0.05)
            assert all(saved_root(session) is None for session in sessions), (
                "Closed-session rows remain"
            )

print(
    "Passed: folder sessions, SQLite roots, validation, isolation, rename, 8 app selections, and automatic cleanup"
)
