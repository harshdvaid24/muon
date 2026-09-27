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

# ---- v2: inputs for the intelligence demo (writing, screenshots, documents, receipts, localization, audio) ----
python3 - "$D" <<'PY'
import sys, os, json
from PIL import Image, ImageDraw, ImageFont
D=sys.argv[1]
def font(sz, mono=False):
    for p in (["/System/Library/Fonts/Menlo.ttc"] if mono else ["/System/Library/Fonts/SFNS.ttf","/System/Library/Fonts/Helvetica.ttc"]):
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()
os.makedirs(f"{D}/Receipts", exist_ok=True); os.makedirs(f"{D}/weather-app/locales", exist_ok=True); os.makedirs(f"{D}/Inbox", exist_ok=True)
# error screenshot (dark terminal look)
im=Image.new("RGB",(1200,420),(24,26,32)); d=ImageDraw.Draw(im); f=font(22,True)
lines=["> npx react-native run-ios","error Failed to build iOS project. \"xcodebuild\" exited with error code 65.",
       "The following build commands failed:","    CompileC Forecast.o Forecast.tsx",
       "error: Cannot find module 'react-native-reanimated' (Forecast.tsx:3)","  Did you forget to run 'pod install' after adding it?"]
for i,l in enumerate(lines): d.text((30,30+i*58),l,font=f,fill=(255,120,120) if "error" in l.lower() else (220,222,228))
im.save(f"{D}/Screenshot 2026-09-27 at 09.41.12.png")
# scanned PDF (image-only pages → exercises OCR)
def page(text, path):
    im=Image.new("RGB",(1240,1600),(252,250,244)); d=ImageDraw.Draw(im); y=110
    for l in text.split("\n"):
        d.text((110,y),l,font=font(30 if not l.isupper() else 40),fill=(30,30,30)); y+=52
    im.save(path,"PDF",resolution=120)
page("""RENTAL AGREEMENT
Between: Sunrise Properties (Landlord) and Priya Nair (Tenant)
Premises: Flat 4B, Lotus Residency, Pune 411045
Term: 11 months starting 1 October 2026

1. Rent is INR 32,000 per month, due on the 5th.
2. Security deposit is INR 96,000, refundable within
   30 days of vacating, less repair costs.
3. Either party may end the agreement with 60 days'
   written notice.
4. Pets are allowed with prior written consent.
5. Maintenance charges of INR 2,500 per month are
   paid by the tenant.
6. Late rent attracts a fee of INR 500 per day.""", f"{D}/lease.pdf")
# receipts
for i,(m,dt,items,tot) in enumerate([("BLUE TOKAI COFFEE","2026-09-03",[("Cappuccino","240.00"),("Croissant","180.00")],"420.00"),
                                      ("UBER","2026-09-05",[("Trip Koregaon Park → Airport","1,150.00")],"1,150.00"),
                                      ("DMART","2026-09-07",[("Groceries","2,314.50"),("Bag","5.00")],"2,319.50")]):
    im=Image.new("RGB",(700,760),(255,255,255)); d=ImageDraw.Draw(im); y=40
    d.text((60,y),m,font=font(40),fill=(0,0,0)); y+=70; d.text((60,y),f"Date: {dt}",font=font(26),fill=(40,40,40)); y+=60
    for n,p in items: d.text((60,y),n,font=font(26),fill=(40,40,40)); d.text((520,y),p,font=font(26),fill=(40,40,40)); y+=44
    y+=30; d.text((60,y),"TOTAL",font=font(34),fill=(0,0,0)); d.text((480,y),f"INR {tot}",font=font(34),fill=(0,0,0)); y+=70
    d.text((60,y),"Paid by card. Thank you!",font=font(24),fill=(90,90,90))
    im.save(f"{D}/Receipts/receipt-{i+1}.png")
# localization source
json.dump({"greeting":"Welcome back, {name}!","forecast":{"title":"Today's forecast","rain":"Rain expected at {time}","empty":"No data yet"},
           "buttons":{"refresh":"Refresh","settings":"Settings","share":"Share forecast"},"errors":{"offline":"You're offline. Showing the last forecast."}},
          open(f"{D}/weather-app/locales/en.json","w"),indent=2,ensure_ascii=False)
# inbox text + error log
open(f"{D}/Inbox/client-email.txt","w").write("""hey, so we looked at the proposal and honestly its a bit more then what we planned to spend this quarter. can you maybe cut the scope down a little, like drop the analytics dashboard for now, and send a revised quote by friday? also our cto wants to know if the data stays in india. thanks""")
open(f"{D}/Inbox/error.log","w").write("""TypeError: Cannot read properties of undefined (reading 'map')
    at Forecast (src/screens/Forecast.tsx:12:5)
    at renderWithHooks (node_modules/react/cjs/react-dom.development.js:16305:18)
    at mountIndeterminateComponent (node_modules/react/cjs/react-dom.development.js:20074:13)""")
print("v2 demo inputs written")
PY
say -o "$D/Inbox/standup.aiff" "Quick standup. Yesterday I finished the offline banner and fixed the forecast crash. Today I am adding the Hindi and Gujarati translations. We decided to ship version one point five on Friday. Action item: Priya will update the App Store screenshots, and I will write the release notes."
echo "Demo workspace v2 ready"
