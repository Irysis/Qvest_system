## run_fof_first_slice.R — Factor-of-Factors 첫 슬라이스 (B×C 메타-포트 cheap-kill probe)
## 목표: "factor momentum 12-1m (family-level) vs 정적틸트" 1쌍 A/B를 canonical_screen_bt로 실측,
##       월별 net active diff d_t = ARM_B − ARM_A → paired NW-t(lag-3)로 판정.
##
## ARM-A (CTRL static)  : W_group = 전기간 고정(EW across 11 경제군). "타이밍 없는 정적 노출".
## ARM-B (TEST momentum): 매월 t, W_group ∝ family 12-1m momentum (trailing t-12..t-1, PIT t-1말 기준).
##                        shumulvey 22 family 일별 → 월말 집계 → 12-1m → fam_of 11군 매핑 → z → max(z,0) 가중.
## 공통: pure_factor_scores neutralized_z → fam_of 11군 group_z(종목별 멤버 평균) → Σ_g W_g·group_z → top25 EW.
##       동일 forward returns(_bo_fwdgic)·동일 15bps·동일 ADV 2e8·동일 유니버스. 가중방식만 차이.
##
## PIT: factor momentum trailing(t-12..t-1)만, t-1 월말 계산, t 리밸. t월 수익 신호 투입 금지(=look-ahead).
##      look-ahead 가드: momentum lag toggle test(lag=1 정상 vs lag=0 오염) 산출.
## 실측-only: canonical_screen_bt(metric_type="canonical_screen", screening advisory). proxy 손계산 금지.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")

OUT <- "04_Research/factor_rotation/fof_first_slice"
con <- file(file.path(OUT,"_fof_first_slice.txt"),"w",encoding="UTF-8")
w <- function(...) writeLines(paste0(...), con)
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }

## ── fam_of: pure_factor_scores prefix → 11 경제군 (factor_group_consolidation.R 복제) ──
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p=="TR") "Size_Liquidity" else "Composite" }

## ── shumulvey 22 family → fam_of 11 경제군 매핑 (명시·gap 보고) ──
## shumulvey 일별 index return 컬럼(Market=벤치 제외) → 경제군. Credit/Composite는 shumulvey 원천 부재(gap).
shu2grp <- list(
  Value          = c("Value"),
  Momentum       = c("Momentum","ResidMom","SUE"),     # SUE=earnings surprise momentum
  Quality        = c("Quality","GPA","EarnStab"),
  LowRisk        = c("LowVol","LowBeta","TailRisk"),
  Size_Liquidity = c("Size","Liquidity"),
  Reversal       = c("Reversal"),
  Growth_Profit  = c("Growth","Investment","Issuance"),# Issuance=financing/investment 차원
  Accruals       = c("Accrual"),
  Consensus      = c("Consensus","ForeignFlow","SmartMoney","Crowding")  # 컨센서스/포지셔닝 플로우
  ## Credit, Composite : shumulvey 원천 부재 → momentum 타이밍 미적용(고정 EW만, ARM-B서도 정적 처리)
)
SHU_USED  <- unlist(shu2grp); names(SHU_USED) <- NULL
SHU_GAP_GRP <- c("Credit","Composite")   # 모멘텀 신호 원천 없는 11군 멤버

w("================ FoF 첫 슬라이스 — B×C 메타-포트 cheap-kill probe ================")
w(sprintf("실행: %s", as.character(Sys.time())))
w("\n=== shumulvey 22 family → fam_of 11 경제군 매핑 ===")
for(g in names(shu2grp)) w(sprintf("  %-16s <= %s", g, paste(shu2grp[[g]],collapse=", ")))
w(sprintf("  %-16s <= (shumulvey 원천 부재 — momentum 타이밍 미적용, ARM-B서 정적 EW)", paste(SHU_GAP_GRP,collapse="/")))
w("  [매핑 gap] shumulvey Market=벤치(제외). 미사용 shumulvey: (없음 — Market 외 21개 전부 매핑)")

