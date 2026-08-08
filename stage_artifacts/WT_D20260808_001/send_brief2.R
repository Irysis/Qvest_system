setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

png <- tryCatch(
  tg_chart_sweep(
    labels    = c("D03 변동성", "Q01 이익안정", "M26 매출모멘텀"),
    values    = c(-1.73, -0.21, 1.544),
    out_dir   = "stage_artifacts/WT_D20260808_001/charts",
    title     = "재료 3종의 포트폴리오 전이 성적 — 자본 기준선 2.95",
    hline     = 2.95),
  error = function(e) { message("chart skip: ", conditionMessage(e)); character(0) })

tg_agent_brief(
  agent = "Q-Lead",
  title = "예측력은 통과하는데 실제 포트에서 죽는다 — 같은 날 세 재료가 같은 자리에서",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "서로 다른 재료 3개가 하루 만에 똑같은 지점에서 걸렸습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 성격이 다른 신호 3개를 각각 독립적으로 검증했습니다",
           "결과: 셋 다 '예측력 있음' 관문은 통과했습니다",
           "그런데: 셋 다 실제 25종목 포트에 넣으면 성적이 무너집니다",
           "의미: 재료가 나쁜 게 아니라 옮기는 과정에 병목이 있습니다")),
    list(type = "table", emoji = "📊", heading = "재료별 성적",
         df = data.frame(
           재료 = c("D03 변동성", "Q01 이익안정", "M26 매출모멘텀"),
           전이 = c("-1.73", "-0.21", "+1.54")
         )),
    list(type = "kv", emoji = "🔬", heading = "핵심 수치",
         kv = list(
           "M26 예측력"   = "t +2.555 (기준 2.0 통과)",
           "M26 중복 여부" = "상관 0.215 — 재탕 아님",
           "M26 전이"     = "1.544 (자본 기준 2.95 미달)",
           "판정"         = "재료 합격 · 전이 실패")),
    list(type = "bullet", emoji = "💡", heading = "왜 중요한가",
         items = c(
           "M26은 다른 세션이 완전히 독립으로 측정했습니다",
           "즉 한 라운드의 우연이 아니라 반복되는 구조입니다",
           "이 병목은 시스템이 1순위로 지목해온 지점입니다",
           "그 기계적 원인 후보가 잡혔고 지금 반증 검증 중입니다")),
    list(type = "bullet", emoji = "🚩", heading = "정직 보고",
         items = c(
           "원인 설명은 아직 미확정 — 검증 통과 전엔 기록도 안 합니다",
           "오늘 제 진단 하나가 틀려서 전면 철회하고 재작성했습니다",
           "알파는 아직 못 찾았습니다. 못 찾는 이유를 좁혔을 뿐입니다")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "돈 관점: 자본 배정 변경 없음 — 어느 것도 기준 미달입니다",
           "중립화 라운드 진행 중 — 병목 원인을 직접 시험합니다",
           "다음 착수자용 검정력 기준선을 원장에 고정했습니다"))
  ),
  charts = png,
  footer = "📚 WT-D20260808_001/002/003 · FQ-161 · layer_bottleneck_map 갱신"
)
cat("[brief2] telegram sent\n")
