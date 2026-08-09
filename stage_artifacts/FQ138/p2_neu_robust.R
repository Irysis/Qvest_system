## FQ-138 P2 — ★양성 결과 자가 적대검증 (보고 전 필수)
## 혐의 1: NEU 가 **단일 무작위 추출**이다(월 ~57종목 중 25종). NEU 잡음이 DiD 를 만들 수 있다.
##         ⇒ POOL_EW(결정적) + 무작위 50회 평균으로 재산출.
## 혐의 2: 위약 20회 중 2회(10%)가 |t|>=2 — 기대 5% 대비 높다. 200회로 확장.
## 혐의 3: canonical_screen_bt 가 **68건 물리불가 월수익**을 격리했다는 경고 — 패널 위생 확인.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ138")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

B <- "04_Research/method_frontier/fq002_contract_magnitude"
R  <- as.data.table(read_parquet(file.path(B, "gridx_returns.parquet")))[, Date := as.Date(Date)]
BM <- as.data.table(read_parquet(file.path(B, "gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B, "gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B, "panelx_A.parquet")))[, ym := as.integer(ym)]

say("=== 혐의 3: 물리불가 월수익 68건 정체 ===")
bad <- R[Ret_1m > 5.0 | Ret_1m < -1.0]
say("  |Ret_1m|>5 또는 <-1 : %d건 / %d (%.3f%%)", nrow(bad), nrow(R), 100*nrow(bad)/nrow(R))
if (nrow(bad)) {
  say("  분포: 최대 %.2f · 최소 %.2f · 연도별:", max(bad$Ret_1m), min(bad$Ret_1m))
  print(bad[, .N, by = .(yr = format(Date, "%Y"))][order(yr)])
  say("  ★계약 신호 유니버스와 겹치는가:")
}
R <- R[!(Ret_1m > 5.0 | Ret_1m < -1.0)]     # 계약함수와 동일 격리
say("  격리 후 %d행", nrow(R))

