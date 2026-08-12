## P14b — FAM_C 3.101 은 '이익개정 계열' 성질인가, C01~C03 세 종의 우연인가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P12a: FAM_C = C01_SUE + C02_EPS_Chg_1m + C03_EPS_Chg_3m → 밴드 arm t_bd **3.101**.
##  P13b: 임의 3-팩터 합성 40종의 밴드 arm 은 **최대 2.104**, 2.95 초과 0/40.
##  ★질문: C 계열의 **미사용 팩터**로 같은 크기 합성을 만들면 재현되는가.
##    재현되면 **계열 성질**(칩 task_a6df1ed3 의 전제가 튼튼) / 안 되면 **3종 우연**(칩 재조정 필요).
##  설계: DB 의 C 계열 전체를 열거 → C01/C02/C03 제외 → **연속 3종씩 결정적 분할**(무작위 아님)
##        + 미사용 C 전체 EW 합성 1종. 전부 같은 밴드(D03 q3~4, m=12).
##  판정 (귀무 천장 2.104 를 기준선으로):
##   C1_FAMILY : 미사용 C 합성의 **중앙 t_bd > 2.104** → 계열 성질
##   C2_COINCIDENCE : 중앙 t_bd <= 1.465(귀무 90분위) → C01~C03 우연
##   C3_MIXED  : 그 사이 → 계열에 신호는 있으나 3.101 은 특정 조합 의존
##  ⚠core4 에 들어있던 C04/C06 도 미사용군에 포함된다(core4 Δ 는 음수였다) — 제외하지 않는다.
##  ★자본 자격 주장 없음. canonical_screen 계층.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
USED <- c("C01_SUE","C02_EPS_Chg_1m","C03_EPS_Chg_3m"); OBS <- 3.101; NULL_MAX <- 2.104; NULL_P90 <- 1.465

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
probe <- as.data.table(load_month_factors(ds[floor(length(ds)/2)]))
CFAM <- sort(unique(probe$Factor_Name[grepl("^C[0-9]{2}_", probe$Factor_Name)]))
UNUSED <- setdiff(CFAM, USED)
cat(sprintf("[열거] C 계열 %d종 · 사용 %d · **미사용 %d**\n", length(CFAM), length(USED), length(UNUSED)))
cat("  미사용:", paste(UNUSED, collapse=", "), "\n")
if (length(UNUSED) < 3L) { cat("⇒ 미사용 3종 미만 — 재현 불가\n"); quit(save="no") }
grp <- split(UNUSED, ceiling(seq_along(UNUSED)/3L))          # 연속 3종씩 결정적 분할
grp <- grp[vapply(grp, length, 1L) == 3L]
SETS <- c(setNames(grp, paste0("UC", seq_along(grp))), list(UC_ALL = UNUSED))
cat(sprintf("[합성] 3종 분할 %d개 + 미사용 전체 1개 = %d\n", length(grp), length(SETS)))

acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=CFAM), silent=TRUE)
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
## 양성 대조: FAM_C 재현(3.101) — 파이프라인 동일성 확인
SETS <- c(list(POSCTL_FAM_C = USED), SETS)
for (nm in names(SETS)) {
  mem <- intersect(SETS[[nm]], names(U)); if (length(mem) < 2L) { cat(sprintf("  skip %s\n", nm)); next }
  U[, .tmp := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=mem]
  D <- U[!is.na(.tmp) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  if (uniqueN(D$Date) < 120L) { U[, .tmp := NULL]; next }
  r0 <- runbt(mk(D,".tmp",0L), paste0("p14b_",nm,"_nb")); r1 <- runbt(mk(D,".tmp",12L), paste0("p14b_",nm,"_bd"))
  U[, .tmp := NULL]
  if (is.null(r0) || is.null(r1)) { cat(sprintf("  fail %s\n", nm)); next }
  rows[[length(rows)+1L]] <- data.table(set=nm, k=length(mem), n=r1$n, cov=round(min(r0$cov,r1$cov),3),
    t_nb=round(r0$t,3), t_bd=round(r1$t,3), delta=round(r1$t-r0$t,3),
    members=paste(mem, collapse="+"))
  cat(sprintf("  %-14s k=%d  t_nb %+6.3f → t_bd %+6.3f  Δ %+6.3f\n", nm, length(mem), r0$t, r1$t, r1$t-r0$t))
}
R <- rbindlist(rows, fill=TRUE)[cov >= 0.95]
ctl <- R[set == "POSCTL_FAM_C"]
ok <- nrow(ctl) == 1L && abs(ctl$t_bd - OBS) <= 0.05
cat(sprintf("\n[양성대조] FAM_C 재현 t_bd %.3f / 정본 %.3f → %s\n",
            if (nrow(ctl)) ctl$t_bd else NA_real_, OBS, ok))
if (!ok) { cat("⇒ 양성대조 실패 — **수치 보고 중단**\n")
  write_json(list(verdict="POSITIVE_CONTROL_FAILED", results=R), file.path(OUT,"p14b_result.json"),
             pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(save="no") }
UC <- R[set != "POSCTL_FAM_C"]
cat("\n=== 미사용 C 합성 ===\n"); print(UC[order(-t_bd), .(set, k, t_nb, t_bd, delta, members)])
med <- median(UC$t_bd); cat(sprintf("\n미사용 C 중앙 t_bd = %.3f (귀무 천장 %.3f · 귀무 90분위 %.3f · FAM_C %.3f)\n",
                                    med, NULL_MAX, NULL_P90, OBS))
cat(sprintf("귀무 천장 초과 %d/%d · Δ>0 %d/%d\n", sum(UC$t_bd > NULL_MAX), nrow(UC), sum(UC$delta>0), nrow(UC)))
verdict <- if (med > NULL_MAX) "C1_FAMILY" else if (med <= NULL_P90) "C2_COINCIDENCE" else "C3_MIXED"
cat(sprintf("\n판정: %s\n★자본 자격 주장 없음 · canonical_screen 계층\n", verdict))
fwrite(R, file.path(OUT,"p14b_cfamily.csv"))
write_json(list(verdict=verdict, positive_control_ok=ok, unused_median=med,
                null_max=NULL_MAX, null_p90=NULL_P90, observed_famc=OBS,
                n_exceed_null_max=sum(UC$t_bd > NULL_MAX), results=R),
           file.path(OUT,"p14b_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
