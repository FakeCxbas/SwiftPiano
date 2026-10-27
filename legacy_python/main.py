"""SwiftPiano: clean 2D piano and any-key sheet playback."""
import argparse
from pathlib import Path
import sys
import pygame
from audio_engine import AudioEngine
from input_manager import InputManager
from sheet_parser import AutoStepper, DEMO_SHEET
from waterfall_renderer import TextArea, WaterfallRenderer

ROOT = Path(__file__).resolve().parent


class PianoApp:
    def __init__(self, screen, audio, sheet=DEMO_SHEET):
        self.screen = screen
        self.audio = audio
        self.input = InputManager()
        self.renderer = WaterfallRenderer(screen.get_size())
        self.editor = TextArea(sheet)
        self.editor.rect = self.renderer.text_rect
        self.editor.blur()
        self.stepper = AutoStepper()
        self.qwerty = True
        self.synth = True
        self.popup = False
        self.auto = False
        self.sustain = False
        self.invert = False
        self.space = False
        self.transpose = 0
        self.volume = 100
        self.velocity = 59
        self.mouse_down = False
        self.mouse_note = None
        self.status = ""
        self.running = True
        self.compile_sheet()

    @property
    def effective_sustain(self):
        return not self.space if self.invert else self.sustain or self.space

    def sync_sustain(self):
        self.audio.set_sustain(self.effective_sustain)

    def compile_sheet(self):
        sheet = self.stepper.load(self.editor.text)
        if sheet.transposition is not None:
            self.transpose = sheet.transposition
        self.status = "" if sheet.steps else "No notes"

    def press(self, source, notes):
        for token, pitch in self.input.press(source, notes, self.transpose):
            self.audio.note_on(token, pitch, self.velocity)
            self.renderer.note_on(token, pitch)

    def release(self, source):
        self.release_voices(self.input.release(source))

    def release_voices(self, voices):
        for token, _ in voices:
            self.audio.note_off(token)
            self.renderer.note_off(token)

    def panic(self):
        self.release_voices(self.input.release_all())
        self.mouse_down = False
        self.mouse_note = None
        self.space = False
        self.audio.stop_all()

    def blur(self):
        if self.editor.focus:
            self.compile_sheet()
        self.editor.blur()

    def toggle_auto(self):
        self.blur()
        if not self.auto:
            self.compile_sheet()
        self.auto = not self.auto

    def control(self, name, delta=1):
        if name == "qwerty":
            self.qwerty = not self.qwerty
        elif name in ("auto", "sheets"):
            self.popup = not self.popup if name == "auto" else True
        elif name == "sustain":
            self.sustain = not self.sustain
        elif name == "invert":
            self.invert = not self.invert
        elif name == "transpose":
            self.transpose = max(-87, min(87, self.transpose + delta))
        elif name == "volume":
            self.volume = max(0, min(100, self.volume + delta * 5))
            self.audio.set_volume(self.volume / 100)
        elif name == "velocity":
            self.velocity = max(1, min(127, self.velocity + delta))
        elif name == "synth":
            self.synth = not self.synth
        self.sync_sustain()

    def move_mouse_note(self, pos):
        midi = None if self.popup and self.renderer.popup.collidepoint(pos) else self.renderer.hit_key(pos)
        if midi != self.mouse_note:
            self.release("mouse")
            self.mouse_note = midi
            if midi is not None:
                self.press("mouse", [midi])

    def handle(self, event):
        if event.type == pygame.QUIT:
            self.running = False
            return
        if event.type == pygame.WINDOWFOCUSLOST:
            self.blur()
            self.panic()
            return
        if event.type == pygame.WINDOWFOCUSGAINED:
            self.sync_sustain()
            return
        if event.type in (pygame.VIDEORESIZE, pygame.WINDOWSIZECHANGED):
            # SDL already resized the display. Requesting another size here
            # creates a configure loop with tiling Wayland compositors.
            self.sync_display_size()
            return
        # Releases must always reach the original source, even after focus/mode changes.
        if event.type == pygame.KEYUP:
            self.input.key_up(event.key)
            self.release(event.key)
            if event.key == pygame.K_SPACE:
                self.space = False
                self.sync_sustain()
            return
        if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self.mouse_down = False
            self.mouse_note = None
            self.release("mouse")
            return
        if event.type == pygame.MOUSEBUTTONDOWN and event.button in (1, 3):
            pos = event.pos
            if self.popup and self.editor.rect.collidepoint(pos) and not self.auto:
                self.editor.click(pos)
                return
            self.blur()
            if self.popup and self.renderer.popup.collidepoint(pos):
                for name, rect in self.renderer.popup_buttons.items():
                    if rect.collidepoint(pos):
                        if name == "run":
                            self.toggle_auto()
                        elif name == "clear":
                            self.auto = False
                            self.editor.text = ""
                            self.editor.cursor = self.editor.anchor = self.editor.scroll = 0
                            self.compile_sheet()
                        elif name == "exit":
                            self.popup = False
                        elif name == "88key":
                            self.status = "88 keys · A0–C8"
                        return
                return
            for name, rect in self.renderer.buttons.items():
                if rect.collidepoint(pos):
                    self.control(name, 1 if event.button == 1 else -1)
                    return
            if event.button == 1:
                self.mouse_down = True
                self.move_mouse_note(pos)
            return
        if event.type == pygame.MOUSEWHEEL:
            pos = pygame.mouse.get_pos()
            if self.popup and self.editor.rect.collidepoint(pos):
                self.editor.scroll = max(0, min(len(self.editor.lines()) - 1, self.editor.scroll - event.y * 3))
            else:
                for name in ("transpose", "volume", "velocity"):
                    if self.renderer.buttons[name].collidepoint(pos):
                        self.control(name, event.y)
            return
        if event.type == pygame.MOUSEMOTION and self.mouse_down:
            self.move_mouse_note(event.pos)
            return
        if self.editor.focus and not self.auto:
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                self.blur()
            else:
                error = self.editor.handle(event)
                if error:
                    self.status = error
            return
        if event.type == pygame.KEYDOWN:
            if not self.input.key_down(event):
                return
            if event.key == pygame.K_ESCAPE:
                if self.popup:
                    self.popup = False
                else:
                    self.running = False
            elif event.key == pygame.K_SPACE:
                self.space = True
                self.sync_sustain()
            elif event.mod & (pygame.KMOD_CTRL | pygame.KMOD_ALT | pygame.KMOD_GUI):
                return
            elif self.auto and self.input.is_step_key(event.key):
                step = self.stepper.next_step()
                if step:
                    self.status = ""
                    if step.transposition is not None:
                        self.transpose = step.transposition
                    self.press(event.key, step.notes)
            elif not self.auto:
                midi = self.input.manual_note(event)
                if midi is not None:
                    self.press(event.key, [midi])

    def sync_display_size(self):
        surface = pygame.display.get_surface()
        if surface is None:
            return
        self.screen = surface
        size = surface.get_size()
        if size != (self.renderer.width, self.renderer.height):
            self.renderer.resize(size)
            self.editor.rect = self.renderer.text_rect

    def update(self, dt):
        self.sync_display_size()
        self.renderer.update(dt)
        self.audio.cleanup()

    def draw(self):
        self.renderer.draw(self.screen, self)


