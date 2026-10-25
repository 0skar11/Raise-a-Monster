"""Remove empty modern metadata from the native model for the installed Rojo.

All retained binary chunks, including native mesh caches, are copied verbatim.
The approved source .rbxm is never modified. No external Python modules needed.
"""

import argparse
import hashlib
import json
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "assets" / "HalloweenCollectionMap.rbxm"
DEFAULT_OUTPUT = ROOT / "assets" / "HalloweenCollectionMap_Rojo.rbxm"
DROP_PROPERTIES = {"Tags", "Capabilities"}
SIGNATURE = b"<roblox!\x89\xff\r\n\x1a\n"


def decompress_lz4_block(source, expected_length):
    """Decode a raw LZ4 block, including overlapping back references."""
    output = bytearray()
    position = 0

    def extension(length):
        nonlocal position
        while True:
            if position >= len(source):
                raise ValueError("Truncated LZ4 length")
            value = source[position]
            position += 1
            length += value
            if value != 255:
                return length

    while position < len(source):
        token = source[position]
        position += 1
        literal_length = token >> 4
        if literal_length == 15:
            literal_length = extension(literal_length)
        if position + literal_length > len(source):
            raise ValueError("Truncated LZ4 literal")
        output.extend(source[position:position + literal_length])
        position += literal_length
        if position == len(source):
            break
        if position + 2 > len(source):
            raise ValueError("Truncated LZ4 offset")
        offset = int.from_bytes(source[position:position + 2], "little")
        position += 2
        if offset == 0 or offset > len(output):
            raise ValueError("Invalid LZ4 offset")
        match_length = (token & 15) + 4
        if token & 15 == 15:
            match_length = extension(match_length)
        if len(output) + match_length > expected_length:
            raise ValueError("LZ4 match exceeds declared length")
        for _ in range(match_length):
            output.append(output[-offset])
    if len(output) != expected_length:
        raise ValueError(f"LZ4 length mismatch: {len(output)} != {expected_length}")
    return bytes(output)


def read_chunks(data):
    if len(data) < 32 or data[:14] != SIGNATURE:
        raise ValueError("Not a Roblox binary model")
    position = 32
    while position < len(data):
        if position + 16 > len(data):
            raise ValueError("Truncated Roblox chunk header")
        tag, compressed, uncompressed, reserved = struct.unpack_from("<4sIII", data, position)
        end = position + 16 + (compressed or uncompressed)
        if end > len(data):
            raise ValueError("Truncated Roblox chunk")
        raw = data[position:end]
        payload = raw[16:]
        if compressed:
            payload = decompress_lz4_block(payload, uncompressed)
        yield tag, payload, raw
        position = end
    if position != len(data):
        raise ValueError("Trailing binary data")


def string_at(payload, position):
    length = struct.unpack_from("<I", payload, position)[0]
    start = position + 4
    return payload[start:start + length], start + length


def instance_classes(chunks):
    classes = {}
    for tag, payload, _ in chunks:
        if tag == b"INST":
            identifier = struct.unpack_from("<I", payload)[0]
            name, offset = string_at(payload, 4)
            count = struct.unpack_from("<I", payload, offset + 1)[0]
            classes[identifier] = (name.decode(), count)
    return classes


def property_header(payload):
    identifier = struct.unpack_from("<I", payload)[0]
    name, offset = string_at(payload, 4)
    return identifier, name.decode(), payload[offset], payload[offset + 1:]


def shared_strings(chunks):
    strings = []
    for tag, payload, _ in chunks:
        if tag == b"SSTR":
            version, count = struct.unpack_from("<II", payload)
            if version != 0:
                raise ValueError(f"Unsupported shared string version {version}")
            position = 8
            for _ in range(count):
                value, position = string_at(payload, position + 16)
                strings.append(value)
            if position != len(payload):
                raise ValueError("Malformed shared string table")
    return strings


def mesh_identity(chunks):
    """Resolve IDs and native physical blobs by mesh name, independent of ordering."""
    classes = instance_classes(chunks)
    strings = shared_strings(chunks)
    properties = {}
    for tag, payload, _ in chunks:
        if tag != b"PROP":
            continue
        identifier, name, value_type, values = property_header(payload)
        class_name, count = classes[identifier]
        if class_name != "MeshPart" or name not in {"Name", "MeshId", "PhysicalConfigData"}:
            continue
        if name == "PhysicalConfigData":
            if value_type != 0x1C or len(values) != count * 4:
                raise ValueError("Unexpected native physical cache encoding")
            indices = [int.from_bytes(bytes(values[i + j * count] for j in range(4)), "big")
                       for i in range(count)]
            properties[name] = [strings[index] for index in indices]
        else:
            if value_type != 0x01:
                raise ValueError(f"Unexpected {name} encoding")
            position = 0
            items = []
            for _ in range(count):
                value, position = string_at(values, position)
                items.append(value)
            if position != len(values):
                raise ValueError(f"Malformed {name} array")
            properties[name] = items
    return {name: (mesh_id, native_cache) for name, mesh_id, native_cache in zip(
        properties["Name"], properties["MeshId"], properties["PhysicalConfigData"])}


