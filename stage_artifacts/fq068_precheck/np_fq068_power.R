## FQ-068 R1 검정력 판정 — 실제 계열 sd 로 (도구 caveat 준수: 25EW 스프레드 sd 대신 본 계열 sd)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/contracts/required_effect_size.R")
S <- fread("stage_artifacts/fq068_precheck/fq068_r1_sector_timing.csv")
say <- function(fmt,...) cat(sprintf(paste0("[pow] ",fmt,"\n"),...))

sd_exc <- sd(S$exc); sd_nm <- sd(S$exc_nm)
say("반도체 초과수익 계열 월 sd = %.4f (non-MEGA %.4f) · n=%d", sd_exc, sd_nm, nrow(S))
say("  참고: 도구 기본값(25EW 바스켓 쌍) 0.0394 — 본 계열이 %s", 
    if (sd_exc > 0.0394) "더 변동적" else "덜 변동적")

say("--- 무조건 반도체 프리미엄(신호 없이) ---")
tt <- t.test(S$exc)
say("  평균 %+.4f/월 (연 %+.2f%%) · t=%.2f · p=%.4f", mean(S$exc), mean(S$exc)*12*100, tt$statistic, tt$p.value)

say("--- 신호 조건부(ON/OFF 차)의 필요 효과크기 ---")
for (sig in c("mom3","mom6","mom12")) {
  on <- S[[sig]] > 0
  p <- mean(on); n <- nrow(S)
  r <- required_effect(n, design="interaction", regime_frac=p, sd_monthly=sd_exc)
  d_obs <- mean(S$exc[on]) - mean(S$exc[!on])
  v <- if (abs(d_obs) < r$required_monthly) "INCONCLUSIVE_UNDERPOWERED" else "NEGATIVE_POWERED"
  say("  %-5s ON비율 %.2f · 유효n %.1f · 필요 연 %+.2f%% | 관측 연 %+.2f%% -> %s",
      sig, p, r$effective_n, r$required_annual*100, d_obs*12*100, v)
}
say("--- 참고: 몇 개월이면 관측 효과(mom6 연 9.07%%)가 t=2.0 에 닿는가 ---")
d6 <- (mean(S$exc[S$mom6>0]) - mean(S$exc[S$mom6<=0]))
p6 <- mean(S$mom6>0)
need_eff_n <- (2.0 * 1.25 * sd_exc / d6)^2
say("  필요 유효n = %.0f  ⇒ 필요 총 개월 = %.0f (현재 %d, ON비율 %.2f)",
    need_eff_n, need_eff_n/(p6*(1-p6)), nrow(S), p6)
