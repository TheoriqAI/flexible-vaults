#!/usr/bin/env python3
"""
Fix descriptions in merged JSON by copying from original source files.

Usage:
    python scripts/fix_descriptions.py <merged_json> <source_file1> <source_file2> ...

Example:
    python scripts/fix_descriptions.py \
        scripts/jsons/ethereum:tqETHPreProd:subvault3.json \
        scripts/jsons/ethereum:tqETH:preprod:sv3:aaveOps-emode0.json \
        scripts/jsons/ethereum:tqETH:preprod:sv3:aaveOps-emode32.json \
        scripts/jsons/ethereum:tqETH:preprod:sv3:sparkOps-emode0.json \
        scripts/jsons/ethereum:tqETH:preprod:sv3:sparkOps-emode32.json
"""

import json
import sys


def load_json(filepath: str) -> dict:
    with open(filepath, 'r') as f:
        return json.load(f)


def save_json(filepath: str, data: dict):
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)


def build_description_map(source_files: list) -> dict:
    """Build a map of verificationData -> description from source files."""
    desc_map = {}

    for filepath in source_files:
        print(f"Reading descriptions from: {filepath}")
        data = load_json(filepath)

        for proof in data.get('merkle_proofs', []):
            vdata = proof.get('verificationData')
            desc = proof.get('description')
            if vdata and desc:
                desc_map[vdata] = desc

    print(f"Total descriptions collected: {len(desc_map)}")
    return desc_map


def fix_descriptions(merged_file: str, source_files: list):
    """Fix descriptions in merged file by index order from source files.

    merge_jsons.py preserves source order (file1 ops, file2 ops, ...),
    so we copy descriptions positionally rather than by verificationData key
    (which can collide for enterExit ops that share the same bitmask).
    """
    print(f"\n=== Fixing descriptions in {merged_file} ===\n")

    # Build ordered list of descriptions matching merge order
    source_descs = []
    for filepath in source_files:
        print(f"Reading descriptions from: {filepath}")
        data = load_json(filepath)
        for proof in data.get('merkle_proofs', []):
            source_descs.append(proof.get('description'))

    print(f"Total descriptions collected: {len(source_descs)}")

    # Load merged file
    merged = load_json(merged_file)
    merged_proofs = merged.get('merkle_proofs', [])

    if len(source_descs) != len(merged_proofs):
        print(f"ERROR: source count ({len(source_descs)}) != merged count ({len(merged_proofs)})")
        sys.exit(1)

    # Fix descriptions by index
    for i in range(len(merged_proofs)):
        merged_proofs[i]['description'] = source_descs[i]

    # Save fixed file
    save_json(merged_file, merged)

    print(f"\n=== Fix Complete ===")
    print(f"Fixed: {len(merged_proofs)}")
    print(f"Output: {merged_file}")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    merged_file = sys.argv[1]
    source_files = sys.argv[2:]

    fix_descriptions(merged_file, source_files)


if __name__ == '__main__':
    main()
