"""Training data for a Muon-specific Needle (see README › Needle).

    node scripts/needle-tools.mjs > tools.json          # Muon's tool schemas from the tool server
    python3 scripts/needle-data.py tools.json           # -> train.jsonl / val.jsonl (templates + your own learned routes)
    ~/.muon/needle/bin/needle finetune train.jsonl --epochs 2 --batch-size 8 --max-len 2048 --out muon_lora.safetensors
    ~/.muon/needle/bin/needle build checkpoints/needle3.safetensors --lora muon_lora.safetensors --out muon.cact
    NEEDLE_WEIGHTS=muon.cact ~/.muon/needle/bin/python scripts/needle-serve.py

One JSONL example = request -> tool call, or answers [] when Muon's other layers should answer (writing, cleanup, small talk).
Your own successful routes (Muon's learned memory) are included; edit HELD_OUT to keep test requests out of training.
"""
import sys
import json, random, re, sqlite3, os, itertools
random.seed(7)
NAMES = ["openApplication","openPath","revealInFinder","quitApplication","findFiles","searchFiles","searchCode","readFile","listDirectory",
         "listProjects","listRunningApps","getSystemStats","webSearch","openInBrowser","largestFiles","findDuplicates","listDevices","jobStatus","listMenus"]
raw = {t["name"]: t for t in json.load(open(sys.argv[1] if len(sys.argv) > 1 else "tools.json"))}
TOOLS = [{"name": n, "description": raw[n]["description"][:300], "parameters": raw[n]["inputSchema"]} for n in NAMES]

apps = ["Xcode","Safari","Slack","Spotify","Notes","Terminal","Finder","Visual Studio Code","Chrome","Music","Messages","Mail","Calendar","Preview","Figma","Discord","Zoom","Notion","Photos","Reminders","Numbers","Pages"]
folders = ["~/Downloads","~/Documents","~/Desktop","~/Projects","~/Work","~/Documents/Receipts","~/Downloads/Archive","~/Projects/weather-app","~/Work/portfolio","~/Desktop/Screenshots"]
folder_words = {"downloads":"~/Downloads","documents":"~/Documents","desktop":"~/Desktop","projects":"~/Projects","work":"~/Work","my downloads folder":"~/Downloads","the desktop":"~/Desktop"}
files = ["package.json","README.md","index.ts","App.tsx","report.pdf","lease.pdf","invoice.pdf","notes.txt","budget.csv","main.swift","Podfile","config.yml","resume.docx","todo.md"]
projects = ["weather-app","portfolio","todo-app","shop-api","blog","muon","recipe-book"]
topics = ["the tallest mountain","the capital of Japan","react native","swift concurrency","typescript generics","python asyncio","the weather in Pune","who won the last world cup","how many grams in an ounce","what is a muon","the population of Chennai","sqlite vacuum","the speed of light","best pizza dough recipe"]
kinds = ["pdfs","invoices","screenshots","photos","spreadsheets","presentations","videos","zip files","word documents","receipts"]
about = ["tax","the lease","insurance","flight tickets","the kathak recital","budget","the wedding","salary","gst","design"]
patterns = ["TODO","FIXME","console.log","useEffect","fetch(","import React","async def","try {","print(","@Test","NSLog","dispatch_async"]
urls = ["youtube.com","github.com","gmail.com","twitter.com","news.ycombinator.com","apple.com/mac","reddit.com/r/swift","linkedin.com"]
menus_apps = ["Safari","Notes","Xcode","Finder","Preview","Mail","Numbers"]

def T(tool, q, **args): return {"query": q, "tools": TOOLS, "answers": [{"name": tool, "arguments": args}]}
def R(q): return {"query": q, "tools": TOOLS, "answers": []}
ex = []
pick = lambda xs, k: random.sample(xs, min(k, len(xs)))

