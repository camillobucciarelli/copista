#!/bin/bash
# Compila ed esegue i test della logica pura (Storico e regole delle scorciatoie).
# Uso: ./test.sh
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
swiftc -swift-version 5 Sources/HistoryStore.swift Sources/Shortcuts.swift Sources/L10n.swift Tests/main.swift -o build/copista-tests
build/copista-tests
