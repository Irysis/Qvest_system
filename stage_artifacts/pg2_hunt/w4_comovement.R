## w4 — ⓔ 재구성: 보유가 같은데 상관이 갈리면 원인은 **같은 종목의 다른 동조**다
## w2 확정: 계약 슬리브의 ON/OFF 보유 Jaccard **0.898**(타 재료 0.897과 동일) — 선별은 안 바뀐다.
## y2 확정: ON월 cov 가 전체 대비 **0.387배**로 줄고 분모(sd곱)는 0.767배 — **분자가 더 줄었다**.
## ⇒ 질문: 같은 종목을 담는데 왜 ON 월에 북과 덜 함께 움직이나.
## 후보:
##  ⓔ1 **횡단면 분산** — ON 월에 종목 간 수익 분산이 커지면 두 포트가 같은 시장에 있어도 덜 닮는다
##  ⓔ2 **보유 특성** — ON 월 보유의 size/과거수익 프로파일이 PG2 와 갈리는가
##  ⓔ3 **타 재료 대조** — 이 감소가 계약 고유인가, 소형 슬리브 일반인가(x5 는 6/8 이 방향만 같았다)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[w4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
B <- "04_Research/method_frontier/fq002_contract_magnitude"
R0 <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R0 <- R0[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
SC <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
SC <- merge(SC, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
SC[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
SC <- SC[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R0[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]

say("=== ⓔ1. 횡단면 분산: ON 월에 종목 간 수익이 더 흩어지는가 ===")
CS <- rt[, .(sd_x = sd(Ret_1m, na.rm=TRUE), iqr = IQR(Ret_1m, na.rm=TRUE),
             n = .N, med = median(Ret_1m, na.rm=TRUE)), by = Date][, m := mi(Date) + 2L]
CS <- merge(CS, LB, by = "m")
say("  %-6s %8s %10s %10s %10s", "국면", "월수", "횡단 sd", "IQR", "중앙수익")
for (g in c(TRUE, FALSE)) { s <- CS[on == g]
  say("  %-6s %8d %10.4f %10.4f %+10.4f", if (g) "ON" else "OFF", nrow(s),
      mean(s$sd_x), mean(s$iqr), mean(s$med)) }
tt <- t.test(CS[on==TRUE, sd_x], CS[on==FALSE, sd_x])
say("  ★횡단 sd 차 %+.4f · Welch t %+.3f · p %.4f → %s",
    mean(CS[on==TRUE,sd_x])-mean(CS[on==FALSE,sd_x]), tt$statistic, tt$p.value,
    if (tt$p.value < 0.05) "★유의" else "구분 안 됨")
say("  ⇒ ON 월 횡단 분산이 크면 두 포트가 같은 시장에 있어도 덜 닮는다(공통 설명)")

say("=== ⓔ2. 보유 특성: ON/OFF 보유의 size 프로파일 ===")
pick <- function(S, N=25L) S[order(Date, -score), .SD[seq_len(min(N,.N))], by=Date][, .(Date, Ticker)]
H <- pick(SC)[, m := mi(Date) + 2L]
H <- merge(H, LB, by="m")
H <- merge(H, US[, .(Date, Ticker, Size)], by=c("Date","Ticker"))
## 월내 size 백분위 (절대 크기가 아니라 상대 위치)
H[, sz_pct := frank(Size)/.N, by = Date]
UN <- merge(unique(SC[, .(Date, Ticker)]), US[, .(Date,Ticker,Size)], by=c("Date","Ticker"))
UN[, sz_pct := frank(Size)/.N, by = Date]
say("  %-6s %10s %12s %12s", "국면", "보유 size%", "유니버스 size%", "차")
for (g in c(TRUE, FALSE)) {
  s <- H[on == g]
  u <- UN[Date %in% s$Date]
  say("  %-6s %10.3f %12.3f %+12.3f", if (g) "ON" else "OFF",
      mean(s$sz_pct), mean(u$sz_pct), mean(s$sz_pct) - mean(u$sz_pct)) }
t2 <- t.test(H[on==TRUE, sz_pct], H[on==FALSE, sz_pct])
say("  ★보유 size 백분위 차 %+.4f · t %+.3f · p %.4f → %s",
    mean(H[on==TRUE,sz_pct])-mean(H[on==FALSE,sz_pct]), t2$statistic, t2$p.value,
    if (t2$p.value < 0.05) "★국면별로 다른 크기대를 담는다" else "크기대 불변")

say("=== ⓔ3. ★대조: 이 감소가 계약 고유인가 (타 재료 4종) ===")
A <- readRDS(file.path(OUT,"factor_long.rds"))
TB <- fread(file.path(OUT,"c6_full_table.csv"))
FS <- TB[is.finite(short_best)][order(short_best)][1:4, factor]
covdrop <- function(S, lab) {
  Hh <- pick(S)[, m := mi(Date) + 2L]
  G <- merge(Hh, rt, by=c("Date","Ticker"))[, .(r = mean(Ret_1m)), by = .(m)]
  Z <- merge(G, inc[, .(m, inc_act = active, bm = benchmark_ret)], by="m")
  Z[, a_s := r - bm]
  Z <- merge(Z, LB, by="m")
  if (nrow(Z[on==TRUE]) < 12) return(NULL)
  c_all <- cov(Z$a_s, Z$inc_act); c_on <- cov(Z[on==TRUE, a_s], Z[on==TRUE, inc_act])
  r_all <- cor(Z$a_s, Z$inc_act); r_on <- cor(Z[on==TRUE, a_s], Z[on==TRUE, inc_act])
  c(cov_ratio = c_on/c_all, rho_all = r_all, rho_on = r_on, drho = r_on - r_all)
}
say("  %-26s %10s %10s %10s %10s", "재료", "cov비율", "전체rho", "ON rho", "Δrho")
cc <- covdrop(SC, "계약")
say("  %-26s %10.3f %+10.3f %+10.3f %+10.3f", "★계약", cc["cov_ratio"], cc["rho_all"], cc["rho_on"], cc["drho"])
rows <- list(data.table(f="계약", t(cc)))
for (f in FS) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)][Date %in% SC$Date]
  if (!nrow(S)) next
  x <- covdrop(S, f); if (is.null(x)) next
  say("  %-26s %10.3f %+10.3f %+10.3f %+10.3f", substr(f,1,26), x["cov_ratio"], x["rho_all"], x["rho_on"], x["drho"])
  rows[[length(rows)+1L]] <- data.table(f=f, t(x))
}
R <- rbindlist(rows, fill=TRUE)
oth <- R[f != "계약"]
say("=== ★판정 ===")
say("  계약 Δrho %+.3f vs 타재료 중앙 %+.3f · 계약이 최소 %s",
    R[f=="계약", drho], median(oth$drho, na.rm=TRUE), R[f=="계약", drho] < min(oth$drho, na.rm=TRUE))
say("  계약 cov비율 %.3f vs 타재료 중앙 %.3f", R[f=="계약", cov_ratio], median(oth$cov_ratio, na.rm=TRUE))
say("  ⇒ %s", if (R[f=="계약", drho] < min(oth$drho, na.rm=TRUE))
  "★계약의 ON월 상관 감소가 타 재료보다 크다 — 재료 고유 성질 시사(설명은 여전히 미확립)" else
  "★타 재료도 비슷하게 감소 — **ON 월 자체가 상관을 낮추는 구간**이고 계약은 그 위에서 정도만 다르다")
fwrite(R, file.path(OUT,"w4_comovement.csv"))
say("=== w4 완료 ===")
