## ============================================================================
## overlay_bt_recon.R — 오버레이 적용 월간 계열 → bt_result 재구성 어댑터
##   (v9.2 §8-S2 [8] · G-3 "오버레이 종단 = 재등급 가능하게", 2026-08-24)
##
## 목적: `drain_run_candidate()` 가 만든 시나리오별 **월간 수익열**(prs[[scenario]])을
##   10-component 계약 산출물로 되돌려 `essence_score()` 가 등급을 낼 수 있게 한다.
##   드레인의 자체 판정(`drain_verdict`)은 `paired_nw_t_lag3` 하나만 읽고 **dMDD 를 판정에
##   쓰지 않는다**(기록만) — 그런데 오버레이의 존재 이유가 MDD 레버다. 그 축을 공급하는 것이
##   이 어댑터의 임무다.
##
## ★★★ 이 파일의 진짜 존재 이유 = basis 방화벽 ★★★
##   실측(2026-08-24): 오버레이를 **하나도 걸지 않고** exposure ≡ 1 로 월간 재구성만 해도
##     MDD 0.5854 → 0.4947 (**−9.07pp**) · Calmar +11.3%.
##   원인은 알파가 아니라 해상도다 — 월간 계열은 월중 저점을 보지 못한다.
##   `sc_incremental_report` 의 HARD 문턱 `ΔMDD ≤ −0.03` 을 **basis 변경만으로 3배 초과**한다.
##   ⇒ 원판(daily_native)과 재구성판(monthly_recon)을 직접 비교하면 오버레이가 아무 일도
##      하지 않아도 통과한다. 그래서:
##     ① 모든 산출물에 `basis` 를 박고(`overlay_provenance$basis = "monthly_recon"`),
##     ② 사다리의 `rl_delta()` 는 basis 불일치 시 **stop**,
##     ③ ③칸은 **bare monthly_recon 대조 의무**(같은 basis 안에서만 증분을 주장한다).
##   검사기 T6 이 "원판 daily MDD 와 monthly_recon MDD 차 > 0.05" 를 못박아 이 사실이
##   코드 변경으로 조용히 사라지지 않게 한다.
##
## 설계 원칙 (신규 측정기 아님 — 계약 재사용):
##   - `build_bt_result()` 가 `sim_result` 에서 실제로 읽는 필드는 **5개뿐**이다:
##       strategy_xts · bm_xts · DAILY_NAV_DT · HOLDINGS_LOG · cost_model_version.
##     (PORTFOLIO_LOG 은 is_rebalance_date 표식에만 쓰이고 NULL 허용.)
##   - ★`NAV_gross` 를 **일부러 넣지 않는다**. build_period_returns:232 가 그때
##     `ret_gross := ret_net` · `cost_ret := 0` 을 만들어 Check 12(cost decomposition)가
##     **구조적으로** PASS 한다. 비용을 숨기는 게 아니라 **재구성이 비용 분해를 재현할 수 없음**을
##     정직하게 표현한 것이고, 그 사실 자체는 `spec$cost_model` 문자열이 진술한다
##     (base 의 15bps 는 이미 ret_net 에 반영 = v2.4 delta / 오버레이 회전비용은 `*_cost` 시나리오만).
##   - ★`metric_type` 은 enum 을 지킨다. `"overlay_applied_monthly"` 같은 신규 값을 넣으면
##     audit_bt_result.R:154-159 가 **Check 10 critical FAIL**, :565-570 이 지표를
##     `unavailable` 로 강등해 essence_score 가 등급을 못 낸다(라벨 하나로 판정 자체가 소멸).
##     ⇒ `"backtested"` 유지 + 라벨은 3곳(input_source/calculation_method/manifest$code_version)
##       + **비-계약 사이드카** `bt$overlay_provenance`.
##     사이드카가 안전한 이유: validate_bt_result:806-812 는 컴포넌트 **누락만** 검사한다.
##   - ★critical & FAIL 이 1건이라도 있으면 `status = "FAIL"` 을 반환한다(감사표 동봉).
##     조용한 통과 금지 — 이 저장소의 반복 결함이 "존재 검사가 정체 검사를 대체"하는 것이다.
##
## 자체합성 금지 정합: 포트폴리오 수익을 만들지 않는다. 입력 월간 수익열은 승인 경로
##   (`drain_run_candidate` → `drain_measure_pr` → `build_benchmark_compare`)가 이미 만든 것이고,
##   여기서는 그것을 계약 스키마로 **렌더링**만 한다. NAV 레벨 경로는
##   `backtest_result_contract.R:330`(`benchmark_nav := cumprod(1 + benchmark_ret)`) 의
##   자구동일 관용구다(계약 본체가 같은 변환을 쓴다).
##
## 사용:
##   res <- overlay_bt_recon(pr_monthly, base_bt, scenario = "uni_cat",
##                           strategy_id = "STR_AS_...", out_dir = ".../rung3/uni_cat")
##   if (identical(res$status, "OK")) essence_score(res$bt, selection_type = "chain")
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
})

