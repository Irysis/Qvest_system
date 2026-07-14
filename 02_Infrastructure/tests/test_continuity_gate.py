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
import os
import sys

ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") \
    or "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "axiom"))
import continuity_gate as G  # noqa: E402

CASES = G.load_cases(ROOT)


def judge(text, marker=None):
    return G.judge_text(text, "", CASES, ROOT, marker_override=marker)


# (name, text, expect_block, marker_override)
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
]


def main():
    fails = []
    for name, text, expect_block, marker in TESTS:
        res = judge(text, marker=marker)
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

    print("\n" + "=" * 56)
    if fails:
        print(f"BATTERY: {len(TESTS)-len(fails)}/{len(TESTS)} pass — FAILURES: {fails}")
        sys.exit(1)
    print(f"BATTERY: {len(TESTS)}/{len(TESTS)} pass — ALL GREEN")
    sys.exit(0)


if __name__ == "__main__":
    main()
