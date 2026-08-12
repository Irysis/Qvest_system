## Y3 — 3단 진술이 **재료-일반**인가, D03 고유 성질인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  현재 base x 필터 = M26 x D03 1쌍뿐. 필터 재료를 바꿔(Q01_EB · z_neutral · M01_PATHQ) 재현 시험.
##  각 필터 재료의 '나쁜 구역' = 그 재료의 decile 프로파일에서 **하위 성과 3분위**(사전 규칙:
##    프로파일 산출 → ann 기준 최하위 3개 decile). 재료마다 위치가 다르므로 규칙으로 고정한다.
##   Y3a 재료-일반: 3재료 중 >=2 가 gap > 0 ∧ t_gap >= 2.0  → 필터 기전이 재료-일반
##   Y3b D03 고유: 0~1 재료만 통과 → D03 고유 성질로 좁힘
##  Y3c 자본 자격 주장 금지 · base 는 M26 고정(사후선택 전제는 P1 소관)
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

COST <- 0.0015; W <- 1/25
FILT <- c("D03_EWMA","Q01_EB","z_neutral","M01_PATHQ")
rows <- list()
for (fc in FILT) {
  D <- X[!is.na(M26_Revenue_Mom) & !is.na(get(fc))]
  D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
  D[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
  D[, qq := cut(frank(get(fc), ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
  # 사전 규칙: 그 재료의 decile 프로파일에서 성과 최하위 3 decile = 나쁜 구역
  D[, univ := mean(Ret_1m), by=Date]
  pr <- D[, .(ex=mean(Ret_1m)-univ[1]), by=.(Date,qq)][, .(ann=mean(ex)), by=qq][order(ann)]
  BAD <- sort(pr$qq[1:3])
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
  for (d in 1:50) { set.seed(20260809L + 40000L + 1000L*match(fc,FILT) + d)
    M[,d] <- no(lapply(seq_along(SL), function(j) {
      S <- SL[[j]]; b <- S[seq_len(25L)]$Ticker; k <- kv[j]
      if (k <= 0L) return(b)
      c(setdiff(b, sample(b,k)), head(setdiff(S$Ticker,b), k)) })) }
  gp <- nf - rowMeans(M)
  rows[[length(rows)+1L]] <- data.table(filter_material=fc, bad_zone=paste(BAD, collapse=","),
    k_mean=round(mean(kv),2), n=length(SL),
    filter_vs_base=round(mean(nf-nb)*12*100,3),
    gap=round(mean(gp)*12*100,3), t_gap=round(.nw_t_mean(gp, lag=3L),3))
}
R <- rbindlist(rows); print(R[])

oth <- R[filter_material != "D03_EWMA"]
hit <- sum(oth$gap > 0 & oth$t_gap >= 2.0)
verdict <- if (hit >= 2L) "Y3a_MATERIAL_GENERAL" else "Y3b_D03_SPECIFIC"
cat(sprintf("\n=== 사전등록 판정 ===\nD03 외 재료 통과 %d/3\n판정: %s\n★Y3c: 자본 자격 주장 없음\n", hit, verdict))
fwrite(R, file.path(OUT,"y3_generalization.csv"))
write_json(list(verdict=verdict, hits=hit, results=R),
           file.path(OUT,"y3_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
