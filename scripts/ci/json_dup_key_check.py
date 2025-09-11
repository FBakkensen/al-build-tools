#!/usr/bin/env python3

import json
import sys

def check_duplicate_keys(pairs):
    """Check for duplicate keys in JSON object."""
    keys_seen = set()
    for key, value in pairs:
        if key in keys_seen:
            return True  # Duplicate found
        keys_seen.add(key)
    return False

def main():
    if len(sys.argv) != 2:
        print("Usage: python json_dup_key_check.py <json_file>")
        sys.exit(1)

    file_path = sys.argv[1]

    try:
        with open(file_path, 'r') as f:
            # Use object_pairs_hook to detect duplicates
            data = json.load(f, object_pairs_hook=lambda pairs: pairs)

        # Check for duplicates
        if check_duplicate_keys(data):
            print(f"Duplicate keys found in {file_path}")
            sys.exit(1)
        else:
            print(f"No duplicate keys in {file_path}")
            sys.exit(0)

    except json.JSONDecodeError as e:
        print(f"Invalid JSON in {file_path}: {e}")
        sys.exit(1)
    except FileNotFoundError:
        print(f"File not found: {file_path}")
        sys.exit(1)

if __name__ == "__main__":
    main()