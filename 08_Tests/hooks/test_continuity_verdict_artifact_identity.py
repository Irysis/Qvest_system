#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_continuity_verdict_artifact_identity.py — C1 '판정 산출물' 판별의 **정체 검사**
차단 실효 (위반 주입 양방향).

대상: 02_Infrastructure/axiom/continuity_gate.py::turn_verdict_artifacts / _closure_evidence

## 원 결함 (2026-08-16 실측)
`turn_verdict_artifacts` 는 `.cache/round_closures.jsonl` · `.cache/last_round_closure.json`
의 **mtime 만** 보고 "이번 턴에 판정 산출물이 있었나" 를 판정했다. 두 파일은 프로젝트 루트
단일 파일이고 main 의 `.cache` 는 `/c/qm_cache` 심볼릭 링크(머신 공유)라 **모든 워크트리
세션이 같은 파일을 읽고 쓴다** ⇒ 병렬 세션이 라운드를 닫으면 내 턴이 '판정 생산 턴' 으로
오인되고, 그 결과 과거 판정 어휘를 인용만 한 운영/브리핑 턴이 차단된다.

## ★이 축이 marker_fresh 수리에서 범위 밖이었던 이유와, 그 전제가 깨진 지점
방향이 반대다 — marker 누수는 **우회**(남의 계속으로 내 종결이 통과), 이 누수는
**과차단(FP)**(va=True 면 탐지가 유지돼 *더* 막힌다). 그래서 재현율을 줄이는 변경으로 보고
따로 측정하기로 미뤘다.

그 판단의 전제를 실측이 뒤집었다(전 transcript 163파일 · 1,282턴 재판정):
  A) 구판(두 누수 공존)          차단 276
  B) marker 만 수리(현재)        차단 302  ← +26
  C) 두 축 다 수리(이 파일의 대상) 차단 297  ← B 대비 −5, **C 가 B 를 넘어 막는 건 0**
같은 남의 종료가 va=True 로 탐지를 살리는 **동시에** 구 marker_fresh 를 True 로 만들어
계약을 충족시켜 통과시켰다 — **두 누수가 서로를 가렸다**. marker 축만 고치면 가림막이
걷혀 FP 가 무장된다. B−C = 5건이 전부 main 루트이고 전부 '남의 종료만' 인 턴이다.
(워크트리 `.cache` 엔 closure 파일이 0건이라 이 누수는 main 루트 세션에만 닿는다.)

## 검사 축
  A 포장도로 보존 — 자기 세션이 이번 턴에 닫음 → PASS (계약 충족 경로)
  B ★누수 — 남의 종료만 → verdict_close 억제 → PASS (억제 사유가 foreign_closure_only 인지까지)
  C 종료 기록 없음 → PASS (기존 C1 동작 회귀 가드)
  D 구판 기록(session_id 필드 부재) → 귀속 불가 → **증거로 셈** → BLOCK (fail-toward-recall)
  E 세션 불명 → 같은 이유로 BLOCK (marker 축은 fail-closed, 이 축은 fail-open — 방향이 반대)
  F ★재현율 불변 — 명시 종결어휘는 남의 종료뿐이어도 BLOCK (va 는 verdict_close 만 문지기)
  G 정체 필드 없는 산출물(l_code) 은 mtime 판정 유지 → 남의 종료와 무관하게 BLOCK
  H 원장(jsonl) 단독 귀속 — 꼬리 판독으로 own/foreign 을 가른다 (마커 파일 없이)
  I ★돌연변이 — mtime-only 로직 복원 시 B 가 BLOCK 으로 뒤집힘 (B 의 PASS 가 정체 검사에서
    온 것임을 매 실행 실증. 검사 사망 통제)
  J 루트 갈림 — 내 종료가 **공유 루트**에 쓰였어도 내 것이면 인정 (쓰는 쪽=main /
    읽는 쪽=워크트리 인 실제 배선에서 재현율이 죽지 않는지)
  K E2E — override 없이 **실제 훅 진입점**(`--transcript`) 경유. session_id 를 transcript
    파일명에서 얻는 실경로로 own/foreign 양방향.