def main():
    parser = argparse.ArgumentParser(description="88-key piano with any-key sheet playback")
    parser.add_argument("--sheet", type=Path, help="UTF-8 Virtual Piano letters file")
    parser.add_argument("--frames", type=int, default=0, help=argparse.SUPPRESS)
    args = parser.parse_args()
    pygame.mixer.pre_init(44100, -16, 2, 512)
    pygame.init()
    try:
        screen = pygame.display.set_mode((1440, 800), pygame.RESIZABLE)
        pygame.display.set_caption("SwiftPiano · 2D Synth")
        screen.fill("#050505")
        font = pygame.font.SysFont("DejaVu Sans", 16)
        msg = font.render("Loading piano…", True, "#bbbbbb")
        screen.blit(msg, msg.get_rect(center=screen.get_rect().center))
        pygame.display.flip()
        audio = AudioEngine(ROOT / "assets" / "samples")
        for warning in audio.sample_warnings:
            print(warning, file=sys.stderr)
        app = PianoApp(screen, audio, args.sheet.read_text(encoding="utf-8") if args.sheet else DEMO_SHEET)
        clock = pygame.time.Clock()
        frames = 0
        while app.running:
            dt = clock.tick(60) / 1000
            for event in pygame.event.get():
                app.handle(event)
            app.update(dt)
            app.draw()
            pygame.display.flip()
            frames += 1
            if args.frames and frames >= args.frames:
                break
        app.panic()
        return 0
    except (pygame.error, OSError) as exc:
        print(f"No se pudo iniciar SwiftPiano: {exc}", file=sys.stderr)
        return 1
    finally:
        pygame.quit()


if __name__ == "__main__":
    raise SystemExit(main())
