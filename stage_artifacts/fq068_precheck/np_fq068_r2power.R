suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
ic <- fread("stage_artifacts/fq068_precheck/fq068_r2_ic.csv")
say <- function(fmt,...) cat(sprintf(paste0("[pow2] ",fmt,"\n"),...))
n <- nrow(ic); s <- sd(ic$ic); m <- mean(ic$ic)
say("월수 %d · IC sd %.4f · 평균 %+.5f", n, s, m)
say("--- 이 설계가 검출할 수 있는 IC 크기 ---")
for (t0 in c(2.0, 2.95)) say("  t=%.2f 도달 필요 IC = %.4f", t0, t0*s/sqrt(n))
say("--- 관심 효과크기별 검정력 (이 저장소 기준 IC 0.04~0.05 = 유의미) ---")
for (ic0 in c(0.02, 0.03, 0.04, 0.05)) {
  tt <- ic0/s*sqrt(n)
  say("  참 IC %.2f 이면 기대 t = %.2f  %s", ic0, tt, if (tt>=2.0) "검출 가능" else "검출 불가")
}
need_n <- (2.0*s/abs(m))^2
say("--- 관측 크기(|IC| %.4f)를 t=2.0 으로 확립하려면 %d개월 필요 (현재 %d) ---", abs(m), ceiling(need_n), n)
say("★판정: 관심 효과크기(IC>=0.04)에 대해 **검정력 충분**(기대 t %.2f) ⇒ 무효과가 아니라 '검출됐어야 하는데 안 나왔다'",
    0.04/s*sqrt(n))
