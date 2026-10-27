# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

"""Review this specific 576x1024 piano-roll video and group attacks for Auto.

The visual calibration is specific to the supplied video, not a general converter.
The audio transcription remains archived unchanged.
"""
import argparse
import json
from pathlib import Path
import subprocess
import numpy as np

def group_attacks(notes, tolerance):
    """Anchor windows to their FIRST attack, never chain an entire arpeggio."""
    groups = []
    for note in sorted(notes, key=lambda n: (n["start"], n["pitch"])):
        if not groups or note["start"] - groups[-1][0]["start"] > tolerance:
            groups.append([])
        groups[-1].append(note)
    return groups

def export_version(output, name, notes, tolerance, max_notes=6):
    import pretty_midi
    midi = pretty_midi.PrettyMIDI(initial_tempo=120, resolution=960)
    piano = pretty_midi.Instrument(program=0, name="Piano para Auto")
    groups = group_attacks(notes, tolerance)
    lines = ["# WhatsApp piano · " + name,
             "# Transcripción automática aproximada, contrastada con el vídeo.",
             f"# Agrupación de ataques: {round(tolerance * 1000)} ms; máximo {max_notes} notas/paso.",
             "# Auto: tú marcas el ritmo. Hay simplificación, no es una partitura exacta."]
    chords = 0
    dropped = 0
    exported = []
    for group in groups:
        pitches = {}
        for note in group:
            p = note["pitch"]
            if p not in pitches or note["confidence"] > pitches[p]["confidence"]:
                pitches[p] = note
        if len(pitches) > max_notes:
            # Preserve bass and top melody, then the most confident inner voices.
            ordered = sorted(pitches)
            selected = [ordered[0], ordered[-1]]
            selected += sorted(ordered[1:-1], key=lambda p: pitches[p]["confidence"], reverse=True)[:max_notes - 2]
            dropped += len(pitches) - len(selected)
            pitches = {p: pitches[p] for p in selected}
        start = round(group[0]["start"] * 1920) / 1920
        chord = sorted(pitches)
        chords += len(chord) > 1
        exported.append(chord)
        labels = [pretty_midi.note_number_to_name(p) for p in chord]
        lines.append("MIDI: " + " ".join(map(str, chord)) + f" # {start:.2f}s · " + " ".join(labels))
        for pitch in chord:
            note = pitches[pitch]
            end = max(start + .10, note["end"])
            piano.notes.append(pretty_midi.Note(velocity=88, pitch=pitch, start=start, end=end))
    # Avoid overlaps of the same pitch in exported MIDI players.
    for pitch in range(21, 109):
        same = sorted((n for n in piano.notes if n.pitch == pitch), key=lambda n: n.start)
        for a, b in zip(same, same[1:]):
            a.end = min(a.end, b.start)
    midi.instruments.append(piano)
    midi.write(str(output / (name + ".mid")))
    (output / (name + ".txt")).write_text("\n".join(lines) + "\n", encoding="utf-8")
    stats = dict(steps=len(groups), chords=chords, solo_steps=len(groups)-chords,
                 max_notes=max(map(len, exported)), capped_notes=dropped,
                 notes=sum(map(len, exported)), window_ms=round(tolerance*1000))
    print(name, stats, flush=True)
    return stats

def visual_activity(source, output, profile="portrait"):
    cache = output / "visual-activity.npy"
    if cache.exists():
        return np.load(cache)
    width, height = (1024 if profile == "landscape" else 576), 10
    scan_y = 420 if profile == "landscape" else 770
    whites = [p for p in range(21, 109) if p % 12 not in [1, 3, 6, 8, 10]]
    centers = {}
    for p in range(21, 109):
        if p in whites:
            centers[p] = (whites.index(p) + 0.5) * width / 52
        else:
            centers[p] = (whites.index(p - 1) + 1) * width / 52
    process = subprocess.Popen(["ffmpeg", "-v", "error", "-threads", "2", "-i", str(source),
        "-an", "-vf", f"fps=30,crop={width}:10:0:{scan_y}", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"], stdout=subprocess.PIPE)
    rows = []
    while True:
        frame = process.stdout.read(width * height * 3)
        if not frame:
            break
        if len(frame) != width * height * 3:
            raise ValueError("Incomplete video frame")
        rgb = np.frombuffer(frame, dtype=np.uint8).reshape(height, width, 3).astype(float)
        r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
        warm = (r > 55) & (r > g * 1.12) & (r > b * 1.5) & (r - b > 30)
        if profile == "landscape":
            warm = ((g > 65) & (g - r > 20) & (g - b > 15)) | ((b > 80) & (b - g > 25) & (b - r > 15))
        rows.append([warm[:, max(0, round(centers[p]) - 1):round(centers[p]) + 2].mean() > .22 for p in range(21, 109)])
    if process.wait() != 0:
        raise RuntimeError("Video decoding failed")
    activity = np.array(rows)
    np.save(cache, activity)
    return activity

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--profile", choices=["portrait", "landscape"], default="portrait")
    args = parser.parse_args()
    activity = visual_activity(args.source, args.output, args.profile)
    for t in [15, 30, 90]:
        print(t, "visual pitches", (np.where(activity[round(t * 30)])[0] + 21).tolist(), flush=True)
    raw_path = args.output / "raw-notes.json"
    if not raw_path.exists():
        return
    raw = json.loads(raw_path.read_text())
    supported = []
    rejected = []
    for note in raw:
        start = max(0, int((note["start"] - .22) * 30))
        end = min(len(activity), int((note["start"] + .22) * 30) + 1)
        support = float(activity[start:end, note["pitch"] - 21].mean()) if end > start else 0
        note["visual_support"] = support
        (supported if support >= .15 else rejected).append(note)
    print("Raw", len(raw), "supported", len(supported), "rejected", len(rejected), flush=True)
    (args.output / "supported-notes.json").write_text(json.dumps(supported, indent=2))
    (args.output / "review-rejected.json").write_text(json.dumps(rejected, indent=2))
    clean = [n for n in supported if n["confidence"] >= .35]
    stats = {"visual_profile": args.profile, "source_notes": len(raw), "visually_supported": len(supported),
             "retained_notes": len(clean), "visual_rejected": len(rejected)}
    stats["auto-acordes"] = export_version(args.output, "auto-acordes", clean, .085)
    stats["auto-facil"] = export_version(args.output, "auto-facil", clean, .180)
    (args.output / "report.json").write_text(json.dumps(stats, indent=2))

if __name__ == "__main__":
    main()
