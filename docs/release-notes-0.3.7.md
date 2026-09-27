# Muon 0.3.7: Needle toggle

- **Settings › Needle (experimental).** [Needle 3](https://github.com/cactus-compute/needle), a 29 MB tool-calling model, can decide simple requests in about 50 ms instead of ~1.2 s on-device. Off by default: on seventeen everyday requests the on-device model was right 16 times at a median 1.9 s; Needle-first was right 8 times at a median 0.6 s (wrong calls came at 90%+ confidence). When on, it acts only at 90%+ confidence and never on tools that move or delete files; otherwise the request goes to the on-device model with a note saying why. The footer names who answered. Server: `scripts/needle-serve.py` (works around the engine wheel missing from Hugging Face for cactus-needle 3.0.5).
- `MUON_NO_CACHE=1` on the command line skips the intent cache, for fair comparisons.

Everything in [0.3.6](https://github.com/harshdvaid24/muon/releases/tag/v0.3.6) applies.
