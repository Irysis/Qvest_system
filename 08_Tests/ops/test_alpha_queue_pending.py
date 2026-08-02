#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""alpha_search_queue_run.sh 의 pending 산정 블록 — 위반 주입 테스트.

왜 이 파일이 있나 (2026-08-02):
  무인 스케줄러(morning_run.sh [0.56/3])가 소비하는 pending 카운터에 키 불일치 결함 2건이
  실측됐다. 둘 다 **오류 없이 조용히 틀린 숫자**를 냈다 —
    결함1  route_20260727 의 id 는 "arxiv:2607.19497" 인데 done 원장은 bare "2607.19497" →
           `pid not in done` 이 항상 참 → 이미 소비·QUARANTINE 판정난 2건이 영구 pending.
    결함2  queue_20260726/27 의 candidates 키는 `paper_id` 인데 카운터는 `id`/`arxiv_id` 만
           읽음 → pid='' → 해당 후보 **전부 침묵 미계수**(결함1과 반대 방향).

★검사 설계 원칙 — "N 이 줄었다"는 증거가 아니다.
  검사기를 죽여도(전건 done 처리해도) N 은 줄어든다. 그래서 이 파일은 **양방향**으로 잰다:
    (A) done 에 있는 건은 표기가 어느 쪽이든 빠지는가
    (B) done 에 없는 신규 testable 은 **여전히 잡히는가** (= 검사 사망 아님)
  더해 legacy(수리 전) 블록을 음성 기준으로 함께 돌려, 이 검사가 실제로 결함을
  구별하는지("teeth")를 매 실행 확인한다. legacy 가 전부 PASS 하면 검사가 무력한 것이다.

★검사 대상 = 사본이 아니라 **원본 .sh 의 heredoc 을 추출**해 돌린다.
  (사본 검사는 드리프트한다 — 원본만 고치고 사본이 계속 초록을 내는 부류.)

실행:
  "$QVEST_PY" 08_Tests/ops/test_alpha_queue_pending.py
종료코드: 0 = 전건 PASS / 1 = 실패 있음.
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
TARGET = os.environ.get("QVEST_QUEUE_RUN_SH") or os.path.join(
    ROOT, "02_Infrastructure", "ops", "alpha_search_queue_run.sh")

# 수리 전 구현(2026-08-02 이전). 음성 기준 전용 — 여기를 "고치지" 말 것.
LEGACY = r'''
import json, sys, glob, os
sd=sys.argv[1]
done=set()
dp=os.path.join(sd,"alpha_search_queue_done.json")
if os.path.exists(dp):
    try: done=set(json.load(open(dp,encoding="utf-8")).get("processed",[]))
    except: done=set()
pend=set()
for f in glob.glob(os.path.join(sd,"alpha_search_queue_*.json")):
    if f.endswith("_done.json"): continue
    try: d=json.load(open(f,encoding="utf-8"))
    except: continue
    for c in d.get("candidates",[]):
        pid=str(c.get("id") or c.get("arxiv_id") or "")
        fc=c.get("factor_candidate") or {}
        if pid and pid not in done and (fc.get("verdict")=="testable" or (c.get("route")=="alpha" and c.get("kr_feasible"))):
            pend.add(pid)
for f in glob.glob(os.path.join(sd,"alpha_search_route_*.json")):
    try: r=json.load(open(f,encoding="utf-8"))
    except: continue
    for p in r.get("papers",[]):
        pid=str(p.get("id") or p.get("arxiv_id") or "")
        fc=p.get("factor_candidate") or {}
        if pid and pid not in done and (fc.get("verdict")=="testable" or (p.get("route")=="alpha" and p.get("kr_feasible"))):
            pend.add(pid)
print(len(pend))
'''


def extract_block():
    """원본 .sh 에서 pending 산정 heredoc 을 추출한다."""
    with open(TARGET, encoding="utf-8") as fh:
        src = fh.read()
    m = re.search(r"^N=\$\(\"\$PYBIN\" - \"\$SD\" <<'PY'\n(.*?)^PY$",
                  src, re.S | re.M)
    if not m:
        sys.stderr.write(
            "FATAL: %s 에서 pending heredoc 을 찾지 못했다 — 마커가 바뀌었으면\n"
            "       이 추출기부터 고칠 것(조용히 0건 검사하는 것을 막기 위해 중단).\n" % TARGET)
        sys.exit(2)
    body = m.group(1)
    if "print(len(pend))" not in body:
        sys.stderr.write("FATAL: 추출 블록에 최종 출력이 없다 — 추출 범위 오류.\n")
        sys.exit(2)
    return body


