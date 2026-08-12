## P8b — slope 규칙 사후검증: 밴드 Δ 를 **돌려보기 전에** 맞힐 수 있는가
## 사전등록(측정 전 고정, 이 주석이 정본 — 임계는 in-sample 3점만으로 결정됨):
##  P8a: slope_14_50 = r26_50 - r14_25 (연율 %) 가 3 base 에서 Δ 순서를 3/3 맞힘.
##       mine +1.132→Δ+0.845 · PG2 -5.779→Δ+0.264 · core4 -6.846→Δ-0.293
##  ⇒ 부호 전환 임계는 (-6.846, -5.779) 사이. **ex-ante τ = -6.3 (괄호 중점)**.
##  규칙: 밴드 Δ > 0  ⟺  slope_14_50 > τ.
##  ★slope 는 **밴드를 전혀 쓰지 않고** base 랭크 프로파일만으로 계산된다(예측자 독립성).
##  검증 집합: 신규 9 base (D03_EWMA 자체 · Q01_EB · M01_PATHQ · z_raw · z_neutral ·
##             C01_SUE · C02_EPS_Chg_1m · C04_ESBR · C06_TP_Gap)
##  통제: in-sample 3 base(mine/PG2/core4)가 P8a·P6c 값을 재현해야 함.
##  ★★기저율 명시 의무: 다수 클래스 비율을 보고하고 적중률을 그것과 대조한다
##    (전부 양수면 '규칙 없이도 8/9' 이므로 적중률만으로는 무정보).
##  판정:
##   V1_RULE_HOLDS : 신규 9 중 적중 >= 7 **그리고** 다수클래스 기저율 초과
##   V2_ORDER_ONLY : 부호 적중은 기저율 이하이나 spearman(slope, Δ) >= 0.6 (전 12 base)
##   V3_RULE_FAILS : 둘 다 아님 → slope 3/3 은 n=3 우연. 기전 서술은 '버리는 구간' 수준에서 멈춤
##  ⚠자본 자격 주장 없음. 커버리지 < 0.95 arm 은 제외하고 그 사실을 보고한다.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

TAU <- -6.3
CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
B[, ym := format(Date, "%Y-%m")]
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
A[, ym := format(as.Date(Date), "%Y-%m")]
ds <- sort(unique(B$Date)); acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=CORE4), silent=TRUE)
  if (inherits(z,"try-error")) next
  z <- as.data.table(z)[!is.na(Z_Score_Aligned)]
  acc[[length(acc)+1L]] <- dcast(z, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")[, Date := ds[i]]
}
C4 <- rbindlist(acc, fill=TRUE)

U <- merge(B, ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
U <- merge(U, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
U <- U[is.na(adv) | adv >= 2e8]
U[, nmo := .N, by=Date]; U <- U[nmo >= 125L]
U <- merge(U, C4, by=c("Date","Ticker"), all.x=TRUE)
U <- merge(U, A[!is.na(score_eff), .(ym, Ticker, pg2=score_eff)], by=c("ym","Ticker"), all.x=TRUE)
U <- merge(U, bench, by="Date"); U[, exc := Ret_1m - BM_Ret]
have4 <- intersect(CORE4, names(U))
U[, q := cut(frank(D03_EWMA, ties.method="first"),
             breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
             include.lowest=TRUE, labels=FALSE), by=Date]
U[complete.cases(U[, have4, with=FALSE]),
  core4 := rowMeans(scale(as.matrix(.SD)), na.rm=TRUE), by=Date, .SDcols=have4]
cat(sprintf("[입력 실측] 행 %d · 월 %d · 초과 결측 %d · τ=%.1f\n", nrow(U), uniqueN(U$Date), sum(is.na(U$exc)), TAU))

## 예측자: 밴드 미사용, 랭크 프로파일만
slope_of <- function(col) {
  D <- U[!is.na(get(col)) & !is.na(exc)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  pr <- D[, { o <- order(-get(col)); e <- .SD$exc[o]; n <- .N
    f <- function(a,b) if (n >= a) mean(e[a:min(b,n)]) else NA_real_
    .(a=f(14,25), b=f(26,50)) }, by=Date, .SDcols=c("exc",col)]
  (mean(pr$b, na.rm=TRUE) - mean(pr$a, na.rm=TRUE)) * 1200
}
## 실측: 2 arm
mk <- function(D, bc, band) D[, {
  o <- order(-get(bc)); tk <- .SD$Ticker[o]; qq <- .SD$q[o]
  keep <- tk[seq_len(min(25L-band, .N))]; pool <- tk[qq %in% 3:4 & !(tk %in% keep)]
  sel <- c(keep, head(pool, band))
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000-frank(-.SD[[bc]], ties.method="first"), -1e6))
}, by=Date, .SDcols=c("Ticker","q",bc)]
runbt <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
      liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL)
  list(t=r$portfolio_alpha_t_nw_lag3, cov=r$selected_ret_coverage, n=r$n_months)
}
BASES <- list(
  list(c="M26_Revenue_Mom", l="M26(in-sample)",  new=FALSE), list(c="pg2", l="PG2(in-sample)", new=FALSE),
  list(c="core4", l="core4-EW(in-sample)", new=FALSE),
  list(c="D03_EWMA", l="D03_EWMA", new=TRUE), list(c="Q01_EB", l="Q01_EB", new=TRUE),
  list(c="M01_PATHQ", l="M01_PATHQ", new=TRUE), list(c="z_raw", l="z_raw", new=TRUE),
  list(c="z_neutral", l="z_neutral", new=TRUE), list(c="C01_SUE", l="C01_SUE", new=TRUE),
  list(c="C02_EPS_Chg_1m", l="C02_EPS_Chg", new=TRUE), list(c="C04_ESBR", l="C04_ESBR", new=TRUE),
  list(c="C06_TP_Gap", l="C06_TP_Gap", new=TRUE))
