#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""transcript_surrogate_scan.py — Claude Code 세션 transcript lone-surrogate 포렌식 (v8.1.2)

용도: API 400 "invalid high/low surrogate" 발생 시 어느 세션·레코드·출처에서
lone surrogate(U+D800-DFFF)가 대화에 주입됐는지 특정. 2026-06-11 사건의
진단 절차(8개 세션 오염 → hook additionalContext 특정)를 도구화.

사용:
  PYTHONUTF8=1 python3 02_Infrastructure/ops/transcript_surrogate_scan.py            # 최근 12개 스캔
  PYTHONUTF8=1 python3 02_Infrastructure/ops/transcript_surrogate_scan.py --all      # 전체
  PYTHONUTF8=1 python3 02_Infrastructure/ops/transcript_surrogate_scan.py --fix      # 오염분 백업 후 스크럽
  (인자로 .jsonl 경로를 직접 주면 해당 파일만)

판정:
  POISONED = 파싱된 string 값 안에 실제 lone surrogate 문자 존재 (그 세션의 모든
  후속 요청이 400 — resume도 불가). --fix 로 백업(.surrogate_bak) 후 '?' 치환하면 복구.
  API_ERR  = "invalid high/low surrogate" 에러 레코드 수 (참고용 — 오염 결과의 흔적).

출력은 ASCII-safe (surrogate는 [S]로 표시). 모든 출력 라인 BMP-only.
"""
import glob
import json
import os
import shutil
import sys

TRANSCRIPT_DIR = "C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot"


def safe(s):
    return "".join("[S]" if 0xD800 <= ord(ch) <= 0xDFFF else (ch if ord(ch) <= 0xFFFF else "?") for ch in s)


def walk_strings(o, hits):
    if isinstance(o, str):
        n = sum(1 for ch in o if 0xD800 <= ord(ch) <= 0xDFFF)
        if n:
            hits.append((n, o))
    elif isinstance(o, list):
        for x in o:
            walk_strings(x, hits)
    elif isinstance(o, dict):
        for v in o.values():
            walk_strings(v, hits)


def scrub(o):
    if isinstance(o, str):
        return "".join("?" if 0xD800 <= ord(ch) <= 0xDFFF else ch for ch in o)
    if isinstance(o, list):
        return [scrub(x) for x in o]
    if isinstance(o, dict):
        return {k: scrub(v) for k, v in o.items()}
    return o


def source_hint(rec):
    """오염 레코드의 출처 단서: hook 이름 / tool / 레코드 타입."""
    att = rec.get("attachment") or {}
    if att:
        return f"attachment[{att.get('type','?')}] hook={att.get('hookName','-')}"
    msg = rec.get("message") or {}
    cont = msg.get("content")
    if isinstance(cont, list):
        for c in cont:
            if isinstance(c, dict):
                if c.get("type") == "tool_result":
                    return f"tool_result id={str(c.get('tool_use_id'))[:24]}"
                if c.get("type") == "tool_use":
                    return f"tool_use {c.get('name')}"
    return f"type={rec.get('type','?')}"


def scan_file(path, fix=False):
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    poisoned = []  # (idx, n_sur, hint, sample)
    api_err = 0
    for i, line in enumerate(lines):
        if "invalid high surrogate" in line or "invalid low surrogate" in line:
            try:
                r = json.loads(line)
                if r.get("isApiErrorMessage"):
                    api_err += 1
            except Exception:
                pass
        try:
            rec = json.loads(line)
        except Exception:
            continue
        hits = []
        walk_strings(rec, hits)
        if hits:
            n = sum(h[0] for h in hits)
            poisoned.append((i, n, source_hint(rec), safe(hits[0][1][:90])))

    name = os.path.basename(path)
    if not poisoned:
        print(f"CLEAN    {name}  (api_err_records={api_err})")
        return False
    print(f"POISONED {name}  records={len(poisoned)} surrogates={sum(p[1] for p in poisoned)} api_err={api_err}")
    for i, n, hint, sample in poisoned[:5]:
        print(f"    rec#{i} sur={n} src={hint}")
        print(f"      sample: {sample}")
    if fix:
        bak = path + ".surrogate_bak"
        if not os.path.exists(bak):
            shutil.copy2(path, bak)
        out = []
        for line in lines:
            try:
                out.append(json.dumps(scrub(json.loads(line)), ensure_ascii=False))
            except Exception:
                out.append(line)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
        print(f"    -> FIXED (backup: {os.path.basename(bak)})")
    return True


def main():
    args = [a for a in sys.argv[1:]]
    fix = "--fix" in args
    scan_all = "--all" in args
    explicit = [a for a in args if a.endswith(".jsonl")]

    if explicit:
        files = explicit
    else:
        files = sorted(glob.glob(os.path.join(TRANSCRIPT_DIR, "*.jsonl")), key=os.path.getmtime, reverse=True)
        if not scan_all:
            files = files[:12]
    n_poison = sum(1 for f in files if scan_file(f, fix=fix))
    print(f"\nRESULT: {n_poison} poisoned / {len(files)} scanned" + ("" if fix or not n_poison else "  (--fix 로 복구 가능)"))
    return 1 if n_poison and not fix else 0


if __name__ == "__main__":
    sys.exit(main())