def run(block, files, expect_stderr=None):
    """픽스처 디렉터리를 만들고 블록을 돌려 N 을 돌려준다."""
    with tempfile.TemporaryDirectory() as td:
        for name, obj in files.items():
            with open(os.path.join(td, name), "w", encoding="utf-8") as fh:
                if isinstance(obj, str):
                    fh.write(obj)          # 손상 JSON 주입용 raw
                else:
                    json.dump(obj, fh, ensure_ascii=False)
        p = subprocess.run([sys.executable, "-", td], input=block,
                           capture_output=True, text=True)
        if p.returncode != 0:
            return ("ERR:" + p.stderr.strip()[-200:], p.stderr)
        out = p.stdout.strip()
        return (out, p.stderr)


# ── 픽스처 헬퍼 ────────────────────────────────────────────────────────────────
def route(*papers):
    return {"date": "20260802", "papers": list(papers)}


def queue(*cands):
    return {"date": "20260802", "candidates": list(cands)}


def done(processed, records=None):
    d = {"processed": list(processed)}
    if records:
        d["records"] = records
    return d


TESTABLE = {"factor_candidate": {"verdict": "testable", "name": "x"}}


def paper(pid_key, pid, **kw):
    o = {pid_key: pid, "title": "t"}
    o.update(TESTABLE)
    o.update(kw)
    return o


# ── 케이스 ────────────────────────────────────────────────────────────────────
# (name, files, expect_fixed, expect_legacy_differs)
#   expect_legacy_differs=True  → legacy 는 이 케이스에서 **틀려야** 한다(= 검사에 이빨 있음)
CASES = [
    # ── 방향 A: done 에 있으면 표기 무관하게 빠져야 한다 ──────────────────────
    ("A1 bare id ∈ done → 제외",
     {"alpha_search_route_x.json": route(paper("id", "2607.19497")),
      "alpha_search_queue_done.json": done(["2607.19497"])}, "0", False),

    ("A2 ★결함1 'arxiv:' 접두 id ∈ done(bare) → 제외",
     {"alpha_search_route_x.json": route(paper("id", "arxiv:2607.19497")),
      "alpha_search_queue_done.json": done(["2607.19497"])}, "0", True),

    ("A3 역방향: bare id ∈ done('arxiv:' 접두) → 제외",
     {"alpha_search_route_x.json": route(paper("id", "2607.19497")),
      "alpha_search_queue_done.json": done(["arxiv:2607.19497"])}, "0", True),

    ("A4 버전 접미(v2) + 접두 ∈ done → 제외",
     {"alpha_search_route_x.json": route(paper("id", "arxiv:2607.19497v2")),
      "alpha_search_queue_done.json": done(["2607.19497"])}, "0", True),

    ("A5 URL 형 id ∈ done → 제외",
     {"alpha_search_route_x.json": route(paper("id", "https://arxiv.org/abs/2607.19497")),
      "alpha_search_queue_done.json": done(["2607.19497"])}, "0", True),

    ("A6 done.records[] 에만 있는 소비분 → 제외(processed append 누락 대비)",
     {"alpha_search_route_x.json": route(paper("id", "arxiv:2607.19005")),
      "alpha_search_queue_done.json": done([], [{"paper_id": "2607.19005",
                                                 "gate_decision": "QUARANTINE"}])}, "0", True),

    # ── 방향 B: done 에 없으면 **여전히 잡혀야** 한다 (검사 사망 아님) ─────────
    ("B1 신규 bare testable ∉ done → 계수",
     {"alpha_search_route_x.json": route(paper("id", "2699.00001")),
      "alpha_search_queue_done.json": done(["2607.19497"])}, "1", False),

    ("B2 ★신규 'arxiv:' 접두 testable ∉ done → 계수(정규화가 다 삼키지 않는다)",
     {"alpha_search_route_x.json": route(paper("id", "arxiv:2699.00002")),
      "alpha_search_queue_done.json": done(["2607.19497"])}, "1", False),

    ("B3 arxiv_id 키(route_0618/0802 스키마) ∉ done → 계수",
     {"alpha_search_route_x.json": route(paper("arxiv_id", "2699.00003")),
      "alpha_search_queue_done.json": done([])}, "1", False),

    ("B4 ★결함2 queue candidates 의 paper_id 키 + fc.verdict → 계수",
     {"alpha_search_queue_20260726.json": queue(paper("paper_id", "2699.00004")),
      "alpha_search_queue_done.json": done([])}, "1", True),

    ("B5 ★결함2b candidate 최상위 verdict(queue_0726 실측 스키마) → 계수",
     {"alpha_search_queue_20260726.json": queue(
         {"paper_id": "2699.00005", "verdict": "testable", "factor_name": "f"}),
      "alpha_search_queue_done.json": done([])}, "1", True),

    ("B6 route=alpha ∧ kr_feasible 경로(verdict 없음) → 계수",
     {"alpha_search_route_x.json": route(
         {"id": "2699.00006", "route": "alpha", "kr_feasible": True}),
      "alpha_search_queue_done.json": done([])}, "1", False),

    ("B7 curated 파일명 id(arXiv 형 아님) ∉ done → 원형 보존·계수",
     {"alpha_search_route_x.json": route(paper("id", "MAN_AHL_trend.pdf")),
      "alpha_search_queue_done.json": done([])}, "1", False),

    ("B8 curated 파일명 id ∈ done → 제외(정규화가 파일명을 망가뜨리지 않는다)",
     {"alpha_search_route_x.json": route(paper("id", "MAN_AHL_trend.pdf")),
      "alpha_search_queue_done.json": done(["MAN_AHL_trend.pdf"])}, "0", False),

    # ── 경계·오계수 ───────────────────────────────────────────────────────────
    ("C1 동일 논문이 접두/bare 두 파일에 → 1건으로 dedup(중복계수 금지)",
     {"alpha_search_route_a.json": route(paper("id", "arxiv:2699.00007")),
      "alpha_search_route_b.json": route(paper("arxiv_id", "2699.00007")),
      "alpha_search_queue_done.json": done([])}, "1", True),

    ("C2 종결 표식(status=QUARANTINE) 보유 후보는 되살리지 않는다",
     {"alpha_search_queue_20260726.json": queue(
         {"paper_id": "2699.00008", "verdict": "testable", "status": "QUARANTINE"}),
      "alpha_search_queue_done.json": done([])}, "0", False),

    ("C3 verdict 가 testable 아님 → 미계수",
     {"alpha_search_route_x.json": route(
         {"id": "2699.00009", "factor_candidate": {"verdict": "not_testable"}}),
      "alpha_search_queue_done.json": done([])}, "0", False),

    ("C4 손상 JSON 1건이 나머지 계수를 죽이지 않는다(fail-soft 유지)",
     {"alpha_search_route_bad.json": "{ this is not json",
      "alpha_search_route_ok.json": route(paper("id", "2699.00010")),
      "alpha_search_queue_done.json": done([])}, "1", False),

    ("C5 done 원장 부재 → 전건 pending(0 으로 삼키지 않는다)",
     {"alpha_search_route_x.json": route(paper("id", "2699.00011"))}, "1", False),

    ("C6 픽스처 전무 → 0 (정상 skip 경로)",
     {}, "0", False),

    ("C7 id 키 충돌 레코드 → 1건 계수 + stderr 경고",
     {"alpha_search_route_x.json": route(
         {"id": "2699.00012", "paper_id": "2699.00099",
          "factor_candidate": {"verdict": "testable"}}),
      "alpha_search_queue_done.json": done([])}, "1", None),
]


