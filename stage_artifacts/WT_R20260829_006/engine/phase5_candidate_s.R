## WT-R20260829_006 Phase 5 — 실투형 후보 1건 (단일 측정)
##  스코어 = TS-FMOM 이 지시하는 팩터 노출의 종목 사영
##    score_i(d) = Σ_f [sign_f(d)/σ_f(d)] · z_{f,i,d} / Σ_f (1/σ_f(d)),  f = 비-모멘텀 계열 13
##  측정 = canonical_screen_bt (계약) top-25 EW long-only · 15bps delta · liq 2e8 · Σw=1
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite);
  library(sandwich);library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
OUT <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
ART <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_R20260829_006"
dir.create(ART, recursive = TRUE, showWarnings = FALSE)

M  <- readRDS(file.path(OUT,"p1s_market.rds"))
P3 <- readRDS(file.path(OUT,"p3s_tier2.rds"))
FAMZ <- as.data.table(read_parquet(file.path(OUT,"p1s_family_z_panel.parquet")))
volm <- P3$volm; sgn <- P3$sgn; nonmom <- P3$nonmom; FW <- P3$FW
d2hm <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m")) + 1L
hm_index <- setNames(seq_len(nrow(FW)), as.character(FW$hm))

## ── 1. 계열 가중 (TS-FMOM 지시) ───────────────────────────────────────────────
Wmat <- sgn[, nonmom, drop = FALSE] / volm[, nonmom, drop = FALSE]
Wdt <- as.data.table(Wmat); Wdt[, hm := FW$hm]
## as_of 신호월(= 최신 실현월 +1) 가중 1행 확장 — 전부 t 이하 실현수익만 사용(PIT)
{
  Fm <- P3$Fm
  hm_next <- max(FW$hm) + 1L
  idx <- which(FW$hm >= hm_next - 12L & FW$hm <= hm_next - 1L)
  s_nx <- sign(colMeans(Fm[idx, nonmom, drop = FALSE], na.rm = TRUE))
  v_nx <- apply(Fm[FW$hm <= hm_next - 1L, nonmom, drop = FALSE], 2, sd, na.rm = TRUE)
  ext <- as.data.table(t(s_nx / v_nx)); ext[, hm := hm_next]
  Wdt <- rbind(Wdt, ext, use.names = TRUE)
  cat("[weights] as_of 확장 행 hm =", hm_next, " (형성창 =", min(FW$hm[idx]), "~", max(FW$hm[idx]), ")\n")
}
Wl <- melt(Wdt, id.vars = "hm", variable.name = "family", value.name = "w_raw",
           variable.factor = FALSE)[is.finite(w_raw)]
Wl[, w := w_raw / sum(abs(w_raw)), by = hm]          # Σ|w| = 1 (스코어 정규화)

FAMZ[, hm := d2hm(Date)]
S <- merge(FAMZ[family %in% nonmom], Wl[, .(hm, family, w)], by = c("hm","family"))
S[, contrib := w * z_fam]
SC <- S[, .(score = sum(contrib), n_fam = .N), by = .(Date, Ticker, hm)]
SC <- SC[n_fam >= 10]                                 # 계열 커버리지 하한
SC <- SC[hm >= 2006L*12L + 1L]
cat("[score] rows", nrow(SC), " months", uniqueN(SC$Date),
    " ", as.character(min(SC$Date)), "~", as.character(max(SC$Date)), "\n")

## ── 2. canonical_screen_bt 실측 ──────────────────────────────────────────────
LIQ <- M$LIQ_DT[, .(Date, Ticker, adv)]
data.table::setattr(LIQ, "liq_ruler", M$liq_ruler)
data.table::setattr(LIQ, "liq_ruler_source", "phase1_build_adv20_t1")
cs <- canonical_screen_bt(
  scores_dt = SC[, .(Date, Ticker, score)],
  returns_dt = M$RET_DT[, .(Date, Ticker, Ret_1m)],
  bench_dt = M$BENCH_DT[, .(Date, BM_Ret)],
  top_n = 25L, cost_bps_oneway = 15, liq_dt = LIQ, liq_min = 2e8,
  run_id = "WT-R20260829_006_TSFMOM_PROJ", strategy_id = "WT-R20260829_006_TSFMOM_PROJ",
  size_dt = M$SIZE_DT[, .(Date, Ticker, Size)])
cat("\n══════ 실투형 후보 — canonical screen ══════\n")
cat(sprintf("n_months %d | PORT_t(NW3) %.3f | p %.4f | IR %.3f | alpha_ann %.4f | net_SR %.3f | TO %.2f/yr | liq_ruler %s | sel_cov %.3f\n",
  cs$n_months, cs$portfolio_alpha_t_nw_lag3, cs$portfolio_alpha_t_pvalue,
  cs$information_ratio, cs$alpha_annualized, cs$net_sr, cs$turnover_annual,
  cs$liq_ruler, cs$selected_ret_coverage))
if (is.list(cs$diag_ew_universe))
  cat(sprintf("[diag EW-유니버스] PORT_t %.3f | post2017_t %.3f | oos_ret_approx %.3f\n",
    cs$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_,
    cs$diag_ew_universe$post2017_t_nw_lag3 %||% NA_real_,
    cs$diag_ew_universe$oos_retention_approx %||% NA_real_))
