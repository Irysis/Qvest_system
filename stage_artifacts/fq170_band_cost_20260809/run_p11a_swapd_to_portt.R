## P11a — swap_d(패널 산술) 가 PORT_t Δ(계약 실측) 로 번역되는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  P10c/P11c 의 모든 수치는 swap_d 기반이다. PORT_t 와의 부호 일치 근거는 **n=3**(P8a) 뿐이라
##  '자본 언어'로 말할 수 없다. ⇒ base 10종에 대해 실제 2-arm canonical_screen_bt 를 돌려 대응을 잰다.
##  ★base 선택은 **결정적·사전 고정**: p11c_net.csv 를 gross 오름차순 정렬 후
##    인덱스 c(1,6,12,18,23,29,35,41,46,52) — 분포 전 구간을 훑는다(최악 INV03 포함).
##    체리피킹 방지: 결과를 보고 고르지 않는다.
##  판정 (임계 사전 산출):
##   V1_TRANSLATES  : 부호일치 >= 8/10 ∧ spearman(swap_d, PORT_t Δ) >= 임계
##   V2_SIGN_ONLY   : 부호일치 >= 8/10 이나 spearman 미달 → **부호만** 전이, 크기 환산 금지
##   V3_NO_TRANSFER : 부호일치 < 8/10 → swap_d 진술을 PORT_t 로 읽지 말 것
##  ★커버리지 < 0.95 arm 은 제외하고 그 사실을 보고한다. 자본 자격 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

PICK_IDX <- c(1,6,12,18,23,29,35,41,46,52)
NET <- fread(file.path(OUT, "p11c_net.csv"))[order(gross)]
stopifnot(nrow(NET) >= max(PICK_IDX))
PICKS <- NET[PICK_IDX]
cat("[사전 고정 선택]\n"); print(PICKS[, .(base, fam, gross=round(gross,3), net=round(net,3))])

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")); B[, Date := as.Date(Date)]
ds <- sort(unique(B$Date))
acc <- list()
for (i in seq_along(ds)) {
  z <- try(load_month_factors(ds[i], factor_names=PICKS$base), silent=TRUE)
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
cat(sprintf("[유니버스] 행 %d · 월 %d · 적재 팩터 %d\n", nrow(U), uniqueN(U$Date), ncol(FD)-2L))

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
rows <- list()
for (i in seq_len(nrow(PICKS))) {
  b <- PICKS$base[i]
  if (!(b %in% names(U))) { cat(sprintf("  skip %s (미적재)\n", b)); next }
  D <- U[!is.na(get(b)) & !is.na(q)]; D[, n2 := .N, by=Date]; D <- D[n2 >= 125L]
  r0 <- runbt(mk(D,b,0L), paste0("p11a_",b,"_nb")); r1 <- runbt(mk(D,b,12L), paste0("p11a_",b,"_bd"))
  if (is.null(r0) || is.null(r1)) { cat(sprintf("  fail %s\n", b)); next }
  rows[[length(rows)+1L]] <- data.table(base=b, fam=PICKS$fam[i],
    swap_d=PICKS$gross[i], net_panel=PICKS$net[i],
    cov_min=round(min(r0$cov,r1$cov),3), n=r1$n,
    t_nb=round(r0$t,3), t_bd=round(r1$t,3), port_delta=round(r1$t-r0$t,3))
  cat(sprintf("  %-28s swap %+7.3f → PORT_t Δ %+7.3f\n", b, PICKS$gross[i], r1$t-r0$t))
}
R <- rbindlist(rows, fill=TRUE)
bad <- R[cov_min < 0.95]
if (nrow(bad)) cat(sprintf("\n⚠커버리지<0.95 제외 %d: %s\n", nrow(bad), paste(bad$base, collapse=", ")))
R <- R[cov_min >= 0.95]
cat("\n=== 대응표 ===\n"); print(R[, .(base, fam, swap_d=round(swap_d,3), t_nb, t_bd, port_delta, n, cov_min)])
n <- nrow(R); tc <- qt(0.975, max(n-2,1)); rho_crit <- sqrt(tc^2/(tc^2+max(n-2,1)))
rho <- suppressWarnings(cor(R$swap_d, R$port_delta, method="spearman"))
agree <- sum(sign(R$swap_d) == sign(R$port_delta))
cat(sprintf("\nn=%d · 임계 |rho|=%.3f · spearman(swap_d, PORT_t Δ)=%.3f · 부호일치 %d/%d\n",
            n, rho_crit, rho, agree, n))
verdict <- if (agree >= ceiling(0.8*n) && is.finite(rho) && rho >= rho_crit) "V1_TRANSLATES" else
           if (agree >= ceiling(0.8*n)) "V2_SIGN_ONLY" else "V3_NO_TRANSFER"
cat(sprintf("판정: %s\n★자본 자격 주장 없음 — PORT_t 수준이 아니라 **Δ 의 대응**만 잰다\n", verdict))
fwrite(R, file.path(OUT,"p11a_translate.csv"))
write_json(list(verdict=verdict, n=n, rho=rho, rho_crit=rho_crit, sign_agree=agree,
                picks_idx=PICK_IDX, results=R),
           file.path(OUT,"p11a_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
