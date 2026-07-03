#!/usr/bin/env python
"""
Extremely simple wrapper to run webpack.

Don't add anything onto this, please. It's meant to a be a super-simple way
of exposing the `webpack` build to those who `pip install openedx-platform`.
"""
import subprocess
import sys
from pathlib import Path


def main():
    this_script = Path(__file__)
    repo_root = Path(__file__).parent.parent.parent
    if not (repo_root / "package.json").is_file():
        raise SystemExit(f"{this_script.name} could not find root of openedx-platform repository")
    # Always `npm ci`: the build toolchain (webpack et al.) lives in devDependencies, which npm ci installs by default.
    for command in (["npm", "ci"], ["npm", "run", "webpack"]):
        print(f"{this_script.name}: running {' '.join(command)} in {repo_root}", flush=True)
        result = subprocess.run(command, cwd=repo_root, check=False)
        if result.returncode != 0:
            raise SystemExit(result.returncode)


if __name__ == "__main__":
    sys.exit(main())
