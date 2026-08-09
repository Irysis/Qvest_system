## alpha_package.json (AST v1.1) — 자격 arm 0 라운드
## ★승계 가설 재작성 금지: alpha_hypothesis.json 문자열 그대로 이관, 형식만 게이트 계약형.
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260809_005")
say <- function(fmt,...) { cat(sprintf(paste0("[pkg] ",fmt,"\n"),...)); flush.console() }
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a

AV  <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)
HYP <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector=FALSE)
A   <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
say("★입력 실측: alpha_scores %d행 · %d개월 · 최신 신호월 %s · hypothesis 최상위 키 %s",
    nrow(A), uniqueN(A$signal_ym), max(A$signal_ym), paste(names(HYP), collapse=","))

## 승계본에서 primary(C18) 블록 찾기 — 구조 가정하지 않고 탐색
## ★구조를 가정하지 않고 재귀 탐색: C18 을 이름으로 가진 list 노드를 찾는다
find_primary <- function(node, depth=0L) {
  if (!is.list(node) || depth > 6L) return(NULL)
  nm <- unlist(node[intersect(names(node), c("factor","factor_id","name","arm","proxy"))])
  if (length(nm) && any(grepl("C18", as.character(nm), fixed=TRUE))) return(node)
  for (e in node) { r <- find_primary(e, depth+1L); if (!is.null(r)) return(r) }
  NULL
}
S <- find_primary(HYP$selected$primaries) %||% find_primary(HYP$selected) %||% find_primary(HYP)
say("승계 primary 블록 %s (키: %s)", if (is.null(S)) "미발견" else "발견",
    if (is.null(S)) "-" else paste(names(S), collapse=","))

as_chr <- function(x) if (is.null(x)) NA_character_ else paste(unlist(x), collapse=" ")
mech <- S$mechanism %||% S$economic_rationale %||% NULL

