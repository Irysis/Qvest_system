## V3 — 멤버십 잔여(30%, 월 ~1.3종)가 표본 노이즈와 구별되는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  잔여 = zone 판본 - k_t 일치 zone-free (V1 에서 {8,9,10} 2.881-2.187 = 0.694%p/yr).
##  두 arm 의 보유 겹침 0.946 이므로 잔여는 월 ~1.3종 차이에 얹혀 있다.
##   Z1 견고: 잔여 월계열의 NW3 t >= 2.0 ∧ 블록 부트스트랩(block=12, B=1000) 95% CI 가 0 을 제외
##   Z2 취약: 둘 중 하나라도 미달 → 멤버십 성분 폐기, 기전을 **적응 강도 단독**으로 확정
##  Z3 자본 자격 주장 금지
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
D[, dR := frank(-D03_EWMA, ties.method="first"), by=Date]
D[, q10D := cut(frank(D03_EWMA, ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]

COST <- 0.0015; W <- 1/25; BAD <- 8:10
ds <- sort(unique(D$Date)); SL <- lapply(ds, function(dt) D[Date==dt][order(rk)])
SL <- SL[sapply(SL,nrow) >= 60L]
cs <- function(h) sapply(seq_along(SL), function(i) {
  cur <- h[[i]]; prv <- if (i==1L) character(0) else h[[i-1]]
  u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) })
no <- function(h) sapply(seq_along(SL), function(i) mean(SL[[i]][Ticker %in% h[[i]]]$Ret_1m)) - cs(h)

kv <- sapply(SL, function(S) sum(S[seq_len(25L)]$q10D %in% BAD))
hA <- lapply(SL, function(S) S[!(q10D %in% BAD)][seq_len(min(25L,.N))]$Ticker)
hB <- lapply(seq_along(SL), function(i) {
  S <- SL[[i]]; b <- S[seq_len(25L)]; k <- kv[i]
  if (k <= 0L) return(b$Ticker)
  drop <- b[order(dR)][seq_len(min(k, nrow(b)))]$Ticker
  c(setdiff(b$Ticker, drop), head(setdiff(S$Ticker, b$Ticker), length(drop))) })
resid <- no(hA) - no(hB)
n <- length(resid)
cat(sprintf("[입력 실측] %d개월 · 잔여 연 %+.3f%%p · NW3 t = %+.3f\n",
            n, mean(resid)*12*100, .nw_t_mean(resid, lag=3L)))
cat(sprintf("  월 상이 종목수 = %.2f (겹침 %.3f)\n",
            mean(mapply(function(x,y) 25-length(intersect(x,y)), hA, hB)),
            mean(mapply(function(x,y) length(intersect(x,y))/25, hA, hB))))

# 블록 부트스트랩 (block=12)
set.seed(20260809L)
bl <- 12L; nb <- ceiling(n/bl); B_ <- 1000L
bs <- numeric(B_)
for (b in seq_len(B_)) {
  st <- sample(seq_len(n-bl+1L), nb, replace=TRUE)
  idx <- unlist(lapply(st, function(s) s:(s+bl-1L)))[1:n]
  bs[b] <- mean(resid[idx])*12*100
}
ci <- quantile(bs, c(0.025, 0.975))
tt <- .nw_t_mean(resid, lag=3L)
cat(sprintf("\n블록 부트스트랩(block=12, B=1000) 95%% CI = [%+.3f, %+.3f]%%p\n", ci[1], ci[2]))
z1 <- (tt >= 2.0) && (ci[1] > 0)
verdict <- if (z1) "Z1_MEMBERSHIP_RESIDUAL_ROBUST" else "Z2_MEMBERSHIP_RESIDUAL_FRAGILE"
cat(sprintf("\n=== 사전등록 판정 ===\nNW3 t %.3f (>=2.0? %s) · CI 하한 %+.3f (>0? %s)\n판정: %s\n★Z3: 자본 자격 주장 없음\n",
            tt, tt>=2.0, ci[1], ci[1]>0, verdict))
write_json(list(verdict=verdict, resid_ann=mean(resid)*12*100, t_nw3=tt,
                ci95=unname(ci), n_months=n),
           file.path(OUT,"v3_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
