#!/bin/zsh
# Runs read-only fixture queries through the CLI and prints tier + latency per query.
cd "$(dirname "$0")/.."
BIN=build/DerivedData/Build/Products/Debug/Muon.app/Contents/MacOS/Muon
Q=(
  "list my projects" "what's using the most memory" "how much disk space is free" "find package.json in portfolio"
  "search code for FirebaseApp.configure" "find pdfs downloaded this week" "show running apps" "list projects"
  "what is inside ~/Downloads" "find files named Muon" "which apps use the most ram" "show system stats"
  "find all screenshots" "search for useEffect in weather-app" "list my projects" "how much disk space is free"
  "show running apps" "find package.json in portfolio" "what's using the most memory" "search code for FirebaseApp.configure"
)
printf "%-45s %-5s %s\n" QUERY TIER MS
for q in "${Q[@]}"; do
  line=$("$BIN" --query "$q" 2>/dev/null | grep -E "^tier=" | head -1)
  printf "%-45s %-5s %s\n" "$q" "${${line#tier=}%% *}" "${line##*ms=}"
done
