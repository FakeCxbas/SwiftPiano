"""Integration regressions for source ownership, editor focus and the actual mixer."""
import os
os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["SDL_AUDIODRIVER"] = "dummy"

import pygame
import pytest
from audio_engine import AudioEngine
from input_manager import build_bindings, BLACK_CLASSES
from main import PianoApp
from sheet_parser import SheetParser, AutoStepper, DEMO_SHEET


class SilentAudio:
    def __init__(self):
        self.active = {}
        self.sustain = False

    def note_on(self, token, midi, velocity):
        self.active[token] = midi

    def note_off(self, token):
        self.active.pop(token, None)

    def set_sustain(self, value):
        self.sustain = value

    def stop_all(self):
        self.active.clear()
        self.sustain = False

    def cleanup(self):
        pass


@pytest.fixture(scope="module", autouse=True)
def pygame_session():
    pygame.mixer.pre_init(44100, -16, 2, 512)
    pygame.init()
    pygame.display.set_mode((1440, 800))
    yield
    pygame.quit()


@pytest.fixture
def app():
    return PianoApp(pygame.display.get_surface(), SilentAudio())


def down(app, char, mod=0, repeat=False):
    app.handle(pygame.event.Event(pygame.KEYDOWN, key=ord(char), mod=mod, repeat=repeat))


def up(app, char):
    app.handle(pygame.event.Event(pygame.KEYUP, key=ord(char), mod=0))


def click(app, rect, button=1):
    app.handle(pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=rect.center, button=button))
    app.handle(pygame.event.Event(pygame.MOUSEBUTTONUP, pos=rect.center, button=button))


def test_exact_layout(app):
    bindings = build_bindings()
    assert [b.midi for b in bindings] == list(range(36, 97))
    assert ''.join(b.label for b in bindings if b.is_black) == '!@$%^*(QWETYIOPSDGHJLZCVB'
    assert len(app.renderer.key_rects) == 88
    assert sum(m % 12 not in BLACK_CLASSES for m in app.renderer.key_rects) == 52
    assert app.renderer.top == 640
    assert app.renderer.piano_width == round(1440 * .82)
    for midi, rect in app.renderer.key_rects.items():
        # All 88 keys accessible; whites tested below the overlapping blacks.
        pos = (rect.centerx, rect.centery if midi % 12 in BLACK_CLASSES else rect.bottom - 3)
        assert app.renderer.hit_key(pos) == midi


def test_parser_real_sheet_chords_and_directives():
    parser = SheetParser()
    assert len(parser.parse(DEMO_SHEET).steps) == 34
    sheet = parser.parse('Title: My Song\nTransposition: 4\n6[er]3 [680] [W0ryd]\nTransposition: 0\n[er]')
    assert [len(s.notes) for s in sheet.steps] == [1, 2, 1, 3, 5, 2]
    assert sheet.transposition == 4
    assert sheet.steps[-1].transposition == 0
    assert len(parser.parse('W E').steps) == 2
    assert len(parser.parse('My Song\n[er|\n?wt] - ()').steps) == 1
    assert len(parser.parse('abc').steps) == 3


def test_stepper_wrap_and_empty():
    stepper = AutoStepper()
    assert stepper.next_step() is None
    stepper.load('6 [er]')
    first = stepper.next_step()
    assert len(stepper.next_step().notes) == 2
    assert stepper.index == 0
    assert stepper.next_step() == first
    stepper.load('')
    assert stepper.index == 0


def test_auto_repeat_hold_overlap_and_transpose(app):
    app.editor.text = '[er] [er]'
    app.toggle_auto()
    down(app, 'a')
    down(app, 'a', repeat=True)
    assert app.stepper.index == 1
    assert len(app.audio.active) == 2
    app.update(.5)
    assert all(app.renderer.bar_rect(b).bottom == app.renderer.top for b in app.renderer.bars.values())
    down(app, 's')
    assert len(app.audio.active) == 4
    app.transpose = 12
    up(app, 'a')
    assert len(app.audio.active) == 2
    app.auto = False
    up(app, 's')
    assert not app.audio.active
    assert not app.renderer.bars
    app.update(.5)
    assert all(app.renderer.bar_rect(b).bottom < app.renderer.top for b in app.renderer.released)


def test_r_is_a_note_and_shift_release(app):
    down(app, 'r')
    assert list(app.audio.active.values()) == [59]
    up(app, 'r')
    down(app, '1', pygame.KMOD_SHIFT)
    assert list(app.audio.active.values()) == [37]
    app.transpose = 24
    up(app, '1')
    assert not app.audio.active


