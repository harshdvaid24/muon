#!/bin/zsh
# Creates ~/Documents/MuonDemo: a neutral workspace to try (and record) Muon's workflows.
# Safe to re-run; it only ever touches ~/Documents/MuonDemo.
set -e
D="$HOME/Documents/MuonDemo"
rm -rf "$D"; mkdir -p "$D"/weather-app/src/{api,screens} "$D"/notes-api "$D"/Downloads/Archive

cat > "$D/weather-app/package.json" <<'JSON'
{ "name": "weather-app", "version": "1.4.0",
  "dependencies": { "react": "19.1.0", "react-native": "0.81.0", "@react-native-firebase/app": "22.2.0", "@react-native-firebase/analytics": "22.2.0" } }
JSON
cat > "$D/weather-app/src/App.tsx" <<'TS'
import React from 'react';
import { Forecast } from './screens/Forecast';

export default function App() {
  // TODO: add offline banner when the network is unreachable
  return <Forecast city="Pune" />;
}
TS
cat > "$D/weather-app/src/api/weather.ts" <<'TS'
const BASE = 'https://api.example.com/v1';

export async function fetchForecast(city: string) {
  // FIXME: retry with backoff instead of failing on the first 503
  const res = await fetch(`${BASE}/forecast?city=${encodeURIComponent(city)}`);
  // TODO: cache the last successful response for 10 minutes
  return res.json();
}
TS
cat > "$D/weather-app/src/screens/Forecast.tsx" <<'TS'
import React from 'react';
import { FlatList, Text } from 'react-native';

export function Forecast({ city }: { city: string }) {
  // TODO: FlatList re-renders every row on scroll; memoize renderItem
  return <FlatList data={[]} renderItem={() => <Text>{city}</Text>} />;
}
TS
cat > "$D/notes-api/package.json" <<'JSON'
{ "name": "notes-api", "version": "0.3.1", "dependencies": { "express": "5.1.0" } }
JSON
cat > "$D/notes-api/server.js" <<'JS'
const express = require('express');
const app = express();
// TODO: validate request bodies before writing notes
app.post('/notes', (req, res) => res.status(201).end());
app.listen(3000);
JS

cd "$D/Downloads"
for i in 01 03 07 12 19; do head -c 180000 /dev/urandom > "Screenshot 2026-08-$i at 10.12.03.png"; done
head -c 5242880 /dev/urandom > "old-build.zip"; cp "old-build.zip" "old-build copy.zip"          # duplicate pair
head -c 2621440 /dev/urandom > "design-assets.zip"; cp "design-assets.zip" "design-assets (1).zip" # duplicate pair
head -c 18874368 /dev/urandom > "app-release-v1.2.apk"
head -c 44040192 /dev/urandom > "demo-recording.mov"
head -c 96000 /dev/urandom > "invoice-2026-08.pdf"
echo "Demo workspace ready at $D"
