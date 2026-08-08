## WT-D20260808_002 — 전이 측정 (FMB t=+2.555 유의 확인 후에만 실행. 사전선언 순서 준수)
## ★사전선언(측정 전 고정): 1급 = M26 원신호 canonical top-25 EW (표준형)
##                          2급 = 증분 표현(3종 통제 후 횡단면 잔차 z) canonical
##   ★두 값 중 argmax 선택 금지 — 둘 다 보고. 본 라운드 판정은 이미 FMB t 로 확정됐고
##     전이 측정은 "재료 자격이 자본 자격으로 얼마나 전이되는가"의 진단이다.
## metric_type = canonical_screen (cap-w HARD 권위) + canonical_screen_diag (dual-basis)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260808_002")
say <- function(fmt,...) { cat(sprintf(paste0("[canon] ",fmt,"\n"),...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

## ---- 입력 실측 (첫 출력) ----------------------------------------------------
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
say("★입력 실측: alpha_scores.parquet %d행 · %d개월 · 관측단위 = (월말 Date × Ticker) · %s ~ %s",
    nrow(A), uniqueN(A$Date), min(A$signal_ym), max(A$signal_ym))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
ME <- sort(RAW[, .(Date=max(Date)), by=.(ym=format(Date,"%Y-%m"))]$Date)
RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt; bench <- fwd$bench_dt; liq <- fwd$liq_dt
size_dt <- RAWME[, .(Date, Ticker, Size)]
say("수익/벤치/유동성 패널: ret %d행 · bench %d행 · liq %d행", nrow(ret), nrow(bench), nrow(liq))

## ---- 점수 2벌 (사전선언) ----------------------------------------------------
A[, Date := as.Date(Date)]
S_raw <- A[, .(Date, Ticker, score = M26_Revenue_Mom)]
## 증분 표현: 월별 횡단면에서 3종 통제 후 잔차
A[, resid := {
  fit <- lm(M26_Revenue_Mom ~ C01_SUE + C02_EPS_Chg_1m + C04_ESBR)
  as.numeric(residuals(fit))
}, by = signal_ym]
S_res <- A[, .(Date, Ticker, score = resid)]
say("점수 2벌: 원신호 %d행 · 잔차(3종 통제) %d행 · 잔차-원신호 상관 %.3f",
    nrow(S_raw), nrow(S_res), cor(A$M26_Revenue_Mom, A$resid))

runone <- function(S, tag) {
  say("=== %s ===", tag)
  r <- canonical_screen_bt(S, ret, bench, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liq, liq_min = 2e8,
                           run_id = paste0("WT_D20260808_002_", tag),
                           strategy_id = paste0("M26_", tag),
                           diag_dual_basis = TRUE, size_dt = size_dt)
  say("  metric_type = %s", r$metric_type %||% "NA")
  say("  ★cap-w PORT_t(NW3) = %+.3f  (HARD 문턱 2.95)", r$portfolio_alpha_t_nw_lag3 %||% NA_real_)
  for (k in c("n_months","net_sr","cagr","mdd","calmar","turnover_annual","net_ir")) {
    v <- r[[k]]; if (!is.null(v) && is.finite(suppressWarnings(as.numeric(v[1]))))
      say("  %-18s %s", k, format(round(as.numeric(v[1]), 4)))
  }
  flat <- function(x, lab) {
    if (is.null(x)) { say("  [%s] 부재", lab); return(invisible()) }
    say("  [%s]", lab)
    if (is.data.frame(x)) { print(as.data.table(x)); return(invisible()) }
    for (nm in names(x)) {
      v <- x[[nm]]
      if (is.null(v)) next
      if (length(v) == 1L && (is.numeric(v) || is.character(v) || is.logical(v)))
        say("    %-28s %s", nm, if (is.numeric(v)) format(round(v,4)) else as.character(v))
      else say("    %-28s <%s len %d>", nm, class(v)[1], length(v))
    }
  }
  flat(r$diag_ew_universe, "diag EW-유니버스 벤치")
  flat(r$diag_cap_tier,   "diag cap-tier")
  r
}
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a

R1 <- runone(S_raw, "raw")
R2 <- runone(S_res, "resid_increment")

saveRDS(list(raw=R1, resid=R2), file.path(OUT,"m26_canonical.rds"))
say("저장 완료 → m26_canonical.rds")
say("★★전이 요약: 원신호 cap-w PORT_t %+.3f · 증분(잔차) cap-w PORT_t %+.3f · HARD 2.95",
    R1$portfolio_alpha_t_nw_lag3 %||% NA_real_, R2$portfolio_alpha_t_nw_lag3 %||% NA_real_)
