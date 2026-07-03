# =============================================================================
# _probe3_verdict.R — probe3 (Hou 2007 sector spillover) 3 반증기준 + 클래스 판정
# =============================================================================
# 3 반증기준 (선행 고정):
#   1. portfolio_alpha_t_nw_lag3 >= 2.95  (HARD, contract .nw_t_mean(daily net active, lag=3))
#   2. oos_retention >= 0.7                (HARD 과적합, active monthly Sharpe OOS/IS, split 2015/2016)
#   3. return_cor vs STR_1715 < 0.5        (직교성 — 최우선; probe1=0.07 PASS)
# + DB 주요팩터 return_cor, peer high-grade module corr.
# 입력: env STRAT_ID (= STR_AS_...) → 04_Research/strategies/<id>/sim_result.rds
# 자체합성 없음: NW t = contract 함수, 월간 active = apply.monthly(Return.cumulative) 동치.
# PowerShell + Rscript -e "source(...)" only.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(xts); library(zoo)
  library(PerformanceAnalytics); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
STRAT_ID <- Sys.getenv("STRAT_ID", "")
TAG      <- Sys.getenv("PROBE3_TAG", STRAT_ID)
if (!nzchar(STRAT_ID)) stop("STRAT_ID 미설정")

# ---- contract NW t (daily net active, lag=3) — 정확히 build_benchmark_compare 방식 ----
.nw_t_mean <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < (lag + 2L)) return(NA_real_)
  mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n; s <- g0
  for (l in 1:lag) { w <- 1 - l/(lag+1); g <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*w*g }
  if (s <= 0) return(NA_real_)
  mu / sqrt(s/n)
}
to_monthly_ret <- function(dt) {  # dt(Date,Ret) -> (ym, ret) via apply.monthly Return.cumulative
  dt <- copy(dt)[is.finite(Ret)]; setorder(dt, Date)
  x <- xts(dt$Ret, order.by = dt$Date)
  m <- apply.monthly(x, Return.cumulative)
  data.table(ym = format(as.Date(index(m)), "%Y-%m"), ret = as.numeric(m[,1]))
}
ann <- sqrt(12)
act_sharpe <- function(x){ x<-x[is.finite(x)]; s<-sd(x); if(!is.finite(s)||s<=0) return(NA_real_); mean(x)/s*ann }

# ---- 1. 전략 sim_result ----
sp <- file.path(PROJ, "04_Research/strategies", STRAT_ID, "sim_result.rds")
if (!file.exists(sp)) sp <- file.path(PROJ, "stage_artifacts/alpha_search", sub("^STR_AS_","",STRAT_ID), "sim_result.rds")
stopifnot(file.exists(sp))
sim <- readRDS(sp)
s_dt <- as.data.table(sim$DAILY_NAV_DT)[, .(Date = as.Date(Date), Ret = Strategy_Ret)]
bm_xts <- sim$bm_xts
b_dt   <- data.table(Date = as.Date(index(bm_xts)), Ret = as.numeric(coredata(bm_xts)))

# daily net active (전략 net - BM) — Date 정합 후
da <- merge(s_dt[, .(Date, s = Ret)], b_dt[, .(Date, b = Ret)], by = "Date")
da[, active := s - b]
port_t_nw3 <- .nw_t_mean(da$active, lag = 3L)
port_p     <- if (is.na(port_t_nw3)) NA_real_ else 2*(1 - pnorm(abs(port_t_nw3)))
cat(sprintf("[PORT_t] daily net active NW lag3 t=%.4f (p=%.4f, n_days=%d)\n", port_t_nw3, port_p, nrow(da)))

# ---- 2. OOS retention (monthly active Sharpe, IS<=2015 / OOS>=2016) ----
s_m <- to_monthly_ret(s_dt); setnames(s_m,"ret","str")
b_m <- to_monthly_ret(b_dt); setnames(b_m,"ret","bm")
act <- merge(s_m, b_m, by="ym"); act[, active := str - bm]
act[, yr := as.integer(substr(ym,1,4))]
sr_is  <- act_sharpe(act[yr<=2015, active]); sr_oos <- act_sharpe(act[yr>=2016, active])
oos_ret <- if (is.finite(sr_is) && abs(sr_is)>1e-9) sr_oos/sr_is else NA_real_
cat(sprintf("[OOS] active SR IS(<=2015,n=%d)=%.4f OOS(>=2016,n=%d)=%.4f retention=%.4f\n",
            nrow(act[yr<=2015]), sr_is, nrow(act[yr>=2016]), sr_oos, oos_ret))

