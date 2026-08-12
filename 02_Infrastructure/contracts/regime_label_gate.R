## regime_label_gate.R — 국면 라벨 자격 관문 **배선 어댑터** (FQ-119 WIRE)
##
## 계약 본체 `label_eligibility_gate.R` 는 **고정**이다(수정 금지). 본 파일은 그 계약을
## 실제 소비 지점에 꽂기 위한 어댑터만 담는다: 정본 패널에서 (라벨, 사건) 쌍을 만들고,
## 호출부가 warn/block 중 무엇으로 반응할지를 한 곳에서 정한다.
##
## ★왜 어댑터가 따로 필요한가 — 세 가지 실측 이유:
##  ① **자격은 (라벨, 사건정의) 쌍에 붙는다**(2026-08-08 확립). 사건 정의를 호출부마다
##     제각각 쓰면 같은 라벨이 사이트마다 다른 판정을 받는다. 정의를 여기서 **고정**한다.
##  ② **PIT**: 라벨은 홀딩월이 시작되기 **전**에 알 수 있던 값만 써야 한다(pit.md C5).
##     각 사이트가 직접 만들면 동월 look-ahead 재발 경로다(실사고: BearProb 오버레이).
##  ③ **`%||%` 오염 차단**: 계약 본체는 최상위에서 `%||%` 를 재정의한다(`if (is.null(a)) b else a`).
##     이를 호출부에 그대로 source 하면 호출부의 더 엄격한 `%||%`(length 0 / all-NA 처리)를
##     덮어써 **무관한 코드의 동작이 조용히 바뀐다**. 그래서 본 어댑터는 계약을 **격리 환경**
##     (`.rlg_env`)에 sys.source 하고 그 환경에서만 호출한다. 전역은 건드리지 않는다.
##
## 사용:
##   source("02_Infrastructure/contracts/regime_label_gate.R")
##   g <- regime_label_gate(asof = as.Date("2026-08-07"))
##   rlg_enforce(g, site = "regime_module_admission")   # 기본 warn, 환경변수로 block 승격
##
## 모드 해석 우선순위: 인자 mode > 환경변수 QVEST_LABEL_GATE_MODE > "warn"
##   "warn"  = 경고만(판정은 산출물에 기록)  "block" = 미달 시 stop  "off" = 판정만·무반응
##   ★"off" 도 판정은 계산·기록한다 — 침묵이 합격으로 읽히지 않게.

suppressPackageStartupMessages({ library(data.table); library(arrow) })

## 내부 전용 null-coalesce. ★`%||%` 를 쓰지 않는다 — 호출부마다 `%||%` 의미가 다르고
## (어떤 판본은 length 0/all-NA 까지 흡수) 그 차이가 조용히 판정을 바꾼다.
.rlg_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.rlg_root <- function(proj = NULL) {
  if (!is.null(proj) && nzchar(proj)) return(proj)
  if (exists("PROJ", inherits = TRUE)) {
    p <- get("PROJ", inherits = TRUE)
    if (is.character(p) && length(p) == 1L && nzchar(p)) return(p)
  }
  p <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = "")
  if (!nzchar(p) || !file.exists(file.path(p, ".cache"))) p <- Sys.getenv("QM_ROOT", unset = "")
  if (!nzchar(p)) p <- getwd()
  p
}

## ── 계약 본체 격리 로드 (전역 %||% 보호) ───────────────────────────────────
.rlg_env <- new.env(parent = globalenv())
.rlg_load_contract <- function(proj = NULL) {
  if (exists("label_eligibility", envir = .rlg_env, inherits = FALSE)) return(invisible(TRUE))
  f <- file.path(.rlg_root(proj), "02_Infrastructure/contracts/label_eligibility_gate.R")
  if (!file.exists(f)) stop("[rlg] 계약 본체 부재: ", f)
  sys.source(f, envir = .rlg_env)
  invisible(TRUE)
}

