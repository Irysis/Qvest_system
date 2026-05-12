#==============================================================================
# Telegram brief — WT-D20260508_013 OPTIMIZER_DONE (v6 SOT)
#
# 구성: tg_agent_brief 단일 호출. 한글 정통 + 옵션 라벨 정합 (도훈 명시):
#   ✅ 비중 비교 0% / 5% / 10% / 15% / 20%  (정량 = 수치 자체)
#   ✅ Mitigation A안 / B안 / C안              (카테고리)
#   ❌ "A안 0% / B안 10%"                      (라벨+수치 중복)
#==============================================================================

suppressPackageStartupMessages({library(jsonlite)})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

# Final package fact-check
opt_pkg <- fromJSON("qepm/mailbox/worktask/WT-D20260508_013/optimization_package.json", simplifyVector = FALSE)

# 5-grid SR / MDD / IR table (분산효과 grid)
gr_dt <- data.frame(
  비중      = c("0%", "5%", "10%", "15%", "20%"),
  결합SR    = c("1.651", "1.685", "1.712", "1.730", "1.737"),
  결합MDD   = c("-0.195", "-0.184", "-0.174", "-0.170", "-0.191"),
  분산효과  = c("0.0%", "-0.7%", "-1.4%", "-2.1%", "-2.8%"),
  stringsAsFactors = FALSE
)
# ncol = 4 ≤ 3 위배. 축소.
gr_dt <- data.frame(
  비중       = c("0%", "5%", "10%", "15%", "20%"),
  결합SR     = c("1.651", "1.685", "1.712", "1.730", "1.737"),
  결합MDD    = c("-0.195", "-0.184", "-0.174", "-0.170", "-0.191"),
  stringsAsFactors = FALSE
)

# Method shopping table (5 후보)
ms_dt <- data.frame(
  방법론        = c("동일가중", "알파가중", "신뢰도MVO", "동등위험기여", "계층위험균형"),
  비용조정SR    = c("0.527", "0.655", "0.380", "0.523", "0.451"),
  stringsAsFactors = FALSE
)

tg_agent_brief(
  agent = "Optimizer",
  title = "WT-D20260508_013 OPTIMIZER_DONE — 좌측꼬리 모멘텀 다양화 비중 결정",
  as_of = "2026-04-30",
  sections = list(
    list(
      type = "summary",
      body = "Atilgan 좌측꼬리 모멘텀 다양화 역할 비중 결정. 기존 혼합 70/15/15 + WT_013 4슬리브 결합. 비중 10% C안 권고 (5-15% 다양화 밴드 중간). 알파가중 방법론 비용조정SR 0.655 선택. 결합SR 1.65 → 1.71 (+0.06) / 결합MDD -0.195 → -0.174 (-2.1pp 개선)."
    ),
    list(
      type = "table",
      heading = "방법론 비교 (다섯 후보, 비용조정SR 기준)",
      df = ms_dt
    ),
    list(
      type = "table",
      heading = "5-격자 결합효과 (혼합 + WT_013 비중)",
      df = gr_dt
    ),
    list(
      type = "kv",
      heading = "공분산 + 직교성",
      kv = list(
        "공분산행렬 LW축약"        = "조건수 1 (μI 퇴화 — 동등위험기여/계층위험균형용)",
        "공분산행렬 요인모형"      = "조건수 1055 (Bβ'+D 시장요인 + 특이위험)",
        "벤치마크 직교성 전기간"   = "+0.025 (혼합 70/15/15 근사 vs WT_013)",
        "벤치마크 직교성 최근60월" = "+0.121 (재상응 모형 작동기 강화)",
        "회전율 평균"              = "32.3% / 월 (연환산 388%)"
      )
    ),
    list(
      type = "bullet",
      heading = "강제 제약 + 공리 검증",
      items = c(
        "종목수 20 ≤ 20 통과 / 가중상한 0.18 ≤ 0.20 통과",
        "롱전용 모두 ≥ 0 통과 / Σw = 1.000 통과",
        "위크포워드 252개 신호일 일정밀도 100%",
        "공리 AX-007 다슬리브 예외 (4슬리브) 정합",
        "공리 AX-001 v2 비율 신뢰구간 [-126, 151] 불안정 → 다양화 정직"
      )
    ),
    list(
      type = "bullet",
      heading = "권고 — Mitigation A/B/C/D/E안 (4슬리브 격자)",
      items = c(
        "A안 0% — 현상유지, 권고 ΔSharpe 검증 미달 시",
        "B안 5% — 보수 진입, 다양화 밴드 하단",
        "C안 10% — 권고 (밴드 중간점, MDD 개선 -2.1pp)",
        "D안 15% — 적극 진입, MDD 개선 최대 -2.5pp",
        "E안 20% — 다양화 밴드 상단 초과, MDD 재악화 위험"
      )
    ),
    list(
      type = "bullet",
      heading = "infeasibility_report (No Silent Override)",
      items = c(
        "Markowitz 정적 분산효과 비중 10% 시 -9.19% 악화 보고됨",
        "위크포워드 5-격자 실측 분산효과 -1.4% (cor 0.025 안정)",
        "정적 vs 실측 차이 = 학술 중요 발견 (정적은 보수적 추정)",
        "Forge 결합 백테스트로 ΔSharpe ≥ +0.05 / ΔMDD ≤ -2pp 검증 의무"
      )
    ),
    list(
      type = "bullet",
      heading = "다음 단계 — Forge Agent 의무",
      items = c(
        "혼합 4슬리브 결합 백테스트 256개월 (PIT C1-C15 + 15bps 비용)",
        "스트레스 위크 위기알파 검증 (8건 중 6건 가용)",
        "장기 롱전용 상위20 슬리브 형식 실현",
        "최대낙폭 완화 비교 vs 혼합 단독 (-16.6%)",
        "검증삼각화 공리 AX-008 3번째 source Architect 독립 재현"
      )
    ),
    list(
      type = "kv",
      heading = "산출 + 인계",
      kv = list(
        "선택 방법론"     = opt_pkg$method_selected %||% "AlphaWeighted_top20",
        "선택 근거"       = "비용조정SR 0.655 (회전율 32%/월 가정 하)",
        "1차 권고 안"     = "C안 10% (위크포워드 SR 1.712 / MDD -0.174)",
        "최종 입장"       = "다양화 정직 다양화 (방어 분류 철회)",
        "다음 에이전트"   = "Forge agent — run_all.R 결합 백테스트"
      )
    )
  )
)
