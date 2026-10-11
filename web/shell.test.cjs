const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');

const shell = readFileSync(`${__dirname}/shell.html`, 'utf8');
const startup = [...shell.matchAll(/<script>([\s\S]*?)<\/script>/g)][0][1];

async function boot({bridge = true, libraries = []} = {}) {
  const elements = Object.fromEntries(['canvas', 'startup', 'startup-message', 'progress'].map(id => [id, {
    hidden: false, getBoundingClientRect: () => ({width: 800, height: 600}),
  }]));
  let starts = 0;
  let receivedConfig;
  const window = bridge ? {CargoHold: {focusPrompt() {}, diagnostics: {report: {engine: 'Box3D'}}}} : {};
  const context = {
    window, document: {
      getElementById: id => elements[id], querySelector: () => elements.canvas,
      createElement: () => ({getContext: () => ({getExtension: () => null})}),
    },
    ResizeObserver: class {observe() {}},
    Engine: class {constructor(config) {receivedConfig = config;} async startGame() {starts++;}},
    isSecureContext: true, crossOriginIsolated: true, SharedArrayBuffer,
    CargoHold: window.CargoHold, setTimeout() {},
  };
  await vm.runInNewContext(startup.replace('$GODOT_CONFIG', JSON.stringify({executable: 'index', fileSizes: {'index.wasm': 123}, gdextensionLibs: libraries})).replaceAll('$MAGICBOX_ASSET_BASE', 'assets/0123456789abcdef0123').replaceAll('$MAGICBOX_ENGINE_BASE', '/assets/abcdef0123456789abcd'), context);
  return {starts, elements, receivedConfig};
}

test('missing motion companion gives an actionable message before engine startup', async () => {
  const {starts, elements} = await boot({bridge: false});
  assert.equal(starts, 0);
  assert.match(elements['startup-message'].textContent, /motion script is missing/);
  assert.equal(elements.progress.hidden, true);
});

test('editor debug export without Box3D is rejected before wasm instantiation', async () => {
  const {starts, elements} = await boot();
  assert.equal(starts, 0);
  assert.match(elements['startup-message'].textContent, /unsupported debug build/);
  assert.equal(elements.progress.hidden, true);
});

test('threaded release with its motion bridge reaches engine startup', async () => {
  const {starts, elements, receivedConfig} = await boot({libraries: ['libbox3d_godot.web.template_release.wasm32.wasm']});
  assert.equal(starts, 1);
  assert.equal(elements.startup.hidden, true);
  assert.equal(receivedConfig.executable, '/assets/abcdef0123456789abcd/index');
  assert.equal(receivedConfig.mainPack, 'index.pck');
  assert.equal(receivedConfig.gdextensionLibs[0], 'libbox3d_godot.web.template_release.wasm32.wasm');
  assert.equal(receivedConfig.fileSizes['/assets/abcdef0123456789abcd/index.wasm'], 123);
});
