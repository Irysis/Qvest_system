#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Gmail API 발송 — OAuth 2.0(설치형 앱 · PKCE) · 권한 = gmail.send 하나(메일 보내기만 · 읽기/삭제 불가) · 비밀번호 저장 없음.

도훈 11-06 "앱 비밀번호는 보안 이슈 → 니가 알아서 메일 보내게 세팅해줘". Google 이 프로그램 연결에 권장하는 방식.
비밀(갱신 토큰)은 저장소 · OneDrive 밖 %LOCALAPPDATA%\\Qvest\\secrets\\ 에 Windows DPAPI(현재 사용자)로 암호화해 둔다
→ 이 PC 의 이 Windows 계정에서만 풀린다. 끊기 = Google 계정 → 보안 → 타사 앱 연결에서 'Qvest' 삭제, 또는 토큰 파일 삭제.

준비(한 번): Google Cloud 콘솔에서 Gmail API 사용 · OAuth 클라이언트(데스크톱 앱) 생성 → JSON 을 secrets\\gmail_client.json 으로.
승인(한 번):
  python gmail_oauth.py start                 → 승인 주소 출력(브라우저에서 열어 '허용')
  python gmail_oauth.py finish "<돌아온 주소>" → http://127.0.0.1:8765/?code=… 주소(페이지가 안 열려도 주소창의 값)로 토큰 교환 · 암호화 저장
  python gmail_oauth.py status                → 클라이언트 · 토큰 유무 · 접근 토큰 갱신 시험(보내지 않음)
