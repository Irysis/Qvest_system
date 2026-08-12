## P15c — 밴드 신호가 기여하는가, 아니면 12종을 아무거나 바꿔 넣어도 같은가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  아크 전체가 'D03 밴드(q3~4)로 12종을 채운다' 를 전제로 돌았는데
##  **처리(밴드 신호) 자체의 기여를 분리한 적이 없다.** 이것이 맨 처음 했어야 할 통제다.
##  base 를 FAM_C(C01+C02+C03 EW)로 **고정**하고 채우는 규칙만 바꾼다:
##   REF0 무밴드(정본 t_nb 1.785) · REF1 D03 q3~4(정본 t_bd 3.101)
##   N1 무작위 12 (비-keep 전체에서 균일) x8      ← "아무거나 바꿔도 되는가"
##   N2 무작위 12 (랭크 26~50 에서, **깊이 정합**) x8 ← D03 픽의 전형 깊이와 맞춤
##   N3 다른 십분위쌍 q1~2 / q5~6 / q7~8 / q9~10  ← "q3~4 가 특별한가"
##  판정:
##   D1_BAND_MATTERS  : 3.101 이 N1·N2·N3 **전부의 최대**를 초과 → 밴드 신호가 기여
##   D2_ANY_SUBSTITUTION : N1 또는 N2 최대가 3.101 에 근접(>= 2.95) → **치환 자체**가 효과, 신호 무관
##   D3_DECILE_ARBITRARY : N3 최대 >= 2.95 → q3~4 가 특별하지 않음
##  ★양성대조: REF0/REF1 이 정본 재현(±0.05) 안 하면 수치 보고 중단.
##  ★자본 자격 주장 없음. canonical_screen 계층.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
FC <- c("C01_SUE","C02_EPS_Chg_1m","C03_EPS_Chg_3m"); T_NB <- 1.785; T_BD <- 3.101
set.seed(20260810L)

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date)); acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=FC), silent=TRUE)
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
have <- intersect(FC, names(U)); stopifnot(length(have) == 3L)
U[, base := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=have]
D <- U[!is.na(base) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
cat(sprintf("[입력 실측] 행 %d · 월 %d\n", nrow(D), uniqueN(D$Date)))

## mode: "none" | "decile" (deciles 인자) | "rand_all" | "rand_deep"
mk <- function(mode, deciles=NULL) D[, {
  o <- order(-base); tk <- .SD$Ticker[o]; qq <- .SD$q[o]; n <- .N
  if (mode == "none") { sel <- tk[seq_len(min(25L,n)) ] } else {
    keep <- tk[seq_len(min(13L,n))]; rest <- setdiff(seq_len(n), seq_len(min(13L,n)))
    idx <- switch(mode,
      "decile"    = rest[qq[rest] %in% deciles],
      "rand_all"  = sample(rest),
      "rand_deep" = { d <- rest[rest >= 26L & rest <= 50L]; if (length(d) >= 12L) sample(d) else sample(rest) })
    sel <- c(keep, tk[head(idx, 12L)])
  }
  .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000-frank(-base, ties.method="first"), -1e6))
}, by=Date, .SDcols=c("Ticker","q","base")]
runbt <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
      liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL)
  list(t=r$portfolio_alpha_t_nw_lag3, cov=r$selected_ret_coverage)
}
add <- function(rows, arm, grp, r) { if (is.null(r)) return(rows)
  rows[[length(rows)+1L]] <- data.table(arm=arm, grp=grp, cov=round(r$cov,3), t=round(r$t,3))
  cat(sprintf("  %-16s %-10s t %+6.3f\n", arm, grp, r$t)); rows }
rows <- list()
rows <- add(rows, "REF0_noband", "ref", runbt(mk("none"), "p15c_ref0"))
rows <- add(rows, "REF1_D03_q34", "ref", runbt(mk("decile", 3:4), "p15c_ref1"))
for (i in 1:8) rows <- add(rows, sprintf("N1_randall_%02d", i), "N1_rand_all",
                           runbt(mk("rand_all"), sprintf("p15c_n1_%02d", i)))
for (i in 1:8) rows <- add(rows, sprintf("N2_randdeep_%02d", i), "N2_rand_deep",
                           runbt(mk("rand_deep"), sprintf("p15c_n2_%02d", i)))
for (dd in list(1:2, 5:6, 7:8, 9:10)) rows <- add(rows, sprintf("N3_q%d%d", dd[1], dd[2]), "N3_decile",
                           runbt(mk("decile", dd), sprintf("p15c_n3_q%d", dd[1])))
R <- rbindlist(rows, fill=TRUE)[cov >= 0.95]
r0 <- R[arm=="REF0_noband", t]; r1 <- R[arm=="REF1_D03_q34", t]
ok <- length(r0)==1L && length(r1)==1L && abs(r0-T_NB)<=0.05 && abs(r1-T_BD)<=0.05
cat(sprintf("\n[양성대조] REF0 %.3f/%.3f · REF1 %.3f/%.3f → %s\n", r0, T_NB, r1, T_BD, ok))
if (!ok) { cat("⇒ 양성대조 실패 — 수치 보고 중단\n")
  write_json(list(verdict="POSITIVE_CONTROL_FAILED", results=R), file.path(OUT,"p15c_result.json"),
             pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(save="no") }
cat("\n=== 귀무군 요약 ===\n")
S <- R[grp != "ref", .(n=.N, min=min(t), med=median(t), max=max(t)), by=grp]; print(S)
mx <- setNames(S$max, S$grp)
cat(sprintf("\n관측 D03 q3~4 = %.3f\n  N1(무작위 전체) 최대 %.3f · N2(깊이정합) 최대 %.3f · N3(타 십분위) 최대 %.3f\n",
            r1, mx["N1_rand_all"], mx["N2_rand_deep"], mx["N3_decile"]))
beats_all <- all(r1 > mx, na.rm=TRUE)
verdict <- if (any(mx[c("N1_rand_all","N2_rand_deep")] >= 2.95, na.rm=TRUE)) "D2_ANY_SUBSTITUTION" else
           if (isTRUE(mx["N3_decile"] >= 2.95)) "D3_DECILE_ARBITRARY" else
           if (beats_all) "D1_BAND_MATTERS" else "D4_UNCLEAR"
cat(sprintf("\n판정: %s\n★자본 자격 주장 없음\n", verdict))
fwrite(R, file.path(OUT,"p15c_perm.csv"))
write_json(list(verdict=verdict, ref_noband=r0, ref_band=r1, group_max=as.list(mx),
                beats_all_nulls=beats_all, summary=S, results=R),
           file.path(OUT,"p15c_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