if (isTRUE(cs$diag_cap_tier$available)) { cat("[diag cap-tier]\n"); print(cs$diag_cap_tier) }

pr <- as.data.table(cs$period_returns)
bca <- beta_controlled_alpha(pr$ret_net, pr$benchmark_ret, periods_per_year = 12, nw_lag = 3L)
cat("\n══════ β-통제 α ══════\n"); str(bca)

## period_returns 저장 (신호월 라벨 + 벤치마크) — 의무 산출물
PRO <- data.table(signal_date = as.Date(pr$date),
                  signal_ym = format(as.Date(pr$date), "%Y-%m"),
                  holding_ym = format(seq_along(pr$date), justify="none"),
                  ret_net = pr$ret_net, benchmark_ret = pr$benchmark_ret,
                  active = pr$ret_net - pr$benchmark_ret)
PRO[, holding_ym := format(as.Date(paste0(format(as.Date(signal_date) + 15, "%Y-%m"), "-01")), "%Y-%m")]
fwrite(PRO, file.path(ART, "period_returns_production.csv"))
cat("[saved]", file.path(ART,"period_returns_production.csv"), nrow(PRO), "행\n")

## ── 3. Advisory 진단 배터리 ──────────────────────────────────────────────────
RM <- merge(SC[, .(Date, Ticker, score)], M$RET_DT[, .(Date, Ticker, Ret_1m)],
            by = c("Date","Ticker"))