me <- data.table(Date = sort(unique(R$Date)))[, ym := as.integer(format(Date, "%Y%m"))]
S <- merge(me, PA[, .(ym, Ticker, w_amt)], by = "ym", allow.cartesian = TRUE)
S <- merge(S, US[, .(Date, Ticker, Size)], by = c("Date","Ticker"))
S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
S <- S[is.finite(score) & score > 0, .(Date, Ticker, score)]
rt <- R[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
bd <- BM[, .(Date, BM_Ret)]
say("  신호 풀: %d행 · 월중앙 %d종목", nrow(S), as.integer(median(S[, .N, by=Date]$N)))

SZ <- merge(R[, .(Date, Ticker, Ret_1m)], US[, .(Date, Ticker, Size)], by = c("Date","Ticker"))
MSv <- SZ[!is.na(Size), { o <- order(-Size); .(ms = mean(Ret_1m[head(o,10)]) - median(Ret_1m)) }, by = Date][order(Date)]
MSv[, regime := shift(ms, 1L) <= 0]
say("  국면 ON %d / %d (%.1f%%)", sum(MSv$regime, na.rm=TRUE), nrow(MSv), 100*mean(MSv$regime, na.rm=TRUE))

runp <- function(sc, tag) {
  r <- suppressWarnings(canonical_screen_bt(sc, rt, bd, top_n = 25L, cost_bps_oneway = 15,
        run_id = tag, strategy_id = tag, diag_dual_basis = FALSE))
  as.data.table(r$period_returns)[, .(date, act = ret_net - benchmark_ret)]
}
hac <- function(y, x, lag = 3L) {
  n <- length(y); X <- cbind(1, as.numeric(x)); b <- solve(crossprod(X), crossprod(X, y))
  e <- as.numeric(y - X %*% b); Xi <- solve(crossprod(X)); Sm <- crossprod(X*e)
  for (l in seq_len(lag)) { w <- 1 - l/(lag+1)
    G <- crossprod((X*e)[(l+1):n,,drop=FALSE], (X*e)[1:(n-l),,drop=FALSE]); Sm <- Sm + w*(G+t(G)) }
  V <- Xi %*% Sm %*% Xi; c(b = as.numeric(b)[2], se = sqrt(diag(V))[2])
}
did <- function(sig, neu) {
  M <- merge(sig, neu, by = "date", suffixes = c("_s","_n"))
  M[, s := act_s - act_n]
  M <- merge(M, MSv[, .(date = Date, regime)], by = "date")[!is.na(regime)]
  h <- hac(M$s, M$regime, 3L); c(delta = h[1], se = h[2], t = h[1]/h[2], n = nrow(M))
}

SIG <- runp(S, "SIG")
say("=== 혐의 1: NEU 구성 민감도 ===")
## (a) POOL_EW — 결정적 대조(풀 전체 동일가중). score 를 상수로 주면 top_n 이 임의 25종이 되므로
##     풀 전체 EW 를 직접 계산한다(계약함수 대신 — 이는 성과지표가 아니라 대조군 구성).
POOL <- merge(S[, .(Date, Ticker)], rt, by = c("Date","Ticker"))
POOL <- POOL[, .(pool = mean(Ret_1m)), by = Date]
POOL <- merge(POOL, bd, by.x = "Date", by.y = "Date")[, .(date = Date, act = pool - BM_Ret)]
d_pool <- did(SIG, POOL)
say("  (a) POOL_EW 대조 : delta %+.5f/월 (연 %+.2f%%) · t %+.3f · n %d",
    d_pool[1], d_pool[1]*12*100, d_pool[3], d_pool[4])
## (b) 무작위 25종 50회
set.seed(7); ds <- matrix(NA_real_, 50, 3)
for (b in 1:50) {
  NS <- copy(S)[, score := runif(.N), by = Date]
  ds[b, ] <- did(SIG, runp(NS, sprintf("NEU%02d", b)))[1:3]
}
say("  (b) 무작위 25종 50회 : delta 중앙 %+.5f (연 %+.2f%%) · t 중앙 %+.3f · t 5~95%% [%+.2f, %+.2f]",
    median(ds[,1]), median(ds[,1])*12*100, median(ds[,3]), quantile(ds[,3],.05), quantile(ds[,3],.95))
say("  ★t 가 항상 문턱 위인가: |t|>=2 비율 %.2f · t>0 비율 %.2f",
    mean(abs(ds[,3]) >= 2), mean(ds[,3] > 0))

say("=== 혐의 2: 위약 확장 200회 ===")
NEU_fix <- POOL
set.seed(99); pl <- numeric(0)
for (b in 1:200) {
  PS <- copy(S)[, score := sample(score), by = Date]
  pl <- c(pl, did(runp(PS, sprintf("PL%03d", b)), NEU_fix)[3])
}
say("  위약 200회 DiD t : 중앙 %+.3f · sd %.3f · |t|>=2 비율 **%.3f** · q95 %+.3f · 최대 %+.3f",
    median(pl), sd(pl), mean(abs(pl) >= 2), quantile(pl, .95), max(abs(pl)))
say("  ★실측 delta t (POOL 대조) = %+.3f · 위약 분포 대비 백분위 %.3f",
    d_pool[3], mean(pl <= d_pool[3]))
say("  ⇒ p_one(위약 기준) = %.4f", mean(pl >= d_pool[3]))

saveRDS(list(d_pool = d_pool, rand = ds, placebo = pl, n_bad = nrow(bad)), file.path(OUT, "p2.rds"))
say("=== P2 완료 ===")

## ---- ★혐의 4 (P2 중 발견) — 2026 오염 구간 의존성 ---------------------------
## 물리불가 월수익 68건 중 **63건이 2026**(최대 152.85 = +15,285%). 오늘 확인한 2026 벤치 결함의
## 종목-계열 판본이다. FQ-138 국면은 2026 에 ON 이므로 양성 결과가 오염 산물일 수 있다.
say("=== ★혐의 4: 2026 오염 구간 의존성 (P2 중 발견) ===")
cut_did <- function(cut_date, lab) {
  s2 <- SIG[date < as.Date(cut_date)]; n2 <- POOL[date < as.Date(cut_date)]
  d <- did(s2, n2)
  say("  %-22s : delta %+.5f/월 (연 %+.2f%%) · t %+.3f · n %d", lab, d[1], d[1]*12*100, d[3], d[4])
  d
}
d_all  <- did(SIG, POOL)
say("  %-22s : delta %+.5f/월 (연 %+.2f%%) · t %+.3f · n %d", "전구간(2026 포함)",
    d_all[1], d_all[1]*12*100, d_all[3], d_all[4])
d_2026 <- cut_did("2026-01-01", "★2026 제외")
d_2025 <- cut_did("2025-01-01", "2025 이후도 제외")
say("  ★2026 제외 시 delta 변화: 연 %+.2f%% -> %+.2f%% (%.1f%% 잔존) · t %+.3f -> %+.3f",
    d_all[1]*12*100, d_2026[1]*12*100, 100*d_2026[1]/d_all[1], d_all[3], d_2026[3])
say("  ⇒ %s", if (abs(d_2026[3]) >= 2 && sign(d_2026[1]) == sign(d_all[1]))
  "★2026 없이도 생존 — 오염 산물 아님" else "★★2026 의존 — 결과 보류")

## 국면 ON 월의 연도 분포 (오염 구간에 몰려 있나)
onm <- MSv[regime %in% TRUE, .(Date)]
say("  국면 ON %d개월의 연도 분포:", nrow(onm))
print(onm[, .N, by = .(yr = format(Date, "%Y"))][order(yr)])
saveRDS(list(d_all = d_all, d_2026 = d_2026, d_2025 = d_2025), file.path(OUT, "p2_cut.rds"))
say("=== 혐의 4 완료 ===")