def test_mouse_drag_transposition_and_black_priority(app):
    app.transpose = 1
    first = app.renderer.key_rects[60]
    pos = (first.centerx, first.bottom - 2)
    app.handle(pygame.event.Event(pygame.MOUSEBUTTONDOWN, button=1, pos=pos))
    assert list(app.audio.active.values()) == [61]
    second = app.renderer.key_rects[62]
    app.handle(pygame.event.Event(pygame.MOUSEMOTION, pos=(second.centerx, second.bottom - 2)))
    assert list(app.audio.active.values()) == [63]
    app.handle(pygame.event.Event(pygame.MOUSEBUTTONUP, button=1, pos=pos))
    assert not app.audio.active


def test_editor_focus_auto_blur_and_clear(app, monkeypatch):
    click(app, app.renderer.buttons['auto'])
    click(app, app.editor.rect)
    assert app.editor.focus
    monkeypatch.setattr(pygame.scrap, 'get_text', lambda: '[680] [er]')
    down(app, 'a', pygame.KMOD_CTRL)
    down(app, 'v', pygame.KMOD_CTRL)
    assert app.editor.text == '[680] [er]'
    assert not app.audio.active
    click(app, app.renderer.popup_buttons['run'])
    assert app.auto and not app.editor.focus
    down(app, 'r')
    assert len(app.audio.active) == 3
    assert app.editor.text == '[680] [er]'
    click(app, app.renderer.popup_buttons['clear'])
    up(app, 'r')
    assert app.stepper.index == 0 and not app.editor.text and not app.auto
    assert not app.audio.active


def test_sustain_invert_and_focus_loss(app):
    down(app, ' ')
    assert app.audio.sustain
    up(app, ' ')
    assert not app.audio.sustain
    app.control('invert')
    assert app.audio.sustain
    down(app, ' ')
    assert not app.audio.sustain
    app.control('sustain')
    assert not app.audio.sustain
    up(app, ' ')
    assert app.audio.sustain
    down(app, 'q')
    app.handle(pygame.event.Event(pygame.WINDOWFOCUSLOST))
    assert not app.audio.active and not app.renderer.bars and not app.input.pressed


def test_actual_preload_polyphony_and_voice_ownership(tmp_path):
    audio = AudioEngine(tmp_path, polyphony=64)
    assert len(audio.sounds) == 88
    audio.set_sustain(True)
    for token in range(80):
        audio.note_on(token, 60, 59)
    assert len(audio.voices) == 80
    assert len({v.channel_id for v in audio.voices.values()}) == 80
    assert all(v.channel.get_busy() for v in audio.voices.values())
    audio.note_off(0)
    assert not audio.voices[0].held and audio.voices[1].held
    assert audio.voices[0].channel.get_busy()
    audio.set_sustain(False)
    pygame.time.wait(300)
    audio.cleanup()
    assert 0 not in audio.voices and 1 in audio.voices
    audio.stop_all()


def test_render_black_canvas_grey_keys_and_red_felt(app):
    down(app, 'q')
    app.update(.5)
    app.draw()
    screen = app.screen
    assert screen.get_at((0, 0))[:3] == (5, 5, 5)
    assert screen.get_at((10, app.renderer.top))[:3] == (165, 0, 0)
    rect = app.renderer.key_rects[53]
    assert screen.get_at((rect.left + 3, rect.bottom - 3))[:3] == (176, 176, 176)
    app.popup = True
    app.draw()
    app.renderer.resize((800, 400))
    app.draw()


def test_tiling_resize_accepts_751px_without_requesting_another_window(app, monkeypatch):
    surface = pygame.Surface((751, 852))
    monkeypatch.setattr(pygame.display, 'get_surface', lambda: surface)

    def forbidden(*args, **kwargs):
        pytest.fail('Resize handler must not request a new window size')

    monkeypatch.setattr(pygame.display, 'set_mode', forbidden)
    for _ in range(20):
        app.handle(pygame.event.Event(pygame.VIDEORESIZE, w=751, h=852, size=(751, 852)))
        app.handle(pygame.event.Event(pygame.WINDOWSIZECHANGED, x=751, y=852))
        app.update(1 / 60)
    assert app.screen is surface
    assert (app.renderer.width, app.renderer.height) == (751, 852)
    app.popup = True
    app.draw()
