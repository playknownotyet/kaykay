"""Geçici sesler (sentez): asıl kayıtlar gelene kadar. Çıktı: assets/ses/*.wav (mono, 22050 Hz, 16 bit)

  python tools/ses/gecici_sesler.py            (yalnız eksik sesleri üretir)
  python tools/ses/gecici_sesler.py --hepsi    (hepsini yeniden üretir: kendi koyduğun sesleri EZER)

Aynı adla gerçek bir kayıt koyunca (wav / ogg) oyun onu çalar (scripts/ses/ses_ayar.gd'de adlar).
Var olan dosyalar varsayılan olarak korunur: kendi kayıtların üzerine yazılmaz.
Döngüler (ruzgar, tekerlek_*, surtunme_*, grind, sehir) baştan sona kesintisiz döner.
"""
import math
import os
import sys
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ses")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


HEPSI = "--hepsi" in sys.argv


def save(name, x, peak=0.85):
    path = os.path.join(OUT, name + ".wav")
    others = [os.path.join(OUT, name + e) for e in (".ogg", ".mp3")]
    if not HEPSI and (os.path.exists(path) or any(os.path.exists(o) for o in others)):
        print("%-16s var, korunuyor" % name)
        return
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("%-16s %.2f sn" % (name, len(x) / SR))


def t(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec):
    return rng.standard_normal(int(sec * SR))


def lowpass(x, fc):
    a = math.exp(-2 * math.pi * fc / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, fc):
    return x - lowpass(x, fc)


def bandpass(x, f0, q):
    # İkinci dereceden (biquad) bant geçiren
    w0 = 2 * math.pi * f0 / SR
    al = math.sin(w0) / (2 * q)
    b0, b1, b2 = al, 0.0, -al
    a0, a1, a2 = 1 + al, -2 * math.cos(w0), 1 - al
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = np.empty_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def brown(sec):
    x = np.cumsum(noise(sec))
    x -= lowpass(x, 3.0)          # kaymayı al
    return x


def seamless(x, fade=0.25):
    """Döngü: sonun son 'fade' saniyesi başa karışır, ek yerinde tık olmaz."""
    n = int(fade * SR)
    head, body, tail = x[:n], x[n:-n] if n else x, x[-n:]
    k = np.linspace(0, 1, n)
    mix = tail * (1 - k) + head * k
    return np.concatenate([mix, body])


def env(sec, attack, decay):
    tt = t(sec)
    a = np.minimum(tt / max(attack, 1e-4), 1.0)
    return a * np.exp(-np.maximum(tt - attack, 0) / decay)


# ---------- Rüzgâr: alçak geçirilmiş gürültü, yavaş esintiler ----------
L = 6.0
w = lowpass(noise(L + 0.25), 500) + 0.5 * bandpass(noise(L + 0.25), 900, 0.7)
tt = t(L + 0.25)
gust = 0.65 + 0.25 * np.sin(2 * math.pi * tt / L) + 0.1 * np.sin(2 * math.pi * 3 * tt / L + 1.3)
save("ruzgar", seamless(w * gust))

# ---------- Tekerlek: düz asfalt (yumuşak uğultu) ve kaba zemin (taş, derz) ----------
L = 2.0
roll = bandpass(brown(L + 0.25), 220, 0.8) * 1.0 + bandpass(noise(L + 0.25), 700, 1.2) * 0.12
tt = t(L + 0.25)
roll *= 0.85 + 0.15 * np.sin(2 * math.pi * 4 * tt / L)       # tekerlek dönüşü (hafif dalga)
save("tekerlek_asfalt", seamless(roll))

rough = bandpass(brown(L + 0.25), 260, 0.7) + bandpass(noise(L + 0.25), 1100, 1.5) * 0.35
imp = np.zeros(int((L + 0.25) * SR))
for _ in range(70):
    i = rng.integers(0, len(imp) - 400)
    imp[i:i + 300] += rng.uniform(0.4, 1.0) * np.exp(-np.arange(300) / 40.0) * rng.standard_normal(300)
rough += bandpass(imp, 1400, 1.0) * 1.4
save("tekerlek_kaba", seamless(rough))

# ---------- Sürtünme 1 (fren: ayak / tekerlek yerde kayar, hışırtılı) ----------
L = 1.6
s1 = bandpass(noise(L + 0.25), 2600, 0.9) + bandpass(noise(L + 0.25), 4800, 1.4) * 0.6
crack = np.abs(rng.standard_normal(int((L + 0.25) * SR))) ** 3
s1 *= 0.6 + 0.4 * lowpass(crack, 60) / (np.max(lowpass(crack, 60)) or 1)
save("surtunme_1", seamless(s1))

