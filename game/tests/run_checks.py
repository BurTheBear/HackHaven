"""Run ECHO checks in a temporary copy with a separate Godot user-data folder.
Usage: python3 game/tests/run_checks.py /path/to/godot
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

game = Path(__file__).resolve().parents[1]
godot = sys.argv[1] if len(sys.argv) > 1 else shutil.which('godot')
if not godot:
    raise SystemExit('Pass your Godot executable as the first argument.')
with tempfile.TemporaryDirectory(prefix='echo-checks-') as directory:
    project = Path(directory) / 'game'
    shutil.copytree(game, project, ignore=shutil.ignore_patterns('.godot', '*.tmp', '__pycache__'))
    config = project / 'project.godot'
    config.write_text(config.read_text().replace('config/name="ECHO"', 'config/name="ECHO Codex Verification"'))
    subprocess.run([godot, '--headless', '--editor', '--path', str(project), '--import'], check=True)
    for script in ('gameplay_checks.gd', 'scene_smoke.gd'):
        subprocess.run([godot, '--headless', '--path', str(project), '--script', 'res://tests/' + script], check=True)
