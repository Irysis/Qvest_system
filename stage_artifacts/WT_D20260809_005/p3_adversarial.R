## =============================================================================
## FQ-198 / WT-D20260809_005 — Self-Adversarial 실측 검증
##
## 자기 비평에서 제기한 concern 을 **말이 아니라 측정**으로 검증한다.
##   L1 PIT parity   : 스텝 프로토타입이 쓰는 consensus 원천 PIT 처리가 빌더와 같은가
##                     (내가 원천에서 재계산한 C01 이 커넥터 C01 과 월별 |spearman|=1 인가)
##   L2 z-basis 비대칭: DB 팩터는 Z_Score_Aligned(IC 기반 방향정렬), 프로토타입은 평 z(사전부호).
##                     방향정렬이 부호를 뒤집은 월이 있으면 비교가 어긋난다 → 부호 실측
##   L3 C15s 정체    : C01 통제 하 C15s 의 증분은 사실상 step[2](직전 분기 수준)인가
##   L4 C18 자기선택 : 좁은 커버리지(월~335종)가 만드는 표본이 incumbent 통제의 의미를 바꾸는가
##   L5 AX-001 v2    : 방어형 조건부 성과 (bad/normal IC ratio · 위기월 조건부)
##   L6 탐색 자유도  : exploratory 3종이 사전등록이 아니라는 사실의 정량 반영(Bonferroni 외 추가 바)
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
say <- function(fmt,...) { cat(sprintf(paste0("[adv] ",fmt,"\n"),...)); flush.console() }
set.seed(20260809L)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

nw_t <- function(x, lag=3L){ x <- x[is.finite(x)]; n <- length(x); if (n<20L) return(NA_real_)
  m <- mean(x); e <- x-m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }

RES <- readRDS(file.path(OUT,"p1_results.rds"))
A   <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet"))); A[, Date := as.Date(Date)]
INCUMBENT <- RES$INCUMBENT; ARMS <- RES$ARMS
say("★입력 실측: alpha_scores %d행 · %d개월 · %s ~ %s · 컬럼 %s",
    nrow(A), uniqueN(A$Date), min(A$signal_ym), max(A$signal_ym), paste(names(A), collapse=","))

## =============================================================================
## L1 — PIT parity: 원천 재계산 C01 vs 커넥터 C01
## =============================================================================
say("================ L1: PIT parity (원천 재계산 C01 ↔ 커넥터 C01) ================")
CD <- file.path(CACHE_DIR,"consensus")
sue <- as.data.table(read_parquet(file.path(CD,"sue.parquet"))); sue[, Date := as.Date(Date)]
pdates <- sort(unique(A$Date)); pdates <- pdates[seq(1, length(pdates), length.out=min(12L,length(pdates)))]
L1 <- rbindlist(lapply(pdates, function(d) {
  h <- sue[Date <= d & is.finite(sue)]
  if (!nrow(h)) return(NULL)
  setorderv(h, c("Ticker","Date"), c(1L,-1L))
  mine <- h[, .(c01_mine = sue[1L]), by=Ticker]
  z <- tryCatch(load_month_factors(d, factor_names="C01_SUE"), error=function(e) NULL)
  if (is.null(z)||!nrow(z)) return(NULL)
  zz <- as.data.table(z)[, .(Ticker, c01_db = Z_Score_Aligned)]
  m <- merge(mine, zz, by="Ticker")
  if (nrow(m) < 30L) return(NULL)
  data.table(ym=format(d,"%Y-%m"), n=nrow(m),
             spearman = cor(m$c01_mine, m$c01_db, method="spearman"))
}))
say("월별 |spearman| 요약: 중앙 %.6f · 최소 %.6f · +1 근사(>0.999) 월 %d/%d · -1 근사(<-0.999) 월 %d",
    median(abs(L1$spearman)), min(abs(L1$spearman)), sum(L1$spearman>0.999), nrow(L1), sum(L1$spearman< -0.999))
for (i in seq_len(nrow(L1))) with(L1[i], say("  %s n=%4d spearman %+.6f", ym, n, spearman))
say("★해석: |spearman|=1 이면 내 원천 PIT 처리 = 빌더와 동일(스텝 프로토타입도 같은 규약 위).")
say("       부호가 음이면 커넥터 방향정렬이 뒤집은 것 — L2 로 이어짐.")

