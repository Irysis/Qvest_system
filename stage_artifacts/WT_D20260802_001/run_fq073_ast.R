# =============================================================================
# run_fq073_ast.R — WT-D20260802_001 / FQ-073
#   AST v1.1 관통 러너: 신호 계산 = ast_compile.R (컴파일러-소유 AS_OF 조인, 수기 merge 금지)
#                        측정      = canonical_screen_bt (계약 실측, 손계산 금지)
#
# 역할 경계: alpha only — 공분산/비중/사전최적화 없음. canonical top-N EW 는 고정 규격 스크린.
#
# 두 lane (falsification 설계):
#   LANE_UPPER  crosswalk = static_current (2024-25 사업보고서 1 vintage를 전 역사 귀속)
#               → C1/C3 사업구성 look-ahead 포함 = **상한**. gate_eligible=FALSE.
#               상한이 실패하면 PIT-clean lane 도 실패한다(논리적 포함관계) → 조기 판정 가능.
#   LANE_CLEAN  effective_from as-of (매핑 공시일 이후만) → n_months 극소, 참고 보고만.
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_001/run_fq073_ast.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

`%||%` <- function(a, b) if (is.null(a)) b else a
.die <- function(fmt, ...) stop(sprintf(paste0("[fq073ast] ", fmt), ...), call. = FALSE)
say <- function(fmt, ...) cat(sprintf(paste0("[fq073ast] ", fmt, "\n"), ...))

source("02_Infrastructure/ast/ast_compile.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")        # build_monthly_forward_returns
source("02_Infrastructure/validation/overlay_pit_guard.R")  # assert_overlay_pit

# -----------------------------------------------------------------------------
# 1. 시장 패널 + 월말 그리드
# -----------------------------------------------------------------------------
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150", "Sector")))
RAW[, Date := as.Date(Date)]
RAW <- RAW[Date >= as.Date("2014-11-01")]
RAW[, ym := format(Date, "%Y-%m")]
MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
say("rawdata: %d행 · 월말 %d개 · %s~%s", nrow(RAW), length(MEND),
    as.character(min(MEND)), as.character(max(MEND)))

# -----------------------------------------------------------------------------
# 2. C5 PIT 감사 — 데이터월 M / usable = M+1/15 / score_date = M+1 월말 / 홀딩 = M+2
# -----------------------------------------------------------------------------
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
SD <- data.table(score_date = MEND)
SD[, data_ym       := ym_add(format(score_date, "%Y-%m"), -1L)]
SD[, usable_date   := as.Date(sprintf("%s-15", ym_add(data_ym, 1L)))]
SD[, holding_start := holdings_signal_cutoff(score_date)]
SD[, buffer_days   := as.integer(holding_start - usable_date)]
assert_overlay_pit(SD$usable_date, SD$holding_start, label = "FQ073_AST_customs_export")
MIN_BUF <- 10L
if (nrow(SD[buffer_days < MIN_BUF]))
  .die("PIT 버퍼 미달 %d행 (min=%d)", nrow(SD[buffer_days < MIN_BUF]), MIN_BUF)
say("C5 PASS — buffer %d~%d일 (요건 >=%d)", min(SD$buffer_days), max(SD$buffer_days), MIN_BUF)

# -----------------------------------------------------------------------------
# 3. 유니버스 그리드 (K200 ∪ KQ150, 신호일 시점 멤버십)
# -----------------------------------------------------------------------------
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
EVAL <- sort(unique(UNIV$Date))
EVAL <- EVAL[EVAL >= as.data.table(read_parquet(
  file.path(OUT, "fq073_export_exposure_chapter.parquet")))[, min(Date)] + 700]  # 24M 히스토리 확보
UNIV <- UNIV[Date %in% EVAL]
say("유니버스: %d월 · 월평균 %.0f종목 · %s~%s", uniqueN(UNIV$Date),
    UNIV[, .N, by = Date][, mean(N)], as.character(min(EVAL)), as.character(max(EVAL)))

