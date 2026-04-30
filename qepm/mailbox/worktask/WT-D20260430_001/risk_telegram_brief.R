#==============================================================================
# Telegram Brief — Risk Phase DONE — WT-D20260430_001
# v4 ENFORCE: tg_agent_brief() only. Sections ≥4. Emoji ≥5.
# 도훈 명시 (2026-04-30): 사용자 이름 금지, 전문 용어 1줄 풀이 + 비유
#==============================================================================

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source("02_Infrastructure/telegram/telegram_notify.R")

# Build Σ Estimator comparison table
sigma_table <- data.frame(
  Estimator = c("sample", "lw_oracle", "lw_constcor (선택)", "gerber"),
  Cond = c("1581.32", "162.83", "87.46", "≈ 5e9 (실패)"),
  PSD = c("OK", "OK", "OK", "OK"),
  shrink = c("0", "낮음", "0.6753", "n/a"),
  stringsAsFactors = FALSE
)

# Stress test 8 + cost-adjusted SR + TDC + AX-002 compliance
res <- tg_agent_brief(
  agent = "Risk",
  title = "WT-D20260430 RISK_DONE — Σ ledoit_wolf_constcor cond 87.46",
  sections = list(
    list(
      emoji = "🔬",
      heading = "Σ Estimator 4종 비교 (R13 병렬)",
      type = "table",
      df = sigma_table
    ),
    list(
      emoji = "💰",
      heading = "Cost-Adjusted SR (Q-Lead 결정 의제)",
      type = "text",
      body = paste0(
        "Zero-cost uplift +0.0176 → Net uplift +0.0163 (감쇠 7.4%). ",
        "거래비용 (15bps × 양방향 × 회전율) 반영 후에도 부호 유지. ",
        "그러나 NW HAC t = 0.440 (lag=4, p>0.5) — 통계적으로 의미 없음 유지. ",
        "비용은 부호를 뒤집지 않지만 의미성도 못 살림.\n\n",
        "Overlay 회전율: S3 28.9%/년 (S2는 21.4%/년). 추가 비용 +2.26 bps/년만큼 더 부담. ",
        "1년에 3번 정도 cash 비중 갈아치우는 전략 — 상대적으로 낮은 회전율.\n\n",
        "MDD-protection 메커니즘은 통계적으로 강함: CRISIS 분산 비율 0.836 [부트스트랩 95%CI 0.769~0.925] — ",
        "위기 39개월에서 분산을 16% 줄임. 1.0과 통계적 구별 가능."
      )
    ),
    list(
      emoji = "🌪️",
      heading = "Tail Risk + Stress 8 (KR-specific)",
      type = "text",
      body = paste0(
        "월간 CVaR 95% (최악 5% 평균손실): S3=10.22% < S2=10.50% < S1=11.12% — overlay가 9bps 개선.\n",
        "월간 VaR 99% (최악 1% 손실): S3=13.40% < S1=13.68% — 28bps 개선.\n",
        "Hill α (꼬리 두께 지표, 클수록 가벼움): S1=2.39 / S3=2.78 — overlay가 꼬리 두께 16% 완화.\n",
        "EVT-GPD ξ=0.04 (S3) ≈ 가벼운 heavy tail.\n\n",
        "8 KR 스트레스 (S3 vs S1):\n",
        "• GFC 2008-09~2009-02: -16.5% vs -21.1% (★ 4.6pp 절감)\n",
        "• Euro Debt 2011: 2.1% vs 4.8% (-2.7pp 손실, false positive)\n",
        "• China Shock 2015: overlay 미발동 (동일 10.2%)\n",
        "• Trade War 2018-19 23개월: -9.3% vs -8.9% (★ -0.4pp 손실, 장기 false positive)\n",
        "• COVID 2020-02~04: -4.8% (S3) vs -8.9% (S2) (★ S2 대비 +4.1pp)\n",
        "• Rate Hike 2022: overlay 미발동 (동일 -13.6%)\n",
        "• Yen Carry 2024-08: 1개월만 — 측정 불충분\n",
        "• KOSPI 2024H2: overlay 미발동 (17.5%)\n\n",
        "결론: 8건 중 1건만 S3가 S1을 의미있게 도움 (GFC). 1건은 오히려 손해 (Trade War). 6건은 동일."
      )
    ),
    list(
      emoji = "🔗",
      heading = "TDC + Regime 4-bucket",
      type = "text",
      body = paste0(
        "TDC q05 (위기 시 동시 하락 확률) S3 vs S1 = 0.824. ",
        "이 값이 높은 이유는 설계상 — S3 = w*S1 (w∈[0.6,1.0], 평균 0.969). ",
        "S3는 84.6%/267월 동안 S1과 정확히 일치 (overlay 미발동). ",
        "포트폴리오 군집 위험이 아니라 메커니즘 구조 자체.\n\n",
        "의미 있는 분리도는 위기 56개월만의 TDC = 0.5357 — 약 46%만큼 분리. ",
        "위기에서 overlay가 실제로 다른 방향으로 작동.\n\n",
        "4-bucket 분산비:\n",
        "• BULL (n=108): 0.990 [0.977~0.998] — overlay 거의 미발동\n",
        "• NORMAL (n=85): 0.987 [0.963~1.000] — 미세\n",
        "• CAUTION (n=35): 0.913 [0.840~0.971] — 8.7% 변동성 절감\n",
        "• CRISIS (n=39): 0.836 [0.769~0.925] — ★ 16.4% 절감 통계적 유의\n",
        "Regime switch rate: 33.8%/월 (높은 변동)"
      )
    ),
    list(
      emoji = "🚩",
      heading = "Risk Flags (Codex R1 = REJECT 대응)",
      type = "bullet",
      items = c(
        "RF-R2 PASS: Condition 87.46 < 500 + PSD 검증 (min_eig 5.5e-5)",
        "RF-R6 REBUTTAL: CVaR 10.22% > codex 템플릿 2.5% — 그러나 STR_1715는 20종목 long-only KR 전략 vol 22.75%. 기존 PG2가 받아들인 리스크 프로파일",
        "RF-R3 INFORMATIONAL: TDC 높음 = 메커니즘 구조 (S3=w*S1). 위기 분리도 0.46이 실질 지표",
        "Cost-adjusted significance FAIL: NW HAC t 0.440 (p>0.5) — 비용 반영해도 통계적 의미 없음",
        "MECHANISM POSITIVE: CRISIS 분산 -16.4% 통계적 유의 — alpha SR 증가 없어도 protective 메커니즘 입증",
        "AX-008 PARTIAL (1-of-N): Risk 독립 재계산 PASS, Codex REJECT 대응 완료, Forge 대기 — 완전 삼각검증 미완"
      )
    ),
    list(
      emoji = "🎛️",
      heading = "AX-002 Compliance + 다음 단계",
      type = "kv",
      kv = list(
        Σ_PSD = "PASS (min_eig 5.50538e-05)",
        alpha_modify = "NO (read-only, hash 보존)",
        weight_propose = "NO (Optimizer 위임, Charter §8)",
        method_log = "4 candidates, lowest_cond rule",
        codex_R1 = "REJECT 7 concerns → REVISED (5 ACCEPT + 2 REBUTTAL)",
        next_phase = "Optimizer Agent — α̂ + Σ 수신 후 target_weights"
      )
    )
  ),
  emoji_min = 6L
)

stopifnot(isTRUE(res$ok))
cat("[telegram] Risk brief sent successfully\n")
cat(sprintf("[telegram] message_id: %s, bytes: %d\n", res$message_id %||% "?", res$bytes %||% 0))
