import os
import json
import base64
import urllib.request
import re

NEW_PIANOS = {
    "steinway_grand": {
        "name": "Steinway Concert Grand",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/MusyngKite/acoustic_grand_piano-ogg.js"
    },
    "bright_piano": {
        "name": "Bright Acoustic Piano",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/bright_acoustic_piano-ogg.js"
    },
    "honkytonk_piano": {
        "name": "Honky-Tonk Saloon Piano",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/honkytonk_piano-ogg.js"
    },
    "electric_grand": {
        "name": "Yamaha CP-80 Electric Grand",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/electric_grand_piano-ogg.js"
    },
    "fm_piano": {
        "name": "DX7 FM Digital Piano",
        "url": "https://raw.githubusercontent.com/gleitz/midi-js-soundfonts/gh-pages/FluidR3_GM/electric_piano_2-ogg.js"
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

for inst_id, info in NEW_PIANOS.items():
    out_dir = f"assets/instruments/{inst_id}"
    os.makedirs(out_dir, exist_ok=True)
    print(f"Downloading {info['name']} from {info['url']}...")
    try:
        req = urllib.request.Request(info['url'], headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as resp:
            content = resp.read().decode('utf-8')
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
            else:
                print(f"Warning: note {sf_name} not found in {inst_id}")
        print(f"-> Successfully saved {saved} notes for {inst_id}")
    except Exception as e:
        print(f"Error processing {inst_id}: {e}")

print("All new pianos downloaded successfully!")
