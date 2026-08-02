# send_fq127_telegram.R — WT-D20260803_002 완료 보고 (tg_agent_brief 단일 진입점)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260803_002 ALPHA_DONE — FQ-127 base-의존성 재판정: 부분 계통",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "8-2일 개선 주장 8건 전수 감사 — 배제-필터형 2건만 부호 반전, 점수-교체형 2건은 전 가중 방식에서 유지."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c("배경: 같은 개선 효과라도 종목 비중을 주는 '저울'(시가총액 vs 점수 순위)에 따라 +가 -로 뒤집힘이 어제 실측됐습니다",
                   "시도: 어제 하루치 개선 주장 전부를 실제 운용 코드의 저울(점수 순위 가중)에 다시 올렸습니다",
                   "결과: '종목을 빼는' 방식의 개선만 저울에 민감해 뒤집혔고, '점수를 바꾸는' 방식은 5개 저울 전부에서 방향이 같았습니다",
                   "의미: 개선 주장 전체가 오염된 것이 아니라, 필터형 주장만 base 표기 없이는 못 씁니다")),
    list(type = "kv", emoji = "📊", heading = "재판정: ΔIR 원 frame → production 저울",
         kv = list(
           "CL-4 MAX5배제(014)"      = "+0.169 → -0.113 반전(승계)",
           "CL-5 배제+overlay(016)"  = "+0.128 → -0.149 반전(승계)",
           "CL-3 경로효율 교체(009)" = "+0.126 → +0.150 유지 t+1.56",
           "CL-8 2팩터 조합(021)"    = "+0.140 → +0.182 유지 t+0.96",
           "인벤토리 분류"           = "8주장: parity 3 / 재판정 4 / 라벨만 4")),
    list(type = "bullet", emoji = "🚩", heading = "주의 (Challenge Flags)",
         items = c("경로효율 교체의 부호 유지는 교체안 부활이 아님 — 멤버십 흔들기 취약(큐 109번) 철회는 그대로, 순위가중에서도 통계 문턱 미달",
                   "WT-003 의 가중 정렬 주장(+2.569)은 기준 점수 패널 미저장으로 미검 — 약한 기준 위 주장이라 경고 최상급",
                   "위기 국면 비중 상한 감응도 실측: 부호 불변 (+0.144 / +0.173)",
                   "자본 주장 없음 — 감사 라운드, 기존 산출물 무수정")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c("큐 128번(라벨 강제 배관)에 개입유형 축 반영 — 필터형 개선치는 기준 가중 표기 의무",
                   "WT-003 기준 패널 재생성 시 가중 정렬 주장 재판정 — 큐 96번 착수의 선행 관문으로 병합",
                   "고상관 재순위 쌍 반례 1회 실측으로 '부분 계통' 경계 확정"))
  ),
  charts = c(
    "stage_artifacts/WT_D20260803_002/chart_fq127_before_after.png",
    "stage_artifacts/WT_D20260803_002/chart_fq127_config_grid.png"
  )
)
cat("[fq127tg] 발송 완료\n")
