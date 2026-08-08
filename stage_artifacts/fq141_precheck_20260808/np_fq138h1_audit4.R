source("02_Infrastructure/contracts/required_effect_size.R")
cat("=== 감사 가능 4건 검정력 판정 (sd 0.0394 = top-25 EW 바스켓 쌍 실측) ===\n")
cases <- list(
  list(id="FQ-064", n=20L,  eff_ann=-0.0180, t=-1.267, note="'풀 편향 가설 기각' 근거로 사용된 비유의 결과"),
  list(id="FQ-118", n=431L, eff_ann=+0.0210, t=NA,     note="오라클 상금(look-ahead 상한) — 라벨 품질 사전검정 FAIL 이 실판정"),
  list(id="FQ-121", n=148L, eff_ann=+0.0320, t=NA,     note="게이트 유효성 NOT_ESTABLISHED(방향 +3.2%/yr 이나 t<2.0)"),
  list(id="FQ-152", n=36L,  eff_ann=-0.0374, t=-1.49,  note="FF3 alpha. 단 OOS retention 0.089·Calmar 0.049·MDD 59.6% 는 검정력 무관 독립 FAIL")
)
for (c in cases) {
  v <- verdict_with_power(observed_t = if (is.na(c$t)) 0 else c$t,
                          observed_monthly = c$eff_ann/12, n = c$n)
  r <- v$required
  cat(sprintf("\n%s  n=%d  보고효과 %+.2f%%/yr  (t=%s)\n", c$id, c$n, c$eff_ann*100,
              if (is.na(c$t)) "미기재" else sprintf("%.2f", c$t)))
  cat(sprintf("  필요 효과(t=2.0) = 연 %+.2f%%  →  판정 %s\n", r$required_annual*100, v$verdict))
  cat(sprintf("  비고: %s\n", c$note))
}
cat("\n⚠ sd 적용 한계: 0.0394 는 **top-25 EW 바스켓 쌍**의 월 수익차 실측이다.\n")
cat("   게이트 on/off·오버레이·FF3 잔차 등 다른 비교축은 변동성이 다를 수 있으므로\n")
cat("   위 판정은 **1차 스크린**이며, 확정하려면 각 라운드의 실제 계열 sd 가 필요하다.\n")
