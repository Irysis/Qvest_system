#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_continuity_marker_identity.py — 연속성 마커의 **정체 검사** 차단 실효 (위반 주입 양방향).

대상: 02_Infrastructure/axiom/continuity_gate.py::marker_fresh
      02_Infrastructure/contracts/close_round.R (발행자 신고 필드)

## 원 결함 (2026-08-16 실측)
구 `marker_fresh` 는 `.cache/last_round_closure.json` 의 **mtime 만** 봤다. 그 파일은
프로젝트 루트 단일 파일이고(main 의 `.cache` 는 `/c/qm_cache` 심볼릭 링크 = 머신 공유),
settings.json 이 `DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}` 로 훅을 세우는데
Bash/훅 환경엔 CLAUDE_PROJECT_DIR 이 없어 **모든 워크트리 세션이 main 의 같은 마커**를
읽고 쓴다. ⇒ 병렬 세션이 내 프롬프트 이후 아무 라운드나 닫으면 mtime 이 내 턴 안으로
들어와 **남이 생산한 계속으로 내 턴이 통과**했다. docstring 은 "이번 턴에 쓴 마커" 라고
선언했고 `round_id` 를 읽기까지 했으나 **검증에 쓰지 않았다**.

실측 재현(실제 훅 경로 · user_ts 존재): 같은 종결 텍스트가
  user_ts=07:25Z → PASS (marker_round_id=INFRA-WT-PURGE-20260816-P2, 이 세션 것 아님)
  user_ts=07:35Z → BLOCK
갈린 것은 서술이 아니라 **남의 mtime**.

## 검사 축
  A 포장도로 보존 — 자기 세션 마커 → 종결 텍스트여도 PASS
  B ★누수 — 다른 세션 마커만 → BLOCK
  C 마커 없음 → BLOCK
  D 구판 마커(session_id 필드 부재) → BLOCK (귀속 불가 = 미인정, fail-closed)
  E 자기 마커지만 stale(내 프롬프트 이전) → BLOCK
  F ★역방향 회귀 — 병렬 세션이 공유 파일을 **덮어써도** 내 세션별 마커가 살아 PASS
    (정체 검사만 넣고 세션별 파일을 안 만들면 내가 정당히 닫은 턴이 차단된다)
  G 세션 불명 → BLOCK (fail-closed. 마커가 아무리 fresh 해도 '내 것' 이라 주장 불가)
  H 인라인 경로 무영향 — 마커 0 + next_probe≥2 + 부활조건 → PASS (수리가 전면 차단이 아님)
  I ★돌연변이 — 구 mtime-only 로직 복원 시 B 가 PASS 로 **뒤집힘** (B 의 BLOCK 이
    정체 검사에서 온 것임을 매 실행 실증. 검사 사망 통제)
  J E2E — 실제 훅(research_continuity_guard.sh) 경유 own/foreign 양방향
  K close_round.R 계약 — session_id 가 마커·원장에 도달 + 세션별 파일 발행
    (Rscript 부재 시 skipped 로 신고 — 조용한 통과 금지)

