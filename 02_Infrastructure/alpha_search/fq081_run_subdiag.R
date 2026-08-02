# FQ-081 보조 진단: rank-IC(advisory) · 서브기간 · 데이터원천 전환(2015) 영향 · 역방향 검정
suppressPackageStartupMessages({ library(data.table); library(arrow); library(dplyr); library(sandwich) })
setDTthreads(2)
ROOT <- local({ for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR",""), Sys.getenv("QM_ROOT",""), getwd()))
  if (nzchar(p) && file.exists(file.path(p,"CLAUDE.md"))) return(gsub("\\\\","/",p)); stop("root") })
setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(ROOT,"02_Infrastructure/alpha_search/fq081_dupont_panel.R"))
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a
OUT <- file.path(ROOT,"stage_artifacts","alpha_search","FQ081_diag")

fv  <- fq081_build_fundamental_vintages(CACHE_DIR)
mon <- fq081_build_monthly_panel(CACHE_DIR)
bmm <- fq081_build_benchmark(CACHE_DIR)
j   <- fq081_asof_join(mon, fv)
u   <- j[in_index == TRUE & is.finite(adv) & adv >= 2e8 & !is.na(Sector)]
u   <- u[ym >= "200501"]
d   <- fq081_build_features(u)

# ── 원천 전환 확인: 종목-월 vintage 신선도 / 갱신 빈도 ──
d[, stale_d := as.integer(sig_date - vint_cur)]
cat("\n[sub] vintage 신선도(일) 중앙값 by era\n")
print(d[, .(med_stale = as.numeric(median(stale_d)), n_vint_per_yr = uniqueN(vint_cur)/uniqueN(substr(ym,1,4)),
            n = .N), by = .(era = fifelse(ym < "201604", "pre2016(분기 XLSX)", "2016+(연간 DART)"))])

# ── rank-IC (advisory) ──
icf <- function(fcol, lab) {
  D <- d[is.finite(ret_fwd) & is.finite(get(fcol))]
  m <- D[, .(ic = if (.N>=20) cor(rank(get(fcol)), rank(ret_fwd)) else NA_real_, n=.N), by=ym][is.finite(ic)]
  sub <- function(x) if (nrow(x)>=12) sprintf("IC=%+.4f ICIR=%+.2f n=%d", mean(x$ic), mean(x$ic)/sd(x$ic)*sqrt(12), nrow(x)) else "n부족"
  cat(sprintf("  %-8s 전기간 %s | 2005-2015 %s | 2016+ %s\n", lab, sub(m), sub(m[ym<"201601"]), sub(m[ym>="201601"])))
}
cat("\n[sub] rank-IC (advisory — PORT_t 가 권위)\n")
for (f in c("g_dPM","g_dATO","i_dPM","i_dATO","i_PM","i_ATO","x_PM","x_ATO")) icf(f, f)

# ── arm 스코어 재생성 + 서브기간 PORT_t ──
FE <- list(A=c("g_dPM","g_dATO"), B=c("i_dPM","i_dATO"),
           C=c("i_dPM","i_dATO","i_PM","i_ATO","x_PM","x_ATO"))
md <- unique(d[, .(ym, mdate)])
returns_dt <- unique(d[is.finite(ret_fwd), .(Date=mdate, Ticker, Ret_1m=ret_fwd)])
bench_dt <- bmm[, .(Date=mdate, BM_Ret)]
liq_dt <- unique(d[, .(Date=mdate, Ticker, adv)])
size_dt <- unique(d[is.finite(Size), .(Date=mdate, Ticker, Size)])

sc <- lapply(FE, function(f) fq081_fm_scores(d, f, min_months = 36L))
run_sub <- function(nm, ymin, ymax, lab) {
  s <- merge(sc[[nm]], md, by="ym")[ym >= ymin & ym <= ymax, .(Date=mdate, Ticker, score)]
  if (nrow(s) < 500) { cat(sprintf("  arm %s %s: 표본부족\n", nm, lab)); return(NULL) }
  r <- tryCatch(canonical_screen_bt(s, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                  liq_dt=liq_dt, liq_min=2e8, size_dt=size_dt, diag_dual_basis=TRUE,
                  run_id=paste0("FQ081_",nm,"_",lab), strategy_id=paste0("FQ081_",nm)), error=function(e) NULL)
  if (is.null(r)) return(NULL)
  ew <- r$diag_ew_universe
  cat(sprintf("  arm %s %-12s months=%3d  PORT_t=%+6.3f  EW-basis=%+6.3f  IR=%+6.3f  netSR=%+6.3f\n",
      nm, lab, r$n_months, r$portfolio_alpha_t_nw_lag3 %||% NA,
      if (is.list(ew)) (ew$portfolio_alpha_t_nw_lag3 %||% NA_real_) else NA_real_,
      r$information_ratio %||% NA, r$net_sr %||% NA))
  r
}
cat("\n[sub] 서브기간 PORT_t (IS/OOS 아님 — 구조 안정성 진단)\n")
for (nm in c("A","B","C")) {
  run_sub(nm, "200501","201512","2005-2015")
  run_sub(nm, "201601","202607","2016-2026")
  run_sub(nm, "200501","201612","pre-2017")
  run_sub(nm, "201701","202607","post-2017")
}

# ── 역방향(반대 부호) 검정: 개선이 아니라 악화가 유리한가 ──
cat("\n[sub] 역방향 검정 (score 부호 반전 — 신호 자체가 반대 방향인지)\n")
for (nm in c("A","B","C")) {
  s <- merge(sc[[nm]], md, by="ym")[, .(Date=mdate, Ticker, score = -score)]
  r <- tryCatch(canonical_screen_bt(s, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                  liq_dt=liq_dt, liq_min=2e8, size_dt=size_dt, diag_dual_basis=FALSE,
                  run_id=paste0("FQ081_neg_",nm), strategy_id=paste0("FQ081_neg_",nm)), error=function(e) NULL)
  if (!is.null(r)) cat(sprintf("  arm %s (부호반전) PORT_t=%+6.3f IR=%+6.3f\n", nm,
                               r$portfolio_alpha_t_nw_lag3 %||% NA, r$information_ratio %||% NA))
}
cat("\n[sub] DONE\n")
