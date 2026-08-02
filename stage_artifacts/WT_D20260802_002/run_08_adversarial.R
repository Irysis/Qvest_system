## run_08_adversarial.R — Self-Adversarial Challenge 실측 (v8.2 의무)
##  C1 분모 컨벤션 오염: Close(수정주가)×Vol(원 거래량) 혼용 → adv 분모 대체판 재측정
##  C2 구성타당도: |net| 은 '참여'가 아니라 '순불균형' — breadth 대체 지표 분포 실측
##  C3 placebo 20 draw 의 최솟값(순위 기반 단측 p)
##  C7 ★IC 사분위 기울기가 cap-tier 효과의 재표현인가 — size 5분위 내 이중정렬
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite);
  library(sandwich); library(lmtest)})
setDTthreads(2); try(arrow::set_io_thread_count(2), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_002"
source("02_Infrastructure/contracts/canonical_screen_bt.R")

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench)
liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
S <- as.data.table(read_parquet(file.path(TD, "gate_panel.parquet"))); S[, Date := as.Date(Date)]
AR <- readRDS(file.path(TD, "arms_results.rds"))
nwt <- function(x) { x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
  m <- stats::lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1, 3]) }

LIQ_MIN <- 2e8
BASE <- merge(S, liqf[, .(Date, Ticker, adv2 = adv)], by = c("Date", "Ticker"), all.x = TRUE)
BASE <- BASE[is.na(adv2) | adv2 >= LIQ_MIN][is.finite(score) & is.finite(fa_share_l0)]; BASE[, adv2 := NULL]
BASE <- merge(BASE, fwd[, .(Date, Ticker, Ret_1m)], by = c("Date", "Ticker"), all.x = TRUE)

## ── C3: placebo 최솟값 / 순위 ──────────────────────────────────────────────────
pl <- AR$placebo
b_gate <- AR$summ[arm == "B_gate" & basis == "capw", port_t]
rank_below <- sum(pl <= b_gate)
cat(sprintf("[C3 placebo] B_gate=%.3f  placebo min=%.3f  n(placebo<=B_gate)=%d/%d  → 단측 p <= %.3f\n",
            b_gate, min(pl), rank_below, length(pl), (rank_below + 1) / (length(pl) + 1)))

## ── C2: 구성타당도 — breadth(비영업일 비율) 실측 분포 ──────────────────────────
cat(sprintf("[C2 breadth] fa_breadth_l0 분포: %s\n",
            paste(sprintf("%s=%.3f", names(quantile(BASE$fa_breadth_l0, c(.05,.25,.5,.75,.95), na.rm=TRUE)),
                          quantile(BASE$fa_breadth_l0, c(.05,.25,.5,.75,.95), na.rm=TRUE)), collapse=" ")))
cat(sprintf("[C2 breadth] breadth==1.0 비율 = %.3f  → 포화도 확인(1에 가까우면 참여 판별력 없음)\n",
            mean(BASE$fa_breadth_l0 >= 0.999, na.rm = TRUE)))
cat(sprintf("[C2] fa_share vs fa_breadth 월평균 Spearman = %.3f\n",
            BASE[, .(r = cor(frank(fa_share_l0), frank(fa_breadth_l0))), by = Date][, mean(r, na.rm = TRUE)]))

## ── C1: 분모 컨벤션 대체 — adv(정본 20d 평균거래대금) 분모판 ────────────────────
## fa_share_adv = Σ|Foreign| 3m / (adv × 60)  — adv 는 liqf 정본(수정주가 혼용 문제 회피)
## Σ|Foreign| 3m 는 fa_share_l0 × tv3 로 역산 가능하나 tv3 미보존 → 재구성 대신
## 순위-동치 대체 지표: fa_share_l0 를 adv 에 대해 횡단 잔차화(분모 편향 제거 근사)
BASE[, fa_resid_adv := as.numeric(residuals(lm(frank(fa_share_l0) ~ frank(adv)))), by = Date]
half <- function(dt, var, desc = TRUE) {
  d <- copy(dt); d[, .r := frank(if (desc) -get(var) else get(var), ties.method = "first"), by = Date]
  d[, .n := .N, by = Date]; out <- d[.r <= ceiling(.n / 2)]; out[, c(".r", ".n") := NULL][] }
