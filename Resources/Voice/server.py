"""Распознавание речи для голосового ввода Lumen.

Отдельный процесс рядом со Swift-приложением, говорит с ним через stdin/stdout.
Модели - GigaAM v3 (русский) и Parakeet (английский) из FlowLocal: берём его
Python и его папку моделей только на чтение. Ничего не качаем и не удаляем:
если чего-то нет, сообщаем об ошибке, и Lumen пишет человеку, что поставить.

Протокол - строки JSON; звук идёт сразу после заголовка сырыми байтами
(float32 little-endian, 16 кГц, моно):

    -> {"cmd": "transcribe", "id": 3, "lang": "ru", "samples": 24000} + байты
    <- {"id": 3, "text": "привет, как дела?", "sec": 0.12}

    <- {"event": "ready"}
    <- {"event": "error", "message": "..."}

Проверка без приложения:

    PY="$HOME/Library/Application Support/FlowLocal/Python/bin/python3"
    "$PY" server.py --file запись.wav [ru|en]
"""

import json
import os
import sys
import time
import wave

# Сеть не нужна: не хватает файлов модели - пусть будет ошибка, а не скачивание
# сотен мегабайт в чужую папку.
os.environ.setdefault("HF_HUB_OFFLINE", "1")

import numpy as np  # noqa: E402

SR = 16000
MODELS_DIR = os.environ.get("LUMEN_VOICE_MODELS") or os.path.expanduser(
    "~/Library/Application Support/FlowLocal/Models")
MODELS = {"ru": "gigaam-v3-e2e-rnnt", "en": "nemo-parakeet-tdt-0.6b-v2"}
QUANT = "int8"
# GigaAM лучше всего знает куски до ~25 с; длиннее режем по самой тихой паузе.
MAX_SEC = 25.0
SEEK_SEC = 4.0
WIN = SR // 50

_proto = sys.stdout


def emit(obj: dict) -> None:
    _proto.write(json.dumps(obj, ensure_ascii=False) + "\n")
    _proto.flush()


def log(msg: str) -> None:
    sys.stderr.write(f"[lumen-voice] {msg}\n")
    sys.stderr.flush()


def claim_stdout() -> None:
    """Протокол - на своём дескрипторе, fd 1 уводим в stderr: случайный print
    библиотеки не приклеится к строке протокола."""
    global _proto
    fd = os.dup(1)
    os.dup2(2, 1)
    sys.stdout = sys.stderr
    _proto = os.fdopen(fd, "w", buffering=1, encoding="utf-8")


def load(lang: str):
    import onnx_asr
    import onnxruntime as rt

    name = MODELS[lang]
    d = os.path.join(MODELS_DIR, name + "-" + QUANT)
    if not os.path.isdir(d):
        raise FileNotFoundError(f"нет модели: {d}")
    so = rt.SessionOptions()
    so.intra_op_num_threads = 3
    so.inter_op_num_threads = 1
    so.add_session_config_entry("session.force_spinning_stop", "1")
    t0 = time.time()
    model = onnx_asr.load_model(name, path=d, quantization=QUANT,
                                providers=["CPUExecutionProvider"], sess_options=so)
    try:
        model.recognize(np.zeros(SR // 2, dtype=np.float32), sample_rate=SR)
    except Exception as e:  # noqa: BLE001
        log(f"прогрев не удался: {type(e).__name__}: {e}")
    log(f"{name} загружена за {time.time() - t0:.1f} с")
    return model


def pieces(audio: np.ndarray) -> list:
    """Куски не длиннее MAX_SEC, рез - в самой тихой паузе у границы."""
    step = int(MAX_SEC * SR)
    seek = int(SEEK_SEC * SR)
    out, pos = [], 0
    while audio.size - pos > step:
        hard = pos + step
        start = max(pos, hard - seek)
        seg = audio[start:hard]
        n = seg.size // WIN
        if n >= 2:
            power = np.abs(seg[:n * WIN]).reshape(n, WIN).mean(axis=1)
            cut = start + int(np.argmin(power)) * WIN + WIN // 2
        else:
            cut = hard
        cut = max(cut, pos + step // 2)
        out.append(audio[pos:cut])
        pos = cut
    out.append(audio[pos:])
    return out


def recognize(model, audio: np.ndarray) -> str:
    if len(audio) < SR // 5:
        return ""
    # Нормализуем громкость: кто-то говорит тихо, кто-то в самый микрофон.
    peak = float(np.max(np.abs(audio)))
    if peak < 0.003:
        return ""
    audio = (audio * min(0.9 / peak, 20.0)).astype(np.float32)
    parts = []
    for p in pieces(audio):
        t = str(model.recognize(p, sample_rate=SR) or "").strip()
        if t:
            parts.append(t)
    return " ".join(parts)


def read_wav(path: str) -> np.ndarray:
    with wave.open(path, "rb") as w:
        if w.getframerate() != SR or w.getsampwidth() != 2:
            raise ValueError("нужен WAV 16 кГц, 16 бит")
        raw = w.readframes(w.getnframes())
        ch = w.getnchannels()
    a = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    return a


def read_exact(stream, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = stream.read(n - len(buf))
        if not chunk:
            raise EOFError
        buf.extend(chunk)
    return bytes(buf)


def serve() -> None:
    claim_stdout()
    try:
        import onnx_asr  # noqa: F401
        import onnxruntime  # noqa: F401
    except Exception as e:  # noqa: BLE001
        log(f"нет библиотек: {type(e).__name__}: {e}")
        emit({"event": "error", "message": str(e)})
        return
    emit({"event": "ready"})

    models = {}
    stdin = sys.stdin.buffer
    while True:
        line = stdin.readline()
        if not line:
            return  # Lumen закрылся - и мы тоже
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("cmd") != "transcribe":
            continue
        n = int(msg.get("samples", 0))
        try:
            raw = read_exact(stdin, n * 4) if n > 0 else b""
        except EOFError:
            return
        audio = np.frombuffer(raw, dtype="<f4")
        lang = msg.get("lang") if msg.get("lang") in MODELS else "ru"
        t0 = time.time()
        try:
            if lang not in models:
                models[lang] = load(lang)
            text = recognize(models[lang], audio)
            emit({"id": msg.get("id"), "text": text, "sec": round(time.time() - t0, 3)})
        except Exception as e:  # noqa: BLE001
            log(f"ошибка распознавания: {type(e).__name__}: {e}")
            emit({"id": msg.get("id"), "text": "", "error": str(e)})


def main() -> None:
    if len(sys.argv) >= 3 and sys.argv[1] == "--file":
        lang = sys.argv[3] if len(sys.argv) > 3 else "ru"
        model = load(lang)
        t0 = time.time()
        print(recognize(model, read_wav(sys.argv[2])))
        print(f"{time.time() - t0:.2f} с", file=sys.stderr)
        return
    serve()


if __name__ == "__main__":
    main()
