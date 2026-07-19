# =============================================================================
# FQ-057 NP4-P1c run_05: verdict JSON 조립 (실 book SPLIT 재확인)
#   metric_type=risk_forecast_accuracy_diagnostic. 자본/성과/weight 주장 없음.
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
M  <- fromJSON(file.path(OUT_DIR,"p1c_metrics.json"), simplifyVector=FALSE)
rm3 <- fromJSON(file.path(OUT_DIR,"p1c_run03_meta.json"), simplifyVector=FALSE)
dg  <- as.data.table(read_parquet(file.path(OUT_DIR,"p1c_sigma_diag.parquet")))
sig_diag <- dg[, .(cond_median=round(median(cond),2), min_ev_median=round(median(min_ev),6),
                   psd_rate=mean(psd)), by=arm]

g <- function(pf,win,tg,pair) {
  b <- M[[win]][[pf]][[tg]]; if(is.null(b$paired)) return(list(t=NA,diff=NA,n=b$n))
  p <- b$paired[[pair]]; list(t=p$dm_nw_t_lag3, diff=p$mean_qlike_diff, n=p$n, verdict=p$verdict) }

verdict <- list(
  id = "FQ-057-NP4-P1c",
  parent = "FQ-057-NP4-P1",
  lane = "method_frontier",
  round_type = "independent_research_round_not_WT",
  agent = "risk-research",
  finalized_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  pin_tag = "fq057_20260718_171024",
  preregistration_ref = "stage_artifacts/method_frontier/p1c_preregistration.json",
  metric_type = "risk_forecast_accuracy_diagnostic",
  selection_objective = "estimation_quality (QLIKE 예측손실 — R4 P3, SR/IR/alpha 미사용)",
  capital_claim = FALSE, graduation_claim = FALSE, weight_proposal = FALSE,

  hypothesis = paste0("P1 SPLIT 판정[(a)ADOPT lw_nls /(b)KEEP EWMA-direct]이 book FORM proxy",
    "(cap-w mom top-25)로 측정됨 → 실 production book(STR_1715_on_M4_R05_noLayer4_PG2)의 ",
    "active weight(score_eff top-20 LinearTilt × invested=m4×β_R05)에서 부호·유의성 유지되는가."),

  verdict = paste0("SPLIT 부분 확증 — (b) KEEP EWMA-direct 는 실 book에서 강건 유지, ",
    "(a) ADOPT lw_nls 는 '방향(lw_nls 어디서도 열등 아님) + TOTAL-분산 채널(DM-t -4.0)'은 유지되나 ",
    "P1이 강조한 PRIMARY TE-채널 유의성은 소실(fullinv DM-t -0.73 / overlaid -1.47 = tie, P1 -3.06). ",
    "= P1 (a)의 TE-채널 강도는 FORM-proxy 아티팩트(cap-w-mom 집중이 linear LW μI 퇴화 페널티를 증폭). ",
    "운영 권고(risk_package는 p>n 대형 Σ에 lw_nls 사용)는 존속(never-worse + total 지배)하되 정당화는 ",
    "'TE 개선'이 아니라 '총분산/집중-active 안전'으로 축소."),

  book_source = list(
    admitted_id = "STR_1715_on_M4_R05_noLayer4_PG2",
    production_code_path = "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/forward_weights_R05_noLayer4.R",
    weight_recipe = "LinearTilt(score_eff top-20, λ=1.5, UB0.20, LIQ 2e8 t-1) [.tilt/.norm production verbatim port] × invested(m4×β_R05)",
    score_base = "alpha_scores_str1715_268m_cleanT1.parquet (score_eff)",
    production_parity_verified = TRUE,
    parity_basis = paste0("cleanT1 meta: production _recompute_alpha_asof.R 직접실행 대비 spearman 0.975~0.997(4 sample months, 2006/2013/2020/2026). ",
      "가중은 production forward_weights .tilt/.norm verbatim port(결정론적). §7b 준수 — 저장 파생 패널 직접 재사용 아님, production-parity 라벨 후 소비, 05_Production 무수정."),
    invested_source = "period_returns_layer5_faith.csv (production materialized m4·beta_R05)",
    elig_restriction_note = "실 book 선택을 elig(complete-60m)로 제한 = Σ 이차형식 coverage 필수. production 무제한 유니버스 top-20 대비 overlap 중앙값 18/20(min 13, ≥17 in 81% months) — 편차 경미."),

  pin_and_machinery = list(
    pin_tag = "fq057_20260718_171024 (P1 상속, read_pinned)",
    machinery_identical_to_P1 = TRUE,
    proof = "Σ cond 중앙값 lw_linear 1.00 / lw_nls 98.14 / ewma_struct Inf = P1 sigma_diagnostics 완전 일치. 입력(월간/일간/liq/snapshot) P1 pinned 재사용 → 유일 변경 = 포트 active vector.",
    sigma_diagnostics = setNames(lapply(seq_len(nrow(sig_diag)), function(i)
      as.list(sig_diag[i])), sig_diag$arm),
    lw_degenerate_months = rm3$lw_degenerate_months,
    book_months = rm3$book_months,
    invested_median = rm3$invested_median,
    real_book_concentration = "held HHI 중앙값 0.115 / n_eff 8.7 / wmax 0.200(cap binds); invested min 0.403 · 36% months <1(CAUTION 0.65/CRISIS 0.45 de-risk)"),

  n_months = list(full_range = g("real_book_fullinv","results_full_range","te","a_lwnls_vs_lwlinear")$n,
                  recent_60m = M$results_recent_60m$real_book_fullinv$te$n,
                  capw_replica = g("capw_mom_proxy","results_full_range","te","a_lwnls_vs_lwlinear")$n),

  harness_validation = list(
    capw_mom_proxy_reproduces_P1 = TRUE,
    detail = paste0("in-run P1 replica(capw_mom_proxy) TE: a_lwnls_vs_lwlinear DM-t=",
      g("capw_mom_proxy","results_full_range","te","a_lwnls_vs_lwlinear")$t,
      " (P1=-3.0569), b_lwnls_vs_ewma_direct DM-t=",
      g("capw_mom_proxy","results_full_range","te","b_lwnls_vs_ewma_direct")$t,
      " (P1=-1.2363) — 완전 재현 → 하네스·창·Σ 동일, 차이는 전적으로 active vector.")),

  # ===== 핵심: split_verdict_holds =====
  split_verdict_holds = list(
    a_ADOPT_lw_nls = list(
      P1_claim = "risk_package 대형-유니버스 Σ: ADOPT lw_nls over linear LW (P1 PRIMARY=TE capw DM-t -3.06)",
      direction_holds = TRUE,
      direction_basis = "lw_nls QLIKE 가 linear LW 이상으로 나쁜 셀 없음 — 실 book TE diff 음수(fullinv -0.0162 / overlaid -0.0312), total diff 음수(-0.526/-0.521). lw_nls never-worse 유지.",
      te_channel_significance_holds = FALSE,
      te_channel = list(
        fullinv_full  = g("real_book_fullinv","results_full_range","te","a_lwnls_vs_lwlinear"),
        overlaid_full = g("real_book_overlaid","results_full_range","te","a_lwnls_vs_lwlinear"),
        fullinv_recent = g("real_book_fullinv","results_recent_60m","te","a_lwnls_vs_lwlinear"),
        overlaid_recent= g("real_book_overlaid","results_recent_60m","te","a_lwnls_vs_lwlinear"),
        interpretation = "실 book LinearTilt active 의 TE 예측에서 lw_nls 는 linear LW 를 유의 초과 못함(|t|<2 tie, P1 -3.06 대비 소실). = P1 (a)의 TE-채널 강도는 cap-w-mom proxy 아티팩트."),
      total_channel_significance_holds = TRUE,
      total_channel = list(
        fullinv_full  = g("real_book_fullinv","results_full_range","total","a_lwnls_vs_lwlinear"),
        overlaid_full = g("real_book_overlaid","results_full_range","total","a_lwnls_vs_lwlinear"),
        fullinv_recent = g("real_book_fullinv","results_recent_60m","total","a_lwnls_vs_lwlinear"),
        interpretation = "총분산(홀딩 20종 자기분산)에선 실 book도 lw_nls 강건 우월(DM-t -4.0 full / -2.9 recent) — linear LW μI 는 25% 과소예측(predvol 0.166 vs 실현 0.220)."),
      operational_recommendation = "STANDS_with_narrowed_justification",
      operational_detail = "risk_package p>n 대형 Σ 는 lw_nls 소비 유지가 안전(never-worse + total 지배 + concentrated-active 보호). 단 '단일-book TE 모니터링 개선'을 근거로 삼지 말 것 — 분산된 LinearTilt active 에선 linear LW TE 페널티 무의미(tie)."),

    b_KEEP_ewma_direct = list(
      P1_claim = "monitoring TE 기준선: KEEP EWMA-direct (lw_nls 가 EWMA-direct 를 유의 초과 못함, P1 -1.24 tie)",
      holds = TRUE,
      basis = "실 book TE 4셀 중 3셀 tie: fullinv full DM-t -1.256 / fullinv recent +0.286 / overlaid recent -0.197. 유일 예외 overlaid full DM-t -2.025(lw_nls 근소 우월) 이나 recent-60m(-0.197)·fullinv 에서 미재현 = 경계·비강건. → KEEP EWMA-direct 유지.",
      cells = list(
        fullinv_full   = g("real_book_fullinv","results_full_range","te","b_lwnls_vs_ewma_direct"),
        overlaid_full  = g("real_book_overlaid","results_full_range","te","b_lwnls_vs_ewma_direct"),
        fullinv_recent = g("real_book_fullinv","results_recent_60m","te","b_lwnls_vs_ewma_direct"),
        overlaid_recent= g("real_book_overlaid","results_recent_60m","te","b_lwnls_vs_ewma_direct"))),

    overall = M$overall_full_range),

  new_finding = list(
    ewma_struct_beats_lwnls_on_realbook_total = list(
      fullinv_full  = g("real_book_fullinv","results_full_range","total","lwnls_vs_ewma_struct"),
      overlaid_full = g("real_book_overlaid","results_full_range","total","lwnls_vs_ewma_struct"),
      note = "실 book 총분산에서 다변량 EWMA(형태-추적 MZ r2 0.17~0.30)가 lw_nls를 유의 초과(+2.42/+2.45). P1 proxy(+0.91 tie)에선 미검출 — 분산된 실 book 에서 vol-clustering 추적이 총분산 예측에 값. TE에선 여전히 tie. P1 P1b(레벨+형태 결합)와 정합.")),

  mechanism_diagnosis = list(
    proxy_concentration_inflated_te_penalty = paste0(
      "linear LW μI 퇴화의 TE-예측 페널티는 active vector 가 off-diagonal 상관에 의존하는 정도에 비례. ",
      "cap-w-mom proxy active = 소수 대형주 cap-w 베팅(상관 고의존) → μI 크게 오차 → lw_nls TE QLIKE 0.244 vs linear 0.389(diff -0.145, t -3.06). ",
      "실 book LinearTilt(score_eff, λ1.5, cap0.20) active = 4F-consensus mid-cap 틸트로 분산(실현 TE 0.175<0.187) → 이차형식 대각지배 → μI 평균분산 근사로 충분 → lw_nls TE QLIKE 0.186 vs linear 0.203(diff -0.016, t -0.73 tie)."),
    total_channel_robust = "총분산(long 20종 시장부하)에선 상관구조가 항상 지배 → μI 실패 강건 → lw_nls 우월 both proxy·real book (-4.0). = P1 (a) 핵심 가드는 total 채널로 존속.",
    overlay_second_order = "invested overlay(m4×β_R05, 36% months<1)는 active 를 스칼라 축소 + 벤치 미스케일 → active 구조 변화이나 결론 불변(fullinv≈overlaid, a tie·b hold). de-risking 이 판정 안 바꿈.",
    b_intrinsic = "단일 포트 자기 TE 추적은 직접법(EWMA-direct)이 구조 Σ 대비 손색없음 — active 구조(proxy든 real든) 무관하게 robust. ⑧행 EWMA-direct 확정 재확인."),

  small_n_caveat = paste0("본 라운드는 단일 book·단일 신호(score_eff)·단일 벤치(cap-w elig) — 검정력·일반성 제한. ",
    "recent-60m 하위창(n=71)은 DM |t|<2 다수 = 무판정(방향만). full-range(n=185) 가 주 검정이나 이 역시 단일-book 진단 — ",
    "타 book/신호로의 일반화는 미검(next_probe). (a) TE-tie 는 '실 book에선 linear LW TE 무해'의 실측이지 'lw_nls 무용'의 증거 아님(never-worse)."),

  limitations = list(
    "벤치 = cap-w over elig(실 index 아님, 실 book 벤치=KOSPI200과 상이). paired DM 는 arm 상대비교라 벤치 불변 — verdict 방향 robust.",
    "실 book 선택을 elig(complete-60m)로 제한 = Σ coverage 필수. production 무제한 top-20 대비 overlap 18/20(경미) — 그러나 완전 동일 아님.",
    "score_eff = cleanT1 패널(production_parity_verified, spearman 0.975~0.997) — production 직접실행 아님(4-month spot parity로 근사). 가중은 verbatim port(결정론적).",
    "invested overlay 는 layer5_faith materialized 값(β_faith 포함 패널이나 invested=m4×β_R05만 취함 — noLayer4 정의 정합). β_R05 재계산 아님(production materialized 소비).",
    "총분산 채널은 20종 p<n sub-block — 25종 hard 제약과 정합(실 book N_TARGET=20). TE 가 PRIMARY(P1 정합).",
    "MVP/포트는 진단 instrument — allocation 제안 아님(role boundary)."),

  next_probes = list(
    list(id="P1c-i", title="타 book/신호 일반화 — score_eff 외 alpha 신호의 active 집중도 스펙트럼 × lw_nls TE-edge",
         detail="cap-w-mom(집중) → LinearTilt(분산) 사이 스펙트럼에서 lw_nls TE-edge 가 active HHI/n_eff 에 어떻게 비례하는지 실측 — '언제 lw_nls TE 개선이 실질인가' 규칙화. risk_package Σ 소비 트리거 정량화."),
    list(id="P1c-ii", title="ewma_struct 형태-추적을 실 book 총분산/regime TE 경보에 (P1b 재발화)",
         detail="실 book total 에서 ewma_struct 유의 우월(+2.4) — lw_nls(레벨) + ewma_struct(형태) 결합이 총분산·CRISIS-진입 TE 경보 QLIKE 를 개선하는지. monitoring 총위험 경보 레인."),
    list(id="P1c-iii", title="risk_research_init posterior ① 문구 정정 반영 확인",
         detail="<v83_dual_basis_captier> 현행 posterior ① '대형-유니버스 Σ=lw_nls ADOPT' 에 P1c caveat(TE-채널 강도는 proxy-inflated·근거=total/집중-active) 추가 — WT-시점 오소비 방지.")),

  revival_or_followup_conditions = list(
    "risk_package lw_nls 대형-Σ 소비는 유지(never-worse). 단 신규 book 의 active 가 고분산(HHI 낮음)이면 linear LW TE 무해 → lw_nls 전환의 TE-근거 약화(P1c-i 규칙 적용).",
    "monitoring lw_nls-TE 재검토: tier-factor/ewma_struct 결합이 EWMA-direct 를 실 book TE 에서 t<=-2 로 유의 초과 시(현재 미달, P1c-ii).",
    "risk_research_init posterior ① 정정 미반영 시 WT-시점 '실 book TE 개선' 오귀속 위험 — Q-Lead 반영 확인 필요."),

  self_adversarial = list(
    accept = list("P1 (a)의 TE-채널 유의성이 실 book에서 소실 = FORM-proxy 아티팩트 실측 인정(P1 C3 caveat 정확 명중)",
                  "단일-book·단일-신호 일반성 제한 인정(P1c-i armed)"),
    partial = list("elig-restriction(complete60) 로 production 무제한 유니버스와 완전 동일 아님(overlap 18/20)",
                   "score_eff = parity-verified 패널(직접 production 실행 아님)"),
    rebuttal = list("하네스 유효성 = capw_mom_proxy 가 P1 완전 재현(a -3.057=−3.0569, b -1.236=−1.2363) + Σ cond bit-일치 → 차이는 전적으로 active vector(측정 신뢰)",
                    "(a) 운영 권고 존속은 방어적 — lw_nls never-worse + total 지배; 'TE-tie'를 'lw_nls 폐기'로 과대해석 안 함",
                    "QLIKE=Patton 2011 robust loss, paired DM 벤치-불변 → 벤치 limitation이 verdict 안 뒤집음")),

  artifacts = list(
    runner_dir = "04_Research/method_frontier/fq057_p1c_realbook/",
    preregistration = "stage_artifacts/method_frontier/p1c_preregistration.json",
    pairs = "stage_artifacts/method_frontier/p1c_pairs.parquet",
    sigma_diag = "stage_artifacts/method_frontier/p1c_sigma_diag.parquet",
    book_panel = "stage_artifacts/method_frontier/p1c_book_panel.parquet",
    metrics = "stage_artifacts/method_frontier/p1c_metrics.json",
    challenge_note = "stage_artifacts/method_frontier/p1c_challenge_note.md")
)
write_json(verdict, file.path(OUT_DIR,"p1c_verdict.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("[done] run_05 verdict written. overall=", M$overall_full_range, "\n")
