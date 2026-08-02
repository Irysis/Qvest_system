## run_04_diagnostics.R — FQ-084 advisory 배터리 + 기전 진단(왜 게이트가 해로운가)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite);
  library(sandwich); library(lmtest)})
setDTthreads(2); try(arrow::set_io_thread_count(2), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_002"
source("02_Infrastructure/validation/statistical_defense.R")

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd <- as.data.table(SI$fwd_ret); liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
S <- as.data.table(read_parquet(file.path(TD, "gate_panel.parquet"))); S[, Date := as.Date(Date)]
AR <- readRDS(file.path(TD, "arms_results.rds"))

LIQ_MIN <- 2e8
BASE <- merge(S, liqf[, .(Date, Ticker, adv2 = adv)], by = c("Date", "Ticker"), all.x = TRUE)
BASE <- BASE[is.na(adv2) | adv2 >= LIQ_MIN][is.finite(score) & is.finite(fa_share_l0)]; BASE[, adv2 := NULL]
BASE <- merge(BASE, fwd[, .(Date, Ticker, Ret_1m)], by = c("Date", "Ticker"), all.x = TRUE)
BASE[, gate := frank(-fa_share_l0, ties.method = "first") <= ceiling(.N / 2), by = Date]

nwt <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
  m <- stats::lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1, 3]) }

## ── [1] advisory 배터리 (base 신호 — 게이트 유무별) ─────────────────────────────
ic_batt <- function(dt, lab) {
  d <- dt[is.finite(Ret_1m) & is.finite(score)]
  ics <- d[, .(ic = if (.N >= 20) cor(frank(score), frank(Ret_1m)) else NA_real_,
               n = .N), by = Date][is.finite(ic)]
  dec <- d[, {
    q <- cut(frank(score, ties.method = "first") / .N, breaks = seq(0, 1, .1), labels = FALSE, include.lowest = TRUE)
    .(dq = q, r = Ret_1m) }, by = Date][, .(mr = mean(r, na.rm = TRUE)), by = dq][order(dq)]
  mono <- mean(diff(dec$mr) > 0)
  sp <- d[, .(ic = if (.N >= 20) cor(frank(score), frank(Ret_1m)) else NA_real_), by = Date][is.finite(ic)]
  sp[, per := fifelse(Date < as.Date("2015-01-01"), "P1_2004_2014",
              fifelse(Date < as.Date("2020-01-01"), "P2_2015_2019", "P3_2020_2026"))]
  sps <- sp[, .(mean_ic = mean(ic), t = nwt(ic), n = .N), by = per][order(per)]
  stab <- min(sps$mean_ic) / max(sps$mean_ic)
  ## size-중립화 후 IC
  dz <- copy(d); dz <- merge(dz, SIZE[, .(Date, Ticker, Size)], by = c("Date", "Ticker"), all.x = TRUE)
  dz <- dz[is.finite(Size) & Size > 0]
  dz[, sc_neut := as.numeric(residuals(lm(score ~ log(Size)))), by = Date]
  icn <- dz[, .(ic = if (.N >= 20) cor(frank(sc_neut), frank(Ret_1m)) else NA_real_), by = Date][is.finite(ic)]
  list(label = lab, n_months = nrow(ics), rank_ic = mean(ics$ic), ic_sd = sd(ics$ic),
       icir = mean(ics$ic) / sd(ics$ic), ic_nw_t = nwt(ics$ic),
       monotonicity = mono, decile_means = dec$mr,
       subperiod = sps, subperiod_stability = stab,
       post_neutralization_ic = mean(icn$ic),
       post_neut_retention = mean(icn$ic) / mean(ics$ic))
}
b_all  <- ic_batt(BASE, "A_base_universe")
b_gate <- ic_batt(BASE[gate == TRUE], "B_gate_universe")
b_low  <- ic_batt(BASE[gate == FALSE], "B_gate_low_universe")
for (b in list(b_all, b_gate, b_low)) {
  cat(sprintf("\n[%s] months=%d rank_ic=%+.4f icir=%+.3f ic_NW_t=%+.2f mono=%.2f subper_stab=%.2f postneut_ic=%+.4f (ret %.2f)\n",
              b$label, b$n_months, b$rank_ic, b$icir, b$ic_nw_t, b$monotonicity,
              b$subperiod_stability, b$post_neutralization_ic, b$post_neut_retention))
  print(b$subperiod)
}

## ── [2] 기전 진단: 게이트가 무엇을 떨어뜨리는가 ────────────────────────────────
BASE[, s_rank := frank(-score, ties.method = "first"), by = Date]
top25 <- BASE[s_rank <= 25]
pass <- top25[, .(pass = mean(gate), n = .N), by = Date]
cat(sprintf("\n[기전1] A_base top-25 중 게이트 통과 비율: 평균 %.3f (월별 min %.2f / max %.2f)\n",
            mean(pass$pass), min(pass$pass), max(pass$pass)))
## 탈락 vs 통과 top-25 의 forward return 차이 (동일 스코어대 내 비교)
g <- top25[is.finite(Ret_1m), .(r_pass = mean(Ret_1m[gate], na.rm = TRUE),
                                r_drop = mean(Ret_1m[!gate], na.rm = TRUE),
                                np = sum(gate), nd = sum(!gate)), by = Date][np > 0 & nd > 0]