RM <- merge(RM, M$LIQ_DT[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
RM <- RM[is.na(adv) | adv >= 2e8]
ic <- RM[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman")), n = .N), by = Date][is.finite(ic)]
rank_ic <- mean(ic$ic); icir <- rank_ic / sd(ic$ic)
ic_t <- rank_ic / (sd(ic$ic)/sqrt(nrow(ic)))
harvey_t <- ic_t / sqrt(1 + 0)   # 단일 가설주도 chain — Harvey 보정 배수 별도 기록
## 데실 단조성
RM[, dec := cut(frank(score)/.N, breaks = seq(0,1,0.1), labels = FALSE, include.lowest = TRUE), by = Date]
dec <- RM[, .(r = mean(Ret_1m)), by = .(Date, dec)][, .(mr = mean(r)), by = dec][order(dec)]
mono <- cor(dec$dec, dec$mr, method = "spearman")
## subperiod 안정성 (IC)
ic[, per := fifelse(Date < as.Date("2015-01-01"), "P1",
             fifelse(Date < as.Date("2020-01-01"), "P2", "P3"))]
sub <- ic[, .(ic = mean(ic), n = .N), by = per][order(per)]
sub_stab <- min(sub$ic) / max(abs(sub$ic))
## size 중립화 후 IC
SZ <- M$SIZE_DT[, .(Date, Ticker, lsz = log(pmax(Size,1)))]
RN <- merge(RM, SZ, by = c("Date","Ticker"))
RN[, sc_n := { f <- lm(score ~ lsz); residuals(f) }, by = Date]
icn <- RN[, .(ic = suppressWarnings(cor(sc_n, Ret_1m, method = "spearman"))), by = Date][is.finite(ic)]
post_neut_ic <- mean(icn$ic)
cat(sprintf("\n[진단] rank_IC %.4f · ICIR %.3f · IC t %.2f · 단조성 %.3f · 부기간 %s · post-neutral IC %.4f\n",
  rank_ic, icir, ic_t, mono, paste(sprintf("%s=%.4f", sub$per, sub$ic), collapse=" "), post_neut_ic))
print(dec)

## DSR (진단 — 가설주도 chain 이므로 게이트 아님)
sr <- mean(pr$ret_net - pr$benchmark_ret)/sd(pr$ret_net - pr$benchmark_ret)
n <- nrow(pr); g3 <- mean(scale(pr$ret_net-pr$benchmark_ret)^3); g4 <- mean(scale(pr$ret_net-pr$benchmark_ret)^4)
sr_star <- 0
dsr <- pnorm(((sr - sr_star)*sqrt(n-1))/sqrt(1 - g3*sr + (g4-1)/4*sr^2))
cat(sprintf("[진단] 월 SR %.4f · DSR(단일시행, SR*=0) %.4f · n_trials(chain) 1\n", sr, dsr))

## ── 4. α̂ 벡터 (as_of = 최신 신호월, forward 미실현) ──────────────────────────
source("02_Infrastructure/factor_db/factor_db_connector.R")
AS_OF <- max(M$ME)
cat("\n[alpha_vector] as_of =", as.character(AS_OF), "\n")
z_last <- as.data.table(load_month_factors(AS_OF, dedup = TRUE))
FAMMAP <- fread(file.path(OUT,"p1s_family_map.csv"))
FAMMAP <- FAMMAP[!is.na(family)]
z_last <- merge(z_last, FAMMAP, by = "Factor_Name")
uu <- M$UNIV_DT[Date == AS_OF, .(Ticker)]
lq <- M$LIQ_DT[Date == AS_OF, .(Ticker, adv)]
keep <- merge(uu, lq, by = "Ticker", all.x = TRUE)[is.na(adv) | adv >= 2e8, .(Ticker)]
z_last <- z_last[Ticker %in% keep$Ticker & is.finite(Z_Score_Aligned)]
fz_last <- z_last[family %in% nonmom, .(z_fam = mean(Z_Score_Aligned), k = uniqueN(Factor_Name)),
                  by = .(Ticker, family)]
hm_as <- d2hm(AS_OF)
wl <- Wl[hm == hm_as, .(family, w)]
if (nrow(wl) == 0) stop("as_of 가중 부재")
sl <- merge(fz_last, wl, by = "family")
SL <- sl[, .(score = sum(w*z_fam), n_fam = .N, k_tot = sum(k)), by = Ticker][n_fam >= 10]
cat("[alpha_vector] n tickers =", nrow(SL), " 계열 가중 n =", nrow(wl), "\n")

## score → 기대초과수익 환산: 확장창 Fama-MacBeth 기울기 (PIT — as_of 까지)
fm <- RM[, { f <- lm(Ret_1m ~ score); .(b = coef(f)[2]) }, by = Date]
fm_slope <- mean(fm$b, na.rm = TRUE)
fm_se <- sd(fm$b, na.rm = TRUE)/sqrt(nrow(fm))
cat(sprintf("[alpha_vector] FM 기울기 평균 %.5f (SE %.5f, t %.2f, n=%d 월)\n",
            fm_slope, fm_se, fm_slope/fm_se, nrow(fm)))
## ③ Uncertainty-aware: 하한 추정 μ̃ = μ̂ − k·SE (k=1)
fm_lb <- fm_slope - 1.0*fm_se
SL[, alpha_hat := fm_lb * score]
SL[, alpha_hat_point := fm_slope * score]

## confidence: 계열 커버리지 + 스코어 순위 안정성 + 부기간 IC 안정성
rk_hist <- SC[Date >= max(SC$Date) - 200, .(Date, Ticker, score)]
rk_hist[, rk := frank(score)/.N, by = Date]
stab <- rk_hist[, .(sd_rk = sd(rk), n = .N), by = Ticker]
SL <- merge(SL, stab, by = "Ticker", all.x = TRUE)
SL[, conf_cov := pmin(1, n_fam/13)]
SL[, conf_stab := fifelse(is.na(sd_rk), 0.4, pmax(0, 1 - pmin(1, sd_rk/0.35)))]
SL[, confidence := round(pmax(0, pmin(1, 0.35*conf_cov + 0.35*conf_stab +
                                       0.30*max(0, min(1, sub_stab)))), 4)]
setorder(SL, -score)
cat("[alpha_vector] top 8:\n"); print(head(SL[, .(Ticker, score, alpha_hat, confidence)], 8))

## alpha_scores.parquet — 전 기간 스코어 + as_of 층
AS <- rbind(
  SC[, .(Date, Ticker, score, layer = "history")],
  SL[, .(Date = AS_OF, Ticker, score, layer = "as_of")])
write_parquet(AS, file.path(ART, "alpha_scores.parquet"))
cat("[saved]", file.path(ART,"alpha_scores.parquet"), nrow(AS), "행\n")

res <- list(
  canonical = list(metric_type = cs$metric_type, n_months = cs$n_months,
    portfolio_alpha_t_nw_lag3 = cs$portfolio_alpha_t_nw_lag3,
    portfolio_alpha_t_pvalue = cs$portfolio_alpha_t_pvalue,
    information_ratio = cs$information_ratio, alpha_annualized = cs$alpha_annualized,
    net_sr = cs$net_sr, turnover_annual = cs$turnover_annual,
    liq_ruler = cs$liq_ruler, selected_ret_coverage = cs$selected_ret_coverage,
    top_n = 25L, cost_bps_oneway = 15,
    diag_ew_universe = cs$diag_ew_universe, diag_cap_tier = cs$diag_cap_tier),
  beta_controlled = bca,
  diagnostics = list(rank_ic = rank_ic, icir = icir, ic_t = ic_t, harvey_t = harvey_t,
    monotonicity = mono, subperiod = as.list(setNames(sub$ic, sub$per)),
    subperiod_stability = sub_stab, post_neutralization_ic = post_neut_ic,
    decile_profile = dec, monthly_sr_active = sr, dsr = dsr, n_trials = 1L),
  alpha_vector_meta = list(as_of = as.character(AS_OF), n_tickers = nrow(SL),
    fm_slope_mean = fm_slope, fm_slope_se = fm_se, fm_slope_lower_bound_k1 = fm_lb,
    n_fm_months = nrow(fm)),
  alpha_table = SL[, .(Ticker, score, alpha_hat, alpha_hat_point, confidence, n_fam)],
  as_of_weights = wl
)
saveRDS(res, file.path(OUT,"p5s_candidate.rds"))
write(toJSON(res, auto_unbox=TRUE, pretty=TRUE, digits=8, na="null"), file.path(OUT,"p5s_candidate.json"))
cat("\n[done] phase5\n")
