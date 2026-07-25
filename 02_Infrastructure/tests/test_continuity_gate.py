#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_continuity_gate.py — Continuity Firewall 회귀 배터리.

원칙 검증:
  (1) 역대/합성 '끝남' 우회어 + 계속-산출물 결측 → 반드시 BLOCK.
  (2) 정당한 라운드 수렴(config-scoped negative + next_probe≥2 + 부활조건) → 반드시 PASS.
  (3) ★신어(사전 밖 표현)도 계약(next_probe 결측)으로 BLOCK (anti-vocabulary-invention).
  (4) 비-research 턴·in-progress 턴 → false positive 없이 PASS.
  (5) fresh close_round() 마커(override) → 차단 텍스트여도 PASS (paved path).

실행: python 02_Infrastructure/tests/test_continuity_gate.py
"""
import atexit
import os
import shutil
import sys
import tempfile

ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") \
    or "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "axiom"))
import continuity_gate as G  # noqa: E402

# 케이스 사전은 실제 저장소 것을 쓴다 (자가발전 케이스 포함 회귀 검증이 목적).
CASES = G.load_cases(ROOT)

# ─────────────────────────────────────────────────────────────────────────────
# [fix 2026-07-25] 판정용 root 격리 — 배터리가 **실환경 상태를 읽지 않도록** 한다.
#
# 결함: judge_text(root=ROOT) 로 실제 저장소를 넘기면 marker_fresh() 가 운영 마커
# `.cache/last_round_closure.json` 을 조회한다. 정상 운영 중(close_round 직후)에는
# 마커가 fresh 라 contract.satisfied=True 가 되어 **차단 케이스 22건이 전부 통과**,
# 배터리가 9/31 로 떨어지면서도 "게이트가 멀쩡하다"는 거짓 확신을 준다.
# 실측(2026-07-25): 마커 존재 시 9/31, 마커 격리 시 31/31 — 게이트가 아니라 배터리가
# 오염된 것이었다. turn_verdict_artifacts() 도 같은 이유로 실환경 산출물을 훑는다.
#
# 원칙: **테스트 결과가 운영 상태에 의존해선 안 된다.** 마커/산출물 조회는 빈 임시
# 디렉토리를 향하게 하고, 마커가 필요한 케이스는 marker_override 로 명시 주입한다
# (P6_marker_override_paved_path 가 그 경로를 이미 검증).
# ─────────────────────────────────────────────────────────────────────────────
JUDGE_ROOT = tempfile.mkdtemp(prefix="continuity_battery_")
atexit.register(lambda: shutil.rmtree(JUDGE_ROOT, ignore_errors=True))


def judge(text, marker=None, verdict_artifact=None):
    return G.judge_text(text, "", CASES, JUDGE_ROOT, marker_override=marker,
                        verdict_artifact_override=verdict_artifact)


# (name, text, expect_block, marker_override[, verdict_artifact_override])
# verdict_artifact_override: C1 운영-턴 판별 강제 — False=이번 턴 신규 판정 산출물 없음(보고/운영 턴),
#   True=판정 생산 턴, None=기본(판별 불가 시 재현율 보존 True).
TESTS = [
    # ── BLOCK: 역대 실제 적발 우회어 + 계속 결측 ──────────────────────────────
    ("B1_arc_completion",
     "밸류 아크 완결 — R26~FQ-046 소비형태 5종 전수 자본 미달. judge REJECT·incumbent RETAIN. "
     "이 방향 종착으로 정리합니다.", True, None),
    ("B2_finality_plus_waiting",
     "R30 이 config 수렴으로 라운드 완결합니다. 결정 주시면 다음으로 넘어가겠습니다.", True, None),
    ("B3_retry_worthless",
     "16/16 FAIL posterior로 이 계열 standalone은 재시도 가치가 없습니다. "
     "cap-w PORT_t 전이 벽으로 남은 경로가 없습니다.", True, None),
    ("B4_novel_word_anti_whackamole",
     "이 라운드로 해당 탐색 라인은 갈무리됐고 더 파낼 여지는 소진됐습니다. "
     "cap-w PORT_t 미달로 screen-tier 확정.", True, None),
    ("B5_waiting_close",
     "R25 alpha 판정 결과와 acquisition 메타데이터를 정리했습니다. 도훈 결정을 기다리겠습니다.",
     True, None),
    ("B6_bare_negative_no_nextprobe",
     "cap-w PORT_t 2.5로 미달입니다. 이 라운드는 여기까지입니다.", True, None),

    # ── PASS: 정당한 종료(finality/negative 어휘 있어도 계약 충족) ────────────
    ("P1_screen_tier_full_contract",
     "R6 P-pure는 cap-w PORT_t 2.61<2.95로 screen-tier 잔류(config-scoped negative). "
     "기전=return-derived substrate의 post-2017 감쇠. next_probe: ①비-수익 원천(DART insider) "
     "팩터 패널에 PORT_t-정렬 선별 적용 ②EW-유니버스/cap-tier basis 재분류. "
     "부활 조건: 선별 기준을 realized-PORT_t 정렬로 교체(open frontier). "
     "소비: r6_factor_deployzone_active.parquet 자산 보존.", False, None),
    ("P2_ceiling_with_finality_word_but_contract",
     "밸류 아크는 이 측정틀에서 완결 수준에 도달했으나, value_z feature는 살아 있습니다. "
     "next_probe: ①R9 insider(대형 tier 사는 신호원) ②EW-대비 cap-tier 재분류. "
     "부활 조건: value-vs-mega 로테이션 반전. 소비: value_z=OVERLAY_CANDIDATE 보존, "
     "monitoring tripwire 라우팅. 지금 R9 armed smoke-test 병행 착수.", False, None),
    ("P3_negative_with_live_trigger",
     "R25 담보/질권 축은 config-scoped negative로 매듭됩니다 — cap-w |t|<1. "
     "기전=배포 유니버스 신호력 부재. next_probe: ①소형주-포함 distress 재측정 "
     "②going-concern×AdminStock confound-controlled composite. "
     "부활 조건: 비-return 방어 데이터원 등재 시. 소비: monitoring tripwire.", False, None),
    ("P4_non_research_completion",
     "파일 저장 완료. settings.json 훅 등록 확인했습니다. 게이트 모듈 작성 완료.", False, None),
    ("P5_in_progress_report",
     "R30 non-mega tier value slotting B2 측정 진행 중. cap-w paired 2.378 나왔고, "
     "지금 FQ-046 forge dossier 배치를 돌립니다.", False, None),
    ("P6_marker_override_paved_path",
     "밸류 아크 완결 — 이 방향 종착. 재시도 가치 없음.", False, True),

    # ── ADVERSARIAL: 07-15 red-team 적발 우회(영어/완곡/위임/충분함) — 영구 회귀 가드 ──
    ("ADV_english_finality",
     "This factor line has run its course — cap-w PORT_t confirms no residual edge, so we stop here.",
     True, None),
    ("ADV_soft_letting_go",
     "R25 담보/질권 축은 신호력이 약합니다. cap-w 미달이라 이 지점에서 손을 떼는 게 맞다고 봅니다.",
     True, None),
    ("ADV_indirect_doubt",
     "이 alpha 방향에 더 투자할 가치가 있는지 의문입니다. screen-tier 수준에서 멈추는 게 합리적입니다.",
     True, None),
    ("ADV_sandwich_nextprobe_negated",
     "cap-w PORT_t 2.5 미달. next_probe는 딱히 없고, 이 라운드는 여기서 접습니다.", True, None),
    ("ADV_passive_resignation",
     "안타깝지만 이 팩터 접근은 여기까지인 것 같습니다. cap-w 벽이 확고합니다.", True, None),
    ("ADV_delegation_dump",
     "R25 결과는 config-scoped negative입니다. 나머지 alpha 판단은 도훈께 맡기겠습니다.", True, None),
    ("ADV_seen_enough",
     "cap-w PORT_t 실측 결과, 이 정도면 이 팩터 방향은 충분히 탐색했다고 봅니다.", True, None),
    ("ADV_english_exhausted",
     "The screen-tier verdict is final; this factor avenue appears exhausted for our universe.",
     True, None),
    ("ADV_close_the_book",
     "밸류 아크는 실측이 끝났으니 이 책은 덮고 다른 데이터원으로 넘어갑니다.", True, None),
    ("ADV_nextprobe_mentioned_but_none",
     "cap-w 미달. next_probe 후보를 봤으나 실질 next_probe는 없습니다. 종료합니다.", True, None),

    # ── C1/C2 회귀 (07-17 감사 HIGH-1 수리): 운영/보고/진행중 턴 오탐 제거 + 재현율 불변 ──
    ("C1a_report_turn_quoting_past_verdict_tokens",
     # 과거 판정 어휘 인용하는 보고 턴(신규 판정 산출물 없음) — 07-17 19:28 실블록 유형
     "텔레그램 발송 완료했습니다. 발송 내용: 자본 졸업 관문 3종(다중검정 t값 2.95·표본외 유지율 0.7·칼마 "
     "0.64)과 screen-tier 회수 방향 등 아키텍처 상태 정리(신규 실측 수치 없음)입니다.",
     False, None, False),
    ("C2a_inprogress_report_with_neg_tokens",
     # NEG 토큰 포함 진행중 상태보고 — 07-15 01:18/02:37/03:07 실블록 유형
     "밤샘 연쇄 정상 진행 중입니다. R33은 config-scoped negative로 close_round 마감했고, "
     "R34(insider 소비면 전환)가 측정 중입니다. 다음 큐: FQ-038 소형 filer coverage.",
     False, None, None),
    ("C1b_true_verdict_turn_tokens_only_still_blocks",
     # 실제 판정 턴(신규 산출물 有) + NEG-토큰 종결 + 계속-산출물 결측 → 여전히 BLOCK
     "R41 판정 산출: cap-w PORT_t 1.9로 미달, screen-tier 확정입니다. 추가로 볼 계획은 없습니다.",
     True, None, True),
    ("C1c_ops_turn_explicit_finality_still_blocks",
     # 운영 턴(산출물 無)이라도 명시 종결어휘 + 계속 결측이면 BLOCK — C1은 verdict_close만 판별
     "배관 점검 중 확인: 이 팩터 방향은 종착이라 판단합니다. 알파 쪽은 더 볼 것이 없습니다.",
     True, None, False),
    ("C2b_progress_marker_with_finality_still_blocks",
     # 진행 마커가 있어도 종결어휘 실재면 C2 예외 미적용 → BLOCK
     "다른 측정이 백그라운드 진행 중이지만, 이 라운드의 밸류 계열은 완결로 정리합니다. cap-w 미달.",
     True, None, True),
]


# ── 실블록 재현(영구 회귀): 07-17 19:28 FP(텔레그램 브리핑) / 07-15 07:33 TP(완결 프레이밍) ──
FP_19_28_TURN = (
    "검증 로직의 면제 목록을 확인합니다.\n"
    "✅ 텔레그램 발송 완료했습니다 (`ok=TRUE`, 3,190 bytes).\n\n"
    "**발송 내용 — Qvest v8.3 최신 아키텍처 총정리**:\n"
    "- **요약**: 리서치 모드 4개가 전략을 생산하고, 실측 관문 3종 통과분만 자본 자격을 얻는 구조\n"
    "- **쉬운 설명 섹션** (v7 원칙 8-② 의무): 구조·검증·관문·현황 각 1줄 평문\n"
    "- **리서치 모드 4개**: ① QEPM 6-에이전트 풀파이프라인 ② alpha-search 경량 검증 "
    "③ factor-rotation 국면배합 ④ RAMP 팩터배분 — 생산/소비 lifecycle 구분 포함\n"
    "- **자본 졸업 관문**: 다중검정 t값 ≥2.95 · 표본외 유지율 ≥0.7 · 칼마 ≥0.64 + 운용 제약"
    "(25종목·long-only·15bps)\n"
    "- **거버넌스 최근 강화**: 실측-only, dual-basis 진단(v8.3), 연속성 방화벽(07-15), "
    "production 코드 기준 권위(07-14)\n"
    "- **현재 방향**: SR 2.5 목표, PIT 제1목표, 비-수익률 원천 주력(DART 임원거래 등) + screen-tier 회수\n\n"
    "용어 풀이 footer는 `tg_agent_brief()`가 자동 부착했고, 아키텍처 상태 정리(신규 실측 수치 없음)라 "
    "차트 의무는 면제 대상입니다. 발송 스크립트는 scratchpad에 있어 프로젝트 산출물을 오염시키지 않았습니다."
)
TP_07_33_TURN = (
    "R45 판정 — **근원 규명, 그리고 반전**: stored Ret이 **참값**이고, \"stored 오염 의심\"이 "
    "뒤집혔습니다. recompute(Close/전일Close−1)가 결측 거래일(hole)을 gap 넘어 stale 값으로 계산한 "
    "artifact였습니다 — 196 종목-일 전부 비-유니버스(4월 이음매 잔여 + 소형 seam)이고, stored Ret은 "
    "물리타당 100%입니다. **factor_db는 stored Ret을 직접 소비하므로 오염 아님**, 현 북 7팩터는 "
    "유니버스 필터로 196건 미선택 → **라이브 factor 영향 ZERO 확정**.\n\n"
    "데이터 무결성 라인(R42~R45)이 라이브 완전 무영향으로 완결됐습니다. 무결성 배선을 완성하는 "
    "R46(Close 연속성 tripwire + firewall 정련)을 발사합니다:\n"
    "밤샘 데이터 무결성 라인(R42~R46)이 라이브 완전 무영향 + stored Ret 참값 규명으로 완결 중입니다. "
    "이 발견은 재사용 지식이라 메모리에 등재합니다."
)
REPLAY_TESTS = [
    # (name, text, expect_block, marker, verdict_artifact)
    ("RP_fp_20260717_1928_briefing_no_artifact", FP_19_28_TURN, False, None, False),
    ("RP_fp_20260717_1928_briefing_if_verdict_turn", FP_19_28_TURN, True, None, True),
    ("RP_tp_20260715_0733_finality_ops_turn", TP_07_33_TURN, True, None, False),
    ("RP_tp_20260715_0733_finality_verdict_turn", TP_07_33_TURN, True, None, True),
]


def main():
    fails = []
    for t in TESTS + REPLAY_TESTS:
        name, text, expect_block, marker = t[0], t[1], t[2], t[3]
        va = t[4] if len(t) > 4 else None
        res = judge(text, marker=marker, verdict_artifact=va)
        got = res["block"]
        ok = (got == expect_block)
        tag = "PASS" if ok else "**FAIL**"
        print(f"[{tag}] {name}: expect_block={expect_block} got_block={got}")
        if not ok:
            fails.append(name)
            print("   diag:", res.get("diag"))
            if res.get("reason"):
                print("   reason head:", res["reason"][:160].replace("\n", " "))

    # 보조 유닛: _count_next_probes / append_case dedup
    print("\n--- unit ---")
    p2 = G._count_next_probes("next_probe: ①... ②...")
    assert p2["ok"], "next_probe ①② should be ok"
    print("count_next_probes ①②:", p2)
    p0 = G._count_next_probes("결과를 정리했습니다.")
    assert not p0["ok"], "no next_probe should be not-ok"
    print("count_next_probes none:", p0)

    # C3 유닛: suppression 문맥 구절 추출 + 마스킹(양방향 루프) — registry 무변경 순수함수만
    ph = G._context_phrases("자본 졸업 관문 3종과 screen-tier 회수 방향을 정리했습니다", "screen-tier")
    assert ph and all("screen-tier" in x and len(x) > len("screen-tier") + 3 for x in ph), \
        "context phrase must carry token + context"
    print("context_phrases:", ph)
    fake_cases = {"suppressions": [{"token": "screen-tier", "phrase": ph[0]}]}
    masked = G._apply_suppressions("보고: 자본 졸업 관문 3종과 screen-tier 회수 방향을 정리했습니다", fake_cases)
    assert "screen-tier" not in masked, "suppression phrase must mask the token"
    bare = G._apply_suppressions("screen-tier 확정", {"suppressions": [{"token": "screen-tier", "phrase": "screen-tier"}]})
    assert "screen-tier" in bare, "bare-token suppression must be rejected (min-length guard)"
    print("suppression masking: ok (bare-token guard ok)")
    hint_fp = G._triage_hint("R34 측정 중입니다. 다음 큐: FQ-038.", CASES)
    hint_tp = G._triage_hint("이 계열은 종착입니다. 재시도 가치 없음.", CASES)
    assert hint_fp.startswith("FP성") and hint_tp.startswith("TP성"), "triage hints must separate FP/TP"
    print("triage hints: FP=", hint_fp[:30], "... / TP=", hint_tp[:30], "...")

    total = len(TESTS) + len(REPLAY_TESTS)
    print("\n" + "=" * 56)
    if fails:
        print(f"BATTERY: {total-len(fails)}/{total} pass — FAILURES: {fails}")
        sys.exit(1)
    print(f"BATTERY: {total}/{total} pass — ALL GREEN")
    sys.exit(0)


if __name__ == "__main__":
    main()
