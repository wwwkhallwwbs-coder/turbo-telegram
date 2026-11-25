#!/usr/bin/env python3
"""مولّد رموز التفعيل (للمصمم فقط).

يوقّع رمز التفعيل بمفتاح Ed25519 خاص. التطبيق يحمل المفتاح العام فقط،
فلا يستطيع أحد إنشاء رمز صالح، ولا يعمل الرمز على جهاز غير الذي صدر له.

الأوامر:
  keygen            إنشاء زوج المفاتيح (مرة واحدة فقط)، ويطبع المفتاح العام للتطبيق
  pubkey            طباعة المفتاح العام من المفتاح الخاص
  sign              إصدار رمز لجهاز: --device كود-الجهاز --role agent
  verify            فحص رمز كما يفعل التطبيق: --code ... --device ... --pubkey ...

صيغة الرمز (نفسها في Dart لاحقاً، انظر docs/ACTIVATION.md):
  MKZ1-<Base32(توقيع 64 بايت || نص الحمولة)>   مقسّمة إلى مجموعات من 5 أحرف
  الحمولة: MKZ1|<role>|<كود الجهاز>|<تاريخ الإصدار YYYYMMDD>

المفتاح الخاص يُحفظ في tools/private/ (مستثنى من git). لا يُرفع ولا يُرسل لأحد.
"""

from __future__ import annotations

import argparse
import base64
import datetime
import os
import re
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

VERSION = "MKZ1"
ROLES = ("agent", "owner")
SIG_LEN = 64
DEVICE_RE = re.compile(r"^[A-Z2-7]{10}$")  # 10 حرفاً من أبجدية Base32، 50 بت
ISSUED_RE = re.compile(r"^\d{8}$")
DEFAULT_KEY = Path(__file__).resolve().parent / "private" / "activation_ed25519.pem"


class ActivationError(Exception):
    """رمز غير صالح لأي سبب (الرسالة للمصمم، والتطبيق يعرض رسالة موحدة)."""


def normalize_device(text: str) -> str:
    device = re.sub(r"[\s\-]", "", text).upper()
    if not DEVICE_RE.match(device):
        raise ActivationError("كود الجهاز يجب أن يكون 10 أحرف (A-Z و2-7)")
    return device


def _group(text: str, size: int = 5) -> str:
    return "-".join(text[i : i + size] for i in range(0, len(text), size))


def make_payload(role: str, device: str, issued: str) -> bytes:
    if role not in ROLES:
        raise ActivationError(f"الدور يجب أن يكون واحداً من {ROLES}")
    if not ISSUED_RE.match(issued):
        raise ActivationError("تاريخ الإصدار بصيغة YYYYMMDD")
    return f"{VERSION}|{role}|{normalize_device(device)}|{issued}".encode("ascii")


def sign_code(private_key: Ed25519PrivateKey, role: str, device: str, issued: str) -> str:
    payload = make_payload(role, device, issued)
    body = private_key.sign(payload) + payload
    encoded = base64.b32encode(body).decode("ascii").rstrip("=")
    return f"{VERSION}-{_group(encoded)}"


def verify_code(public_key: Ed25519PublicKey, code: str, device: str) -> dict[str, str]:
    """نفس خطوات التطبيق. يرجع الحقول عند النجاح، أو يرفع ActivationError."""
    expected_device = normalize_device(device)
    compact = re.sub(r"[\s\-]", "", code).upper()
    if not compact.startswith(VERSION):
        raise ActivationError("صيغة الرمز غير معروفة")
    encoded = compact[len(VERSION) :]
    encoded += "=" * (-len(encoded) % 8)
    try:
        body = base64.b32decode(encoded)
    except ValueError as exc:
        raise ActivationError("الرمز يحوي أحرفاً غير صالحة") from exc
    if len(body) <= SIG_LEN:
        raise ActivationError("الرمز قصير")
    signature, payload = body[:SIG_LEN], body[SIG_LEN:]
    try:
        public_key.verify(signature, payload)
    except InvalidSignature as exc:
        raise ActivationError("التوقيع غير صحيح") from exc
    try:
        version, role, device_in_code, issued = payload.decode("ascii").split("|")
    except (UnicodeDecodeError, ValueError) as exc:
        raise ActivationError("الحمولة تالفة") from exc
    if version != VERSION or role not in ROLES or not ISSUED_RE.match(issued):
        raise ActivationError("الحمولة غير مدعومة")
    if device_in_code != expected_device:
        raise ActivationError("الرمز مخصص لجهاز آخر")
    return {"role": role, "device": device_in_code, "issued": issued}


def load_private(path: Path) -> Ed25519PrivateKey:
    if not path.exists():
        raise ActivationError(f"لا يوجد مفتاح خاص في {path}. شغّل keygen أولاً")
    key = serialization.load_pem_private_key(path.read_bytes(), password=None)
    if not isinstance(key, Ed25519PrivateKey):
        raise ActivationError("المفتاح ليس Ed25519")
    return key


def public_b64(public_key: Ed25519PublicKey) -> str:
    raw = public_key.public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    return base64.b64encode(raw).decode("ascii")


def public_from_b64(text: str) -> Ed25519PublicKey:
    return Ed25519PublicKey.from_public_bytes(base64.b64decode(text))


def keygen(path: Path) -> Ed25519PublicKey:
    if path.exists():
        raise ActivationError(
            f"المفتاح موجود في {path}. لن أستبدله، فاستبداله يُبطل كل الرموز الصادرة"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    key = Ed25519PrivateKey.generate()
    pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(pem)
    return key.public_key()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="رموز تفعيل مخبزك")
    parser.add_argument("--key", type=Path, default=DEFAULT_KEY, help="مسار المفتاح الخاص")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("keygen")
    sub.add_parser("pubkey")
    p_sign = sub.add_parser("sign")
    p_sign.add_argument("--device", required=True)
    p_sign.add_argument("--role", choices=ROLES, default="agent")
    p_sign.add_argument("--issued", default=datetime.date.today().strftime("%Y%m%d"))
    p_verify = sub.add_parser("verify")
    p_verify.add_argument("--code", required=True)
    p_verify.add_argument("--device", required=True)
    p_verify.add_argument("--pubkey", required=True, help="المفتاح العام Base64")
    args = parser.parse_args(argv)

    try:
        if args.cmd == "keygen":
            pub = keygen(args.key)
            print(f"تم إنشاء المفتاح الخاص: {args.key}")
            print("احفظ نسخة احتياطية منه في مكان آمن خارج المستودع.")
            print(f"المفتاح العام (يوضع في التطبيق): {public_b64(pub)}")
        elif args.cmd == "pubkey":
            print(public_b64(load_private(args.key).public_key()))
        elif args.cmd == "sign":
            print(sign_code(load_private(args.key), args.role, args.device, args.issued))
        else:
            info = verify_code(public_from_b64(args.pubkey), args.code, args.device)
            print("صالح:", info)
    except ActivationError as exc:
        print(f"خطأ: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
