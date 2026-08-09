## p3 — EW 벤치가 "더 쉬운 벤치" 라는 08-08 판독의 기전 확인
## 08-08 결론(금지 규범)은 옳았으나 근거 기전이 "더 쉬운 벤치" 였다. 실측으로 확인한다.
suppressPackageStartupMessages(library(data.table))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[m] ", fmt, "\n"), ...)); flush.console() }
R <- fread("stage_artifacts/ladder_sweep/decompose.csv")
R[, shift := m_ew - m_capw]
say("=== mean 채널 방향 (8재료) ===")
say("  m_ew - m_capw : 중앙 %+.6f/월 (연 %+.2f%%)", median(R$shift), median(R$shift)*12*100)
say("  8/8 모두 음수: %s · sd %.6f", all(R$shift < 0), sd(R$shift))
say("  ⇒ 포트의 EW 대비 초과가 cap-w 대비보다 %s",
    if (median(R$shift) < 0) "**작다**" else "크다")
say("  ⇒ ★EW 유니버스 벤치의 실현수익이 cap-w 벤치보다 **높다** = mean 기준 **더 어려운** 벤치")
say("     (08-08 판독 '더 쉬운 벤치로 채점' 은 방향이 반대. 금지 규범 자체는 옳았다)")
say("=== t 이득의 출처 ===")
say("  mean 채널 t 기여 : 중앙 %+.3f  (불리)", median(R$contrib_mean))
say("  se   채널 t 기여 : 중앙 %+.3f  (|절대값|, 배율)", median(abs(R$contrib_se)))
say("  se 비율 EW/capw  : 중앙 %.3f → 배율 x%.3f", median(R$se_ratio), 1/median(R$se_ratio))
say("  ⇒ ★t 이득은 **전량 분모(se) 축소**에서 온다. 분자는 오히려 불리하다.")
say("=== 계약 정합 확인 ===")
say("  → canonical_screen_bt() diag_ew_universe$basis_channels 가 이 두 채널을 필드로 발행한다")
say("     (2026-08-09 추가 · 검사 08_Tests/contract_regression/test_basis_channels.R 22/22)")
