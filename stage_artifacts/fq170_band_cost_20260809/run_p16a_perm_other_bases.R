## P16a — 밴드 연산의 일반화: 순열 통제를 다른 base 3곳에서 반복
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P15c: FAM_C base 에서 D03 q3~4(3.101)가 순열 전부(최대 1.455)를 이겼고 **순열은 무밴드보다도 낮았다**.
##  ★그러나 **base 한 곳**에서만 쟀다. ⇒ 다른 3곳에서 반복한다:
##    FAM_M (P12a 1.690→2.397, Δ +0.708) · FAM_V (1.476→2.220, +0.744) ·
##    **CORE4_EW (1.685→1.303, Δ -0.381 = 20종 중 유일 음수)**
##  각 base: REF0 무밴드 · REF1 D03 q3~4 · N2 무작위12(랭크26~50 깊이정합) x5 · N3 타 십분위쌍 x4
##  ★양성대조: 각 base 의 REF0/REF1 이 P12a 정본을 ±0.05 재현해야 한다. 실패 시 그 base 는 제외.
##  판정:
##   E1_GENERAL : 3/3 base 에서 D03 이 자기 base 의 모든 귀무를 이김 → 밴드 연산 base-무관
##   E2_MOSTLY  : 2/3
##   E3_CORE4_EXPLAINED : CORE4_EW 에서 어떤 귀무가 D03 을 이김 → 그 음수 Δ 의 기전
##  ★자본 자격 주장 없음. canonical_screen 계층.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
set.seed(20260810L)
NET <- fread(file.path(OUT, "p11c_net.csv"))
CORE4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
BASES <- list(
  FAM_M    = list(mem = NET[fam=="M", base], ref0 = 1.690, ref1 = 2.397),
  FAM_V    = list(mem = NET[fam=="V", base], ref0 = 1.476, ref1 = 2.220),
  CORE4_EW = list(mem = CORE4,               ref0 = 1.685, ref1 = 1.303))
cat("[사전 고정]\n"); for (nm in names(BASES))
  cat(sprintf("  %-9s %s (ref %.3f→%.3f)\n", nm, paste(BASES[[nm]]$mem, collapse="+"),
              BASES[[nm]]$ref0, BASES[[nm]]$ref1))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
need <- unique(unlist(lapply(BASES, `[[`, "mem")))
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
runbt <- function(Sc, lab) {
  r <- try(canonical_screen_bt(Sc, ret[, .(Date,Ticker,Ret_1m)], bench, top_n=25L, cost_bps_oneway=15,
      liq_dt=liq[, .(Date,Ticker,adv)], liq_min=2e8, run_id=lab, strategy_id=lab), silent=TRUE)
  if (inherits(r,"try-error")) return(NULL)
  list(t=r$portfolio_alpha_t_nw_lag3, cov=r$selected_ret_coverage)
}
rows <- list()
for (nm in names(BASES)) {
  mem <- intersect(BASES[[nm]]$mem, names(U)); if (length(mem) < 2L) { cat(sprintf("skip %s\n", nm)); next }
  U[, bs := rowMeans(do.call(cbind, lapply(.SD, zs)), na.rm=TRUE), by=Date, .SDcols=mem]
  D <- U[!is.na(bs) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  mk <- function(mode, deciles=NULL) D[, {
    o <- order(-bs); tk <- .SD$Ticker[o]; qq <- .SD$q[o]; n <- .N
    if (mode == "none") sel <- tk[seq_len(min(25L,n))] else {
      keep <- tk[seq_len(min(13L,n))]; rest <- setdiff(seq_len(n), seq_len(min(13L,n)))
      idx <- switch(mode, "decile" = rest[qq[rest] %in% deciles],
                    "rand_deep" = { d <- rest[rest >= 26L & rest <= 50L]
                                    if (length(d) >= 12L) sample(d) else sample(rest) })
      sel <- c(keep, tk[head(idx, 12L)]) }
    .(Ticker=.SD$Ticker, score=ifelse(.SD$Ticker %in% sel, 1000-frank(-bs, ties.method="first"), -1e6))
  }, by=Date, .SDcols=c("Ticker","q","bs")]
  add <- function(arm, grp, r) { if (is.null(r)) return(invisible(NULL))
    rows[[length(rows)+1L]] <<- data.table(base=nm, arm=arm, grp=grp, cov=round(r$cov,3), t=round(r$t,3))
    cat(sprintf("  %-9s %-14s t %+6.3f\n", nm, arm, r$t)) }
  add("REF0_noband", "ref", runbt(mk("none"), paste0("p16a_",nm,"_ref0")))
  add("REF1_D03_q34","ref", runbt(mk("decile", 3:4), paste0("p16a_",nm,"_ref1")))
  for (i in 1:5) add(sprintf("N2_randdeep_%02d", i), "N2_rand_deep",
                     runbt(mk("rand_deep"), sprintf("p16a_%s_n2_%02d", nm, i)))
  for (dd in list(1:2, 5:6, 7:8, 9:10)) add(sprintf("N3_q%d%d", dd[1], dd[2]), "N3_decile",
                     runbt(mk("decile", dd), sprintf("p16a_%s_n3_q%d", nm, dd[1])))
  U[, bs := NULL]
}
R <- rbindlist(rows, fill=TRUE)[cov >= 0.95]
cat("\n=== base 별 요약 ===\n"); res <- list()
for (nm in names(BASES)) {
  S <- R[base == nm]; if (!nrow(S)) next
  r0 <- S[arm=="REF0_noband", t]; r1 <- S[arm=="REF1_D03_q34", t]
  ok <- length(r0)==1L && length(r1)==1L &&
        abs(r0-BASES[[nm]]$ref0)<=0.05 && abs(r1-BASES[[nm]]$ref1)<=0.05
  nulls <- S[grp != "ref", t]; mx <- if (length(nulls)) max(nulls) else NA_real_
  beats <- isTRUE(r1 > mx); below_ref0 <- if (length(nulls)) mean(nulls < r0) else NA_real_
  cat(sprintf("  %-9s 대조 %s · 무밴드 %+.3f · D03 %+.3f · 귀무최대 %+.3f · D03이김 %s · 귀무<무밴드 %.0f%%\n",
              nm, ok, r0, r1, mx, beats, 100*below_ref0))
  res[[nm]] <- list(control_ok=ok, ref0=r0, ref1=r1, null_max=mx,
                    d03_beats_all=beats, frac_nulls_below_ref0=below_ref0)
}
valid <- Filter(function(x) isTRUE(x$control_ok), res)
nb <- sum(vapply(valid, function(x) isTRUE(x$d03_beats_all), logical(1)))
c4 <- res[["CORE4_EW"]]
verdict <- if (length(valid) == 0L) "E0_CONTROLS_FAILED" else
           if (nb == length(valid)) "E1_GENERAL" else
           if (!is.null(c4) && isTRUE(c4$control_ok) && !isTRUE(c4$d03_beats_all)) "E3_CORE4_EXPLAINED" else
           "E2_MOSTLY"
cat(sprintf("\n대조 통과 base %d/%d · D03 이 모든 귀무를 이긴 base %d/%d\n판정: %s\n",
            length(valid), length(res), nb, length(valid), verdict))
cat("★자본 자격 주장 없음\n")
fwrite(R, file.path(OUT,"p16a_perm_bases.csv"))
write_json(list(verdict=verdict, n_valid=length(valid), n_beats=nb, per_base=res, results=R),
           file.path(OUT,"p16a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
