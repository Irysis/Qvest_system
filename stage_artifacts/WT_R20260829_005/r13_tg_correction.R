suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
W <- readRDS(file.path(OUT,"risk_r11.rds")); S <- W$wf_summary; KR <- W$KR

tab <- data.frame(
  Axis = c("시장 분산비중","개별위험 비중","잔차변동 노출","실현 beta"),
  `as-of -> walk-forward` = c("0.749 -> 0.812", "0.053 -> 0.086",
                              "+0.387 -> -0.256", "0.869 -> 1.041"),
  check.names = FALSE, stringsAsFactors = FALSE)

res <- tg_agent_brief(
  agent = "Risk",
  title = "WT-R20260829_005 RISK 정정 — walk-forward 재판정 + KR_Bear 보완",
  as_of = "2026-07-31",
  sections = list(
    list(emoji="📌", heading="정정 사유", type="bullet",
         items=c("직전 브리핑 수치 일부가 as-of 단일 단면 산출이었다",
                 "스킬 Cycle 2 교훈이 금지한 판정 방식 — 자기 점검에서 적발",
                 "필수 스트레스 6종 중 KR_Bear 누락도 함께 확인",
                 "둘 다 실측 보완했고 결과가 실제로 달라졌다")),
    list(emoji="🔬", heading="walk-forward 재판정 (n=40개월)", type="table",
         df=tab, max_col_width=18L,
         notes=c("단일 단면이 시장 지배도를 과소표시했다 (과대가 아니라)",
                 "잔차변동 노출은 부호가 뒤집힌다 — as-of 값이 관측 범위의 최댓값")),
    list(emoji="🚨", heading="KR_Bear — 글로벌 목록이 놓친 축", type="bullet",
         items=c("정의: 벤치 낙폭 -20% 이하 에피소드 (데이터 도출, 임의지정 아님)",
                 "낙폭 상태 125개월 합산: 전략 -44.9% vs 벤치 -15.3%",
                 "  초과손실 -29.6%p",
                 "최악 2018-02~2020-11: 벤치 본전인데 전략 -22.7% (초과 -23.0%p)",
                 "초과손실은 급락 순간이 아니라 낙폭 상태 지속 구간에 쌓인다")),
    list(emoji="🧪", heading="판정 변화", type="bullet",
         items=c("시장 지배도 플래그: 74.9% -> 81.2%로 상향, 발화 유지",
                 "  판정 근거를 walk-forward 평균으로 교체",
                 "MDD -53.03% = 베타 낙폭 이라는 앞의 서술은 보완 필요",
                 "  베타는 낙폭 크기를 설명하나 낙폭 상태의 초과손실은 베타 밖",
                 "beta 창의존 반론이 두 번 정정됨 — 0.54~1.48 산포, 평균은 1 위")),
    list(emoji="⚠️", heading="변경 없음", type="text",
         body="Sigma 자체 · 추정기 선택 · 조건수 · 꼬리위험 · 크라우딩은 불변. 역할 경계도 불변.")
  ),
  footer = "➡️ Next: Optimizer Agent (risk_package 갱신본 소비)"
)
print(res)
