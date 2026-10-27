"""Preloaded piano bank, independent voices, sustain and soft damper release."""
from pathlib import Path
from dataclasses import dataclass
import numpy as np
import pygame


@dataclass
class Voice:
    channel: pygame.mixer.Channel
    gain: float
    channel_id: int
    held: bool = True


class AudioEngine:
    def __init__(self, sample_dir="assets/samples", polyphony=128, sample_rate=44100):
        if not pygame.mixer.get_init():
            pygame.mixer.init(sample_rate, -16, 2, 512)
        self.sample_rate, fmt, channels = pygame.mixer.get_init()
        if fmt != -16 or channels != 2:
            raise RuntimeError("Audio requires signed 16-bit stereo")
        self.polyphony = max(64, polyphony)
        pygame.mixer.set_num_channels(self.polyphony)
        self.volume = 1.0
        self.sustain = False
        self.voices = {}
        self.sounds = {}
        self.sample_warnings = []
        sample_dir = Path(sample_dir)
        for midi in range(21, 109):
            name = self.midi_name(midi)
            paths = [sample_dir / f"{s}.wav" for s in (name, name.replace("#", "s"), str(midi))]
            sample = next((p for p in paths if p.is_file()), None)
            if sample:
                try:
                    self.sounds[midi] = pygame.mixer.Sound(str(sample))
                    continue
                except pygame.error as exc:
                    self.sample_warnings.append(f"{sample.name}: {exc}")
            self.sounds[midi] = self._synthesize(midi)

    @staticmethod
    def midi_name(midi):
        return ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")[midi % 12] + str(midi // 12 - 1)

    def _synthesize(self, midi):
        """Grand-style fallback: decaying, slightly inharmonic strings."""
        frequency = 440 * 2 ** ((midi - 69) / 12)
        duration = max(4.0, 10.0 - (midi - 21) * 0.065)
        t = np.arange(int(duration * self.sample_rate), dtype=np.float32) / self.sample_rate
        wave = np.zeros_like(t)
        for harmonic, gain in enumerate((1, .42, .22, .13, .08, .045, .025), 1):
            f = frequency * harmonic * (1 + .000025 * harmonic ** 2)
            if f >= self.sample_rate * .47:
                continue
            decay = np.exp(-t * (0.45 + (midi - 21) * .013 + harmonic * .12))
            wave += gain * decay * (np.sin(2 * np.pi * f * t)
                                    + .22 * np.sin(2 * np.pi * f * 1.0008 * t))
        wave *= np.minimum(t / .005, 1) * np.minimum((duration - t) / .15, 1)
        pcm = np.asarray(np.clip(wave * .16, -1, 1) * 32767, dtype=np.int16)
        return pygame.sndarray.make_sound(np.column_stack((pcm, pcm)))

    def note_on(self, token, midi, velocity=59):
        self.cleanup()
        channel_id = next((i for i in range(self.polyphony) if not pygame.mixer.Channel(i).get_busy()), None)
        if channel_id is None:
            old = self.polyphony
            self.polyphony *= 2
            pygame.mixer.set_num_channels(self.polyphony)
            channel_id = old
        self.voices = {k: v for k, v in self.voices.items() if v.channel_id != channel_id}
        channel = pygame.mixer.Channel(channel_id)
        gain = max(0, min(127, velocity)) / 127
        channel.play(self.sounds[midi])
        channel.set_volume(gain * self.volume)
        self.voices[token] = Voice(channel, gain, channel_id)

    def note_off(self, token):
        voice = self.voices.get(token)
        if voice:
            voice.held = False
            if not self.sustain:
                voice.channel.fadeout(160)

    def set_sustain(self, enabled):
        if self.sustain and not enabled:
            for voice in self.voices.values():
                if not voice.held:
                    voice.channel.fadeout(260)
        self.sustain = enabled

    def set_volume(self, value):
        self.volume = max(0, min(1, value))
        for voice in self.voices.values():
            voice.channel.set_volume(voice.gain * self.volume)

    def cleanup(self):
        self.voices = {k: v for k, v in self.voices.items() if v.channel.get_busy()}

    def stop_all(self):
        pygame.mixer.stop()
        self.voices.clear()
        self.sustain = False
