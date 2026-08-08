# p11_conditioning_axis.R — E3: 조건화 축 직접 대조 (시장 전체 vs 보유종목)
# 가설(D3 파생): 9종 시장상태 신호가 실패하고 R05_z 만 작동한 이유는 신호 재료가 아니라
#   **조건화 대상** — 시장 집계가 아니라 '내가 들고 있는 종목의 위험 특성'이 신호였다.
# 시험: 동일 팩터를 두 방식으로 집계해 판별력을 직접 대조.
#   (a) market  = 그 달 유니버스 전체 평균 z
#   (b) port    = 그 달 실제 보유 20종목 평균 z   ← production overlay 가 쓰는 방식
# 채점 = 경제 기준(발화월 평균 sleeve 수익 · β≤0.5 적용 시 dSR/dMDD) + 분류 보조.
# ★PIT: load_month_factors(정본 C15 경로) + align_factor_direction. 보유종목은 캐리어 실측.
suppressMessages({ library(data.table); library(arrow); library(dplyr); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
BPS <- 0.0015
FACTORS <- c("R05_Tail_Risk", "D01_IdioVol", "R12_Beta", "L01_Amihud", "Q07_Earnings_Stability")

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
E <- merge(R[, .(decision_date, eval_date, regime, gross=gA, turn=tA)],
           unique(car[, .(decision_date, invested)]), by="decision_date")
setorder(E, decision_date)
hold <- car[, .(decision_date, Ticker)]
reg <- .load_registry()

agg <- rbindlist(lapply(seq_len(nrow(E)), function(i) {
  dd <- E$decision_date[i]
  f <- tryCatch(load_month_factors(dd, factor_names = FACTORS), error = function(e) NULL)
  if (is.null(f) || !nrow(f)) return(NULL)
  if ("Coverage" %in% names(f)) f <- f[Coverage == TRUE]
  f <- f[is.finite(Z_Score)]
  if (!nrow(f)) return(NULL)
  f_in <- copy(f)[, sig_date := dd]        # align_factor_direction 이 입력을 참조 변형 → 사본 전달
  fa <- tryCatch(align_factor_direction(f_in, reg, sig_date = dd, min_ic_months = 12L),
                 error = function(e) copy(f))
  fa <- as.data.table(fa)
  zcol <- if ("Z_Score_Aligned" %in% names(fa)) "Z_Score_Aligned" else "Z_Score"
  hk <- hold[decision_date == dd, Ticker]
  out <- fa[, .(mkt = mean(get(zcol), na.rm=TRUE),
                port = if (length(hk)) mean(get(zcol)[Ticker %in% hk], na.rm=TRUE) else NA_real_,
                n_port = sum(Ticker %in% hk)), by = Factor_Name]
  out[, decision_date := dd][]
}), fill = TRUE)
cat(sprintf("[집계] %d행 | 월 %d | 팩터 %s\n", nrow(agg), uniqueN(agg$decision_date),
            paste(sort(unique(agg$Factor_Name)), collapse=",")))
cat(sprintf("[보유 매칭] 월평균 보유종목 중 팩터 커버 %.1f개\n", mean(agg$n_port, na.rm=TRUE)))

base_x <- xts(E$gross*E$invested - BPS*E$turn*E$invested, order.by=E$eval_date)
bt <- table.AnnualizedReturns(base_x, scale=12, Rf=0)
base_SR <- as.numeric(bt[3,1]); base_MDD <- as.numeric(maxDrawdown(base_x))*100
cat(sprintf("[기준선] SR %.3f · MDD %.2f%%\n", base_SR, base_MDD))

expq <- function(x,p,mn=36L) sapply(seq_along(x), function(i) if (i<=mn) NA_real_ else quantile(x[1:(i-1)],p,names=FALSE,na.rm=TRUE))
score <- function(fire, lbl) {
  fire[is.na(fire)] <- FALSE
  if (sum(fire) < 5) return(NULL)
  inv2 <- pmin(E$invested, ifelse(fire, 0.50, 1)); inv2 <- pmin(inv2, E$invested)
  net2 <- E$gross*inv2 - BPS*E$turn*inv2
  x2 <- xts(net2, order.by=E$eval_date); t2 <- table.AnnualizedReturns(x2, scale=12, Rf=0)
  tt <- t.test(E$gross[fire], E$gross[!fire])
  data.table(signal=lbl, 발화=sum(fire), 발화월평균=round(100*mean(E$gross[fire]),2),
             미발화평균=round(100*mean(E$gross[!fire]),2), t=round(as.numeric(tt$statistic),2),
             p=round(tt$p.value,4), dSR=round(as.numeric(t2[3,1])-base_SR,3),
             dMDD=round(as.numeric(maxDrawdown(x2))*100-base_MDD,2))
}
rows <- list()
for (fn in sort(unique(agg$Factor_Name))) {
  a <- agg[Factor_Name == fn]
  D <- merge(E[, .(decision_date)], a[, .(decision_date, mkt, port)], by="decision_date", all.x=TRUE)
  setorder(D, decision_date)
  for (ax in c("mkt","port")) {
    v <- D[[ax]]
    if (sum(is.finite(v)) < 60) next
    q <- expq(v, 0.20)
    rows[[length(rows)+1L]] <- score(is.finite(q) & is.finite(v) & v <= q,
                                     sprintf("%s [%s]", fn, ifelse(ax=="mkt","시장전체","보유종목")))
  }
}
out <- rbindlist(Filter(Negate(is.null), rows))
setorder(out, -dSR)
cat("\n===== 조건화 축 대조 (하위 q20 발화 → β≤0.5) =====\n"); print(out)
out[, axis := ifelse(grepl("보유종목", signal), "보유종목", "시장전체")]
cat("\n[축별 요약]\n")
print(out[, .(신호수=.N, 평균dSR=round(mean(dSR),3), 평균dMDD=round(mean(dMDD),2),
              발화월평균수익=round(mean(발화월평균),2), dSR양수=sum(dSR>0)), by=axis])
fwrite(out, "stage_artifacts/tilt_realign_20260808/p11_conditioning_axis.csv")