run1 <- function(dt, nm) {
  r <- canonical_screen_bt(dt[, .(Date, Ticker, score)], fwd, bench, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liqf, liq_min = LIQ_MIN, size_dt = NULL,
                           run_id = paste0("fq084_adv_", nm), strategy_id = paste0("FQ084_ADV_", nm),
                           diag_dual_basis = FALSE)
  r$portfolio_alpha_t_nw_lag3 }
pt_resid <- run1(half(BASE, "fa_resid_adv", TRUE), "gate_residadv")
cat(sprintf("[C1 분모대체] adv-잔차화 게이트 PORT_t = %+.3f  (원판 게이트 %+.3f / base %+.3f)\n",
            pt_resid, b_gate, AR$summ[arm == "A_base" & basis == "capw", port_t]))

## ── C7 ★: IC 기울기가 size 효과의 재표현인가 — size 5분위 내 fa 이중정렬 ────────
BASE[, sz_q := cut(frank(Size, ties.method = "first") / .N, breaks = seq(0, 1, .2),
                   labels = FALSE, include.lowest = TRUE), by = Date]
BASE[, fa_q_within := cut(frank(fa_share_l0, ties.method = "first") / .N, breaks = c(0, .5, 1),
                          labels = FALSE, include.lowest = TRUE), by = .(Date, sz_q)]
dbl <- BASE[is.finite(Ret_1m) & is.finite(sz_q) & is.finite(fa_q_within),
            .(ic = if (.N >= 15) cor(frank(score), frank(Ret_1m)) else NA_real_),
            by = .(Date, sz_q, fa_q_within)][is.finite(ic)]
dsum <- dbl[, .(mean_ic = mean(ic), nw_t = nwt(ic), months = .N), by = .(sz_q, fa_q_within)][order(sz_q, fa_q_within)]
cat("\n[C7 이중정렬] size 5분위 × 외국인활동 반분 내 base-score rank-IC (fa=1 저활동 / fa=2 고활동):\n")
print(dsum)
gapd <- dcast(dsum, sz_q ~ fa_q_within, value.var = "mean_ic")
setnames(gapd, c("1", "2"), c("ic_lowFA", "ic_highFA"))
gapd[, gap_low_minus_high := ic_lowFA - ic_highFA]
cat("[C7 요약] size 분위별 (저활동 IC − 고활동 IC):\n"); print(gapd)
## 월별 gap 시계열의 NW t (size 통제 후에도 저활동 우위가 유지되는가)
gap_ts <- dcast(dbl, Date + sz_q ~ fa_q_within, value.var = "ic")
setnames(gap_ts, c("1", "2"), c("lo", "hi"))
gap_ts <- gap_ts[is.finite(lo) & is.finite(hi)]
gm <- gap_ts[, .(g = mean(lo - hi)), by = Date]
cat(sprintf("[C7 검정] size-통제 (저활동 − 고활동) IC gap: 평균 %+.5f  NW lag-3 t = %+.2f  months=%d\n",
            mean(gm$g), nwt(gm$g), nrow(gm)))

saveRDS(list(placebo_min = min(pl), placebo_rank_below = rank_below,
             placebo_onesided_p = (rank_below + 1) / (length(pl) + 1),
             breadth_sat = mean(BASE$fa_breadth_l0 >= 0.999, na.rm = TRUE),
             pt_resid_adv = pt_resid, dbl_sort = dsum, gap_by_size = gapd,
             gap_mean = mean(gm$g), gap_nw_t = nwt(gm$g), gap_months = nrow(gm)),
        file.path(TD, "adversarial.rds"))
write_json(list(placebo = list(min = min(pl), n_below = rank_below, onesided_p = (rank_below + 1) / (length(pl) + 1)),
                breadth_saturation = mean(BASE$fa_breadth_l0 >= 0.999, na.rm = TRUE),
                gate_residualized_on_adv_port_t = pt_resid,
                double_sort = dsum, gap_by_size = gapd,
                size_controlled_gap = list(mean = mean(gm$g), nw_t = nwt(gm$g), months = nrow(gm))),
           file.path(TD, "adversarial.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("[DONE]\n")
