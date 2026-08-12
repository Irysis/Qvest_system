## P15b — FAM_C 3.101 을 한 부분기간이 끌고 있는가 (시대 분할)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P14b 로 계열 재현이 실패해 coincidence 가 선도 가설이다. 가장 싼 판별 = **시대 분할**.
##  전기간 t = 3.101 이 균등하게 분포한다면 반기 각각의 t 는 대략 3.101/sqrt(2) ≈ **2.19** 근방이어야 한다.
##  ⇒ 문턱을 그로부터 사전 도출: **각 반기 t_bd > 2.0** 이면 '균등에 부합', < 1.0 이면 '거의 기여 없음'.
##  비교군: FAM_M(전기간 2.397) 도 같이 분할해 불안정성이 FAM_C 고유인지 일반적인지 본다.
##  arm = 각 base x {무밴드, D03 q3~4} x {전반 133m, 후반 133m}
##  판정 (FAM_C 기준):
##   G1_STABLE     : 양 반기 t_bd > 2.0 ∧ 양 반기 Δ > 0  → 우연 가설 약화
##   G2_ONE_SIDED  : 한 반기가 t_bd < 1.0 또는 Δ < 0     → **한쪽이 끌고 있다**, 우연 쪽으로 기움
##   G3_UNSTABLE   : 양 반기 다 t_bd < 2.0               → 전기간 수치가 표본 특이
##  ★양성대조: 전기간 재현(1.785 / 3.101) ±0.05.
##  ⚠반기 t 는 검정력이 약 1/sqrt(2) 이므로 **낮은 t 를 실패로 읽지 말 것** — 문턱을 그래서 2.0 으로 낮췄다.
##  ★자본 자격 주장 없음. oos_retention 의 대리이지 그 자체가 아니다(anchored 3분할 v2 아님).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
NET <- fread(file.path(OUT, "p11c_net.csv"))
BASES <- list(FAM_C = list(mem=c("C01_SUE","C02_EPS_Chg_1m","C03_EPS_Chg_3m"), r0=1.785, r1=3.101),
              FAM_M = list(mem=NET[fam=="M", base],                             r0=1.690, r1=2.397))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date)); need <- unique(unlist(lapply(BASES, `[[`, "mem")))
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
allm <- sort(unique(U$Date)); half <- floor(length(allm)/2)
ERAS <- list(FULL = allm, EARLY = allm[seq_len(half)], LATE = allm[(half+1L):length(allm)])
cat(sprintf("[분할] 전기간 %d · 전반 %d (%s~%s) · 후반 %d (%s~%s)\n", length(allm),
            length(ERAS$EARLY), min(ERAS$EARLY), max(ERAS$EARLY),
            length(ERAS$LATE),  min(ERAS$LATE),  max(ERAS$LATE)))
runbt <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
      liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL)
  list(t=r$portfolio_alpha_t_nw_lag3, cov=r$selected_ret_coverage, n=r$n_months)
}
rows <- list()
for (nm in names(BASES)) {
  mem <- intersect(BASES[[nm]]$mem, names(U)); if (length(mem) < 2L) next
  U[, bs := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=mem]
  for (er in names(ERAS)) {
    D <- U[Date %in% ERAS[[er]] & !is.na(bs) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
    if (uniqueN(D$Date) < 60L) next
    mk <- function(band) D[, {
      o <- order(-bs); tk <- .SD$Ticker[o]; qq <- .SD$q[o]
      keep <- tk[seq_len(min(25L-band, .N))]; pool <- tk[qq %in% 3:4 & !(tk %in% keep)]
      .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% c(keep, head(pool, band)),
                                        1000-frank(-bs, ties.method="first"), -1e6))
    }, by=Date, .SDcols=c("Ticker","q","bs")]
    a <- runbt(mk(0L), sprintf("p15b_%s_%s_nb", nm, er)); b <- runbt(mk(12L), sprintf("p15b_%s_%s_bd", nm, er))
    if (is.null(a) || is.null(b)) next
    rows[[length(rows)+1L]] <- data.table(base=nm, era=er, n=b$n, cov=round(min(a$cov,b$cov),3),
      t_nb=round(a$t,3), t_bd=round(b$t,3), delta=round(b$t-a$t,3))
    cat(sprintf("  %-6s %-5s n=%3d  t_nb %+6.3f → t_bd %+6.3f  Δ %+6.3f\n", nm, er, b$n, a$t, b$t, b$t-a$t))
  }
  U[, bs := NULL]
}
R <- rbindlist(rows, fill=TRUE)[cov >= 0.95]
fc <- R[base=="FAM_C"]; f_full <- fc[era=="FULL"]
ok <- nrow(f_full)==1L && abs(f_full$t_nb-1.785)<=0.05 && abs(f_full$t_bd-3.101)<=0.05
cat(sprintf("\n[양성대조] FAM_C 전기간 %.3f/%.3f → %s\n", f_full$t_nb, f_full$t_bd, ok))
if (!ok) { cat("⇒ 양성대조 실패 — 수치 보고 중단\n")
  write_json(list(verdict="POSITIVE_CONTROL_FAILED", results=R), file.path(OUT,"p15b_result.json"),
             pretty=TRUE, auto_unbox=TRUE, digits=NA); quit(save="no") }
cat("\n=== 전체 ===\n"); print(R)
h <- fc[era != "FULL"]
cat(sprintf("\n★균등 기대치: 3.101/sqrt(2) ≈ %.2f · 사전 문턱 t_bd > 2.0\n", 3.101/sqrt(2)))
verdict <- if (all(h$t_bd > 2.0) && all(h$delta > 0)) "G1_STABLE" else
           if (any(h$t_bd < 1.0) || any(h$delta < 0)) "G2_ONE_SIDED" else "G3_UNSTABLE"
cat(sprintf("FAM_C 반기 t_bd: %s · Δ: %s\n판정: %s\n",
            paste(sprintf("%+.3f", h$t_bd), collapse=" / "),
            paste(sprintf("%+.3f", h$delta), collapse=" / "), verdict))
cat(sprintf("(비교) FAM_M 반기 t_bd: %s\n",
            paste(sprintf("%+.3f", R[base=="FAM_M" & era!="FULL", t_bd]), collapse=" / ")))
cat("⚠반기 검정력은 약 1/sqrt(2) — 낮은 t 를 곧바로 실패로 읽지 말 것\n★자본 자격 주장 없음\n")
fwrite(R, file.path(OUT,"p15b_era.csv"))
write_json(list(verdict=verdict, positive_control_ok=ok, uniform_expectation=3.101/sqrt(2),
                famc_half_t_bd=h$t_bd, famc_half_delta=h$delta, results=R),
           file.path(OUT,"p15b_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
