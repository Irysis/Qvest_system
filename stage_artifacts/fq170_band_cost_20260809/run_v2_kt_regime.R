## V2 — 적응 강도 k_t 자체가 국면 신호인가 (소비면 전환 검정)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  k_t = 그 달 북(top-25 by M26) 종목 중 D03 나쁜구역{8,9,10} 에 걸린 수.
##  V1 이 적응 강도를 주기전(70%)으로 확정했으므로 k_t 가 무엇에 반응하는지 묻는다.
##   X1 국면 신호: k_t 와 **동월 유니버스 수익** 또는 **익월 유니버스 수익** 상관이 |rho|>=0.15 ∧ p<0.05
##      → k_t 는 국면 지표. 오버레이 입력 소비면 개방.
##   X2 무정보: 둘 다 미달 → k_t 는 구성 잡음. 오버레이 전환 근거 없음.
##  ★익월(forward) 이 핵심이다 — 동월 상관은 동시성이라 예측이 아니다. PIT 상 익월만 소비 가능.
##  X3 자본 자격 주장 금지
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X <- merge(X, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
D <- X[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q10D := cut(frank(D03_EWMA, ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]

K <- D[rk <= 25L, .(k_t = sum(q10D %in% 8:10)), by=Date][order(Date)]
U <- D[, .(univ = mean(Ret_1m)), by=Date][order(Date)]
M <- merge(K, U, by="Date")
M[, univ_fwd := shift(univ, -1L)]              # 익월 (PIT 상 소비 가능한 방향)
M[, k_sd := (k_t - mean(k_t))/sd(k_t)]
cat(sprintf("[입력 실측] %d개월 · k_t 평균 %.2f · sd %.2f · 범위 %d~%d\n",
            nrow(M), mean(M$k_t), sd(M$k_t), min(M$k_t), max(M$k_t)))

ct <- cor.test(M$k_t, M$univ, method="spearman", exact=FALSE)
Mf <- M[!is.na(univ_fwd)]
cf <- cor.test(Mf$k_t, Mf$univ_fwd, method="spearman", exact=FALSE)
cat(sprintf("\n동월  rho = %+.3f (p %.4f)\n익월  rho = %+.3f (p %.4f)  ★소비 가능 방향\n",
            ct$estimate, ct$p.value, cf$estimate, cf$p.value))

# k_t 상/하위 3분위별 익월 수익 (해석 보조)
Mf[, kb := cut(frank(k_t, ties.method="first"),
               breaks=quantile(seq_len(.N), probs=c(0,1/3,2/3,1)), include.lowest=TRUE, labels=FALSE)]
prof <- Mf[, .(n=.N, k_mean=round(mean(k_t),2),
               fwd_ann=round(mean(univ_fwd)*12*100,2)), by=kb][order(kb)]
cat("\n=== k_t 3분위별 익월 유니버스 수익 ===\n"); print(prof[])

x1 <- (abs(cf$estimate) >= 0.15 && cf$p.value < 0.05)
x1_same <- (abs(ct$estimate) >= 0.15 && ct$p.value < 0.05)
verdict <- if (x1) "X1_KT_IS_FORWARD_REGIME_SIGNAL" else if (x1_same) "X1b_CONTEMPORANEOUS_ONLY" else "X2_NO_INFORMATION"
cat(sprintf("\n=== 사전등록 판정 ===\n판정: %s\n★X3: 자본 자격 주장 없음\n", verdict))
write_json(list(verdict=verdict,
                rho_same=unname(ct$estimate), p_same=ct$p.value,
                rho_fwd=unname(cf$estimate), p_fwd=cf$p.value, profile=prof),
           file.path(OUT,"v2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
fwrite(M, file.path(OUT,"v2_kt_series.csv"))
