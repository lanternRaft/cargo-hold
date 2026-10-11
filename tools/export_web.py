#!/usr/bin/env python3
"""Release export, pack audit, versioned assets and precompressed HTTP variants."""
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ['index.js', 'index.pck', 'index.wasm', 'index.side.wasm',
            'libbox3d_godot.web.template_release.wasm32.wasm', 'motion.js']
ENGINE_FILES = {'index.js', 'index.wasm', 'index.side.wasm',
                'index.audio.worklet.js', 'index.audio.position.worklet.js'}

def compress(path):
    data = path.read_bytes()
    variants = {'raw': len(data)}
    if path.suffix in {'.wasm', '.pck', '.js', '.html'}:
        gz = gzip.compress(data, compresslevel=9, mtime=0)
        br = subprocess.check_output(['brotli', '-q', '11', '-c', str(path)])
        assert gzip.decompress(gz) == data
        assert subprocess.check_output(['brotli', '-d', '-c'], input=br) == data
        for extension, content in (('gz', gz), ('br', br)):
            Path(str(path) + '.' + extension).write_bytes(content)
            variants[extension] = len(content)
    return variants

def package_group(files, output):
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.name.encode() + b'\0' + path.read_bytes())
    version = digest.hexdigest()[:20]
    relative = f'assets/{version}'
    destination = output / relative
    if not destination.exists():
        with tempfile.TemporaryDirectory(prefix='assets-', dir=output) as directory:
            temporary = Path(directory) / version
            temporary.mkdir()
            sizes = {}
            for path in files:
                target = temporary / path.name
                shutil.copy2(path, target)
                sizes[path.name] = compress(target)
            (temporary / 'sizes.json').write_text(json.dumps(sizes, indent=2) + '\n')
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary.rename(destination)
    sizes = json.loads((destination / 'sizes.json').read_text())
    return relative, sizes

def package(stage, output):
    """Version engine and content separately; retain assets needed by open tabs."""
    output.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in stage.iterdir() if p.is_file() and p.name != 'index.html')
    engine_base, engine_sizes = package_group([p for p in files if p.name in ENGINE_FILES], output)
    relative, sizes = package_group([p for p in files if p.name not in ENGINE_FILES], output)
    sizes = {**engine_sizes, **sizes}
    html = ((stage / 'index.html').read_text().replace('$MAGICBOX_ASSET_BASE', relative)
            .replace('$MAGICBOX_ENGINE_BASE', '/' + engine_base))
    assert '$GODOT_' not in html and '$MAGICBOX_' not in html
    with tempfile.TemporaryDirectory(prefix='html-', dir=output) as directory:
        entry = Path(directory) / 'index.html'
        entry.write_text(html)
        compress(entry)
        for extension in ('.br', '.gz', ''):
            Path(str(entry) + extension).replace(output / ('index.html' + extension))
    (output / '_headers').write_text(
        '/*\n  Cross-Origin-Opener-Policy: same-origin\n'
        '  Cross-Origin-Embedder-Policy: require-corp\n'
        '  Cross-Origin-Resource-Policy: same-origin\n'
        '  Cache-Control: no-cache\n/assets/*\n'
        '  Cache-Control: public, max-age=31536000, immutable\n')
    totals = {encoding: sum(s.get(encoding, s['raw']) for s in sizes.values())
              for encoding in ('raw', 'gz', 'br')}
    report = {'asset_base': relative, 'engine_base': engine_base, 'bytes': totals, 'files': sizes}
    (output / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
    return report

def main():
    (ROOT / 'build').mkdir(exist_ok=True)
    (ROOT / 'build/.gdignore').touch()
    if not shutil.which('brotli'):
        raise SystemExit('Brotli CLI is required; see README setup.')
    if not (ROOT / 'build/templates/web_release.zip').is_file():
        raise SystemExit('Build the custom template first: python3 tools/build_web_template.py')
    metadata_path = ROOT / 'build/templates/web_release.json'
    if not metadata_path.is_file():
        raise SystemExit('Missing template provenance; rerun python3 tools/build_web_template.py')
    metadata = json.loads(metadata_path.read_text())
    if metadata['profile_sha256'] != hashlib.sha256((ROOT / 'tools/web_build_profile.gdbuild').read_bytes()).hexdigest():
        raise SystemExit('Build profile changed; rerun python3 tools/build_web_template.py')
    if metadata['template_sha256'] != hashlib.sha256((ROOT / 'build/templates/web_release.zip').read_bytes()).hexdigest():
        raise SystemExit('Template does not match its provenance; rebuild it')
    build = ROOT / 'build'
    with tempfile.TemporaryDirectory(prefix='web-export-', dir=build) as directory:
        stage = Path(directory)
        subprocess.run(['godot', '--headless', '--path', str(ROOT), '--export-release',
                        'Web Release', str(stage / 'index.html')], check=True)
        shutil.copy2(ROOT / 'web/motion.js', stage / 'motion.js')
        for name in REQUIRED:
            assert (stage / name).is_file(), f'Missing release asset: {name}'
        subprocess.run(['python3', str(ROOT / 'tools/audit_pck.py'), str(stage / 'index.pck')], check=True)
        report = package(stage, build / 'web')
        print(json.dumps(report, indent=2))

if __name__ == '__main__':
    main()
