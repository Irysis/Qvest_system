## P0e — 기전 확정 2차: 왜 C10 ≡ C01 인가
##
## ★자기 정정: P0c 에서 세운 "이력 깊이 1" 가설은 P0d 실측으로 **기각**됐다
##   (sue 이력 깊이 중앙 536 · 깊이>=2 비율 1.0000).
## 새 가설: consensus 원천이 **일간**(sue 고유 Date 6140개/25년)인데 C10 은
##   `mean(sue[1:min(.N,4)])` = 최근 **4개 관측 = 4 영업일** 평균이다.
##   SUE 는 분기 실적발표로만 갱신되는 계단함수이므로 최근 4영업일 값이 전부 같다
##   ⇒ 평균 = 최신값 = C01_SUE.  "4분기 이동평균" 의도가 "4일 이동평균" 으로 구현됨.
## 같은 논리로 C13 = mean(esbr[1:3]) = 최근 3영업일 평균, C15 = sue[1]-sue[2] = 인접 2영업일 차분(≈0).
## ★추론으로 끝내지 않고 원천에서 직접 잰다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260809_005")
say <- function(fmt,...) { cat(sprintf(paste0("[p0e] ",fmt,"\n"),...)); flush.console() }
source("02_Infrastructure/config.R")

CD <- file.path(CACHE_DIR, "consensus")
sue  <- as.data.table(read_parquet(file.path(CD,"sue.parquet")));  sue[,  Date := as.Date(Date)]
esbr <- as.data.table(read_parquet(file.path(CD,"esbr.parquet"))); esbr[, Date := as.Date(Date)]

## [1] 관측 간격 — 일간인가
for (nm in c("sue","esbr")) {
  dt <- get(nm)
  ds <- sort(unique(dt$Date))
  gap <- as.numeric(diff(ds))
  say("%s: 고유 Date %d · 간격 중앙 %.0f일 (최소 %d · 최대 %d) ⇒ 관측단위 = %s",
      nm, length(ds), median(gap), min(gap), max(gap),
      if (median(gap) <= 4) "일간(영업일)" else "저빈도")
}

## [2] ★계단함수 확인: 인접 관측 간 값이 바뀌는 비율
say("================ [2] 계단성 — 인접 영업일 간 값 변화율 ================")
for (nm in c("sue","esbr")) {
  dt <- copy(get(nm)); v <- nm
  setorderv(dt, c("Ticker","Date"))
  dt[, prev := shift(get(v), 1L, type="lag"), by=Ticker]
  d <- dt[is.finite(prev) & is.finite(get(v))]
  chg <- d[, mean(get(v) != prev)]
  say("  %s: 인접 관측 %d쌍 · 값이 **바뀌는** 비율 %.6f · 동일 비율 %.6f",
      nm, nrow(d), chg, 1-chg)
  ## 최근 4개 관측이 전부 동일한 Ticker-Date 비율 (= C10 이 C01 과 같아지는 조건)
  for (k in c(2L,3L,4L)) {
    dt2 <- copy(dt); setorderv(dt2, c("Ticker","Date"), c(1L,-1L))
    dt2[, rn := seq_len(.N), by=Ticker]
    top <- dt2[rn <= k]
    same <- top[, .(all_same = uniqueN(get(v))==1L, n=.N), by=Ticker][n==k]
    say("    최근 %d개 관측이 전부 동일한 Ticker 비율: %.6f (n=%d)", k, mean(same$all_same), nrow(same))
  }
}

## [3] ★직접 재현: 특정 sig_date 에서 C01/C10/C13/C15 raw 를 빌더 식 그대로 계산
say("================ [3] 빌더 식 직접 재현 (raw 레벨) ================")
cons_hist <- function(src, metric, sig_d) {
  h <- src[Date <= sig_d & !is.na(get(metric))]
  setorderv(h, c("Ticker","Date"), c(1L,-1L)); h[]
}
for (sd_ in as.Date(c("2010-06-30","2018-06-29","2026-07-31"))) {
  sh <- cons_hist(sue, "sue", sd_); eh <- cons_hist(esbr, "esbr", sd_)
  c01 <- sh[, .(c01 = sue[1L]), by=Ticker]                                   # latest
  c10 <- sh[, .(c10 = mean(sue[seq_len(min(.N,4L))])), by=Ticker]            # 빌더 식
  c15 <- sh[, .(c15 = if (.N>=2L) sue[1L]-sue[2L] else NA_real_), by=Ticker] # 빌더 식
  c04 <- eh[, .(c04 = esbr[1L]), by=Ticker]
  c13 <- eh[, .(c13 = mean(esbr[seq_len(min(.N,3L))])), by=Ticker]
  m1 <- merge(c01, c10, by="Ticker"); m1 <- merge(m1, c15, by="Ticker")
  m2 <- merge(c04, c13, by="Ticker")
  say("  %s  C01 vs C10(raw): n=%d · 완전동일 %.6f · 최대절대차 %.3e · spearman %+.6f",
      sd_, nrow(m1), mean(m1$c01==m1$c10), max(abs(m1$c01-m1$c10)),
      cor(m1$c01, m1$c10, method="spearman"))
  say("  %s  C04 vs C13(raw): n=%d · 완전동일 %.6f · 최대절대차 %.3e · spearman %+.6f",
      sd_, nrow(m2), mean(m2$c04==m2$c13), max(abs(m2$c04-m2$c13)),
      cor(m2$c04, m2$c13, method="spearman"))
  z <- m1[is.finite(c15)]
  say("  %s  C15(raw = sue[1]-sue[2]): n=%d · **정확히 0 인 비율 %.6f** · 비영 %d · sd %.6e",
      sd_, nrow(z), mean(z$c15==0), sum(z$c15!=0), sd(z$c15))
}

## [4] ★의도대로라면? — 분기 스텝 기준 4-스텝 평균과 비교
say("================ [4] 의도된 정의(분기 스텝)로 계산하면 다른 팩터가 되는가 ================")
for (sd_ in as.Date(c("2018-06-29","2026-07-31"))) {
  sh <- cons_hist(sue, "sue", sd_)
  ## 값이 바뀌는 지점만 남겨 '스텝' 시계열로 압축 (최신 우선 정렬 상태)
  st <- sh[, {
    v <- sue; keep <- c(TRUE, v[-1] != v[-length(v)])
    .(step = v[keep])
  }, by=Ticker]
  a <- st[, .(c10_true = mean(step[seq_len(min(.N,4L))]),
              c15_true = if (.N>=2L) step[1L]-step[2L] else NA_real_,
              n_steps = .N), by=Ticker]
  b <- sh[, .(c01 = sue[1L]), by=Ticker]
  m <- merge(a, b, by="Ticker")
  say("  %s  스텝 개수 중앙 %.0f · C01 vs C10_true: n=%d · 완전동일 %.4f · spearman %+.4f",
      sd_, median(m$n_steps), nrow(m), mean(m$c01==m$c10_true),
      cor(m$c01, m$c10_true, method="spearman", use="complete.obs"))
  mv <- m[is.finite(c15_true)]
  say("  %s  C15_true(스텝 차분): n=%d · 0 비율 %.4f · sd %.4f · C01 과 spearman %+.4f",
      sd_, nrow(mv), mean(mv$c15_true==0), sd(mv$c15_true),
      cor(mv$c01, mv$c15_true, method="spearman"))
}
say("완료")
