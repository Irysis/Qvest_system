# =============================================================================
# run_wt122_control.R — WT-D20260808_001 통제 arm + advisory 진단 배터리
#   ① vol-축 재발견 배제: Q01 을 D03(=EWMA vol 63d) 에 대해 월별 횡단면 직교화 후 동일 필터
#   ② 제외집합 중첩 census (Q01-bottom-q ∩ D03-bottom-q)
#   ③ advisory 배터리: rank IC / ICIR / monotonicity / subperiod / Harvey t /
#      post-neutralization IC / turnover / DSR(진단) / alpha_inheritance_cor
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/run_wt122_control.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[ctl] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/essence_score.R")
source("02_Infrastructure/contracts/required_effect_size.R")

FILT <- c("D03_EWMA", "Q01_EB"); Q_PRIMARY <- 0.20

BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
say("INPUT base_panel nrow=%d MONTHLY %d개월 / tuned nrow=%d MONTHLY %d개월",
    nrow(BASE), uniqueN(BASE$Date), nrow(TUNED), uniqueN(TUNED$Date))
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","K200","KQ150")))[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
UNIV <- RAW[Date %in% MEND & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
rm(RAW); gc(verbose = FALSE)
SEC <- as.data.table(read_parquet(file.path(IN9, "sector_panel.parquet")))[, Date := as.Date(Date)]
SIZEP <- as.data.table(read_parquet(file.path(IN9, "size_panel.parquet")))[, Date := as.Date(Date)]

fwd <- readRDS(file.path(OUT, "fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[,     .(Date = as.Date(Date), Ticker, adv)]

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]),
           error = function(e) NA_real_)
}
nw_ci <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA_real_, NA_real_))
  fit <- lm(x ~ 1)
  se <- tryCatch(sqrt(sandwich::NeweyWest(fit, lag = 3L, prewhite = FALSE)[1,1]), error = function(e) NA_real_)
  mean(x) + c(-1,1) * qt(0.975, df = length(x)-1L) * se
}
score_of <- function(f) {
  sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name == f, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == f, .(Date, Ticker, score = score)]
  merge(sc[!is.na(score)], UNIV, by = c("Date","Ticker"))
}
SC_M01 <- score_of("M01_PATHQ")
E <- merge(SC_M01, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
E <- E[is.na(adv) | adv >= 2e8][, adv := NULL]
setorder(E, Date, -score); E[, rk := seq_len(.N), by = Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date, Ticker, fz = score, F_ = f)]))
FZ <- merge(FZ, E[, .(Date, Ticker)], by = c("Date","Ticker"))
FZ[, q_rank := frank(fz)/.N, by = .(Date, F_)]

CTL <- list()
cs_base <- canonical_screen_bt(E[, .(Date, Ticker, score)], returns_dt, bench_dt, top_n = 25L,
  cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8, run_id = "ctl_base",
  strategy_id = "BASE_M01_TOP25", diag_dual_basis = TRUE)
say("base PORT_t=%+.3f net_sr=%+.3f TO=%.2f n=%d", cs_base$portfolio_alpha_t_nw_lag3,
    cs_base$net_sr, cs_base$turnover_annual, cs_base$n_months)

# ── ① 직교화 통제: Q01 ⊥ D03 (vol 축 재발견 배제) ───────────────────────────
say("=== ① vol-축 통제: Q01 을 D03(EWMA vol 63d) 에 월별 횡단면 직교화 ===")
W <- dcast(FZ[, .(Date, Ticker, F_, fz)], Date + Ticker ~ F_, value.var = "fz")
setnames(W, c("D03_EWMA","Q01_EB"), c("d03","q01"))
say("  D03↔Q01 월별 횡단면 Pearson cor 중앙값 %+.4f (Spearman %+.4f) — 직교 여부 실측",
    W[!is.na(d03) & !is.na(q01), cor(d03, q01), by = Date][, median(V1)],
    W[!is.na(d03) & !is.na(q01), cor(d03, q01, method = "spearman"), by = Date][, median(V1)])
W[, q01_res := {
  ok <- is.finite(d03) & is.finite(q01)
  r <- rep(NA_real_, .N)
  if (sum(ok) >= 20L && sd(d03[ok]) > 1e-8) r[ok] <- residuals(lm(q01[ok] ~ d03[ok]))
  r
}, by = Date]
ORTH <- W[is.finite(q01_res), .(Date, Ticker, fz = q01_res)]
ORTH[, q_rank := frank(fz)/.N, by = Date]

