#!/usr/bin/env python3
"""Inspect Godot 4 PCK directory entries without unpacking runtime assets."""
from pathlib import Path
import struct
import sys

def entries(path):
 with Path(path).open('rb') as stream:
  def u32(): return struct.unpack('<I',stream.read(4))[0]
  assert stream.read(4)==b'GDPC', 'Not a Godot PCK'
  version=u32(); assert version in (2,3,4), f'Unsupported PCK format: {version}'
  major,minor,patch=u32(),u32(),u32()
  flags=u32();base=struct.unpack('<Q',stream.read(8))[0]
  if version >= 3:
   directory_offset=struct.unpack('<Q',stream.read(8))[0]
  stream.read(64)
  if version >= 3: stream.seek(directory_offset)
  count=u32(); names=[]
  for _ in range(count):
   length=u32();names.append(stream.read(length).rstrip(b'\0').decode())
   stream.read(8+8+16+4)
  return names

if __name__=='__main__':
 names=entries(sys.argv[1] if len(sys.argv)>1 else 'build/web/index.pck')
 for name in names: print(name)
 banned=['addons/gdUnit4/', 'example/', 'tests/', 'tools/', 'hosting/', 'build/', 'web/', '.git/', '.aws/']
 assert not any(part in name for name in names for part in banned), 'Development/private files in runtime pack'
 assert any('addons/box3d/box3d.gdextension' in n for n in names), 'Missing Box3D manifest'
 for script in ['magic_box','motion_processor','browser_input','cargo_theme']:
  assert any(f'scripts/{script}.gdc' in n for n in names), f'Missing {script}'
 assert not any('shaders/cargo_panels' in n for n in names), 'Removed theme shader in runtime pack'
 print(f'PASS: {len(names)} runtime entries; no development or private files')