pkg <- list(
  task_id = "WT-D20260809_005",
  frontier_queue_id = "FQ-198",
  as_of_date = as.character(max(A$signal_ym)),
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  build_hash = AV$build_hash,
  metric_type = "canonical_screen_diag",

  pit = list(
    sig_date = as.character(max(A$signal_ym)),
    decision_ts = "sig_date + 1 거래일 (컨센서스 registry known_discrepancy — 보수 가용시점)",
    decision_ts_rationale = "컨센서스 33종은 registry 가 same-day vintage 를 known_discrepancy 로 자인. 본 라운드는 자격 미달로 배포 경로에 오르지 않으므로 T+1 실행앵커 재측정은 미실시(미측정 항목으로 명시)."
  ),

  hypothesis = list(
    statement = as_chr(S$hypothesis_statement %||% S$statement),
    mechanism = if (is.null(mech)) NULL else list(
      agent = as_chr(mech$agent), friction = as_chr(mech$friction), path = as_chr(mech$path %||% mech)),
    falsification = list(
      list(field = "C18_Earnings_CAR_3d",
           observable = "발표일 프록시가 종목별 실제 발표일을 식별해야 이벤트-CAR 해석이 성립한다",
           reject_if = "프록시 날짜가 전 종목 공통 월말 창으로 수렴하면 이벤트 팩터가 아니다",
           measured = "고유 ann_date 월당 5~6개 (같은 달 종목 287~382개) · sig_d−ann_date 중앙 3~7일 ⇒ **반증 성립**"),
      list(field = "C18_Earnings_CAR_3d",
           observable = "모멘텀/단기반전 통제 후에도 증분이 남아야 자격 인정 (가설설계가 자격 전제조건으로 격상)",
           reject_if = "통제 후 |t| < 2.0 이면 재포장 — t 값과 무관하게 자격 불인정",
           measured = "trail6d 통제 |t| 2.551→1.486(0.58) · 전체 통제 1.554(0.61) · trail6d 와 spearman +0.674 ⇒ **반증 성립**"),
      list(field = "C18_Earnings_CAR_3d",
           observable = "사전 지정 부호(+, PEAD underreaction) 방향으로 계수가 나와야 한다",
           reject_if = "부호가 반대면 기전 가설 반증",
           measured = "FMB t −2.551 · 단독 rank-IC −0.0246 (t −3.12) ⇒ **부호 반증 성립**"),
      list(field = "C10_SUE_Persistence / C13_Revision_Breadth_3m",
           observable = "신규 팩터가 incumbent 와 구별되는 값을 가져야 한다",
           reject_if = "완전동일이면 재탕",
           measured = "표본월 8건 전건 완전동일 1.0000 · 최대절대차 0.000e+00 · spearman +1.000000 ⇒ **재탕 확정**"),
      list(field = "C15_Forecast_Error_Trend",
           observable = "팩터가 factor_db 에 실제로 산출되어야 측정 가능하다",
           reject_if = "미산출이면 측정 불가",
           measured = "인접 2영업일 차분이 정확히 0 인 비율 1.000000 · sd 0.000000e+00 · 커넥터 4표본월 전건 부재 ⇒ **미산출 확정**")
    ),
    regime_scope = list(
      holds_in = as.list(unlist(S$regime_scope$holds_in %||% list("측정 전 기각 — 국면 경계 소비 없음"))),
      weakens_or_reverses_in = as.list(unlist(S$regime_scope$weakens_or_reverses_in %||% list("해당 없음"))),
      boundary_rationale = as_chr(S$regime_scope$boundary_rationale %||%
        "본 라운드는 전표본 횡단면 판정이며 국면 분할을 하지 않았다(구조적 저검정력 회피). 국면 경계는 사후 해석 가이드로만 승계.")
    ),
    inherited_from = "alpha-hypothesis (model: fable) — qepm/mailbox/worktask/WT-D20260809_005/alpha_hypothesis.json (revision 2)",
    inheritance_note = paste0(
      "mechanism / regime_scope 는 문자 그대로 승계(재작성 금지). falsification 은 내용 보존 + 게이트 계약형(배열+field) 재배치 후 ",
      "**measured 필드에 실측 결과만 추가**했다. ★승계본 revision 2 는 alpha-research 의 P0 실측을 받아 스스로 ",
      "primaries 4 → primary 1 + exploratory 3 + dead 3 으로 개정한 것이다 — 담체 검사(관측 간격 ≥40거래일)가 자기 반증으로 발화했다.")
  ),

  factors = list(list(
    factor_id = "F1_C18_earnings_car_3d",
    ast = list(op = "CS_ZSCORE", args = list(list(leaf = "REGISTRY", factor = "C18_Earnings_CAR_3d"))),
    role = "core_signal",
    restatement_exposure = 0
  )),
  combination_rule = "single_factor",

  ## ★자격 미달 — 하류(risk/optimizer/forge)로 전진하지 않는다
  verdict = "no_material_qualified",
  advance_to_risk = FALSE,
  advance_block_reason = paste0(
    "원안 4종 + exploratory 3종 전부 재료 자격 불성립. primary C18 은 |t| 2.551 로 문턱은 넘었으나 ",
    "사전등록 자격 전제조건(모멘텀/반전 배제)을 통과하지 못했다(통제 후 |t| 1.486). ",
    "alpha_vector 를 발행하지 않는다 — 하류가 소비할 알파가 없다."),

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "C18_Earnings_CAR_3d",
           availability_rule = "Date <= sig_d (컨센서스 daily, registry 선언 T-1 · known_discrepancy)",
           restatement_prone = FALSE,
           provenance = "factor_db 월 파일 → load_month_factors() 커넥터 경유(C15). Z_Score_Aligned = 방향정렬 횡단면 z(C13)",
           window_check = "신호창 종점 = 신호월 거래일 월말 · 수익창 = (월말, +1개월] ⇒ 창 비중첩. align_signal_return_ym(off=0, signal_anchor), 월 coverage 1.000"),
      list(leaf = "C10s/C13s/C15s (스텝 프로토타입)",
           availability_rule = "consensus 원천 Date <= sig_date (스텝 압축은 전역 1회, PIT 는 step_date <= sig_date 로 적용)",
           restatement_prone = FALSE,
           provenance = "factor DB 에 부재하는 신규 프로토타입 → consensus 원천 파생(C15 우회 아님). 부호는 사전 지정, IC 사후 정렬 없음(C13)",
           window_check = "★PIT parity 실측: 원천 재계산 C01 ↔ 커넥터 C01 월별 spearman 중앙 0.999993 · 최소 0.999986 · 11/11 월 양의 부호")
    ),
    verdict = "clean",
    residual_risk = "커넥터 z 와 내 평 z 의 |rho| 가 정확히 1.000000 은 아니다(0.999986~0.999996) — winsorization/동점 처리 차이로 보이나 **원인 미측정**. 판정에 영향 없는 크기."
  ),

  alpha_vector = NULL,
  confidence_vector = NULL,
  signal_matrix_ref = "stage_artifacts/WT_D20260809_005/alpha_scores.parquet",

  factor_specs = list(list(
    factor_family = "Consensus_Earnings_Event",
    proxy = "C18_Earnings_CAR_3d",
    formula = "sum(Ret - BM_Ret) over [ann_date-3, ann_date+3], ann_date = sue_hist[Date <= sig_d-3 & >= sig_d-400] 최신 → 횡단면 Z_Score_Aligned",
    formula_reality_check = "★실측: ann_date 가 월당 고유 5~6개로 수렴 = 종목별 발표일이 아니라 전 종목 공통 월말 창. 실질 정의 = **월말 고정 ~6일 시장조정 수익**",
    lag_rule = "Date <= sig_date",
    winsorization = "factor_db 빌더 내장 (원형 소비 — no_sweep)",
    neutralization = "none (판정은 incumbent 3종 동시 회귀로 통제)",
    economic_rationale = as_chr(mech$path %||% mech %||% "승계 서술 — 실측으로 반증됨(부호 반전 + 반전 재포장)"),
    weight_theta = 0.0,
    source = "db_existing",
    redundancy_cluster_id = "short_term_reversal_cluster (★registry 는 consensus/earnings 계열로 선언 — 실측은 trail6d spearman +0.674 로 **반전 클러스터**. 라벨 정정 제안)",
    references = list("Bernard-Thomas (1989) PEAD — 출발점 인용이며 채택 근거 아님(본 라운드에서 반증)")
  )),

  diagnostics = list(
    fmb_increment_t_nw_lag3 = AV$primary$fmb_nw3_t,
    fmb_increment_t_after_reversal_control = AV$c18_identity$reversal_control$full$t_nw3,
    reversal_control_retention = AV$c18_identity$retention_vs_base$full,
    rank_ic = AV$primary$rank_ic, icir = AV$primary$icir,
    harvey_t_stat = AV$primary$rank_ic_t_nw3,
    vif_med = AV$primary$vif_med,
    placebo_p = AV$primary$placebo_p,
    lag1_retention = AV$primary$lag1_retention,
    canonical_port_t_nw_lag3 = AV$transition$capw_port_t_raw,
    canonical_port_t_ew_universe = AV$transition$ew_universe_port_t_raw,
    canonical_port_t_post2017_ew = AV$transition$post2017_t_ew,
    turnover_proxy = AV$transition$turnover_annual_raw,
    net_sr = AV$transition$net_sr_raw,
    oos_retention_approx = NA,
    subperiod_stability = "2001-2009 t −2.01 / 2010-2016 −0.69 / 2017-2026 −1.57 (advisory)",
    monotonicity = NA, post_neutralization_ic = NA
  ),

  selection_objective = "material_qualification_fmb_increment_t",
  method_shopping_log = list(
    candidates_tried = 7L, n_trials = 4L, selection_type = "preregistered_family_grid",
    method_log = list(
      list(name = "C18_Earnings_CAR_3d", kind = "primary_preregistered", fmb_nw3_t = AV$primary$fmb_nw3_t, selected = FALSE),
      list(name = "C10s_SUE_Persist_step", kind = "exploratory_precheck_discovered", fmb_nw3_t = AV$exploratory[[1]]$fmb_nw3_t, selected = FALSE),
      list(name = "C13s_RevBreadth_step", kind = "exploratory_precheck_discovered", fmb_nw3_t = AV$exploratory[[2]]$fmb_nw3_t, selected = FALSE),
      list(name = "C15s_SUE_Trend_step", kind = "exploratory_precheck_discovered", fmb_nw3_t = AV$exploratory[[3]]$fmb_nw3_t, selected = FALSE),
      list(name = "C10_SUE_Persistence", kind = "dead", verdict = "duplicate_of_incumbent(C01_SUE)", selected = FALSE),
      list(name = "C13_Revision_Breadth_3m", kind = "dead", verdict = "duplicate_of_incumbent(C04_ESBR)", selected = FALSE),
      list(name = "C15_Forecast_Error_Trend", kind = "dead", verdict = "not_emitted_zero_variance", selected = FALSE)
    ),
    bonferroni_two_sided_t = 2.50,
    note = "자격 arm 0 이라 선택할 챔피언이 없다 — DSR 적용 대상 자체가 부재. exploratory 3종은 사전등록 원안 밖(P0 중 발견)이라 primary 와 동일 증거력으로 읽지 말 것."
  ),

  challenge_flags = c(
    "[HIGH] primary C18 의 사전등록 부호(+)가 반증됨 — 관측 부호 −(FMB t −2.551 · rank-IC t −3.12). 기전 가설(PEAD underreaction) 성립 안 함",
    "[HIGH] C18 은 이벤트-CAR 가 아님 — '발표일 프록시'가 월당 고유 5~6개로 수렴(종목 287~382개 대상). 실질 = 월말 고정 6일 시장조정 수익, trail6d spearman +0.674",
    "[HIGH] 사전등록 자격 전제조건(반전/모멘텀 배제) 미통과 — trail6d 통제 시 |t| 2.551→1.486(0.58) · 전체 통제 1.554(0.61)",
    "[HIGH] C10_SUE_Persistence ≡ C01_SUE · C13_Revision_Breadth_3m ≡ C04_ESBR (완전동일 1.0000 · 최대절대차 0.000e+00 · spearman +1.000000) — 신규 재료 아님",
    "[HIGH] C15_Forecast_Error_Trend 미산출(항등 0, sd 0.000e+00) — ★FQ-163 verdict 의 'C15 300개월 실림' 진술 정정 필요",
    "[MEDIUM] exploratory 3종 전부 검정력 라벨 INCONCLUSIVE_BAR_RESTATES_T (implied_t 2.44~2.58) — '효과 없음'으로 읽지 말 것",
    "[MEDIUM] C18 표본 대형·고서프라이즈 편중(C01 평균 0.221 vs 0.041 · log Size 28.13 vs 26.88) — 수익 편의는 없으나(t 0.22) 일반화 범위 좁음",
    "[MEDIUM] 회전율 16.99/yr — Implementation Discipline 11.0 초과 (6일 창 신호의 필연)",
    "[INFO] 전이 수치(cap-w −1.040 · EW −2.335)는 음의 계수의 거울상 — 부호 반전분 감안해도 |1.04| « 2.95. C13 규칙상 사후 부호 반전 안 함",
    "[INFO] 프롬프트 지시 'FQ-174' 는 병렬 세션 선점(폐지풀 ML 앙상블) — consume_rule 규약대로 FQ-198 로 재배정·재읽기 확인"
  ),

  round_provenance = list(
    prereg = "stage_artifacts/WT_D20260809_005/p1_increment.R 헤더 (실행 전 확정)",
    frame_reuse = "stage_artifacts/WT_D20260808_002/np_m26_increment.R (M26 재료 자격 선례 t +2.555)",
    parent = "FQ-163 (compute_consensus.R 침묵 스킵 7종 수리 + 2026-08-09 factor_db 전면 재빌드)",
    verdict = "no_material_qualified"
  )
)

PKG <- file.path(MB, "alpha_package.json")
write(toJSON(pkg, auto_unbox=TRUE, pretty=TRUE, digits=NA, null="null"), PKG)
say("alpha_package.json 저장 (%d bytes)", file.size(PKG))
chk <- fromJSON(PKG, simplifyVector=FALSE)
say("재읽기 검증: 최상위 키 %d · verdict=%s · advance_to_risk=%s · falsification %d건 · challenge_flags %d건",
    length(chk), chk$verdict, chk$advance_to_risk, length(chk$hypothesis$falsification), length(chk$challenge_flags))
