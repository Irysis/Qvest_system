#!/usr/bin/env Rscript
#==============================================================================
# forward_parity_check.R — [P3 초안] 배포 비중 ↔ 북 기록 엔진 parity 게이트
#
# 목적: forward 생성기가 산출한 실배포 비중이, *선언된 가중 규약*으로 캐리어 엔진을
#   replay 한 결과와 일치하는지 검사. 불일치 = 배포와 북이 다른 전략 (2026-08-08 실측 결함).
#
# ★규약은 하드코딩이 아니라 declared_convention 인자 — 정렬 방향이 어느 쪽으로 결정되든
#   같은 게이트가 작동한다(결정-독립). 기본값 = canonical(strategy_tilt_weights.R 정본).
#
# 반환: list(status = PASS|FAIL|ERROR, divergence, ...). status!=PASS → exit 1 (fail-closed).
# ★빈 입력·파일 부재는 PASS 가 아니라 ERROR (— "빈 결과 = 합격" 계통 차단).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
options(scipen = 999)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))

FP_TOL <- 1e-8          # 생성기가 같은 엔진을 쓰면 기계 정밀도로 일치해야 함
FP_TOPN <- 20L; FP_MINN <- 15L; FP_LIQ <- 2e8; FP_LAM <- 1.5; FP_UB <- 0.20; FP_UBCR <- 0.10

# 선언 규약 2종 — 새 규약 채택 시 여기 추가 (호출부는 문자열만 바꾸면 됨)
.fp_weights <- function(alpha, w_prev, regime, convention, phi = 3.0) {
  ub <- if (identical(regime, "CRISIS") && convention == "canonical") min(FP_UB, FP_UBCR) else FP_UB
  if (convention == "canonical") {
    w <- linear_tilt_to_penalty_qd(alpha, lambda = FP_LAM, w_prev = w_prev, phi = phi, lb = 0, ub = ub)
    names(w) <- names(alpha)
    normalize_long_only(w, lb = 0, ub = ub, target_sum = 1)
  } else if (convention == "zlinear") {
    z <- (alpha - mean(alpha)) / pmax(sd(alpha), 1e-10)
    w <- pmax(0, 1/length(alpha) + FP_LAM * z / length(alpha))
    if (sum(w) > 0) w <- w / sum(w)
    w[w > ub] <- ub; for (i in 1:50) { s <- sum(w); if (abs(s-1) < 1e-8 || s == 0) break; w <- w*(1/s); w[w > ub] <- ub }
    names(w) <- names(alpha); w
  } else stop(sprintf("[parity] 미지원 규약: %s", convention))
}

