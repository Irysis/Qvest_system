## probe_a5_stock25.R — A5(분기 팩터모멘텀 배분)의 25종목 배포 형태 변환 소규모 실측 프로브
## READ-ONLY 조사: 기존 파이프라인 파일 무수정. 산출물은 본 디렉터리에만.
## 측정은 전부 계약 경유(canonical_screen_bt / weighted_screen_bt). 자체합성 금지.
##
## 사전등록 명세: stage_artifacts/probe_a5_20260822/probe_a5_prereg.json
##
## PIT 규약:
##   - 결정일 d0 = 월말 거래일. Z = load_month_factors(d0) (C13/14/15 경유, Z_Score_Aligned)
##   - w_f = A5 팩터비중, 결정월 말(d0) 정보만 사용 (S[m-1,] = m-1월까지 지수수익 12M active)
##   - 스코어(d0) -> 익월(d0->d1) 실현수익. 유동성 = adv20_t1 (C10, 당일 미포함)
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
setDTthreads(4)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_adv20_t1 / build_monthly_forward_returns

OUT <- file.path(QM, "stage_artifacts/probe_a5_20260822")
suppressMessages({library(sandwich); library(lmtest)})
nwt <- function(x){x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m, lag=3, prewhite=FALSE))[1,3])}
IRf <- function(x){x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12)}

## ─────────────────────────────────────────────────────────────────────────────
## 0) 팩터 매핑 (ramp_shumulvey_indices.R broad-21 FAC 벡터 — 재타이핑 아님: 동일 소스 파싱)
## ─────────────────────────────────────────────────────────────────────────────
FAC <- c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
         Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
         Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
         Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
         LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
         Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
         Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
         ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")

## ─────────────────────────────────────────────────────────────────────────────
## 1) A5 지수-레벨 재현 + 월별 적용 비중 기록 (위상 보존: 전 구간에서 돌린 뒤 창만 자름)
## ─────────────────────────────────────────────────────────────────────────────
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
R[, ym := format(Date, "%Y-%m")]
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x), x, 0))-1), .(medate=max(Date))),
         by=ym, .SDcols=c("Market", fac)]
setorder(mon, medate); NM <- nrow(mon); NAx <- 1+length(fac)
stopifnot(identical(sort(fac), sort(names(FAC))))

S <- matrix(NA_real_, NM, length(fac)); colnames(S) <- fac
for (fi in seq_along(fac)) for (m in 12:NM) { w <- (m-11):m
  S[m, fi] <- prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w]) - 1 }

BPS <- 15; FREQ <- 3L; START_M <- 13L
Wapp <- matrix(NA_real_, NM, NAx); colnames(Wapp) <- c("Market", fac)
isdec <- rep(FALSE, NM); decidx <- rep(NA_integer_, NM)
pr <- rep(NA_real_, NM); tov <- rep(NA_real_, NM)
wprev <- rep(1/NAx, NAx); wcur <- NULL; cur_dec <- NA_integer_
for (m in START_M:NM) { d <- m-1
  if (is.null(wcur) || ((m-START_M) %% FREQ == 0)) {
    s <- S[d, ]; pos <- which(is.finite(s) & s>0); w <- rep(0, NAx)
    if (length(pos)==0) w[1] <- 1 else w[1+pos] <- s[pos]/sum(s[pos])
    wcur <- w; isdec[m] <- TRUE; cur_dec <- m }
  decidx[m] <- cur_dec
  Wapp[m, ] <- wcur
  ri <- unlist(mon[m, c("Market", fac), with=FALSE]); ri[!is.finite(ri)] <- 0
  dlt <- sum(abs(wcur-wprev)); tov[m] <- dlt
  pr[m] <- sum(wcur*ri) - (BPS/1e4)*dlt
  wd <- wcur*(1+ri); wprev <- wd/sum(wd); wcur <- wprev }

cat(sprintf("[1] A5 지수레벨 재현: NM=%d | 유효 %d개월 | Market-fallback(w_Market>0) 개월 = %d\n",
  NM, sum(is.finite(pr)), sum(is.finite(Wapp[,1]) & Wapp[,1] > 1e-8)))

