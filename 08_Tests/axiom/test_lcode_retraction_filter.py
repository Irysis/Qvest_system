#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""test_lcode_retraction_filter.py — 판정서 ⑦ 마디 ⓐ '철회 차단' + 1-1 '강화 증류 끔' (2026-09-23).

무엇을 지키나
-------------
  ⓐ `retracted_by`/`pit_invalid` 표식 L-code 는 교훈 생성·재료·인용 어디에도 나타나지 않는다.
     판정 = 02_Infrastructure/axiom/lcode_validity.py::lcode_invalidation (단일 정본)
     차단 지점 = lcode_harvester.py::harvest() (수확 단계) → corpus 하류 전부.
  1-1 research_mode ∈ _CAND_EXCLUDED_MODES(reinforcement_cell·reinforcement) 는 CAND 도 DIST 도 만들지 않는다
     (build_candidates · build_distilled 공통) — 강화 기억은 rf_lessons(P3) 일원화(도훈 AX-D2).

축 (양성 대조 + 위반 주입 + 돌연변이 — '초록'이 계측 사망과 구별되게)
  P  판정 함수 단위: 표식 7형(참/거짓/모호) — 보수 규칙(모호하면 무효)
  H  샌드박스 수확: 표식 L-code 는 lcodes 에 없고 invalidated_lcodes 에 사유와 함께 있다 · 최근교훈 3줄에 없다
     (양성 대조: 같은 픽스처의 무표식 L-code 는 들어온다 · 표식 L-code 가 가장 최신이라 필터가 없으면 최근교훈 1위)
     돌연변이 M-H: 판정 함수를 무력화(항상 None) → 표식 L-code 가 lcodes·최근교훈에 **나타나야** 한다(red 기대 → 검출)
  C  샌드박스 클러스터: 표식 L-code 는 어떤 CAND/DIST 의 supporting 에도 없다 · 강화 모드 CAND/DIST 0
     (양성 대조: ramp 무표식 L-code 의 CAND 는 생긴다 · 디스크에 남은 기존 CAND_reinforcement_* 가 DIST 로 안 올라간다)
     돌연변이 M-C: 제외 집합을 구판({reinforcement_cell})으로 되돌림 → CAND_reinforcement_*·DIST 가 **생겨야** 한다
  S  운영 상태(읽기 전용): 철회 5건 원천에 표식 · corpus.lcodes 부재 · corpus.invalidated_lcodes 존재 ·
     hypothesis_index/knowledge_index 부재 · 음성 대조(08-20 보정 L-code V5)는 무표식·corpus 존재

