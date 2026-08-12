## P13b — FAM_C 의 t_bd 3.101 은 '20 중 최대' 프리미엄인가 (귀무분포 실측)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P12a: 정체 정의 합성 20종 중 FAM_C 밴드 arm 이 t_bd **3.101** 로 유일하게 2.95 초과.
##  ★그러나 **20종 중 최대값**이다. 2.95(Harvey-Liu-Zhu)는 문헌-레벨 다중검정을 반영하지만
##    **사내 시행 20회는 별도 층**이다. ⇒ 귀무분포를 실측해 백분위를 낸다.
##  귀무 = "임의 3-팩터 EW 합성 + 같은 밴드". 52 팩터 풀에서 3종씩 **무작위 40 합성**(seed 고정).
##    계열 구조를 쓰지 않으므로 FAM_C 의 '계열' 성분이 특별한지 아닌지가 대비된다.
##  판정:
##   B1_SURVIVES : 3.101 이 귀무 90분위 초과 ∧ 귀무 40 중 2.95 초과가 <= 2건 → 드묾
##   B2_COMMON   : 2.95 초과가 >= 5건 → 밴드+3팩터 조합이면 흔한 수준, FAM_C 특별하지 않음
##   B3_MIDDLE   : 그 사이 → 프리미엄이 실재하나 결정적이지 않음
##  ⚠밴드 arm 만 잰다(질문이 't_bd 수준'이므로). 자본 자격 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
OBS <- 3.101; N_DRAW <- 40L; K <- 3L
set.seed(20260810L)

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
POOL <- fread(file.path(OUT, "p11c_net.csv"))$base
cat(sprintf("[풀] 팩터 %d종 · 무작위 %d합성 x %d팩터 (seed 20260810)\n", length(POOL), N_DRAW, K))
DRAWS <- lapply(seq_len(N_DRAW), function(i) sample(POOL, K))

acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=POOL), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]; if (!nrow(z)) next
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
FD <- rbindlist(acc, fill=TRUE)
U <- merge(B[, .(Date,Ticker,D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]; U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, FD, by=c("Date","Ticker"), all.x=TRUE)
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
zs <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s==0) rep(0,length(x)) else (x-m)/s }
mk <- function(D, bc, band) D[, {
  o <- order(-get(bc)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]
  keep <- tk[seq_len(min(25L-band, .N))]; pool <- tk[qq %in% 3:4 & !(tk %in% keep)]
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% c(keep, head(pool, band)),
                                    1000-frank(-.SD[[bc]], ties.method="first"), -1e6))
}, by=Date, .SDcols=c("Ticker","q",bc)]
runbt <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
      liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL)
  list(t=r$portfolio_alpha_t_nw_lag3, cov=r$selected_ret_coverage, n=r$n_months)
}
rows <- list()
for (i in seq_along(DRAWS)) {
  mem <- intersect(DRAWS[[i]], names(U)); if (length(mem) < K) next
  cn <- sprintf("RND%02d", i)
  U[, (cn) := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=mem]
  D <- U[!is.na(get(cn)) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 120L) { U[, (cn) := NULL]; next }
  r1 <- runbt(mk(D,cn,12L), paste0("p13b_",cn))
  U[, (cn) := NULL]
  if (is.null(r1)) next
  rows[[length(rows)+1L]] <- data.table(draw=cn, members=paste(mem, collapse="+"),
    n=r1$n, cov=round(r1$cov,3), t_bd=round(r1$t,3))
  if (i %% 10L == 0L) cat(sprintf("  ...%d/%d\n", i, length(DRAWS)))
}
R <- rbindlist(rows, fill=TRUE)[cov >= 0.95]
cat(sprintf("\n[귀무] 유효 합성 %d / %d\n", nrow(R), N_DRAW))
qs <- quantile(R$t_bd, c(0,0.25,0.5,0.75,0.90,0.95,1), na.rm=TRUE)
cat("t_bd 분위:\n"); print(round(qs,3))
pct <- mean(R$t_bd < OBS); n295 <- sum(R$t_bd >= 2.95)
cat(sprintf("\n관측 FAM_C t_bd = %.3f\n  귀무 백분위 = %.1f%% (귀무 %d개 중 %d개가 더 낮음)\n",
            OBS, 100*pct, nrow(R), sum(R$t_bd < OBS)))
cat(sprintf("  귀무 중 2.95 초과 = **%d / %d (%.1f%%)** · 귀무 최대 %.3f\n",
            n295, nrow(R), 100*n295/nrow(R), max(R$t_bd)))
cat("\n=== 귀무 상위 5 ===\n"); print(head(R[order(-t_bd), .(draw, t_bd, members)], 5))
verdict <- if (pct >= 0.90 && n295 <= 2L) "B1_SURVIVES" else if (n295 >= 5L) "B2_COMMON" else "B3_MIDDLE"
cat(sprintf("\n판정: %s\n★자본 자격 주장 없음 — 이건 '20중 최대 프리미엄' 의 크기만 잰다\n", verdict))
fwrite(R, file.path(OUT,"p13b_null.csv"))
write_json(list(verdict=verdict, observed=OBS, n_null=nrow(R), percentile=pct,
                n_exceed_295=n295, null_max=max(R$t_bd), quantiles=as.list(round(qs,4)),
                results=R), file.path(OUT,"p13b_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
