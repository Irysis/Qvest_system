setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "R35 / FQ-047 P1 / WT-D20260715_004 (SP sales-yield 소비면 재라우팅)",
  verdict_type = "screen_tier_routed",
  mechanism_diagnosis = "SP(V20 매출-yield) EW-basis 트랙은 실신호·PIT-safe(lag1 2.758->2.182 graceful·placebo p=0)·diversifying(P-pure active-corr 0.458/0.423·Jaccard 0.064)이나 자본 미달(cap-w PORT_t 2.236·EW-uni 2.758 둘 다 <2.95, 수용력 median 0.5억원 = EW top-25가 유동성경계 소형 농축으로 배포 불가). 오버레이 한계기여는 base·incumbent 양쪽 post-2024 paired ~0(-0.178/-0.026 = SP-특이 감쇠, live 레버 아님). ★R31 '2024+ 생존축' 정정: cap-w tier-조건부 marginal-vs-붕괴base 프레임 아티팩트 — standalone SP는 pre-2024-지배(EW-active pre 2.51 vs post 1.12·regime의존: 2015-19 사멸, 2020-23 revival). broad 순환-가치 sector(HHI 0.10)·저품질함정 아님(EP-z -0.016). SP=OVERLAY_CANDIDATE feature 보존이지 배포책/live 오버레이 아님.",
  next_probes = c(
    "P1: SP를 RAMP/factor-rotation regime-conditional 입력으로 소비(standalone 아님) — value-favorable 레짐에서만 켜는 조건부 sleeve. 단 cross-family regime-conditional FALSIFIED prior로 저EV·조건부(데이터게이트 없음, feasible now)",
    "P2: value 정의-로테이션 monitoring tripwire 정련(R31 P2 승계) — '상대 vs EBIT/EV' 대신 'SP 절대 rolling-24m EW PORT_t 지속 >2 재상향'을 부활신호로(상대만으론 base-붕괴 아티팩트 재발). monitoring 등록 후보",
    "P3: deployable cap-tier(MEGA/MID)에 SP 신호 잔존 여부 diag_cap_tier 별도 측정 — standalone SP는 OTHER-국소 예상, 저순위(cap-tier 국소화 벽 재확인 예상)"
  ),
  consumer_surfaces = c(
    "⑥선별라벨: SP(V20 매출-yield) = OVERLAY_CANDIDATE feature 보존(real·PIT-safe·diversifying corr<0.5 vs P-pure). standalone 자본/배선 금지 라벨",
    "⑧monitoring: value 정의-로테이션 tripwire 후보(SP 절대 rolling-24m EW PORT_t 지속>2 부활신호) — R31 P2 정정 정련",
    "타모드(RAMP): SP regime-conditional 입력 후보(P1, 저EV·조건부)"
  ),
  frontier_update = "FQ-047 P1 소비 완료: SP 소비면 재라우팅 = screen_tier_routed(feature 보존)+config-scoped negative(standalone 배포·live 오버레이 레버). ★R31 '2024+ 생존' 서사 정정(cap-w marginal 프레임 아티팩트, absolute는 pre-2024-지배). 밸류 아크(R26~R35) EW-basis 소비면까지 확장 측정 완료 — 남은 가치=monitoring tripwire+조건부 feature. FQ-047 status=screen_tier_routed로 갱신.",
  live_trigger = c(
    "SP 절대 rolling-24m EW PORT_t가 지속(>=6개월) >2로 재상향 = 순환-가치 레짐 부활(현 last 2.00, peak 5.12 대비 하락 국면)",
    "value-vs-mega 스타일 로테이션 반전(스프레드 재확대·mega 반도체 레짐 붕괴 — 밸류 아크 공통 부활조건)",
    "SP 오버레이 한계기여 post-2024 paired가 다시 양(+)으로 = live 오버레이 레버 부활신호"
  ),
  layer = "①재료(밸류 정의축) → 소비면은 ⑥선별라벨/⑧monitoring. cap-tier×cap-w 전이 벽 + EW-소형 수용력 벽 재확인 — 성과 병목 해소 아님(feature/monitoring 소비만)",
  evidence_refs = c(
    "stage_artifacts/WT_D20260715_004/verdict.md",
    "stage_artifacts/WT_D20260715_004/alpha_validation.json",
    "stage_artifacts/WT_D20260715_004/challenge_note.md",
    "stage_artifacts/WT_D20260715_004/r35_results.rds",
    "qepm/mailbox/worktask/WT_D20260715_004/alpha_package.json",
    "prereg_sha256 7ddd3cb38f33c3cec9bef28908ca0f3846975bda3b629465e95ef407710faeea"
  )
)

