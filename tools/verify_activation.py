#!/usr/bin/env python3
"""اختبارات رمز التفعيل. تُشغَّل: python3 -I tools/verify_activation.py (تحتاج مكتبة cryptography)."""

from __future__ import annotations

import importlib.util
import os
import stat
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

_path = Path(__file__).resolve().parent / "activation.py"
_spec = importlib.util.spec_from_file_location("activation", _path)
assert _spec is not None and _spec.loader is not None
act = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(act)

DEVICE = "K7QZ2MWD4A"
OTHER_DEVICE = "K7QZ2MWD4B"
ISSUED = "20261121"


def expect_error(fn, label: str) -> None:
    try:
        fn()
    except act.ActivationError:
        return
    raise AssertionError(f"كان يجب أن يُرفض: {label}")


def test_round_trip() -> None:
    key = Ed25519PrivateKey.generate()
    code = act.sign_code(key, "agent", DEVICE, ISSUED)
    info = act.verify_code(key.public_key(), code, DEVICE)
    assert info == {"role": "agent", "device": DEVICE, "issued": ISSUED}, info
    assert code.startswith("MKZ1-")
    assert len(code) < 200, len(code)  # يُلصق من واتساب، لا يُكتب باليد


def test_bound_to_device() -> None:
    key = Ed25519PrivateKey.generate()
    code = act.sign_code(key, "agent", DEVICE, ISSUED)
    expect_error(lambda: act.verify_code(key.public_key(), code, OTHER_DEVICE), "جهاز آخر")


def test_wrong_key() -> None:
    code = act.sign_code(Ed25519PrivateKey.generate(), "agent", DEVICE, ISSUED)
    other = Ed25519PrivateKey.generate().public_key()
    expect_error(lambda: act.verify_code(other, code, DEVICE), "مفتاح مختلف")


def test_tampered() -> None:
    key = Ed25519PrivateKey.generate()
    code = act.sign_code(key, "agent", DEVICE, ISSUED)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    original = act.verify_code(key.public_key(), code, DEVICE)
    # تغيير حرف واحد في كل موضع من الجسم: لا يُقبل أي رمز معدّل.
    # الاستثناء الوحيد: آخر حرف يحمل بتّين فقط من البيانات و3 بتات حشو، فتغيير الحشو
    # يفك إلى البايتات نفسها تماماً. هذا لا يضعف شيئاً لأن التوقيع يغطي البايتات المفكوكة.
    body_positions = [i for i, ch in enumerate(code) if i >= 5 and ch != "-"]
    last = body_positions[-1]
    for i in body_positions:
        swapped = alphabet[(alphabet.index(code[i]) + 1) % 32]
        broken = code[:i] + swapped + code[i + 1 :]
        try:
            info = act.verify_code(key.public_key(), broken, DEVICE)
        except act.ActivationError:
            continue
        assert i == last and info == original, f"قُبل رمز معدّل في الموضع {i}"
    expect_error(lambda: act.verify_code(key.public_key(), code[:-6], DEVICE), "رمز مقطوع")
    expect_error(lambda: act.verify_code(key.public_key(), "MKZ1-", DEVICE), "رمز فارغ")
    expect_error(lambda: act.verify_code(key.public_key(), "XYZ9-AAAA", DEVICE), "بادئة خاطئة")
    expect_error(lambda: act.verify_code(key.public_key(), code + "!", DEVICE), "حرف غريب")


def test_forgiving_input() -> None:
    key = Ed25519PrivateKey.generate()
    code = act.sign_code(key, "owner", DEVICE, ISSUED)
    messy = "  " + code.lower().replace("-", " ") + "\n"
    info = act.verify_code(key.public_key(), messy, "k7qz2-mwd4a")
    assert info["role"] == "owner"


def test_bad_inputs_at_signing() -> None:
    key = Ed25519PrivateKey.generate()
    expect_error(lambda: act.sign_code(key, "admin", DEVICE, ISSUED), "دور غير معروف")
    expect_error(lambda: act.sign_code(key, "agent", "SHORT", ISSUED), "كود جهاز قصير")
    expect_error(lambda: act.sign_code(key, "agent", "K7QZ2MWD40", ISSUED), "الرقم 0 ليس في الأبجدية")
    expect_error(lambda: act.sign_code(key, "agent", DEVICE, "2026-11-21"), "تاريخ بصيغة خاطئة")


def test_keygen_files() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "private" / "k.pem"
        pub = act.keygen(path)
        mode = stat.S_IMODE(os.stat(path).st_mode)
        assert mode == 0o600, oct(mode)
        expect_error(lambda: act.keygen(path), "عدم استبدال المفتاح")
        loaded = act.load_private(path)
        code = act.sign_code(loaded, "agent", DEVICE, ISSUED)
        pub_again = act.public_from_b64(act.public_b64(pub))
        assert act.verify_code(pub_again, code, DEVICE)["device"] == DEVICE
        # CLI من البداية للنهاية
        assert act.main(["--key", str(path), "sign", "--device", DEVICE]) == 0
        assert act.main(["--key", str(path), "pubkey"]) == 0


def main() -> None:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in tests:
        fn()
        print("PASS", fn.__name__)
    print(f"{len(tests)}/{len(tests)} passed")


if __name__ == "__main__":
    main()
