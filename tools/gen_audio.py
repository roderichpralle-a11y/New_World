#!/usr/bin/env python3
"""Erzeugt Musik, Umgebungsgeraeusche und Soundeffekte fuer Insel-Siedler.

Alles ist eigene Synthese (numpy/scipy), keine fremden Samples. Lizenz CC0.
Aufruf:  python3 tools/gen_audio.py   (braucht numpy, scipy und ffmpeg mit libvorbis)

Ausgabe:
  assets/audio/music/*.ogg   Musikstuecke, nahtlos geloopt
  assets/audio/ambient/*.ogg Meer, Voegel, Grillen (Schleifen)
  assets/audio/sfx/*.wav     kurze Effekte
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "audio")
SR = 44100
SFX_SR = 22050
rng = np.random.default_rng(7)

NOTE_IDX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """'A4', 'Bb3', 'C#5' -> MIDI-Nummer."""
    n = NOTE_IDX[name[0]]
    i = 1
    while name[i] in "#b":
        n += 1 if name[i] == "#" else -1
        i += 1
    return n + 12 * (int(name[i:]) + 1)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# ---------------------------------------------------------------- Huellkurven, Filter
def env_adsr(n, sr, a=0.01, d=0.1, s=0.7, r=0.1):
    t = np.arange(n) / sr
    e = np.ones(n) * s
    na = max(1, int(a * sr))
    nd = max(1, int(d * sr))
    e[:na] = np.linspace(0, 1, na, endpoint=False)[: len(e[:na])]
    seg = e[na:na + nd]
    e[na:na + nd] = np.linspace(1, s, nd)[: len(seg)]
    nr = min(n, max(1, int(r * sr)))
    e[-nr:] *= np.linspace(1, 0, nr)
    return e


def lowpass(x, f, sr, order=2):
    return sosfilt(butter(order, min(f, sr * 0.45), "low", fs=sr, output="sos"), x)


def highpass(x, f, sr, order=2):
    return sosfilt(butter(order, f, "high", fs=sr, output="sos"), x)


def bandpass(x, lo, hi, sr, order=2):
    return sosfilt(butter(order, [lo, min(hi, sr * 0.45)], "band", fs=sr, output="sos"), x)


def reverb_ir(seconds, sr, damp=3000.0, seed=1):
    r = np.random.default_rng(seed)
    n = int(seconds * sr)
    t = np.arange(n) / sr
    ir = r.standard_normal(n) * np.exp(-t * 6.9 / seconds)
    ir = lowpass(ir, damp, sr)
    ir[: int(0.012 * sr)] = 0.0  # kleine Vorverzoegerung
    return ir / np.sqrt(np.sum(ir ** 2))


# ---------------------------------------------------------------- Instrumente
def inst_flute(f, dur, sr=SR, vel=1.0):
    n = int((dur + 0.15) * sr)
    t = np.arange(n) / sr
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.18) * 4, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / sr
    x = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.07 * np.sin(3 * ph)
    breath = bandpass(rng.standard_normal(n), f * 0.9, f * 2.5, sr) * 0.05
    e = env_adsr(n, sr, a=0.05, d=0.15, s=0.8, r=0.16)
    return (x + breath) * e * 0.5 * vel


def inst_pluck(f, dur, sr=SR, vel=1.0, bright=1.0):
    n = int((dur + 0.6) * sr)
    t = np.arange(n) / sr
    x = np.zeros(n)
    for k in range(1, 12):
        if f * k > sr * 0.45:
            break
        x += np.sin(2 * np.pi * f * k * t * (1 + 0.0007 * k)) / k ** (1.6 - 0.3 * bright) * np.exp(-t * (1.6 + k * 1.3))
    x *= np.minimum(1, t / 0.003)
    rel = np.ones(n)
    nr = int(0.6 * sr)
    rel[-nr:] = np.linspace(1, 0, nr)
    return x * rel * 0.45 * vel


def inst_bell(f, dur, sr=SR, vel=1.0, decay=1.6):
    n = int((dur + decay) * sr)
    t = np.arange(n) / sr
    x = np.zeros(n)
    for ratio, amp, dk in [(1, 1.0, 1.0), (2.0, 0.45, 1.7), (3.01, 0.22, 2.6), (4.17, 0.12, 3.5), (5.43, 0.06, 4.5)]:
        if f * ratio < sr * 0.45:
            x += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * dk * 2.2 / decay)
    x *= np.minimum(1, t / 0.002)
    return x * 0.35 * vel


def inst_bass(f, dur, sr=SR, vel=1.0):
    n = int((dur + 0.1) * sr)
    t = np.arange(n) / sr
    ph = 2 * np.pi * f * t
    x = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)
    e = env_adsr(n, sr, a=0.01, d=0.25, s=0.6, r=0.09)
    return x * e * 0.3 * vel


def inst_pad(freqs, dur, sr=SR, vel=1.0):
    n = int((dur + 0.5) * sr)
    t = np.arange(n) / sr
    x = np.zeros(n)
    for f in freqs:
        for det in (-0.004, 0.0, 0.0045):
            ph = (f * (1 + det) * t + rng.random()) % 1.0
            x += 2 * ph - 1
    x = lowpass(x, 900, sr, 2) / (len(freqs) * 3)
    e = env_adsr(n, sr, a=0.5, d=0.3, s=0.8, r=0.5)
    return x * e * 0.5 * vel


def drum_kick(sr=SR, vel=1.0):
    n = int(0.22 * sr)
    t = np.arange(n) / sr
    f = 50 + 70 * np.exp(-t * 30)
    x = np.sin(2 * np.pi * np.cumsum(f) / sr) * np.exp(-t * 14)
    return x * 0.7 * vel


def drum_shaker(sr=SR, vel=1.0):
    n = int(0.09 * sr)
    t = np.arange(n) / sr
    x = bandpass(rng.standard_normal(n), 5000, 10000, sr) * np.exp(-t * 45) * np.minimum(1, t / 0.008)
    return x * 0.1 * vel


def drum_snare(sr=SR, vel=1.0):
    n = int(0.2 * sr)
    t = np.arange(n) / sr
    x = bandpass(rng.standard_normal(n), 1200, 6000, sr) * np.exp(-t * 22)
    x += 0.4 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
    return x * 0.28 * vel


# ---------------------------------------------------------------- Sequenzer
class Song:
    def __init__(self, bpm, bars, beats_per_bar=4, sr=SR):
        self.bpm = bpm
        self.bpb = beats_per_bar
        self.sr = sr
        self.beat = 60.0 / bpm
        self.length = int(bars * beats_per_bar * self.beat * sr)
        tail = int(4.0 * sr)
        self.tracks = {}
        self.n = self.length + tail

    def track(self, name, pan=0.0, verb=0.25):
        if name not in self.tracks:
            self.tracks[name] = [np.zeros(self.n), pan, verb]
        return self.tracks[name][0]

    def add(self, name, start_beat, sig, pan=0.0, verb=0.25):
        buf = self.track(name, pan, verb)
        i = int(start_beat * self.beat * self.sr)
        # Ueber das Ende hinaus wird am Anfang weitergespielt (nahtlose Schleife)
        for chunk_start in range(0, len(sig), self.length):
            part = sig[chunk_start:chunk_start + self.length]
            j = (i + chunk_start) % self.length
            end = min(len(buf), j + len(part))
            buf[j:end] += part[: end - j]

    def mixdown(self, master=0.72):
        L = np.zeros(self.n)
        R = np.zeros(self.n)
        wet = np.zeros(self.n)
        for name, (buf, pan, verb) in self.tracks.items():
            if os.environ.get("AUDIO_DEBUG"):
                print("   Spur %-7s RMS %.3f" % (name, np.sqrt(np.mean(buf[: self.length] ** 2))))
            gl = np.cos((pan + 1) * np.pi / 4)
            gr = np.sin((pan + 1) * np.pi / 4)
            L += buf * gl
            R += buf * gr
            wet += buf * verb
        ir_l = reverb_ir(2.2, self.sr, seed=3)
        ir_r = reverb_ir(2.2, self.sr, seed=4)
        L += fftconvolve(wet, ir_l)[: self.n] * 0.5
        R += fftconvolve(wet, ir_r)[: self.n] * 0.5
        # Nachhall hinter dem Ende auf den Anfang legen
        out = np.stack([L, R], axis=1)
        loop = out[: self.length].copy()
        rest = out[self.length:]
        loop[: len(rest)] += rest
        peak = np.max(np.abs(loop))
        return loop / peak * master


def parse_bars(text):
    """'A4:1 C5:1 r:2 | ...' -> Liste von Takten mit (Note|None, Schlaege)."""
    bars = []
    for bar in text.split("|"):
        notes = []
        for tok in bar.split():
            name, d = tok.split(":")
            notes.append((None if name == "r" else midi(name), float(d)))
        bars.append(notes)
    return bars


def place_melody(song, name, bars_text, start_bar, inst, transpose=0, pan=0.0, verb=0.3, vel=1.0, legato=0.95):
    beat = start_bar * song.bpb
    for bar in parse_bars(bars_text):
        for m, d in bar:
            if m is not None:
                f = hz(m + transpose)
                song.add(name, beat, inst(f, d * song.beat * legato, vel=vel), pan, verb)
            beat += d


CHORDS = {
    "C": ["C", "E", "G"], "Dm": ["D", "F", "A"], "Em": ["E", "G", "B"], "F": ["F", "A", "C"],
    "G": ["G", "B", "D"], "Am": ["A", "C", "E"], "Bb": ["Bb", "D", "F"], "Gm": ["G", "Bb", "D"],
    "A": ["A", "C#", "E"], "E": ["E", "G#", "B"], "D": ["D", "F#", "A"],
}


def chord_midis(ch, octave):
    names = CHORDS[ch]
    root = midi(names[0] + str(octave))
    out = []
    for nm in names:
        m = midi(nm + str(octave))
        while m < root:
            m += 12
        out.append(m)
    return out


def place_chords(song, chords, start_bar, bass=True, pad=False, arp=None, arp_vel=0.7, bass_pattern=None, pad_vel=0.6, bass_vel=1.0):
    for i, ch in enumerate(chords):
        bar = start_bar + i
        b0 = bar * song.bpb
        bar_s = song.bpb * song.beat
        root3 = chord_midis(ch, 2)[0]
        if bass:
            pat = bass_pattern or [(0, song.bpb)]
            for off, d, *rest in [(p[0], p[1], *p[2:]) for p in pat]:
                interval = rest[0] if rest else 0
                song.add("bass", b0 + off, inst_bass(hz(root3 + interval), d * song.beat * 0.9, vel=bass_vel), 0.0, 0.08)
        if pad:
            song.add("pad", b0, inst_pad([hz(m) for m in chord_midis(ch, 4)], bar_s, vel=pad_vel), 0.0, 0.5)
        if arp:
            tones = chord_midis(ch, 3) + [chord_midis(ch, 4)[0], chord_midis(ch, 4)[1]]
            step, idxs, inst, pan = arp
            for k, idx in enumerate(idxs):
                if idx is None:
                    continue
                f = hz(tones[idx % len(tones)] + 12 * (idx // len(tones)))
                song.add("arp", b0 + k * step, inst(f, step * song.beat * 1.6, vel=arp_vel), pan, 0.3)


def place_drums(song, start_bar, bars, kick=None, snare=None, shaker=None):
    for b in range(start_bar, start_bar + bars):
        b0 = b * song.bpb
        for pos in kick or []:
            song.add("drums", b0 + pos, drum_kick(), 0.0, 0.05)
        for pos in snare or []:
            song.add("drums", b0 + pos, drum_snare(), 0.1, 0.15)
        for pos, v in shaker or []:
            song.add("shaker", b0 + pos, drum_shaker(vel=v), 0.35, 0.1)


# ---------------------------------------------------------------- Musikstuecke
def song_tag():
    """Tag auf der Heimatinsel: F-Dur, freundlich, Floete und Zupfharfe."""
    s = Song(92, 32)
    A = ["F", "C", "Dm", "Bb", "F", "C", "Bb", "C"]
    A2 = ["F", "C", "Dm", "Bb", "F", "C", "Bb", "F"]
    B = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "C"]
    mel_a = ("A4:1 C5:1 F5:1.5 E5:0.5 | D5:1 C5:1 G4:2 | A4:1 D5:1 F5:1 E5:0.5 D5:0.5 | C5:3 r:1 | "
             "A4:1 C5:1 F5:1 G5:1 | A5:1.5 G5:0.5 E5:1 C5:1 | D5:1 F5:1 E5:1 D5:0.5 E5:0.5 | E5:3 r:1")
    mel_a2 = ("A4:1 C5:1 F5:1.5 E5:0.5 | D5:1 C5:1 G4:2 | A4:1 D5:1 F5:1 E5:0.5 D5:0.5 | C5:3 r:1 | "
              "A4:1 C5:1 F5:1 G5:1 | A5:1.5 G5:0.5 E5:1 C5:1 | D5:1 C5:1 Bb4:1 G4:1 | F4:3 r:1")
    mel_b = ("F5:1.5 E5:0.5 D5:1 A4:1 | Bb4:1 D5:1 F5:2 | C5:1.5 A4:0.5 C5:1 F5:1 | E5:2 G5:2 | "
             "A5:1.5 G5:0.5 F5:1 D5:1 | F5:1 D5:1 Bb4:2 | G4:1 Bb4:1 D5:1 G5:1 | E5:1 D5:1 C5:1 E5:1")
    arp8 = (0.5, [0, 1, 2, 3, 4, 3, 2, 1], inst_pluck, -0.3)
    walk = [(0, 1.5), (1.5, 0.5, 7), (2, 2, 12)]
    place_chords(s, A, 0, arp=arp8, bass_pattern=walk)
    place_melody(s, "lead", mel_a, 0, inst_flute, pan=0.15, vel=0.9)
    place_drums(s, 0, 8, shaker=[(1, 0.6), (3, 0.6), (3.5, 0.4)])
    place_chords(s, A2, 8, arp=arp8, pad=True, bass_pattern=walk, pad_vel=0.45)
    place_melody(s, "lead", mel_a2, 8, inst_flute, pan=0.15, vel=0.9)
    place_drums(s, 8, 8, kick=[0, 2], shaker=[(0.5, 0.5), (1, 0.7), (1.5, 0.4), (2.5, 0.5), (3, 0.7), (3.5, 0.4)])
    place_chords(s, B, 16, pad=True, arp=(1.0, [0, 2, 4, 2], inst_pluck, -0.3), bass_pattern=[(0, 2), (2, 2, 7)])
    place_melody(s, "lead", mel_b, 16, inst_flute, pan=0.15, vel=0.95)
    place_melody(s, "harm", mel_b, 16, inst_pluck, transpose=-12, pan=-0.4, vel=0.35)
    place_drums(s, 16, 8, kick=[0, 2.5], snare=[], shaker=[(1, 0.6), (3, 0.6)])
    place_chords(s, A, 24, arp=(0.5, [0, 2, 1, 3, 2, 4, 3, 2], inst_pluck, -0.3), bass_pattern=[(0, 4)])
    place_melody(s, "bell", mel_a, 24, inst_bell, transpose=12, pan=0.25, vel=0.55, verb=0.45)
    return s.mixdown()


def song_nacht():
    """Nacht: a-Moll im Dreiertakt, Spieluhr und weiche Flaechen."""
    s = Song(68, 24, beats_per_bar=3)
    A = ["Am", "F", "C", "G", "Am", "F", "E", "E"]
    B = ["F", "G", "Em", "Am", "Dm", "F", "E", "E"]
    A3 = ["Am", "F", "C", "G", "Am", "F", "E", "Am"]
    mel_a = ("E5:2 A4:1 | C5:2 A4:1 | G4:1 C5:1 E5:1 | D5:3 | E5:2 A5:1 | G5:1.5 F5:0.5 E5:1 | "
             "D5:1 B4:1 G#4:1 | B4:3")
    mel_b = ("A4:1 C5:1 F5:1 | G5:2 D5:1 | E5:1 G5:1 B5:1 | A5:3 | F5:2 E5:1 | D5:1 C5:1 A4:1 | "
             "B4:2 G#4:1 | E5:3")
    mel_a3 = ("E5:2 A4:1 | C5:2 A4:1 | G4:1 C5:1 E5:1 | D5:3 | E5:2 A5:1 | G5:1.5 F5:0.5 E5:1 | "
              "D5:1 B4:1 G#4:1 | A4:3")
    arp3 = (1.0, [0, 1, 2], inst_pluck, -0.35)
    place_chords(s, A, 0, pad=True, arp=arp3, arp_vel=0.45, pad_vel=1.0, bass_vel=0.55)
    place_melody(s, "bell", mel_a, 0, inst_bell, pan=0.2, vel=0.7, verb=0.5)
    place_chords(s, B, 8, pad=True, arp=(1.0, [0, 2, 3], inst_pluck, -0.35), arp_vel=0.45, pad_vel=1.0, bass_vel=0.55)
    place_melody(s, "lead", mel_b, 8, inst_flute, transpose=-12, pan=0.15, vel=0.7, verb=0.45)
    place_melody(s, "bell", mel_b, 8, inst_bell, pan=0.25, vel=0.35, verb=0.55)
    place_chords(s, A3, 16, pad=True, arp=arp3, arp_vel=0.4, pad_vel=0.9, bass_vel=0.55)
    place_melody(s, "bell", mel_a3, 16, inst_bell, pan=0.2, vel=0.6, verb=0.5)
    return s.mixdown(0.65)


def song_insel():
    """Fremde Inseln und Seefahrt: d-Dorisch, voranschreitend, mit Trommeln."""
    s = Song(108, 24)
    A = ["Dm", "C", "Bb", "C", "Dm", "C", "Bb", "A"]
    B = ["F", "C", "Dm", "Am", "Bb", "F", "G", "A"]
    mel_a = ("D5:1 F5:1 A5:1.5 G5:0.5 | E5:1 C5:1 G4:2 | F5:1 D5:1 Bb4:1 D5:1 | E5:2 C5:1 E5:1 | "
             "D5:1 F5:1 A5:1 D6:1 | C6:1.5 Bb5:0.5 A5:1 G5:1 | F5:1 G5:1 A5:1 F5:1 | E5:3 C#5:1")
    mel_b = ("A5:2 C6:1 A5:1 | G5:2 E5:2 | F5:1 E5:1 D5:1 F5:1 | E5:3 r:1 | D5:1 F5:1 Bb5:2 | "
             "A5:1 G5:1 F5:1 C5:1 | D5:1 G5:1 B4:1 D5:1 | C#5:2 E5:1 A5:1")
    strum = (0.5, [0, 2, 1, 2, 0, 2, 1, 3], inst_pluck, -0.35)
    drive = [(0, 0.5), (0.5, 0.5), (1, 0.5), (1.5, 0.5, 12), (2, 0.5), (2.5, 0.5), (3, 0.5, 7), (3.5, 0.5, 12)]
    place_chords(s, A, 0, arp=strum, bass_pattern=drive, arp_vel=0.6)
    place_melody(s, "lead", mel_a, 0, inst_flute, pan=0.15)
    place_drums(s, 0, 8, kick=[0, 2], snare=[1, 3], shaker=[(i * 0.5, 0.35 + 0.25 * (i % 2)) for i in range(8)])
    place_chords(s, B, 8, arp=strum, pad=True, bass_pattern=drive, arp_vel=0.6, pad_vel=0.5)
    place_melody(s, "lead", mel_b, 8, inst_flute, pan=0.15)
    place_melody(s, "harm", mel_b, 8, inst_pluck, transpose=-12, pan=-0.4, vel=0.35)
    place_drums(s, 8, 8, kick=[0, 1.5, 2], snare=[1, 3], shaker=[(i * 0.5, 0.35 + 0.25 * (i % 2)) for i in range(8)])
    place_chords(s, A, 16, arp=strum, pad=True, bass_pattern=drive, arp_vel=0.55, pad_vel=0.4)
    place_melody(s, "lead", mel_a, 16, inst_flute, pan=0.15, vel=0.9)
    place_melody(s, "bell", mel_a, 16, inst_bell, transpose=12, pan=0.3, vel=0.3, verb=0.45)
    place_drums(s, 16, 8, kick=[0, 2], snare=[3], shaker=[(i * 0.5, 0.3 + 0.2 * (i % 2)) for i in range(8)])
    return s.mixdown(0.7)


# ---------------------------------------------------------------- Umgebung
def ambient(kind, seconds=24.0, sr=SR):
    n = int(seconds * sr)
    t = np.arange(n) / sr
    out = np.zeros((n, 2))
    # Wellen: gefiltertes Rauschen mit langsamen, nahtlos wiederkehrenden Schwellungen
    for ch in range(2):
        noise = rng.standard_normal(n + sr)
        surf = lowpass(noise, 700, sr, 2)[sr:]
        swell = 0.55 + 0.45 * np.sin(2 * np.pi * t * 3 / seconds + ch * 1.3) ** 2
        swell *= 0.75 + 0.25 * np.sin(2 * np.pi * t * 7 / seconds + ch) ** 2
        hiss = highpass(rng.standard_normal(n), 2500, sr) * 0.12 * swell ** 3
        out[:, ch] = surf * swell * 0.35 + hiss
    if kind == "tag":
        for _ in range(16):
            start = rng.uniform(0, seconds - 1.5)
            base = rng.uniform(2600, 4200)
            for k in range(rng.integers(2, 6)):
                ln = rng.uniform(0.05, 0.12)
                m = int(ln * sr)
                tt = np.arange(m) / sr
                f = base * (1 + 0.25 * np.sin(np.pi * tt / ln)) * rng.uniform(0.9, 1.15)
                chirp = np.sin(2 * np.pi * np.cumsum(f) / sr) * np.sin(np.pi * tt / ln) ** 2
                i = int((start + k * rng.uniform(0.09, 0.18)) * sr)
                pan = rng.uniform(-0.7, 0.7)
                if i + m < n:
                    out[i:i + m, 0] += chirp * 0.07 * (1 - pan) / 2
                    out[i:i + m, 1] += chirp * 0.07 * (1 + pan) / 2
    else:
        for _ in range(3):
            f = rng.uniform(4300, 5200)
            pan = rng.uniform(-0.6, 0.6)
            rate = rng.uniform(14, 20)
            gate = (np.sin(2 * np.pi * rate * t) > 0.3).astype(float)
            phrase = (np.sin(2 * np.pi * t / rng.uniform(1.6, 2.6) + rng.uniform(0, 6)) > 0.1).astype(float)
            # Takt passend zur Schleifenlaenge runden
            cr = np.sin(2 * np.pi * f * t) * lowpass(gate * phrase, 80, sr, 1) * 0.035
            out[:, 0] += cr * (1 - pan) / 2
            out[:, 1] += cr * (1 + pan) / 2
    # Kreuzblende fuer eine saubere Schleife
    fade = int(1.0 * sr)
    w = np.linspace(0, 1, fade)[:, None]
    out[:fade] = out[:fade] * w + out[-fade:] * (1 - w)
    out = out[:-fade]
    return out / np.max(np.abs(out)) * 0.7


# ---------------------------------------------------------------- Effekte
def t_arr(sec, sr=SFX_SR):
    return np.arange(int(sec * sr)) / sr


def sweep(f0, f1, sec, sr=SFX_SR, shape="sin"):
    t = t_arr(sec, sr)
    f = f0 * (f1 / f0) ** (t / sec)
    ph = 2 * np.pi * np.cumsum(f) / sr
    if shape == "square":
        return np.sign(np.sin(ph)) * 0.6
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    return np.sin(ph)


def noise(sec, sr=SFX_SR):
    return rng.standard_normal(int(sec * sr))


def decay(sec, rate, sr=SFX_SR):
    t = t_arr(sec, sr)
    return np.exp(-t * rate) * np.minimum(1, t / 0.002)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(sig, sec, sr=SFX_SR):
    return np.concatenate([np.zeros(int(sec * sr)), sig])


def small_room(x, sr=SFX_SR, amount=0.18, size=0.5):
    ir = reverb_ir(size, sr, damp=4000, seed=9)
    return x + fftconvolve(x, ir)[: len(x) + int(size * sr)][: len(x)] * amount


def tail(x, sec, sr=SFX_SR):
    return np.concatenate([x, np.zeros(int(sec * sr))])


def sfx_all():
    S = {}
    S["klick"] = mix(sweep(1400, 700, 0.045) * decay(0.045, 70), bandpass(noise(0.02), 2000, 6000, SFX_SR) * decay(0.02, 200) * 0.3) * 0.5
    S["auf"] = sweep(380, 900, 0.09, shape="tri") * env_adsr(int(0.09 * SFX_SR), SFX_SR, 0.005, 0.03, 0.6, 0.04) * 0.45
    S["zu"] = sweep(800, 350, 0.09, shape="tri") * env_adsr(int(0.09 * SFX_SR), SFX_SR, 0.005, 0.03, 0.6, 0.04) * 0.4
    S["platzieren"] = mix(sweep(140, 55, 0.2) * decay(0.2, 18), lowpass(noise(0.15), 600, SFX_SR) * decay(0.15, 25) * 0.6)
    for i, f in enumerate([620, 540, 700]):
        S["hammer%d" % i] = small_room(mix(sweep(f, f * 0.8, 0.09) * decay(0.09, 45) * 0.7,
                                           bandpass(noise(0.05), 1200, 3500, SFX_SR) * decay(0.05, 90) * 0.8))
    for i, f in enumerate([850, 1000]):
        S["axt%d" % i] = small_room(mix(bandpass(noise(0.12), f * 0.7, f * 1.6, SFX_SR) * decay(0.12, 35) * 1.4,
                                        sweep(180, 90, 0.1) * decay(0.1, 30) * 0.6))
    for i, b in enumerate([2100, 2500]):
        clink = sum(np.sin(2 * np.pi * b * r * t_arr(0.3)) * np.exp(-t_arr(0.3) * k) * a
                    for r, a, k in [(1, 1, 22), (1.62, 0.6, 30), (2.48, 0.4, 40)])
        S["stein%d" % i] = small_room(mix(clink * 0.35, highpass(noise(0.04), 3000, SFX_SR) * decay(0.04, 120) * 0.5))
    rust = bandpass(noise(0.22), 1800, 5000, SFX_SR) * env_adsr(int(0.22 * SFX_SR), SFX_SR, 0.03, 0.05, 0.6, 0.1)
    rust *= 0.6 + 0.4 * np.sin(2 * np.pi * 38 * t_arr(0.22))
    S["pfluecken"] = rust * 0.6
    t = t_arr(0.45)
    sp = sum(bandpass(noise(0.45), lo, lo * 2.2, SFX_SR) * np.exp(-t * k) * a for lo, k, a in [(300, 9, 1.0), (1500, 12, 0.6), (4000, 20, 0.3)])
    S["platsch"] = mix(sp * np.minimum(1, t / 0.01) * 0.6, sweep(500, 1300, 0.12) * decay(0.12, 25) * 0.2)
    S["saege"] = bandpass(noise(0.35), 1500, 4500, SFX_SR) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 7 * t_arr(0.35)))) * env_adsr(int(0.35 * SFX_SR), SFX_SR, 0.02, 0.05, 0.8, 0.08) * 0.5

    def notes(seq, inst, gap, vel=1.0, **kw):
        out = np.zeros(1)
        for i, nm in enumerate(seq):
            out = mix(out, at(inst(hz(midi(nm)), 0.3, sr=SFX_SR, vel=vel, **kw), i * gap))
        return out

    S["fertig"] = small_room(notes(["C5", "E5", "G5", "C6"], inst_pluck, 0.07), amount=0.3, size=1.0)
    S["fertig"] = mix(S["fertig"], at(inst_bell(hz(midi("C6")), 0.4, sr=SFX_SR, vel=0.5), 0.28))
    fan = mix(*[at(inst_flute(hz(midi(nm)), d, sr=SFX_SR, vel=0.8), s0) for nm, s0, d in
                [("G4", 0, 0.12), ("C5", 0.13, 0.12), ("E5", 0.26, 0.12), ("G5", 0.39, 0.6)]])
    fan = mix(fan, at(notes(["C5", "E5", "G5"], inst_pluck, 0.0, vel=0.8), 0.39))
    S["forschung"] = small_room(fan, amount=0.3, size=1.2)
    S["geburt"] = small_room(notes(["E6", "G6", "C7", "G6"], inst_bell, 0.11, vel=0.6, decay=0.9), amount=0.35, size=1.2)
    S["tod"] = small_room(mix(inst_bell(hz(midi("A3")), 0.2, sr=SFX_SR, decay=2.0), at(inst_bell(hz(midi("C4")), 0.2, sr=SFX_SR, decay=2.0, vel=0.6), 0.35)) * 0.9, amount=0.4, size=1.5)
    birds = np.zeros(1)
    for k, (b, s0) in enumerate([(3200, 0), (3600, 0.14), (3400, 0.3), (3900, 0.42)]):
        ln = 0.09
        tt = t_arr(ln)
        f = b * (1 + 0.3 * np.sin(np.pi * tt / ln))
        birds = mix(birds, at(np.sin(2 * np.pi * np.cumsum(f) / SFX_SR) * np.sin(np.pi * tt / ln) ** 2 * 0.35, s0))
    S["morgen"] = mix(small_room(birds, amount=0.3), at(inst_bell(hz(midi("G5")), 0.2, sr=SFX_SR, vel=0.25, decay=1.0), 0.0))
    t = t_arr(1.7)
    f = np.interp(t, [0, 0.25, 1.1, 1.7], [380, 640, 600, 420]) * (1 + 0.012 * np.sin(2 * np.pi * 6 * t))
    ph = 2 * np.pi * np.cumsum(f) / SFX_SR
    howl = (np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.1 * np.sin(3 * ph)) * env_adsr(len(t), SFX_SR, 0.2, 0.2, 0.85, 0.5)
    S["heulen"] = small_room(lowpass(howl, 2000, SFX_SR) * 0.45, amount=0.45, size=1.5)
    t = t_arr(0.6)
    gr = lowpass(noise(0.6), 500, SFX_SR) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t))
    saw = ((90 * t) % 1.0 * 2 - 1) * 0.4
    S["knurren"] = lowpass(gr + saw, 900, SFX_SR) * env_adsr(len(t), SFX_SR, 0.06, 0.1, 0.8, 0.2) * 0.8
    t = t_arr(0.4)
    gr = lowpass(noise(0.4), 700, SFX_SR) * (0.6 + 0.4 * np.sin(2 * np.pi * 45 * t))
    S["grunzen"] = mix(gr * env_adsr(len(t), SFX_SR, 0.02, 0.05, 0.7, 0.15) * 0.7,
                       sweep(220, 140, 0.15, shape="square") * decay(0.15, 12) * 0.15)
    t = t_arr(0.25)
    sw = bandpass(noise(0.25), 900, 3500, SFX_SR) * np.sin(np.pi * t / 0.25) ** 2
    S["pfeil"] = mix(sw * 0.5, at(mix(sweep(300, 120, 0.06) * decay(0.06, 50), bandpass(noise(0.03), 800, 2500, SFX_SR) * decay(0.03, 100)) * 0.6, 0.22))
    S["treffer"] = mix(sweep(180, 70, 0.12) * decay(0.12, 25) * 0.8, lowpass(noise(0.08), 1500, SFX_SR) * decay(0.08, 40) * 0.6)
    S["autsch"] = lowpass(sweep(260, 150, 0.16, shape="square"), 1200, SFX_SR) * env_adsr(int(0.16 * SFX_SR), SFX_SR, 0.01, 0.04, 0.7, 0.06) * 0.35
    bell = mix(inst_bell(hz(midi("A5")), 0.2, sr=SFX_SR, decay=1.4), at(inst_bell(hz(midi("A5")), 0.2, sr=SFX_SR, decay=1.4, vel=0.8), 0.32))
    S["glocke"] = small_room(bell, amount=0.35, size=1.2)
    disc = mix(*[at(inst_flute(hz(midi(nm)), d, sr=SFX_SR, vel=0.8), s0) for nm, s0, d in
                 [("D5", 0, 0.14), ("F#5", 0.15, 0.14), ("A5", 0.3, 0.14), ("D6", 0.45, 0.8)]])
    disc = mix(disc, at(notes(["D4", "A4", "D5", "F#5"], inst_pluck, 0.02, vel=0.7), 0.45))
    S["entdeckt"] = small_room(disc, amount=0.35, size=1.3)
    lost = mix(*[at(inst_flute(hz(midi(nm)), 0.4, sr=SFX_SR, vel=0.7), i * 0.38) for i, nm in enumerate(["A4", "F4", "D4"])])
    S["verloren"] = small_room(mix(lost, at(inst_bell(hz(midi("D3")), 0.2, sr=SFX_SR, decay=2.0, vel=0.7), 0.76)), amount=0.4, size=1.5)
    warn = mix(*[at(lowpass(sweep(f, f, 0.14, shape="square"), 2500, SFX_SR) * env_adsr(int(0.14 * SFX_SR), SFX_SR, 0.005, 0.02, 0.7, 0.04) * 0.3, s0)
                 for f, s0 in [(620, 0), (465, 0.16), (620, 0.4), (465, 0.56)]])
    S["warnung"] = warn
    S["fehler"] = lowpass(sweep(170, 150, 0.16, shape="square"), 1500, SFX_SR) * env_adsr(int(0.16 * SFX_SR), SFX_SR, 0.005, 0.03, 0.7, 0.05) * 0.35
    S["stufe"] = small_room(notes(["G5", "B5", "D6"], inst_bell, 0.06, vel=0.5, decay=0.6), amount=0.25)
    S["essen"] = mix(*[at(bandpass(noise(0.05), 600, 2000, SFX_SR) * decay(0.05, 60) * 0.35, s) for s in (0, 0.12, 0.24)])
    S["ziel"] = small_room(mix(notes(["C5", "G5", "C6"], inst_pluck, 0.05, vel=0.8), at(inst_bell(hz(midi("E6")), 0.3, sr=SFX_SR, vel=0.5, decay=1.0), 0.12)), amount=0.3, size=1.0)
    return S


# ---------------------------------------------------------------- Ausgabe
def write_wav(path, x, sr):
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = x[:, None]
    pk = np.max(np.abs(x))
    if pk > 0.98:
        x = x / pk * 0.98
    data = (x * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())


def write_ogg(path, x, sr, quality=3):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    write_wav(tmp, x, sr)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.remove(tmp)


def main():
    for d in ("music", "ambient", "sfx"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
    for name, fn in [("tag", song_tag), ("nacht", song_nacht), ("insel", song_insel)]:
        x = fn()
        write_ogg(os.path.join(OUT, "music", name + ".ogg"), x, SR)
        print("Musik", name, "%.1f s" % (len(x) / SR))
    for kind in ("tag", "nacht"):
        write_ogg(os.path.join(OUT, "ambient", "meer_%s.ogg" % kind), ambient(kind), SR, quality=1)
    for name, x in sfx_all().items():
        x = np.asarray(x)
        fade = min(len(x), int(0.01 * SFX_SR))
        x[-fade:] *= np.linspace(1, 0, fade)
        write_wav(os.path.join(OUT, "sfx", name + ".wav"), x, SFX_SR)
    print("Effekte fertig")


if __name__ == "__main__":
    main()
