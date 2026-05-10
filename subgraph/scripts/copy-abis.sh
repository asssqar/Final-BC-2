#!/usr/bin/env bash
# Copy ABIs from the forge build into ./abis/ for the subgraph.
# Run this AFTER `forge build` in ../contracts/.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/../contracts/out"
DEST="$ROOT/abis"

mkdir -p "$DEST"

declare -A MAP=(
    [GameItems]="GameItems.sol/GameItems.json"
    [ResourceAMM]="ResourceAMM.sol/ResourceAMM.json"
    [GameGovernor]="GameGovernor.sol/GameGovernor.json"
    [LootBox]="LootBox.sol/LootBox.json"
)

for name in "${!MAP[@]}"; do
    src="$OUT/${MAP[$name]}"
    if [ ! -f "$src" ]; then
        echo "Missing $src — run 'forge build' in ../contracts first" >&2
        exit 1
    fi
    # Forge writes the full artifact; the subgraph wants just the .abi array.
    jq '.abi' "$src" > "$DEST/$name.json"
    echo "  ✓ $name -> $DEST/$name.json"
done
