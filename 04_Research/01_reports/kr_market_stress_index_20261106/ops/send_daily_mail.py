#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""스트레스 일보 메일 — daily/latest 의 PDF 일보 + 엑셀 대시보드를 ops/mail_config.json 수신자에게 보낸다(도훈 11-06).

- 기준일당 1통: 보낸 뒤 daily/<기준일>/mail_sent.json 을 남기고, 같은 기준일은 다시 보내지 않는다(--force 로만).
- 발신 = SMTP(기본 smtp.gmail.com:587 STARTTLS) · 계정 · 앱 비밀번호 = 사용자 환경 변수 QVEST_MAIL_USER · QVEST_MAIL_APP_PASSWORD
  (값은 저장소 · 로그 · 출력에 남기지 않는다 · 예약 작업 셸에 없으면 사용자 범위 환경 변수를 읽는다). 없으면 '자격 없음'으로 건너뜀(rc 0).
- 본문 = latest.json 요약(점수 · 순위 · 단계 · 기준일) — 숫자는 일보 산출값 그대로.
실행: <repo>/.venv_qvest_ml/Scripts/python.exe ops/send_daily_mail.py [--dry-run] [--force]
  --dry-run = 메시지를 만들어 크기 · 제목 · 첨부만 출력(보내지 않음 · 자격 불필요).
"""
from __future__ import annotations

import datetime as dt
import json
import os
import smtplib
import ssl
import subprocess
import sys
from email.message import EmailMessage
from email.utils import formataddr

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
REP = os.path.dirname(HERE)
LATEST = REP + "/daily/latest"


def user_env(name):
    v = os.environ.get(name)
    if v:
        return v
    try:      # 예약 작업 · 도구 셸엔 사용자 범위 변수가 없을 수 있다(값은 출력하지 않음)
        out = subprocess.run(["powershell", "-NoProfile", "-Command", f"[Environment]::GetEnvironmentVariable('{name}','User')"],
                             capture_output=True, text=True, timeout=30).stdout.strip()
        return out or None
    except Exception:  # noqa: BLE001
        return None


def build(cfg, lt):
    day = lt["day"]
    top = max(1, round(100 - 100 * lt["score_pct"]))
    lev = round(lt.get("level", 0))
    msg = EmailMessage()
    msg["Subject"] = cfg["subject"].format(day=day, level=lev, tier=lt["tier"], top=top)
    msg["To"] = ", ".join(cfg["to"])
    refs = " · ".join(f"{r['label']} {round(r['level'])}" for r in lt.get("ref_marks", []))
    text = (f"국내 자본시장 스트레스 일일 보고 — {day} 기준\n\n"
            f"스트레스 점수 {lev} / 100 (높을수록 나쁨) · 2006년 이후 거래일 중 나쁜 순 상위 {top}% · 경보 단계 {lt['tier']}\n"
            f"점수 눈금: {refs}\n\n"
            f"첨부: ① 일일 보고서(PDF) ② 원자료 엑셀 대시보드(xlsx)\n"
            f"연구 시제품(KR-CISS v1) — 투자 판단의 유일한 근거로 쓰지 마시기 바랍니다. 자동 발송 메일입니다.\n")
    html = (f"<div style='font-family:Malgun Gothic,sans-serif;font-size:13px;color:#111'>"
            f"<p style='font-size:15px;font-weight:700;margin:0 0 6px'>국내 자본시장 스트레스 일일 보고 — {day} 기준</p>"
            f"<table style='border-collapse:collapse;margin:6px 0'><tr>"
            f"<td style='padding:6px 12px;border:1px solid #ccc'>스트레스 점수<br><b style='font-size:20px;color:#c62828'>{lev}</b> / 100</td>"
            f"<td style='padding:6px 12px;border:1px solid #ccc'>역대 순위<br><b style='font-size:16px'>나쁜 순 상위 {top}%</b></td>"
            f"<td style='padding:6px 12px;border:1px solid #ccc'>경보 단계<br><b style='font-size:16px'>{lt['tier']}</b></td></tr></table>"
            f"<p style='color:#444;margin:4px 0'>점수 눈금: {refs}</p>"
            f"<p style='margin:8px 0 2px'>첨부 ① 일일 보고서(PDF) ② 원자료 엑셀 대시보드(xlsx)</p>"
            f"<p style='color:#777;font-size:11px;margin:10px 0 0'>연구 시제품(KR-CISS v1) — 투자 판단의 유일한 근거로 쓰지 마시기 바랍니다. 자동 발송 메일입니다.</p></div>")
    msg.set_content(text)
    msg.add_alternative(html, subtype="html")
    total = 0
    for src, name in zip(cfg["attach"], cfg["attach_names"]):
        p = f"{LATEST}/{src}"
        data = open(p, "rb").read()
        total += len(data)
        mt = ("application", "pdf") if p.endswith(".pdf") else ("application", "vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        msg.add_attachment(data, maintype=mt[0], subtype=mt[1], filename=name.format(day=day))
    if total > cfg.get("max_total_mb", 20) * 1e6:
        raise RuntimeError(f"첨부 합계 {total / 1e6:.1f} MB > 상한 {cfg.get('max_total_mb')} MB")
    return msg, total


def main():
    dry, force = "--dry-run" in sys.argv, "--force" in sys.argv
    cfg = json.load(open(HERE + "/mail_config.json", encoding="utf-8"))
    if not cfg.get("enabled"):
        print("[mail] 꺼짐(mail_config.json enabled=false)")
        return 0
    lt = json.load(open(LATEST + "/latest.json", encoding="utf-8"))
    day = lt["day"]
    stamp = f"{REP}/daily/{day}/mail_sent.json"
    if os.path.exists(stamp) and not force and not dry:
        print(f"[mail] {day} 이미 보냄({json.load(open(stamp, encoding='utf-8')).get('sent_at')}) — 건너뜀")
        return 0
    msg, total = build(cfg, lt)
    print(f"[mail] 제목 = {msg['Subject']} · 받는 사람 = {msg['To']} · 첨부 {total / 1e6:.1f} MB")
    if dry:
        print("[mail] --dry-run — 보내지 않음")
        return 0
    user, pw = user_env("QVEST_MAIL_USER"), user_env("QVEST_MAIL_APP_PASSWORD")
    if not user or not pw:
        print("[mail] ★발신 자격 없음(사용자 환경 변수 QVEST_MAIL_USER · QVEST_MAIL_APP_PASSWORD) — 보내지 않음. 설정은 ops/README.md")
        return 0
    msg["From"] = formataddr(("Qvest 스트레스 일보", user))
    with smtplib.SMTP(cfg["smtp_host"], cfg["smtp_port"], timeout=120) as s:
        s.starttls(context=ssl.create_default_context())
        s.login(user, pw)
        s.send_message(msg)
    os.makedirs(os.path.dirname(stamp), exist_ok=True)
    json.dump({"day": day, "sent_at": dt.datetime.now().isoformat(timespec="seconds"), "to": cfg["to"], "subject": msg["Subject"],
               "attach_mb": round(total / 1e6, 2)}, open(stamp, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"[mail] 보냄 → {', '.join(cfg['to'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