## ── 1) pure_factor_scores → fam_of 11군 group_z (종목별 멤버 neutralized_z 평균 → 월별 재표준화) ──
w("\n=== 1) 종목 스코어: pure_factor_scores → 11 경제군 group_z ===")
sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","neutralized_z")))
sc[, signal_date := as.Date(signal_date)]
sc[, family := sapply(factor_id, fam_of)]
sc <- sc[family != "Macro"]   # Macro 제외(consolidation 정합)
grp <- sc[, .(z = mean(neutralized_z, na.rm=TRUE)), by=.(signal_date, security_id, family)]
grp[, gz := { m<-mean(z,na.rm=TRUE); s<-sd(z,na.rm=TRUE); if(is.na(s)||s<1e-9) z-m else (z-m)/s }, by=.(signal_date, family)]
GRP_FAMS <- sort(unique(grp$family))
w(sprintf("  경제군: %s", paste(GRP_FAMS, collapse=", ")))
w(sprintf("  signal_date 월수: %d (%s ~ %s)", length(unique(grp$signal_date)),
          as.character(min(grp$signal_date)), as.character(max(grp$signal_date))))

## ── 2) shumulvey 일별 → 월말 집계 → family 12-1m momentum (PIT trailing, lag 적용) ──
w("\n=== 2) family 12-1m momentum (shumulvey 월말 집계, PIT trailing) ===")
shu <- as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns_broad.parquet"))
shu[, Date := as.Date(Date)]
shu[, ym := format(Date,"%Y-%m")]
fam_cols <- intersect(SHU_USED, names(shu))
stopifnot(length(setdiff(SHU_USED, names(shu))) == 0)  # 매핑 family가 전부 존재해야
# 월별 family return = (1+daily) 누적곱 - 1 (월간 복리). NA는 0으로(거래일 결측 보수)
mret <- shu[, lapply(.SD, function(x){ x[is.na(x)] <- 0; prod(1+x)-1 }), by=ym, .SDcols=fam_cols]
# month-end Date 부여 (해당 월 마지막 거래일)
mend <- shu[, .(meom = max(Date)), by=ym]
mret <- merge(mret, mend, by="ym"); setorder(mret, meom)
# family 12-1m momentum: log-return 누적합 trailing 11개월(t-12..t-2) — 표준 12-1m은 t-1 제외(reversal 회피)
# 본 슬라이스는 family index의 12-1m: trailing months [t-12, t-1] 누적, t-1 = 직전월(최근 1개월 skip 옵션은 toggle로 검증).
# fmom_t = sum_{k=1}^{11} logret_{t-1-k+1} ... 명료화: 12-1m = 직전 12개월 중 가장 최근 1개월 제외 (k=2..12)
fmom_lag <- function(lret_mat, skip_recent){
  # lret_mat: T×F log returns (행=월말 순서). skip_recent: 1=표준 12-1m(최근월 제외), 0=12-0m(오염 toggle)
  T <- nrow(lret_mat); F <- ncol(lret_mat); out <- matrix(NA_real_, T, F)
  for(t in seq_len(T)){
    hi <- t - 1 - skip_recent + 1   # t-1 이 직전월. skip_recent=1 → 가장 최근 포함월 = t-2
    hi <- t - 1 - skip_recent        # window 끝(최근). skip=1 → t-2, skip=0 → t-1
    lo <- t - 12                     # window 시작(최오래). 12개월 길이
    if(lo >= 1 && hi >= lo) out[t,] <- colSums(lret_mat[lo:hi, , drop=FALSE], na.rm=TRUE)
  }
  out
}
lmat <- as.matrix(log1p(as.matrix(mret[, ..fam_cols])))   # T×F log returns
fmom_std  <- fmom_lag(lmat, skip_recent=1L)   # 표준 12-1m (PIT clean, 최근월 제외)
fmom_test <- fmom_lag(lmat, skip_recent=0L)   # toggle: 최근월 포함 (12-0m, 더 공격적이나 reversal 노출)
rownames(fmom_std) <- as.character(mret$meom); colnames(fmom_std) <- fam_cols
rownames(fmom_test)<- as.character(mret$meom); colnames(fmom_test)<- fam_cols
w(sprintf("  shumulvey 월수: %d (%s ~ %s) | momentum family: %d개",
          nrow(mret), as.character(min(mret$meom)), as.character(max(mret$meom)), length(fam_cols)))
w(sprintf("  12-1m 정의: trailing log-return 누적 [t-12 .. t-2] (skip_recent=1, 최근 1개월 제외 = 표준)"))

