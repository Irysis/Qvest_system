#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""factor_deep_recheck_run.sh 의 uncertain 큐 산정 블록 — 위반 주입 테스트.

왜 별도 파일인가 (test_alpha_queue_pending.py 와 분리):
  두 스크립트는 같은 결함(id 표기 미정규화)을 공유하지만 **술어가 다르다** —
  이쪽은 `verdict=="uncertain"` 전용(tier-2 심층 재검 대상)이고 산출도 다르다
  (카운트뿐 아니라 factor_recheck_queue_<TODAY>.json 을 **직접 쓴다**).
  술어를 한 파일에 섞으면 어느 쪽 계약을 재는지가 흐려진다. 각자 자기 원본을 추출한다.

원 결함 (2026-08-02 실측):
  route papers[].id = "arxiv:2607.16450" (0727 판) vs done processed[].paper_id = bare
  → `pid not in done` 항상 참 → 08-02 큐가 **3/3 전량 이미 처리분**(참값 0).
  ★표시 버그가 아니다 — morning_run [0.55/3] 이 이 큐로 `claude -p` 심층 재검을 돌리므로
    끝난 논문에 매일 토큰을 태운다.

★검사 설계 — "N 이 줄었다"는 증거가 아니다(검사기를 죽여도 준다). 양방향으로 잰다:
  (A) done 에 있는 건은 표기가 어느 쪽이든 빠지는가
  (B) done 에 없는 신규 uncertain 은 **여전히 잡히는가**
  (C) 산출 큐 파일에 기록되는 id 가 정규화형인가 (하류 재오염 차단)
  legacy(수리 전) 블록을 음성 기준으로 동반 실행 — 전부 PASS 하면 검사가 무력한 것이다.

★검사 대상 = 사본이 아니라 원본 술어.
  2026-08-02 공용 모듈 승격 이후 원본 = `02_Infrastructure/ops/research_pool_predicates.py`
  (구판은 .sh 의 heredoc). 위 원 결함이 alpha_search_queue_run.sh 와 **독립으로 재발**한 것이
  승격 사유였다 — 술어가 2벌이면 수리도 2벌이어야 하고, 그 동기화는 아무도 보증하지 않았다.
  ★배선 단언 동반 — 소비자 .sh 가 실제로 정본을 경유하는지(모듈만 초록인 상태 방지).

실행: "$QVEST_PY" 08_Tests/ops/test_factor_recheck_pending.py
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
# 돌연변이 검사(검사기 자신이 살아 있는지)용 오버라이드. 평시엔 비워 둔다.
TARGET = os.environ.get("QVEST_RECHECK_RUN_SH") or os.path.join(
    ROOT, "02_Infrastructure", "ops", "factor_deep_recheck_run.sh")
PRED = os.environ.get("QVEST_PREDICATES_PY") or os.path.join(
    ROOT, "02_Infrastructure", "ops", "research_pool_predicates.py")
MODULE = object()   # 정본 술어 센티넬 (legacy 문자열 블록과 구분)

# 수리 전 구현(2026-08-02 이전). 음성 기준 전용 — 여기를 "고치지" 말 것.
LEGACY = r'''
import json, sys, glob, os
sd, out = sys.argv[1], sys.argv[2]
today = sys.argv[3] if len(sys.argv) > 3 else None
done=set()
dp=os.path.join(sd,"factor_recheck_done.json")
if os.path.exists(dp):
    try:
        for x in json.load(open(dp,encoding="utf-8")).get("processed",[]):
            pid = x.get("paper_id") if isinstance(x, dict) else x
            if pid: done.add(str(pid))
    except: done=set()
seen={}
for f in sorted(glob.glob(os.path.join(sd,"alpha_search_route_*.json"))):
    try: r=json.load(open(f,encoding="utf-8"))
    except: continue
    for p in r.get("papers",[]):
        fc=p.get("factor_candidate") or {}
        if fc.get("verdict")=="uncertain":
            pid=str(p.get("id") or p.get("arxiv_id") or p.get("paper_id") or "")
            if pid and pid not in done and pid not in seen:
                seen[pid]={"paper_id":pid,"title":p.get("title",""),"source":p.get("source",""),
                           "factor_hint":fc.get("name") or fc.get("factor_hint",""),
                           "prior_verdict":fc.get("verdict"),"prior_reason":fc.get("reason") or fc.get("summary","")}
items=list(seen.values())
json.dump({"date":today,"n":len(items),"items":items},
          open(out,"w",encoding="utf-8"),ensure_ascii=False,indent=2)
print(len(items))
'''