def main():
    block = extract_block()
    fails, teeth_fail = [], []
    print("대상: %s" % os.path.relpath(TARGET, ROOT))
    print("=" * 78)
    for name, files, expect, legacy_differs in CASES:
        got, err = run(block, files)
        ok = (got == expect)
        # 음성 기준: legacy 가 이 케이스를 틀리는지 확인 (= 검사에 이빨이 있는지)
        lgot, _ = run(LEGACY, files)
        if legacy_differs is True and lgot == expect:
            teeth_fail.append(name)
        mark = "PASS" if ok else "FAIL"
        tag = ""
        if legacy_differs is True:
            tag = "   [legacy=%s %s]" % (lgot, "구별O" if lgot != expect else "★구별X")
        print("  [%s] %-62s N=%s (기대 %s)%s" % (mark, name, got, expect, tag))
        if not ok:
            fails.append((name, expect, got, err.strip()[-300:]))
        if name.startswith("C7"):
            if "id 키 충돌" not in err:
                fails.append((name + " (stderr 경고)", "충돌 경고", err.strip()[-200:], ""))

    print("=" * 78)
    if teeth_fail:
        print("★검사 무력 경보 — legacy 가 아래를 구별하지 못했다(검사 사망 의심):")
        for t in teeth_fail:
            print("   - %s" % t)
    for n, e, g, err in fails:
        print("  - %s: 기대 %s / 실측 %s %s" % (n, e, g, err))
    n_fail = len(fails) + len(teeth_fail)
    n_pass = len(CASES) - len(fails)
    print("PASS %d / FAIL %d  (legacy 구별 %d건 — 검사에 이빨 있음)"
          % (n_pass, n_fail, sum(1 for c in CASES if c[3] is True)))
    # run_all_hooks.sh 집계용 요약 라인 — 이 줄이 없으면 러너가 UNREPORTED(=1 fail)로 계상한다.
    print(json.dumps({"test": "alpha_queue_pending", "pass": n_pass,
                      "fail": n_fail, "total": n_pass + n_fail}))
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
