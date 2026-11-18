#!/usr/bin/env python3
"""Adapt removed Qualcomm camera extensions to Android 17's public camera ABI.

Keep normal camera metadata and ABI intact. For obsolete optional extended face
properties absent from camera_face_t, pass 0 to the legacy Java fields.
Preserve original vendor command numbers without changing system camera headers.
"""
from pathlib import Path
import re
import sys

FACE_FIELDS = (
    'smile_degree', 'smile_score', 'blink_detected', 'face_recognised',
    'gaze_angle', 'updown_dir', 'leftright_dir', 'roll_dir', 'leye_blink',
    'reye_blink', 'left_right_gaze', 'top_bottom_gaze',
)
COMMANDS = {
    'CAMERA_CMD_HISTOGRAM_ON': ('kInfinityHistogramOn', 11),
    'CAMERA_CMD_HISTOGRAM_OFF': ('kInfinityHistogramOff', 12),
    'CAMERA_CMD_HISTOGRAM_SEND_DATA': ('kInfinityHistogramSendData', 13),
    'CAMERA_CMD_LONGSHOT_ON': ('kInfinityLongshotOn', 14),
    'CAMERA_CMD_LONGSHOT_OFF': ('kInfinityLongshotOff', 15),
    'CAMERA_CMD_METADATA_ON': ('kInfinityMetadataOn', 100),
    'CAMERA_CMD_METADATA_OFF': ('kInfinityMetadataOff', 101),
}
MARKER = '// Infinity-X Android 17 camera JNI compatibility for legacy Qualcomm extensions.'


def main() -> int:
    if len(sys.argv) != 2:
        print('Usage: prepare-camera-jni.py <android-source-root>', file=sys.stderr)
        return 2
    source = Path(sys.argv[1]) / 'frameworks/base/core/jni/android_hardware_Camera.cpp'
    if not source.is_file():
        print(f'Missing camera JNI source: {source}', file=sys.stderr)
        return 1
    original = source.read_text(encoding='utf-8')
    if MARKER in original:
        if (all(f'INFINITY_FACE_FIELD(metadata->faces[i], {field})' in original
                for field in FACE_FIELDS)
                and all(symbol in original for symbol, _ in COMMANDS.values())):
            print('Infinity-X camera JNI compatibility: already applied')
            return 0
        print('Camera JNI fix is partially applied. Refusing overwrite.', file=sys.stderr)
        return 1
    missing = [f'face {field}' for field in FACE_FIELDS
               if original.count(f'metadata->faces[i].{field}') != 1]
    missing += [f'command {command}' for command in COMMANDS
                if len(re.findall(rf'\b{command}\b', original)) != 1]
    if missing:
        print(f'Unexpected camera JNI revision: {", ".join(missing)}', file=sys.stderr)
        return 1
    first_include = re.search(r'^#include\s+', original, re.MULTILINE)
    if first_include is None:
        print('Cannot find camera JNI include section.', file=sys.stderr)
        return 1
    updated = original
    for field in FACE_FIELDS:
        updated = updated.replace(
            f'metadata->faces[i].{field}',
            f'INFINITY_FACE_FIELD(metadata->faces[i], {field})')
    for command, (replacement, value) in COMMANDS.items():
        updated = re.sub(rf'\b{command}\b', replacement, updated)

    # C++20 compile-time field detection preserves camera_face_t's ABI.
    preamble = f'''{MARKER}
#define INFINITY_FACE_FIELD(faceExpr, fieldName) \\
    ([]<typename FaceT>(const FaceT& face) -> int {{ \\
        if constexpr (requires {{ face.fieldName; }}) {{ \\
            return static_cast<int>(face.fieldName); \\
        }} else {{ \\
            return 0; \\
        }} \\
    }}(faceExpr))

namespace {{
'''
    preamble += ''.join(f'constexpr int {name} = {value};\n'
                        for name, value in COMMANDS.values())
    preamble += '} // namespace\n\n'
    first_include = re.search(r'^#include\s+', updated, re.MULTILINE)
    updated = updated[:first_include.start()] + preamble + updated[first_include.start():]
    if any(re.search(rf'\b{command}\b', updated) for command in COMMANDS):
        print('Legacy camera command tokens remain; refusing patch.', file=sys.stderr)
        return 1
    source.write_text(updated, encoding='utf-8')
    print('Infinity-X camera JNI compatibility: optional face fields guarded, legacy commands restored')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
