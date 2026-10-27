"""Virtual Piano parser and cyclic any-key stepper; no playback timer."""
from dataclasses import dataclass
import re
from input_manager import build_bindings

DEMO_SHEET = (
    "6 [er] [er] 3 [er] [er] 6 [er] [er] [wt] 8 [wt] [wt] [qe] 8 [qe] [qe] "
    "6 [er] [er] 3 [er] [er] 6 [er] [er] [wt] 8 [wt] [wt] [qe] 8 [qe] [qe]"
)


@dataclass(frozen=True)
class Step:
    notes: tuple[int, ...]
    transposition: int | None = None


@dataclass(frozen=True)
class Sheet:
    steps: tuple[Step, ...]
    transposition: int | None = None


class SheetParser:
    def __init__(self):
        self.mapping = {b.label: b.midi for b in build_bindings()}

    def parse(self, text):
        steps = []
        transpose = None
        initial = None
        chord = None
        for line in text.replace("\r", "").splitlines():
            directive = re.fullmatch(r"\s*Transposition\s*:\s*([+-]?\d+)\s*", line, re.I)
            if directive:
                transpose = max(-87, min(87, int(directive[1])))
                if not steps:
                    initial = transpose
                continue
            stripped = line.strip()
            if (re.match(r"^(title|song|artist|by|título|canción|autor)\s*:", stripped, re.I)
                    or stripped.startswith(("#", "//"))
                    or ("[" not in line and len(stripped.split()) >= 2
                        and stripped.istitle() and any(len(w) >= 3 for w in stripped.split())
                        and not any(c.isdigit() for c in stripped))):
                continue
            for char in line:
                if char == "[":
                    if chord:
                        steps.append(Step(tuple(dict.fromkeys(chord)), transpose))
                    chord = []
                elif char == "]":
                    if chord:
                        steps.append(Step(tuple(dict.fromkeys(chord)), transpose))
                    chord = None
                elif char in self.mapping and char != "(":
                    if chord is not None:
                        chord.append(self.mapping[char])
                    else:
                        steps.append(Step((self.mapping[char],), transpose))
        if chord:
            steps.append(Step(tuple(dict.fromkeys(chord)), transpose))
        return Sheet(tuple(steps), initial)


class AutoStepper:
    def __init__(self):
        self.sheet = Sheet(())
        self.index = 0

    def load(self, text):
        self.sheet = SheetParser().parse(text)
        self.index = 0
        return self.sheet

    def next_step(self):
        if not self.sheet.steps:
            return None
        step = self.sheet.steps[self.index]
        self.index = (self.index + 1) % len(self.sheet.steps)
        return step