## =============================================================================
## L2 — z-basis 비대칭: 프로토타입 부호가 사전지정과 맞는가 (사후 정렬 아님, 진단만)
## =============================================================================
say("================ L2: z-basis / 부호 진단 ================")
L2 <- rbindlist(lapply(intersect(ARMS, names(A)), function(a_) {
  s <- A[is.finite(get(a_)) & is.finite(Ret_1m),
         .(ic = suppressWarnings(cor(get(a_), Ret_1m, method="spearman", use="complete.obs")), n=.N),
         by=signal_ym][n>=30L & is.finite(ic)]
  data.table(arm=a_, n_months=nrow(s), mean_ic=mean(s$ic), ic_t=nw_t(s$ic), ic_pos_rate=mean(s$ic>0))
}))
for (i in seq_len(nrow(L2))) with(L2[i], say(
  "  %-26s 단독 rank-IC %+.4f (t %+.2f · IC>0 %.1f%% · %d개월) ⇒ 사전지정 부호(+)와 %s",
  arm, mean_ic, ic_t, ic_pos_rate*100, n_months, ifelse(mean_ic>0,"일치","불일치")))
say("★프로토타입은 IC 로 사후 정렬하지 않았다(C13 규칙). 위는 진단이지 정렬이 아니다.")

## =============================================================================
## L3 — C15s 정체: C01 통제 하 증분이 step[2] 인가
## =============================================================================
say("================ L3: C15s 의 증분 정체 ================")
if ("C15s_SUE_Trend_step" %in% names(A)) {
  sub <- A[is.finite(C15s_SUE_Trend_step) & is.finite(C01_SUE)]
  r <- sub[, .(rho = suppressWarnings(cor(C15s_SUE_Trend_step, C01_SUE, method="spearman", use="complete.obs")), n=.N),
           by=signal_ym][n>=30L & is.finite(rho)]
  say("  C15s vs C01 월별 spearman: 평균 %+.4f (sd %.3f · n=%d개월)", mean(r$rho), sd(r$rho), nrow(r))
  say("  ★C15s = step[1]-step[2] 이고 C01 ≈ step[1] 이므로, C01 통제 후 C15s 의 증분은")
  say("    사실상 **-step[2](직전 분기 수준)** 의 정보다. 이는 '추세'가 아니라 '직전 수준의 역방향'일 수 있다 —")
  say("    부호 해석 시 이 정체를 명시할 것(재료 자격 자체는 무효화하지 않음).")
} else say("  C15s 부재 — 생략")

## =============================================================================
## L4 — C18 자기선택: 좁은 커버리지가 표본을 바꾸는가
## =============================================================================
say("================ L4: C18 이벤트 자기선택 ================")
if ("C18_Earnings_CAR_3d" %in% names(A)) {
  A[, has_c18 := is.finite(C18_Earnings_CAR_3d)]
  cmp <- A[is.finite(Ret_1m), .(n=.N, mean_ret=mean(Ret_1m),
              mean_c01=mean(C01_SUE, na.rm=TRUE), mean_size=mean(log(pmax(Size,1)), na.rm=TRUE)),
           by=has_c18]
  print(cmp)
  ## 같은 달 안에서 C18 보유군 vs 미보유군 익월 수익 차 (월별 → NW t)
  d <- A[is.finite(Ret_1m), .(diff = mean(Ret_1m[has_c18]) - mean(Ret_1m[!has_c18]),
                              n1=sum(has_c18), n0=sum(!has_c18)), by=signal_ym][n1>=20 & n0>=20]
  say("  C18 보유군 − 미보유군 익월 수익차: 월평균 %+.5f · NW t %+.2f · %d개월",
      mean(d$diff), nw_t(d$diff), nrow(d))
  say("  ★유의하면 C18 표본 자체가 수익 편의를 갖는다 = incumbent 통제의 의미가 달라진다.")
  ## 증분 회귀 표본과 전표본의 incumbent 계수 비교 (통제의 의미 변화 실측)
  fmb <- function(dat, xs) dat[, { fit <- tryCatch(lm(as.formula(paste("Ret_1m ~", paste(xs,collapse="+"))), data=.SD),
                                                   error=function(e) NULL)
      if (is.null(fit)) .(term=character(0), est=numeric(0)) else { cf <- coef(fit); .(term=names(cf), est=as.numeric(cf)) } },
      by=signal_ym, .SDcols=c("Ret_1m",xs)]
  full <- A[complete.cases(A[, ..INCUMBENT]) & is.finite(Ret_1m)]
  narrow <- full[has_c18 == TRUE]
  for (tag in c("full","narrow")) {
    dd <- get(tag); mm <- dd[, .N, by=signal_ym]; dd <- dd[signal_ym %in% mm[N>=30L, signal_ym]]
    cf <- fmb(dd, INCUMBENT)
    for (v in INCUMBENT) { e <- cf[term==v, est]
      say("  [%-6s] %-16s n=%3d · mean %+.6f · t %+.2f", tag, v, length(e), mean(e), nw_t(e)) }
  }
} else say("  C18 부재 — 생략")