# -----------------------------------------------------------------------------
# 4. forward returns / benchmark / liquidity / size  (전부 계약 함수 경유)
# -----------------------------------------------------------------------------
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt    <- RAWME[, .(Date, Ticker, Size)]
say("forward returns %d행 · bench %d행 · liq %d행", nrow(returns_dt), nrow(bench_dt), nrow(liq_dt))

# 라벨 방향 감사 (동적 검정 — 정적 PASS가 면제하지 않음, SOT §4)
lbl <- merge(RAWME[, .(Date, Ticker, Close)], returns_dt, by = c("Date", "Ticker"))
lbl <- merge(lbl, RAWME[, .(Date_next = Date, Ticker, Close_next = Close)], by = "Ticker",
             allow.cartesian = TRUE)
lbl <- lbl[Date_next > Date][order(Ticker, Date, Date_next)]
lbl <- lbl[, .SD[1], by = .(Ticker, Date)]
lbl[, ret_check := Close_next / Close - 1]
lab_corr <- lbl[is.finite(ret_check) & is.finite(Ret_1m), stats::cor(Ret_1m, ret_check)]
say("라벨 방향 감사: cor(Ret_1m, forward recompute) = %.6f (>0.99 기대)", lab_corr)
if (!is.finite(lab_corr) || lab_corr < 0.99) .die("라벨 방향 감사 실패 — forward label 부호/정렬 오류")

# -----------------------------------------------------------------------------
# 5. AST 컴파일 → canonical_screen_bt 실측
# -----------------------------------------------------------------------------
FIDS <- c("F1_export_surprise", "F2_export_yoy_level",
          "F3_export_accel", "F4_export_surprise_secneutral")

measure <- function(scores, tag, top_n = 25L) {
  sc <- scores[is.finite(value), .(Date, Ticker, score = value)]
  if (!nrow(sc)) return(NULL)
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = top_n,
                      cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                      diag_dual_basis = TRUE, size_dt = size_dt)
}

results <- list(); manifests <- list(); panels <- list()
for (fid in FIDS) {
  say("── AST compile: %s", fid)
  cmp <- tryCatch(
    ast_compile(file.path(OUT, sprintf("ast_%s.json", fid)),
                eval_dates = EVAL, universe = UNIV,
                manifest_out = file.path(OUT, sprintf("ast_manifest_%s.json", fid))),
    error = function(e) { say("  compile ERROR: %s", conditionMessage(e)); NULL })
  if (is.null(cmp)) next
  p <- cmp$panel
  nn <- sum(!is.na(p$value))
  say("  panel %d cells · non-NA %d (%.1f%%) · nodes=%s depth=%s",
      nrow(p), nn, 100 * nn / max(1, nrow(p)),
      cmp$manifest$ast_features$node_count %||% NA,
      cmp$manifest$ast_features$max_depth %||% NA)
  panels[[fid]] <- p; manifests[[fid]] <- cmp$manifest
  r <- measure(p, fid)
  if (is.null(r)) { say("  측정 skip (스코어 0행)"); next }
  results[[fid]] <- r
  say("  PORT_t(cap-w)=%.3f p=%.3f n=%d · netSR=%.3f · IR=%.3f · TO=%.0f%%",
      r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue, r$n_months,
      r$net_sr %||% NA_real_, r$information_ratio %||% NA_real_,
      100 * (r$turnover_annual %||% NA_real_))
  ew <- r$diag_ew_universe
  if (!is.null(ew$portfolio_alpha_t_nw_lag3))
    say("  dual-basis EW-universe PORT_t=%.3f · post2017_t=%s (진단·비바인딩)",
        ew$portfolio_alpha_t_nw_lag3, format(ew$post2017_t_nw_lag3 %||% NA_real_, digits = 3))
}

saveRDS(list(results = results, manifests = manifests),
        file.path(OUT, "fq073_ast_results.rds"))
for (fid in names(panels)) {
  write_parquet(panels[[fid]], file.path(OUT, sprintf("alpha_scores_%s.parquet", fid)))
}
say("완료 — 측정 %d/%d 팩터", length(results), length(FIDS))
