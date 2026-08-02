# =============================================================================
# run_wt016_eval.R — WT-D20260802_016 복권형 제외-필터 x overlay(M4xR05_V5) 포함판 (FQ-111)
#   사전등록: stage_artifacts/WT_D20260802_016/preregistration.json (측정 전 고정)
#
#   base 하네스 = WT-014 run_wt014_eval.R VERBATIM (cleanT1 score_eff top-25 cap_norm(Size), 15bps)
#   overlay     = 현 book 실현 β_combined = m4_weight_lag x beta_threshold_lag x beta_R05_V5
#                 (production period_returns_layer5.csv read-only 소비, return_ym 조인만)
#   primary     = overlay-ON paired NW lag-3 t + ΔIR (필터 ON vs OFF, 양팔 동일 exposure)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_016/run_wt016_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_016")
W10 <- file.path(ROOT, "stage_artifacts/WT_D20260802_010")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt016] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
eom <- function(ym) {  # 해당 YYYY-MM의 말일
  as.Date(paste0(ym_add(ym, 1), "-01")) - 1L
}

# ── 1. 입력 로드 (WT-014 verbatim) ───────────────────────────────────────────
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench)
liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
for (dt in list(fwd_ret, bench, liqf, SIZE)) dt[, Date := as.Date(Date)]

CLEAN <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"))
CLEAN[, Date := as.Date(Date)]
stopifnot(CLEAN$vintage_verified[1] == "production_parity_verified")   # §7b

PAN <- as.data.table(read_parquet(file.path(W10, "ot_panel.parquet")))
PAN[, Date := as.Date(Date)]
MAX5 <- PAN[is.finite(max5), .(Date, Ticker, max5)]

# ── 2. parity2 경로 VERBATIM ─────────────────────────────────────────────────
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}

d0map <- data.table(d0 = sort(unique(fwd_ret$Date))); d0map[, ym := format(d0, "%Y-%m")]
CL <- copy(CLEAN); CL[, map_ym := format(Date - 1, "%Y-%m")]
CLd <- merge(CL, d0map, by.x = "map_ym", by.y = "ym")
S0 <- merge(CLd[is.finite(score_eff), .(Date = d0, Ticker, sc = score_eff)], SIZE,
            by = c("Date", "Ticker"))
S0 <- merge(S0, liqf, by = c("Date", "Ticker"), all.x = TRUE)
S0 <- S0[is.na(adv) | adv >= 2e8]

top25_capw <- function(S) {
  dd <- sort(unique(S$Date)); W <- vector("list", length(dd))
  for (i in seq_along(dd)) {
    sub <- S[Date == dd[i]]
    if (nrow(sub) < 25) next
    setorder(sub, -sc)
    hd <- head(sub, 25)
    W[[i]] <- data.table(Date = dd[i], Ticker = hd$Ticker, w = cap_norm(hd$Size))
  }
  rbindlist(W)
}

