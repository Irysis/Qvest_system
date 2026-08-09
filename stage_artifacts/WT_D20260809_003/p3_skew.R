## WT-D20260809_003 P3 — rank-IC ↔ 평균-프로파일 불일치의 기전 검정
## 예측은 p3_prediction.json 에 측정 전 고정 (H1/H2/H3 + 반증조건 F1/F2)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_003")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

B <- readRDS(file.path(OUT, "merged_panel.rds"))
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
X <- merge(B, as.data.table(P$ret)[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, as.data.table(P$liq)[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
X <- X[is.na(adv) | adv >= 2e8]
say("1급 프레임 패널 %d행 · %d개월 (유동성필터 적용)", nrow(X), uniqueN(X$Date))

skew1 <- function(v) { v <- v[is.finite(v)]; n <- length(v)
  if (n < 3) return(NA_real_); s <- sd(v); if (!is.finite(s) || s == 0) return(NA_real_)
  sum((v - mean(v))^3) / n / s^3 }

deep <- function(D, k) {
  D <- D[!is.na(get(k))]
  D[, nmo := .N, by = Date]; D <- D[nmo >= 50L]
  D[, dec := cut(frank(get(k), ties.method = "first"),
                 breaks = quantile(seq_len(.N), probs = seq(0, 1, 0.1)),
                 include.lowest = TRUE, labels = FALSE), by = Date]
  D[, umean := mean(Ret_1m), by = Date]
  D[, umed  := median(Ret_1m), by = Date]
  M <- D[, .(mn = mean(Ret_1m) - umean[1], md = median(Ret_1m) - umed[1]), by = .(Date, dec)]
  ## 종목-수준 왜도·급락비율은 전체 pool 에서 (월-평균 아님)
  G <- D[, .(skew = skew1(Ret_1m), crash = mean(Ret_1m < -0.20, na.rm = TRUE),
             n = .N), by = dec]
  R <- M[, .(mean_ann = mean(mn) * 12 * 100, mean_t = .nw_t_mean(mn, lag = 3L),
             med_ann = mean(md) * 12 * 100,  med_t = .nw_t_mean(md, lag = 3L),
             n_months = .N), by = dec]
  R <- merge(R, G, by = "dec")[order(dec)]
  R[, gap := mean_ann - med_ann]
  R
}

cols <- c("D03_EWMA", "M26_Revenue_Mom", "Q01_EB", "M01_PATHQ")
out <- list(); sm <- list()
for (k in cols) {
  R <- deep(X, k); out[[k]] <- R
  sp_mean <- suppressWarnings(cor(R$dec, R$mean_ann, method = "spearman"))
  sp_med  <- suppressWarnings(cor(R$dec, R$med_ann,  method = "spearman"))
  sp_gap  <- suppressWarnings(cor(R$dec, R$gap,      method = "spearman"))
  sp_skew <- suppressWarnings(cor(R$dec, R$skew,     method = "spearman"))
  say("=== %s ===", k)
  say("  dec  mean_ann  (t)    med_ann  (t)     gap    skew   crash%%")
  for (i in seq_len(nrow(R)))
    say("  D%-2d %+8.2f %+6.2f  %+8.2f %+6.2f  %+7.2f  %+6.2f  %5.2f",
        R$dec[i], R$mean_ann[i], R$mean_t[i], R$med_ann[i], R$med_t[i],
        R$gap[i], R$skew[i], R$crash[i] * 100)
  say("  spearman(dec, mean) %+.3f | (dec, median) %+.3f | (dec, gap) %+.3f | (dec, skew) %+.3f",
      sp_mean, sp_med, sp_gap, sp_skew)
  sm[[length(sm) + 1L]] <- data.table(material = k, sp_mean = sp_mean, sp_med = sp_med,
                                       sp_gap = sp_gap, sp_skew = sp_skew,
                                       gap_D1 = R$gap[1], gap_D10 = R$gap[10],
                                       crash_D1 = R$crash[1], crash_D10 = R$crash[10])
}
S <- rbindlist(sm)

say("=== ★예측 판정 (p3_prediction.json 고정분) ===")
d03 <- S[material == "D03_EWMA"]; m26 <- S[material == "M26_Revenue_Mom"]
h1 <- d03$sp_med >= 0.50
h2 <- d03$sp_gap <= -0.50
h3 <- !(m26$sp_gap <= -0.50 && m26$sp_med < m26$sp_mean - 0.3)
say("  H1 D03 중앙값 프로파일 상향(spearman>=+0.50): %+.3f -> %s", d03$sp_med, h1)
say("  H2 D03 (평균-중앙값) 격차가 decile 따라 감소(spearman<=-0.50): %+.3f -> %s", d03$sp_gap, h2)
say("  H3 M26 에서는 패턴 부재/약함 (음성 대조): sp_gap %+.3f · sp_med %+.3f -> %s",
    m26$sp_gap, m26$sp_med, h3)
say("  F1 반증(D03 중앙값도 하향): %s", d03$sp_med < 0)
say("  F2 반증(M26 도 동일 강도): %s", (m26$sp_gap <= -0.50 && m26$sp_med >= 0.50 && m26$sp_mean < 0))
verdict <- if (d03$sp_med < 0) "MECHANISM_REFUTED_F1" else
           if (h1 && h2 && h3) "MECHANISM_SUPPORTED" else
           if (h1 && h2 && !h3) "MECHANISM_SUPPORTED_BUT_NOT_D03_SPECIFIC" else "PARTIAL"
say("  ★판정: %s", verdict)

saveRDS(list(profiles = out, summary = S, verdict = verdict), file.path(OUT, "p3_results.rds"))
fwrite(S, file.path(OUT, "p3_skew_summary.csv"))
fwrite(rbindlist(lapply(names(out), function(k) cbind(material = k, out[[k]]))),
       file.path(OUT, "p3_decile_detail.csv"))
say("=== P3 완료 ===")