def check_wiring():
    """★배선 단언 — 소비자 .sh 가 정본 술어를 경유하는가 (술어 재분기 방지축)."""
    fails = []
    if not os.path.isfile(PRED):
        fails.append("술어 정본 부재: %s" % PRED)
        return fails
    with open(TARGET, encoding="utf-8") as fh:
        src = fh.read()
    if "recheck-build" not in src:
        fails.append("소비자가 정본 술어를 호출하지 않는다 (recheck-build 호출 부재): %s"
                     % os.path.relpath(TARGET, ROOT))
    if re.search(r"^[^#\n]*<<'PY'", src, re.M):
        fails.append("★heredoc 술어가 되살아났다 — 정의가 다시 2벌로 갈렸다: %s"
                     % os.path.relpath(TARGET, ROOT))
    return fails


def run(block, files):
    """픽스처 디렉터리를 만들고 술어를 돌려 (N, 산출 items) 를 돌려준다.

    block is MODULE → 정본 모듈 CLI(recheck-build) / block is str → legacy 음성 기준.
    """
    with tempfile.TemporaryDirectory() as td:
        sd = os.path.join(td, "sd")
        os.makedirs(sd)
        for name, obj in files.items():
            with open(os.path.join(sd, name), "w", encoding="utf-8") as fh:
                if isinstance(obj, str):
                    fh.write(obj)          # 손상 JSON 주입용 raw
                else:
                    json.dump(obj, fh, ensure_ascii=False)
        out = os.path.join(td, "queue_out.json")
        if block is MODULE:
            cmd, inp = [sys.executable, PRED, "recheck-build", sd, out, "20260802"], None
        else:
            cmd, inp = [sys.executable, "-", sd, out, "20260802"], block
        p = subprocess.run(cmd, input=inp, capture_output=True, text=True)
        if p.returncode != 0:
            return ("ERR:" + p.stderr.strip()[-160:], [])
        items = []
        if os.path.exists(out):
            try:
                items = json.load(open(out, encoding="utf-8")).get("items", [])
            except Exception:
                items = []
        return (p.stdout.strip(), items)


def route(*papers):
    return {"date": "20260802", "papers": list(papers)}


def done(processed):
    # 실 원장 형태 = dict 리스트. bare-string 관용도 유지되는지 함께 본다.
    return {"processed": [p if isinstance(p, (dict, str)) else str(p) for p in processed]}


def unc(pid_key, pid, **kw):
    o = {pid_key: pid, "title": "t", "source": "arxiv",
         "factor_candidate": {"verdict": "uncertain", "name": "hint"}}
    o.update(kw)
    return o


CASES = [
    # ── A: done 에 있으면 표기 무관하게 빠져야 한다 ────────────────────────────
    ("A1 bare id ∈ done → 제외",
     {"alpha_search_route_x.json": route(unc("id", "2607.16450")),
      "factor_recheck_done.json": done([{"paper_id": "2607.16450"}])}, "0", False),

    ("A2 ★원결함 'arxiv:' 접두 id ∈ done(bare) → 제외",
     {"alpha_search_route_x.json": route(unc("id", "arxiv:2607.16450")),
      "factor_recheck_done.json": done([{"paper_id": "2607.16450"}])}, "0", True),

    ("A3 역방향: bare id ∈ done('arxiv:' 접두) → 제외",
     {"alpha_search_route_x.json": route(unc("id", "2607.16450")),
      "factor_recheck_done.json": done([{"paper_id": "arxiv:2607.16450"}])}, "0", True),

    ("A4 버전 접미(v2) + 접두 ∈ done → 제외",
     {"alpha_search_route_x.json": route(unc("id", "arxiv:2607.16450v2")),
      "factor_recheck_done.json": done([{"paper_id": "2607.16450"}])}, "0", True),

    ("A5 URL 형 id ∈ done → 제외",
     {"alpha_search_route_x.json": route(unc("id", "https://arxiv.org/abs/2607.16450")),
      "factor_recheck_done.json": done([{"paper_id": "2607.16450"}])}, "0", True),

    ("A6 done 이 bare 문자열 리스트(구 관용형)여도 제외",
     {"alpha_search_route_x.json": route(unc("id", "arxiv:2607.16450")),
      "factor_recheck_done.json": done(["2607.16450"])}, "0", True),

    # ── B: done 에 없으면 여전히 잡혀야 한다 (검사 사망 아님) ──────────────────
    ("B1 신규 bare uncertain ∉ done → 계수",
     {"alpha_search_route_x.json": route(unc("id", "2699.00001")),
      "factor_recheck_done.json": done([{"paper_id": "2607.16450"}])}, "1", False),

    ("B2 ★신규 'arxiv:' 접두 uncertain ∉ done → 계수(정규화가 다 삼키지 않는다)",
     {"alpha_search_route_x.json": route(unc("id", "arxiv:2699.00002")),
      "factor_recheck_done.json": done([{"paper_id": "2607.16450"}])}, "1", False),

    ("B3 arxiv_id 키(route_0618/0802 스키마) ∉ done → 계수",
     {"alpha_search_route_x.json": route(unc("arxiv_id", "2699.00003")),
      "factor_recheck_done.json": done([])}, "1", False),

    ("B4 done 원장 부재 → 전건 계수(0 으로 삼키지 않는다)",
     {"alpha_search_route_x.json": route(unc("id", "2699.00004"))}, "1", False),

    # ── C: 술어 경계 · 산출 정규화 ────────────────────────────────────────────
    ("C1 verdict=testable 은 이 큐 대상 아님(uncertain 전용 계약 유지)",
     {"alpha_search_route_x.json": route(
         {"id": "2699.00005", "factor_candidate": {"verdict": "testable"}}),
      "factor_recheck_done.json": done([])}, "0", False),

    ("C2 동일 논문이 접두/bare 두 파일에 → 1건 dedup(중복 재검 금지)",
     {"alpha_search_route_a.json": route(unc("id", "arxiv:2699.00006")),
      "alpha_search_route_b.json": route(unc("arxiv_id", "2699.00006")),
      "factor_recheck_done.json": done([])}, "1", True),

    ("C3 손상 JSON 1건이 나머지 계수를 죽이지 않는다(fail-soft 유지)",
     {"alpha_search_route_bad.json": "{ not json",
      "alpha_search_route_ok.json": route(unc("id", "2699.00007")),
      "factor_recheck_done.json": done([])}, "1", False),

    ("C4 픽스처 전무 → 0 (정상 skip 경로)", {}, "0", False),

    ("C5 curated 파일명 id 는 원형 보존(정규화가 파일명을 망가뜨리지 않는다)",
     {"alpha_search_route_x.json": route(unc("id", "MAN_AHL_trend.pdf")),
      "factor_recheck_done.json": done([])}, "1", False),
]

