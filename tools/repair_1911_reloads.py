"""Repair the stock 1911 wrist keys in ZoneTool S1 xanim dumps.

Usage: python tools/repair_1911_reloads.py <original-xanim-directory>
Outputs the three Classic clips in zone_source/xanim for the zone builder.
"""

import hashlib
import math
from pathlib import Path
import struct
import sys


# The normal/empty clips share a brief reversed wrist pose during magazine
# removal. The quick reload has a one-frame wrist snap in the same movement.
CLIPS = {
    "reload": (8, 14, "462918d9436926d7389dd7c16fc811ae15dc17880c4967ee8d509b4cabcb615c"),
    "reload_empty": (8, 14, "8fe3ff6040d3aadf892516603c17ba3afa5c846ae81b68ded97e83fe98775f04"),
    "reload_quick": (5, 9, "0f77a64e9bfa22a931300894e4cb1918c3254a3440f709b67550dcaf42e587a8"),
}
BONES = {"j_wrist_le", "j_wristtwist_le", "j_wristtwist_back_le"}


def normalize(q):
    length = math.sqrt(sum(v * v for v in q))
    return tuple(v / length for v in q)


def slerp(a, b, t):
    a, b = normalize(a), normalize(b)
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b, dot = tuple(-v for v in b), -dot
    if dot > 0.9995:
        return normalize(tuple(x + t * (y - x) for x, y in zip(a, b)))
    theta = math.acos(min(dot, 1))
    left, right = math.sin((1 - t) * theta), math.sin(t * theta)
    return tuple((x * left + y * right) / math.sin(theta) for x, y in zip(a, b))


def repair(source, output, suffix, start, end, digest):
    path = source / f"va_m1911_{suffix}.xab"
    assert path.stat().st_size < 65536, path
    data = bytearray(path.read_bytes())
    assert hashlib.sha256(data).hexdigest() == digest, f"Unexpected stock clip: {path}"
    cursor = 0

    def record(size=0):
        nonlocal cursor
        assert data[cursor:cursor + 2] == bytes([8 if size else 6, 1])
        cursor += 2
        if size:
            count = struct.unpack_from("<I", data, cursor)[0]
            cursor += 4
            offset = cursor
            cursor += count * size
            return offset
        offset = cursor
        cursor = data.index(0, cursor) + 1
        return data[offset:cursor - 1].decode()

    header = record(216)
    name_start = cursor
    assert record() == f"va_m1911_{suffix}"
    name_end = cursor
    counts = data[header + 17:header + 29]
    assert counts[1] == 0 and counts[3] == 0
    assert struct.unpack_from("<H", data, header + 14)[0] < 256
    names = [record() for _ in range(counts[9])]
    frames = record(1)
    shorts = record(2)
    record(4)  # Translations stay byte-for-byte intact.
    rotations = record(2)
    changed_bones = set()
    changed_keys = 0
    for bone in names[counts[0]:counts[0] + counts[2]]:
        count = struct.unpack_from("<H", data, shorts)[0] + 1
        shorts += 2
        keys = dict(zip(data[frames:frames + count], range(rotations, rotations + count * 8, 8)))
        if bone in BONES:
            a = struct.unpack_from("<4h", data, keys[start])
            b = struct.unpack_from("<4h", data, keys[end])
            for frame, offset in keys.items():
                if start < frame < end:
                    q = slerp(a, b, (frame - start) / (end - start))
                    packed = [max(-32768, min(32767, round(v * 32768))) for v in q]
                    struct.pack_into("<4h", data, offset, *packed)
                    changed_keys += 1
            changed_bones.add(bone)
        frames += count
        rotations += count * 8
    assert changed_bones == BONES
    name = f"awz_m1911_{suffix}"
    data[name_start:name_end] = b"\x06\x01" + name.encode() + b"\0"
    (output / f"{name}.xab").write_bytes(data)
    print(f"[Classic] {name}: repaired {changed_keys} wrist keys between frames {start} and {end}")


if __name__ == "__main__":
    source = Path(sys.argv[1])
    output = Path(__file__).resolve().parents[1] / "zone_source" / "xanim"
    output.mkdir(parents=True, exist_ok=True)
    for suffix, (start, end, digest) in CLIPS.items():
        repair(source, output, suffix, start, end, digest)