## L-code emit (ledger 완결)
source("02_Infrastructure/axiom/lcode_emit.R")
r <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "R35_SP_sales_yield_consumption_reroute",
  grade = "C",
  metric_type = "canonical_screen",
  construction_type = "sp_ew_basis_track + tilt_overlay_marginal + regime_decomposition",
  selection_type = "chain",
  lesson_text = paste0(
"[canonical_screen 실측] R35 FQ-047 P1 SP(V20 매출-yield) 소비면 재라우팅 — R31이 지목한 '유일 2024+ 생존 밸류 정의'를 cap-w 자본 게이트 밖 EW-basis/OVERLAY 소비면으로 재라우팅. base=clean recon_panels(production_parity_verified off0 T-1 §7b). ",
"★판정: SCREEN_TIER_ROUTED(feature 보존)+config-scoped negative(standalone 배포·live 오버레이). ",
"Part1 EW-basis: SP EW top-25 cap-w PORT_t 2.236·EW-uni 2.758(둘다<2.95)·post2017_t 1.16·oos_v2 EW 0.902(단 2020-23 revival 반영)·capw 0.029·TE_ew 12.6%·TO 3.9·수용력 median 0.5억원(micro-배포불가)·active-corr vs P-pure base 0.458/D-2 0.423(<0.5 diversifying)·Jaccard 0.064. PIT: lag1 EW-uni 2.758->2.182 graceful·placebo(N=60 within-month) p_emp=0.000. ",
"Part2 OVERLAY(m1-drain 형식): base clean paired 1.882(pre24 1.959/post24 -0.178)·incumbent bk paired 1.127(pre24 1.174/post24 -0.026) = 한계기여 pre-2024-only, 양 base 동일 = SP-특이 감쇠(live 레버 아님). ",
"★Part3 2024+ 정정: standalone SP EW-active 부기간 NW-t 2008-14 2.28/2015-19 -0.24/2020-23 2.51/2024+ 1.12 = pre-2024-지배(pre 2.508 vs post 1.119). R31 'SP 2024+ 생존'은 cap-w tier-조건부 marginal-vs-붕괴base 프레임 아티팩트이지 구조적 매출-yield 프리미엄 아님. rolling-24m last 2.00·max 5.12(하락국면). sector HHI 0.10 broad(필수소비재/건설/건강관리+철강/화학 post24)·저품질함정 아님(EP-z -0.016). ",
"방법론: R31 subaxis_panels(SP aligned-z off0 T-1) + WT_D20260714_004 screen_inputs 재사용. canonical_screen_bt(EW top-25 15bps liq2e8)+dual-basis diag. incumbent bk AS_OF(1일)->d0(월말) realized_ym 정렬(reference-book-benchmark-alignment). n_trials=1(chain·DSR 부적용). book_state/05_Production/outputs.ramp 무변경·DART API 금지·cov/weights 미산출(역할경계). pin R28_current_20260714·prereg_sha256 7ddd3cb3. ",
"재라우팅 답(도훈): SP 유일 생존축 = standalone 배포책·live 오버레이 아님(자본미달·수용력 micro·오버레이 pre-2024-only). OVERLAY_CANDIDATE feature 보존(real·PIT-safe·diversifying)+정정지식(2024+ 아티팩트). 소비면=RAMP regime-conditional 입력(P1 저EV)+정의-로테이션 tripwire(P2). ",
"next_probe: P1(SP RAMP regime-conditional 입력, feasible now 저EV); P2(SP 절대 rolling-24m EW PORT_t 지속>2 부활 tripwire); P3(deployable cap-tier SP 신호 diag_cap_tier, 저순위)."),
  mechanism_hypothesis = "R31 유일 2024+ 생존 밸류축 SP를 cap-w 밖 소비면(EW-basis 배포/tilt 오버레이)으로 쓰면 자본 가치가 있는가. 결과: EW-basis 실신호·PIT-safe이나 자본미달+수용력 micro(배포불가), 오버레이 한계기여 pre-2024-only(live 아님). ★R31 '2024+ 생존'=cap-w marginal 프레임 아티팩트 정정(absolute SP=pre-2024-지배·regime의존 순환가치). SP=OVERLAY_CANDIDATE feature 보존.",
  portfolio_alpha_t = 2.236,
  oos_months = 270L,
  core_reference = "FQ-047 P1 (R31 L-AR-20260714_235257 next_probe P1); base clean recon_panels WT_D20260714_004 production_parity_verified; prereg_sha256 7ddd3cb38f33c3cec9bef28908ca0f3846975bda3b629465e95ef407710faeea",
  metrics = list(
    sp_ew_capw_port_t = 2.236, sp_ew_ewuni_port_t = 2.758, ewuni_post2017_t = 1.162,
    oos_v2_ew = 0.902, oos_v2_capw = 0.029, capacity_bil_krw = 0.5,
    active_corr_ppure_base = 0.458, active_corr_ppure_d2 = 0.423, jaccard_ppure = 0.064,
    lag1_ewuni = 2.182, placebo_p = 0.000,
    overlay_base_paired = 1.882, overlay_base_post24 = -0.178,
    overlay_incumbent_paired = 1.127, overlay_incumbent_post24 = -0.026,
    sp_pre2024_nwt = 2.508, sp_post2024_nwt = 1.119,
    subperiod_nwt = "0814:2.28 / 1519:-0.24 / 2023:2.51 / 2426:1.12",
    sector_hhi_post24 = 0.105, ep_z_median = -0.016,
    n_trials = 1L, verdict_type = "screen_tier_routed",
    next_probe = c("SP RAMP regime-conditional (P1)", "SP abs rolling-24m tripwire (P2)", "deployable cap-tier SP (P3)"),
    consumer_surfaces = c("선별라벨: OVERLAY_CANDIDATE feature", "monitoring: value-def-rotation tripwire", "RAMP: regime-conditional input"),
    evidence = "stage_artifacts/WT_D20260715_004/verdict.md"
  ),
  tags = c("book_enhancement","value_definition_spectrum","sales_yield","sp_v20",
           "consumption_reroute","ew_basis","overlay_candidate_feature","screen_tier_routed",
           "config_scoped_negative","capacity_wall","2024plus_artifact_correction",
           "regime_dependent_cyclical_value","captier_localization","value_arc")
)
cat("emitted:", if(is.list(r)) (if(!is.null(r$l_code)) r$l_code else "see-output") else as.character(r), "\n")
