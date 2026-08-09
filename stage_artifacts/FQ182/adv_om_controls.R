## FQ-182 적대검증(other_markets) — STEP 2: 통제
##  C1 창-정합: KR_BM 과 타 계열을 **공통 날짜**로 맞춘 뒤 재비교 (창 교락 제거)
##  C2 계열-정체: KR_BM(benchmark.parquet 계보) vs indices.parquet::kospi200 동일 지수인가
##  C3 시대 분해: 부호 뒤집힘이 특정 시대(1997-98)에 사는가
##  C4 에피소드 잭나이프: 병합 에피소드 1개 제거 시 결론이 유지되는가
##  C5 극단관측 의존: ON 최대 +수익 k개 제거 시 skew 잔존
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[ctl] ", fmt, "\n"), ...)); flush.console() }

skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
n_epi <- function(on, gap = 60L) { i <- which(on); if (!length(i)) return(0L); sum(diff(i) > gap) + 1L }
epi_id <- function(on, gap = 60L) {          ## ON 일에 병합 에피소드 번호 부여
  id <- rep(NA_integer_, length(on)); i <- which(on); if (!length(i)) return(id)
  g <- cumsum(c(1L, as.integer(diff(i) > gap))); id[i] <- g; id
}
bbskew <- function(x, on, B = 500L, blk = 60L) {
  n <- length(x); nb <- ceiling(n/blk); starts <- seq_len(max(1, n-blk+1)); o <- rep(NA_real_, B)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:min(k+blk-1, n))))[1:n]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 30 || sum(!ob) < 30) next
    o[b] <- skew1(xb[ob]) - skew1(xb[!ob])
  }
  o[is.finite(o)]
}
## 레벨 -> (Date, ret, dd252, fwd1)
mk <- function(dates, lvl) {
  ok <- is.finite(lvl) & !is.na(dates); d <- dates[ok]; l <- lvl[ok]
  o <- order(d); d <- d[o]; l <- l[o]
  D <- data.table(Date = d, ret = c(NA_real_, l[-1]/l[-length(l)] - 1))[is.finite(ret)][abs(ret) < 0.5]
  D
}
## 공통 날짜로 자른 뒤 **그 안에서** dd252/fwd1 재계산 (창-정합 규약)
finish <- function(D) {
  nav <- cumprod(1 + D$ret)
  D[, dd252 := nav / frollapply(nav, 252, max, fill = NA, align = "right") - 1]
  D[, fwd1 := shift(ret, 1L, type = "lead")]
  D[is.finite(dd252) & is.finite(fwd1)]
}
rep1 <- function(D, thr, lab, B = 500L) {
  on <- D$dd252 <= thr
  if (sum(on) < 100) { say("  %-26s dd<=%.0f%%: ON %d — 보류", lab, thr*100, sum(on))
    return(data.table(lab=lab, thr=thr*100, n=nrow(D), n_on=sum(on), n_epi=n_epi(on),
                      on_skew=NA_real_, off_skew=NA_real_, diff=NA_real_, se=NA_real_, ratio=NA_real_)) }
  a <- skew1(D$fwd1[on]); o <- skew1(D$fwd1[!on]); df <- a - o
  bs <- bbskew(D$fwd1, on, B); se <- sd(bs)
  say("  %-26s dd<=%.0f%%: n %d · ON %d (에피 %d) · ON_skew %+.4f · OFF_skew %+.4f · diff %+.4f · se %.4f · ratio %.3f",
      lab, thr*100, nrow(D), sum(on), n_epi(on), a, o, df, se, abs(df)/(2*se))
  data.table(lab=lab, thr=thr*100, n=nrow(D), n_on=sum(on), n_epi=n_epi(on),
             on_skew=a, off_skew=o, diff=df, se=se, ratio=abs(df)/(2*se))
}

