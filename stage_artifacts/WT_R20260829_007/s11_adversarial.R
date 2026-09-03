# S11 — Self-Adversarial Challenge 의 정량 근거 (진술 대신 재도출)
#  W7 : in-house KR MKT 팩터가 mandate 벤치와 같은 것을 재는가 + **팩터 라벨 정렬** 점검
#  W7b: 전략 FF3/Carhart4 를 홀딩월 라벨로 재산출 (S5c 는 신호월 라벨)
#  W8 : 15bps x 회전율의 실제 잠식폭 + 손익분기 bps
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O5b <- readRDS(file.path(OUT, "s5b_objects.rds"))
pr <- O5b$pr_s; PRD <- O5b$PRD

fdt <- local({ source(file.path(ROOT, "02_Infrastructure/factor_portfolios.R"), local = TRUE)
               as.data.table(load_kr_factor_returns()) })
fdt[, ym := format(as.Date(Date), "%Y-%m")]

## ★라벨 정렬: pr$date 는 신호월 말이고 수익은 다음 캘린더월에 실현된다.
hold_ym <- format(as.Date(vapply(as.Date(pr$date), function(d)
  as.character(seq(as.Date(format(d, "%Y-%m-01")), by = "month", length.out = 2)[2]), character(1))), "%Y-%m")
B <- data.table(ym = hold_ym, ym_signal = format(as.Date(pr$date), "%Y-%m"),
                bm = pr$benchmark_ret, r = pr$ret_net)
J <- merge(B, fdt[, .(ym, MKT, RF, SMB, HML, WML)], by = "ym")
J <- J[is.finite(MKT) & is.finite(bm) & is.finite(RF)][, bm_x := bm - RF]
Js <- merge(B[, .(ym = ym_signal, bm, r)], fdt[, .(ym, MKT, RF, SMB, HML, WML)], by = "ym")
Js <- Js[is.finite(MKT) & is.finite(bm) & is.finite(RF)][, bm_x := bm - RF]

fa <- lm(bm_x ~ MKT, data = J); fs <- lm(bm_x ~ MKT, data = Js)
w7 <- list(
  n_months_aligned = nrow(J), n_months_signal_label = nrow(Js),
  aligned_holding_month = list(cor = cor(J$bm_x, J$MKT), beta = unname(coef(fa)[2]),
    alpha_ann_pct = 100*12*unname(coef(fa)[1]), alpha_t = unname(summary(fa)$coefficients[1,3]),
    adj_r2 = summary(fa)$adj.r.squared),
  signal_month_label = list(cor = cor(Js$bm_x, Js$MKT), beta = unname(coef(fs)[2]),
    alpha_ann_pct = 100*12*unname(coef(fs)[1]), alpha_t = unname(summary(fs)$coefficients[1,3]),
    adj_r2 = summary(fs)$adj.r.squared),
  mean_ann_bm_excess_pct = 100*12*mean(J$bm_x), mean_ann_MKT_pct = 100*12*mean(J$MKT),
  reading = "mandate 벤치의 초과수익을 in-house MKT 로 회귀한다. 정렬판에서 beta 가 1 근처·상관이 높으면 두 시장 대리가 같은 것을 재는 것이고, 어긋남판과의 차이가 라벨 정렬이 만들어내는 가짜 alpha 의 크기다.")
cat(sprintf("[W7] 정렬(홀딩월)  cor=%+.4f beta=%.3f alpha=%+.2f%%/yr (t %+.3f) adjR2=%.3f\n",
  w7$aligned_holding_month$cor, w7$aligned_holding_month$beta, w7$aligned_holding_month$alpha_ann_pct,
  w7$aligned_holding_month$alpha_t, w7$aligned_holding_month$adj_r2))
cat(sprintf("[W7] 어긋남(신호월) cor=%+.4f beta=%.3f alpha=%+.2f%%/yr (t %+.3f) adjR2=%.3f | 평균 bm_excess %+.2f%%/yr vs MKT %+.2f%%/yr\n",
  w7$signal_month_label$cor, w7$signal_month_label$beta, w7$signal_month_label$alpha_ann_pct,
  w7$signal_month_label$alpha_t, w7$signal_month_label$adj_r2,
  w7$mean_ann_bm_excess_pct, w7$mean_ann_MKT_pct))

## W7b — 전략 FF3/Carhart4 를 두 라벨로 각각
nwv <- function(f) NeweyWest(f, lag = max(1L, floor(nobs(f)^(1/3))), prewhite = FALSE)
gt <- function(f) { ct <- coeftest(f, vcov = nwv(f))
  list(alpha_ann_pct = 100*12*ct[1,1], alpha_t = ct[1,3],
       loadings = setNames(as.list(round(ct[-1,1], 4)), rownames(ct)[-1]),
       adj_r2 = summary(f)$adj.r.squared, n = nobs(f)) }