# ---- 3. return_cor vs STR_1715 (monthly active overlap) ----
s1715_dir <- file.path(PROJ, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output")
pr  <- fread(file.path(s1715_dir, "03_period_returns.csv"))
bch <- fread(file.path(s1715_dir, "05_benchmark_returns.csv"))
# STR_1715 라벨 규약(차월 첫 거래일=전월 수익) — 1개월 당겨 정렬 (정정 2026-06-13: 이전 cor 과소치)
pr[, ym := format(as.Date(format(as.Date(date), "%Y-%m-01")) - 1L, "%Y-%m")]
bch[, ym := format(as.Date(format(as.Date(date), "%Y-%m-01")) - 1L, "%Y-%m")]
s1715 <- merge(pr[, .(ym, str=ret_net)], bch[, .(ym, bm=benchmark_ret)], by="ym")
s1715[, active := str - bm]
ov <- merge(act[, .(ym, a=active)], s1715[, .(ym, s=active)], by="ym")
cor_1715 <- if (nrow(ov)>12) cor(ov$a, ov$s, use="complete.obs") else NA_real_
cat(sprintf("[CORR] return_cor vs STR_1715 (active) rho=%.4f (overlap=%d months)\n", cor_1715, nrow(ov)))

# ---- peer high-grade module corr (score>=40) ----
mods <- tryCatch(fromJSON(file.path(PROJ,"06_Registry/module_catalog.json"))$modules, error=function(e) NULL)
peer <- list()
if (!is.null(mods)) for (k in names(mods)) {
  if (identical(k, STRAT_ID)) next
  sc <- tryCatch(as.numeric(mods[[k]]$meta$score), error=function(e) NA_real_)
  if (length(sc) != 1L || !is.finite(sc) || sc < 40) next
  rds <- file.path(PROJ, mods[[k]]$sim_result_path); if (!file.exists(rds)) next
  pm <- tryCatch(readRDS(rds), error=function(e) NULL)
  if (is.null(pm$DAILY_NAV_DT) || is.null(pm$bm_xts)) next
  p_dt <- as.data.table(pm$DAILY_NAV_DT)[, .(Date=as.Date(Date), Ret=Strategy_Ret)]
  p_bm <- data.table(Date=as.Date(index(pm$bm_xts)), Ret=as.numeric(coredata(pm$bm_xts)))
  pm_m <- merge(to_monthly_ret(p_dt), to_monthly_ret(p_bm), by="ym", suffixes=c(".s",".b"))
  setnames(pm_m, c("ret.s","ret.b"), c("ps","pb")); pm_m[, pa := ps - pb]
  o2 <- merge(act[, .(ym, a=active)], pm_m[, .(ym, pa)], by="ym")
  if (nrow(o2) > 12) { rho <- cor(o2$a, o2$pa, use="complete.obs")
    peer[[k]] <- list(rho=round(rho,4), score=sc, overlap=nrow(o2)) }
}
if (length(peer)) { cat("[PEER corr high-grade]:\n"); for(k in names(peer)) cat(sprintf("   %s score%.0f rho=%.4f (n=%d)\n", k, peer[[k]]$score, peer[[k]]$rho, peer[[k]]$overlap)) }

# ---- FF/Carhart from analysis_multifactor.csv (factor_analysis 산출) ----
ff_summary <- NA
run_dir <- file.path(PROJ, "stage_artifacts/alpha_search", sub("^STR_AS_","",STRAT_ID))
amf <- file.path(run_dir, "analysis_multifactor.csv")
if (file.exists(amf)) { ff_summary <- fread(amf); cat("[FF/Carhart]:\n"); print(ff_summary) }

# ---- 3 반증기준 판정 + 클래스 verdict ----
crit1 <- is.finite(port_t_nw3) && port_t_nw3 >= 2.95
crit2 <- is.finite(oos_ret)    && oos_ret    >= 0.70
crit3 <- is.finite(cor_1715)   && cor_1715   <  0.50
orthogonal_alive <- crit3
alpha_alive      <- crit1 && crit2
class_verdict <- if (orthogonal_alive && alpha_alive) "ORTHOGONAL_ALPHA_ALIVE (GO 재벌데이터)" else
                 if (orthogonal_alive && !alpha_alive) "ORTHOGONAL_NOISE (probe1형 — 관계형 long-only 종료 권고)" else
                 "NOT_ORTHOGONAL (베타 모방)"

out <- list(
  probe = "probe3 Hou2007 industry lead-lag spillover (long-only KR)",
  strategy_id = STRAT_ID, tag = TAG, sim_result = sp,
  falsification = list(
    crit1_port_t_ge_2p95 = list(value = round(port_t_nw3,4), pval = round(port_p,4), pass = crit1),
    crit2_oos_retention_ge_0p70 = list(value = round(oos_ret,4), is_sr = round(sr_is,4), oos_sr = round(sr_oos,4), pass = crit2),
    crit3_return_cor_STR1715_lt_0p50 = list(value = round(cor_1715,4), overlap = nrow(ov), pass = crit3)
  ),
  peer_corr_highgrade = peer,
  orthogonal_alive = orthogonal_alive, alpha_alive = alpha_alive,
  class_verdict = class_verdict,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
out_path <- file.path(PROJ, "stage_artifacts/alpha_search", sprintf("probe3_verdict_%s.json", TAG))
write_json(out, out_path, auto_unbox=TRUE, pretty=TRUE, digits=6)
cat(sprintf("\n[VERDICT] %s\n  crit1 PORT_t=%.3f(>=2.95?%s) crit2 OOS_ret=%.3f(>=0.7?%s) crit3 cor1715=%.3f(<0.5?%s)\n[saved] %s\n",
            class_verdict, port_t_nw3, crit1, oos_ret, crit2, cor_1715, crit3, out_path))