rows <- list()
for (bs in BASES) {
  D <- U[!is.na(get(bs$c)) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 60L) { cat(sprintf("  skip %s (월 %d)\n", bs$l, uniqueN(D$Date))); next }
  sl <- slope_of(bs$c)
  r0 <- runbt(mk(D, bs$c, 0L),  paste0("p8b_", bs$c, "_nb"))
  r1 <- runbt(mk(D, bs$c, 12L), paste0("p8b_", bs$c, "_bd"))
  if (is.null(r0) || is.null(r1)) { cat(sprintf("  fail %s\n", bs$l)); next }
  rows[[length(rows)+1L]] <- data.table(base=bs$l, is_new=bs$new, n=r1$n,
    cov_min=round(min(r0$cov, r1$cov),3), slope=round(sl,3),
    pred=ifelse(sl > TAU, "+", "-"), t_nb=round(r0$t,3), t_bd=round(r1$t,3),
    delta=round(r1$t - r0$t, 3))
  cat(sprintf("  %-22s slope %+7.3f  pred %s  Δ %+7.3f\n", bs$l, sl, ifelse(sl>TAU,"+","-"), r1$t-r0$t))
}
R <- rbindlist(rows)
R[, hit := (pred == "+") == (delta > 0)]
bad <- R[cov_min < 0.95]
if (nrow(bad)) cat(sprintf("\n⚠커버리지<0.95 제외 %d: %s\n", nrow(bad), paste(bad$base, collapse=", ")))
R <- R[cov_min >= 0.95]
cat("\n=== 전 base ===\n"); print(R[, .(base,is_new,n,cov_min,slope,pred,t_nb,t_bd,delta,hit)])

ctl <- R[is_new == FALSE]
cat(sprintf("\n[통제] in-sample 재현 %d/%d hit — %s\n", sum(ctl$hit), nrow(ctl),
            paste(sprintf("%s Δ%+.3f", ctl$base, ctl$delta), collapse=" · ")))
NEW <- R[is_new == TRUE]
pos <- sum(NEW$delta > 0); base_rate <- max(pos, nrow(NEW)-pos) / nrow(NEW)
hits <- sum(NEW$hit)
rho <- suppressWarnings(cor(R$slope, R$delta, method="spearman"))
cat(sprintf("\n[신규 %d base] 적중 %d/%d = %.3f · 다수클래스 기저율 %.3f (양수 %d/%d)\n",
            nrow(NEW), hits, nrow(NEW), hits/nrow(NEW), base_rate, pos, nrow(NEW)))
cat(sprintf("spearman(slope, Δ) 전 %d base = %.3f\n", nrow(R), rho))
verdict <- if (hits >= 7 && hits/nrow(NEW) > base_rate) "V1_RULE_HOLDS" else
           if (is.finite(rho) && rho >= 0.6) "V2_ORDER_ONLY" else "V3_RULE_FAILS"
cat(sprintf("판정: %s\n★자본 자격 주장 없음 · τ=-6.3 은 in-sample 3점으로 사전 고정\n", verdict))
fwrite(R, file.path(OUT,"p8b_slope_rule.csv"))
write_json(list(verdict=verdict, tau=TAU, hits=hits, n_new=nrow(NEW), base_rate=base_rate,
                spearman=rho, control_hits=sum(ctl$hit), results=R),
           file.path(OUT,"p8b_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