## =============================================================================
## L5 — AX-001 v2 조건부 (방어형 판정 시 의무)
## =============================================================================
say("================ L5: AX-001 v2 조건부 (bad/normal IC ratio) ================")
BM <- tryCatch({
  RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","BM_Ret")))
  RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date,"%Y-%m")]
  RAW[, .(bm = prod(1+BM_Ret[is.finite(BM_Ret)])-1), by=.(ym, Ticker)][, .(bm=mean(bm)), by=ym]
}, error=function(e) NULL)
if (!is.null(BM)) {
  L5 <- rbindlist(lapply(intersect(ARMS, names(A)), function(a_) {
    s <- A[is.finite(get(a_)) & is.finite(Ret_1m),
           .(ic=suppressWarnings(cor(get(a_), Ret_1m, method="spearman", use="complete.obs")), n=.N),
           by=signal_ym][n>=30L & is.finite(ic)]
    s <- merge(s, BM, by.x="signal_ym", by.y="ym")
    bad <- s[bm < 0]; nor <- s[bm >= 0]
    if (!nrow(bad) || !nrow(nor)) return(NULL)
    data.table(arm=a_, n_bad=nrow(bad), ic_bad=mean(bad$ic), n_nor=nrow(nor), ic_nor=mean(nor$ic),
               ratio = mean(bad$ic)/mean(nor$ic),
               n_crisis=nrow(s[bm < -0.10]), ic_crisis=mean(s[bm < -0.10]$ic))
  }))
  for (i in seq_len(nrow(L5))) with(L5[i], say(
    "  %-26s bad(bm<0) n=%3d IC %+.4f | normal n=%3d IC %+.4f | ratio %+.2f | crisis(bm<-10%%) n=%d IC %+.4f",
    arm, n_bad, ic_bad, n_nor, ic_nor, ratio, n_crisis, ic_crisis))
  fwrite(L5, file.path(OUT,"p3_ax001.csv"))
} else say("  BM 로드 실패 — AX-001 조건부 생략(진단 불가로 표기, 추측 금지)")

## =============================================================================
## L6 — 탐색 자유도: exploratory arm 의 실질 다중검정 바
## =============================================================================
say("================ L6: 탐색 자유도 ================")
say("  보고 arm 4 → Bonferroni 양측 alpha .05/4 ⇒ |t| >= 2.50")
say("  ★단 exploratory 3종은 사전등록 원안(4종 DB 팩터)에 없었고 P0 사전 확인 중 발견됐다.")
say("    '스텝 압축'은 내가 고른 여러 가능한 수리 중 하나다(대안: 분기 리샘플·달력 lag·이벤트 정렬).")
say("    ⇒ exploratory arm 은 primary 와 같은 증거력으로 읽지 말 것. 자본 경로 진입 전")
say("      **독립 사전등록 라운드에서 재현**이 조건이다(부활 조건에 명시).")

saveRDS(list(L1=L1, L2=L2), file.path(OUT,"p3_adversarial.rds"))
fwrite(L1, file.path(OUT,"p3_pit_parity.csv")); fwrite(L2, file.path(OUT,"p3_sign_diag.csv"))
say("저장 완료")
