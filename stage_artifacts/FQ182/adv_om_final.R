## FQ-182 적대검증 — STEP 6: 첨도-정합 null (1급) + 최종 요약표
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182"); say <- function(fmt, ...) { cat(sprintf(paste0("[fin] ", fmt, "\n"), ...)); flush.console() }
skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
kurt1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<4||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^4)/n/s^4-3}
set.seed(20260811)
BD <- as.data.table(readRDS(file.path(ROOT,"stage_artifacts/alloc_daily/p0.rds"))$BD)[order(Date)]
r0 <- BD[is.finite(BM_Ret)][abs(BM_Ret)<0.5]$BM_Ret
n <- length(r0); mu <- mean(r0); s2 <- var(r0); RK <- kurt1(r0)
alpha <- 0.10; beta <- 0.88; omega <- s2*(1-alpha-beta)
say("실측 초과첨도 %.2f · 실측 전기간 왜도 %+.4f", RK, skew1(r0))

sim1 <- function(df, n) {
  e <- rt(n+500, df=df)/sqrt(df/(df-2)); h <- numeric(n+500); h[1]<-s2; r <- numeric(n+500)
  for (t in seq_len(n+500)) { if (t>1) h[t] <- omega + alpha*(r[t-1]-mu)^2 + beta*h[t-1]; r[t] <- mu + sqrt(h[t])*e[t] }
  r[501:(500+n)]
}
run <- function(df, NSIM=500L) {
  o <- matrix(NA_real_, NSIM, 6)
  for (i in seq_len(NSIM)) {
    r <- sim1(df, n); nav <- cumprod(1+r)
    dd <- nav/frollapply(nav,252,max,fill=NA,align="right")-1
    f1 <- c(r[-1],NA_real_); k <- is.finite(dd)&is.finite(f1); dd<-dd[k]; f1<-f1[k]
    on <- dd <= -0.20; if (sum(on)<100||sum(!on)<100) next
    a<-skew1(f1[on]); of<-skew1(f1[!on])
    o[i,] <- c(sum(on), a, of, a-of, as.numeric(a>0&&of<0), kurt1(r))
  }
  O <- as.data.table(o); setnames(O,c("n_on","on_skew","off_skew","diff","signflip","kurt")); O[is.finite(diff)]
}
say("=== 첨도-정합 탐색 (t6, t7) ===")
best <- NULL
for (df in c(6,7)) {
  V <- run(df, 500L)
  say("  t%d: 시뮬 초과첨도 중앙 %.2f (목표 %.2f) · null diff sd %.3f · P(diff>=0.5808) %.3f · P(부호뒤집힘) %.3f · P(ON_skew>=0.2717) %.3f",
      df, median(V$kurt), RK, sd(V$diff), mean(V$diff>=0.5808), mean(V$signflip==1), mean(V$on_skew>=0.2717))
  if (is.null(best) || abs(median(V$kurt)-RK) < abs(median(best$kurt)-RK)) { best <- V; bdf <- df }
}
say("=== ★1급 null = t%d (첨도 정합 %.2f vs 실측 %.2f) ===", bdf, median(best$kurt), RK)
say("  null diff sd %.3f  vs  주장이 사용한 블록부트 se 0.1826  ->  se 과소평가 %.1f배",
    sd(best$diff), sd(best$diff)/0.1826)
say("  ★관측 diff +0.5808 의 null 확률 = %.3f", mean(best$diff >= 0.5808))
say("  ★관측 부호뒤집힘(ON>0 & OFF<0) 의 null 확률 = %.3f", mean(best$signflip==1))
say("  ★관측 ON_skew +0.2717 이상의 null 확률 = %.3f", mean(best$on_skew >= 0.2717))
fwrite(best, file.path(OUT, "adv_om_null_primary.csv"))

## ---------------- 최종 요약표 ----------------
SUM <- data.table(
  test = c("R0 기준선 재현(KR_BM 전기간)",
           "R1 타계열 재현 (dd<=-20%, 원창)",
           "R2 공통창 2002-2026/06 · 9계열",
           "R3 창-정합 (2026-07 이후 제거)",
           "R4 단일관측 제거 (2026-07-31 +19.98%)",
           "R5 시대분해 1991-1999",
           "R6 시대분해 2000-2009",
           "R7 계열정체 KR_BM vs indices::kospi200",
           "R8 첨도정합 null: 관측 diff 의 우연확률",
           "R9 첨도정합 null: 부호뒤집힘 우연확률",
           "R10 블록부트 se 대 null 실제 sd"),
  result = c("ON +0.2717 / OFF -0.3091 / diff +0.5808 / se 0.1826 / ratio 1.592 — 주장 수치 재현됨",
             "타 KR 주식계열 5종 전부 ON_skew < 0 (부호뒤집힘 0/5) · 최대 ratio 0.675 · SP500 ON 73일로 판정불가",
             "부호뒤집힘 3/9 (KR_BM·KOSPI200·KOSDAQ_large) · diff>0 9/9 · ratio>=1 3/9",
             "ON_skew +0.2723 -> +0.0914 · ratio 1.592 -> 0.991 (문턱 미달)",
             "ON_skew +0.2717 -> +0.0141 · diff +0.5808 -> +0.3231 · ratio 1.569 -> 1.001",
             "ON +0.3300 / OFF +0.2094 — OFF 도 양수, 뒤집힘 없음 · ratio 0.238",
             "ON -0.1602 / OFF -0.4415 — ON 이 음수, 뒤집힘 없음 · ratio 0.645",
             "일간 수익 상관 1.0000 · 완전동일 8976/8976 — 동일 지수(창만 다름)",
             sprintf("%.3f", mean(best$diff >= 0.5808)),
             sprintf("%.3f", mean(best$signflip==1)),
             sprintf("0.1826 vs %.3f — %.1f배 과소평가", sd(best$diff), sd(best$diff)/0.1826)),
  direction = c("중립(재현확인)","반증","혼합","반증","반증","반증","반증","맥락","반증","반증","반증")
)
fwrite(SUM, file.path(OUT, "adv_om_summary.csv"))
print(SUM)
say("=== STEP 6 완료 ===")