set.seed(20260809)
IDX <- as.data.table(read_parquet(".cache/indices.parquet"))[order(Date)]
BD  <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/alloc_daily/p0.rds"))$BD)[order(Date)]

BMr  <- data.table(Date = BD$Date, ret = BD$BM_Ret)[is.finite(ret)][abs(ret) < 0.5]
K200 <- mk(IDX$Date, IDX$kospi200)
KOSP <- mk(IDX$Date, IDX$kospi)
KOSD <- mk(IDX$Date, IDX$kosdaq)

say("=== 입력 실측 ===")
say("  KR_BM   행 %d · %s ~ %s · sd %.5f", nrow(BMr), min(BMr$Date), max(BMr$Date), sd(BMr$ret))
say("  KOSPI200 행 %d · %s ~ %s · sd %.5f", nrow(K200), min(K200$Date), max(K200$Date), sd(K200$ret))
say("  KOSPI    행 %d · %s ~ %s · sd %.5f", nrow(KOSP), min(KOSP$Date), max(KOSP$Date), sd(KOSP$ret))
say("  KOSDAQ   행 %d · %s ~ %s · sd %.5f", nrow(KOSD), min(KOSD$Date), max(KOSD$Date), sd(KOSD$ret))

## ---------------- C2 계열 정체 ----------------
say("=== C2 계열-정체: KR_BM vs indices::kospi200 ===")
M <- merge(BMr[, .(Date, bm = ret)], K200[, .(Date, k2 = ret)], by = "Date")
say("  공통일 %d (KR_BM 단독 %d · KOSPI200 단독 %d)", nrow(M),
    nrow(BMr) - nrow(M), nrow(K200) - nrow(M))
say("  일간 수익 상관 %.4f · 평균절대차 %.5f · 완전동일일 비율 %.3f",
    cor(M$bm, M$k2), mean(abs(M$bm - M$k2)), mean(abs(M$bm - M$k2) < 1e-8))
say("  ★KR_BM 에만 있는 날짜 예: %s", paste(utils::head(setdiff(as.character(BMr$Date), as.character(K200$Date)), 6), collapse=" "))
say("  ★KOSPI200 에만 있는 날짜 예: %s", paste(utils::head(setdiff(as.character(K200$Date), as.character(BMr$Date)), 6), collapse=" "))

## ---------------- C1 창-정합 비교 ----------------
say("=== C1 창-정합 (공통 날짜 %d일에서 dd252 재계산) ===", nrow(M))
cmn <- M$Date
res <- list()
for (thr in c(-0.20, -0.30)) {
  res[[length(res)+1L]] <- rep1(finish(BMr[Date %in% cmn]), thr, "KR_BM @common")
  res[[length(res)+1L]] <- rep1(finish(K200[Date %in% cmn]), thr, "KOSPI200 @common")
  res[[length(res)+1L]] <- rep1(finish(KOSP[Date %in% cmn]), thr, "KOSPI @common")
}
## KOSDAQ 은 1997-05 시작 -> KR_BM 을 KOSDAQ 창으로 잘라 대조
say("=== C1b KOSDAQ 창(1997-05~)으로 KR_BM 재측정 ===")
cmn2 <- intersect(as.character(BMr$Date), as.character(KOSD$Date))
for (thr in c(-0.20, -0.30)) {
  res[[length(res)+1L]] <- rep1(finish(BMr[as.character(Date) %in% cmn2]), thr, "KR_BM @KOSDAQwin")
  res[[length(res)+1L]] <- rep1(finish(KOSD[as.character(Date) %in% cmn2]), thr, "KOSDAQ @KOSDAQwin")
}
## 2001+ 창 (KOSPI_small 창)
say("=== C1c 2001+ 창 ===")
for (thr in c(-0.20, -0.30)) {
  res[[length(res)+1L]] <- rep1(finish(BMr[Date >= as.Date("2001-01-01")]), thr, "KR_BM @2001+")
  res[[length(res)+1L]] <- rep1(finish(K200[Date >= as.Date("2001-01-01")]), thr, "KOSPI200 @2001+")
}
C1 <- rbindlist(res)
fwrite(C1, file.path(OUT, "adv_om_window_matched.csv"))

