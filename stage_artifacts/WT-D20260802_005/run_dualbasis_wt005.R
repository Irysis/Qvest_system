#==============================================================================
# run_dualbasis.R — alpha-search 후보의 canonical PORT_t + dual-basis 진단 하네스
#
#   목적 (v8.3 의무): alpha-search 라운드의 판정 1급 지표 = canonical PORT_t
#   (cap-w basis, metric_type="canonical_screen"). 기각 前 **EW-유니버스 대비 +
#   cap-tier(MEGA/MID/OTHER) 분해**를 반드시 병기한다(post-2017 감쇠의 상당부분이
#   mega-cap 벤치 아티팩트라는 실측 때문 — memory project-megacap-anchor-construction).
#
#   run_alpha_search()는 grade<B & screen_pass=FALSE 이면 proxy(hurdle_gate)에서
#   멈추고 권위측정(build_bt_result/canonical)으로 escalate 하지 않는다. 07-27
#   큐 2건(spec_mass / resid_info_vol)이 dual-basis 없이 QUARANTINE 된 이유.
#   본 하네스가 그 공백을 메운다.
#
#   실행:
#     AS_FE=<factor_engine 절대경로> AS_LABEL=<라벨> Rscript ... run_dualbasis.R
#   규율: K200∪KQ150 · top-25 EW long-only · liq>=2e8 · 15bps · start 2005-01-01
#         자체합성 없음(canonical_screen_bt 계약 경유)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
INFRA <- file.path(ROOT, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))          # load_rawdata
source(file.path(INFRA, "ramp", "factor_validation.R")) # build_monthly_forward_returns
source(file.path(INFRA, "contracts", "backtest_result_contract.R"))
source(file.path(INFRA, "contracts", "canonical_screen_bt.R"))
stopifnot(exists("build_benchmark_compare"), exists("canonical_screen_bt"))

FE     <- Sys.getenv("AS_FE", "")
LABEL  <- Sys.getenv("AS_LABEL", "unnamed")
TOPN   <- as.integer(Sys.getenv("AS_TOPN", "25"))
START  <- Sys.getenv("AS_START", "2005-01-01")
OUT    <- Sys.getenv("AS_OUT", file.path(ROOT, "stage_artifacts", "WT-D20260802_005"))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
stopifnot(nzchar(FE), file.exists(FE))
cat(sprintf("[dualbasis] FE=%s | label=%s | top_n=%d | start=%s\n", FE, LABEL, TOPN, START))

# ── 1. RAWDATA (run_alpha_search와 동일 경로) ────────────────────────────────
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
LIQ <- 2e8
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ]

# ── 2. factor engine → FACTORS ───────────────────────────────────────────────
fe_env <- new.env(parent = environment())
fe_env$RAWDATA <- RAWDATA; fe_env$BM_DT <- BM_DT
source(FE, local = fe_env)
FACTORS <- fe_env$FACTORS
rm(fe_env); gc(verbose = FALSE)
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
FACTORS <- FACTORS[Date >= as.Date(START)]

# ── 3. 유니버스 K200∪KQ150 (PIT 시변 멤버십) ────────────────────────────────
.me_uni <- unique(FACTORS$Date)
.mem <- unique(RAWDATA[Date %in% .me_uni & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
n0 <- uniqueN(FACTORS$Ticker)
FACTORS <- merge(FACTORS, .mem, by = c("Date","Ticker"))
cat(sprintf("[dualbasis] FACTORS %d rows | dates %d | tickers %d->%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n0, uniqueN(FACTORS$Ticker)))

# ── 4. 표준 forward returns / bench / liq (frozen 규약) ──────────────────────
RAWDATA[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAWDATA[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAWDATA[Date %in% .MEND, .(Date, Ticker, Close, Vol, Size, K200, KQ150)]
fwd <- build_monthly_forward_returns(RAWME, .MEND)
returns_dt <- fwd$returns_dt; bench_dt <- fwd$bench_dt; liq_dt <- fwd$liq_dt

# size_dt: 유니버스 전체(멤버십 통과) 시총 패널 — cap_rank는 이 패널 내 상대랭킹
size_dt <- merge(RAWME[, .(Date, Ticker, Size)], .mem, by = c("Date","Ticker"))
size_dt <- size_dt[is.finite(Size)]

# ── 5. canonical_screen_bt (계약 경유, dual-basis 병기) ─────────────────────
scores <- FACTORS[, .(Date, Ticker, score = Score)]
out <- canonical_screen_bt(scores, returns_dt, bench_dt,
                           top_n = TOPN, cost_bps_oneway = 15,
                           liq_dt = liq_dt, liq_min = 2e8,
                           run_id = paste0("AS_DUALBASIS_", LABEL),
                           strategy_id = LABEL,
                           diag_dual_basis = TRUE, size_dt = size_dt)

capw_t <- out$portfolio_alpha_t_nw_lag3 %||% NA_real_
ew     <- out$diag_ew_universe %||% list()
ct     <- out$diag_cap_tier %||% list()

cat("\n===== DUAL-BASIS SUMMARY =====\n")
cat(sprintf("label            : %s\n", LABEL))
cat(sprintf("n_months         : %s\n", as.character(out$n_months %||% NA)))
cat(sprintf("[cap-w 권위] PORT_t=%.3f | net_sr=%.3f | IR=%.3f | alpha_ann=%.4f\n",
            capw_t, out$net_sr %||% NA_real_, out$information_ratio %||% NA_real_,
            out$alpha_annualized %||% NA_real_))
cat(sprintf("[EW-uni 진단] PORT_t=%.3f | net_sr=%.3f | oos~=%.3f | post2017_t=%.3f (n=%s)\n",
            ew$portfolio_alpha_t_nw_lag3 %||% NA_real_, ew$net_sr %||% NA_real_,
            ew$oos_retention_approx %||% NA_real_, ew$post2017_t_nw_lag3 %||% NA_real_,
            as.character(ew$n_months_post2017 %||% NA)))
if (isTRUE(ct$available)) {
  ws <- ct$weight_share_avg; ca <- ct$contrib_gross_annualized
  cat(sprintf("[cap-tier] weight MEGA=%.3f MID=%.3f OTHER=%.3f UNRANKED=%.3f\n",
              ws$MEGA, ws$MID, ws$OTHER, ws$UNRANKED))
  cat(sprintf("[cap-tier] contrib_ann MEGA=%.4f MID=%.4f OTHER=%.4f UNRANKED=%.4f\n",
              ca$MEGA, ca$MID, ca$OTHER, ca$UNRANKED))
} else {
  cat(sprintf("[cap-tier] unavailable: %s\n", ct$note %||% "?"))
}

# JSON 저장 (대용량 하위표는 제거)
slim <- out
slim$benchmark_compare <- NULL; slim$period_returns <- NULL
if (!is.null(slim$diag_ew_universe)) {
  slim$diag_ew_universe$benchmark_compare <- NULL
  slim$diag_ew_universe$period_returns <- NULL
}
if (!is.null(slim$diag_cap_tier)) slim$diag_cap_tier$by_month <- NULL
write_json(slim, file.path(OUT, sprintf("dualbasis_%s.json", LABEL)),
           auto_unbox = TRUE, na = "null", pretty = TRUE)
# 월간 active 시계열은 별도 CSV (재현·차트용)
if (!is.null(out$period_returns)) {
  fwrite(as.data.table(out$period_returns),
         file.path(OUT, sprintf("period_returns_%s.csv", LABEL)))
}
cat(sprintf("[dualbasis] saved: %s\n", file.path(OUT, sprintf("dualbasis_%s.json", LABEL))))
