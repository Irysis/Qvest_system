#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""research_pool_status.py 부팅 상태 라인 3축 — 위반 주입 테스트.

왜 이 파일이 있나 (2026-08-02):
  소비자 3종(alpha_search_queue_run.sh · factor_deep_recheck_run.sh ·
  paper_research_dispatch.R)의 같은-뿌리 결함("필드명·모양 불일치가 예외 없이 조용한
  빈 값이 된다")을 소비자 측에서 수리했는데, **부팅 리더는 같은 술어를 자기 안에 얕게
  재구현하고 있어서 수리가 닿지 않았다**. 결과: 소비자는 맞고 리더만 틀린 상태로,
  부팅 라인이 매일 틀린 숫자를 광고했다 — 실측 08-02:

    축1 AlphaQueue  "testable route 2 — VolRankStability, T_RetAutoCorr_12M"
                    → 두 건 다 그날 실행·QUARANTINE 완료. done 차감 시 0.
                      게다가 `_latest` 로 **최신 route 파일 하나만** 봐서 진짜 미소비분
                      (과거 파일에 있음)은 이 라인에 아예 안 잡혔다. 정본 술어 참값 1.
    축2 recheck잔여  3 → 참값 0. 큐의 'arxiv:' 접두 id 를 done 의 bare id 와 raw 비교.
                      소비자는 이미 정규화로 수리돼 N=0 을 내고 있었다.
    축3 mode_queue   3키를 최상위에서만 읽음 → mode_queue_20260727.json(queue{} 중첩)을
                      재생하면 opt0/risk0/regime0. 소비자가 이 미해석으로 14편을 드롭했다.

★검사 설계 — "숫자가 줄었다"는 증거가 아니다(검사기를 죽여도 준다). 축마다 양방향:
  (A) 이미 소비/처리된 건은 표기가 어느 쪽이든 **빠지는가**
  (B) 진짜 미소비분은 **여전히 잡히는가** (= 검사 사망 아님)
  더해 legacy(수리 전 리더 술어)를 음성 기준으로 동반 실행 — 전부 통과하면 검사가 무력하다.

★검사 대상 = 사본이 아니라 **원본 리더 모듈**을 그대로 import 해 collect()/render() 를 돌린다.
★배선 단언 = 리더가 술어 정본(research_pool_predicates.py)을 경유하는지 + 술어를 자기 안에
  다시 적지 않았는지(정규화 정규식 재출현 감시). 재구현이 바로 이 결함의 기전이었다.

실행: "$QVEST_PY" 08_Tests/ops/test_research_pool_status_axes.py
종료코드: 0 = 전건 PASS / 1 = 실패 있음.
"""
import importlib.util
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
READER = os.environ.get("QVEST_RPS_PY") or os.path.join(
    ROOT, "02_Infrastructure", "ops", "research_pool_status.py")
PRED = os.environ.get("QVEST_PREDICATES_PY") or os.path.join(
    ROOT, "02_Infrastructure", "ops", "research_pool_predicates.py")

PASS = []
FAIL = []


def ok(m):
    PASS.append(m)
    print("  [PASS] %s" % m)


def bad(m, d):
    FAIL.append((m, d))
    print("  [FAIL] %s — %s" % (m, d))


# ── 원본 리더 로드 ────────────────────────────────────────────────────────────
def load_reader():
    if not os.path.isfile(READER):
        sys.stderr.write("FATAL: 리더 부재: %s\n" % READER)
        sys.exit(2)
    spec = importlib.util.spec_from_file_location("rps_under_test", READER)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    for fn in ("collect", "render"):
        if not hasattr(m, fn):
            sys.stderr.write("FATAL: 리더에 %s() 가 없다 — 추출 대상 오류.\n" % fn)
            sys.exit(2)
    return m


# ── 픽스처 ────────────────────────────────────────────────────────────────────
def stage_root(files):
    """{filename: obj} 로 임시 PROJECT_ROOT/stage_artifacts/paper_recharge 를 만든다."""
    td = tempfile.mkdtemp()
    sd = os.path.join(td, "stage_artifacts", "paper_recharge")
    os.makedirs(sd)
    for name, obj in files.items():
        with open(os.path.join(sd, name), "w", encoding="utf-8") as fh:
            if isinstance(obj, str):
                fh.write(obj)
            else:
                json.dump(obj, fh, ensure_ascii=False)
    return td, sd


def route(date, *papers):
    return {"date": date, "papers": list(papers)}


def testable_paper(pid, name="F"):
    return {"id": pid, "title": "t-" + name,
            "factor_candidate": {"verdict": "testable", "name": name}}


def uncertain_paper(pid, name="U"):
    return {"id": pid, "title": "t-" + name, "source": "arxiv",
            "factor_candidate": {"verdict": "uncertain", "name": name}}


# ── legacy(수리 전 리더 술어) — 음성 기준 전용. 여기를 "고치지" 말 것 ───────────
def legacy_axis1(sd):
    """구판: 최신 route 파일만, done 차감 없음."""
    fs = sorted([f for f in os.listdir(sd) if f.startswith("alpha_search_route_")])
    if not fs:
        return 0
    r = json.load(open(os.path.join(sd, fs[-1]), encoding="utf-8"))
    cands = [(p.get("factor_candidate") or {}) for p in r.get("papers", [])]
    return len([c for c in cands if str(c.get("verdict", "")).lower() == "testable"])


def legacy_axis2(sd):
    """구판: 큐 paper_id 를 done 과 raw 문자열 비교."""
    fs = sorted([f for f in os.listdir(sd) if f.startswith("factor_recheck_queue_")])
    q = set()
    if fs:
        j = json.load(open(os.path.join(sd, fs[-1]), encoding="utf-8"))
        q = {it.get("paper_id") for it in (j.get("items") or []) if it.get("paper_id")}
    d = set()
    dp = os.path.join(sd, "factor_recheck_done.json")
    if os.path.exists(dp):
        for x in json.load(open(dp, encoding="utf-8")).get("processed", []):
            pid = x.get("paper_id") if isinstance(x, dict) else x
            if pid:
                d.add(pid)
    return len(q - d)


def legacy_axis3(sd):
    """구판: 3키를 최상위에서만 읽음."""
    fs = sorted([f for f in os.listdir(sd) if f.startswith("mode_queue_")])
    if not fs:
        return (0, 0, 0)
    m = json.load(open(os.path.join(sd, fs[-1]), encoding="utf-8"))
    return tuple(len(m.get(k)) if isinstance(m.get(k), list) else 0
                 for k in ("optimizer", "risk", "regime"))


# ── 배선 단언 ─────────────────────────────────────────────────────────────────
def check_wiring():
    if not os.path.isfile(PRED):
        bad("W0 술어 정본 부재", PRED)
        return
    src = open(READER, encoding="utf-8").read()
    if "research_pool_predicates" in src:
        ok("W1 리더가 술어 정본을 import 한다")
    else:
        bad("W1 정본 미경유", "리더가 술어를 자체 구현 중 — 승격이 무효화됐다")
    # ★재구현 감시: 정규화 정규식이 리더 안에 다시 나타나면 정의가 또 갈린 것이다.
    if re.search(r"arxiv\.org/\(\?:abs\|pdf\)|_AXPFX|_AXID", src):
        bad("W2 ★술어 재구현", "id 정규화 정규식이 리더에 다시 등장 — 정의가 2벌로 갈렸다")
    else:
        ok("W2 리더가 id 정규화를 재구현하지 않는다")
    for fn in ("alpha_pending", "mode_queue_routes", "recheck_residual"):
        if fn not in src:
            bad("W3 축 미배선", "리더가 %s 를 호출하지 않는다" % fn)
            return
    ok("W3 세 축이 전부 정본 함수를 호출한다 (alpha_pending/mode_queue_routes/recheck_residual)")


# ── 축 1: AlphaQueue 미소비 pending ──────────────────────────────────────────
def axis1(M):
    # A1 ★원결함: 최신 route 의 testable 이 전부 done → 미소비 0
    td, sd = stage_root({
        "alpha_search_route_20260802.json": route(
            "20260802", testable_paper("2607.00001", "VolRankStability"),
            testable_paper("2607.00002", "T_RetAutoCorr_12M")),
        "alpha_search_queue_done.json": {"processed": ["2607.00001", "2607.00002"]},
    })
    o = M.collect(td)
    lg = legacy_axis1(sd)
    if o["alpha_pending_n"] == 0:
        ok("A1 ★원결함 done 처리분 2건 → 미소비 0 (legacy=%d %s)"
           % (lg, "구별O" if lg != 0 else "★구별X"))
        if lg == 0:
            bad("A1 음성기준", "legacy 도 0 — 이 케이스가 결함을 구별하지 못한다")
    else:
        bad("A1 done 미차감", "미소비=%s (기대 0)" % o["alpha_pending_n"])

    # A2 ★원결함: 진짜 미소비분이 **과거 파일**에 있다 (_latest 한 파일만 보는 결함)
    td, sd = stage_root({
        "alpha_search_route_20260801.json": route(
            "20260801", testable_paper("2607.00009", "OldUnconsumed")),
        "alpha_search_route_20260802.json": route(
            "20260802", testable_paper("2607.00001", "A"), testable_paper("2607.00002", "B")),
        "alpha_search_queue_done.json": {"processed": ["2607.00001", "2607.00002"]},
    })
    o = M.collect(td)
    lg = legacy_axis1(sd)
    if o["alpha_pending_n"] == 1 and "OldUnconsumed" in " ".join(o["alpha_pending_names"]):
        ok("A2 ★원결함 과거 파일의 미소비분을 잡는다 → 1 (legacy=%d %s)"
           % (lg, "구별O" if lg != 1 else "★구별X"))
        if lg == 1:
            bad("A2 음성기준", "legacy 도 1 — 구별 실패")
    else:
        bad("A2 과거 파일 누락", "미소비=%s names=%s (기대 1/OldUnconsumed)"
            % (o["alpha_pending_n"], o["alpha_pending_names"]))

    # A3 방향 B: 신규 미소비분은 여전히 잡힌다 (검사 사망 아님)
    td, sd = stage_root({
        "alpha_search_route_20260802.json": route("20260802", testable_paper("2699.00001", "New")),
        "alpha_search_queue_done.json": {"processed": []},
    })
    o = M.collect(td)
    if o["alpha_pending_n"] == 1:
        ok("A3 신규 미소비 testable → 1 (정규화·차감이 다 삼키지 않는다)")
    else:
        bad("A3 검사 사망 의심", "미소비=%s (기대 1)" % o["alpha_pending_n"])

    # A4 표기 불일치: route 'arxiv:' 접두 vs done bare → 제외
    td, sd = stage_root({
        "alpha_search_route_20260802.json": route(
            "20260802", testable_paper("arxiv:2607.00003", "Pfx")),
        "alpha_search_queue_done.json": {"processed": ["2607.00003"]},
    })
    o = M.collect(td)
    lg = legacy_axis1(sd)
    if o["alpha_pending_n"] == 0:
        ok("A4 'arxiv:' 접두 ∈ done(bare) → 미소비 0 (legacy=%d 구별%s)"
           % (lg, "O" if lg != 0 else "X"))
    else:
        bad("A4 표기 미정규화", "미소비=%s (기대 0)" % o["alpha_pending_n"])

    # A5 라우터 명시 기각은 되살아나지 않는다
    td, sd = stage_root({
        "alpha_search_route_20260802.json": route("20260802", {
            "id": "2699.00002", "route": "alpha", "kr_feasible": True,
            "factor_candidate": {"verdict": "redundant"}}),
        "alpha_search_queue_done.json": {"processed": []},
    })
    o = M.collect(td)
    if o["alpha_pending_n"] == 0:
        ok("A5 verdict=redundant + alpha∧feasible → 미소비 0 (기각 존중)")
    else:
        bad("A5 기각 부활", "미소비=%s (기대 0)" % o["alpha_pending_n"])

    # A6 render: 헤드라인이 미소비 수를 말한다 + placeholder '?' 없음(boot_status_smoke 계약)
    td, sd = stage_root({
        "alpha_search_route_20260802.json": route(
            "20260802", testable_paper("2607.00001", "A"), testable_paper("2699.00003", "Fresh")),
        "alpha_search_queue_done.json": {"processed": ["2607.00001"]},
        "mode_queue_20260802.json": {"date": "20260802", "optimizer": [], "risk": [], "regime": []},
    })
    lines = M.render(M.collect(td))
    aq = [l for l in lines if "AlphaQueue" in l]
    if aq and "미소비 1" in aq[0]:
        ok("A6 render 헤드라인 = 미소비 수 (route-최신 testable 을 pending 인 척하지 않는다)")
    else:
        bad("A6 render", "AlphaQueue 라인=%s" % (aq[0] if aq else "(없음)"))
    ph = [l for l in lines if re.search(r"(?:^|[ =(/·])\?(?:$|[ )/·,])", l)]
    if ph:
        bad("A7 placeholder 잔존", "boot_status_smoke 계약 위반: %s" % ph[0][:90])
    else:
        ok("A7 placeholder '?' 없음 (boot_status_smoke 단언 정합)")


# ── 축 2: recheck 잔여 ────────────────────────────────────────────────────────
def axis2(M):
    # B1 ★원결함: 큐 'arxiv:' 접두 vs done bare → 잔여 0
    td, sd = stage_root({
        "factor_recheck_queue_20260802.json": {"date": "20260802", "items": [
            {"paper_id": "arxiv:2607.16450"}, {"paper_id": "arxiv:2607.14174"},
            {"paper_id": "arxiv:2607.13968"}]},
        "factor_recheck_done.json": {"processed": [
            {"paper_id": "2607.16450"}, {"paper_id": "2607.14174"},
            {"paper_id": "2607.13968"}]},
    })
    o = M.collect(td)
    lg = legacy_axis2(sd)
    if o["recheck_pending"] == 0:
        ok("B1 ★원결함 접두 큐 vs bare done 3건 → 잔여 0 (legacy=%d %s)"
           % (lg, "구별O" if lg != 0 else "★구별X"))
        if lg == 0:
            bad("B1 음성기준", "legacy 도 0 — 구별 실패")
    else:
        bad("B1 raw 비교 잔존", "잔여=%s (기대 0)" % o["recheck_pending"])

    # B2 방향 B: 진짜 미처리분은 여전히 잡힌다
    td, sd = stage_root({
        "factor_recheck_queue_20260802.json": {"date": "20260802", "items": [
            {"paper_id": "arxiv:2607.16450"}, {"paper_id": "2699.00007"}]},
        "factor_recheck_done.json": {"processed": [{"paper_id": "2607.16450"}]},
    })
    o = M.collect(td)
    if o["recheck_pending"] == 1:
        ok("B2 미처리 1건은 여전히 잔여로 잡힌다 (정규화가 다 삼키지 않는다)")
    else:
        bad("B2 검사 사망 의심", "잔여=%s (기대 1)" % o["recheck_pending"])

    # B3 드리프트 표면화: 큐파일은 0 인데 route 재파생은 1 (큐파일 stale)
    td, sd = stage_root({
        "factor_recheck_queue_20260802.json": {"date": "20260802", "items": []},
        "alpha_search_route_20260802.json": route("20260802", uncertain_paper("2699.00008")),
        "factor_recheck_done.json": {"processed": []},
    })
    o = M.collect(td)
    if o.get("recheck_drift"):
        ok("B3 큐파일 stale 을 드리프트로 표면화 (%s)" % o["recheck_drift"])
    else:
        bad("B3 드리프트 은폐", "큐파일 0 / route 재파생 1 인데 표식 없음")


# ── 축 3: mode_queue 형태 관용 ────────────────────────────────────────────────
def axis3(M):
    # C1 ★원결함: queue{} 중첩 판
    td, sd = stage_root({
        "mode_queue_20260727.json": {
            "schema_version": "mode_queue_v1", "date": "20260727",
            "generated_by": "paper_router_v2",
            "queue": {"optimizer": [1, 2, 3, 4, 5, 6, 7], "risk": [1, 2, 3, 4],
                      "regime": [1, 2, 3]}},
        "alpha_search_route_20260727.json": route("20260727"),
    })
    o = M.collect(td)
    got = (o["mode_queue"]["optimizer"], o["mode_queue"]["risk"], o["mode_queue"]["regime"])
    lg = legacy_axis3(sd)
    if got == (7, 4, 3):
        ok("C1 ★원결함 queue{} 중첩 판 구제 7/4/3 (legacy=%s %s)"
           % ("/".join(map(str, lg)), "구별O" if lg != (7, 4, 3) else "★구별X"))
        if lg == (7, 4, 3):
            bad("C1 음성기준", "legacy 도 7/4/3 — 구별 실패")
    else:
        bad("C1 중첩 미해석", "%s (기대 7/4/3)" % "/".join(map(str, got)))

    # C2 방향 B: 정본 평면 판을 관용이 깨지 않는다
    td, sd = stage_root({
        "mode_queue_20260802.json": {"date": "20260802", "optimizer": [1, 2, 3],
                                     "risk": [1, 2, 3, 4], "regime": [1, 2]},
        "alpha_search_route_20260802.json": route("20260802"),
    })
    o = M.collect(td)
    got = (o["mode_queue"]["optimizer"], o["mode_queue"]["risk"], o["mode_queue"]["regime"])
    if got == (3, 4, 2):
        ok("C2 정본 평면 판 3/4/2 (관용 추가가 정본을 깨지 않았다)")
    else:
        bad("C2 정본 회귀", "%s (기대 3/4/2)" % "/".join(map(str, got)))

    # C3 미해석 키 표면화 — "0편"과 "못 읽음"을 구분하는 유일 축
    td, sd = stage_root({
        "mode_queue_20260802.json": {"date": "20260802", "payload": {"optimizer": [1, 2]}},
        "alpha_search_route_20260802.json": route("20260802"),
    })
    o = M.collect(td)
    if o.get("mode_queue_unresolved"):
        ok("C3 3라우트 0 + 미해석 키(%s) 표면화 (드롭 ≠ 0편)"
           % ", ".join(o["mode_queue_unresolved"]))
    else:
        bad("C3 드롭 은폐", "미해석 키가 있는데 표식 없음 — 0편과 못읽음이 같은 출력")

    # C4 진짜 빈 큐는 조용히 0 (관용이 유령 경보를 만들지 않는다)
    td, sd = stage_root({
        "mode_queue_20260802.json": {"date": "20260802", "note": "n",
                                     "optimizer": [], "risk": [], "regime": []},
        "alpha_search_route_20260802.json": route("20260802"),
    })
    o = M.collect(td)
    if not o.get("mode_queue_unresolved"):
        ok("C4 진짜 빈 큐 → 미해석 경보 없음 (오탐 아님)")
    else:
        bad("C4 오탐", "빈 큐에 미해석 키 경보: %s" % o["mode_queue_unresolved"])


def main():
    M = load_reader()
    print("리더: %s" % os.path.relpath(READER, ROOT))
    print("술어 정본: %s" % os.path.relpath(PRED, ROOT))
    print("=" * 78)
    check_wiring()
    axis1(M)
    axis2(M)
    axis3(M)
    print("=" * 78)
    for m, d in FAIL:
        print("  - %s: %s" % (m, d))
    n_pass, n_fail = len(PASS), len(FAIL)
    print("PASS %d / FAIL %d" % (n_pass, n_fail))
    print(json.dumps({"test": "research_pool_status_axes", "pass": n_pass,
                      "fail": n_fail, "total": n_pass + n_fail}))
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
