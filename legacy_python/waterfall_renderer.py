"""88-key geometry, rising bars, compact control panel and Auto text editor."""
from dataclasses import dataclass
import pygame
from input_manager import BLACK_CLASSES, build_bindings
from vfx_manager import VFXManager


@dataclass
class Bar:
    midi: int
    born: float
    released: float | None = None


class TextArea:
    def __init__(self, text):
        self.text = text
        self.cursor = len(text)
        self.anchor = self.cursor
        self.focus = False
        self.scroll = 0
        self.rect = pygame.Rect(0, 0, 1, 1)
        self.font = pygame.font.SysFont("DejaVu Sans Mono", 15)
        self.cell = self.font.size("M")[0]
        self.line_height = self.font.get_linesize()

    def blur(self):
        self.focus = False
        pygame.key.stop_text_input()

    def lines(self):
        cols = max(1, (self.rect.width - 16) // self.cell)
        lines = []
        start = 0
        for i, char in enumerate(self.text):
            if char == "\n":
                lines.append((start, i))
                start = i + 1
            elif i - start >= cols:
                lines.append((start, i))
                start = i
        lines.append((start, len(self.text)))
        return lines

    def locate_cursor(self):
        lines = self.lines()
        for row, (start, end) in enumerate(lines):
            if self.cursor <= end:
                return row, self.cursor - start
        return len(lines) - 1, 0

    def reveal(self):
        row, _ = self.locate_cursor()
        visible = max(1, (self.rect.height - 12) // self.line_height)
        self.scroll = max(0, min(self.scroll, row))
        if row >= self.scroll + visible:
            self.scroll = row - visible + 1

    def click(self, pos):
        self.focus = True
        pygame.key.start_text_input()
        pygame.key.set_text_input_rect(self.rect)
        lines = self.lines()
        row = max(0, min(len(lines) - 1, (pos[1] - self.rect.y - 6) // self.line_height + self.scroll))
        start, end = lines[row]
        self.cursor = min(end, start + max(0, round((pos[0] - self.rect.x - 8) / self.cell)))
        self.anchor = self.cursor

    def insert(self, text):
        a, b = sorted((self.cursor, self.anchor))
        text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\x00", "")
        self.text = self.text[:a] + text + self.text[b:]
        self.cursor = a + len(text)
        self.anchor = self.cursor
        self.reveal()

    def handle(self, event):
        """Return a short clipboard error for the floating window, if needed."""
        if event.type == pygame.TEXTINPUT:
            self.insert(event.text)
        elif event.type == pygame.KEYDOWN:
            ctrl = event.mod & pygame.KMOD_CTRL
            if ctrl and event.key == pygame.K_a:
                self.anchor, self.cursor = 0, len(self.text)
            elif ctrl and event.key in (pygame.K_v, pygame.K_c, pygame.K_x):
                try:
                    if event.key == pygame.K_v:
                        self.insert(pygame.scrap.get_text())
                    else:
                        a, b = sorted((self.anchor, self.cursor))
                        pygame.scrap.put_text(self.text[a:b])
                        if event.key == pygame.K_x:
                            self.insert("")
                except (pygame.error, OSError) as exc:
                    return f"Clipboard: {exc}"
            elif event.key in (pygame.K_BACKSPACE, pygame.K_DELETE):
                if self.cursor == self.anchor:
                    if event.key == pygame.K_BACKSPACE:
                        self.anchor = max(0, self.cursor - 1)
                    else:
                        self.anchor = min(len(self.text), self.cursor + 1)
                self.insert("")
            elif event.key == pygame.K_RETURN:
                self.insert("\n")
            elif event.key in (pygame.K_LEFT, pygame.K_RIGHT, pygame.K_HOME, pygame.K_END, pygame.K_UP, pygame.K_DOWN):
                if event.key in (pygame.K_LEFT, pygame.K_RIGHT):
                    self.cursor = max(0, min(len(self.text), self.cursor + (1 if event.key == pygame.K_RIGHT else -1)))
                else:
                    row, col = self.locate_cursor()
                    lines = self.lines()
                    if event.key in (pygame.K_UP, pygame.K_DOWN):
                        row = max(0, min(len(lines) - 1, row + (1 if event.key == pygame.K_DOWN else -1)))
                        self.cursor = min(lines[row][1], lines[row][0] + col)
                    else:
                        self.cursor = lines[row][0 if event.key == pygame.K_HOME else 1]
                if not event.mod & pygame.KMOD_SHIFT:
                    self.anchor = self.cursor
            self.reveal()
        return ""

    def draw(self, target):
        pygame.draw.rect(target, "white", self.rect)
        old_clip = target.get_clip()
        target.set_clip(self.rect.inflate(-8, -8))
        a, b = sorted((self.cursor, self.anchor))
        for row, (start, end) in enumerate(self.lines()):
            y = self.rect.y + 6 + (row - self.scroll) * self.line_height
            if y < self.rect.y - self.line_height or y > self.rect.bottom:
                continue
            if a < end and b > start:
                x = self.rect.x + 8 + (max(a, start) - start) * self.cell
                width = (min(b, end) - max(a, start)) * self.cell
                pygame.draw.rect(target, "#b8d9ff", (x, y, width, self.line_height))
            target.blit(self.font.render(self.text[start:end], True, "black"), (self.rect.x + 8, y))
        if self.focus and pygame.time.get_ticks() % 1000 < 600:
            row, col = self.locate_cursor()
            x = self.rect.x + 8 + col * self.cell
            y = self.rect.y + 6 + (row - self.scroll) * self.line_height
            pygame.draw.line(target, "black", (x, y), (x, y + self.line_height - 2))
        target.set_clip(old_clip)
        pygame.draw.rect(target, "#777777" if self.focus else "#333333", self.rect, 1)


class WaterfallRenderer:
    SPEED = 140.0

    def __init__(self, size):
        self.time = 0.0
        self.bars = {}
        self.released = []
        self.labels = {b.midi: b.label for b in build_bindings()}
        self.fonts = {}
        self.vfx = VFXManager()
        self.resize(size)

    def font(self, size):
        if size not in self.fonts:
            self.fonts[size] = pygame.font.SysFont("DejaVu Sans", size)
        return self.fonts[size]

    def resize(self, size):
        self.width, self.height = size
        self.top = round(self.height * .8)
        self.piano_width = round(self.width * .82)
        self.key_rects = {}
        white_width = self.piano_width / 52
        index = 0
        for midi in range(21, 109):
            if midi % 12 in BLACK_CLASSES:
                rect = pygame.Rect(round(index * white_width - .31 * white_width), self.top + 4,
                                   max(4, round(white_width * .62)), round((self.height - self.top - 4) * .63))
            else:
                x = round(index * white_width)
                rect = pygame.Rect(x, self.top + 4, round((index + 1) * white_width) - x,
                                   self.height - self.top - 4)
                index += 1
            self.key_rects[midi] = rect
        self.buttons = {}
        grid = [("qwerty", "volume"), ("auto", "sustain"), ("invert",),
                ("transpose", "velocity"), ("sheets", "synth")]
        left, width = self.piano_width + 4, self.width - self.piano_width - 8
        row_height = (self.height - self.top - 8) / len(grid)
        for row, names in enumerate(grid):
            for col, name in enumerate(names):
                self.buttons[name] = pygame.Rect(left + col * width / len(names), self.top + 4 + row * row_height,
                                                width / len(names) - 3, row_height - 3)
        w, h = min(490, self.width - 16), min(270, self.top - 16)
        self.popup = pygame.Rect(self.width - w - 8, self.top - h - 8, w, h)
        self.popup_buttons = {name: pygame.Rect(self.popup.x + 8 + i * (w - 16) / 4, self.popup.y + 8,
                                              (w - 16) / 4 - 4, 28)
                              for i, name in enumerate(("run", "clear", "88key", "exit"))}
        self.text_rect = pygame.Rect(self.popup.x + 8, self.popup.y + 44, w - 16, h - 72)

    def hit_key(self, pos):
        for black in (True, False):
            for midi, rect in self.key_rects.items():
                if (midi % 12 in BLACK_CLASSES) == black and rect.collidepoint(pos):
                    return midi
        return None

    def note_on(self, token, midi):
        self.bars[token] = Bar(midi, self.time)

    def note_off(self, token):
        bar = self.bars.pop(token, None)
        if bar:
            bar.released = self.time
            self.released.append(bar)

    def update(self, dt):
        self.time += dt
        self.released = [b for b in self.released if self.top - self.SPEED * (self.time - b.released) > -20]

    def bar_rect(self, bar):
        key = self.key_rects[bar.midi]
        end = self.time if bar.released is None else bar.released
        width = max(5, round(key.width * .78))
        bottom = self.top - self.SPEED * (self.time - end)
        height = max(width, self.SPEED * (end - bar.born))
        return pygame.Rect(key.centerx - width // 2, round(bottom - height), width, round(height))

    def button(self, target, rect, label, active=False):
        pygame.draw.rect(target, "#1e1e1e", rect)
        pygame.draw.rect(target, "#333333", rect, 1)
        size = min(13, max(9, rect.height - 8))
        while size > 7 and self.font(size).size(label)[0] > rect.width - (16 if active else 8):
            size -= 1
        text = self.font(size).render(label, True, "white")
        target.blit(text, text.get_rect(center=rect.center))
        if active:
            pygame.draw.rect(target, "#62ff00", (rect.right - 6, rect.y + 4, 3, rect.height - 8))

    def draw(self, target, app):
        target.fill("#050505")
        target.set_clip(pygame.Rect(0, 0, self.width, self.top))
        if app.synth:
            color = VFXManager.rainbow(self.time)
            self.vfx.draw_bars(target, [self.bar_rect(bar) for bar in [*self.released, *self.bars.values()]], color)
        target.set_clip(None)
        active = {bar.midi for bar in self.bars.values()}
        for black in (False, True):
            for midi, rect in self.key_rects.items():
                if (midi % 12 in BLACK_CLASSES) != black:
                    continue
                fill = ("#3d3d3d" if black else "#b0b0b0") if midi in active else ("#101010" if black else "#f5f5f5")
                pygame.draw.rect(target, fill, rect)
                pygame.draw.rect(target, "#000000" if black else "#555555", rect, 1)
                if app.qwerty and midi in self.labels:
                    text = self.font(max(8, min(12, rect.width - 3))).render(self.labels[midi], True, "white" if black else "#555555")
                    y = rect.bottom - 10 if black else rect.top + round(rect.height * .8)
                    target.blit(text, text.get_rect(center=(rect.centerx, y)))
        pygame.draw.rect(target, "#a50000", (0, self.top, self.piano_width, 4))
        pygame.draw.rect(target, "black", (self.piano_width, self.top, self.width - self.piano_width, self.height - self.top))
        labels = {"qwerty": "Qwerty Toggle", "volume": f"Volume {app.volume}%", "auto": "Auto",
                  "sustain": "Sustain", "invert": "Invert Sustain", "transpose": f"Transposition: {app.transpose}",
                  "velocity": f"Velocity: {app.velocity}", "sheets": "Sheets", "synth": "2D Synth"}
        flags = {"qwerty": app.qwerty, "sustain": app.effective_sustain, "invert": app.invert,
                 "auto": app.auto, "synth": app.synth}
        for name, rect in self.buttons.items():
            self.button(target, rect, labels[name], flags.get(name, False))
        if app.popup:
            pygame.draw.rect(target, "#050505", self.popup)
            pygame.draw.rect(target, "#333333", self.popup, 1)
            for name, label in (("run", "Auto"), ("clear", "Clear"), ("88key", "88KEY"), ("exit", "Exit")):
                self.button(target, self.popup_buttons[name], label, name == "run" and app.auto)
            app.editor.rect = self.text_rect
            app.editor.draw(target)
            status = app.status or f"{app.stepper.index} / {len(app.stepper.sheet.steps)}"
            text = self.font(11).render(status, True, "#bbbbbb")
            old_clip = target.get_clip()
            target.set_clip(self.popup)
            target.blit(text, (self.popup.x + 9, self.popup.bottom - 21))
            target.set_clip(old_clip)
