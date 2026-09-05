#!/usr/bin/env python
"""battery_checklist.py — 배터리 로그(test_reinforce_auto.sh 등)를 절 단위 체크리스트(markdown)로 렌더한다.
도훈 2026-09-05: "배터리는 체크리스트로 표현 바꿔도 되지 않아?" — 검사 자체는 안 건드리고 **출력만** 변환한다.
입력: 로그 파일(=== N. 제목 === 헤더 · 'OK'/'FAIL' 판정 줄 · 마지막 {"test":...} 요약). 출력: markdown(stdout 또는 -o).
규칙: 절마다 [x]=전부 OK · [ ]=FAIL 포함 · [-]=판정 줄 0(미실행/스킵). FAIL 줄은 절 아래 들여써서 원문 그대로 남긴다(조용한 요약 아님).
"""
import re, sys, io, json, argparse
ap = argparse.ArgumentParser(); ap.add_argument("log"); ap.add_argument("-o", "--out"); a = ap.parse_args()
lines = io.open(a.log, encoding="utf-8", errors="replace").read().split("\n")
secs, cur, summary = [], None, None
H = re.compile(r"^=== +(\d+[a-z]?)\. +(.*?) +===\s*$")
for l in lines:
    m = H.match(l)
    if m:
        cur = {"no": m.group(1), "title": m.group(2), "ok": 0, "fail": [], "raw_fail": 0}; secs.append(cur); continue
    s = l.strip()
    if s.startswith("OK") and cur is not None: cur["ok"] += 1
    elif s.startswith("FAIL") and cur is not None: cur["fail"].append(s)
    elif s.startswith('{"test"'):
        try: summary = json.loads(s)
        except Exception: pass
out = []
if summary: out.append("# 배터리 체크리스트 — `%s` · 통과 %s / 실패 %s / 총 %s\n" % (summary.get("test"), summary.get("pass"), summary.get("fail"), summary.get("total")))
for s in secs:
    box = "[-]" if (s["ok"] + len(s["fail"])) == 0 else ("[x]" if not s["fail"] else "[ ]")
    out.append("- %s **%s. %s** — OK %d · FAIL %d" % (box, s["no"], s["title"], s["ok"], len(s["fail"])))
    for f in s["fail"]: out.append("    - ✗ " + f[:160])
n_fail_secs = sum(1 for s in secs if s["fail"]); n_skip = sum(1 for s in secs if (s["ok"] + len(s["fail"])) == 0)
out.append("\n절 %d개 · 실패 포함 %d · 판정 0(미실행) %d" % (len(secs), n_fail_secs, n_skip))
txt = "\n".join(out) + "\n"
if a.out: io.open(a.out, "w", encoding="utf-8", newline="\n").write(txt)
sys.stdout.write(txt)