## 격리 원칙 (2026-07-25 배터리 오염 사고 계승)
판정용 root 는 **매 케이스 새 임시 디렉토리**다. 운영 마커를 읽으면 결과가 운영 상태에
의존하고, 바로 그 오염이 2026-07-25 에 차단 케이스 22건을 통째로 통과시켰다.
"""
import atexit
import hashlib
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

MY_SID = "11111111-aaaa-4bbb-8ccc-111111111111"
OTHER_SID = "22222222-dddd-4eee-8fff-222222222222"

# 종결 프레이밍 + 계속-산출물 결측 (인라인 계약 미충족: next_probe 0 · 부활조건 0)
CLOSURE_TEXT = ("FQ-233 라운드 판정입니다. cap-w PORT_t 가 2.95 미달이고 oos_retention 도 "
                "게이트 아래입니다. 이 방향 끝 — 종결합니다.")
# 인라인 계약 충족본 (마커 없이도 통과해야 하는 정당한 수렴)
INLINE_OK_TEXT = ("FQ-233 은 이 config 에서 cap-w PORT_t 미달(config-scoped negative). "
                  "기전 = return-derived substrate 의 post-2017 감쇠. "
                  "next_probe: ①일별 축에서 분포-표적 재측정 ②EW-대비 cap-tier 재분류. "
                  "부활 조건: 비-return 데이터원 등재 시. 소비: OVERLAY_CANDIDATE 보존.")


def new_root():
    d = tempfile.mkdtemp(prefix="cont_ident_")
    _TMPS.append(d)
    os.makedirs(os.path.join(d, ".cache"), exist_ok=True)
    return d


def write_marker(root, session_id, round_id, mtime, per_session=True, shared=True,
                 omit_sid_field=False):
    """마커를 임의 정체·임의 mtime 으로 심는다(위반 주입의 손잡이)."""
    rec = {"schema": "round_closure_v1", "round_id": round_id,
           "verdict_type": "capability_established", "closed_at": "fixture"}
    if not omit_sid_field:
        rec["session_id"] = session_id
    blob = json.dumps(rec, ensure_ascii=False)
    paths = []
    if shared:
        paths.append(os.path.join(root, ".cache", "last_round_closure.json"))
    if per_session and session_id and not omit_sid_field:
        sd = os.path.join(root, ".cache", G.SESSION_MARKER_DIR)
        os.makedirs(sd, exist_ok=True)
        paths.append(os.path.join(sd, G._sanitize_sid(session_id) + ".json"))
    for p in paths:
        with open(p, "w", encoding="utf-8") as f:
            f.write(blob)
        os.utime(p, (mtime, mtime))
    return paths


def iso_utc(epoch):
    import datetime
    return datetime.datetime.fromtimestamp(
        epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def judge(root, text, user_ts, session_id, extra_root=None):
    """판정 1회. **env 루트를 샌드박스로 고정**한 채 돈다.

    ★`marker_fresh` 는 QM_ROOT / CLAUDE_PROJECT_DIR 도 마커 탐색 후보로 쓴다(쓰는 쪽과
      읽는 쪽의 루트가 갈려 있어서 — 게이트 `_marker_roots` 주석 참조). 그대로 두면 이
      배터리가 **운영 저장소의 실제 마커를 읽게 되고**, 그것이 2026-07-25 에 차단 케이스
      22건을 통째로 통과시킨 오염이다. 원칙: 테스트 결과는 운영 상태에 의존하지 않는다.
    extra_root: 공유 루트를 따로 두고 싶을 때(축 L — 루트 갈림 재현).
    """
    saved = {k: os.environ.get(k) for k in ("QM_ROOT", "CLAUDE_PROJECT_DIR")}
    os.environ["QM_ROOT"] = extra_root or root
    os.environ["CLAUDE_PROJECT_DIR"] = root
    try:
        # verdict_artifact_override=True: C1 운영-턴 판별을 고정해, 이 배터리가 재는 축이
        # 오직 **마커 정체**가 되게 한다(판별 경로는 test_continuity_gate.py 소관).
        return G.judge_text(text, "", CASES, root, user_ts=user_ts,
                            verdict_artifact_override=True, session_id=session_id)
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


NOW = time.time()
T_PROMPT = NOW - 600          # 내 프롬프트
T_AFTER = NOW - 300           # 프롬프트 이후(= 이번 턴 안)
T_BEFORE = NOW - 1200         # 프롬프트 이전(= 지난 턴)
USER_TS = iso_utc(T_PROMPT)


def main():
    print("\n[anchor] root_src=%s root=%s" % (_ROOT_SRC, ROOT))
    print("         gate=%s" % G.__file__)

    print("\n[A] 포장도로 보존 — 자기 세션이 이번 턴에 닫은 라운드")
    r = new_root()
    write_marker(r, MY_SID, "MY-ROUND-A", T_AFTER)
    res = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
    chk("A1_own_marker_passes", res["block"] is False,
        "자기 마커 → 종결 텍스트여도 통과(계속을 *내가* 생산했으므로)")
    chk("A2_why_own", res["diag"].get("contract", {}).get("marker_why") == "own")

    print("\n[B] ★누수 — 다른 세션의 라운드 종료가 내 턴을 열 수 있는가")
    r = new_root()
    write_marker(r, OTHER_SID, "FOREIGN-ROUND-B", T_AFTER)
    res = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
    ct = res["diag"].get("contract", {})
    chk("B1_foreign_marker_blocks", res["block"] is True,
        "병렬 세션 마커로는 통과 못 한다")
    chk("B2_why_foreign", ct.get("marker_why") == "foreign_session",
        "차단 사유가 진단 가능하게 남는다")
    chk("B3_reason_names_foreign_round",
        res.get("reason") is not None and "FOREIGN-ROUND-B" in res["reason"],
        "차단 메시지가 어느 라운드가 남의 것인지 지목한다")

    print("\n[C] 마커 없음 + 종결 프레이밍")
    r = new_root()
    res = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
    chk("C1_no_marker_blocks", res["block"] is True)
    chk("C2_why_no_marker",
        res["diag"].get("contract", {}).get("marker_why") == "no_marker")

    print("\n[D] 구판 마커(session_id 필드 부재) — 귀속 불가")
    r = new_root()
    write_marker(r, MY_SID, "LEGACY-ROUND-D", T_AFTER, omit_sid_field=True)
    res = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
    chk("D1_unattributed_blocks", res["block"] is True,
        "발행자를 모르면 인정하지 않는다(존재 검사로 정체 검사를 대체하지 않음)")
    chk("D2_why_unattributed",
        res["diag"].get("contract", {}).get("marker_why") == "unattributed")

    print("\n[E] 자기 마커지만 지난 턴 것(stale)")
    r = new_root()
    write_marker(r, MY_SID, "MY-OLD-ROUND-E", T_BEFORE)
    res = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
    chk("E1_stale_own_blocks", res["block"] is True, "신선도 축은 그대로 살아 있다")
    chk("E2_why_stale", res["diag"].get("contract", {}).get("marker_why") == "stale")

    print("\n[F] ★역방향 회귀 — 병렬 세션이 공유 마커를 덮어쓴 뒤에도 내 종료는 유효한가")
    r = new_root()
    write_marker(r, MY_SID, "MY-ROUND-F", T_AFTER)             # 내가 먼저 닫고
    write_marker(r, OTHER_SID, "FOREIGN-OVERWRITE-F", T_AFTER + 1,
                 per_session=True, shared=True)                 # B 가 공유 파일을 덮어씀
    shared = json.load(open(os.path.join(r, ".cache", "last_round_closure.json"),
                            encoding="utf-8"))
    chk("F1_shared_really_overwritten", shared.get("round_id") == "FOREIGN-OVERWRITE-F",
        "픽스처가 실제로 덮어쓰기 상황을 만들었다(공허한 PASS 방지)")
    res = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
    chk("F2_own_survives_overwrite", res["block"] is False,
        "세션별 마커가 포장도로를 보존한다 — 정체 검사만 넣으면 여기서 오차단이 난다")
    chk("F3_round_id_is_mine",
        res["diag"].get("contract", {}).get("marker_round_id") == "MY-ROUND-F",
        "인정된 것이 남의 라운드가 아니라 내 라운드다")

    print("\n[G] 세션 불명 — fail-closed")
    r = new_root()
    write_marker(r, MY_SID, "MY-ROUND-G", T_AFTER)
    res = judge(r, CLOSURE_TEXT, USER_TS, "")
    chk("G1_unknown_session_blocks", res["block"] is True,
        "내 정체를 모르면 어떤 마커도 '내 것' 이라 주장할 수 없다")
    chk("G2_why_unknown",
        res["diag"].get("contract", {}).get("marker_why") == "unknown_session")

    print("\n[H] 인라인 경로 무영향 — 수리가 전면 차단이 아님")
    r = new_root()
    res = judge(r, INLINE_OK_TEXT, USER_TS, MY_SID)
    chk("H1_inline_contract_passes", res["block"] is False,
        "마커 0 이어도 next_probe≥2 + 부활조건이면 통과(정당한 수렴 보존)")
    r = new_root()
    write_marker(r, OTHER_SID, "FOREIGN-ROUND-H", T_AFTER)
    res = judge(r, INLINE_OK_TEXT, USER_TS, MY_SID)
    chk("H2_inline_ok_even_with_foreign_marker", res["block"] is False,
        "남의 마커가 있어도 인라인 계약이 충족되면 통과 — 정체 검사가 오차단을 만들지 않는다")

    print("\n[I] ★돌연변이 — 구 mtime-only 로직 복원 시 B 가 뒤집히는가 (검사 사망 통제)")
    r = new_root()
    write_marker(r, OTHER_SID, "FOREIGN-ROUND-I", T_AFTER)
    orig = G.marker_fresh

    def _legacy_marker_fresh(root, user_ts, session_id=None):
        """수리 전 구현 그대로 — mtime 만 보고 round_id 는 읽되 검증에 쓰지 않는다."""
        p = os.path.join(root, ".cache", "last_round_closure.json")
        if not os.path.exists(p):
            return False, None, "no_marker"
        mt = os.path.getmtime(p)
        ref = G._ts_to_epoch(user_ts)
        fresh = (mt >= (ref - 2)) if ref is not None else ((time.time() - mt) <= 1800)
        rid = None
        try:
            rid = json.load(open(p, encoding="utf-8")).get("round_id")
        except Exception:
            pass
        return fresh, rid, "legacy"

    try:
        G.marker_fresh = _legacy_marker_fresh
        mut = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
    finally:
        G.marker_fresh = orig
    chk("I1_mutation_reopens_leak", mut["block"] is False,
        "구 로직에선 남의 마커가 통과시킨다 — B1 의 BLOCK 이 정체 검사에서 온 것임을 실증")
    post = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
    chk("I2_restored_blocks_again", post["block"] is True, "복원 후 다시 차단(패치 누출 없음)")

    print("\n[L] ★루트 갈림 — 쓰는 쪽(main)과 읽는 쪽(워크트리)의 루트가 다를 때")
    # 실측 근거: 워크트리 `.cache` 에 게이트 산출물(continuity_blocks.jsonl·counters)은 있는데
    #   closure 파일은 0건이고, 종료 기록 468건 전부가 main 의 `.cache` 에 있다 ⇒ close_round 는
    #   Bash 툴(CLAUDE_PROJECT_DIR 부재)에서 QM_ROOT 에 쓰고 훅은 워크트리에서 읽는다.
    #   정체 검사가 있으므로 공유 루트를 훑어도 안전하다 — L2 가 그 안전성을 확인한다.
    r_read = new_root()      # 훅이 읽는 루트(워크트리 역) — 마커 없음
    r_write = new_root()     # close_round 가 쓰는 루트(main 역)
    write_marker(r_write, MY_SID, "MY-ROUND-L", T_AFTER)
    res = judge(r_read, CLOSURE_TEXT, USER_TS, MY_SID, extra_root=r_write)
    chk("L1_cross_root_own_found", res["block"] is False,
        "다른 루트에 쓴 **내** 마커를 찾는다 — 워크트리 세션의 포장도로 복구")
    r_read2 = new_root()
    r_write2 = new_root()
    write_marker(r_write2, OTHER_SID, "FOREIGN-ROUND-L", T_AFTER)
    res = judge(r_read2, CLOSURE_TEXT, USER_TS, MY_SID, extra_root=r_write2)
    chk("L2_cross_root_foreign_still_blocks", res["block"] is True,
        "공유 루트를 훑어도 **남의** 마커는 통과시키지 않는다 (루트 확장이 누수를 되열지 않음)")
    chk("L3_cross_root_why_foreign",
        res["diag"].get("contract", {}).get("marker_why") == "foreign_session")

    print("\n[J] E2E — 실제 훅(research_continuity_guard.sh) 경유 양방향")
    hook = os.path.join(ROOT, "02_Infrastructure", "hooks", "research_continuity_guard.sh")
    gate_src = os.path.join(ROOT, _ANCHOR_MARKER)
    if not os.path.isfile(hook):
        skip("J_e2e", "훅 스크립트 미발견: %s" % hook)
    elif not shutil.which("bash"):
        skip("J_e2e", "bash 미발견")
    else:
        def e2e(sid_of_marker, tag):
            r = new_root()
            os.makedirs(os.path.join(r, "02_Infrastructure", "axiom"), exist_ok=True)
            os.makedirs(os.path.join(r, "06_Registry"), exist_ok=True)
            shutil.copy2(gate_src, os.path.join(r, _ANCHOR_MARKER))
            shutil.copy2(os.path.join(ROOT, "06_Registry", "continuity_cases.json"),
                         os.path.join(r, "06_Registry", "continuity_cases.json"))
            # 복사본이 검사 대상과 동일한지 확인 — 낡은 사본을 재는 함정 방지
            h1 = hashlib.sha1(open(gate_src, "rb").read()).hexdigest()
            h2 = hashlib.sha1(open(os.path.join(r, _ANCHOR_MARKER), "rb").read()).hexdigest()
            assert h1 == h2, "E2E 사본이 대상과 불일치"
            write_marker(r, sid_of_marker, "E2E-%s" % tag, T_AFTER)
            # transcript 파일명 = session_id (훅 경로의 정체 권위)
            tp = os.path.join(r, MY_SID + ".jsonl")
            with open(tp, "w", encoding="utf-8") as f:
                f.write(json.dumps({"type": "user", "timestamp": USER_TS,
                                    "message": {"role": "user", "content": "상태 알려줘."}},
                                   ensure_ascii=False) + "\n")
                f.write(json.dumps({"type": "assistant",
                                    "message": {"role": "assistant",
                                                "content": [{"type": "text",
                                                             "text": CLOSURE_TEXT}]}},
                                   ensure_ascii=False) + "\n")
            env = dict(os.environ)
            env["CLAUDE_PROJECT_DIR"] = r
            env["QM_ROOT"] = r          # 격리: 하위 프로세스가 운영 마커를 훑지 않게
            env["QVEST_PY_BIN"] = sys.executable
            env["PYTHONUTF8"] = "1"
            payload = json.dumps({"hook_event_name": "Stop", "transcript_path": tp,
                                  "stop_hook_active": False})
            out = subprocess.run(["bash", hook], input=payload, capture_output=True,
                                 text=True, env=env, timeout=120).stdout
            return out

        out_own = e2e(MY_SID, "OWN")
        out_foreign = e2e(OTHER_SID, "FOREIGN")
        chk("J1_e2e_own_passes", '"decision"' not in out_own,
            "자기 마커 → 훅이 block 을 발행하지 않는다 (out=%r)" % out_own.strip()[:60])
        chk("J2_e2e_foreign_blocks", '"decision"' in out_foreign,
            "남의 마커 → 훅이 실제로 block 을 발행한다 (차단 실효)")
        chk("J3_e2e_block_is_valid_json",
            (lambda: (lambda d: isinstance(d, dict) and d.get("decision") == "block")(
                json.loads(out_foreign.strip().splitlines()[-1])))()
            if '"decision"' in out_foreign else False,
            "발행 JSON 이 훅 계약 형태다")

    print("\n[K] close_round.R — 발행자 신고가 마커·원장에 도달하는가")
    cr = os.path.join(ROOT, "02_Infrastructure", "contracts", "close_round.R")
    if not shutil.which("Rscript"):
        skip("K_close_round_contract", "Rscript 미발견 — R 계약 축 미측정")
    elif not os.path.isfile(cr):
        skip("K_close_round_contract", "close_round.R 미발견: %s" % cr)
    else:
        r = new_root()
        drive = os.path.join(r, "drive.R")
        with open(drive, "w", encoding="utf-8") as f:
            f.write(
                "source('%s')\n"
                "close_round(round_id='K-CONTRACT', verdict_type='capability_established',\n"
                "  mechanism_diagnosis='검사용 기전 진단 본문 — 20자 이상 요건 충족을 위한 더미.',\n"
                "  next_probes=c('p1','p2'), consumer_surfaces='c', frontier_update='f',\n"
                "  live_trigger='t')\n" % cr.replace("\\", "/"))
        env = dict(os.environ)
        env["CLAUDE_PROJECT_DIR"] = r
        env["QM_ROOT"] = r              # 격리: R 계약이 운영 `.cache` 에 쓰지 않게
        env["CLAUDE_CODE_SESSION_ID"] = MY_SID
        p = subprocess.run(["Rscript", "-e", "source('%s')" % drive.replace("\\", "/")],
                           capture_output=True, text=True, env=env, timeout=300)
        mk = os.path.join(r, ".cache", "last_round_closure.json")
        sess = os.path.join(r, ".cache", G.SESSION_MARKER_DIR, G._sanitize_sid(MY_SID) + ".json")
        led = os.path.join(r, ".cache", "round_closures.jsonl")
        if not os.path.isfile(mk):
            chk("K0_close_round_ran", False, "마커 미발행. stderr=%s" % p.stderr[-300:])
        else:
            d = json.load(open(mk, encoding="utf-8"))
            chk("K1_session_id_in_marker", d.get("session_id") == MY_SID,
                "발행자가 마커에 신고된다 (탐지 아닌 선언)")
            chk("K2_per_session_marker", os.path.isfile(sess),
                "세션별 마커가 함께 발행된다 (덮어쓰기 회귀 방어)")
            chk("K3_ledger_carries_sid",
                os.path.isfile(led) and
                json.loads([l for l in open(led, encoding="utf-8") if l.strip()][-1]
                           ).get("session_id") == MY_SID,
                "원장에도 정체가 남는다(사후 감사 가능)")
            # ★end-to-end: 실제 close_round 산출물을 게이트가 '내 것' 으로 인정하는가
            os.utime(mk, (T_AFTER, T_AFTER))
            os.utime(sess, (T_AFTER, T_AFTER))
            res = judge(r, CLOSURE_TEXT, USER_TS, MY_SID)
            chk("K4_real_marker_accepted", res["block"] is False,
                "R 계약이 만든 진짜 마커가 게이트를 통과한다 (픽스처가 아닌 실산출물)")
            res_other = judge(r, CLOSURE_TEXT, USER_TS, OTHER_SID)
            chk("K5_real_marker_foreign_to_others", res_other["block"] is True,
                "같은 마커가 **다른 세션에겐** 통하지 않는다")

    total = PASS + FAIL
    print("\nTOTAL: %d pass / %d fail / %d skipped" % (PASS, FAIL, SKIP))
    if _FAILED:
        print("FAILURES: %s" % _FAILED)
    print(json.dumps({"test": "continuity_marker_identity", "pass": PASS,
                      "fail": FAIL, "total": total, "skipped": SKIP}, ensure_ascii=False))
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
