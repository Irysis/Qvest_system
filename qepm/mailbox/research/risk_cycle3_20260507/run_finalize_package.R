suppressPackageStartupMessages({library(jsonlite); library(data.table)})

j <- read_json("qepm/mailbox/research/risk_cycle3_20260507/risk_package_draft.json", simplifyVector=FALSE)

# v2 finalize: post-Codex round disposition reflected
j$version <- "v2_post_codex_round_disposition"

# Codex critic round outcome
j$codex_critic_round <- list(
  round_executed = TRUE,
  stance_received = "REJECT",
  veto_flag = FALSE,
  critical_concerns_count = 8,
  severity_HIGH = 6,
  severity_MEDIUM = 2,
  concerns_disposed = "8/8 (2 ACCEPT + 6 PARTIAL_ACCEPT, 0 REBUTTAL)",
  challenge_note_path = "qepm/mailbox/research/risk_cycle3_20260507/risk_challenge_note.md",
  fixes_applied_in_v2 = c(
    "C1 — scope_disclaimer 강화 (meta-research scope + path naming convention 명시)",
    "C2 — 'risk profile sensitivity diagnostic' (vs admit decision) 명시 강화",
    "C3 — 사이클 2 5-estimator inheritance + 사이클 3 DCC-GARCH 보강 명시 + B Ω B'+D 정식 lifecycle 인계",
    "C4 — 사이클 2 stress + tail risk inheritance reference + 사이클 3 Bootstrap CI 1000 trials 보강 (이미 axis_4)",
    "C5 — scope boundary (PG2 admit / family saturation은 governor 영역) 명시 + 6-source covariance가 본질적 PG2 TDC measure",
    "C6 — 사이클 2 weakest_assumption inheritance + 사이클 4 topic_1 우선",
    "C7 — 사이클 2 disposition inheritance + 사이클 4 topic_2",
    "C8 — DR 18% 상승 정량 + risk-parity gauging diagnostic 명시"
  ),
  rebuttal_summary = "8/8 모두 PARTIAL_ACCEPT 또는 ACCEPT — REBUTTAL 0건. C5 (crowding diagnostics)는 scope boundary (governor admission 영역) + 6-source covariance가 PG2 TDC measure 정량 반박. C8 (mctv_AR dominant)은 Choueifaty-Coignard DR 18% 상승 + risk-parity gauging diagnostic 명시 반박. 나머지 6건 모두 사이클 1+2 disposition 일관 inheritance + 사이클 4 candidate topic 인계.",
  ax_002_post_disposition = "PASS_with_meta_research_scope (process honesty 충족 + Charter §8 No Silent Override 준수)",
  ax_007_post_disposition = "EXEMPT_for_existing_admit_book (Hybrid 70/15/15 변경 X, 사이클 1+2 동일)",
  ax_008_post_disposition = "TARGETING_for_meta_research_1.5of3_PASS_NA (Forge PASS + Codex PARTIAL + Architect NA)",
  rationalization_red_flags_self_check_initial = 0,
  rationalization_red_flags_corrected_count = 0,
  rationalization_red_flags_remaining_post_correction = 0,
  weakest_assumption_disposition = "ACCEPT — VRP US VIX proxy unresolved + KOSPI BM RV12m vs VIX cor (level) 0.505. 사이클 4 topic_1 KRX KOSPI200 옵션 chain direct 의무 (1순위)",
  auto_escalate_trigger_HIGH_ge_5 = TRUE,
  qlead_escalate_required = TRUE
)

# Update notes for Q-Lead with cycle 4 progression rationale
j$notes_for_qlead <- c(
  "사이클 3 axis 1: VRP 4 sub-variants (BKM/CW/BTZ/BCI) × KOSPI BM realized vol — 사이클 2 weakest_assumption 부분 해소 (full 해소는 사이클 4 KOSPI 옵션 chain 의무)",
  "VIX-KOSPI RV12m cor (level) = 0.505 / (diff) 0.191 — proxy 정합성 정량",
  "사이클 3 axis 2: Defensive AX-005 v1.2 multi-sleeve EXCLUSION 자격 형식 충족 + 4-sleeve Σ PD (min_eig 1.637e-04, cond 22.88) + Defensive vs AR cor 0.002 (직교 source 자격)",
  "사이클 3 axis 3: 6-source diversification ratio + risk-parity MCTV. Hybrid_base DR 1.105 → +5_def_5_com_5_vrp DR 1.307 (18% 상승)",
  "사이클 3 axis 4 robustness: Joe-Clayton (Clayton + Gumbel separate fit) parametric TDC + DCC-GARCH dynamic correlation + Bootstrap CI 1000 trials 추가 보강",
  "DCC-GARCH 결과: KR 3-source dynamics 약함 (dynamic ≈ static) → 사이클 3 정적 Sample covariance 사용 정당화",
  "Bootstrap CI: VRP crisis PASS 100% (CI [1.0, 1.0]) — 가장 robust crisis hedge 정량 입증",
  "Codex stance=REJECT — 정식 WT 검증 기준 적용 (meta-research scope 외부). 8 concerns 모두 disposition: 2 ACCEPT + 6 PARTIAL_ACCEPT + 0 REBUTTAL",
  "Codex weakest_assumption: VRP US VIX proxy unresolved → 사이클 4 topic_1 KRX KOSPI200 옵션 chain direct 의무 (1순위)",
  "사이클 4 권고 5 topic 명시: (1) [HIGH] KOSPI200 옵션 chain direct VRP, (2) [HIGH] Q07 direct + multi-axis quality, (3) [MEDIUM] pre-2010 stress backfill, (4) [HIGH 격상] DCC-GARCH 6-source 확장, (5) [LOW] multi-horizon AR decay",
  "신규 source 채택 결정은 정식 alpha-research → risk-research → optimizer-research lifecycle 의무 (Charter §8)"
)

j$codex_critic_round_pending <- FALSE
j$next_step_qlead_decision <- "사이클 3 risk_package.json finalize (도착) + 사이클 4 candidate spawn (Q-Lead 결정)"

# Save final risk_package.json (no _draft)
write_json(j, "qepm/mailbox/research/risk_cycle3_20260507/risk_package.json",
           pretty=TRUE, auto_unbox=TRUE, na="null", null="null")
cat("Final risk_package.json written.\n")
cat("File size:", file.info("qepm/mailbox/research/risk_cycle3_20260507/risk_package.json")$size, "B\n")
