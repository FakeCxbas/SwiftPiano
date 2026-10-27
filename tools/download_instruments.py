import os
import json
import base64
import urllib.request
import re

INSTRUMENTS = {
    "church_organ": {
        "name": "Church Organ",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/church_organ-ogg.js"
    },
    "synth_strings": {
        "name": "Synth Strings",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/synth_strings_1-ogg.js"
    },
    "celesta": {
        "name": "Celesta",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/celesta-ogg.js"
    },
    "harpsichord": {
        "name": "Harpsichord",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/harpsichord-ogg.js"
    }
}

NOTE_NAMES = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"]
FLAT_NAMES = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

def midi_to_sharp_name(midi):
    name = NOTE_NAMES[midi % 12]
    octave = int(midi / 12) - 1
    return f"{name}{octave}"

def midi_to_soundfont_name(midi):
    name = FLAT_NAMES[midi % 12]
    octave = int(midi / 12) - 1
    return f"{name}{octave}"

for inst_id, info in INSTRUMENTS.items():
    out_dir = f"assets/instruments/{inst_id}"
    os.makedirs(out_dir, exist_ok=True)
    print(f"Downloading {info['name']} from {info['url']}...")
    try:
        req = urllib.request.urlopen(info['url'])
        content = req.read().decode('utf-8')
        decl_idx = content.find('MIDI.Soundfont.')
        start = content.find('{', decl_idx)
        end = content.rfind('}') + 1
        clean_json = re.sub(r',\s*\}', '}', content[start:end])
        data = json.loads(clean_json)

        saved = 0
        for midi in range(21, 109, 3):
            sf_name = midi_to_soundfont_name(midi)
            sharp_name = midi_to_sharp_name(midi)
            if sf_name in data:
                raw_b64 = data[sf_name].split(',', 1)[1]
                ogg_bytes = base64.b64decode(raw_b64)
                out_path = f"{out_dir}/{sharp_name}.ogg"
                with open(out_path, "wb") as f:
                    f.write(ogg_bytes)
                saved += 1
        print(f"-> Saved {saved} notes for {inst_id}")
    except Exception as e:
        print(f"Error processing {inst_id}: {e}")

print("All instruments processed!")
