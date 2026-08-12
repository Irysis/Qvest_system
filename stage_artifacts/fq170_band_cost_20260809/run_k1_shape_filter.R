## K1 — 형태를 **필터**로 소비 (랭킹 축 미달 후 소비 경로 전환)
## 사전등록: preregistration_k1.json (측정 전 작성)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
PRE <- fromJSON(file.path(OUT,"preregistration_k1.json"), simplifyVector=FALSE)
cat(sprintf("[prereg] 규칙 %d개 고정\n", length(PRE$decision_rules_fixed_before_results)))

B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X <- merge(X, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
D <- X[!is.na(M26_Revenue_Mom) & !is.na(Q01_EB) & !is.na(D03_EWMA)]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
cat(sprintf("[입력 실측] %d행 · %d개월 (3재료 공통 커버)\n", nrow(D), uniqueN(D$Date)))

D[, rk   := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q5Q  := cut(frank(Q01_EB, ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=6L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
D[, q10D := cut(frank(D03_EWMA, ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
D[, bad_Q  := q5Q %in% c(1L,5L)]          # HUMP 양 극단
D[, bad_D  := q10D %in% c(9L,10L)]        # INVERTED 상단
D[, bad_B  := bad_Q | bad_D]

COST <- 0.0015; W <- 1/25
ds <- sort(unique(D$Date))
pick <- function(S, badcol) { S[get(badcol) == FALSE][order(rk)][seq_len(min(25L,.N))]$Ticker }

hold <- list(base=list(), fQ=list(), fD=list(), fB=list())
kdrop <- list(fQ=numeric(0), fD=numeric(0), fB=numeric(0))
retm  <- list()
for (dt in ds) {
  S <- D[Date == dt][order(rk)]
  if (nrow(S) < 60L) next
  b  <- S[seq_len(25L)]$Ticker
  k  <- as.character(as.Date(dt))
  hold$base[[k]] <- b
  hold$fQ[[k]]   <- pick(S, "bad_Q"); hold$fD[[k]] <- pick(S, "bad_D"); hold$fB[[k]] <- pick(S, "bad_B")
  kdrop$fQ <- c(kdrop$fQ, sum(S[seq_len(25L)]$bad_Q))
  kdrop$fD <- c(kdrop$fD, sum(S[seq_len(25L)]$bad_D))
  kdrop$fB <- c(kdrop$fB, sum(S[seq_len(25L)]$bad_B))
  retm[[k]] <- S
}
dsk <- names(hold$base)
rmap <- function(k, tk) { S <- retm[[k]]; mean(S[Ticker %in% tk]$Ret_1m) }
cost_of <- function(h) { sapply(seq_along(dsk), function(i) {
  cur <- h[[dsk[i]]]; prv <- if (i==1L) character(0) else h[[dsk[i-1]]]
  u <- unique(c(cur,prv)); COST*sum(abs(W*(u %in% cur) - W*(u %in% prv))) }) }
netof <- function(h) sapply(seq_along(dsk), function(i) rmap(dsk[i], h[[dsk[i]]])) - cost_of(h)

n_base <- netof(hold$base)
res <- list()
for (nm in c("fQ","fD","fB")) {
  dn <- netof(hold[[nm]]) - n_base
  bar <- required_effect(length(dn), t_threshold=2.0, series=dn)
  res[[nm]] <- data.table(arm=nm, k_drop=mean(kdrop[[nm]]),
                          net_ann=mean(dn)*12*100, t_net=.nw_t_mean(dn, lag=3L),
                          bar_ann=bar$required_annual*100)
}
# ── 무작위 통제: 같은 k 를 무작위 제외 후 refill, 20 draw ────────────────────
rand_ann <- numeric(20L); rand_series <- matrix(NA_real_, length(dsk), 20L)
for (d in 1:20) {
  set.seed(20260809L + 100L + d)
  h <- list()
  for (i in seq_along(dsk)) {
    k <- dsk[i]; S <- retm[[k]]; kk <- kdrop$fB[i]
    b <- S[seq_len(25L)]$Ticker
    if (kk > 0L) {
      drop <- sample(b, kk); pool <- setdiff(S[order(rk)]$Ticker, b)
      b <- c(setdiff(b, drop), head(pool, kk))
    }
    h[[k]] <- b
  }
  rand_series[, d] <- netof(h) - n_base
  rand_ann[d] <- mean(rand_series[, d])*12*100
}
rc <- rowMeans(rand_series)
res[["rand"]] <- data.table(arm="rand_control", k_drop=mean(kdrop$fB),
                            net_ann=mean(rc)*12*100, t_net=.nw_t_mean(rc, lag=3L),
                            bar_ann=NA_real_)
R <- rbindlist(res)
R[, (setdiff(names(R),"arm")) := lapply(.SD, function(z) round(z,3)), .SDcols=setdiff(names(R),"arm")]
print(R[]); cat(sprintf("\nrand draw sd = %.3f%%p (20 draw)\n", sd(rand_ann)))

hit <- R[arm %in% c("fQ","fD","fB") & net_ann > 0 & t_net >= 2.0]
beats_rand <- nrow(hit) > 0 && any(hit$net_ann > R[arm=="rand_control", net_ann])
l3 <- R[arm=="rand_control", t_net] >= 2.0 && R[arm=="rand_control", net_ann] > 0
verdict <- {
  if (nrow(hit) > 0 && beats_rand && !l3) "L1_SHAPE_FILTER_SUPPORTED"
  else if (l3) "L3_NOT_INFORMATION_SIMPLE_SWAP"
  else "L2_CONFIG_SCOPED_NEGATIVE"
}
cat(sprintf("\n=== 사전등록 판정 ===\n필터 arm 문턱 통과 %d/3 · 무작위 통제 초과 %s\n판정: %s\n★L5: 자본 자격 주장 없음\n",
            nrow(hit), beats_rand, verdict))
fwrite(R, file.path(OUT,"k1_shape_filter_summary.csv"))
write_json(list(round_id=PRE$round_id, verdict=verdict, results=R, rand_draw_sd=sd(rand_ann)),
           file.path(OUT,"k1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