# 산출 큐 파일에 적히는 id 가 정규화형인지 — 하류(프롬프트·done writer) 재오염 차단축
WRITE_CASES = [
    ("W1 ★큐 적재 id 가 정규화형('arxiv:' 접두 제거)",
     {"alpha_search_route_x.json": route(unc("id", "arxiv:2699.00008")),
      "factor_recheck_done.json": done([])}, "2699.00008", True),
    ("W2 curated 파일명은 원형 그대로 적재",
     {"alpha_search_route_x.json": route(unc("id", "GMO_primer.pdf")),
      "factor_recheck_done.json": done([])}, "GMO_primer.pdf", False),
]


def main():
    block = MODULE
    fails, teeth_fail = [], []
    print("술어 정본: %s" % os.path.relpath(PRED, ROOT))
    print("소비자 배선: %s" % os.path.relpath(TARGET, ROOT))
    print("=" * 78)
    _w = check_wiring()
    for w in _w:
        fails.append((("W 배선"), "정본 경유", w))
        print("  [FAIL] W 배선 — %s" % w)
    if not _w:
        print("  [PASS] W 배선: 소비자가 정본 술어를 경유 (heredoc 재분기 없음)")
    for name, files, expect, legacy_differs in CASES:
        got, _ = run(block, files)
        ok = (got == expect)
        lgot, _ = run(LEGACY, files)
        if legacy_differs is True and lgot == expect:
            teeth_fail.append(name)
        tag = ("   [legacy=%s %s]" % (lgot, "구별O" if lgot != expect else "★구별X")
               ) if legacy_differs is True else ""
        print("  [%s] %-58s N=%s (기대 %s)%s"
              % ("PASS" if ok else "FAIL", name, got, expect, tag))
        if not ok:
            fails.append((name, expect, got))

    for name, files, expect_id, legacy_differs in WRITE_CASES:
        _, items = run(block, files)
        got = items[0]["paper_id"] if items else "(적재 0)"
        ok = (got == expect_id)
        _, litems = run(LEGACY, files)
        lgot = litems[0]["paper_id"] if litems else "(적재 0)"
        if legacy_differs is True and lgot == expect_id:
            teeth_fail.append(name)
        tag = ("   [legacy=%s %s]" % (lgot, "구별O" if lgot != expect_id else "★구별X")
               ) if legacy_differs is True else ""
        print("  [%s] %-58s id=%s (기대 %s)%s"
              % ("PASS" if ok else "FAIL", name, got, expect_id, tag))
        if not ok:
            fails.append((name, expect_id, got))

    total = len(CASES) + len(WRITE_CASES) + 1      # +1 = 배선 단언
    print("=" * 78)
    if teeth_fail:
        print("★검사 무력 경보 — legacy 가 아래를 구별하지 못했다(검사 사망 의심):")
        for t in teeth_fail:
            print("   - %s" % t)
    for n, e, g in fails:
        print("  - %s: 기대 %s / 실측 %s" % (n, e, g))
    n_fail = len(fails) + len(teeth_fail)
    n_pass = total - len(fails)
    n_teeth = sum(1 for c in CASES + WRITE_CASES if c[3] is True)
    print("PASS %d / FAIL %d  (legacy 구별 %d건 — 검사에 이빨 있음)"
          % (n_pass, n_fail, n_teeth))
    print(json.dumps({"test": "factor_recheck_pending", "pass": n_pass,
                      "fail": n_fail, "total": n_pass + n_fail}))
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
