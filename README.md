# Cargo Hold

Web toy inspired by u/nathan82 post "Rigid body sim on mobile with Box3D" onto r/Simulated on 2026-10-09

![screenshot](cargo_hold_screenshot.jpg)

## Details
A Godot web toy with 100 small space cargo spheres, cubes, capsules, and cylinders
inside an enclosed 3D box. Tilt and shake in all three axes, or grab and throw
shapes. Without sensors, drag empty space to tilt; mouse works too. Reload the
page to restore the seeded contents. A one-time overlay offers **Enable motion**
and **Continue with touch**. Desktop browsers suggest opening on a phone for
tilt & shake, with **Play with mouse** available here.

## Setup and run

Dependencies: Godot **4.7.2 stable**, Compatibility renderer;
[box3d-godot 0.5.0](https://github.com/Stink-O/box3d-godot) in `addons/box3d/`;
GDUnit4 **6.2.0** in `addons/gdUnit4/`.

## Tests

```sh
godot --headless --path . --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
godot --path . --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
node --test web/*.test.cjs
python3 tools/test_web_delivery.py
```

The small dependency compatibility check remains available:

```sh
godot --headless --path . res://scenes/compatibility.tscn
```


## Web export and preview

Keep the matching official Godot 4.7.2 templates installed, including
`web_dlink_debug.zip` (Godot validates debug availability even for a release
export). Release exports now use the smaller custom template at
`build/templates/web_release.zip`. The selected addon supplies only a threaded release web
library. The checked-in **Web Release** preset enables threads and extensions;
debug/single-threaded exports cannot load this supplied addon. The preset is
intentionally not marked Runnable: Godot's **Run in Browser** always makes a debug
export (`tmp_js_export.html`), which this addon cannot use. Use the commands below
for browser previews, including Chrome.

One-time toolchain setup (Python 3.11+, Git and the Brotli CLI are required;
macOS can install Brotli with `brew install brotli`):

```sh
mkdir -p build
touch build/.gdignore
git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot.git build/toolchain/godot
git clone --depth 1 https://github.com/emscripten-core/emsdk.git build/toolchain/emsdk
python3 -m venv build/toolchain/python
build/toolchain/python/bin/pip install scons==4.9.1
python3 build/toolchain/emsdk/emsdk.py install 4.0.11
python3 build/toolchain/emsdk/emsdk.py activate 4.0.11
python3 tools/build_web_template.py
```

The builder checks the exact Godot 4.7.2 source commit and Emscripten version.
`tools/web_build_profile.gdbuild` removes advanced GUI, advanced text shaping
(retaining the fallback text server), unused media codecs, navigation, XR,
multiplayer/network transports, model importers, CSG, GridMap and unused image/
texture codecs. Both built-in 3D solvers and the 2D solver are omitted; shared
physics APIs remain available to extensions. Box3D's vendor binary is unchanged.
Keep 3D, Compatibility rendering, GDScript, JavaScript evaluation, threads and
dynamic linking. The build uses `optimize=size` and full LTO; `size_extra` is
avoided to preserve runtime performance. No automatic class stripping is used
because it can miss dependencies inside GDExtensions. GDUnit4 remains installed
and the normal native Godot/editor is unchanged.

Rebuild the template after changing that profile; ordinary app edits need only:

```sh
python3 tools/export_web.py
python3 tools/serve.py
```

Open **http://localhost:8061** as a top-level tab. Localhost is a browser secure
context; remote/device previews require trusted HTTPS. The preview server sets
real COOP/COEP response headers. For a device reachable on your LAN, supply your
own trusted certificate and its key (neither belongs in this repository):

```sh
python3 tools/serve.py --cert /absolute/path/certificate.pem --key /absolute/path/key.pem
```

Use the certificate's valid hostname on the phone. This HTTPS/device path has not
been exercised in this session. The plain preview binds only to localhost; HTTPS
binds all interfaces. Stop either server with Ctrl-C. The default port is 8061 to keep this release
preview separate from Godot's temporary editor server on 8060. Use `--port` to
choose another port.

If Chrome reports `motion.js` 404, `GOT.func` import errors or keeps waiting on
`wasm-instantiate`, check the URL. A `tmp_js_export.html` URL is the editor's debug
preview. Open the release URL above after running both commands; hard refresh
with Cmd-Shift-R on macOS (Ctrl-Shift-R elsewhere). The helper copies `motion.js`
and exports the engine JS, wasm, side module and Box3D library as one matching set.
Do not mix files from temporary, debug, single-threaded or older exports.

`tools/export_web.py` exports into a temporary staging directory, audits the pack,
copies the source-controlled motion companion, and packages versioned assets
under `build/web/assets/<content-hash>/`. Engine and app content have separate
hashes so app edits reuse the cached engine. Brotli quality 11 and gzip quality 9
variants are generated and verified to decompress to the original bytes. Their
sizes and current asset paths are recorded in `build/web/build.json`. Old asset
generations are retained so already-open tabs can finish loading; removing
`build/web/` clears them when a clean build is wanted. The shell source is
`web/shell.html`, referenced by the export preset; the helper fills its asset
path placeholders reproducibly. The runtime pack excludes GDUnit4,
tests, tools, reference video, hosting sources, credentials and editor caches
(other than Godot's required exported-scene/UID metadata).

Serve the whole `build/web/` directory, retaining its asset paths. The preview
server negotiates Brotli, gzip or uncompressed delivery using `Accept-Encoding`,
sets `Content-Encoding` and `Vary: Accept-Encoding`, and preserves original MIME
types (`application/wasm`, JavaScript or binary PCK). Safari decompresses the
response automatically; there is no custom decoder or patched Godot loader.
Versioned assets use a one-year immutable browser cache. HTML uses `no-cache`
(revalidate with a content-hash ETag), so normal reloads discover the latest build
without downloading an unchanged engine. `--no-cache` forces `no-store` for
diagnostics. Restart an existing preview server after changing `tools/serve.py`.
The generated `_headers` remains only a hosting configuration candidate; another
host must explicitly support precompressed variants and actual isolation headers.
No Sites hosting limitation is resolved by this optimization. Recheck first load,
reload, content encoding and isolation at the tunnel/host as well as the origin.

Required actual response headers:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: same-origin
```

The shell checks secure context, isolation, shared memory, WebGL 2 and eventual
physics startup, with a visible error instead of a blank canvas. There is no
service-worker workaround. Header configuration files alone are not verification.