## 격리 원칙 (2026-07-25 배터리 오염 사고 계승)
판정용 root 는 **매 케이스 새 임시 디렉토리**이고, `QM_ROOT`/`CLAUDE_PROJECT_DIR` 도 그
샌드박스로 고정한다. `_marker_roots` 가 공유 루트를 훑기 때문에 고정하지 않으면 이 배터리가
**운영 저장소의 실제 종료 기록을 읽는다** — 그 오염이 2026-07-25 에 차단 케이스 22건을
통째로 통과시켰다. ★그리고 이 파일이 존재하는 이유가 그 격리의 대가다:
`02_Infrastructure/tests/test_continuity_gate.py` 는 `verdict_artifact_override` 로 이 축을
절연해 **`turn_verdict_artifacts` 본문이 한 번도 실행되지 않는다**(31/31 초록이 이 결함을
못 본 이유). 옳은 격리가 무커버 표면을 만든다 — 그 표면은 별도 배터리로 덮는다.
"""
import atexit
import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

# ─────────────────────────────────────────────────────────────────────────────
# 루트 해석 — **자기 위치(`__file__`) 가 1순위**, 모든 tier 에 표지 검증.
# (계약: 02_Infrastructure/docs/rules/r-portability.md ④-b — 테스트 러너는 자기가 실린
#  트리를 검사한다. env-first 면 worktree 의 변경이 한 번도 검사되지 않는다.)
# ─────────────────────────────────────────────────────────────────────────────
_ANCHOR_MARKER = os.path.join("02_Infrastructure", "axiom", "continuity_gate.py")
_ANCHOR_ORDER = ("self", "CLAUDE_PROJECT_DIR", "QM_ROOT", "cwd")


def _anchor_norm(p):
    return os.path.abspath(p).replace("\\", "/") if p else ""


_SELF_ROOT = _anchor_norm(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def _resolve_root():
    cands = {
        "self": _SELF_ROOT,
        "CLAUDE_PROJECT_DIR": _anchor_norm(os.environ.get("CLAUDE_PROJECT_DIR", "")),
        "QM_ROOT": _anchor_norm(os.environ.get("QM_ROOT", "")),
        "cwd": _anchor_norm(os.getcwd()),
    }
    for src in _ANCHOR_ORDER:
        cand = cands.get(src, "")
        if cand and os.path.isfile(os.path.join(cand, _ANCHOR_MARKER)):
            if _SELF_ROOT and cand != _SELF_ROOT:
                sys.stderr.write("⚠ ANCHOR OVERRIDE: '%s' 가 아니라 %s='%s' 를 검사합니다.\n"
                                 % (_SELF_ROOT, src, cand))
            return src, cand
    sys.stderr.write("❌ ROOT 해석 실패 — 표지 '%s' 보유 후보 없음.\n" % _ANCHOR_MARKER)
    sys.exit(2)


_ROOT_SRC, ROOT = _resolve_root()
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "axiom"))
import continuity_gate as G  # noqa: E402

CASES = G.load_cases(ROOT)

PASS = 0
FAIL = 0
SKIP = 0
_FAILED = []


def chk(name, cond, note=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  PASS: %s%s" % (name, (" — " + note) if note else ""))
    else:
        FAIL += 1
        _FAILED.append(name)
        print("  **FAIL**: %s%s" % (name, (" — " + note) if note else ""))


def skip(name, why):
    global SKIP
    SKIP += 1
    print("  SKIP: %s — %s" % (name, why))


# ─────────────────────────────────────────────────────────────────────────────
# 픽스처
# ─────────────────────────────────────────────────────────────────────────────
_TMPS = []
atexit.register(lambda: [shutil.rmtree(d, ignore_errors=True) for d in _TMPS])

MY_SID = "aaaaaaaa-1111-4222-8333-aaaaaaaaaaaa"
OTHER_SID = "bbbbbbbb-4444-4555-8666-bbbbbbbbbbbb"

# ── verdict_close **단독** 텍스트 ────────────────────────────────────────────
# 조건: ①research_context 성립(리서치 용어 ≥2) ②마감 영역에 NEG 토큰 ③category
# backstop 어휘 없음(있으면 has_finality 로 va 와 무관하게 차단 = 축이 안 갈림)
# ④ops_context 마커 없음(있으면 in_progress 예외로 통과 — 통과 사유가 뒤바뀜)
# ⑤next_probe 0 · 부활조건 0(인라인 계약 미충족).
VERDICT_ONLY_TEXT = (
    "요청하신 아키텍처 상태를 정리해 보고드립니다. 자본 졸업 관문은 portfolio-alpha t "
    "2.95 · oos_retention 0.7 · calmar 0.64 이고, 지난 라운드의 factor 계열은 cap-w "
    "PORT_t 미달로 screen-tier 로 분류돼 있습니다. 텔레그램 발송했습니다."
)
# 명시 종결어휘 포함본 (F 축 — va 와 무관하게 막혀야 한다)
FINALITY_TEXT = (
    "cap-w PORT_t 미달입니다. 이 alpha 방향은 종착이라 판단합니다. "
    "factor 쪽은 더 볼 것이 없습니다."
)


def new_root():
    d = tempfile.mkdtemp(prefix="cont_va_")
    _TMPS.append(d)
    os.makedirs(os.path.join(d, ".cache"), exist_ok=True)
    return d


def iso_utc(epoch):
    return datetime.datetime.fromtimestamp(
        epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def iso_local(epoch):
    """close_round 이 쓰는 형식(`%Y-%m-%dT%H:%M:%S%z`) 재현."""
    return datetime.datetime.fromtimestamp(epoch).astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def write_closure(root, session_id, round_id, mtime, shared=True, per_session=True,
                  ledger=True, omit_sid_field=False):
    """종료 기록을 임의 정체·임의 mtime 으로 심는다(위반 주입의 손잡이).

    실제 close_round() 가 쓰는 3면을 그대로 재현한다 — 공유 마커 · 세션별 마커 · 원장 append.
    """
    rec = {"schema": "round_closure_v1", "round_id": round_id,
           "verdict_type": "config_scoped_negative", "closed_at": iso_local(mtime)}
    if not omit_sid_field:
        rec["session_id"] = session_id
    blob = json.dumps(rec, ensure_ascii=False)
    cache = os.path.join(root, ".cache")
    os.makedirs(cache, exist_ok=True)
    paths = []
    if shared:
        p = os.path.join(cache, "last_round_closure.json")
        open(p, "w", encoding="utf-8").write(blob)
        paths.append(p)
    if per_session and session_id and not omit_sid_field:
        sd = os.path.join(cache, G.SESSION_MARKER_DIR)
        os.makedirs(sd, exist_ok=True)
        p = os.path.join(sd, G._sanitize_sid(session_id) + ".json")
        open(p, "w", encoding="utf-8").write(blob)
        paths.append(p)
    if ledger:
        p = os.path.join(cache, "round_closures.jsonl")
        with open(p, "a", encoding="utf-8") as f:
            f.write(blob + "\n")
        paths.append(p)
    for p in paths:
        os.utime(p, (mtime, mtime))
    return paths


def write_lcode_artifact(root, mtime):
    """정체 필드가 없는 판정 산출물(l_code) — mtime 판정을 유지하는 표면."""
    d = os.path.join(root, "stage_artifacts", "l_code")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "l_code_fixture.json")
    open(p, "w", encoding="utf-8").write('{"lcode":"L-FIXTURE"}')
    os.utime(p, (mtime, mtime))
    return p


def judge(root, text, user_ts, session_id, extra_root=None):
    """판정 1회. **override 없이** — 실제 파일만 보게 한다.

    ★env 루트를 샌드박스로 고정: `_marker_roots` 가 QM_ROOT / CLAUDE_PROJECT_DIR 을
      마커 탐색 후보로 쓰므로, 고정하지 않으면 운영 저장소의 실제 종료 기록을 읽는다.
    extra_root: 공유 루트를 따로 두고 싶을 때(축 J — 쓰는 루트/읽는 루트 갈림 재현).
    """
    saved = {k: os.environ.get(k) for k in ("QM_ROOT", "CLAUDE_PROJECT_DIR")}
    os.environ["QM_ROOT"] = extra_root or root
    os.environ["CLAUDE_PROJECT_DIR"] = root
    try:
        return G.judge_text(text, "", CASES, root, user_ts=user_ts, session_id=session_id)
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def va_diag(res):
    return res["diag"].get("verdict_artifacts", {})


def suppressed(res):
    return res["diag"].get("closure", {}).get("verdict_close_suppressed")


NOW = time.time()
T_PROMPT = NOW - 600          # 내 프롬프트
T_AFTER = NOW - 300           # 프롬프트 이후(= 이번 턴 안)
T_BEFORE = NOW - 1200         # 프롬프트 이전(= 지난 턴)
USER_TS = iso_utc(T_PROMPT)


# ─────────────────────────────────────────────────────────────────────────────
def main():
    print("\n[anchor] root_src=%s root=%s" % (_ROOT_SRC, ROOT))
    print("         gate=%s" % G.__file__)

    # 픽스처 자체의 유효성 — 텍스트가 정말 verdict_close **단독** 인가.
    # (이게 깨지면 아래 축들이 '다른 이유로' 초록이 되어 검사가 조용히 죽는다.)
    print("\n[0] 픽스처 유효성 — 축이 실제로 va 하나로 갈리는가")
    cl = G.detect_closure(VERDICT_ONLY_TEXT, CASES)
    chk("0a_verdict_close_only", cl["verdict_close"] and not cl["has_finality"]
        and not cl["has_waiting"],
        "종결어휘·대기어휘 없이 NEG 토큰만: %s" % cl["verdict_tokens"][:3])
    chk("0b_no_ops_progress", not cl["ops_progress"],
        "진행 마커 없음 — 통과가 in_progress 예외 때문이 아님을 보장")
    chk("0c_research_context", G.research_context(VERDICT_ONLY_TEXT, CASES))
    chk("0d_finality_text_has_lexeme", G.detect_closure(FINALITY_TEXT, CASES)["has_finality"],
        "F 축 픽스처는 반대로 종결어휘를 실제로 갖는다")

    print("\n[A] 포장도로 보존 — 자기 세션이 이번 턴에 닫은 라운드")
    r = new_root()
    write_closure(r, MY_SID, "MY-ROUND-A", T_AFTER)
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("A1_own_closure_passes", res["block"] is False,
        "내가 계속을 생산했으므로 통과(계약 충족 경로)")
    chk("A2_own_evidence_attributed",
        any("round_closure_by_session" in e or e == "round_closures.jsonl"
            for e in va_diag(res).get("evidence", [])),
        "증거가 내 것으로 귀속됨: %s" % va_diag(res).get("evidence"))

    print("\n[B] ★누수 — 병렬 세션의 라운드 종료만 있는 운영/브리핑 턴")
    r = new_root()
    write_closure(r, OTHER_SID, "FOREIGN-ROUND-B", T_AFTER)
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("B1_foreign_closure_does_not_make_verdict_turn", res["block"] is False,
        "남의 종료로 내 턴이 '판정 생산 턴' 이 되지 않는다")
    chk("B2_va_false", va_diag(res).get("produced") is False)
    chk("B3_suppression_reason_is_foreign", suppressed(res) == "foreign_closure_only",
        "억제 사유가 진단 가능하게 남는다(사후 FP율 측정의 분자)")
    chk("B4_evidence_names_dropped_round",
        any("FOREIGN-ROUND-B" in str(e) for e in va_diag(res).get("evidence", [])),
        "무엇을 왜 뺐는지 지목: %s" % va_diag(res).get("evidence"))

    print("\n[C] 종료 기록 없음 — 기존 C1 동작 회귀 가드")
    r = new_root()
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("C1_no_closure_passes", res["block"] is False)
    chk("C2_reason_is_plain_absence", suppressed(res) == "no_new_verdict_artifact",
        "'없음' 과 '남의 것' 을 라벨로 구분한다")

    print("\n[D] 구판 기록(session_id 필드 부재) — 귀속 불가")
    r = new_root()
    write_closure(r, MY_SID, "LEGACY-ROUND-D", T_AFTER, omit_sid_field=True)
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("D1_unattributed_counts_as_evidence", res["block"] is True,
        "fail-toward-recall — 귀속 못 하면 증거로 센다(marker 축과 방향이 반대)")
    chk("D2_va_true", va_diag(res).get("produced") is True)

    print("\n[E] 세션 불명 — 정체를 모르면 무엇도 남의 것이라 단정 못 한다")
    r = new_root()
    write_closure(r, OTHER_SID, "FOREIGN-ROUND-E", T_AFTER)
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, "")
    chk("E1_unknown_session_keeps_recall", res["block"] is True,
        "세션 불명 = 구판 동작(mtime) 으로 낙하 — 재현율 쪽으로 넘어진다")

    print("\n[F] ★재현율 불변 — 명시 종결어휘는 va 와 무관")
    r = new_root()
    write_closure(r, OTHER_SID, "FOREIGN-ROUND-F", T_AFTER)
    res = judge(r, FINALITY_TEXT, USER_TS, MY_SID)
    chk("F1_finality_still_blocks", res["block"] is True,
        "va 는 verdict_close 만 문지기 — 종결어휘 경로는 손대지 않는다")

    print("\n[G] 정체 필드 없는 산출물(l_code) 은 mtime 판정 유지")
    r = new_root()
    write_closure(r, OTHER_SID, "FOREIGN-ROUND-G", T_AFTER)   # 남의 종료 + 내 l_code
    write_lcode_artifact(r, T_AFTER)
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("G1_lcode_artifact_still_counts", res["block"] is True,
        "정체를 확인할 수 없는 표면에 정체 검사를 흉내내지 않는다")
    chk("G2_evidence_is_lcode",
        any("l_code" in str(e) for e in va_diag(res).get("evidence", [])),
        "증거 = %s" % va_diag(res).get("evidence"))

    print("\n[H] 원장(jsonl) 단독 귀속 — 마커 파일 없이 꼬리 판독만으로")
    r = new_root()
    write_closure(r, OTHER_SID, "FOREIGN-LEDGER-H", T_AFTER, shared=False, per_session=False)
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("H1_foreign_ledger_only_passes", res["block"] is False,
        "원장 mtime 만으로 '판정 턴' 을 주장할 수 없다")
    r = new_root()
    write_closure(r, MY_SID, "MY-LEDGER-H", T_AFTER, shared=False, per_session=False)
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("H2_own_ledger_only_counts", va_diag(res).get("produced") is True,
        "내 append 는 꼬리 판독으로 인정된다: %s" % va_diag(res).get("evidence"))
    r = new_root()
    write_closure(r, OTHER_SID, "FOREIGN-OLD-H", T_BEFORE, shared=False, per_session=False)
    write_closure(r, MY_SID, "MY-NEW-H", T_AFTER, shared=False, per_session=False)
    res = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("H3_mixed_ledger_finds_own", va_diag(res).get("produced") is True,
        "남의 기록이 섞여 있어도 내 것 하나면 인정")

    print("\n[I] ★돌연변이 — mtime-only 로직 복원 시 B 가 뒤집히는가 (검사 사망 통제)")
    r = new_root()
    write_closure(r, OTHER_SID, "FOREIGN-ROUND-I", T_AFTER)
    orig = G._closure_evidence

    def _legacy_mtime_only(root_, ref_, session_id_):
        ev = []
        for rt in G._marker_roots(root_):
            for f in ("round_closures.jsonl", "last_round_closure.json"):
                p = os.path.join(rt, ".cache", f)
                try:
                    if os.path.isfile(p) and os.path.getmtime(p) >= ref_:
                        ev.append(f)
                except Exception:
                    pass
        return ev, []

    G._closure_evidence = _legacy_mtime_only
    try:
        res_mut = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    finally:
        G._closure_evidence = orig
    chk("I1_mutant_reintroduces_the_FP", res_mut["block"] is True,
        "구 로직을 되살리면 같은 운영 턴이 다시 차단됨 = B1 의 PASS 는 정체 검사가 만든 것")
    res_back = judge(r, VERDICT_ONLY_TEXT, USER_TS, MY_SID)
    chk("I2_restored", res_back["block"] is False, "복원 확인(돌연변이 누수 없음)")

    print("\n[J] 루트 갈림 — 내 종료가 공유 루트(main)에 쓰이고 게이트는 워크트리를 읽을 때")
    shared_root = new_root()          # = QM_ROOT (close_round 이 실제로 쓰는 곳)
    wt_root = new_root()              # = CLAUDE_PROJECT_DIR (게이트가 읽는 곳)
    write_closure(shared_root, MY_SID, "MY-ROUND-J", T_AFTER)
    res = judge(wt_root, VERDICT_ONLY_TEXT, USER_TS, MY_SID, extra_root=shared_root)
    chk("J1_own_closure_in_shared_root_counts", va_diag(res).get("produced") is True,
        "공유 보관소를 훑되 **정체로 거른다** — 훑기 자체는 누수가 아니다")
    shared_root2 = new_root()
    wt_root2 = new_root()
    write_closure(shared_root2, OTHER_SID, "FOREIGN-ROUND-J", T_AFTER)
    res = judge(wt_root2, VERDICT_ONLY_TEXT, USER_TS, MY_SID, extra_root=shared_root2)
    chk("J2_foreign_closure_in_shared_root_dropped", res["block"] is False,
        "같은 공유 보관소의 남의 종료는 여전히 제외")

    print("\n[K] E2E — override 없이 실제 훅 진입점(--transcript) 경유")
    run_e2e()

    print("\n" + "=" * 64)
    total = PASS + FAIL
    if FAIL:
        print("BATTERY: %d/%d pass, %d skipped — FAILURES: %s" % (PASS, total, SKIP, _FAILED))
        sys.exit(1)
    print("BATTERY: %d/%d pass, %d skipped — ALL GREEN" % (PASS, total, SKIP))
    sys.exit(0)


def _write_transcript(root, sid, text, user_ts):
    """훅이 읽는 형식의 transcript. 파일명 = session_id (게이트의 정체 권위 출처)."""
    d = os.path.join(root, "_transcripts")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, sid + ".jsonl")
    lines = [
        {"type": "user", "timestamp": user_ts,
         "message": {"content": "상태 정리해서 보고해줘"}},
        {"type": "assistant", "timestamp": user_ts,
         "message": {"content": [{"type": "text", "text": text}]}},
    ]
    with open(p, "w", encoding="utf-8") as f:
        for ln in lines:
            f.write(json.dumps(ln, ensure_ascii=False) + "\n")
    return p


def _e2e_root():
    """E2E 샌드박스 — 케이스 사전을 심는다.

    ★초판은 이걸 안 심었고, 그래서 `--transcript` 가 `load_cases` 에서 FileNotFoundError
      로 죽어 **fail-open `{}`** 을 뱉었다. '차단 안 됨' 이 그대로 초록이 되어
      K1(남의 종료 → 통과)이 **내 수리와 무관하게** 통과했다 — 게이트가 판정을 한 게
      아니라 아예 안 돈 것이다. 옆 축(K2, 차단을 기대하는 방향)이 없었으면 못 봤다.
      ⇒ 아래 K0 양성 대조가 그 재발을 매 실행 막는다: **통과 주장 전에 이 하네스가
      차단을 낼 수 있음을 먼저 보인다.**
    """
    r = new_root()
    src = os.path.join(ROOT, "06_Registry", "continuity_cases.json")
    dst_dir = os.path.join(r, "06_Registry")
    os.makedirs(dst_dir, exist_ok=True)
    shutil.copyfile(src, os.path.join(dst_dir, "continuity_cases.json"))
    return r


def run_e2e():
    """`continuity_gate.py --transcript` 를 서브프로세스로 — 실제 훅과 같은 경로.

    ★여기서만 `current_session_id()` 의 transcript-파일명 경로가 돈다. 인프로세스 축은
      session_id 를 인자로 넘기므로 그 배선을 검사하지 못한다.
    """
    gate = os.path.join(ROOT, "02_Infrastructure", "axiom", "continuity_gate.py")
    py = os.environ.get("QVEST_PY") or sys.executable
    if not os.path.isfile(gate):
        skip("K_e2e", "게이트 파일 부재")
        return
    if not os.path.isfile(os.path.join(ROOT, "06_Registry", "continuity_cases.json")):
        skip("K_e2e", "케이스 사전 부재 — 샌드박스를 구성할 수 없음")
        return

    def run(root, sid, text=VERDICT_ONLY_TEXT):
        tp = _write_transcript(root, sid, text, USER_TS)
        env = dict(os.environ)
        env["QM_ROOT"] = root
        env["CLAUDE_PROJECT_DIR"] = root
        env.pop("QVEST_CONTINUITY_LLM", None)      # 네트워크 비의존
        try:
            out = subprocess.run([py, gate, "--transcript", tp], capture_output=True,
                                 text=True, timeout=60, env=env, cwd=root)
        except Exception as e:
            return None, str(e)
        try:
            return json.loads(out.stdout.strip() or "{}"), out.stderr
        except Exception:
            return None, out.stdout + out.stderr

    # ── K0 양성 대조: 이 하네스가 애초에 차단을 낼 수 있는가 ──────────────────
    r = _e2e_root()
    got, err = run(r, MY_SID, FINALITY_TEXT)
    alive = got is not None and got.get("decision") == "block"
    chk("K0_e2e_harness_can_block", alive,
        "양성 대조 — 실패 시 아래 '통과' 축들은 무의미(게이트가 안 돈 것). stderr=%s"
        % (str(err)[:120] if not alive else "clean"))
    if not alive:
        skip("K1_e2e_foreign", "양성 대조 실패로 판정 불가")
        skip("K2_e2e_own", "양성 대조 실패로 판정 불가")
        return

    r = _e2e_root()
    write_closure(r, OTHER_SID, "FOREIGN-ROUND-K", T_AFTER)
    got, err = run(r, MY_SID)
    if got is None:
        chk("K1_e2e_foreign_passes", False, "게이트 실행 실패: %s" % str(err)[:160])
    else:
        chk("K1_e2e_foreign_passes", got.get("decision") != "block",
            "실훅 경로: 남의 종료만 → 통과")

    r = _e2e_root()
    write_closure(r, MY_SID, "MY-ROUND-K", T_AFTER, shared=False, per_session=False)
    got, err = run(r, MY_SID)
    if got is None:
        chk("K2_e2e_own_ledger_blocks", False, "게이트 실행 실패: %s" % str(err)[:160])
    else:
        # 내 원장 append 만 있고 마커는 없음 → va=True 로 탐지 유지, 계약 미충족 → 차단.
        chk("K2_e2e_own_ledger_blocks", got.get("decision") == "block",
            "실훅 경로: 내 판정 턴이면 계속-산출물 결측을 그대로 막는다")


if __name__ == "__main__":
    main()