## family momentum → 경제군 momentum (shu2grp 평균) → 월별 cross-section z (양수쪽 가중용)
# 11군 중 9군은 momentum 원천, 2군(Credit/Composite)은 momentum 부재 → 정적 EW로 처리
grp_mom <- function(fmom_mat){
  # 반환: data.table(meom_chr, <11군 z-momentum>). gap군은 0(중립 z) 채움.
  dt <- data.table(meom = rownames(fmom_mat))
  for(g in GRP_FAMS){
    if(g %in% names(shu2grp)){
      mem <- intersect(shu2grp[[g]], colnames(fmom_mat))
      dt[[g]] <- rowMeans(fmom_mat[, mem, drop=FALSE], na.rm=TRUE)
    } else {
      dt[[g]] <- NA_real_   # Credit/Composite: momentum 부재
    }
  }
  dt
}
gm_std  <- grp_mom(fmom_std)
gm_test <- grp_mom(fmom_test)

## ── 3) ARM별 월별 W_group 결정 ──
## ARM-A: 전기간 고정 EW across 11군 (W_g = 1/11). 타이밍 없음.
## ARM-B: 매월 W_g ∝ max(z_g, 0), z_g = 그 달 9-momentum군의 cross-section z. gap 2군은 평균치(중립) 가중.
w("\n=== 3) ARM 가중 결정 ===")
nG <- length(GRP_FAMS)
W_static <- setNames(rep(1/nG, nG), GRP_FAMS)
w(sprintf("  ARM-A (static): W_g = 1/%d (전기간 EW across 11군)", nG))

arm_b_weights <- function(gm){
  # 각 meom 행에서 9-momentum군 z → max(z,0) → 정규화. gap 2군은 momentum군 평균 비중 부여(중립 유지).
  meoms <- gm$meom; Wlist <- list()
  momg <- intersect(names(shu2grp), GRP_FAMS)   # momentum 보유군
  for(i in seq_along(meoms)){
    mv <- unlist(gm[i, ..momg]); mv <- mv[is.finite(mv)]
    if(length(mv) < 3) next   # momentum 미성립월(초기 12m 워밍업) skip
    z <- (mv - mean(mv)) / (sd(mv) + 1e-12)
    raw <- pmax(z, 0)
    if(sum(raw) < 1e-9) raw[] <- 1   # 전부 음수면 EW fallback
    wm <- raw / sum(raw)             # momentum군 비중(합 1). 단 gap군에도 자리 줘야 11군 정규화.
    # gap 2군: 중립 = momentum군 평균 비중(1/length(momg))로 부여 후 전체 재정규화
    wfull <- setNames(rep(0, nG), GRP_FAMS)
    wfull[names(wm)] <- wm
    if(length(SHU_GAP_GRP)>0){ wfull[SHU_GAP_GRP] <- mean(wm) }
    wfull <- wfull / sum(wfull)
    Wlist[[as.character(meoms[i])]] <- wfull
  }
  Wlist
}
WB_std  <- arm_b_weights(gm_std)
WB_test <- arm_b_weights(gm_test)
w(sprintf("  ARM-B (momentum): W_g ∝ max(z_g,0), %d-momentum군 + gap %d군 중립. 유효 월수=%d",
          length(intersect(names(shu2grp),GRP_FAMS)), length(SHU_GAP_GRP), length(WB_std)))

## ── 4) ARM별 종목 score 패널 구성 (PIT: t 리밸 시 t-1말 momentum 사용) ──
## grp$signal_date = t-1 월말(신호 시점). canonical_screen_bt가 forward Ret_1m로 t월 실현.
## ARM-B: signal_date(=신호월)에 해당하는 family momentum = 그 signal_date까지 trailing(12-1m). 동일 시점 매칭.
## PIT 핵심: signal_date(월말 d)에서 momentum은 [d-12m .. d-1m] 사용(skip_recent=1로 d월 자체도 제외 안전).
##   shumulvey meom(월말)을 signal_date(월말)에 ym 매칭. fmom row의 meom = 신호 산출 시점.

# grp에 ym 키
grp[, ym := format(signal_date, "%Y-%m")]
gm_key <- function(gm){ d<-copy(gm); d[, ym := format(as.Date(meom),"%Y-%m")]; d }
gm_std_k <- gm_key(gm_std)

