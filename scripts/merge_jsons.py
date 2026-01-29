#!/usr/bin/env python3
"""
Merge multiple JSON permission files into a single file with regenerated merkle proofs.

Usage:
    python scripts/merge_jsons.py <output_title> <input_file1> <input_file2> ...

Example:
    python scripts/merge_jsons.py ethereum:tqETHPreProd:subvault4 \
        scripts/jsons/ethereum:tqETH:preprod:sv4:aaveOps.json \
        scripts/jsons/ethereum:tqETH:preprod:sv4:pendlePT.json \
        scripts/jsons/ethereum:tqETH:preprod:sv4:curveNUSD.json
"""

import json
import sys
from typing import List
from eth_abi import encode
from eth_utils import keccak


def load_json(filepath: str) -> dict:
    """Load a JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)


def save_json(filepath: str, data: dict):
    """Save data to a JSON file."""
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)


def hash_leaf(verification_type: int, verification_data: bytes) -> bytes:
    """Hash a leaf node: keccak256(abi.encode(verificationType, verificationData))"""
    encoded = encode(['uint8', 'bytes'], [verification_type, verification_data])
    return keccak(encoded)


def generate_proofs(leaves: List[bytes]) -> List[List[bytes]]:
    """Generate merkle proofs for each leaf."""
    if not leaves:
        return []
    if len(leaves) == 1:
        return [[]]

    n = len(leaves)
    proofs = [[] for _ in range(n)]

    # Build the tree and track indices
    tree_levels = [leaves[:]]
    current = leaves[:]

    while len(current) > 1:
        next_level = []
        for i in range(0, len(current), 2):
            left = current[i]
            right = current[i + 1] if i + 1 < len(current) else current[i]

            # Sort for consistent ordering
            if left > right:
                left, right = right, left

            parent = keccak(left + right)
            next_level.append(parent)

        current = next_level
        tree_levels.append(current)

    # Generate proofs by walking up the tree
    for leaf_idx in range(n):
        idx = leaf_idx
        for level in range(len(tree_levels) - 1):
            level_nodes = tree_levels[level]
            sibling_idx = idx ^ 1  # XOR to get sibling

            if sibling_idx < len(level_nodes):
                proofs[leaf_idx].append(level_nodes[sibling_idx])
            else:
                # Odd number of nodes, sibling is self
                proofs[leaf_idx].append(level_nodes[idx])

            idx = idx // 2

    return proofs


def bytes_to_hex(b: bytes) -> str:
    """Convert bytes to 0x-prefixed hex string."""
    return '0x' + b.hex()


def hex_to_bytes(h: str) -> bytes:
    """Convert 0x-prefixed hex string to bytes."""
    if h.startswith('0x'):
        h = h[2:]
    return bytes.fromhex(h)


def merge_jsons(output_title: str, input_files: List[str]) -> dict:
    """
    Merge multiple JSON files into one with regenerated merkle proofs.
    """
    all_proofs = []

    print(f"=== Merging {len(input_files)} JSON files ===\n")

    for filepath in input_files:
        print(f"Reading: {filepath}")
        data = load_json(filepath)

        proofs = data.get('merkle_proofs', [])
        print(f"  Operations: {len(proofs)}")

        for proof in proofs:
            all_proofs.append(proof)

    print(f"\nTotal operations: {len(all_proofs)}")

    # Compute leaf hashes
    leaves = []
    for proof in all_proofs:
        vtype = proof['verificationType']
        vdata = hex_to_bytes(proof['verificationData'])
        leaf_hash = hash_leaf(vtype, vdata)
        leaves.append(leaf_hash)

    # Compute merkle root and proofs
    print("Computing merkle root and proofs...")
    proofs = generate_proofs(leaves)

    # Compute merkle root
    merkle_root = b'\x00' * 32
    if leaves:
        current = leaves[:]
        while len(current) > 1:
            next_level = []
            for i in range(0, len(current), 2):
                left = current[i]
                right = current[i + 1] if i + 1 < len(current) else current[i]
                if left > right:
                    left, right = right, left
                next_level.append(keccak(left + right))
            current = next_level
        merkle_root = current[0]

    print(f"Merkle root: {bytes_to_hex(merkle_root)}")

    # Update proofs in the data
    for i, proof_data in enumerate(all_proofs):
        proof_data['proof'] = [bytes_to_hex(p) for p in proofs[i]]

    # Build output
    output = {
        'title': output_title,
        'merkle_root': bytes_to_hex(merkle_root),
        'merkle_proofs': all_proofs
    }

    return output


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    output_title = sys.argv[1]
    input_files = sys.argv[2:]

    result = merge_jsons(output_title, input_files)

    output_path = f"scripts/jsons/{output_title}.json"
    save_json(output_path, result)

    print(f"\n=== Merge Complete ===")
    print(f"Output: {output_path}")
    print(f"Merkle root: {result['merkle_root']}")
    print(f"Total operations: {len(result['merkle_proofs'])}")


if __name__ == '__main__':
    main()
