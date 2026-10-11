#!/usr/bin/env python3
"""Build the pinned, threaded GDExtension template without modifying addons."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GODOT_COMMIT = "ed1daf0bf001b61586d9930840f2f1394092c079"

def main():
    (ROOT / 'build').mkdir(exist_ok=True)
    (ROOT / 'build/.gdignore').touch()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'build/toolchain/godot')
    parser.add_argument('--emsdk', type=Path, default=ROOT / 'build/toolchain/emsdk')
    parser.add_argument('--scons', type=Path, default=ROOT / 'build/toolchain/python/bin/scons')
    parser.add_argument('--jobs', type=int, default=6)
    args = parser.parse_args()
    source, emsdk, scons = args.source.resolve(), args.emsdk.resolve(), args.scons.resolve()
    for path in (source / 'SConstruct', emsdk / 'emsdk_env.sh', scons):
        if not path.exists():
            parser.error(f'Missing {path}; see README toolchain setup')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    if commit != GODOT_COMMIT:
        parser.error(f'Expected Godot 4.7.2 commit {GODOT_COMMIT}, found {commit}')
    compiler = subprocess.check_output(
        ['bash', '-c', 'source "$1/emsdk_env.sh" >/dev/null 2>&1; emcc --version',
         'compiler-version', str(emsdk)], text=True)
    if '4.0.11' not in compiler.splitlines()[0]:
        parser.error('Activate Emscripten 4.0.11 before building this template')
    command = [str(scons), f'-j{args.jobs}', 'platform=web', 'target=template_release',
               'arch=wasm32', 'threads=yes', 'dlink_enabled=yes', 'javascript_eval=yes',
               'production=yes', 'optimize=size', 'lto=full', 'debug_symbols=no',
               'use_closure_compiler=no', f'build_profile={ROOT / "tools/web_build_profile.gdbuild"}']
    # Positional shell arguments preserve paths safely; the SDK stays project-local.
    subprocess.run(['bash', '-c', 'source "$1/emsdk_env.sh" >/dev/null 2>&1; shift; exec "$@"',
                    'web-template', str(emsdk), *command], cwd=source, check=True)
    template = source / 'bin/godot.web.template_release.wasm32.dlink.zip'
    if not template.is_file():
        raise RuntimeError(f'Missing built template: {template}')
    destination = ROOT / 'build/templates/web_release.zip'
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(template, destination)
    (destination.parent / 'web_release.json').write_text(json.dumps({
        'godot_commit': commit, 'emscripten': '4.0.11',
        'profile_sha256': hashlib.sha256((ROOT / 'tools/web_build_profile.gdbuild').read_bytes()).hexdigest(),
        'template_sha256': hashlib.sha256(destination.read_bytes()).hexdigest(),
        'scons_options': command[2:],
    }, indent=2) + '\n')
    print(f'Custom web template: {destination}')

if __name__ == '__main__':
    main()
