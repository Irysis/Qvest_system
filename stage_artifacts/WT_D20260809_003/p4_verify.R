## WT-D20260809_003 P4 — 자가 적대검증: P3 기전이 '유니버스 차감' 인공물인가
## 혐의 1: gap = (dec mean - univ mean) - (dec med - univ med). 차감항이 패턴을 만들 수 있다 -> 생(raw) 값으로 재확인
## 혐의 2: D10(저변동)이 crash 0.54% 인데 평균이 최악(-5.12%) = 표면 모순 -> 꼬리를 직접 본다
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_003")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

B <- readRDS(file.path(OUT, "merged_panel.rds"))
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
X <- merge(B, as.data.table(P$ret)[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
X <- merge(X, as.data.table(P$liq)[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
X <- X[is.na(adv) | adv >= 2e8]
say("패널 %d행 · %d개월", nrow(X), uniqueN(X$Date))

dec <- function(D, k) {
  D <- D[!is.na(get(k))]; D[, nmo := .N, by = Date]; D <- D[nmo >= 50L]
  D[, dd := cut(frank(get(k), ties.method = "first"),
                breaks = quantile(seq_len(.N), probs = seq(0, 1, 0.1)),
                include.lowest = TRUE, labels = FALSE), by = Date]
  D
}

say("=== 혐의 1: 유니버스 차감 없는 생(raw) decile 평균 vs 중앙값 ===")
for (k in c("D03_EWMA", "M26_Revenue_Mom")) {
  D <- dec(X, k)
  M <- D[, .(mn = mean(Ret_1m), md = median(Ret_1m)), by = .(Date, dd)]
  R <- M[, .(mean_ann = mean(mn) * 12 * 100, med_ann = mean(md) * 12 * 100), by = dd][order(dd)]
  R[, gap := mean_ann - med_ann]
  say("  --- %s (생값, 차감 없음) ---", k)
  say("    dec  mean_ann  med_ann     gap")
  for (i in seq_len(nrow(R)))
    say("    D%-2d %+8.2f %+8.2f %+8.2f", R$dd[i], R$mean_ann[i], R$med_ann[i], R$gap[i])
  say("    spearman(dec,mean) %+.3f | (dec,median) %+.3f | (dec,gap) %+.3f",
      cor(R$dd, R$mean_ann, method = "spearman"),
      cor(R$dd, R$med_ann, method = "spearman"),
      cor(R$dd, R$gap, method = "spearman"))
}

say("=== 혐의 2: D03 decile 별 수익 분포 꼬리 직접 관찰 ===")
D <- dec(X, "D03_EWMA")
Q <- D[, .(p01 = quantile(Ret_1m, 0.01), p05 = quantile(Ret_1m, 0.05),
           p50 = median(Ret_1m), p95 = quantile(Ret_1m, 0.95),
           p99 = quantile(Ret_1m, 0.99), mn = mean(Ret_1m),
           sd = sd(Ret_1m), n = .N), by = dd][order(dd)]
say("  dec     p01     p05     p50     p95     p99    mean      sd     n")
for (i in seq_len(nrow(Q)))
  say("  D%-2d %+7.3f %+7.3f %+7.3f %+7.3f %+7.3f %+7.4f %7.4f %6d",
      Q$dd[i], Q$p01[i], Q$p05[i], Q$p50[i], Q$p95[i], Q$p99[i], Q$mn[i], Q$sd[i], Q$n[i])
say("  ★D1 sd %.4f vs D10 sd %.4f (배수 %.2f) — D03 정렬 방향 확인용",
    Q[dd == 1, sd], Q[dd == 10, sd], Q[dd == 1, sd] / Q[dd == 10, sd])

say("=== 혐의 3: 월별 평균이 소수 극단월에 끌리는가 (D10 평균 -5.12%% 의 출처) ===")
M10 <- D[dd == 10, .(mn = mean(Ret_1m)), by = Date][order(mn)]
MU  <- D[, .(u = mean(Ret_1m)), by = Date]
Z <- merge(M10, MU, by = "Date")[, ex := mn - u][order(ex)]
say("  D10 초과수익 최악 5개월: %s",
    paste(sprintf("%s %+.3f", format(head(Z$Date, 5)), head(Z$ex, 5)), collapse = " · "))
say("  전체 평균 초과 %+.5f/월 · 최악 5개월 제외 시 %+.5f/월 (연 %+.2f%% -> %+.2f%%)",
    mean(Z$ex), mean(Z$ex[-(1:5)]), mean(Z$ex) * 12 * 100, mean(Z$ex[-(1:5)]) * 12 * 100)
say("  중앙값 기준 월초과 %+.5f · 양(+)월 비율 %.3f", median(Z$ex), mean(Z$ex > 0))
say("  ★해석: 양월 비율이 0.5 이상인데 평균이 음수면 = **소수 극단 음수월 지배** = 평균/순위 괴리의 시계열 판본")

saveRDS(list(tails = Q, d10_months = Z), file.path(OUT, "p4_results.rds"))
say("=== P4 완료 ===")