## ─────────────────────────────────────────────────────────────────────────────
## 2) 측정 창 (최근 5년) + 월말 거래일 + forward returns/벤치/유동성
## ─────────────────────────────────────────────────────────────────────────────
WIN_FIRST_FWD <- "2021-08"; WIN_LAST_FWD <- "2026-07"
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
RAW <- RAW[Date >= as.Date("2021-01-01") & Date <= as.Date("2026-07-31")]
alld <- sort(unique(RAW$Date)); rym <- format(alld, "%Y-%m")
ME_all <- alld[!duplicated(rym, fromLast=TRUE)]
# 결정일 = 예측월 직전 월말. 예측월 2021-08 ~ 2026-07  ->  결정일 2021-07말 ~ 2026-06말
# ME 는 마지막 forward 구간 종점(2026-07말)까지 포함해야 Ret_1m 이 만들어진다.
ME <- ME_all[format(ME_all,"%Y-%m") >= "2021-07" & format(ME_all,"%Y-%m") <= "2026-07"]
cat(sprintf("[2] 월말 거래일 %d개: %s ~ %s\n", length(ME), as.character(min(ME)), as.character(max(ME))))

ADV20 <- build_adv20_t1(RAW[, .(Date, Ticker, Vol, Close)], at_dates = ME)
RAWME <- RAW[Date %in% ME]
SIZE_ME <- RAWME[, .(Date, Ticker, Size)]
rm(RAW); invisible(gc())
fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
RET <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
BEN <- fwd$bench_dt[, .(Date=as.Date(Date), BM_Ret)]
LIQ <- fwd$liq_dt[, .(Date=as.Date(Date), Ticker, adv)]
setattr(LIQ, "liq_ruler", attr(fwd$liq_dt, "liq_ruler", exact=TRUE))
setattr(LIQ, "liq_ruler_source", attr(fwd$liq_dt, "liq_ruler_source", exact=TRUE))
cat(sprintf("    liq_ruler=%s | returns %d행 %d월 | bench %d월\n", fwd$liq_ruler,
  nrow(RET), uniqueN(RET$Date), nrow(BEN)))

## 결정일 목록 (forward 월이 창 안에 있는 것)
DEC <- data.table(d0 = ME[-length(ME)])
DEC[, fwd_ym := format(ME[-1], "%Y-%m")]
DEC <- DEC[fwd_ym >= WIN_FIRST_FWD & fwd_ym <= WIN_LAST_FWD]
DEC[, mrow := match(fwd_ym, mon$ym)]
stopifnot(!any(is.na(DEC$mrow)))
DEC[, is_dec := isdec[mrow]]
cat(sprintf("[2b] 측정 결정일 %d개 (%s ~ %s) | 그중 A5 분기결정월 %d개\n",
  nrow(DEC), as.character(min(DEC$d0)), as.character(max(DEC$d0)), sum(DEC$is_dec)))

## ─────────────────────────────────────────────────────────────────────────────
## 3) Z 패널 로드 (결정일별 1회) + 유니버스 교집합
## ─────────────────────────────────────────────────────────────────────────────
ZCACHE <- file.path(OUT, "_zpanel.rds")
if (file.exists(ZCACHE)) { ZP <- readRDS(ZCACHE) } else {
  ZP <- list()
  for (i in seq_len(nrow(DEC))) { d0 <- DEC$d0[i]
    uni <- RAWME[Date==d0 & ((!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)) &
                 is.finite(Size) & Size>0, .(Ticker, cap=Size)]
    f0 <- tryCatch(load_month_factors(d0, factor_names=unname(FAC)), error=function(e) NULL)
    if (is.null(f0) || !nrow(f0)) next
    asof <- attr(f0, "factor_db_asof_date", exact=TRUE)
    f <- merge(as.data.table(f0), uni, by="Ticker")   # 유니버스 교집합 (비유니버스 오염 차단)
    ZP[[as.character(d0)]] <- list(f=f, uni=uni, asof=asof)
    if (i %% 12 == 0) cat(sprintf("    Z 로드 %d/%d (%s)\n", i, nrow(DEC), as.character(d0)))
  }
  saveRDS(ZP, ZCACHE)
}
cat(sprintf("[3] Z 패널 %d개월 로드 완료\n", length(ZP)))

