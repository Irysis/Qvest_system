## Z1 — Y3 수리: 규칙 구조를 T1 과 **동일 고정**(상단 연속 3 decile {8,9,10})하고 재료만 교체
## 사전등록(측정 전 고정, 이 주석이 정본):
##  Y3 는 규칙을 '성과 최하위 3 decile' 로 바꿔 D03 에서 {1,8,10} 흩어진 집합을 골랐고,
##  그 결과 **양성 대조(D03)가 t 0.776 으로 무너져** 검사가 무효였다.
##  ⇒ Z1 은 규칙을 {8,9,10} 으로 고정한다. D03 이 t~2.6 으로 재현되면 양성 대조 성립.
##   Z1a 재료-일반: D03 외 3재료 중 >=2 가 gap>0 ∧ t_gap>=2.0
##   Z1b D03 고유: 0~1 통과 (단 **양성 대조 성립 조건 하에서만** 해석)
##   Z1c 검사 무효: D03 이 t<2.0 이면 이 판본도 무효로 기록하고 원인을 다시 찾는다
##  Z1d 자본 자격 주장 금지
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

COST <- 0.0015; W <- 1/25; BAD <- 8:10           # ★T1 과 동일 고정
FILT <- c("D03_EWMA","Q01_EB","z_neutral","M01_PATHQ")
rows <- list()
for (fc in FILT) {
  D <- X[!is.na(M26_Revenue_Mom) & !is.na(get(fc))]
  D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
  D[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
  D[, qq := cut(frank(get(fc), ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
  ds <- sort(unique(D$Date)); SL <- lapply(ds, function(dt) D[Date==dt][order(rk)])
  SL <- SL[sapply(SL,nrow) >= 60L]
  cs <- function(h) sapply(seq_along(SL), function(i) {
    cur <- h[[i]]; prv <- if (i==1L) character(0) else h[[i-1]]
    u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) })
  no <- function(h) sapply(seq_along(SL), function(i) mean(SL[[i]][Ticker %in% h[[i]]]$Ret_1m)) - cs(h)
  nb <- no(lapply(SL, function(S) S[seq_len(25L)]$Ticker))
  kv <- sapply(SL, function(S) sum(S[seq_len(25L)]$qq %in% BAD))
  nf <- no(lapply(SL, function(S) S[!(qq %in% BAD)][seq_len(min(25L,.N))]$Ticker))
  M <- matrix(NA_real_, length(SL), 50L)
  for (d in 1:50) { set.seed(20260809L + 30000L + 1000L*match(fc,FILT) + d)
    M[,d] <- no(lapply(seq_along(SL), function(j) {
      S <- SL[[j]]; b <- S[seq_len(25L)]$Ticker; k <- kv[j]
      if (k <= 0L) return(b)
      c(setdiff(b, sample(b,k)), head(setdiff(S$Ticker,b), k)) })) }
  gp <- nf - rowMeans(M)
  rows[[length(rows)+1L]] <- data.table(filter_material=fc, k_mean=round(mean(kv),2), n=length(SL),
    filter_vs_base=round(mean(nf-nb)*12*100,3),
    gap=round(mean(gp)*12*100,3), t_gap=round(.nw_t_mean(gp, lag=3L),3))
}
R <- rbindlist(rows); print(R[])

pc <- R[filter_material=="D03_EWMA", t_gap]
oth <- R[filter_material != "D03_EWMA"]
hit <- sum(oth$gap > 0 & oth$t_gap >= 2.0)
verdict <- {
  if (pc < 2.0) "Z1c_TEST_INVALID_POSITIVE_CONTROL_FAILED"
  else if (hit >= 2L) "Z1a_MATERIAL_GENERAL"
  else "Z1b_D03_SPECIFIC"
}
cat(sprintf("\n=== 사전등록 판정 ===\n양성대조(D03) t = %.3f (>=2.0? %s) · 타 재료 통과 %d/3\n판정: %s\n★Z1d: 자본 자격 주장 없음\n",
            pc, pc>=2.0, hit, verdict))
fwrite(R, file.path(OUT,"z1_generalization_fixed.csv"))
write_json(list(verdict=verdict, positive_control_t=pc, hits=hit, results=R),
           file.path(OUT,"z1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
