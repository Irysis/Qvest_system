## P12a — 강한 base 에서 밴드 Δ 가 뒤집히는가 (자본 접속의 관문)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P11a 10종은 t_nb 중앙이 음수라 **강한 구간을 못 봤다**. P6c 에서 core4(1.704)는 Δ -0.293 이었다.
##  ★설계 함정: Δ = t_bd - t_nb 이므로 **t_nb 로 base 를 고르면** 회귀-평균이 Δ 를 인위적 음수로 만든다
##    (오늘 세 번 나온 공유항 계통의 선택-효과 판본). ⇒ **성과로 고르지 않는다.**
##  ⇒ base = **정체로 정의된 계열 EW 합성** 19종 + core4-EW(선행 연구에서 사전 지정).
##     계열 소속은 팩터 이름이 정하므로 성과 선택이 개입하지 않는다. t_nb 는 자연히 흩어진다.
##  1급 판정량 = **t_nb >= 1.5 부분집합에서 Δ 의 부호 분포**(각 부호는 기계적으로 강제되지 않음).
##  2급(참고) = spearman(t_nb, Δ) — **회귀-평균으로 음수 편향**이므로 단독 해석 금지.
##   A1_WEAK_BASE_TOOL : 강한 부분집합에서 Δ<0 이 과반 → 밴드는 약~중간 base 전용
##   A2_IDIOSYNCRATIC  : 강한 부분집합에서 Δ>0 이 과반 → core4 -0.293 은 개별 사례
##   A3_NO_STRONG      : t_nb>=1.5 인 base 가 3개 미만 → 판정 불가, 강한 합성을 더 만들어야 함
##  ★자본 자격 주장 없음. PORT_t 수준이 2.95 를 넘는지도 함께 보고한다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
fam_of <- function(x){ f <- sub("^([A-Za-z]+)[0-9_].*$","\\1",x); ifelse(f==x, substr(x,1,3), f) }
NET <- fread(file.path(OUT, "p11c_net.csv"))          # P9c 의 52종(계열당 3) — 정체로 선택됨
FAMS <- NET[, .(members=list(base), k=.N), by=fam][order(fam)]
cat(sprintf("[사전 고정] 계열 %d종 (계열당 %s) + core4-EW\n", nrow(FAMS), paste(range(FAMS$k), collapse="~")))

need <- unique(c(NET$base, CORE4))
acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=need), silent=TRUE)
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
## 계열 EW 합성 (정체 기반) + core4
comp_cols <- character(0)
for (i in seq_len(nrow(FAMS))) {
  mem <- intersect(FAMS$members[[i]], names(U)); if (!length(mem)) next
  cn <- paste0("FAM_", FAMS$fam[i])
  U[, (cn) := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=mem]
  comp_cols <- c(comp_cols, cn)
}
h4 <- intersect(CORE4, names(U))
if (length(h4) == 4L) { U[, CORE4_EW := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=h4]
  comp_cols <- c(comp_cols, "CORE4_EW") }
cat(sprintf("[합성] %d종 · 유니버스 행 %d · 월 %d\n", length(comp_cols), nrow(U), uniqueN(U$Date)))

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
for (cn in comp_cols) {
  D <- U[!is.na(get(cn)) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 120L) next
  r0 <- runbt(mk(D,cn,0L), paste0("p12a_",cn,"_nb")); r1 <- runbt(mk(D,cn,12L), paste0("p12a_",cn,"_bd"))
  if (is.null(r0) || is.null(r1)) { cat(sprintf("  fail %s\n", cn)); next }
  rows[[length(rows)+1L]] <- data.table(base=cn, n=r1$n, cov_min=round(min(r0$cov,r1$cov),3),
    t_nb=round(r0$t,3), t_bd=round(r1$t,3), delta=round(r1$t-r0$t,3))
  cat(sprintf("  %-14s t_nb %+6.3f → t_bd %+6.3f  Δ %+6.3f\n", cn, r0$t, r1$t, r1$t-r0$t))
}
R <- rbindlist(rows, fill=TRUE)[cov_min >= 0.95][order(-t_nb)]
cat("\n=== 전 합성 (t_nb 내림차순) ===\n"); print(R)
S <- R[t_nb >= 1.5]
cat(sprintf("\n★t_nb >= 1.5 인 합성: %d종\n", nrow(S)))
if (nrow(S)) { print(S); cat(sprintf("  Δ>0: %d / %d · Δ 중앙 %+.3f\n", sum(S$delta>0), nrow(S), median(S$delta))) }
rho <- suppressWarnings(cor(R$t_nb, R$delta, method="spearman"))
cat(sprintf("\n[2급·참고] spearman(t_nb, Δ) = %.3f — **회귀-평균 음수 편향** 있으므로 단독 해석 금지\n", rho))
cat(sprintf("PORT_t 2.95 도달 arm: %d (t_nb) / %d (t_bd)\n", sum(R$t_nb>=2.95), sum(R$t_bd>=2.95)))
verdict <- if (nrow(S) < 3L) "A3_NO_STRONG" else if (sum(S$delta>0) > nrow(S)/2) "A2_IDIOSYNCRATIC" else "A1_WEAK_BASE_TOOL"
cat(sprintf("\n판정: %s\n★자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"p12a_strong.csv"))
write_json(list(verdict=verdict, n_base=nrow(R), n_strong=nrow(S),
                strong_pos=if (nrow(S)) sum(S$delta>0) else 0L,
                rho_caveated=rho, n_reach_295_nb=sum(R$t_nb>=2.95), n_reach_295_bd=sum(R$t_bd>=2.95),
                results=R), file.path(OUT,"p12a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