run_arm <- function(excl, tag) {
  S <- merge(E[, .(Date, Ticker, score)], excl[, .(Date, Ticker, drop_ = TRUE)],
             by = c("Date","Ticker"), all.x = TRUE)
  S <- S[is.na(drop_)][, drop_ := NULL]
  cs <- canonical_screen_bt(S, returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 15,
        liq_dt = liq_dt, liq_min = 2e8, run_id = paste0("ctl_", tag),
        strategy_id = tag, diag_dual_basis = TRUE)
  d <- merge(as.data.table(cs_base$period_returns)[, .(date, b = ret_net)],
             as.data.table(cs$period_returns)[, .(date, tr = ret_net)], by = "date")
  d[, delta := tr - b]
  req <- required_effect(n = nrow(d), t_threshold = 2.0, sd_monthly = sd(d$delta), design = "full")
  vw <- verdict_with_power(observed_t = nw_t(d$delta), observed_monthly = mean(d$delta),
                           n = nrow(d), sd_monthly = sd(d$delta), design = "full")
  ci <- nw_ci(d$delta)
  list(tag = tag, delta_ann_pct = 100*12*mean(d$delta), t_nw = nw_t(d$delta),
       ci_ann_pct = 100*12*ci, required_ann_pct = 100*req$required_annual,
       power_verdict = vw$verdict, port_t = cs$portfolio_alpha_t_nw_lag3,
       ew_uni_port_t = cs$diag_ew_universe$portfolio_alpha_t_nw_lag3,
       turnover = cs$turnover_annual, net_sr = cs$net_sr, n_months = nrow(d), cs = cs, delta = d)
}
a_q01 <- run_arm(FZ[F_ == "Q01_EB" & q_rank <= Q_PRIMARY], "EXCL_Q01_q20")
a_orth <- run_arm(ORTH[q_rank <= Q_PRIMARY], "EXCL_Q01ORTHD03_q20")
a_d03 <- run_arm(FZ[F_ == "D03_EWMA" & q_rank <= Q_PRIMARY], "EXCL_D03_q20")
for (a in list(a_q01, a_orth, a_d03))
  say("  %-22s Δ연 %+.2f%%  NW t=%+.2f  CI[%+.2f,%+.2f]  필요치 %+.2f%%  PORT_t %+.3f  TO %.2f → %s",
      a$tag, a$delta_ann_pct, a$t_nw, a$ci_ann_pct[1], a$ci_ann_pct[2], a$required_ann_pct,
      a$port_t, a$turnover, a$power_verdict)
CTL$orth_control <- lapply(list(q01 = a_q01, q01_orth_d03 = a_orth, d03 = a_d03),
  function(a) a[setdiff(names(a), c("cs","delta"))])

# ── ② 제외집합 중첩 census ───────────────────────────────────────────────────
say("=== ② 제외집합 중첩 census (q=0.20) ===")
xq <- FZ[F_ == "Q01_EB" & q_rank <= Q_PRIMARY, .(Date, Ticker, inQ = TRUE)]
xd <- FZ[F_ == "D03_EWMA" & q_rank <= Q_PRIMARY, .(Date, Ticker, inD = TRUE)]
xo <- ORTH[q_rank <= Q_PRIMARY, .(Date, Ticker, inO = TRUE)]
mm <- merge(merge(xq, xd, by = c("Date","Ticker"), all = TRUE), xo, by = c("Date","Ticker"), all = TRUE)
for (cc in c("inQ","inD","inO")) mm[is.na(get(cc)), (cc) := FALSE]
ov <- mm[, .(nQ = sum(inQ), nD = sum(inD), nO = sum(inO),
             QD = sum(inQ & inD), QO = sum(inQ & inO)), by = Date]
say("  월평균 제외수: Q01 %.1f / D03 %.1f / Q01⊥D03 %.1f | Jaccard(Q01,D03) %.3f | Jaccard(Q01,Q01⊥D03) %.3f",
    mean(ov$nQ), mean(ov$nD), mean(ov$nO),
    ov[, mean(QD/(nQ+nD-QD))], ov[, mean(QO/(nQ+nO-QO))])
