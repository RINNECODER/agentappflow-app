from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


def git_executable() -> str:
    configured = os.environ.get("AGENTAPPFLOW_TEST_GIT", "").strip()
    candidates = [
        configured or None,
        "/opt/homebrew/bin/git",
        shutil.which("git"),
    ]
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate)
        if path.is_absolute() and not path.exists():
            continue
        return str(path)
    return "git"


def init_repo(path: Path) -> None:
    subprocess.run(
        [git_executable(), "init"],
        cwd=path,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
