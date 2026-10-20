from pathlib import Path
import base64
import gzip
import hashlib
import json

root = Path(__file__).resolve().parent.parent
old = (root / 'source/release/Plain Craft Launcher 2.exe').read_bytes()
new = (root / 'PCL-Download-Restored.exe').read_bytes()
index = {}
for pos in range(0, len(old) - 31, 4):
    key = old[pos:pos + 32]
    if key not in index:
        index[key] = pos

ops = []
literal = bytearray()
cursor = 0
while cursor < len(new):
    src = index.get(new[cursor:cursor + 32])
    if src is None:
        literal.append(new[cursor])
        cursor += 1
        continue
    if literal:
        ops.append({'data': base64.b64encode(literal).decode('ascii')})
        literal.clear()
    count = 32
    while src + count + 4096 <= len(old) and cursor + count + 4096 <= len(new) and old[src + count:src + count + 4096] == new[cursor + count:cursor + count + 4096]:
        count += 4096
    while src + count < len(old) and cursor + count < len(new) and old[src + count] == new[cursor + count]:
        count += 1
    ops.append({'copy': [src, count]})
    cursor += count
if literal:
    ops.append({'data': base64.b64encode(literal).decode('ascii')})

rebuilt = b''.join(old[x['copy'][0]:sum(x['copy'])] if 'copy' in x else base64.b64decode(x['data']) for x in ops)
assert rebuilt == new
manifest = {
    'format': 1,
    'version': '2.99.0.0',
    'before': hashlib.sha256(old).hexdigest(),
    'after': hashlib.sha256(new).hexdigest(),
    'beforeLength': len(old),
    'afterLength': len(new),
    'operations': ops,
}
out = root
(out / 'download.patch.gz').write_bytes(gzip.compress(json.dumps(manifest, separators=(',', ':')).encode(), mtime=0))
print(json.dumps({k:v for k,v in manifest.items() if k != 'operations'}, indent=2))
print(f'{len(ops)} operations; compressed delta {(out / "download.patch.gz").stat().st_size} bytes')
