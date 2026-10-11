"""HTTP and packaging integration tests for compression, caches and updates."""
from functools import partial
import gzip
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from threading import Thread
import unittest

from export_web import package
from serve import Handler

class QuietHandler(Handler):
    def log_message(self, *args):
        pass

class DeliveryTest(unittest.TestCase):
    def setUp(self):
        if not shutil.which('brotli'):
            self.skipTest('Brotli CLI required')
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.stage = root / 'stage'
        self.output = root / 'web'
        self.stage.mkdir()
        (self.stage / 'index.html').write_text('<script src="$MAGICBOX_ENGINE_BASE/index.js"></script><script src="$MAGICBOX_ASSET_BASE/motion.js"></script>')
        self.wasm = b'\0asm' + b'0123456789' * 1000
        (self.stage / 'index.wasm').write_bytes(self.wasm)
        (self.stage / 'index.js').write_text('console.log("ready");')
        (self.stage / 'motion.js').write_text('console.log("motion");')
        self.report = package(self.stage, self.output)
        self.asset = '/' + self.report['engine_base'] + '/index.wasm'
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(self.output)))
        Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def request(self, path, encoding=None, etag=None, method='GET'):
        headers = {}
        if encoding is not None:
            headers['Accept-Encoding'] = encoding
        if etag:
            headers['If-None-Match'] = etag
        connection = HTTPConnection(*self.server.server_address)
        connection.request(method, path, headers=headers)
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def test_brotli_gzip_and_identity_are_lossless_with_original_mime(self):
        for accepted, expected in [('br, gzip', 'br'), ('gzip', 'gzip'), ('identity', None),
                                   ('br;q=0, gzip;q=1', 'gzip'), ('*;q=0.5', 'br'),
                                   ('br;q=0.5, identity;q=1', None)]:
            with self.subTest(accepted=accepted):
                status, headers, body = self.request(self.asset, accepted)
                self.assertEqual(status, 200)
                self.assertEqual(headers.get('Content-Encoding'), expected)
                self.assertEqual(headers['Content-Type'], 'application/wasm')
                self.assertEqual(int(headers['Content-Length']), len(body))
                self.assertEqual(headers['Vary'], 'Accept-Encoding')
                self.assertIn('immutable', headers['Cache-Control'])
                if expected == 'br':
                    body = subprocess.check_output(['brotli', '-d', '-c'], input=body)
                elif expected == 'gzip':
                    body = gzip.decompress(body)
                self.assertEqual(body, self.wasm)
        self.assertEqual(self.request(self.asset, '*;q=0')[0], 406)

    def test_head_and_conditional_requests_preserve_isolation_and_variants(self):
        _, headers, _ = self.request(self.asset, 'br')
        for method, etag, expected in [('HEAD', None, 200), ('GET', headers['ETag'], 304),
                                       ('GET', 'W/' + headers['ETag'], 304)]:
            status, result, body = self.request(self.asset, 'br', etag, method)
            self.assertEqual(status, expected)
            self.assertEqual(body, b'')
            self.assertEqual(result['Cross-Origin-Opener-Policy'], 'same-origin')
            self.assertEqual(result['Cross-Origin-Embedder-Policy'], 'require-corp')
        # A Brotli validator cannot validate a different representation.
        self.assertEqual(self.request(self.asset, 'identity', headers['ETag'])[0], 200)

    def test_updates_publish_new_urls_and_keep_old_tabs_working(self):
        _, headers, old_html = self.request('/', 'identity')
        self.assertEqual(headers['Cache-Control'], 'no-cache')
        self.assertEqual(self.request('/', 'identity', headers['ETag'])[0], 304)
        (self.stage / 'motion.js').write_text('console.log("newer");')
        newer = package(self.stage, self.output)
        self.assertNotEqual(newer['asset_base'], self.report['asset_base'])
        self.assertEqual(newer['engine_base'], self.report['engine_base'])
        status, _, new_html = self.request('/', 'identity', headers['ETag'])
        self.assertEqual(status, 200)
        self.assertNotEqual(old_html, new_html)
        self.assertIn(newer['asset_base'].encode(), new_html)
        self.assertEqual(self.request(self.asset, 'br')[0], 200)
        repeated = package(self.stage, self.output)
        self.assertEqual(repeated['asset_base'], newer['asset_base'])
        self.assertEqual(json.loads((self.output / 'build.json').read_text())['asset_base'], newer['asset_base'])

    def test_missing_files_remain_errors_with_isolation_headers(self):
        status, headers, _ = self.request('/missing.wasm', 'br')
        self.assertEqual(status, 404)
        self.assertNotIn('Content-Encoding', headers)
        self.assertEqual(headers['Cross-Origin-Embedder-Policy'], 'require-corp')

if __name__ == '__main__':
    unittest.main()
