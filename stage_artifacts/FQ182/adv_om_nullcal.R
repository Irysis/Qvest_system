## FQ-182 적대검증 — STEP 5: null 공정성 보정
## 혐의(자기 반증): D3 의 t(5) 혁신이 과도하게 두꺼워 null 을 부풀린 것 아닌가?
## -> 혁신 분포 3종(t5 / t8 / 정규)으로 null 을 다시 만들고, **실측 첨도와 맞는 null** 을 1급으로 삼는다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182"); say <- function(fmt, ...) { cat(sprintf(paste0("[cal] ", fmt, "\n"), ...)); flush.console() }
skew1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<3||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^3)/n/s^3}
kurt1 <- function(v){v<-v[is.finite(v)];n<-length(v);s<-sd(v);if(n<4||!is.finite(s)||s==0)return(NA_real_);sum((v-mean(v))^4)/n/s^4-3}
set.seed(20260810)

BD <- as.data.table(readRDS(file.path(ROOT,"stage_artifacts/alloc_daily/p0.rds"))$BD)[order(Date)]
r0 <- BD[is.finite(BM_Ret)][abs(BM_Ret)<0.5]$BM_Ret
n  <- length(r0); mu <- mean(r0); s2 <- var(r0)
say("=== 입력 실측 === n %d · mu %.6f · sd %.5f · 초과첨도 %.2f · 왜도 %.4f", n, mu, sqrt(s2), kurt1(r0), skew1(r0))
say("  ★실측 전기간 왜도 %.4f (음수 = 주식 표준 사실)", skew1(r0))

alpha <- 0.10; beta <- 0.88; omega <- s2*(1-alpha-beta)
gen <- function(kind, m) {
  if (kind == "t5") rt(m, df=5)/sqrt(5/3) else if (kind == "t8") rt(m, df=8)/sqrt(8/6) else rnorm(m)
}
sim1 <- function(kind, n) {
  e <- gen(kind, n+500); h <- numeric(n+500); h[1] <- s2; r <- numeric(n+500)
  for (t in seq_len(n+500)) { if (t>1) h[t] <- omega + alpha*(r[t-1]-mu)^2 + beta*h[t-1]; r[t] <- mu + sqrt(h[t])*e[t] }
  r[501:(500+n)]
}
run_null <- function(kind, NSIM = 400L) {
  o <- matrix(NA_real_, NSIM, 6)
  for (i in seq_len(NSIM)) {
    r <- sim1(kind, n); nav <- cumprod(1+r)
    dd <- nav/frollapply(nav,252,max,fill=NA,align="right") - 1
    f1 <- c(r[-1], NA_real_); k <- is.finite(dd)&is.finite(f1); dd<-dd[k]; f1<-f1[k]
    on <- dd <= -0.20
    if (sum(on)<100 || sum(!on)<100) next
    a<-skew1(f1[on]); of<-skew1(f1[!on])
    o[i,] <- c(sum(on), a, of, a-of, as.numeric(a>0 && of<0), kurt1(r))
  }
  O <- as.data.table(o); setnames(O, c("n_on","on_skew","off_skew","diff","signflip","kurt"))
  O[is.finite(diff)]
}
OBS_DIFF <- 0.5808; OBS_ON <- 0.2717
rows <- list()
for (kind in c("norm","t8","t5")) {
  V <- run_null(kind, 400L)
  say("--- null 혁신 = %-4s : 유효 %d · 시뮬 초과첨도 중앙 %.2f (실측 %.2f) · ON일 중앙 %.0f",
      kind, nrow(V), median(V$kurt), kurt1(r0), median(V$n_on))
  say("    null diff: 평균 %+.4f · sd %.4f · [5%%,95%%] = [%+.3f, %+.3f]",
      mean(V$diff), sd(V$diff), quantile(V$diff,.05), quantile(V$diff,.95))
  say("    ★P(diff >= %+.4f) = %.3f · ★P(부호뒤집힘) = %.3f · ★P(ON_skew >= %+.4f) = %.3f",
      OBS_DIFF, mean(V$diff >= OBS_DIFF), mean(V$signflip==1), OBS_ON, mean(V$on_skew >= OBS_ON))
  rows[[length(rows)+1L]] <- data.table(innov=kind, n_valid=nrow(V), sim_kurt_med=median(V$kurt),
    real_kurt=kurt1(r0), null_diff_mean=mean(V$diff), null_diff_sd=sd(V$diff),
    p_diff_ge_obs=mean(V$diff>=OBS_DIFF), p_signflip=mean(V$signflip==1),
    p_onskew_ge_obs=mean(V$on_skew>=OBS_ON), boot_se_claimed=0.1826)
}
R <- rbindlist(rows); fwrite(R, file.path(OUT, "adv_om_null_calibration.csv"))
say("=== ★핵심 대조: 주장이 쓴 블록부트 se = 0.1826 vs null 실제 sd ===")
print(R[, .(innov, sim_kurt_med=round(sim_kurt_med,2), null_diff_sd=round(null_diff_sd,3),
            se_understate_x = round(null_diff_sd/0.1826,1), p_diff_ge_obs, p_signflip)])
say("=== STEP 5 완료 ===")
