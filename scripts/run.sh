#!/bin/zsh
# Relaunch the built app.
cd "$(dirname "$0")/.."
pkill -x Muon 2>/dev/null; sleep 0.3
open build/DerivedData/Build/Products/Debug/Muon.app && echo "Muon launched"