for a in apps:
    for f in pick(["open {a}","launch {a}","start {a}","switch to {a}","bring up {a}","can you open {a}","{a} please","go to {a}","open up {a}","show me {a}"], 4): ex.append(T("openApplication", f.format(a=a), name=a))
    for f in pick(["quit {a}","close {a}","kill {a}","exit {a}","shut {a} down","stop {a}","quit {a} please","close {a} for me"], 3): ex.append(T("quitApplication", f.format(a=a), name=a))
for a in menus_apps:
    for f in pick(["what menus does {a} have","list {a}'s menu commands","what can I do in {a}","show the menu items of {a}","what functions does {a} offer","which commands does {a} have"], 3): ex.append(T("listMenus", f.format(a=a), app=a))
for fo in folders:
    for f in pick(["what is inside {p}","list {p}","show me {p}","what's in {p}","contents of {p}","open the list of {p}","ls {p}","what do I have in {p}"], 3): ex.append(T("listDirectory", f.format(p=fo), path=fo))
    for f in pick(["what's taking space in {p}","what is taking space in {p}","biggest files in {p}","largest files in {p}","what is eating disk in {p}","show the largest files under {p}","free up space in {p}"], 3): ex.append(T("largestFiles", f.format(p=fo), path=fo))
    for f in pick(["find duplicate files in {p}","find duplicates in {p}","are there duplicate files in {p}","duplicate files under {p}","which files are duplicated in {p}"], 2): ex.append(T("findDuplicates", f.format(p=fo), path=fo))
    for f in pick(["reveal {p} in finder","show {p} in finder","open {p} in finder","reveal {p}"], 2): ex.append(T("revealInFinder", f.format(p=fo), path=fo))
for w, p in folder_words.items():
    ex.append(T("listDirectory", f"what is inside {w}", path=p)); ex.append(T("largestFiles", f"what's taking space in {w}", path=p)); ex.append(T("findDuplicates", f"find duplicate files in {w}", path=p))
for fi in files:
    fo = random.choice(folders)
    for f in pick(["read {fo}/{fi}","show me {fo}/{fi}","cat {fo}/{fi}","what does {fo}/{fi} contain","print {fo}/{fi}","open the contents of {fo}/{fi}"], 2): ex.append(T("readFile", f.format(fo=fo, fi=fi), path=f"{fo}/{fi}"))
    ex.append(T("openPath", random.choice(["open {fo}/{fi}","open the file {fo}/{fi}","launch {fo}/{fi}"]).format(fo=fo, fi=fi), path=f"{fo}/{fi}"))
    pr = random.choice(projects)
    for f in pick(["where is {fi} in {pr}","find {fi} in {pr}","locate {fi} inside {pr}","which folder has {fi} in {pr}","look for {fi} in {pr}"], 2): ex.append(T("findFiles", f.format(fi=fi, pr=pr), name=fi, scope=pr))
    for f in pick(["find {fi}","where is {fi}","locate {fi}","search for a file named {fi}"], 1): ex.append(T("findFiles", f.format(fi=fi), name=fi))
for k in kinds:
    for ab in pick(about, 2):
        for f in pick(["find {k} about {ab}","search {k} about {ab}","look for {k} related to {ab}","{k} about {ab}","show me {k} mentioning {ab}"], 2): ex.append(T("searchFiles", f.format(k=k, ab=ab), query=f"{k} {ab}"))
for pa in patterns:
    pr = random.choice(projects); fo = random.choice(folders)
    for f in pick(["search code for {pa} in {pr}","grep {pa} in {pr}","find {pa} in the code of {pr}","where do I use {pa} in {pr}","look for {pa} across {pr}"], 2): ex.append(T("searchCode", f.format(pa=pa, pr=pr), pattern=pa, scope=pr))
    ex.append(T("searchCode", f"search code for {pa} in {fo}", pattern=pa, scope=fo))