build_scores <- function(arm, Wlist=NULL){
  # arm="A": 고정 W_static. arm="B": Wlist[ym] 사용.
  out <- grp[, .(signal_date, security_id, family, gz, ym)]
  if(arm=="A"){
    out[, wg := W_static[family]]
  } else {
    # ym별 W_group 매핑
    wdt <- rbindlist(lapply(names(Wlist), function(k){
      data.table(meom=k, family=names(Wlist[[k]]), wg=as.numeric(Wlist[[k]]))
    }))
    wdt[, ym := format(as.Date(meom),"%Y-%m")]
    out <- merge(out, wdt[, .(ym, family, wg)], by=c("ym","family"), all.x=TRUE)
    out <- out[!is.na(wg)]   # momentum 미성립 초기월 제거(양 ARM 동일 구간 정렬은 아래서)
  }
  # 종목 score = Σ_g wg·gz
  s <- out[, .(score = sum(wg * gz, na.rm=TRUE)), by=.(signal_date, security_id)]
  s[, score := zc(score), by=signal_date]   # 월별 재표준화(top-N 선택은 순위만 쓰지만 일관성)
  s
}
scA <- build_scores("A")
scB <- build_scores("B", WB_std)
# 공정 비교: 양 ARM 동일 signal_date 집합으로 정렬(ARM-B momentum 워밍업 이후)
common_sd <- sort(intersect(unique(scA$signal_date), unique(scB$signal_date)))
scA <- scA[signal_date %in% common_sd]
scB <- scB[signal_date %in% common_sd]
w(sprintf("\n=== 4) 종목 score 패널 — 공통 signal_date %d개월 (%s ~ %s) ===",
          length(common_sd), as.character(min(common_sd)), as.character(max(common_sd))))

## ── 5) canonical_screen_bt 2-run (top25 EW long-only, 동일 forward·15bps·ADV) ──
bo  <- readRDS(".cache/_bo_fwdgic.rds"); fwd <- bo$fwd
ret_dt   <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date), Ticker, Ret_1m)]
bench_dt <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date), BM_Ret)]
liq_dt   <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date), Ticker, adv)]

run_arm <- function(sdt, id){
  canonical_screen_bt(
    scores_dt  = sdt[, .(Date=as.Date(signal_date), Ticker=security_id, score)],
    returns_dt = ret_dt, bench_dt = bench_dt,
    top_n = 25L, cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
    run_id = id, strategy_id = id)
}
csA <- run_arm(scA, "ARM_A_static")
csB <- run_arm(scB, "ARM_B_momentum")

w("\n=== 5) canonical_screen_bt 실측 (metric_type=canonical_screen, screening advisory) ===")
fmt_arm <- function(cs, nm){
  w(sprintf("  [%s] n_months=%d | net_SR=%+.3f | port_t_NWlag3=%+.2f (p=%.3f) | IR=%+.3f | turnover_ann=%.0f%%",
    nm, cs$n_months, cs$net_sr, cs$portfolio_alpha_t_nw_lag3, cs$portfolio_alpha_t_pvalue,
    cs$information_ratio, 100*cs$turnover_annual))
}
fmt_arm(csA, "ARM-A static")
fmt_arm(csB, "ARM-B momentum")

## ── 6) paired NW-t(lag-3): d_t = ARM_B_active − ARM_A_active ──
w("\n=== 6) paired NW-t(lag-3) — d_t = ARM_B_active − ARM_A_active ===")
prA <- as.data.table(csA$period_returns)[, .(date=as.Date(date), actA = ret_net - benchmark_ret)]
prB <- as.data.table(csB$period_returns)[, .(date=as.Date(date), actB = ret_net - benchmark_ret)]
D <- merge(prA, prB, by="date"); setorder(D, date)
D[, d := actB - actA]
n_d <- nrow(D); mean_d <- mean(D$d)
fit <- lm(d ~ 1, data=D)
nw  <- coeftest(fit, vcov = sandwich::NeweyWest(fit, lag=3, prewhite=FALSE))
paired_t <- as.numeric(nw[1,3]); paired_p <- as.numeric(nw[1,4])
# SR lift
sr_lift <- csB$net_sr - csA$net_sr
w(sprintf("  n(paired months) = %d", n_d))
w(sprintf("  mean(d) [월별 active diff] = %+.5f (%.4f%%/월)", mean_d, 100*mean_d))
w(sprintf("  paired NW-t(lag-3) = %+.3f (p=%.3f)", paired_t, paired_p))
w(sprintf("  net active SR lift (B−A) = %+.3f", sr_lift))
w(sprintf("  port_t lift (B−A) = %+.2f", csB$portfolio_alpha_t_nw_lag3 - csA$portfolio_alpha_t_nw_lag3))