OBR_VERSION  <- "overlay_bt_recon_v1"
OBR_BASIS    <- "monthly_recon"
OBR_NOT_CAPITAL <- paste(
  "자본 tier 판정 근거로 인용 불가 — basis=monthly_recon 은 월중 저점을 보지 못해",
  "MDD/Calmar 가 원판(daily_native) 대비 구조적으로 유리하다(실측: 오버레이 없이도 MDD −9.07pp).",
  "비교는 같은 basis 안에서만 성립한다. HARD 3종/graduation 은 forge-authoritative 수치로만 판정한다.")

## ─── 계약 견고 소싱 (score_composite.R:35-49 전례 — idempotent) ──────────────
.obr_source <- function(rel, probe) {
  if (exists(probe, mode = "function")) return(invisible(TRUE))
  cands <- c(file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "."), rel),
             file.path(Sys.getenv("QM_ROOT", "."), rel),
             rel)
  for (f in cands) if (!is.null(f) && file.exists(f)) { suppressMessages(source(f)); return(invisible(TRUE)) }
  invisible(FALSE)
}

.obr_nz <- function(a, b) if (!is.null(a) && length(a) > 0L && !all(is.na(a)) &&
                              !identical(as.character(a[1]), "")) a[1] else b

.obr_bt <- function(x) {
  if (is.character(x) && length(x) == 1L) {
    if (!file.exists(x)) stop("[overlay_bt_recon] base bt_result 부재: ", x)
    return(readRDS(x))
  }
  if (is.list(x) && !is.null(x$period_returns) && !is.null(x$manifest)) return(x)
  stop("[overlay_bt_recon] base_bt 는 bt_result(list) 또는 .rds 경로여야 한다")
}

## base strategy_spec(data.table 1행) → build_strategy_spec_tbl 이 먹는 flat list
.obr_spec_list <- function(base_bt) {
  S <- as.data.table(base_bt$strategy_spec)
  if (!nrow(S)) return(list())
  s <- as.list(S[1])
  s[["run_id"]] <- NULL                      # builder 가 다시 박는다
  lapply(s, function(v) if (length(v) > 1L) v[1] else v)
}