# ---------- Sürtünme 2 (kayma: tekerlek yana kayar; tonsuz, düzensiz hırıltı) ----------
L = 1.6
n = int((L + 0.25) * SR)
s2 = bandpass(noise(L + 0.25), 1300, 1.1) + bandpass(noise(L + 0.25), 2600, 1.4) * 0.55 + lowpass(noise(L + 0.25), 500) * 0.25
# Düzensiz tutma-bırakma (periyodik değil): yavaş değişen rastgele genlik
grit = lowpass(np.abs(rng.standard_normal(n)), 18.0)
grit = grit / (np.max(grit) or 1)
s2 *= 0.45 + 0.55 * grit
save("surtunme_2", seamless(s2))

# ---------- Grind (truck metal üstünde): metalik vızıltı ----------
L = 1.5
tt = t(L + 0.25)
g = bandpass(noise(L + 0.25), 3200, 6.0) + bandpass(noise(L + 0.25), 5200, 8.0) * 0.6
g += 0.25 * np.sin(2 * math.pi * 2350 * tt) * (0.6 + 0.4 * np.sin(2 * math.pi * 34 * tt))
save("grind", seamless(g))

# ---------- Tık (titreşimle birlikte: taş, derz) ----------
sec = 0.05
c = highpass(noise(sec), 1500) * env(sec, 0.0005, 0.006) + np.sin(2 * math.pi * 2600 * t(sec)) * env(sec, 0.0003, 0.004) * 0.6
save("tik", c, 0.7)

# ---------- Pop (ollie: kuyruk yere vurur, kaykay kalkar) ----------
sec = 0.3
pp = highpass(noise(sec), 800) * env(sec, 0.0005, 0.012)
pp += np.sin(2 * math.pi * 170 * t(sec)) * env(sec, 0.001, 0.045) * 0.9
pp += bandpass(noise(sec), 900, 3.0) * env(sec, 0.0005, 0.03) * 2.0
save("pop", pp)

# ---------- İniş: güm + şık şık (önce arka, sonra ön tekerlekler) ----------
sec = 0.5
thud = np.sin(2 * math.pi * (80 + 40 * np.exp(-t(sec) / 0.03)) * t(sec)) * env(sec, 0.001, 0.08)
def clack(off):
    x = np.zeros(int(sec * SR))
    n = int(0.12 * SR)
    i = int(off * SR)
    k = highpass(noise(0.12), 1200) * env(0.12, 0.0004, 0.01) + bandpass(noise(0.12), 1600, 4.0) * env(0.12, 0.0004, 0.025) * 1.5
    x[i:i + n] += k[: len(x) - i]
    return x
save("inis", thud * 1.2 + clack(0.0) + clack(0.045) * 0.8)

# ---------- Şık (tek tahta tıkırtısı: kaykayı yere koyma, binme, kenar) ----------
sec = 0.15
sk = highpass(noise(sec), 1300) * env(sec, 0.0004, 0.01) + bandpass(noise(sec), 1500, 4.0) * env(sec, 0.0004, 0.03) * 1.6
save("sik", sk)

# ---------- Şehir ambiyansı: hafif uzak trafik + yumuşak kalabalık (gürüldemez, dalgalanmaz) ----------
L = 12.0
tt = t(L + 0.5)
# Uzak trafik: alçak tonlar kesik (fırtına gibi gürlemesin), orta bantta yumuşak hışırtı
hum = bandpass(noise(L + 0.5), 420, 0.6) * 0.6 + bandpass(noise(L + 0.5), 900, 0.8) * 0.3
hum *= 0.9 + 0.1 * np.sin(2 * math.pi * tt / L)
# Kalabalık: çok sayıda, birbirinden bağımsız ses; genlikleri sığ dalgalanır (toplam sabit kalır)
babble = np.zeros_like(tt)
for v in range(18):
    f1 = rng.uniform(450, 800)
    f2 = rng.uniform(1100, 2300)
    voice = bandpass(noise(L + 0.5), f1, 5.0) + bandpass(noise(L + 0.5), f2, 6.0) * 0.5
    syll = 0.6 + 0.4 * np.clip(np.sin(2 * math.pi * rng.uniform(3.5, 5.5) * tt + rng.uniform(0, 6)), 0, 1)
    phrase = 0.5 + 0.5 * lowpass((np.sin(2 * math.pi * rng.uniform(0.12, 0.3) * tt + rng.uniform(0, 6)) > 0).astype(float), 2.0)
    babble += voice * lowpass(syll * phrase, 12)
city = hum / (np.max(np.abs(hum)) or 1) * 0.55 + babble / (np.max(np.abs(babble)) or 1) * 0.5
save("sehir", seamless(city, 0.6), 0.6)

