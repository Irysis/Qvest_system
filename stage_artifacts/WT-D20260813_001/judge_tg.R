root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))
sa <- file.path(root, "stage_artifacts/WT-D20260813_001/backtest_result")

res <- tg_agent_brief(
  agent   = "Judge",
  title   = "WT-D20260813_001 q90 pinball — Grade F / JUDGE_FAILED",
  charts  = c(file.path(sa, "equity_curve.png"), file.path(sa, "oos_zoom_chart.png")),
  sections = list(
    list(emoji = "⚖️", heading = "판정", type = "text",
         body = paste0(
           "Grade F (essence_score 독립 재실행 = 권위) / JUDGE_FAILED. 자본 자격 없음 — governor 미인계.\n",
           "graduation HARD 3종 전패: PORT_t 0.837(<2.95) / OOS retention -0.855(<0.7) / Calmar 0.212(<0.64).")),
    list(emoji = "🚦", heading = "게이트 요약", type = "bullet",
         items = c(
           "Gate A(PIT) PASS · B(격리) PASS · D(crowding) PASS · E(종목집중) PASS",
           "Gate C(알파 허들) FAIL · F(drift/OOS) FAIL · 17(무신호 대조) FAIL · 18(구조 drawdown) FAIL",
           "Gate 16(DSR) NA — selection_type=chain(파라미터 사전고정) 면제",
           "PIT C1~C15 전수 PASS (오버레이 없어 C5/C8/C9 NA)")),
    list(emoji = "📊", heading = "핵심 수치", type = "kv",
         pairs = list(
           "Sharpe" = "0.578", "CAGR" = "14.2%", "MDD" = "66.9%",
           "회전율" = "10.61/yr (cap 11.0 이내)",
           "β-통제 t(α)" = "1.207 (|t|<2, 알파 존재 주장 불가)",
           "no_signal_gate" = "INDISTINGUISHABLE (무신호 대조와 구별 불가, diff NW-t 0.97)")),
    list(emoji = "💡", heading = "쉬운 설명", type = "text",
         body = paste0(
           "이 전략은 '앞으로 크게 오를 소수 종목(상방 꼬리)을 맞히는 예측기'를 만들어 25종목을 담았습니다. ",
           "예측기가 실제로 상방 급등 종목을 잘 골라내긴 했습니다(F1 tail-hit 검정 t=+4.6, 매우 강함). ",
           "그런데 25종목을 똑같이 나눠 담는 '평균 방식'이 그 소수 종목의 대박을 희석시켜 포트폴리오 성과로 이어지지 못했습니다. ",
           "게다가 벤치 초과성과가 '시총 큰 종목·반도체 57% 노출 효과'와 통계적으로 구별되지 않아 ",
           "'신호가 돈을 벌었다'고 인정할 수 없었습니다. 결론: 표적(무엇을 예측하나)은 옳으나 소비 방식(어떻게 담나)이 벽입니다.")),
    list(emoji = "🔭", heading = "다음 프로브", type = "bullet",
         items = c(
           "① expectile(τ=0.9) 표적 별도 사전등록 (소비 정합 이론상 더 직접)",
           "② 소비 마디 교체 — 분위-표적 측정 계약(canonical_screen_bt 분포-표적 소비면) 신설이 리서치 선행",
           "③ FQ-237 결합 규칙 폐형식 교체 (선별 아닌 결합·이산 top-N 소비 마디가 벽으로 실측)",
           "screen_route=DISTRIBUTION_TARGET. config-scoped negative — target-form family 판결 아님(INV-7)")),
    list(emoji = "✅", heading = "검증", type = "text",
         body = paste0(
           "AX-008 Verification Triangulation 2/3 PASS (forge + self-adversarial). PIT C1 위반 없음. ",
           "equity_curve 전기간 연속(OOS 미절단·chart 완전). escalate 불요. L-code L-JG-20260822_220935 적립."))
  ),
  footer = "판정 종료 — 자본 게이트 정지 (governor 미인계)"
)
cat("TG result ok=", isTRUE(res$ok), " bytes=", res$bytes %||% NA, " err=", res$error %||% "none", "\n")