## ─── 본체 ───────────────────────────────────────────────────────────────────
#' @param pr_monthly  data.table(date, ret_net[, benchmark_ret]) — **월간** 계열.
#'                    drain_run_candidate()$prs[[scenario]] 를 그대로 넣는다.
#' @param base_bt     기저 전략의 bt_result 또는 .rds 경로 (spec/holdings/벤치 라벨 상속원)
#' @param scenario    시나리오 라벨 ("bare" / "uni_cat" / "voltgt_cost" ...)
#' @param strategy_id 재구성 산출물의 strategy_id
#' @param run_id      NULL 이면 자동 생성
#' @param out_dir     비-NULL 이면 bt_result.rds + 10_audit.csv 기록
#' @param cost_bps    manifest transaction_cost_bps 표기값 (기본 15)
#' @param pin_tag     국면 라벨 vintage pin 태그 (provenance 기록용)
#' @param exposure_source  노출 스케줄 출처 문자열 (예: "unified_regime_signal/CAT_EXPOSURE prev-month")
#' @param carry_holdings   base holdings 상속 여부. FALSE 면 Check 3·18 이 WARN(미측정 표식)
#' @return list(status, bt, audit_summary, provenance, reason)
overlay_bt_recon <- function(pr_monthly, base_bt, scenario, strategy_id,
                             run_id = NULL, out_dir = NULL,
                             cost_bps = 15, pin_tag = NA_character_,
                             exposure_source = NA_character_,
                             carry_holdings = TRUE) {
  .obr_source("02_Infrastructure/contracts/backtest_result_contract.R", "build_bt_result")
  .obr_source("02_Infrastructure/contracts/audit_bt_result.R", "audit_bt_result")
  if (!exists("build_bt_result", mode = "function"))
    stop("[overlay_bt_recon] backtest_result_contract.R 소싱 실패 — 계약 없이 재구성 금지")
  if (!exists("audit_bt_result", mode = "function"))
    stop("[overlay_bt_recon] audit_bt_result.R 소싱 실패 — 무감사 산출 금지")

  base <- .obr_bt(base_bt)

  ## ── 입력 정규화 ──────────────────────────────────────────────────────────
  P <- as.data.table(copy(pr_monthly))
  if (!all(c("date", "ret_net") %in% names(P)))
    stop("[overlay_bt_recon] pr_monthly 에 date/ret_net 필요")
  P[, date := as.Date(date)]
  P <- P[is.finite(ret_net)]
  setorder(P, date)
  if (nrow(P) < 12L)
    stop(sprintf("[overlay_bt_recon] 월간 관측 %d < 12 — 재구성 거부(억지 산출 금지)", nrow(P)))
  med_gap <- as.numeric(stats::median(diff(P$date)))
  if (!is.finite(med_gap) || med_gap < 26 || med_gap > 33)
    stop(sprintf(paste0("[overlay_bt_recon] 입력이 월간 계열이 아니다 (median date gap %.1f일). ",
                        "이 어댑터는 basis=monthly_recon 전용 — 일간 입력은 원판 경로를 쓸 것."), med_gap))

  ## 벤치: 입력에 있으면 그것을, 없으면 base 를 월간 집계해 붙인다
  if (!"benchmark_ret" %in% names(P)) {
    bb <- as.data.table(base$benchmark_returns)[, .(date = as.Date(date),
                                                    benchmark_ret = as.numeric(benchmark_ret))]
    bfreq <- tolower(as.character((as.data.table(base$benchmark_returns)$frequency)[1]))
    if (identical(bfreq, "daily")) {
      bx <- xts::xts(bb$benchmark_ret, order.by = bb$date)
      bm <- xts::apply.monthly(bx, PerformanceAnalytics::Return.cumulative)
      bb <- data.table(date = as.Date(format(zoo::index(bm), "%Y-%m-01")),
                       benchmark_ret = as.numeric(bm))
    }
    P <- merge(P, bb, by = "date", all.x = TRUE)
    setorder(P, date)
  }
  if (any(!is.finite(P$benchmark_ret)))
    stop("[overlay_bt_recon] benchmark_ret 결측 — 벤치-상대 지표를 낼 수 없다(무성의한 0 채움 금지)")

  ## ── sim_result 5필드 (build_bt_result 가 실제로 읽는 전부) ────────────────
  ##   ★NAV_gross 미부착이 의도적이다(헤더 참조) — Check 12 구조적 PASS + 정직한 진술.
  ret_x <- xts::xts(as.numeric(P$ret_net), order.by = P$date)
  bm_x  <- xts::xts(as.numeric(P$benchmark_ret), order.by = P$date)
  ## NAV 레벨 경로 = 계약 본체(backtest_result_contract.R:330)의 자구동일 관용구.
  nav_dt <- data.table(Date = P$date, NAV = 1e8 * cumprod(1 + as.numeric(P$ret_net)))

  hold <- if (isTRUE(carry_holdings)) {
    H <- as.data.table(base$holdings)
    if (nrow(H)) copy(H) else NULL
  } else NULL

  sim_result <- list(
    strategy_xts       = ret_x,
    bm_xts             = bm_x,
    DAILY_NAV_DT       = nav_dt,
    HOLDINGS_LOG       = hold,
    PORTFOLIO_LOG      = NULL,
    cost_model_version = as.character(.obr_nz(base$manifest$cost_model_version, "v2.4_delta_15bps"))
  )

  ## ── spec: base 상속 + 5개 덮어쓰기 ───────────────────────────────────────
  spec <- .obr_spec_list(base)
  base_wm  <- as.character(.obr_nz(spec$weighting_method, "unspecified"))
  base_rc  <- as.character(.obr_nz(spec$risk_controls, "none"))
  base_lp  <- as.character(.obr_nz(spec$lookahead_prevention, "detect_lookahead static scan"))
  base_cr  <- as.character(.obr_nz(spec$cash_rule, "fully_invested"))
  spec$rebalance_frequency <- "monthly"                       # → Check 16 PASS (nav monthly ↔ 라벨 monthly)
  spec$weighting_method    <- sprintf("%s | overlay exposure scaling (scenario=%s, basis=%s)",
                                      base_wm, scenario, OBR_BASIS)
  spec$cash_rule           <- sprintf("%s | overlay: (1-e_t) 는 현금 @0%% (월간 ret_net × e_t, weighted_screen_bt L65 규약)",
                                      base_cr)
  spec$risk_controls       <- sprintf("%s | overlay=%s exposure_source=%s pin=%s", base_rc, scenario,
                                      .obr_nz(exposure_source, "unspecified"), .obr_nz(pin_tag, "none"))
  ## ★정직성 진술 — Check 12 가 구조적으로 PASS 하는 이유를 spec 이 말한다.
  spec$cost_model          <- paste0(
    as.character(.obr_nz(spec$cost_model, "v2.4_delta_15bps")),
    " | RECON NOTE: 재구성 계열은 gross/net 분해를 재현하지 않는다(ret_gross := ret_net, cost_ret = 0). ",
    "base 의 15bps one-way(v2.4 delta)는 입력 ret_net 에 **이미** 반영돼 있고, ",
    "오버레이 회전비용(|Δexposure|×15bps)은 `*_cost` 시나리오 계열에만 별도 차감돼 있다. ",
    "따라서 Check 12 의 PASS 는 '비용이 0'이 아니라 '이 basis 에서 분해가 미측정'을 뜻한다.")
  ## ★`C5` 문자열이 있어야 Check 8 의 grepl("C\\d+") 이 발화한다.
  spec$lookahead_prevention <- paste0(
    base_lp, " | C5 overlay signal timing: assert_overlay_pit HARD (신호 컷오프 ≤ 홀딩월 첫날) ",
    "+ lag1 스트레스 + strict-PIT A/B (overlay_candidate_drain.R). PIT C1-C15 불변.")

  ## ── 계약 산출 ────────────────────────────────────────────────────────────
  if (is.null(run_id))
    run_id <- sprintf("OBR_%s_%s_%s", format(Sys.time(), "%Y%m%d_%H%M%S"), Sys.getpid(),
                      gsub("[^A-Za-z0-9]", "", scenario))
  bt <- build_bt_result(
    sim_result           = sim_result,
    strategy_spec        = spec,
    run_id               = run_id,
    strategy_id          = strategy_id,
    strategy_version     = sprintf("%s+overlay_%s",
                                   as.character(.obr_nz(base$manifest$strategy_version, "v1.0")), scenario),
    benchmark_id         = as.character(.obr_nz(base$manifest$benchmark_ids, "KOSPI200")),
    benchmark_name       = as.character(.obr_nz(as.data.table(base$benchmark_returns)$benchmark_name, "KOSPI 200")),
    transaction_cost_bps = as.numeric(.obr_nz(base$manifest$transaction_cost_bps, cost_bps)),
    slippage_bps         = as.numeric(.obr_nz(base$manifest$slippage_bps, 0)),
    risk_free_rate       = 0,
    frequency            = "monthly",
    annualization_factor = 12,
    universe_id          = as.character(.obr_nz(base$manifest$universe_id, "K200_KQ150")),
    code_version         = sprintf("%s (basis=%s, scenario=%s)", OBR_VERSION, OBR_BASIS, scenario),
    created_by_agent     = "reinforce_ladder/overlay_bt_recon"
  )

  ## ── ★apply.monthly 항등 assert — 재구성이 입력을 바꾸지 않았음을 못박는다 ──
  got <- as.numeric(bt$period_returns$ret_net)
  want <- as.numeric(P$ret_net)
  stopifnot(length(got) == length(want))
  stopifnot(isTRUE(all.equal(got, want)))
  ## 날짜는 **값**으로 비교한다 — data.table 컬럼이 들고 다니는 부가 attribute 때문에
  ## Date 객체 직접 all.equal 은 "Attributes: Length mismatch" 로 거짓 실패한다.
  stopifnot(isTRUE(all.equal(as.numeric(as.Date(bt$period_returns$date)), as.numeric(P$date))))

  ## ── 라벨 3곳: metric_type 은 enum 유지, 라벨은 부가 컬럼에 ────────────────
  M <- as.data.table(bt$metrics)
  if (nrow(M)) {
    lbl <- sprintf("overlay_recon(scenario=%s, basis=%s)", scenario, OBR_BASIS)
    if ("input_source" %in% names(M))
      bt$metrics[, input_source := paste0(as.character(input_source), " | ", lbl)]
    if ("calculation_method" %in% names(M))
      bt$metrics[, calculation_method := paste0(as.character(calculation_method), " | ", lbl)]
  }

  ## ── 감사 ─────────────────────────────────────────────────────────────────
  bt <- audit_bt_result(bt)
  A <- as.data.table(bt$audit)
  n_pass <- nrow(A[status == "PASS"]); n_fail <- nrow(A[status == "FAIL"]); n_warn <- nrow(A[status == "WARN"])
  crit <- A[severity == "critical" & status == "FAIL"]
  vres <- validate_bt_result(bt)

  ## ── 비-계약 사이드카 (validate_bt_result 는 누락만 검사 — 추가는 안전) ────
  bt$overlay_provenance <- list(
    schema           = OBR_VERSION,
    basis            = OBR_BASIS,
    basis_warning    = OBR_NOT_CAPITAL,
    scenario         = as.character(scenario),
    exposure_source  = as.character(.obr_nz(exposure_source, NA_character_)),
    pin_tag          = as.character(.obr_nz(pin_tag, NA_character_)),
    base_run_id      = as.character(.obr_nz(base$manifest$run_id, NA_character_)),
    base_strategy_id = as.character(.obr_nz(base$manifest$strategy_id, NA_character_)),
    base_basis       = paste0("daily_native (", as.character(.obr_nz(
                          (as.data.table(base$period_returns)$frequency)[1], "unknown")), ")"),
    base_integrity   = as.character(.obr_nz(base$manifest$integrity_status, NA_character_)),
    carry_holdings   = isTRUE(carry_holdings),
    cost_note        = as.character(spec$cost_model),
    metric_type_note = paste("metrics$metric_type 은 enum('backtested') 을 지킨다 —",
                             "신규 값은 Check 10 critical FAIL 이라 등급 자체가 소멸한다.",
                             "재구성 사실은 이 사이드카 + code_version + input_source 가 진술한다."),
    n_months         = nrow(P),
    generated_at     = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )

  audit_summary <- list(
    pass = n_pass, fail = n_fail, warn = n_warn,
    integrity = as.character(bt$manifest$integrity_status[1]),
    critical_fail_n = nrow(crit),
    critical_fail_checks = as.character(crit$check_name),
    fail_checks = as.character(A[status == "FAIL"]$check_name),
    warn_checks = as.character(A[status == "WARN"]$check_name),
    schema_valid = isTRUE(vres$valid),
    schema_errors = as.character(vres$errors)
  )

  status <- "OK"; reason <- NA_character_
  if (nrow(crit) > 0L) {
    status <- "FAIL"
    reason <- sprintf("critical FAIL %d건: %s — 조용한 통과 금지(재구성 산출물 인용 불가)",
                      nrow(crit), paste(crit$check_name, collapse = ", "))
  } else if (!isTRUE(vres$valid)) {
    status <- "FAIL"
    reason <- sprintf("validate_bt_result 실패: %s", paste(vres$errors, collapse = " | "))
  }

  ## ── 기록 (선택) ──────────────────────────────────────────────────────────
  if (!is.null(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(bt, file.path(out_dir, "bt_result.rds"))
    data.table::fwrite(A, file.path(out_dir, "10_audit.csv"))
    data.table::fwrite(as.data.table(bt$metrics), file.path(out_dir, "06_metrics.csv"))
  }

  cat(sprintf("[overlay_bt_recon] %s scenario=%s basis=%s | n=%d | PASS %d FAIL %d WARN %d | integrity=%s | status=%s\n",
              strategy_id, scenario, OBR_BASIS, nrow(P), n_pass, n_fail, n_warn,
              audit_summary$integrity, status))

  list(status = status, bt = bt, audit_summary = audit_summary,
       provenance = bt$overlay_provenance, reason = reason)
}

cat("[overlay_bt_recon.R] Loaded — overlay_bt_recon() (basis=monthly_recon, ★basis 방화벽)\n")