# ── 3. base anchor 재현 (§7b STOP 조건) ──────────────────────────────────────
Wb_full <- top25_capw(S0)
rb_full <- weighted_screen_bt(Wb_full, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT016_base_full", strategy_id = "WT016_base_full")
say("base anchor(268m): PORT_t=%.4f (target 3.0583) n=%d",
    rb_full$portfolio_alpha_t_nw_lag3, rb_full$n_months)
if (abs(rb_full$portfolio_alpha_t_nw_lag3 - 3.0583) > 0.01)
  stop("ANCHOR FAIL — parity 기록 3.0583 재현 실패. 측정 무효 (사전등록 STOP).")

# ── 4. paired 공통월 + 필터 (WT-014 verbatim, X=10%) ─────────────────────────
common_d0 <- sort(intersect(unique(S0$Date), unique(MAX5$Date)))
S <- S0[Date %in% common_d0]
SM <- merge(S, MAX5, by = c("Date", "Ticker"), all.x = TRUE)
mk_filter <- function(SM, X) {
  SM2 <- copy(SM)
  SM2[, thr := { v <- max5[is.finite(max5)]
                 if (length(v) >= 30L) quantile(v, 1 - X, type = 7, names = FALSE) else Inf },
      by = Date]
  SM2[, excluded := is.finite(max5) & max5 >= thr]
  SM2
}
SMx <- mk_filter(SM, 0.10)
Wb <- top25_capw(S)
Wf <- top25_capw(SMx[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
say("paired 공통월 %d (시작 %s)", length(common_d0), as.character(min(common_d0)))

# ── 5. overlay exposure 구성 (return_ym 조인만 — anchor_date 금지) ───────────
L5 <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
stopifnot(all(c("return_ym", "m4_weight_lag", "beta_threshold_lag", "beta_R05_V5") %in% names(L5)))
stopifnot(anyDuplicated(L5$return_ym) == 0)
L5[, exposure := as.numeric(m4_weight_lag) * as.numeric(beta_threshold_lag) * as.numeric(beta_R05_V5)]
EXPO <- L5[, .(return_ym, exposure, ret_L5_V5 = as.numeric(ret_L5_V5))]

d0_dt <- data.table(Date = common_d0)
d0_dt[, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]          # 홀딩월 = d0월 + 1
exp_dt <- merge(d0_dt, EXPO, by.x = "hold_ym", by.y = "return_ym", all.x = TRUE)
n_na <- exp_dt[, sum(is.na(exposure))]
say("exposure 커버: %d/%d월 (NA %d → weighted_screen_bt 규약상 1.0 처리) / e<1 월 %d (%.1f%%) / mean e = %.4f",
    nrow(exp_dt) - n_na, nrow(exp_dt), n_na,
    exp_dt[exposure < 1, .N], 100 * exp_dt[exposure < 1, .N] / nrow(exp_dt),
    exp_dt[, mean(exposure, na.rm = TRUE)])
exposure_dt <- exp_dt[, .(Date, exposure)]

# ── 6. PIT C5: assert_overlay_pit HARD + 위반 주입 실증 ──────────────────────
# 신호컷(production shift 구조): exposure(홀딩월 M)은 M-1월말 EOM까지 데이터로 결정
used_cutoff   <- eom(ym_add(exp_dt$hold_ym, -1L))   # M-1월말
holding_start <- as.Date(paste0(exp_dt$hold_ym, "-01"))
assert_overlay_pit(used_cutoff, holding_start, label = "M4xR05_V5 exposure")
say("PIT C5 PASS: 신호컷(M-1월말) < 홀딩월 시작 — %d행 전부", length(used_cutoff))
# 위반 주입: 컷오프를 M월말로 옮기면 stop() 발화해야 함 (가드 사망 검사)
inj <- tryCatch({
  assert_overlay_pit(eom(exp_dt$hold_ym), holding_start, label = "INJECTION_M_end")
  "GUARD_DEAD"
}, error = function(e) sprintf("FIRED: %s", substr(conditionMessage(e), 1, 120)))
if (identical(inj, "GUARD_DEAD")) stop("위반 주입 미발화 — overlay_pit_guard 사망. STOP (사전등록 조건).")
say("위반 주입 발화 확인: %s", inj)

# ── 7. 2x2 실측 ──────────────────────────────────────────────────────────────
run1 <- function(W, tag, ed = NULL) weighted_screen_bt(W, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = paste0("WT016_", tag), strategy_id = paste0("WT016_", tag), exposure_dt = ed)
rb  <- run1(Wb, "base_bare")
rf  <- run1(Wf, "filt_bare")
rbo <- run1(Wb, "base_ov", exposure_dt)
rfo <- run1(Wf, "filt_ov", exposure_dt)

pr_act <- function(r, nm) as.data.table(r$period_returns)[, .(date, ret = ret_net, act = ret_net - benchmark_ret)][, setnames(.SD, c("ret","act"), paste0(c("ret_","act_"), nm))]
PD <- Reduce(function(a, b) merge(a, b, by = "date"),
             list(pr_act(rb, "b"), pr_act(rf, "f"), pr_act(rbo, "bo"), pr_act(rfo, "fo")))
PD[, d_bare := act_f - act_b]
PD[, d_ov   := act_fo - act_bo]
PD[, d_int  := d_ov - d_bare]

delta_ir_bare <- rf$information_ratio - rb$information_ratio
delta_ir_ov   <- rfo$information_ratio - rbo$information_ratio
t_bare <- nw_t(PD$d_bare); t_ov <- nw_t(PD$d_ov); t_int <- nw_t(PD$d_int)

say("--- 2x2 (paired %d월) ---", nrow(PD))
cell <- function(r, nm) say("  %-12s PORT_t=%+.3f IR=%+.4f | abs: SR=%+.3f CAGR=%+.2f%% MDD=%+.1f%% | TO=%.1f%%/yr",
    nm, r$portfolio_alpha_t_nw_lag3, r$information_ratio,
    r$abs_net_sr, 100 * r$abs_cagr, 100 * r$abs_mdd, 100 * r$turnover_annual)
cell(rb, "base/bare"); cell(rf, "filt/bare"); cell(rbo, "base/OVERLAY"); cell(rfo, "filt/OVERLAY")
say("★ PRIMARY overlay-ON: paired NW t=%+.3f | ΔIR=%+.4f | Δactive %+.5f/월", t_ov, delta_ir_ov, PD[, mean(d_ov)])
say("  참조 bare(WT-014 재현): paired t=%+.3f ΔIR=%+.4f", t_bare, delta_ir_bare)
say("  상호작용(d_ov − d_bare): t=%+.3f mean=%+.5f/월", t_int, PD[, mean(d_int)])

# ── 8. 국면별 분해 (unified_regime_signal, WT-014 step 9 동일) ───────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
PD[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
PDr <- merge(PD, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
PDr <- merge(PDr, exp_dt[, .(hold_ym, exposure)], by = "hold_ym", all.x = TRUE)
reg_tab <- PDr[!is.na(Category),
  .(n = .N, mean_e = mean(exposure, na.rm = TRUE),
    mean_d_bare = mean(d_bare), t_bare = nw_t(d_bare),
    mean_d_ov = mean(d_ov), t_ov = nw_t(d_ov)), by = Category]
say("--- 국면별 Δactive (bare vs overlay-ON) ---")
for (i in seq_len(nrow(reg_tab)))
  say("  %-8s n=%3d e̅=%.2f | bare %+.5f (t %+.2f) → ov %+.5f (t %+.2f)",
      reg_tab$Category[i], reg_tab$n[i], reg_tab$mean_e[i],
      reg_tab$mean_d_bare[i], reg_tab$t_bare[i], reg_tab$mean_d_ov[i], reg_tab$t_ov[i])

# ── 9. lag1 필터 스트레스 (overlay-ON) ───────────────────────────────────────
d0_all <- sort(unique(MAX5$Date))
idx <- setNames(seq_along(d0_all), as.character(d0_all))
M5lag <- copy(MAX5)[, i := idx[as.character(Date)] + 1L][i <= length(d0_all)]
M5lag <- M5lag[, .(Date = d0_all[i], Ticker, max5)]
SMl <- mk_filter(merge(S, M5lag, by = c("Date", "Ticker"), all.x = TRUE), 0.10)
Wfl <- top25_capw(SMl[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
rflo <- run1(Wfl, "filtlag1_ov", exposure_dt)
pl <- as.data.table(rflo$period_returns)[, .(date, act_flo = ret_net - benchmark_ret)]
PDl <- merge(PD[, .(date, act_bo)], pl, by = "date")[, dl := act_flo - act_bo]
say("lag1(필터, overlay-ON): ΔIR=%+.4f paired t=%+.3f  (primary ΔIR=%+.4f t=%+.3f)",
    rflo$information_ratio - rbo$information_ratio, nw_t(PDl$dl), delta_ir_ov, t_ov)

# ── 10. exposure 타이밍 변형 (진단 병기 — 선택 사용 금지) ────────────────────
mk_expo_shift <- function(k) {  # e(M+k)를 M에 적용
  ed <- copy(exp_dt)[, hold_shift := ym_add(hold_ym, k)]
  ed <- merge(ed[, .(Date, hold_shift)], EXPO, by.x = "hold_shift", by.y = "return_ym", all.x = TRUE)
  ed[, .(Date, exposure)]
}
expo_leak <- mk_expo_shift(+1L)   # 홀딩월 말 정보(동월 누출 방향 — anchor_date 조인이 유발)
expo_lag1 <- mk_expo_shift(-1L)   # stale 1개월
res_var <- list()
for (v in list(list(nm = "leak_Mend", ed = expo_leak), list(nm = "expo_lag1", ed = expo_lag1))) {
  rbv <- run1(Wb, paste0("base_", v$nm), v$ed); rfv <- run1(Wf, paste0("filt_", v$nm), v$ed)
  pv <- merge(as.data.table(rbv$period_returns)[, .(date, ab = ret_net - benchmark_ret)],
              as.data.table(rfv$period_returns)[, .(date, af = ret_net - benchmark_ret)], by = "date")
  res_var[[v$nm]] <- list(delta_ir = rfv$information_ratio - rbv$information_ratio,
                          paired_t = nw_t(pv[, af - ab]),
                          base_port_t = rbv$portfolio_alpha_t_nw_lag3,
                          base_abs_sr = rbv$abs_net_sr)
  say("exposure 변형 %s: ΔIR=%+.4f paired t=%+.3f | base(무필터) PORT_t=%+.3f absSR=%+.3f",
      v$nm, res_var[[v$nm]]$delta_ir, res_var[[v$nm]]$paired_t,
      res_var[[v$nm]]$base_port_t, res_var[[v$nm]]$base_abs_sr)
}
ab_leak <- overlay_lookahead_ab(res_var$leak_Mend$base_abs_sr, rbo$abs_net_sr,
                                metric_name = "base absSR (leak vs strict)")
say(ab_leak$message)

# ── 11. EW top-25 dual-basis (overlay-ON) ────────────────────────────────────
ew_w <- function(W) copy(W)[, w := 1 / .N, by = Date]
rbo_ew <- run1(ew_w(Wb), "base_ew_ov", exposure_dt)
rfo_ew <- run1(ew_w(Wf), "filt_ew_ov", exposure_dt)
pe <- merge(as.data.table(rbo_ew$period_returns)[, .(date, ab = ret_net - benchmark_ret)],
            as.data.table(rfo_ew$period_returns)[, .(date, af = ret_net - benchmark_ret)], by = "date")
say("EW top-25 (overlay-ON): ΔIR=%+.4f paired t=%+.3f (base PORT_t=%+.3f filt PORT_t=%+.3f)",
    rfo_ew$information_ratio - rbo_ew$information_ratio, nw_t(pe[, af - ab]),
    rbo_ew$portfolio_alpha_t_nw_lag3, rfo_ew$portfolio_alpha_t_nw_lag3)

# ── 12. overlay 배선 parity (STOP 조건: cor < 0.95) ──────────────────────────
pp <- merge(as.data.table(rbo$period_returns)[, .(date, mine = ret_net)],
            merge(d0_dt, EXPO, by.x = "hold_ym", by.y = "return_ym")[!is.na(ret_L5_V5), .(date = Date, book = ret_L5_V5)],
            by = "date")
par_cor <- pp[, cor(mine, book)]
say("overlay parity: 내 base/OVERLAY vs book ret_L5_V5 — cor=%.4f, mean diff=%+.5f/월, n=%d",
    par_cor, pp[, mean(mine - book)], nrow(pp))
if (is.finite(par_cor) && par_cor < 0.95)
  stop(sprintf("OVERLAY PARITY FAIL — cor=%.4f < 0.95. 배선 진단 필요 (사전등록 STOP).", par_cor))

# ── 13. 저장 ─────────────────────────────────────────────────────────────────
slim <- function(r) r[setdiff(names(r), "benchmark_compare")]
saveRDS(list(
  anchor = list(target = 3.0583, observed = rb_full$portfolio_alpha_t_nw_lag3),
  cells = list(base_bare = slim(rb), filt_bare = slim(rf),
               base_ov = slim(rbo), filt_ov = slim(rfo)),
  primary = list(delta_ir_ov = delta_ir_ov, paired_t_ov = t_ov,
                 mean_d_ov = PD[, mean(d_ov)], n_months = nrow(PD)),
  bare_ref = list(delta_ir = delta_ir_bare, paired_t = t_bare),
  interaction = list(t = t_int, mean = PD[, mean(d_int)]),
  regime_tab = reg_tab,
  lag1_filter_ov = list(delta_ir = rflo$information_ratio - rbo$information_ratio,
                        paired_t = nw_t(PDl$dl)),
  expo_variants = res_var, leak_ab = ab_leak,
  ew_ov = list(base = slim(rbo_ew), filt = slim(rfo_ew),
               delta_ir = rfo_ew$information_ratio - rbo_ew$information_ratio,
               paired_t = nw_t(pe[, af - ab])),
  parity = list(cor = par_cor, mean_diff = pp[, mean(mine - book)], n = nrow(pp)),
  exposure_coverage = list(n = nrow(exp_dt), n_na = n_na,
                           n_lt1 = exp_dt[exposure < 1, .N],
                           mean_e = exp_dt[, mean(exposure, na.rm = TRUE)]),
  pit = list(assert = "PASS", injection = inj),
  paired_series = PD
), file.path(OUT, "wt016_eval_results.rds"))
say("완료 — wt016_eval_results.rds")
