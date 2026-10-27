# SwiftPiano
# Copyright (c) 2026 Sebastián Zambrano
# Distributed under the terms of the MIT License.

"""Extract the user's Letras PDF using its heading typography and outline.

Requires Poppler only. Prints JSON; no PDF dependency is needed by the game.
"""
import json
import subprocess
import sys
import xml.etree.ElementTree as ET


def extract(path):
    root = ET.fromstring(subprocess.check_output(["pdftohtml", "-xml", "-stdout", path]))
    fonts = {f.get("id"): float(f.get("size")) for f in root.iter("fontspec")}
    songs = []
    outline = [" ".join("".join(x.itertext()).split()) for x in root.findall("outline/item")]
    primary = []
    current = None
    for page in root.findall("page"):
        number = int(page.get("number"))
        for line in page.findall("text"):
            text = "".join(line.itertext()).strip().replace("\u200b", "")
            if not text:
                continue
            heading = fonts[line.get("font")] >= 20 and not text.lower().startswith("transpose")
            if heading:
                continuation = current and not current["lines"] and any(
                    title.startswith(current["title"] + " " + text) for title in outline)
                if continuation:
                    current["title"] += " " + text
                    if fonts[line.get("font")] >= 30:
                        primary[-1] = current["title"]
                else:
                    current = {"id": "letras-%03d" % (len(songs) + 1),
                               "title": text, "page": number, "end_page": number, "lines": []}
                    songs.append(current)
                    if fonts[line.get("font")] >= 30:
                        primary.append(text)
            elif current:
                current["lines"].append(text)
                current["end_page"] = number
    assert primary == outline, "Heading/outline mismatch: inspect PDF"
    for song in songs:
        song["sheet"] = "\n".join(song.pop("lines"))
        song["has_sheet"] = bool(song["sheet"])
    return {"source": "Letras.pdf", "pages": len(root.findall("page")), "songs": songs}


if __name__ == "__main__":
    print(json.dumps(extract(sys.argv[1]), ensure_ascii=False, indent=2))