# ---------- Araba çarpması: ağır darbe (bas), ezilen sac, kırılan cam / plastik, kaykayın savrulması ----------
sec = 2.2
tt = t(sec)
# Darbe: derinden inen bas + gövde gümü
x = np.sin(2 * math.pi * (38 + 70 * np.exp(-tt / 0.06)) * tt) * env(sec, 0.001, 0.32) * 2.2
x += lowpass(noise(sec), 180) * env(sec, 0.001, 0.25) * 2.5
# Ezilen sac: doyurulmuş geniş bant gürültü, metal kısmi tonlarla, uzun kuyruk
crunch = bandpass(noise(sec), 700, 0.7) * 1.4 + bandpass(noise(sec), 2200, 0.9) * 0.9
grit = lowpass(np.abs(rng.standard_normal(len(tt))), 35.0)
crunch *= (grit / (np.max(grit) or 1)) * env(sec, 0.002, 0.42)
for f, d in ((310, 0.5), (523, 0.38), (847, 0.3), (1340, 0.22), (2110, 0.16), (3170, 0.1)):
    crunch += np.sin(2 * math.pi * f * tt + rng.uniform(0, 6)) * env(sec, 0.001, d) * 0.35
x += np.tanh(crunch * 2.5) * 0.9
# Cam / plastik: yüzlerce küçük, yüksek kırık parça (ilk 0,8 sn)
glass = np.zeros_like(tt)
for _ in range(260):
    j = int(rng.uniform(0.0, 0.8) ** 1.6 * SR)
    n = int(rng.uniform(0.01, 0.04) * SR)
    if j + n >= len(glass):
        continue
    f = rng.uniform(3200, 9000)
    seg = np.arange(n) / SR
    glass[j:j + n] += np.sin(2 * math.pi * f * seg) * np.exp(-seg / rng.uniform(0.004, 0.015)) * rng.uniform(0.2, 1.0)
x += glass * 0.35
# Kaykay yerde savrulup takırdar
for i in range(7):
    off = 0.35 + i * rng.uniform(0.1, 0.19)
    if off > sec - 0.15:
        break
    k = highpass(noise(0.12), 1200) * env(0.12, 0.0004, 0.012) + bandpass(noise(0.12), 1500, 4.0) * env(0.12, 0.0004, 0.03) * 1.4
    k += np.sin(2 * math.pi * 140 * np.arange(len(k)) / SR) * env(0.12, 0.001, 0.03) * 0.8
    j = int(off * SR)
    x[j:j + len(k)] += k[: len(x) - j] * (0.9 - i * 0.11)
# Yüksek ve dolgun dursun: hafif doyurma (sıkıştırma gibi)
x = np.tanh(x * 1.6)
save("carpma", x, 0.95)

# ---------- Kornalar (iki çeşit) ----------
def horn(sec, freqs, beeps):
    tt = t(sec)
    x = np.zeros_like(tt)
    for f in freqs:
        ph = (tt * f) % 1.0
        x += np.where(ph < 0.5, 1.0, -1.0) * 0.5 + (2 * ph - 1) * 0.3
    x = lowpass(x, 2200)
    gate = np.zeros_like(tt)
    for b0, b1 in beeps:
        gate += ((tt >= b0) & (tt < b1)).astype(float)
    return x * lowpass(gate, 60)
save("korna_1", horn(0.7, [415, 523], [(0.0, 0.45)]), 0.7)
save("korna_2", horn(0.75, [370, 466], [(0.0, 0.14), (0.24, 0.6)]), 0.7)

# ---------- Rampa: yerden toprak / kaya kütlesi çıkar (gürleme + çatırtı + taş sesleri) ----------
def rampa_sesi(sec, guc):
    tt = t(sec)
    # Derin gürleme: alçak geçirilmiş kahverengi gürültü, hızla yükselip yavaş söner
    rum = lowpass(brown(sec), 140) * env(sec, 0.04, sec * 0.35) * 2.5
    rum += np.sin(2 * math.pi * (48 - 14 * tt / sec) * tt) * env(sec, 0.03, sec * 0.3) * 0.6
    # Zemin kırılması: kısa, kalın çatırtılar (ilk yarı)
    crack = np.zeros_like(tt)
    for _ in range(int(14 * guc)):
        j = int(rng.uniform(0.0, sec * 0.55) ** 1.3 * SR)
        n = int(rng.uniform(0.03, 0.09) * SR)
        if j + n >= len(crack):
            continue
        seg = bandpass(noise(n / SR), rng.uniform(350, 1400), 1.2) * env(n / SR, 0.001, rng.uniform(0.01, 0.03))
        crack[j:j + len(seg)] += seg * rng.uniform(0.4, 1.0)
    # Düşen taşlar / toprak serpintisi (sonda)
    peb = np.zeros_like(tt)
    for _ in range(int(40 * guc)):
        j = int(rng.uniform(sec * 0.25, sec * 0.95) * SR)
        n = int(0.025 * SR)
        if j + n >= len(peb):
            continue
        seg = highpass(noise(n / SR), 1800) * env(n / SR, 0.0005, rng.uniform(0.003, 0.008))
        peb[j:j + len(seg)] += seg * rng.uniform(0.1, 0.45)
    return np.tanh((rum + crack * 1.6 + peb) * 1.3)

save("rampa", rampa_sesi(1.4, 1.0), 0.95)
save("rampa_bat", rampa_sesi(1.0, 0.5), 0.8)