## ── 고정 상수 (sweep 금지) ─────────────────────────────────────────────────
## 사건 정의 문턱은 **탐색으로 고르지 않았다**. 2026-08-08 실측에서 라벨의 판별력이
## 사건 심도에 단조 증가함이 확립됐고(<0% 무판별 → <-5% → <-10% 순 증가), 방어 소비면의
## 표적은 "MDD 를 만드는 큰 하락"이므로 **-5% 를 1급 판정축**으로 못박고 -10% 는 진단 병기.
RLG_EVENT_THR      <- -0.05
RLG_EVENT_THR_DIAG <- -0.10
## 확장(공격) 축 진단 — RCMA 는 방어/공격 양방향 admission 이므로 반대 축도 재서 병기한다.
RLG_EVENT_THR_UP   <-  0.05
RLG_STRESS_LABELS  <- c("CRISIS", "RISK_OFF", "CAUTION")
RLG_EXPANSION_LABELS <- c("RISK_ON", "NEUTRAL")
## ★어휘는 라벨 원천마다 다르다 — 배포 경로(alpha_scores::regime_state)는 BULL/NORMAL/CAUTION/CRISIS,
##   unified 계열은 RISK_ON/NEUTRAL/CAUTION/CRISIS/RISK_OFF. 한쪽 어휘를 다른 쪽에 쓰면 라벨이
##   상수(n_on=0)가 되어 UNMEASURABLE_DEGENERATE 로 떨어진다 — 조용한 통과는 아니지만 판정도 못 한다.
.rlg_default_labels <- function(label_basis) {
  if (identical(label_basis, "alpha_scores_regime_state"))
    list(stress = c("CRISIS", "CAUTION"), expansion = c("BULL", "NORMAL"))
  else list(stress = RLG_STRESS_LABELS, expansion = RLG_EXPANSION_LABELS)
}

.rlg_cache <- new.env(parent = emptyenv())