## ─────────────────────────────────────────────────────────────────────────────
## 4) 3가지 변환 규칙으로 스코어 패널 구성
##    B1 = Z-합성      Score_i = sum_f w_f * Z_f,i                      (prereg A6 형)
##    B2 = 멤버십      Score_i = sum_f (w_f/|H_f|) * 1{i in H_f}        (지수-충실, EW-within)
##    B3 = 내재비중    pi_i    = sum_f w_f * cap_i 1{i in H_f} / sum_{H_f} cap  (지수-충실, cap-w)
##    C0 = 대조군      w_f = 1/21 고정 (팩터모멘텀 무배분) x Z-합성
##    H_f = 상위 1/3 (지수 구성 규칙 그대로, ramp_shumulvey_indices.R)
## ─────────────────────────────────────────────────────────────────────────────
mk_scores <- function(mode, wsrc) {
  rows <- vector("list", nrow(DEC))
  for (i in seq_len(nrow(DEC))) { d0 <- DEC$d0[i]; z <- ZP[[as.character(d0)]]
    if (is.null(z)) next
    wv <- if (identical(wsrc,"EW")) setNames(rep(1/length(fac), length(fac)), fac)
          else setNames(Wapp[DEC$mrow[i], -1], fac)
    if (sum(wv) <= 1e-12) next                      # Market-fallback 월 = 종목 신호 없음
    f <- z$f
    tk <- z$uni$Ticker; capv <- setNames(z$uni$cap, z$uni$Ticker)
    sc <- setNames(rep(0, length(tk)), tk); hit <- setNames(rep(0, length(tk)), tk)
    for (nm in names(FAC)) { wf <- wv[[nm]]; if (!is.finite(wf) || wf <= 0) next
      sub <- f[Factor_Name == FAC[[nm]] & is.finite(Z_Score_Aligned)]
      if (nrow(sub) < 15) next
      if (mode == "B1") {
        v <- setNames(sub$Z_Score_Aligned, sub$Ticker)
        sc[names(v)] <- sc[names(v)] + wf * v
        hit[names(v)] <- hit[names(v)] + wf
      } else {
        thr <- quantile(sub$Z_Score_Aligned, 2/3, na.rm=TRUE)
        H <- sub[Z_Score_Aligned >= thr, Ticker]
        if (!length(H)) next
        if (mode == "B2") { sc[H] <- sc[H] + wf/length(H) }
        else { cw <- capv[H]; sc[H] <- sc[H] + wf * cw/sum(cw) }
        hit[H] <- hit[H] + wf
      }
    }
    keep <- hit > 0
    if (!any(keep)) next
    rows[[i]] <- data.table(Date=d0, Ticker=names(sc)[keep], score=as.numeric(sc[keep]))
  }
  rbindlist(rows)
}

SC <- list(B1 = mk_scores("B1","A5"), B2 = mk_scores("B2","A5"),
           B3 = mk_scores("B3","A5"), C0 = mk_scores("B1","EW"))
for (nm in names(SC)) cat(sprintf("[4] %s 스코어: %d행 / %d월\n", nm, nrow(SC[[nm]]), uniqueN(SC[[nm]]$Date)))

## B1Q = 분기 동결(선택을 분기 결정월에만 갱신 — 회전율 축소 변형)
frz <- NULL; rows <- vector("list", nrow(DEC))
for (i in seq_len(nrow(DEC))) { d0 <- DEC$d0[i]
  if (isTRUE(DEC$is_dec[i]) || i == 1L) { cand <- SC$B1[Date == d0, .(Ticker, score)]
    if (nrow(cand)) frz <- cand }
  if (is.null(frz) || !nrow(frz)) next
  rows[[i]] <- data.table(Date=d0, Ticker=frz$Ticker, score=frz$score) }
SC$B1Q <- rbindlist(rows)
cat(sprintf("[4] B1Q(분기동결) 스코어: %d행 / %d월\n", nrow(SC$B1Q), uniqueN(SC$B1Q$Date)))

## ─────────────────────────────────────────────────────────────────────────────
## 5) 계약 측정 — canonical_screen_bt (top-25 EW long-only, 15bps, adv20 2e8)
## ─────────────────────────────────────────────────────────────────────────────
res <- list()
for (nm in names(SC)) {
  s <- SC[[nm]][is.finite(score)]
  cs <- canonical_screen_bt(s, RET, BEN, top_n=25L, cost_bps_oneway=15,
        liq_dt=LIQ, liq_min=2e8, run_id=paste0("probe_a5_", tolower(nm)),
        strategy_id=paste0("PROBE_A5_", nm), diag_dual_basis=TRUE, size_dt=SIZE_ME)
  res[[nm]] <- cs
  pr2 <- as.data.table(cs$period_returns); act <- pr2$ret_net - pr2$benchmark_ret
  cat(sprintf("  [%s] n=%d PORT_t=%+.3f IR=%+.3f 연평균active=%+.2f%%p netSR=%+.3f TO=%.2f cov=%.3f\n",
    nm, cs$n_months, cs$portfolio_alpha_t_nw_lag3, cs$information_ratio,
    100*mean(act)*12, cs$net_sr, cs$turnover_annual, cs$selected_ret_coverage))
}