격리: 쓰기는 tempfile 샌드박스에만. 운영 트리는 읽기만 한다(S).
실행: "$QVEST_PY" 08_Tests/axiom/test_lcode_retraction_filter.py
"""
from __future__ import annotations

import copy
import importlib
import io
import json
import os
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if not os.path.isfile(os.path.join(ROOT, "02_Infrastructure", "axiom", "lcode_validity.py")):
    ROOT = os.environ.get("QM_ROOT") or os.environ.get("CLAUDE_PROJECT_DIR") or ROOT
AX = os.path.join(ROOT, "02_Infrastructure", "axiom")
sys.path.insert(0, AX)

PASS = FAIL = 0


def ok(n, m=""):
    global PASS
    PASS += 1
    print(f"  PASS: {n}" + (f" — {m}" if m else ""))


def bad(n, m=""):
    global FAIL
    FAIL += 1
    print(f"  FAIL: {n}" + (f" — {m}" if m else ""))


def chk(n, cond, m=""):
    (ok if cond else bad)(n, m)


import lcode_validity as LV  # noqa: E402
import lcode_harvester as LH  # noqa: E402
import cluster_extractor as CE  # noqa: E402

RETRACTED = ["L-RAMP-20260619_144257", "L-RAMP-20260619_150531", "L-RAMP-20260619_151835",
             "L-RAMP-20260619_152736", "L-RAMP-20260619_173504"]
NEG_CONTROL = "L-RAMP-20260820_221500"   # 08-20 보정 회계 재측정(V5) — 철회 대상 아님

# ── P. 판정 함수 단위 ─────────────────────────────────────────────────────────
print("\n[P] lcode_invalidation — 표식 형태별 판정 (보수: 모호하면 무효)")
cases = [
    ({"pit_invalid": True, "retracted_by": "L-X"}, True, "정상 표식"),
    ({"retracted_by": "L-X"}, True, "retracted_by 단독"),
    ({"pit_invalid": True}, True, "pit_invalid 단독(형식 위반이나 소비는 막는다)"),
    ({"pit_invalid": "true"}, True, "문자열 'true'(모호 → 무효)"),
    ({"pit_invalid": [True]}, True, "R 길이-1 배열 [true]"),
    ({"pit_invalid": False, "retracted_by": ""}, False, "거짓·빈 참조 = 표식 아님"),
    ({"l_code": "L-1", "grade": "F"}, False, "무표식"),
]
for rec, want, lab in cases:
    got = LV.lcode_invalidation(rec) is not None
    chk(f"P {lab}", got == want, f"got={got} want={want}")

# ── 샌드박스 픽스처 ───────────────────────────────────────────────────────────
SB = tempfile.mkdtemp(prefix="lcretr_")


def wl(mode, fname, rec, mtime=None):
    d = os.path.join(SB, "stage_artifacts", "l_code", mode)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, fname)
    with io.open(p, "w", encoding="utf-8") as fh:
        json.dump(rec, fh, ensure_ascii=False, indent=2)
    if mtime is not None:
        os.utime(p, (mtime, mtime))
    return p


base = {"record_type": "performance", "metric_type": "backtested", "construction_type": "momentum",
        "mechanism_hypothesis": "테스트 기전 — 국면 신호가 월간 지연에 소멸", "next_probes": ["a", "b"],
        "tags": ["RAMP", "regime"], "family": "overlay_regime"}
t0 = time.time() - 86400
fx_ok1 = dict(base, l_code="L-RAMP-TEST_OK1", strategy_id="RAMP_TEST_OK1", grade="C", research_mode="ramp",
              lesson_text="정상 교훈 1 — 국면 오버레이 월간 적용 측정")
fx_ok2 = dict(base, l_code="L-RAMP-TEST_OK2", strategy_id="RAMP_TEST_OK2", grade="F", research_mode="ramp",
              lesson_text="정상 교훈 2 — 국면 오버레이 월간 적용 측정 반복")
fx_bad = dict(base, l_code="L-RAMP-TEST_RETRACTED", strategy_id="RAMP_TEST_RETRACTED", grade="A",
              research_mode="ramp", lesson_text="철회된 헤드라인 — 동월 적용 결함 위 수치",
              pit_invalid=True, retracted_by="L-TEST-CORRECTION", retracted_at="2026-08-20")
fx_rb = dict(base, l_code="L-RAMP-TEST_RBONLY", strategy_id="RAMP_TEST_RBONLY", grade="B", research_mode="ramp",
             lesson_text="retracted_by 단독 표식", retracted_by="L-TEST-CORRECTION-2")
fx_rf = dict(base, l_code="L-RF-TEST_BLOCK1", strategy_id="RF_TEST_B1", grade="C", research_mode="reinforcement",
             lesson_text="강화 블록 교훈 — 증류 제외 대상")
wl("ramp", "l_code_ok1.json", fx_ok1, t0)
wl("ramp", "l_code_ok2.json", fx_ok2, t0 + 10)
p_bad = wl("ramp", "l_code_bad.json", fx_bad, t0 + 1000)      # 가장 최신 — 필터가 없으면 최근교훈 1위
wl("ramp", "l_code_rbonly.json", fx_rb, t0 + 900)
wl("reinforcement", "l_code_rf1.json", fx_rf, t0 + 20)
MARKED = {"L-RAMP-TEST_RETRACTED", "L-RAMP-TEST_RBONLY"}

# ── H. 수확 ─────────────────────────────────────────────────────────────────
print("\n[H] 샌드박스 수확 — 표식 L-code 는 corpus.lcodes 에서 빠지고 invalidated_lcodes 에 남는다")
corp = LH.harvest(SB)
ids = {x["l_code"] for x in corp["lcodes"]}
inv = {x["l_code"]: x for x in corp.get("invalidated_lcodes", [])}
chk("H1 표식 L-code 부재(lcodes)", not (ids & MARKED), f"누출={sorted(ids & MARKED)}")
chk("H2 invalidated_lcodes 에 사유와 함께 기록", MARKED <= set(inv) and all(inv[k]["reason"] for k in MARKED),
    f"inv={sorted(inv)}")
chk("H3 양성 대조: 무표식 L-code 는 수확됨", {"L-RAMP-TEST_OK1", "L-RAMP-TEST_OK2", "L-RF-TEST_BLOCK1"} <= ids,
    f"ids={sorted(ids)}")
chk("H4 n_invalidated 산술", corp.get("n_invalidated") == len(MARKED), str(corp.get("n_invalidated")))
rec = LH._pc_recent_lessons(corp)
chk("H5 최근교훈(주입 재료)에 표식 L-code 없음", not any(m in " ".join(rec) for m in MARKED), " | ".join(rec)[:160])

print("\n[M-H] 돌연변이 — 판정 함수 무력화 시 누출이 **보여야** 한다(검사 생존 지문)")
_orig = LH.lcode_invalidation
try:
    LH.lcode_invalidation = lambda r: None
    corp_m = LH.harvest(SB)
    ids_m = {x["l_code"] for x in corp_m["lcodes"]}
    rec_m = LH._pc_recent_lessons(corp_m)
    chk("M-H1 필터 제거 → 표식 L-code 가 lcodes 에 나타남(검출)", MARKED <= ids_m)
    chk("M-H2 필터 제거 → 최근교훈 1위가 철회 L-code(검출)", bool(rec_m) and "L-RAMP-TEST_RETRACTED" in rec_m[0],
        rec_m[0][:80] if rec_m else "")
finally:
    LH.lcode_invalidation = _orig

# ── C. 클러스터·증류 ─────────────────────────────────────────────────────────
print("\n[C] 샌드박스 클러스터·증류 — 표식 L-code 는 후보·증류 어디에도 없고, 강화 모드는 CAND/DIST 0")


def run_cluster(corpus, tag):
    cd = os.path.join(SB, tag, "candidates")
    dd = os.path.join(SB, tag, "distilled")
    os.makedirs(cd, exist_ok=True)
    # 디스크에 남은 **기존** 강화 CAND (단계 1-3 이관 전 존치분) — build_distilled 가 DIST 로 올리면 안 된다
    pre = {"candidate_id": "CAND_reinforcement_000000000000", "research_mode": "reinforcement",
           "supporting_l_codes": ["L-RF-OLD1", "L-RF-OLD2"], "polarity": "mixed", "type": "empirical",
           "statement_draft": "[초안] 기존 강화 후보", "cluster_key": "000000000000", "status": "pending_5axis"}
    with io.open(os.path.join(cd, "CAND_reinforcement_000000000000.json"), "w", encoding="utf-8") as fh:
        json.dump(pre, fh, ensure_ascii=False)
    CE.build_candidates(copy.deepcopy(corpus), cd)
    CE.build_distilled(cd, dd, os.path.join(SB, tag, "distilled_index.json"))
    cands = [json.load(io.open(os.path.join(cd, f), encoding="utf-8"))
             for f in os.listdir(cd) if f.startswith("CAND_") and f.endswith(".json")]
    dists = [json.load(io.open(os.path.join(dd, f), encoding="utf-8"))
             for f in os.listdir(dd) if f.startswith("DIST-") and f.endswith(".json")] if os.path.isdir(dd) else []
    return cands, dists


cands, dists = run_cluster(corp, "run")
sup_all = {lc for c in cands for lc in (c.get("supporting_l_codes") or [])} | \
          {lc for d in dists for lc in (d.get("supporting_l_codes") or [])}
chk("C1 표식 L-code 는 CAND/DIST supporting 어디에도 없음", not (sup_all & MARKED), str(sorted(sup_all & MARKED)))
new_rf = [c for c in cands if c.get("research_mode") == "reinforcement" and c["candidate_id"] != "CAND_reinforcement_000000000000"]
chk("C2 강화 모드 신규 CAND 0 (build_candidates 제외)", not new_rf, str([c["candidate_id"] for c in new_rf]))
rf_dist = [d for d in dists if d.get("research_mode") == "reinforcement"]
chk("C3 기존 강화 CAND 가 DIST 로 안 올라감 (build_distilled 같은 제외)", not rf_dist, str([d.get("dist_id") for d in rf_dist]))
chk("C4 양성 대조: ramp 무표식 L-code 의 CAND 는 생긴다",
    any("L-RAMP-TEST_OK1" in (c.get("supporting_l_codes") or []) for c in cands))
chk("C5 양성 대조: ramp CAND 의 DIST 는 생긴다", any(d.get("research_mode") == "ramp" for d in dists))

print("\n[M-C] 돌연변이 — 제외 집합을 구판({reinforcement_cell})으로 되돌리면 강화 CAND/DIST 가 **생겨야** 한다")
_orig_ex = CE._CAND_EXCLUDED_MODES
try:
    CE._CAND_EXCLUDED_MODES = frozenset({"reinforcement_cell"})
    cands_m, dists_m = run_cluster(corp, "mut")
    chk("M-C1 구판 → CAND_reinforcement_* 신규 생성(검출)",
        any(c.get("research_mode") == "reinforcement" and c["candidate_id"] != "CAND_reinforcement_000000000000"
            for c in cands_m))
    chk("M-C2 구판 → 강화 DIST 생성(검출)", any(d.get("research_mode") == "reinforcement" for d in dists_m))
finally:
    CE._CAND_EXCLUDED_MODES = _orig_ex

# ── S. 운영 상태 (읽기 전용) ───────────────────────────────────────────────────
print("\n[S] 운영 상태 — 철회 5건 원천 표식 · corpus/hypothesis_index/knowledge_index 부재 · 음성 대조")
lcdir = os.path.join(ROOT, "stage_artifacts", "l_code", "ramp")
src = {}
for f in os.listdir(lcdir):
    if f.startswith("l_code_") and f.endswith(".json"):
        try:
            r = json.load(io.open(os.path.join(lcdir, f), encoding="utf-8-sig"))
        except Exception:
            continue
        if r.get("l_code") in RETRACTED + [NEG_CONTROL]:
            src[r["l_code"]] = r
chk("S1 철회 5건 원천 파일 전부 발견", set(RETRACTED) <= set(src), str(sorted(set(RETRACTED) - set(src))))
chk("S2 철회 5건 원천에 표식(판정 함수 기준)", all(LV.lcode_invalidation(src.get(k, {})) for k in RETRACTED))
chk("S3 표식은 추가만 — 원 필드(lesson_text·grade) 보존", all(src[k].get("lesson_text") and src[k].get("grade")
                                                         for k in RETRACTED if k in src))
chk("S4 음성 대조: V5(보정 재측정)는 무표식", NEG_CONTROL in src and LV.lcode_invalidation(src[NEG_CONTROL]) is None)
cp = os.path.join(ROOT, ".cache", "lcode_corpus.json")
pc = json.load(io.open(cp, encoding="utf-8"))
cids = {x["l_code"] for x in pc["lcodes"]}
civ = {x["l_code"] for x in pc.get("invalidated_lcodes", [])}
chk("S5 운영 corpus.lcodes 에 철회 5건 부재", not (cids & set(RETRACTED)), str(sorted(cids & set(RETRACTED))))
chk("S6 운영 corpus.invalidated_lcodes 에 철회 5건 기록", set(RETRACTED) <= civ, str(sorted(set(RETRACTED) - civ)))
chk("S7 음성 대조: V5 는 corpus.lcodes 에 존재", NEG_CONTROL in cids)
for rel, lab in (("06_Registry/hypothesis_index.json", "S8 hypothesis_index"),
                 ("06_Registry/knowledge_index.json", "S9 knowledge_index")):
    txt = io.open(os.path.join(ROOT, rel), encoding="utf-8").read()
    hit = [k for k in RETRACTED if k in txt]
    chk(f"{lab} 에 철회 5건 부재(재빌드 반영)", not hit, str(hit))

shutil.rmtree(SB, ignore_errors=True)
print(f"\nTOTAL: {PASS} pass / {FAIL} fail")
print(json.dumps({"test": "lcode_retraction_filter", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
sys.exit(1 if FAIL else 0)