발송(다른 모듈): send_raw(bytes) — RFC 822 메시지를 업로드 엔드포인트로(최대 35 MB).
"""
from __future__ import annotations

import base64
import ctypes
import ctypes.wintypes as wt
import datetime as dt
import hashlib
import json
import os
import secrets
import sys
import urllib.parse

import requests

SCOPE = "https://www.googleapis.com/auth/gmail.send"
REDIRECT = "http://127.0.0.1:8765/"
SECRETS = os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), "Qvest", "secrets")
CLIENT = os.path.join(SECRETS, "gmail_client.json")
TOKEN = os.path.join(SECRETS, "gmail_token.dpapi")
PENDING = os.path.join(SECRETS, "gmail_oauth_pending.json")


# ── Windows DPAPI(현재 사용자) ──────────────────────────────────────────────────
class _BLOB(ctypes.Structure):
    _fields_ = [("cbData", wt.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]


def _in(b: bytes):
    buf = ctypes.create_string_buffer(b, len(b))
    return _BLOB(len(b), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char))), buf


def _dpapi(b: bytes, protect: bool) -> bytes:
    blob, _keep = _in(b)
    out = _BLOB()
    fn = ctypes.windll.crypt32.CryptProtectData if protect else ctypes.windll.crypt32.CryptUnprotectData
    desc = ctypes.c_wchar_p("Qvest gmail.send token") if protect else None
    if not fn(ctypes.byref(blob), desc, None, None, None, 0x1, ctypes.byref(out)):      # 0x1 = UI 금지
        raise ctypes.WinError()
    try:
        return ctypes.string_at(out.pbData, out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(ctypes.cast(out.pbData, ctypes.c_void_p))


def _client():
    if not os.path.exists(CLIENT):
        raise FileNotFoundError(f"OAuth 클라이언트 파일 없음: {CLIENT}")
    c = json.load(open(CLIENT, encoding="utf-8"))
    c = c.get("installed") or c.get("web") or c
    return c["client_id"], c.get("client_secret", "")


def save_token(tok: dict):
    os.makedirs(SECRETS, exist_ok=True)
    open(TOKEN, "wb").write(_dpapi(json.dumps(tok).encode("utf-8"), True))


def load_token() -> dict:
    return json.loads(_dpapi(open(TOKEN, "rb").read(), False).decode("utf-8"))


# ── 승인 ──────────────────────────────────────────────────────────────────────
def start():
    cid, _ = _client()
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(48)).rstrip(b"=").decode()
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    os.makedirs(SECRETS, exist_ok=True)
    json.dump({"verifier": verifier, "state": state, "at": dt.datetime.now().isoformat(timespec="seconds")}, open(PENDING, "w", encoding="utf-8"))
    q = {"client_id": cid, "redirect_uri": REDIRECT, "response_type": "code", "scope": SCOPE, "access_type": "offline",
         "prompt": "consent", "code_challenge": challenge, "code_challenge_method": "S256", "state": state}
    print("https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode(q))


def finish(redirected: str):
    cid, csec = _client()
    p = json.load(open(PENDING, encoding="utf-8"))
    qs = urllib.parse.parse_qs(urllib.parse.urlparse(redirected).query)
    if qs.get("error"):
        raise SystemExit(f"승인 거부: {qs['error'][0]}")
    if qs.get("state", [""])[0] != p["state"]:
        raise SystemExit("state 불일치 — 다른 승인 시도의 주소다. start 부터 다시")
    r = requests.post("https://oauth2.googleapis.com/token", timeout=60, data={
        "client_id": cid, "client_secret": csec, "code": qs["code"][0], "code_verifier": p["verifier"],
        "grant_type": "authorization_code", "redirect_uri": REDIRECT})
    j = r.json()
    if r.status_code != 200 or "refresh_token" not in j:
        raise SystemExit(f"토큰 교환 실패 {r.status_code}: {j.get('error')} {j.get('error_description', '')}")
    if SCOPE not in j.get("scope", ""):
        raise SystemExit(f"받은 권한이 gmail.send 가 아님: {j.get('scope')}")
    save_token({"refresh_token": j["refresh_token"], "client_id": cid, "scope": j.get("scope"), "created": dt.datetime.now().isoformat(timespec="seconds")})
    os.remove(PENDING)
    print(f"[gmail] 승인 저장(권한 = {j.get('scope')}) → {TOKEN}(DPAPI 암호화)")


def access_token() -> str:
    cid, csec = _client()
    t = load_token()
    r = requests.post("https://oauth2.googleapis.com/token", timeout=60, data={
        "client_id": cid, "client_secret": csec, "refresh_token": t["refresh_token"], "grant_type": "refresh_token"})
    j = r.json()
    if r.status_code != 200:
        raise RuntimeError(f"접근 토큰 갱신 실패 {r.status_code}: {j.get('error')} — 승인이 끊겼으면 gmail_oauth.py start/finish 로 다시 승인")
    return j["access_token"]


def send_raw(raw: bytes) -> str:
    """RFC 822 바이트를 그대로 보낸다(업로드 엔드포인트 · 최대 35 MB). 반환 = Gmail 메시지 id."""
    r = requests.post("https://gmail.googleapis.com/upload/gmail/v1/users/me/messages/send?uploadType=media", timeout=300,
                      headers={"Authorization": f"Bearer {access_token()}", "Content-Type": "message/rfc822"}, data=raw)
    if r.status_code != 200:
        raise RuntimeError(f"Gmail 발송 실패 {r.status_code}: {r.text[:300]}")
    return r.json().get("id", "")


def status():
    print("client:", os.path.exists(CLIENT), CLIENT)
    print("token :", os.path.exists(TOKEN), TOKEN)
    if os.path.exists(CLIENT) and os.path.exists(TOKEN):
        t = load_token()
        print("scope :", t.get("scope"), "· created", t.get("created"))
        access_token()
        print("refresh: OK(접근 토큰 갱신 성공 · 보내지 않음)")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "start":
        start()
    elif cmd == "finish":
        finish(sys.argv[2])
    elif cmd == "status":
        status()
    elif cmd == "selftest-dpapi":
        x = b"qvest-dpapi-roundtrip"
        y = _dpapi(x, True)
        print("dpapi roundtrip", _dpapi(y, False) == x, "· ciphertext", len(y), "bytes · plaintext-visible", x in y)
    else:
        raise SystemExit("usage: gmail_oauth.py start | finish <redirected-url> | status | selftest-dpapi")