for t in topics:
    for f in pick(["search for {t}","google {t}","what is {t}","look up {t}","search the web for {t}","tell me about {t}","who is {t}" if t.startswith("who") else "what's {t}"], 3): ex.append(T("webSearch", f.format(t=t), query=t))
for u in urls:
    for f in pick(["open {u}","go to {u}","open {u} in the browser","take me to {u}","browse to {u}"], 2): ex.append(T("openInBrowser", f.format(u=u), url=u))
for t in pick(topics, 6): ex.append(T("openInBrowser", f"open a web search for {t}", query=t))
for q in ["show my projects","list my projects","what projects do I have","which projects are in my work folder","my projects","list projects","what am I working on"]: ex.append(T("listProjects", q))
for q in ["which apps are using the most memory","what is using my memory","memory hogs","which app uses the most ram","show running apps by memory","what apps are running","top apps by ram","which apps are open"]: ex.append(T("listRunningApps", q))
for q in ["is my mac hot","how much disk space is free","how is my mac doing","what's my battery","is my cpu busy","free ram","system stats","how much memory is free","is the mac overheating","how full is my disk","battery percentage","cpu load"]: ex.append(T("getSystemStats", q))
for q in ["which simulators do I have","list my simulators","what devices can I run on","which android emulators are there","show connected devices","do I have an iphone simulator","list devices","which emulators are installed"]: ex.append(T("listDevices", q))
for q in ["is my build done","job status","how is the build going","did the build finish","status of my background jobs","is the release build finished","any jobs running","build status"]: ex.append(T("jobStatus", q))
# hand back: small talk, writing, cleanup and anything Muon's other layers answer
for q in ["hi","hello","hey there","thanks","thank you","how are you","good morning","what can you do","help","who are you","explain this","fix grammar","summarize this","make this professional","translate this","reply saying I'll be there at 5","draft an email about the delayed shipment","undo","save macro morning","what's the largest transaction","analyse this statement","meeting notes from ~/Downloads/standup.mp4","total the receipts in ~/Documents/Receipts","move the screenshots in ~/Downloads into ~/Downloads/Archive","trash zips in downloads older than 30 days","archive the pdfs on my desktop","rename my screenshots","every monday move the screenshots in ~/Downloads older than 30 days into ~/Downloads/Archive","run weather-app on iPhone 17","commit this","push","clean the metro caches","start claude code for weather-app","in safari open a new private window","read the latest screenshot","explain the error in this screenshot","what does ~/Documents/lease.pdf say about the deposit","write a poem","tell me a joke","what time is it","set a timer for 5 minutes","play some music","call mom","asdfgh","??"]:
    ex.append(R(q))
# Muon's own learned routes (real requests)
db = os.path.expanduser("~/Library/Application Support/Muon/memory.db")
for key, tool, args in sqlite3.connect(db).execute("select key, tool, args_json from intent_cache"):
    if tool in NAMES: ex.append(T(tool, key, **json.loads(args)))
# keep your evaluation honest: requests listed here (one per line in held_out.txt, if present) never enter training
HELD_OUT = "held_out.txt"
held = {l.strip().lower() for l in open(HELD_OUT)} if os.path.exists(HELD_OUT) else set()
seen = set(); out = []
for e in ex:
    k = e["query"].lower().strip()
    if k in held or k in seen: continue
    seen.add(k); out.append(e)
random.shuffle(out)
n_val = max(40, len(out) // 10)
with open("val.jsonl", "w") as f:
    for e in out[:n_val]: f.write(json.dumps(e) + "\n")
with open("train.jsonl", "w") as f:
    for e in out[n_val:]: f.write(json.dumps(e) + "\n")
from collections import Counter
c = Counter(e["answers"][0]["name"] if e["answers"] else "(hand back)" for e in out)
print(f"train {len(out)-n_val}  val {n_val}  held-out benchmark queries excluded {len(held)}")
print(", ".join(f"{k} {v}" for k, v in c.most_common()))