#' 정본 국면 라벨 × 벤치 월수익 패널 (PIT: 홀딩월 시작 전 라벨만)
#'
#' 라벨 정본 = `.cache/unified_regime_signal_daily.parquet::Category`
#'   (RCMA 가 쓰는 바로 그 파일 — 소비 지점과 **같은 원천**이어야 관문이 의미가 있다).
#' 라벨 lag = RCMA 와 동일한 t-1 일간 shift. 그 위에서 **각 월의 첫 거래일 라벨**만 취한다
#'   = 홀딩월이 시작되기 전에 알 수 있던 값(pit.md C5 clean 컷오프).
#' 사건 = 그 홀딩월의 벤치 실현 수익. `prod(1+r)-1` 은 성과 주장이 아니라
#'   **사건 정의(diagnostic)** 다 — metric_type = "diagnostic_event_definition".
#'
#' @param label_basis 소비 지점이 **실제로 쓰는 라벨 구성**을 지정한다. ★관문이 사이트가 쓰는
#'   것과 *다른* 라벨을 재면 그건 정체 검사가 아니라 대용품 검사다(이 저장소가 반복 수리한 계통).
#'   - "daily_t1_monthstart" (기본, RCMA 정합): 일간 정본 `unified_regime_signal_daily` 에
#'     t-1 shift 후 **홀딩월 첫 거래일** 라벨.
#'   - "monthly_prev" (auto_regime_overlay_ab 정합): 월간 정본 `unified_regime_signal` 의
#'     **직전 월** Category (해당 스크립트의 `.prev_month_ym` 규약).
#'   - "monthly_same" (portfolio_governor 정합): 월간 정본의 **동월** Category — lag 없음
#'     (`get_regime_at_date` = "date 이하 가장 가까운 월" 조회).
#'   - "alpha_scores_regime_state" (배포 경로 정합): `alpha_scores.parquet::regime_state`.
#'     ★배포 β_R05 가 읽는 라벨은 unified 계열이 **아니다** — 어휘부터 다르다
#'     (BULL/NORMAL/CAUTION/CRISIS vs RISK_ON/NEUTRAL/CAUTION/CRISIS/RISK_OFF).
#'     이 축을 unified 로 재면 배포 라벨을 잰 게 아니라 남의 라벨을 잰 것이다.
#' @return data.table(ym, regime, bm_m, n_days) — 실패 시 NULL (빈 결과를 합격으로 쓰지 말 것)
regime_label_monthly_panel <- function(proj = NULL, refresh = FALSE,
                                       label_basis = c("daily_t1_monthstart", "monthly_prev",
                                                       "monthly_same", "alpha_scores_regime_state")) {
  label_basis <- match.arg(label_basis)
  root <- .rlg_root(proj)
  key <- paste0("panel:", label_basis, ":", root)
  if (!refresh && !is.null(.rlg_cache[[key]])) return(.rlg_cache[[key]])

  f_bm  <- file.path(root, ".cache/benchmark.parquet")
  f_lab <- switch(label_basis,
    monthly_prev              = file.path(root, ".cache/unified_regime_signal.parquet"),
    monthly_same              = file.path(root, ".cache/unified_regime_signal.parquet"),
    alpha_scores_regime_state = file.path(root, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"),
    file.path(root, ".cache/unified_regime_signal_daily.parquet"))
  if (!file.exists(f_lab) || !file.exists(f_bm)) return(NULL)

  RG <- tryCatch(as.data.table(read_parquet(f_lab)), error = function(e) NULL)
  B  <- tryCatch(as.data.table(read_parquet(f_bm)),  error = function(e) NULL)
  if (is.null(RG) || is.null(B)) return(NULL)
  lab_col <- if (identical(label_basis, "alpha_scores_regime_state")) "regime_state" else "Category"
  if (!(lab_col %in% names(RG))) return(NULL)

  if (identical(label_basis, "alpha_scores_regime_state")) {
    ## 배포 경로 규약: sig_date(월초) 라벨이 **그 달**의 β 를 정한다 → 같은 ym 과 짝짓는다.
    ## ★이 축은 패널 자신의 PIT 성질을 그대로 물려받는다(관문은 라벨을 *소비되는 형태 그대로*
    ##   재는 것이 목적이며, 패널 vintage 문제는 별개 축이다 — measurement-graduation §7b).
    RG <- RG[!is.na(get(lab_col)), .(ym = format(as.Date(Date), "%Y%m"),
                                     regime = as.character(get(lab_col)))]
    lab_m <- unique(RG, by = "ym")
  } else if (identical(label_basis, "monthly_same")) {
    ## governor(get_regime_at_date) 규약: "date 이하 가장 가까운 월"의 라벨 = **동월** 라벨.
    ## ★lag 이 없다는 사실 자체를 관문이 드러내야 한다 — 여기서 몰래 lag 을 넣으면
    ##   governor 가 쓰는 것보다 보수적인 라벨을 재게 되어 판정이 실제보다 낙관적이 된다.
    RG <- RG[!is.na(Category), .(ym = format(as.Date(Date), "%Y%m"),
                                 regime = as.character(Category))]
    lab_m <- unique(RG, by = "ym")
  } else if (identical(label_basis, "monthly_prev")) {
    ## 월간 정본: 라벨은 신호 월(ym_sig), 소비되는 홀딩월은 그 **다음 달**.
    ## ★YM 컬럼을 신뢰하지 않고 Date 에서 재생성한다(원장 오기재 전례).
    RG <- RG[!is.na(Category), .(ym_sig = format(as.Date(Date), "%Y%m"),
                                 Category = as.character(Category))]
    setorder(RG, ym_sig)
    RG[, ym := format(as.Date(paste0(ym_sig, "01"), "%Y%m%d") + 32L, "%Y%m")]  # 직전월 신호 → 홀딩월
    lab_m <- unique(RG[, .(ym, regime = Category)], by = "ym")
  } else {
    RG <- RG[!is.na(Category), .(Date = as.Date(Date), Category = as.character(Category))]
    setorder(RG, Date)
    RG[, regime := shift(Category, 1L)]                  # ★ RCMA 와 동일한 t-1 lag
    RG <- RG[!is.na(regime)]
    RG[, ym := format(Date, "%Y%m")]
    lab_m <- RG[order(Date), .SD[1L], by = ym][, .(ym, regime)] # 월 첫 거래일 = 홀딩월 시작 전
  }

  setnames(B, tolower(names(B)))
  if (!all(c("date", "bm_ret") %in% names(B))) return(NULL)
  B <- B[, .(Date = as.Date(date), bm = as.numeric(bm_ret))][!is.na(bm)]
  setorder(B, Date); B[, ym := format(Date, "%Y%m")]
  ret_m <- B[, .(bm_m = prod(1 + bm) - 1, n_days = .N), by = ym]   # diagnostic_event_definition

  M <- merge(lab_m, ret_m, by = "ym")[n_days >= 10L]      # 반쪽 월 제외(사건 정의 불안정)
  setorder(M, ym)
  if (nrow(M) == 0L) return(NULL)
  .rlg_cache[[key]] <- M
  M
}

#' 국면 라벨 자격 판정 (소비 직전 호출)
#'
#' @param asof  Date/문자열. 지정 시 **asof 이하 월만** 사용(walk-forward PIT — 관문 자신이
#'              미래를 보면 그 관문이 lookahead 원천이 된다).
#' @return list — 계약 반환값 + (site 메타 · 진단축). 패널 부재 시 verdict="UNAVAILABLE_PANEL"
#'         (★eligible = NA. 합격 아님 — 계측 불가는 통과가 아니다)
regime_label_gate <- function(asof = NULL,
                              stress_labels   = NULL,
                              event_threshold = RLG_EVENT_THR,
                              label_basis     = "daily_t1_monthstart",
                              proj = NULL) {
  .rlg_load_contract(proj)
  le <- get("label_eligibility", envir = .rlg_env)
  .def <- .rlg_default_labels(label_basis)
  stress_labels <- .rlg_or(stress_labels, .def$stress)

  M <- regime_label_monthly_panel(proj, label_basis = label_basis)
  if (is.null(M))
    return(list(eligible = NA, verdict = "UNAVAILABLE_PANEL",
                reason = "라벨/벤치 정본 패널을 읽지 못함 — 자격 판정 불가(합격 아님)",
                recall = NA_real_, base_rate = NA_real_, lift = NA_real_, fisher_p = NA_real_,
                n = 0L, n_on = 0L, n_event = 0L,
                asof = as.character(.rlg_or(asof, NA)), event_definition = NA_character_))

  if (!is.null(asof) && !all(is.na(asof))) {
    cut_ym <- format(as.Date(asof), "%Y%m")
    M <- M[ym <= cut_ym]
  }
  if (nrow(M) == 0L)
    return(list(eligible = NA, verdict = "UNMEASURABLE_NO_DATA",
                reason = sprintf("asof=%s 이하 월 관측 0 — 자격 판정 불가(합격 아님)", as.character(asof)),
                recall = NA_real_, base_rate = NA_real_, lift = NA_real_, fisher_p = NA_real_,
                n = 0L, n_on = 0L, n_event = 0L,
                asof = as.character(.rlg_or(asof, NA)), event_definition = NA_character_))

  on <- M$regime %in% stress_labels
  g  <- le(on, M$bm_m < event_threshold)

  ## 진단 병기 — 판정축(-5%)만으로는 "심도에 따라 뒤집히는" 성질이 안 보인다.
  g_diag <- le(on, M$bm_m < RLG_EVENT_THR_DIAG)
  g_up   <- le(M$regime %in% .def$expansion, M$bm_m > RLG_EVENT_THR_UP)

  ## lag1 스트레스 (pit.md C5 의무). 라벨을 한 달 더 밀었을 때 판별력이 얼마나 남는가.
  ##   ★붕괴 = 동월 누출 **의심 신호**이지 확정이 아니다 — 빠르게 변하는 라벨도 지연 시 감쇠한다.
  ##   판별은 같은 시험을 받은 **다른 라벨과의 대비**로 한다(2026-08-08 실측:
  ##   t-1 lag 로 만든 unified 라벨 보존율 0.85~0.89 vs 배포 alpha_scores 라벨 0.26).
  ##   패널이 사실상 연속월이라는 가정 위의 shift 다(관측 커버리지 ≈ 전월, 결측월은 NA 로 제외).
  on1 <- shift(on, 1L)
  ok1 <- !is.na(on1)
  g_l1 <- if (sum(ok1) > 0L) le(on1[ok1], (M$bm_m < event_threshold)[ok1]) else list(lift = NA_real_, fisher_p = NA_real_, verdict = "UNMEASURABLE_NO_DATA")
  ret1 <- if (is.finite(g_l1$lift) && is.finite(g$lift) && g$lift > 0) g_l1$lift / g$lift else NA_real_

  c(g, list(
    asof             = as.character(.rlg_or(asof, max(M$ym))),
    ym_min           = min(M$ym), ym_max = max(M$ym),
    event_definition = sprintf("benchmark monthly return < %.2f%%", event_threshold * 100),
    label_basis      = label_basis,
    label_definition = sprintf("regime[%s] in {%s}", label_basis, paste(stress_labels, collapse = ",")),
    label_source     = switch(label_basis,
      monthly_prev              = ".cache/unified_regime_signal.parquet::Category (직전월 신호 → 홀딩월)",
      monthly_same              = ".cache/unified_regime_signal.parquet::Category (동월 라벨 — lag 없음, get_regime_at_date 규약)",
      alpha_scores_regime_state = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet::regime_state (sig_date=홀딩월초)",
      ".cache/unified_regime_signal_daily.parquet::Category (t-1 lag, month-start)"),
    metric_type      = "diagnostic_event_definition",
    diag_deep        = list(threshold = RLG_EVENT_THR_DIAG, lift = g_diag$lift,
                            fisher_p = g_diag$fisher_p, verdict = g_diag$verdict),
    diag_expansion   = list(threshold = RLG_EVENT_THR_UP, lift = g_up$lift,
                            fisher_p = g_up$fisher_p, verdict = g_up$verdict),
    diag_lag1        = list(lift = g_l1$lift, fisher_p = g_l1$fisher_p, verdict = g_l1$verdict,
                            retention = ret1,
                            note = "라벨 1개월 추가 지연 시 판별력 보존율. 낮으면 동월 누출 의심(확정 아님) — 다른 라벨과 대비해 읽을 것")))
}

#' 호출부 반응 — warn(기본) / block / off
#'
#' ★ELIGIBLE 이 아닌 모든 상태(INELIGIBLE·UNMEASURABLE_*·UNAVAILABLE_*)를 동일하게 다룬다.
#'   "재지 못했다"를 "통과했다"로 접는 것이 이 저장소가 반복 수리한 결함 계통이다.
rlg_enforce <- function(g, site, mode = NULL) {
  m <- .rlg_or(mode, Sys.getenv("QVEST_LABEL_GATE_MODE", unset = "warn"))
  m <- tolower(as.character(m)[1]); if (!m %in% c("warn", "block", "off")) m <- "warn"
  ok <- isTRUE(g$eligible)
  msg <- sprintf("[label_gate/%s] %s | verdict=%s | %s", site,
                 .rlg_or(g$event_definition, "event=?"), .rlg_or(g$verdict, "?"), .rlg_or(g$reason, ""))
  if (ok) { message(msg); return(invisible(list(gate = g, mode = m, action = "pass"))) }
  if (identical(m, "block"))
    stop(sprintf("%s\n  ★소비 측정 착수 금지 — 판별력 없는 라벨은 중립이 아니라 발화 월수에 비례해 유해하다(WT-019 paired -3.77).\n  (해제: QVEST_LABEL_GATE_MODE=warn)", msg), call. = FALSE)
  if (identical(m, "off")) return(invisible(list(gate = g, mode = m, action = "recorded_only")))
  warning(msg, call. = FALSE)
  invisible(list(gate = g, mode = m, action = "warned"))
}

#' 산출물 기록용 축약 (JSON 직렬화 안전)
rlg_summary <- function(g) {
  ## ★fisher_p 를 문자열로도 싣는다. 소비자 다수가 `jsonlite::write_json` 기본값(digits=4)으로
  ##   기록하는데, 그러면 p=1.2e-05 가 `0` 으로 납작해져 **정확히 0** 처럼 읽힌다(조용한 훼손).
  ##   소비자의 직렬화 설정을 바꾸지 않고 정밀도를 보존하는 쪽을 택했다.
  list(eligible = g$eligible, verdict = g$verdict,
       recall = g$recall, base_rate = g$base_rate, lift = g$lift, fisher_p = g$fisher_p,
       fisher_p_str = if (is.null(g$fisher_p) || !is.finite(g$fisher_p)) NA_character_
                      else format(g$fisher_p, scientific = TRUE, digits = 4),
       n_months = g$n, n_label_on = g$n_on, n_event = g$n_event,
       asof = g$asof, event_definition = g$event_definition,
       label_basis = g$label_basis,
       label_definition = g$label_definition, label_source = g$label_source,
       metric_type = g$metric_type,
       diag_deep = g$diag_deep, diag_expansion = g$diag_expansion, diag_lag1 = g$diag_lag1,
       contract = "02_Infrastructure/contracts/label_eligibility_gate.R (FQ-119)")
}

