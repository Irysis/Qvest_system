## P11c — 회전 비용을 물리면 '기본값으로 켤 만하다' 가 유지되는가 (자기 결론 스트레스)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P10c: gross Δ 중앙 +5.688%p · 하위10% +1.951 · 최악 -2.077 → Y2_MOSTLY_SAFE.
##  ★그러나 밴드 arm 은 상위 13 유지 + 밴드 12 교체라 **회전이 는다**. 비용 미반영이 최대 약점.
##  측정: 두 arm 의 **월간 단방향 회전율**(이름 기준 EW) 을 실측하고
##    cost_model v2.4(15bps one-way, delta 기반)로 연율 환산해 gross Δ 에서 차감.
##    EW 25종에서 k 종목 교체 → 거래 명목 = 2k/25 (매도 k/25 + 매수 k/25) → 월 비용 = (2k/25)*15bps
##  판정 (사전 고정):
##   Z1_HOLDS      : net 하위10% >= 0  → '기본값' 결론 유지
##   Z2_WEAKENED   : net 중앙 > 0 이나 하위10% < 0 → '기본값' 철회, '계열 선별 후 사용' 으로 격하
##   Z3_RETRACTED  : net 중앙 <= 0 → P10c 결론 **철회**
##  ★음성 대조: 무밴드 arm 도 같은 방식으로 회전을 재서 **차분만** 물린다(수준 아님).
##  ★백테 아님(패널 산술). PORT_t 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
BPS <- 15/1e4

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
fam_of <- function(x){ f <- sub("^([A-Za-z]+)[0-9_].*$","\\1",x); ifelse(f==x, substr(x,1,3), f) }
probe <- as.data.table(load_month_factors(ds[floor(length(ds)/2)]))
CD <- data.table(base=sort(unique(probe$Factor_Name))); CD[, fam := fam_of(base)]
sel <- CD[, head(.SD, 3L), by=fam]$base
acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=sel), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]; if (!nrow(z)) next
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
FD <- rbindlist(acc, fill=TRUE)
U <- merge(B[, .(Date,Ticker,D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]; U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, FD, by=c("Date","Ticker"), all.x=TRUE)
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
cat(sprintf("[입력 실측] 행 %d · 월 %d · base 후보 %d\n", nrow(U), uniqueN(U$Date), length(sel)))

## arm 별 월간 보유집합 → 회전율
sets_for <- function(col, band) {
  D <- U[!is.na(get(col)) & !is.na(q) & !is.na(exc)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 120L) return(NULL)
  S <- D[, { o <- order(-get(col)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]
    keep <- tk[seq_len(min(25L-band, .N))]
    add  <- head(setdiff(tk[qq %in% 3:4], keep), band)
    .(sel = list(c(keep, add))) }, by=Date, .SDcols=c("Ticker","q",col)]
  setorder(S, Date); S
}
turnover_ann <- function(S) {                       # 단방향 이름 회전 → 연율 비용 %
  if (is.null(S) || nrow(S) < 3L) return(NA_real_)
  k <- vapply(2:nrow(S), function(i) {
    a <- S$sel[[i-1]]; b <- S$sel[[i]]
    length(setdiff(b, a)) / max(length(b), 1L) }, numeric(1))
  mean(k, na.rm=TRUE) * 2 * BPS * 12 * 100        # (매도+매수) x 15bps x 12개월 x 100(%)
}
PA <- fread(file.path(OUT, "p9c_bases.csv"))
rows <- list()
for (b in setdiff(names(FD), c("Date","Ticker"))) {
  if (!nrow(PA[base == b])) next
  S0 <- sets_for(b, 0L); S1 <- sets_for(b, 12L)
  if (is.null(S0) || is.null(S1)) next
  c0 <- turnover_ann(S0); c1 <- turnover_ann(S1)
  rows[[length(rows)+1L]] <- data.table(base=b, fam=fam_of(b),
    gross = PA[base==b, swap_all],
    cost_noband = c0, cost_band = c1, cost_delta = c1 - c0)
}
R <- rbindlist(rows, fill=TRUE)
R[, net := gross - cost_delta]
cat(sprintf("\n[대조] 무밴드 회전비용 연율 중앙 %.3f%% · 밴드 %.3f%% · **차분 중앙 %.3f%%p**\n",
            median(R$cost_noband), median(R$cost_band), median(R$cost_delta)))
q <- function(x) round(quantile(x, c(0,0.10,0.25,0.50,0.75,0.90,1), na.rm=TRUE), 3)
cat("\n=== gross ===\n"); print(q(R$gross))
cat("=== 비용 차분 ===\n"); print(q(R$cost_delta))
cat("=== net (gross - 비용차분) ===\n"); print(q(R$net))
cat(sprintf("\nnet 양수 %d/%d · net 중앙 %.3f · net 하위10%% %.3f · net 최악 %.3f\n",
            sum(R$net > 0), nrow(R), median(R$net),
            quantile(R$net, 0.10, na.rm=TRUE), min(R$net, na.rm=TRUE)))
cat("\n=== net 최악 5 ===\n"); print(R[order(net)][1:5, .(base, fam, gross=round(gross,3),
    cost_delta=round(cost_delta,3), net=round(net,3))])
p10 <- as.numeric(quantile(R$net, 0.10, na.rm=TRUE)); med <- median(R$net, na.rm=TRUE)
verdict <- if (p10 >= 0) "Z1_HOLDS" else if (med > 0) "Z2_WEAKENED" else "Z3_RETRACTED"
cat(sprintf("\n판정: %s\n", verdict))
if (verdict != "Z1_HOLDS") cat("⇒ P10c 의 '기본값으로 켤 만하다' 를 이 판정에 맞춰 **수정**할 것\n")
cat("⚠여전히 패널 산술 — PORT_t 아님. 이름-기준 회전(가중 변화 미반영)이라 비용은 **하한**\n")
fwrite(R, file.path(OUT,"p11c_net.csv"))
write_json(list(verdict=verdict, n_base=nrow(R), net_median=med, net_p10=p10,
                net_worst=min(R$net,na.rm=TRUE), n_net_positive=sum(R$net>0),
                cost_delta_median=median(R$cost_delta), results=R),
           file.path(OUT,"p11c_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
