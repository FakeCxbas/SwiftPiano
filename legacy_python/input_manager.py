"""Physical bindings and source-owned note lifetimes."""
from dataclasses import dataclass
import pygame

WHITE_BINDINGS = "1234567890qwertyuiopasdfghjklzxcvbnm"
BLACK_BINDINGS = "!@$%^*(QWETYIOPSDGHJLZCVB"
BLACK_CLASSES = {1, 3, 6, 8, 10}


@dataclass(frozen=True)
class KeyBinding:
    key: int
    midi: int
    label: str
    shifted: bool
    is_black: bool


def build_bindings():
    whites = [m for m in range(36, 97) if m % 12 not in BLACK_CLASSES]
    blacks = [m for m in range(36, 97) if m % 12 in BLACK_CLASSES]
    shift_digits = dict(zip("!@$%^*(", "1245689"))
    result = [KeyBinding(ord(c), m, c, False, False)
              for c, m in zip(WHITE_BINDINGS, whites, strict=True)]
    result += [KeyBinding(ord(shift_digits.get(c, c.lower())), m, c, True, True)
               for c, m in zip(BLACK_BINDINGS, blacks, strict=True)]
    return tuple(sorted(result, key=lambda b: b.midi))


class InputManager:
    def __init__(self):
        self.bindings = build_bindings()
        self.lookup = {(b.key, b.shifted): b.midi for b in self.bindings}
        self.pressed = set()
        self.sources = {}
        self.serial = 0

    def key_down(self, event):
        if event.key in self.pressed or getattr(event, "repeat", False):
            return False
        self.pressed.add(event.key)
        return True

    def key_up(self, key):
        self.pressed.discard(key)

    @staticmethod
    def is_step_key(key):
        return pygame.K_a <= key <= pygame.K_z or pygame.K_0 <= key <= pygame.K_9

    def manual_note(self, event):
        return self.lookup.get((event.key, bool(event.mod & pygame.KMOD_SHIFT)))

    def press(self, source, notes, transpose=0):
        """Capture pitches on keydown; keyup never recomputes pitches."""
        if source in self.sources:
            return []
        voices = []
        for midi in dict.fromkeys(notes):
            pitch = midi + transpose
            if 21 <= pitch <= 108:
                self.serial += 1
                voices.append((self.serial, pitch))
        self.sources[source] = voices
        return voices

    def release(self, source):
        return self.sources.pop(source, [])

    def release_all(self):
        voices = [v for group in self.sources.values() for v in group]
        self.sources.clear()
        self.pressed.clear()
        return voices
