## =============================================================================
## FQ-198 / WT-D20260809_005 — 전이 측정 (dual-basis)
##
## ★사전선언(측정 전 고정, np_m26_canonical.R 프레임 승계):
##   재료 자격(|FMB t| >= 2.0)을 얻은 arm 에 대해서만 실행. arm 별로 2벌:
##     1급 = 원신호 canonical top-25 EW (표준형)
##     2급 = 증분 표현(incumbent 3종 통제 후 월별 횡단면 잔차)
##   ★두 값 중 argmax 선택 금지 — 둘 다 보고.
## ★전이는 별도 관문 — 본 라운드는 **재료 자격까지만** 주장한다. cap-w PORT_t 는 진단.
## metric_type = canonical_screen (cap-w) + canonical_screen_diag (dual-basis)
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
say <- function(fmt,...) { cat(sprintf(paste0("[canon] ",fmt,"\n"),...)); flush.console() }
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

RES <- readRDS(file.path(OUT,"p1_results.rds"))
V   <- RES$V; INCUMBENT <- RES$INCUMBENT
QUAL <- V[abs(t_nw3) >= 2.0 & redundancy == "DISTINCT", arm]
say("★재료 자격 통과 arm %d: %s", length(QUAL), paste(QUAL, collapse=", "))
if (!length(QUAL)) { say("자격 arm 0 — 전이 측정 생략(측정할 재료 없음)"); quit(save="no", status=0) }

## ---- 입력 실측 (첫 출력) ----
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
setnames(A, "signal_date", "Date"); A[, Date := as.Date(Date)]
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

runone <- function(S, tag) {
  say("=== %s ===", tag)
  r <- canonical_screen_bt(S, ret, bench, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liq, liq_min = 2e8,
                           run_id = paste0("WT_D20260809_005_", tag),
                           strategy_id = paste0("FQ198_", tag),
                           diag_dual_basis = TRUE, size_dt = size_dt)
  say("  metric_type = %s", r$metric_type %||% "NA")
  say("  ★cap-w PORT_t(NW3) = %+.3f  (HARD 문턱 2.95 — 본 라운드는 진단, 자본 주장 아님)",
      r$portfolio_alpha_t_nw_lag3 %||% NA_real_)
  for (k in c("n_months","net_sr","cagr","mdd","calmar","turnover_annual","net_ir")) {
    v <- r[[k]]; if (!is.null(v) && is.finite(suppressWarnings(as.numeric(v[1]))))
      say("  %-18s %s", k, format(round(as.numeric(v[1]),4)))
  }
  flat <- function(x, lab) {
    if (is.null(x)) { say("  [%s] 부재", lab); return(invisible()) }
    say("  [%s]", lab)
    if (is.data.frame(x)) { print(as.data.table(x)); return(invisible()) }
    for (nm in names(x)) { v <- x[[nm]]; if (is.null(v)) next
      if (length(v)==1L && (is.numeric(v)||is.character(v)||is.logical(v)))
        say("    %-28s %s", nm, if (is.numeric(v)) format(round(v,4)) else as.character(v))
      else say("    %-28s <%s len %d>", nm, class(v)[1], length(v)) }
  }
  flat(r$diag_ew_universe, "diag EW-유니버스 벤치")
  flat(r$diag_cap_tier,   "diag cap-tier")
  r
}

OUTL <- list()
for (a_ in QUAL) {
  sub <- A[is.finite(get(a_))]
  S_raw <- sub[, .(Date, Ticker, score = get(a_))]
  ## 증분 표현: 월별 횡단면에서 incumbent 3종 통제 후 잔차
  cols <- c(INCUMBENT, a_)
  sub2 <- sub[complete.cases(sub[, ..cols])]
  sub2[, resid := {
    fit <- lm(as.formula(paste(a_, "~", paste(INCUMBENT, collapse=" + "))), data=.SD)
    as.numeric(residuals(fit))
  }, by = signal_ym, .SDcols = cols]
  S_res <- sub2[, .(Date, Ticker, score = resid)]
  say("[%s] 점수 2벌: 원신호 %d행 · 잔차 %d행 · 잔차-원신호 상관 %.3f",
      a_, nrow(S_raw), nrow(S_res), cor(sub2[[a_]], sub2$resid))
  OUTL[[a_]] <- list(raw = runone(S_raw, paste0(a_,"_raw")),
                     resid = runone(S_res, paste0(a_,"_resid_increment")))
}

saveRDS(OUTL, file.path(OUT,"p2_canonical.rds"))
say("================ 전이 요약 ================")
SUM <- rbindlist(lapply(names(OUTL), function(a_) data.table(
  arm=a_,
  raw_capw_port_t   = OUTL[[a_]]$raw$portfolio_alpha_t_nw_lag3 %||% NA_real_,
  resid_capw_port_t = OUTL[[a_]]$resid$portfolio_alpha_t_nw_lag3 %||% NA_real_,
  raw_net_sr        = OUTL[[a_]]$raw$net_sr %||% NA_real_,
  raw_mdd           = OUTL[[a_]]$raw$mdd %||% NA_real_,
  raw_calmar        = OUTL[[a_]]$raw$calmar %||% NA_real_,
  raw_turnover      = OUTL[[a_]]$raw$turnover_annual %||% NA_real_)))
print(SUM)
fwrite(SUM, file.path(OUT,"p2_transition_summary.csv"))
say("저장 완료 → p2_canonical.rds / p2_transition_summary.csv")