## ---------------- C3 시대 분해 (KR_BM 전기간) ----------------
say("=== C3 시대 분해 (KR_BM) ===")
FB <- finish(copy(BMr))
er <- list(c("1991-01-01","1999-12-31"), c("2000-01-01","2009-12-31"), c("2010-01-01","2026-12-31"),
           c("2000-01-01","2026-12-31"))
r3 <- list()
for (e in er) {
  S <- FB[Date >= as.Date(e[1]) & Date <= as.Date(e[2])]
  for (thr in c(-0.20)) r3[[length(r3)+1L]] <- rep1(S, thr, sprintf("KR_BM %s~%s", substr(e[1],1,4), substr(e[2],1,4)))
}
C3 <- rbindlist(r3); fwrite(C3, file.path(OUT, "adv_om_era.csv"))

## ---------------- C4 에피소드 잭나이프 (KR_BM, dd<=-20%) ----------------
say("=== C4 에피소드 잭나이프 (KR_BM dd<=-20%%) ===")
on <- FB$dd252 <= -0.20; eid <- epi_id(on, 60L)
full_a <- skew1(FB$fwd1[on]); full_o <- skew1(FB$fwd1[!on]); full_d <- full_a - full_o
say("  전체: ON_skew %+.4f · OFF_skew %+.4f · diff %+.4f · 에피소드 %d", full_a, full_o, full_d, max(eid, na.rm=TRUE))
jk <- list()
for (g in sort(unique(eid[!is.na(eid)]))) {
  keep <- !(on & eid == g & !is.na(eid))
  S <- FB[keep]; on2 <- S$dd252 <= -0.20
  if (sum(on2) < 100) next
  a2 <- skew1(S$fwd1[on2]); d2 <- a2 - skew1(S$fwd1[!on2])
  dts <- FB$Date[on & eid == g & !is.na(eid)]
  say("  에피 %2d 제거 (%s~%s · %3d일): ON_skew %+.4f (Δ%+.4f) · diff %+.4f (Δ%+.4f)",
      g, min(dts), max(dts), length(dts), a2, a2 - full_a, d2, d2 - full_d)
  jk[[length(jk)+1L]] <- data.table(epi=g, from=min(dts), to=max(dts), n=length(dts),
                                    on_skew=a2, d_on=a2-full_a, diff=d2, d_diff=d2-full_d)
}
C4 <- rbindlist(jk); fwrite(C4, file.path(OUT, "adv_om_episode_jackknife.csv"))
say("  ★ON_skew 부호 유지 에피소드 제거 수 = %d / %d", C4[on_skew > 0, .N], nrow(C4))

## ---------------- C5 극단관측 의존 ----------------
say("=== C5 극단관측 의존 (KR_BM dd<=-20%%, ON 표본에서 최대 +수익 k개 제거) ===")
v <- FB$fwd1[on]; vo <- FB$fwd1[!on]
r5 <- list()
for (k in c(0,1,2,3,5,10,20)) {
  v2 <- if (k == 0) v else v[order(-v)][-(1:k)]
  say("  k=%2d 제거: ON n %d · ON_skew %+.4f · (제거된 최대값 %s)", k, length(v2), skew1(v2),
      if (k==0) "-" else paste(sprintf("%.3f", sort(v, decreasing=TRUE)[1:min(k,3)]), collapse=","))
  r5[[length(r5)+1L]] <- data.table(k=k, n=length(v2), on_skew=skew1(v2), off_skew=skew1(vo))
}
C5 <- rbindlist(r5); fwrite(C5, file.path(OUT, "adv_om_extreme_dependence.csv"))
say("=== STEP 2 완료 ===")