def convert(source, destination):
    if source.resolve() == destination.resolve():
        raise ValueError("Source and destination must differ")
    original = source.read_bytes()
    chunks = list(read_chunks(original))
    classes = instance_classes(chunks)
    strings = shared_strings(chunks)
    kept = []
    removed = []
    for tag, payload, raw in chunks:
        if tag == b"PROP":
            identifier, name, value_type, values = property_header(payload)
            if name in DROP_PROPERTIES:
                # Empty tags index the empty shared string; capabilities are zero.
                # Refuse to discard actual behavior-bearing metadata.
                if any(values):
                    raise ValueError(f"Refusing to discard nonempty {classes[identifier][0]}.{name}")
                expected_type, width = (0x1C, 4) if name == "Tags" else (0x21, 8)
                if value_type != expected_type or len(values) != classes[identifier][1] * width:
                    raise ValueError(f"Unexpected encoding for {name}")
                if name == "Tags" and (not strings or strings[0]):
                    raise ValueError("Tags reference a nonempty shared string")
                removed.append({"class": classes[identifier][0], "property": name,
                                "type": hex(value_type), "instances": classes[identifier][1]})
                continue
        kept.append(raw)
    transformed = original[:32] + b"".join(kept)
    reread = list(read_chunks(transformed))
    assert [chunk[2] for chunk in reread] == kept
    assert instance_classes(reread) == classes
    assert [p for t, p, _ in chunks if t == b"SSTR"] == [p for t, p, _ in reread if t == b"SSTR"]
    destination.write_bytes(transformed)
    assert source.read_bytes() == original
    return {
        "source": str(source), "destination": str(destination),
        "source_sha256": hashlib.sha256(original).hexdigest(),
        "source_bytes": len(original), "converted_bytes": len(transformed),
        "classes": {name: count for name, count in classes.values()},
        "removed": removed, "retained_chunks_byte_identical": True,
        "native_shared_strings_byte_identical": True,
    }


def validate_rojo(destination, rojo):
    """Build only the model in a temporary project; leave the live project alone."""
    with tempfile.TemporaryDirectory(prefix="halloween-rbxm-check-") as temporary:
        folder = Path(temporary)
        project = folder / "default.project.json"
        project.write_text(json.dumps({"name": "HalloweenMeshCompatibilityCheck", "tree": {
            "$className": "DataModel", "Workspace": {"$className": "Workspace",
                "HalloweenCollectionMap": {"$path": str(destination.resolve())}}
        }}), encoding="utf-8")
        built = folder / "check.rbxl"
        completed = subprocess.run([str(rojo), "build", str(project), "--output", str(built)],
                                   capture_output=True, text=True, check=False)
        if completed.returncode:
            raise RuntimeError(completed.stdout + completed.stderr)
        chunks = list(read_chunks(built.read_bytes()))
        classes = instance_classes(chunks)
        mesh_count = sum(count for name, count in classes.values() if name == "MeshPart")
        if mesh_count != 82:
            raise ValueError(f"Rojo build has {mesh_count} MeshParts, expected 82")
        original_chunks = list(read_chunks(destination.read_bytes()))
        native_blobs = shared_strings(original_chunks)
        built_blobs = shared_strings(chunks)
        if not set(native_blobs).issubset(set(built_blobs)):
            raise ValueError("Rojo build lost native shared string data")
        original_identity = mesh_identity(original_chunks)
        if len(original_identity) != 82 or mesh_identity(chunks) != original_identity:
            raise ValueError("Rojo build changed mesh IDs or native physical cache data")
        return {"rojo_build_passed": True, "meshparts": mesh_count,
                "all_mesh_ids_and_native_caches_preserved": True,
                "native_shared_string_blobs": len(native_blobs),
                "native_shared_string_bytes": sum(map(len, native_blobs)),
                "build_output": completed.stdout.strip()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--rojo", type=Path)
    args = parser.parse_args()
    report = convert(args.source, args.output)
    print(json.dumps(report, indent=2), flush=True)
    if args.rojo:
        print(json.dumps(validate_rojo(args.output, args.rojo), indent=2), flush=True)
