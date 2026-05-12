## Architect Telegram brief (qvest-telegram SOT v6)
suppressMessages({library(jsonlite)})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Architect",
  title = "WT-T20260508_004 S4 PG2 admit AX-008 3-source 검증 결과",
  sections = list(
    list(type = "summary", emoji = "🎯",
         body = "S4 (혼합 50/25/20/5) PG2 승격 AX-008 3-source 검증 PASS_3_OF_3. 6월 1일 발효 진행 권고."),

    list(type = "kv", emoji = "📊", heading = "독립 산출 결과 (메트릭스 재생 + 합성 재생 두 경로)",
         kv = list(
           "S4 샤프 (단조)"     = 1.7224,
           "S4 샤프 (감리관)" = 1.7224,
           "최대 샤프 차이"     = "4×10⁻⁷ (한계값 0.05)",
           "S4 최대낙폭"        = "11.64% (목표 -25% 대비 13.36%pt 우월)",
           "감리관-단조 상관"   = 1.000000,
           "수익률 합성 차이"   = "0.0 (기계 오차 한계)"
         )),

    list(type = "table", emoji = "🔬", heading = "5 mandate 결과",
         df = data.frame(
           mandate = c("1. 독립 재생산", "2. 점진 갱신 audit", "3. AX-001 v2 조건부 방어", "4. PIT C1~C15", "5. 승격 정당성"),
           verdict = c("PASS (5/5)", "PASS (5 sample)", "PASS_3_OF_4", "PASS", "JUSTIFIED")
         )),

    list(type = "bullet", emoji = "🛡️", heading = "S4 vs S0 (기준선) AX-001 v2 조건부 방어",
         items = c("M1 위기알파 +2.03%pt (S4가 S0보다 stress 평균 우월) PASS",
                   "M2 최대낙폭 완화 +8.03%pt (S0 16.56% → S4 8.53% 워스트 stress) PASS",
                   "M3 SR 비율 -0.053 (strict 0.5 FAIL이나 stress 평균 음수라 metric 자체 robust X)",
                   "M4 stress 5건 PASS",
                   "S4 역할: Defense (다양화 보다 강한 위기 보호)")),

    list(type = "bullet", emoji = "⚖️", heading = "S4 vs S3 supersede 정량",
         items = c("샤프지수: 1.674 → 1.722 (+0.048 변동성 축소 효과)",
                   "최대낙폭: 16.65% → 11.64% (-5.0%pt 추가 완화)",
                   "연복리수익률: 26.5% → 19.3% (-7.2%pt 희생, 자본 미활용)",
                   "S4 자본 배분: AR 50% + KR10년채 20% + TSMOM 25% + 현금 5%",
                   "AR 50%만 risk allocate → 50%가 낮은 expected return drag")),

    list(type = "bullet", emoji = "⚠️", heading = "1 부수 발견 (boundary 외)",
         items = c("Forge 06_metrics 연복리 0.1928 vs Architect 0.1955 = +0.27%pt 차이",
                   "원인: NAV 첫 row establishment cost denominator distortion",
                   "Backtest Contract v1.1 reconcile mandate (PD2 deadline 2026-08)")),

    list(type = "bullet", emoji = "➡️", heading = "권고 5건",
         items = c("S4 운용형 승격 6월 1일 발효 진행 — 감리관 3중 검증 통과",
                   "코덱스 정식 라운드 사후 보강 (지배인 승인 단계 전이 시)",
                   "백테스트 계약 1.1판 연복리 산식 정합화 (8월 마감)",
                   "60일 유예 기간 모니터링 (실현 샤프 1.5 미만 시 S3 회복 검토)",
                   "네 번째 직교 알파 발굴 가속 (샤프 목표 2.0 대비 달성 1.722, 격차 0.278)"))
  ),
  footer = "Pure Function R12 정합. 3-package immutable retain. 자료: ax008_3rd_source_verdict.json + architect_verification_report.md"
)
