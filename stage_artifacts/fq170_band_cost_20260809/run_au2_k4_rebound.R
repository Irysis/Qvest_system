## AU2 — AS2 의 k=4 반등(0.472 → 0.657)이 노이즈인가 분기 효과인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AS2 감쇠 프로파일: k=1 1.000 · k=2 0.704 · k=3 0.472 · **k=4 0.657** · k=5 0.620 · k=6 0.310.
##  가설: k=4 반등이 **분기 실적발표 주기**(3개월)와 정합하면 리밸 타이밍이 새 축이다.
##  검정 3축 (전부 사전 고정):
##   ① 편입월 캘린더 분해 — 편입 시점의 달(월 1~12)을 분기 경계(3/6/9/12)와 그 외로 나눠
##      k별 프로파일을 따로 낸다. 분기 효과면 **경계 편입분에서만 k=4 반등**이 나타나야 한다.
##   ② 무작위 대조 — 같은 코호트 구조로 무작위 25종을 담아 k별 프로파일을 낸다(20 draw).
##      반등이 무작위에서도 나오면 이 재료 성질이 아니라 시장 구조/계절이다.
##   ③ 유의성 — k=4 의 t 가 k=3 보다 유의하게 높은지 paired 로 검정(같은 달 쌍).
##   AX1 분기 효과: ①에서 경계 편입분만 반등 ∧ ②에서 무작위 반등 없음 → 리밸 타이밍 축 개방
##   AX2 노이즈: ③ paired 비유의 ∧ ②에서 무작위도 반등 → 주기 축 폐쇄 유지
##   AX3 시장 구조: ②에서 무작위도 반등 → 재료 무관 계절성, 이 arm 의 축 아님
##  AX4 자본 자격 주장 없음
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
D <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
D <- merge(D, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
D <- D[is.na(adv) | adv >= 2e8]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q  := cut(frank(D03_EWMA, ties.method="first"),
              breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
              include.lowest=TRUE, labels=FALSE), by=Date]
ds <- sort(unique(D$Date))
BMv <- bench[Date %in% ds][order(Date)]$BM_Ret
RET <- ret[Date %in% ds]; setkey(RET, Date, Ticker)
cat(sprintf("[입력 실측] %d개월\n", length(ds)))

sel <- lapply(seq_along(ds), function(i) {
  S <- D[Date == ds[i]][order(rk)]
  keep <- S[seq_len(min(13L, .N))]$Ticker
  pool <- S[q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(12L,.N))]$Ticker
  c(keep, pool) })
mo <- as.integer(format(ds, "%m"))
bnd <- mo %in% c(3L,6L,9L,12L)

coh <- function(sels, k, idx) {
  ex <- numeric(0); wh <- integer(0)
  for (i in idx) { j <- i + k - 1L; if (j > length(ds)) next
    r <- RET[.(ds[j], sels[[i]]), on=.(Date,Ticker), nomatch=0L]
    if (nrow(r) < 20L) next
    ex <- c(ex, mean(r$Ret_1m) - BMv[j]); wh <- c(wh, i) }
  list(ex = ex, idx = wh)
}
cat("\n=== ① 편입월 분해 (분기경계 3/6/9/12 vs 그 외) ===\n")
prof <- function(idx, lab) {
  v <- sapply(1:6, function(k) { z <- coh(sel,k,idx)$ex; if (!length(z)) NA_real_ else mean(z)*12*100 })
  cat(sprintf("  %-10s [%s]  k4/k3 = %.3f\n", lab, paste(sprintf("%+6.2f", v), collapse=" "), v[4]/v[3]))
  v
}
v_b <- prof(which(bnd),  "분기경계"); v_o <- prof(which(!bnd), "그 외")
v_a <- prof(seq_along(ds), "전체")

cat("\n=== ② 무작위 대조 (20 draw) ===\n")
rv <- matrix(NA_real_, 6L, 20L)
for (d in 1:20) { set.seed(20260809L + 31000L + d)
  rs <- lapply(seq_along(ds), function(i) { S <- D[Date == ds[i]]; S[sample(.N, min(25L,.N))]$Ticker })
  rv[,d] <- sapply(1:6, function(k) { z <- coh(rs,k,seq_along(ds))$ex; if (!length(z)) NA_real_ else mean(z)*12*100 }) }
rm_ <- rowMeans(rv, na.rm=TRUE)
cat(sprintf("  무작위     [%s]  k4/k3 = %.3f\n", paste(sprintf("%+6.2f", rm_), collapse=" "), rm_[4]/rm_[3]))

cat("\n=== ③ k=4 vs k=3 paired (같은 편입월) ===\n")
c3 <- coh(sel,3,seq_along(ds)); c4 <- coh(sel,4,seq_along(ds))
common <- intersect(c3$idx, c4$idx)
d34 <- c4$ex[match(common, c4$idx)] - c3$ex[match(common, c3$idx)]
t34 <- .nw_t_mean(d34, lag=3L)
cat(sprintf("  n=%d · 차이 연 %+.3f%%p · NW3 t = %+.3f\n", length(d34), mean(d34)*12*100, t34))

rand_rebound <- is.finite(rm_[4]/rm_[3]) && (rm_[4] > rm_[3])
bnd_only <- (v_b[4] > v_b[3]) && !(v_o[4] > v_o[3])
verdict <- {
  if (bnd_only && !rand_rebound) "AX1_QUARTER_EFFECT"
  else if (rand_rebound) "AX3_MARKET_SEASONALITY"
  else if (abs(t34) < 2.0) "AX2_NOISE"
  else "AX_MIXED"
}
cat(sprintf("\n판정: %s\n★AX4: 자본 자격 주장 없음\n", verdict))
write_json(list(verdict=verdict, boundary=v_b, other=v_o, all=v_a, random=rm_,
                paired_t_k4_k3=t34, n_paired=length(d34)),
           file.path(OUT,"au2_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