CTL$overlap <- list(mean_excl_q01 = mean(ov$nQ), mean_excl_d03 = mean(ov$nD),
  mean_excl_orth = mean(ov$nO), jaccard_q01_d03 = ov[, mean(QD/(nQ+nD-QD))],
  jaccard_q01_orth = ov[, mean(QO/(nQ+nO-QO))])

# ── ③ advisory 배터리 ────────────────────────────────────────────────────────
say("=== ③ advisory 진단 배터리 (게이트 아님) ===")
RET <- returns_dt
ic_battery <- function(sc, nm) {
  D <- merge(sc, RET, by = c("Date","Ticker"))
  ic <- D[, {
    if (.N >= 10L && sd(score) > 0 && sd(Ret_1m) > 0) .(ic = cor(score, Ret_1m, method = "spearman"))
    else .(ic = NA_real_)
  }, by = Date][is.finite(ic)]
  mono <- D[, {
    if (.N >= 20L && sd(score) > 0) {
      q <- cut(frank(score), breaks = 5, labels = FALSE)
      .(dq = mean(Ret_1m[q==5], na.rm=TRUE) - mean(Ret_1m[q==1], na.rm=TRUE),
        m1 = mean(Ret_1m[q==1],na.rm=TRUE), m2 = mean(Ret_1m[q==2],na.rm=TRUE),
        m3 = mean(Ret_1m[q==3],na.rm=TRUE), m4 = mean(Ret_1m[q==4],na.rm=TRUE),
        m5 = mean(Ret_1m[q==5],na.rm=TRUE))
    } else .(dq=NA_real_,m1=NA_real_,m2=NA_real_,m3=NA_real_,m4=NA_real_,m5=NA_real_)
  }, by = Date]
  qm <- sapply(paste0("m",1:5), function(k) mean(mono[[k]], na.rm = TRUE))
  mono_score <- mean(diff(qm) > 0)
  sp <- ic[, .(p = fifelse(Date < as.Date("2015-01-01"), "P1_2001_2014",
               fifelse(Date < as.Date("2020-01-01"), "P2_2015_2019", "P3_2020_2026"))), by = Date]
  spm <- merge(ic, sp, by = "Date")[, .(ic_mean = mean(ic), n = .N), by = p]
  list(name = nm, n_month = nrow(ic), rank_ic = mean(ic$ic), icir = mean(ic$ic)/sd(ic$ic),
       harvey_t_stat = nw_t(ic$ic), quintile_mean_ann_pct = 100*12*qm,
       monotonicity = mono_score, subperiod = spm,
       subperiod_stability = mean(spm$ic_mean > 0))
}
specs <- list(M01_PATHQ = E[, .(Date, Ticker, score)],
              Q01_EB = FZ[F_ == "Q01_EB", .(Date, Ticker, score = fz)],
              D03_EWMA = FZ[F_ == "D03_EWMA", .(Date, Ticker, score = fz)])
bat <- lapply(names(specs), function(n) ic_battery(specs[[n]], n)); names(bat) <- names(specs)
for (n in names(bat)) {
  b <- bat[[n]]
  say("  %-10s rank_IC %+.4f  ICIR %+.3f  Harvey-t(NW) %+.2f  monotonicity %.2f  subperiod %.2f  n=%d",
      n, b$rank_ic, b$icir, b$harvey_t_stat, b$monotonicity, b$subperiod_stability, b$n_month)
  say("             분위 평균 연수익 Q1..Q5 = %s", paste(sprintf("%+.1f%%", b$quintile_mean_ann_pct), collapse = " "))
}
CTL$advisory <- lapply(bat, function(b) { b$subperiod <- as.list(b$subperiod); b })
CTL$harvey_t_specs_pass_count <- sum(sapply(bat, function(b) is.finite(b$harvey_t_stat) && b$harvey_t_stat >= 3.0))
say("  harvey_t_specs_pass_count (>=3.0) = %d / %d", CTL$harvey_t_specs_pass_count, length(bat))