#' @param deployed_csv  실배포 비중 CSV (rank,Ticker,...,Weight — CASH 행 포함 가능)
#' @param as_of         결정월 (Date/문자)
#' @param carrier_parquet w_prev 체인 소스 (북 기록 엔진 산출)
#' @param declared_convention "canonical" | "zlinear"
forward_parity_check <- function(deployed_csv, as_of,
                                 carrier_parquet = file.path(ROOT, "06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"),
                                 declared_convention = "canonical",
                                 alpha_path = file.path(ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"),
                                 raw_path = file.path(ROOT, ".cache/rawdata.parquet"),
                                 tol = FP_TOL, verbose = TRUE) {
  err <- function(msg) { if (verbose) cat(sprintf("[parity] ERROR — %s\n", msg))
                         return(list(status = "ERROR", reason = msg, divergence = NA_real_)) }
  as_of <- as.Date(as_of)
  if (!file.exists(deployed_csv)) return(err(sprintf("배포 CSV 부재: %s", deployed_csv)))
  for (p in c(carrier_parquet, alpha_path, raw_path)) if (!file.exists(p)) return(err(sprintf("입력 부재: %s", p)))

  dep <- tryCatch(fread(deployed_csv), error = function(e) NULL)
  if (is.null(dep) || !nrow(dep)) return(err("배포 CSV 판독 실패 또는 0행"))
  if (!all(c("Ticker","Weight") %in% names(dep))) return(err("배포 CSV 에 Ticker/Weight 컬럼 없음"))
  dep_eq <- dep[Ticker != "CASH" & is.finite(Weight)]
  if (!nrow(dep_eq)) return(err("배포 CSV 에 주식 행 0 — 검사 불능(합격 아님)"))
  inv <- sum(dep_eq$Weight)
  if (!is.finite(inv) || inv <= 0) return(err("배포 비중 합 0 이하 — 검사 불능"))
  w_dep <- setNames(dep_eq$Weight / inv, dep_eq$Ticker)

  car <- as.data.table(read_parquet(carrier_parquet)); car[, decision_date := as.Date(decision_date)]
  ap <- as.data.table(read_parquet(alpha_path)); ap[, Date := as.Date(Date)]
  raw <- as.data.table(read_parquet(raw_path, col_select = c("Date","Ticker","Close","Vol")))
  raw[, Date := as.Date(Date)]; raw[, TV := Close * Vol]

  replay <- function(sig, w_prev) {
    panel <- ap[Date == sig & !is.na(score_eff)]
    if (!nrow(panel)) return(NULL)
    regime <- panel$regime_state[1L]; setorder(panel, -score_eff)
    N <- min(FP_TOPN, nrow(panel)); if (N < FP_MINN && nrow(panel) >= FP_MINN) N <- FP_MINN
    a <- setNames(panel[seq_len(N)]$score_eff, panel[seq_len(N)]$Ticker)
    sd_ <- min(raw[Date >= sig]$Date)
    liq <- raw[Date >= sd_ - 30L & Date < sd_, .(ADV = mean(TV, na.rm=TRUE)), by=Ticker][ADV >= FP_LIQ, Ticker]
    tk <- intersect(names(a), liq); if (length(tk) < 5L) tk <- names(a)
    a <- a[tk]
    list(w = .fp_weights(a, w_prev, regime, declared_convention), regime = regime)
  }
  # w_prev 체인: 캐리어 마지막 결정월 → as_of 직전월까지 replay 연장
  last_dd <- max(car$decision_date)
  if (last_dd >= as_of) {                      # 캐리어가 해당 월을 이미 포함
    x <- car[decision_date == as_of]
    if (!nrow(x)) return(err("캐리어에 as_of 행 없음"))
    w_ref <- setNames(x$weight_strategy, x$Ticker); regime <- x$regime[1L]
  } else {
    x <- car[decision_date == last_dd]
    wp <- setNames(x$weight_strategy, x$Ticker)
    months <- seq(seq(last_dd, by = "month", length.out = 2)[2], as_of, by = "month")
    r <- NULL
    for (m in as.list(months)) { r <- replay(as.Date(m), wp); if (is.null(r)) return(err(sprintf("replay 실패 @%s", m))); wp <- r$w }
    w_ref <- wp; regime <- r$regime
  }
  if (!length(w_ref)) return(err("기준 비중 산출 0 — 검사 불능"))

  allt <- union(names(w_dep), names(w_ref))
  a <- setNames(rep(0, length(allt)), allt); a[names(w_dep)] <- w_dep
  b <- setNames(rep(0, length(allt)), allt); b[names(w_ref)] <- w_ref
  d <- a - b
  div <- 0.5 * sum(abs(d))                     # 턴오버 등가 괴리
  status <- if (max(abs(d)) <= tol) "PASS" else "FAIL"
  if (verbose) cat(sprintf("[parity] %s | as_of=%s regime=%s conv=%s | max|dw|=%.3e 괴리=%.4f (%.1f%%) | 종목 배포%d/기준%d\n",
      status, as_of, regime, declared_convention, max(abs(d)), div, div*100, sum(a>1e-9), sum(b>1e-9)))
  list(status = status, divergence = div, max_abs_dw = max(abs(d)), regime = regime,
       convention = declared_convention, n_deployed = sum(a > 1e-9), n_reference = sum(b > 1e-9), as_of = as.character(as_of))
}

if (sys.nframe() == 0 && !interactive()) {
  ar <- commandArgs(trailingOnly = TRUE)
  if (length(ar) < 2) { cat("usage: forward_parity_check.R <deployed_csv> <as_of> [convention]\n"); quit(status = 2) }
  r <- forward_parity_check(ar[1], ar[2], declared_convention = if (length(ar) >= 3) ar[3] else "canonical")
  quit(status = if (identical(r$status, "PASS")) 0L else 1L)
}