J[, r_x := r - RF]; Js[, r_x := r - RF]
w7b <- list(
  aligned_holding_month = list(FF3 = gt(lm(r_x ~ MKT + SMB + HML, data = J)),
                               Carhart4 = gt(lm(r_x ~ MKT + SMB + HML + WML, data = J))),
  signal_month_label = list(FF3 = gt(lm(r_x ~ MKT + SMB + HML, data = Js)),
                            Carhart4 = gt(lm(r_x ~ MKT + SMB + HML + WML, data = Js))),
  s5c_reported = "S5c 의 FF3 +15.59%/yr (t 3.178) / Carhart4 +14.83%/yr (t 3.042) 는 run_multifactor_regression 에 **신호월 라벨** xts 를 넘겨 산출됐다.",
  reading = "라벨 하나로 FF alpha 가 크게 달라지면 S5c 값은 알파가 아니라 정렬 아티팩트다.")
cat(sprintf("[W7b] 정렬 FF3 %+.2f%%/yr (t %+.3f) adjR2 %.3f MKT로딩 %.3f | Carhart4 %+.2f%%/yr (t %+.3f) WML로딩 %.3f\n",
  w7b$aligned_holding_month$FF3$alpha_ann_pct, w7b$aligned_holding_month$FF3$alpha_t,
  w7b$aligned_holding_month$FF3$adj_r2, w7b$aligned_holding_month$FF3$loadings$MKT,
  w7b$aligned_holding_month$Carhart4$alpha_ann_pct, w7b$aligned_holding_month$Carhart4$alpha_t,
  w7b$aligned_holding_month$Carhart4$loadings$WML))
cat(sprintf("[W7b] 어긋남 FF3 %+.2f%%/yr (t %+.3f) adjR2 %.3f MKT로딩 %.3f\n",
  w7b$signal_month_label$FF3$alpha_ann_pct, w7b$signal_month_label$FF3$alpha_t,
  w7b$signal_month_label$FF3$adj_r2, w7b$signal_month_label$FF3$loadings$MKT))

## W8 — 비용이 실제로 구속하는가
gross_act <- PRD$ret_gross - PRD$benchmark_ret
nwt <- function(x) { m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
sens <- lapply(c(0, 5, 10, 15, 25, 40), function(bps) {
  a <- PRD$ret_gross - PRD$traded_notional*bps/1e4 - PRD$benchmark_ret
  list(cost_bps = bps, active_ann_pct = 100*12*mean(a), nw_t = nwt(a), net_sr = mean(a)/sd(a)*sqrt(12)) })
be <- 1e4*mean(gross_act)/mean(PRD$traded_notional)
w8 <- list(
  turnover_annual_two_sided = 12*mean(PRD$traded_notional),
  turnover_annual_one_way = 6*mean(PRD$traded_notional),
  cost_drag_ann_pct = 100*12*mean(PRD$cost),
  gross_active_ann_pct = 100*12*mean(gross_act), net_active_ann_pct = 100*12*mean(PRD$active_net),
  cost_share_of_gross_active = mean(PRD$cost)/mean(gross_act),
  breakeven_cost_bps_oneway = be, cost_sensitivity = sens,
  reading = "손익분기 편도 bps 가 현행 15bps 에 가까울수록 '회전율이 급소' 라는 주장이 강해진다. 멀면 급소는 회전율이 아니라 신호 자체다.")
cat(sprintf("[W8] 회전율 양방향 %.2f/yr (편도 %.2f) | 비용 %.2f%%/yr = gross 활성 %.2f%%/yr 의 %.1f%% | 손익분기 %.1f bps(편도)\n",
  w8$turnover_annual_two_sided, w8$turnover_annual_one_way, w8$cost_drag_ann_pct,
  w8$gross_active_ann_pct, 100*w8$cost_share_of_gross_active, be))
for (x in sens) cat(sprintf("      %2dbps -> 활성 %+6.2f%%/yr NW-t %+6.3f netSR %+6.3f\n",
                            x$cost_bps, x$active_ann_pct, x$nw_t, x$net_sr))

write_json(list(
  meta = list(wt_id = "WT-R20260829_007", purpose = "Self-Adversarial Challenge 의 정량 근거 — 진술이 아니라 재도출"),
  W7_inhouse_MKT_vs_mandate_bench = w7,
  W7b_factor_model_label_alignment = w7b,
  W8_cost_binding_check = w8),
  file.path(OUT, "s11_adversarial.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S11] done\n")
