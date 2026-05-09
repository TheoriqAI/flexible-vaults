#!/usr/bin/env python3
"""
Merge multiple JSON permission files into a single file with regenerated merkle proofs.
FIXED version that matches Solidity leaf hash computation.

Usage:
    python scripts/merge_jsons_new.py <output_title> <input_file1> <input_file2> ...

Example:
    python scripts/merge_jsons_new.py ethereum:tqETH:prod:sv3:all \
        scripts/jsons/ethereum:tqETH:prod:sv3:aaveOps-emode1.json \
        scripts/jsons/ethereum:tqETH:prod:sv3:sparkOps-emode1.json \
        scripts/jsons/ethereum:tqETH:prod:sv3:swapModule.json
"""

import json
import sys
from typing import List, Tuple
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


def bytes_to_hex(b: bytes) -> str:
    """Convert bytes to 0x-prefixed hex string."""
    return '0x' + b.hex()


def hex_to_bytes(h: str) -> bytes:
    """Convert 0x-prefixed hex string to bytes."""
    if h.startswith('0x'):
        h = h[2:]
    return bytes.fromhex(h)


def hash_leaf_solidity(verification_type: int, verification_data: bytes) -> bytes:
    """
    Hash a leaf node matching the Solidity implementation:
    keccak256(bytes.concat(keccak256(abi.encode(verificationType, keccak256(verificationData)))))

    This matches:
    - Verifier.sol line 104-105
    - ProofLibrary.sol line 81-83
    """
    # Step 1: Hash the verificationData
    hashed_verification_data = keccak(verification_data)

    # Step 2: abi.encode(verificationType, hashedVerificationData)
    # verificationType is uint8 in the enum but encoded as uint256 in abi.encode
    encoded = encode(['uint8', 'bytes32'], [verification_type, hashed_verification_data])

    # Step 3: First keccak256
    first_hash = keccak(encoded)

    # Step 4: bytes.concat (just the 32 bytes) then keccak256 again
    # This is the OpenZeppelin MerkleProof leaf double-hash pattern
    leaf = keccak(first_hash)

    return leaf


def commutative_keccak256(a: bytes, b: bytes) -> bytes:
    """
    Matches Solidity's Hashes.commutativeKeccak256 - sorts before hashing.
    """
    if a < b:
        return keccak(a + b)
    else:
        return keccak(b + a)


def generate_merkle_tree(leaves: List[bytes]) -> Tuple[bytes, List[List[bytes]]]:
    """
    Generate merkle tree matching the Solidity ProofLibrary.generateMerkleProofs.
    Returns (root, proofs_for_each_leaf).
    """
    n = len(leaves)
    if n == 0:
        return b'\x00' * 32, []

    if n == 1:
        return leaves[0], [[]]

    # Sort leaves (matching Solidity's Arrays.sort)
    sorted_leaves = sorted(leaves)

    # Build tree array: size = 2n - 1
    # Tree is stored with root at index 0
    # For a leaf at sorted position i, its tree index is (tree.length - 1 - i)
    tree_size = 2 * n - 1
    tree = [b'\x00' * 32] * tree_size

    # Place sorted leaves at the end of tree
    for i in range(n):
        tree[tree_size - 1 - i] = sorted_leaves[i]

    # Build internal nodes from bottom up
    # Internal nodes are at indices 0 to n-2
    for i in range(n, 2 * n - 1):
        v = tree_size - 1 - i  # Current node index
        l = v * 2 + 1  # Left child
        r = v * 2 + 2  # Right child
        tree[v] = commutative_keccak256(tree[l], tree[r])

    root = tree[0]

    # Generate proofs for each original leaf (in original order)
    proofs = []
    for i in range(n):
        original_leaf = leaves[i]

        # Find this leaf's position in sorted order
        sorted_index = sorted_leaves.index(original_leaf)

        proof = []
        tree_index = tree_size - 1 - sorted_index

        while tree_index > 0:
            # Find sibling
            if tree_index % 2 == 0:
                sibling_index = tree_index - 1
            else:
                sibling_index = tree_index + 1

            proof.append(tree[sibling_index])
            tree_index = (tree_index - 1) // 2

        proofs.append(proof)

    return root, proofs


def verify_proof(proof: List[bytes], root: bytes, leaf: bytes) -> bool:
    """Verify a merkle proof."""
    computed = leaf
    for sibling in proof:
        computed = commutative_keccak256(computed, sibling)
    return computed == root


def merge_jsons(output_title: str, input_files: List[str]) -> dict:
    """
    Merge multiple JSON files into one with regenerated merkle proofs.
    Uses the corrected leaf hash computation that matches Solidity.
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

    # Compute leaf hashes using the CORRECT Solidity-matching algorithm
    leaves = []
    for proof in all_proofs:
        vtype = proof['verificationType']
        vdata = hex_to_bytes(proof['verificationData'])
        leaf_hash = hash_leaf_solidity(vtype, vdata)
        leaves.append(leaf_hash)

    print(f"Computing merkle root and proofs (Solidity-compatible)...")

    # Generate merkle tree and proofs
    merkle_root, proofs = generate_merkle_tree(leaves)

    print(f"Merkle root: {bytes_to_hex(merkle_root)}")

    # Verify all proofs
    print("Verifying proofs...")
    for i, (leaf, proof) in enumerate(zip(leaves, proofs)):
        if not verify_proof(proof, merkle_root, leaf):
            print(f"  ERROR: Proof {i} failed verification!")
            raise ValueError(f"Proof verification failed for index {i}")
    print("  All proofs verified successfully!")

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