# post-neutralization IC (섹터+사이즈 중립화 후 Q01)
say("--- post-neutralization IC (sector + size) ---")
NEU <- merge(FZ[F_ == "Q01_EB", .(Date, Ticker, fz)], SEC, by = c("Date","Ticker"), all.x = TRUE)
NEU <- merge(NEU, SIZEP, by = c("Date","Ticker"), all.x = TRUE)
NEU[is.na(Sector), Sector := "UNKNOWN"]
scol <- setdiff(names(SIZEP), c("Date","Ticker"))[1]
NEU[, lsz := suppressWarnings(log(pmax(get(scol), 1)))]
NEU[, fz_n := {
  ok <- is.finite(fz) & is.finite(lsz)
  r <- rep(NA_real_, .N)
  if (sum(ok) >= 30L && uniqueN(Sector[ok]) >= 2L)
    r[ok] <- residuals(lm(fz[ok] ~ lsz[ok] + factor(Sector[ok])))
  r
}, by = Date]
bn <- ic_battery(NEU[is.finite(fz_n), .(Date, Ticker, score = fz_n)], "Q01_EB_neutralized")
say("  Q01_EB post-neutral rank_IC %+.4f (raw %+.4f, retention %.2f) Harvey-t %+.2f",
    bn$rank_ic, bat$Q01_EB$rank_ic, bn$rank_ic/bat$Q01_EB$rank_ic, bn$harvey_t_stat)
CTL$post_neutralization <- list(rank_ic = bn$rank_ic, raw_rank_ic = bat$Q01_EB$rank_ic,
  retention = bn$rank_ic/bat$Q01_EB$rank_ic, harvey_t = bn$harvey_t_stat)

# DSR (진단 — chain 이라 게이트 아님). n_trials = 실제 측정 arm 수 6 (보수)
say("--- DSR (진단, chain → 게이트 부적용) ---")
dsr_of <- function(cs, n_trials) {
  pr <- as.data.table(cs$period_returns)
  a <- pr$ret_net - pr$benchmark_ret
  sr <- mean(a)/sd(a)*sqrt(12)
  .essence_dsr(sr, length(a), n_trials, skew = 0, kurt = 3, A = 12)
}
CTL$dsr <- list(base = dsr_of(cs_base, 6L), q01_q20 = dsr_of(a_q01$cs, 6L),
                q01_orth = dsr_of(a_orth$cs, 6L), d03_q20 = dsr_of(a_d03$cs, 6L),
                n_trials_used = 6L, note = "selection_type=chain → DSR 게이트 부적용(진단 산출만). n_trials=측정 arm 수 6 보수 적용")
say("  DSR base %.3f / Q01_q20 %.3f / Q01⊥D03 %.3f / D03_q20 %.3f (n_trials=6, 진단)",
    CTL$dsr$base, CTL$dsr$q01_q20, CTL$dsr$q01_orth, CTL$dsr$d03_q20)

# alpha_inheritance_cor (emitted score vs incumbent single M01)
say("--- alpha_inheritance_cor (emitted vs base M01) ---")
EMIT <- merge(E[, .(Date, Ticker, m01 = score)],
              FZ[F_ == "Q01_EB", .(Date, Ticker, q_rank)], by = c("Date","Ticker"), all.x = TRUE)
EMIT[, excluded := !is.na(q_rank) & q_rank <= Q_PRIMARY]
EMIT[, emit := fifelse(excluded, m01 - 1000, m01)]   # 제외 = 순위 최하로 강등
inh <- EMIT[, .(p = cor(emit, m01), s = cor(emit, m01, method = "spearman")), by = Date]
CTL$alpha_inheritance_cor <- list(pearson_median = median(inh$p), spearman_median = median(inh$s),
  spearman_mean = mean(inh$s))
say("  Spearman 중앙값 %.4f (Pearson %.4f) — discovery role card 기준 <0.95 대비 판정 필요",
    median(inh$s), median(inh$p))

# 후보 alpha 점수 패널 저장
ALPHA <- EMIT[, .(Date, Ticker, score = emit, m01_score = m01, excluded_by_q01 = excluded)]
write_parquet(ALPHA, file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet 저장 (%d행 / %d개월)", nrow(ALPHA), uniqueN(ALPHA$Date))

CTL$base_arm <- list(port_t = cs_base$portfolio_alpha_t_nw_lag3, net_sr = cs_base$net_sr,
  ir = cs_base$information_ratio, alpha_ann_pct = 100*cs_base$alpha_annualized,
  turnover = cs_base$turnover_annual, n_months = cs_base$n_months)
saveRDS(CTL, file.path(OUT, "wt122_control.rds"))
say("=== 통제 + 배터리 완료 → wt122_control.rds ===")