## ── 7) PIT look-ahead 가드: momentum lag toggle test (skip=1 clean vs skip=0 오염) ──
w("\n=== 7) PIT look-ahead 가드: momentum lag toggle (skip_recent 1=clean vs 0=오염) ===")
scB_test <- build_scores("B", WB_test)
common_sd2 <- sort(intersect(unique(scA$signal_date), unique(scB_test$signal_date)))
scB_test <- scB_test[signal_date %in% common_sd2]
csB_test <- run_arm(scB_test, "ARM_B_momentum_lag0")
w(sprintf("  ARM-B clean (skip=1, t-12..t-2): port_t=%+.2f net_SR=%+.3f", csB$portfolio_alpha_t_nw_lag3, csB$net_sr))
w(sprintf("  ARM-B toggle(skip=0, t-12..t-1): port_t=%+.2f net_SR=%+.3f", csB_test$portfolio_alpha_t_nw_lag3, csB_test$net_sr))
w("  해석: 둘 다 trailing-only(미래월 0개 사용). skip=0은 직전월 포함(더 fast, reversal 노출↑)이나 여전히 PIT-clean.")
w("        t월 수익을 신호에 넣는 진짜 look-ahead는 본 설계상 불가(canonical forward Ret_1m은 신호 아닌 실현).")

## ── 8) cheap-kill 판정 ──
w("\n=== 8) cheap-kill 판정 ===")
kill <- (sr_lift < 0) || (paired_t < 1)
expand <- (sr_lift > 0) && (paired_t > 2)
verdict <- if(kill) "KILL" else if(expand) "EXPAND" else "BORDERLINE"
w(sprintf("  규칙: KILL = (SR lift<0) OR (paired-t<1) | EXPAND = (SR lift>0) AND (paired-t>2)"))
w(sprintf("  SR lift=%+.3f, paired-t=%+.3f → 판정: %s", sr_lift, paired_t, verdict))
if(verdict=="KILL")   w("  → factor-momentum-timing 무효력. 확대(full 316/crowding/value spread) 착수 금지. screen-tier.")
if(verdict=="EXPAND") w("  → 확대 정당. (다음: factor value spread·full 316 family·crowding interaction)")
if(verdict=="BORDERLINE") w("  → 경계. lift>0이나 t∈[1,2] — 보강증거 필요(holdout/subwindow), 자본 확대 보류.")

## ── 저장 ──
saveRDS(list(csA=csA, csB=csB, csB_test=csB_test, D=D,
             paired_t=paired_t, paired_p=paired_p, mean_d=mean_d, n_d=n_d,
             sr_lift=sr_lift, verdict=verdict,
             shu2grp=shu2grp, W_static=W_static), file.path(OUT,"_fof_first_slice.rds"))
fwrite(D, file.path(OUT,"paired_active_diff.csv"))

# 콘솔 머신리더블 라인
cat(sprintf("RESULT|n=%d|srA=%.4f|srB=%.4f|sr_lift=%.4f|ptA=%.3f|ptB=%.3f|paired_t=%.3f|paired_p=%.4f|mean_d=%.6f|verdict=%s\n",
  n_d, csA$net_sr, csB$net_sr, sr_lift, csA$portfolio_alpha_t_nw_lag3, csB$portfolio_alpha_t_nw_lag3,
  paired_t, paired_p, mean_d, verdict))
cat(sprintf("ARMA|net_sr=%.4f|port_t=%.3f|IR=%.4f|turnover=%.4f|n=%d\n", csA$net_sr, csA$portfolio_alpha_t_nw_lag3, csA$information_ratio, csA$turnover_annual, csA$n_months))
cat(sprintf("ARMB|net_sr=%.4f|port_t=%.3f|IR=%.4f|turnover=%.4f|n=%d\n", csB$net_sr, csB$portfolio_alpha_t_nw_lag3, csB$information_ratio, csB$turnover_annual, csB$n_months))
cat(sprintf("TOGGLE|clean_port_t=%.3f|clean_sr=%.4f|lag0_port_t=%.3f|lag0_sr=%.4f\n", csB$portfolio_alpha_t_nw_lag3, csB$net_sr, csB_test$portfolio_alpha_t_nw_lag3, csB_test$net_sr))
close(con)
cat("FOF_FIRST_SLICE_DONE\n")
