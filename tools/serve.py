#!/usr/bin/env python3
"""Preview with isolation headers, negotiated compression and browser caches."""
import argparse
from functools import partial
import hashlib
import os
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import re
import ssl
from urllib.parse import urlsplit

def accepted_encodings(header):
    result = {}
    for entry in header.split(','):
        parts = entry.strip().lower().split(';')
        if not parts[0]:
            continue
        quality = 1.0
        try:
            for parameter in parts[1:]:
                if parameter.strip().startswith('q='):
                    quality = float(parameter.strip()[2:])
            if not 0 <= quality <= 1:
                quality = 0.0
        except ValueError:
            quality = 0.0
        result[parts[0]] = quality
    return result

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, no_cache=False, **kwargs):
        self.no_cache = no_cache
        super().__init__(*args, **kwargs)

    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
        super().end_headers()

    def send_head(self):
        requested = urlsplit(self.path).path
        original = Path(self.translate_path(self.path))
        if original.is_dir():
            if not requested.endswith('/'):
                self.send_response(301)
                self.send_header('Location', requested + '/')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return None
            original = original / 'index.html'
        if not original.is_file():
            self.send_error(404, 'File not found')
            return None
        encodings = accepted_encodings(self.headers.get('Accept-Encoding', ''))
        selected, encoding = original, None
        choices = [(encodings.get(name, encodings.get('*', 0)), name, suffix)
                   for name, suffix in (('br', '.br'), ('gzip', '.gz'))]
        identity = encodings.get('identity', 0 if encodings.get('*') == 0 else 1)
        for quality, name, suffix in sorted(choices, key=lambda item: item[0], reverse=True):
            candidate = Path(str(original) + suffix)
            if quality > 0 and candidate.is_file() and quality >= encodings.get('identity', 0):
                selected, encoding = candidate, name
                break
        if encoding is None and identity == 0:
            self.send_error(406, 'No acceptable encoding')
            return None
        stream = selected.open('rb')
        # Hash-based validators distinguish rapid, same-size rebuilds.
        etag = '"' + hashlib.file_digest(stream, 'sha256').hexdigest() + '"'
        stream.seek(0)
        immutable = bool(re.fullmatch(r'/assets/[0-9a-f]{20}/[^/]+', requested))
        cache = 'public, max-age=31536000, immutable' if immutable else 'no-cache'
        if self.no_cache:
            cache = 'no-store'
        matches = [tag.strip().removeprefix('W/') for tag in self.headers.get('If-None-Match', '').split(',')]
        unchanged = etag in matches or '*' in matches
        self.send_response(304 if unchanged else 200)
        self.send_header('Cache-Control', cache)
        self.send_header('ETag', etag)
        self.send_header('Vary', 'Accept-Encoding')
        if encoding:
            self.send_header('Content-Encoding', encoding)
        if not unchanged:
            self.send_header('Content-Type', self.guess_type(str(original)))
            self.send_header('Content-Length', str(os.fstat(stream.fileno()).st_size))
            self.send_header('Last-Modified', self.date_time_string(original.stat().st_mtime))
        self.end_headers()
        if unchanged:
            stream.close()
            return None
        return stream

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', default='build/web')
    parser.add_argument('--port', type=int, default=8061)
    parser.add_argument('--cert')
    parser.add_argument('--key')
    parser.add_argument('--no-cache', action='store_true')
    args = parser.parse_args()
    if bool(args.cert) != bool(args.key):
        parser.error('--cert and --key must be provided together')
    server = ThreadingHTTPServer(('127.0.0.1' if not args.cert else '0.0.0.0', args.port),
                                partial(Handler, directory=str(Path(args.directory).resolve()), no_cache=args.no_cache))
    if args.cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.cert, args.key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f"Cargo Hold: {'https' if args.cert else 'http'}://localhost:{args.port}", flush=True)
    server.serve_forever()

if __name__ == '__main__':
    main()
