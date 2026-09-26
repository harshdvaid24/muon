#!/bin/zsh
# Relaunch the built app.
cd "$(dirname "$0")/.."
pkill -x MacAgent 2>/dev/null; sleep 0.3
open build/DerivedData/Build/Products/Debug/MacAgent.app && echo "MacAgent launched"