## 5b) B3 내재비중을 실제 가중으로 (top-25, w ∝ pi, cap 0.20, Σw=1) — weighted_screen_bt
w3 <- SC$B3[is.finite(score) & score > 0]
w3 <- merge(w3, LIQ, by=c("Date","Ticker"), all.x=TRUE)[is.na(adv) | adv >= 2e8]
setorder(w3, Date, -score)
w3 <- w3[, head(.SD, 25L), by=Date]
capw <- function(v, cap=0.20) { w <- v/sum(v)
  for (k in 1:100) { if (max(w) <= cap + 1e-12) break
    ex <- pmax(w-cap, 0); w <- pmin(w, cap); w <- w + sum(ex)*w/sum(w) }
  w/sum(w) }
w3[, w := capw(score), by=Date]
ws <- weighted_screen_bt(w3[, .(Date, Ticker, w)], RET, BEN, cost_bps_oneway=15,
      run_id="probe_a5_b3w", strategy_id="PROBE_A5_B3W")
res[["B3w"]] <- ws
pr3 <- as.data.table(ws$period_returns); act3 <- pr3$ret_net - pr3$benchmark_ret
cat(sprintf("  [B3w] n=%d PORT_t=%+.3f IR=%+.3f 연평균active=%+.2f%%p TO=%.2f (cap0.20 비중)\n",
  ws$n_months, ws$portfolio_alpha_t_nw_lag3, ws$information_ratio, 100*mean(act3)*12,
  ws$turnover_annual))

## ─────────────────────────────────────────────────────────────────────────────
## 6) 창-정합 지수레벨 A5 기준자 (같은 60개월)
## ─────────────────────────────────────────────────────────────────────────────
kw <- mon$ym >= WIN_FIRST_FWD & mon$ym <= WIN_LAST_FWD & is.finite(pr)
a5p <- pr[kw]; a5m <- mon$Market[kw]; a5act <- a5p - a5m
cat(sprintf("\n[6] 창-정합 지수레벨 A5 (%s~%s, n=%d): PORT_t=%+.3f IR=%+.3f 연평균active=%+.2f%%p TO=%.2f\n",
  WIN_FIRST_FWD, WIN_LAST_FWD, sum(kw), nwt(a5act), IRf(a5act), 100*mean(a5act)*12,
  mean(tov[kw], na.rm=TRUE)*12))
cat(sprintf("    (전체 236개월 A5 헤드라인: PORT_t 3.232 / oos 0.704 / calmar 0.309 — 참고)\n"))

## ─────────────────────────────────────────────────────────────────────────────
## 7) 저장
## ─────────────────────────────────────────────────────────────────────────────
tab <- rbindlist(lapply(names(res), function(nm) { cs <- res[[nm]]
  p <- as.data.table(cs$period_returns); a <- p$ret_net - p$benchmark_ret
  data.table(arm=nm, n_months=cs$n_months, PORT_t=cs$portfolio_alpha_t_nw_lag3,
    IR=cs$information_ratio, active_ann=100*mean(a)*12, net_SR=cs$net_sr,
    TO_ann=cs$turnover_annual,
    sel_cov=if(is.null(cs$selected_ret_coverage)) NA_real_ else cs$selected_ret_coverage,
    ew_uni_t = if (!is.null(cs$diag_ew_universe$portfolio_alpha_t_nw_lag3))
                 cs$diag_ew_universe$portfolio_alpha_t_nw_lag3 else NA_real_) }))
tab <- rbind(tab, data.table(arm="A5_index_windowmatched", n_months=sum(kw), PORT_t=nwt(a5act),
  IR=IRf(a5act), active_ann=100*mean(a5act)*12, net_SR=IRf(a5p), TO_ann=mean(tov[kw],na.rm=TRUE)*12,
  sel_cov=NA_real_, ew_uni_t=NA_real_), fill=TRUE)
fwrite(tab, file.path(OUT, "probe_a5_stock25_results.csv"))
saveRDS(list(res=res, tab=tab, DEC=DEC, Wapp=Wapp, isdec=isdec, mon=mon,
             liq_ruler=fwd$liq_ruler), file.path(OUT, "probe_a5_stock25.rds"))
cat("\n"); print(tab, digits=3)
cat("\nPROBE_A5_DONE\n")