g[, d := r_pass - r_drop]
cat(sprintf("[기전2] top-25 내 (게이트통과 − 탈락) 월평균 수익차 = %+.4f/월 (연 %+.4f), NW t = %+.2f, months=%d\n",
            mean(g$d), mean(g$d) * 12, nwt(g$d), nrow(g)))
## 전체 유니버스에서 fa_share 자체의 forward-ret 예측력 (게이트 변수의 방향성)
fa_ic <- BASE[is.finite(Ret_1m), .(ic = cor(frank(fa_share_l0), frank(Ret_1m))), by = Date]
cat(sprintf("[기전3] fa_share 자체의 rank-IC(방향) = %+.4f  NW t = %+.2f  → 게이트 변수는 그 자체로 %s\n",
            mean(fa_ic$ic), nwt(fa_ic$ic), ifelse(mean(fa_ic$ic) < 0, "역-예측(고활동=저수익)", "순-예측")))
## 스코어-활동 교차: 활동 사분위별 IC (알파가 어디에 사는가)
BASE[, fa_q := cut(frank(fa_share_l0, ties.method = "first") / .N, breaks = seq(0, 1, .25),
                   labels = FALSE, include.lowest = TRUE), by = Date]
byq <- BASE[is.finite(Ret_1m), .(ic = if (.N >= 15) cor(frank(score), frank(Ret_1m)) else NA_real_),
            by = .(Date, fa_q)][is.finite(ic)]
qsum <- byq[, .(mean_ic = mean(ic), nw_t = nwt(ic), months = .N), by = fa_q][order(fa_q)]
cat("[기전4] 외국인활동 사분위별 base-score rank-IC (Q1=저활동 ... Q4=고활동):\n"); print(qsum)

## ── [3] DSR (진단 — chain 이므로 게이트 아님) ──────────────────────────────────
sm <- as.data.table(AR$summ)
dsr_rows <- rbindlist(lapply(c("A_base", "B_gate"), function(nm) {
  r <- sm[arm == nm & basis == "capw"]
  pr <- NULL
  d <- compute_dsr(r$net_sr, r$n_months, n_trials = 1)
  data.table(arm = nm, net_sr = r$net_sr, n_obs = r$n_months, n_trials = 1L,
             dsr = d$dsr, note = if (is.null(d$note)) "" else d$note)
}))
cat("\n[DSR — n_trials=1 (chain, 게이트 부적용·진단만)]\n"); print(dsr_rows)

## ── [4] AX-001 v2 진단 (bad/normal IC ratio) — 방어형 판정용 참고 ───────────────
bm <- as.data.table(SI$bench); setorder(bm, Date)
bm[, st := fifelse(BM_Ret < quantile(BM_Ret, 0.25), "bad", fifelse(BM_Ret > quantile(BM_Ret, 0.75), "good", "normal"))]
icd <- BASE[is.finite(Ret_1m), .(ic = cor(frank(score), frank(Ret_1m))), by = Date]
icd <- merge(icd, bm[, .(Date, st)], by = "Date")
axr <- icd[, .(mean_ic = mean(ic), n = .N), by = st]
bad_norm <- axr[st == "bad", mean_ic] / axr[st == "normal", mean_ic]
cat(sprintf("\n[AX-001 v2] bad/normal IC ratio = %.3f\n", bad_norm)); print(axr)

## ── [5] 인수인계용 alpha_scores 패널 저장 ───────────────────────────────────────
OUT <- BASE[, .(Date, Ticker, score, fa_share_l0, fa_share_l1, gate, adv, Size, Ret_1m)]
setnames(OUT, "score", "alpha_score_base")
write_parquet(OUT, file.path(TD, "alpha_scores.parquet"))
cat(sprintf("\n[SAVED] alpha_scores.parquet rows=%d months=%d\n", nrow(OUT), uniqueN(OUT$Date)))

saveRDS(list(batt_all = b_all, batt_gate = b_gate, batt_low = b_low,
             top25_pass = mean(pass$pass), top25_diff_mo = mean(g$d), top25_diff_t = nwt(g$d),
             fa_ic = mean(fa_ic$ic), fa_ic_t = nwt(fa_ic$ic), by_fa_quartile = qsum,
             dsr = dsr_rows, ax001_bad_norm = bad_norm, ax001_table = axr),
        file.path(TD, "diagnostics.rds"))
write_json(list(
  battery = list(A_base = b_all[c("rank_ic","icir","ic_nw_t","monotonicity","subperiod_stability","post_neutralization_ic","post_neut_retention","n_months")],
                 B_gate = b_gate[c("rank_ic","icir","ic_nw_t","monotonicity","subperiod_stability","post_neutralization_ic","post_neut_retention","n_months")],
                 B_gate_low = b_low[c("rank_ic","icir","ic_nw_t","monotonicity","subperiod_stability","post_neutralization_ic","post_neut_retention","n_months")]),
  mechanism = list(top25_gate_pass_rate = mean(pass$pass), top25_pass_minus_drop_monthly = mean(g$d),
                   top25_pass_minus_drop_nw_t = nwt(g$d), fa_share_own_rank_ic = mean(fa_ic$ic),
                   fa_share_own_ic_nw_t = nwt(fa_ic$ic), ic_by_fa_quartile = qsum),
  dsr = dsr_rows, ax001_v2 = list(bad_normal_ic_ratio = bad_norm, table = axr)),
  file.path(TD, "diagnostics.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("[DONE]\n")
