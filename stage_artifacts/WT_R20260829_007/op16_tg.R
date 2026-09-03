suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
df <- data.frame(
  방법 = c("등가중 top25(수신)","등가중+버퍼50 채택","Alpha 비례 tilt","MVO+회전벌점","버퍼40+MVO"),
  `비용차감 정보비율 · 회전판정` = c("0.243 초과탈락","0.220 통과","0.153 초과탈락","0.063 초과탈락","0.093 통과"),
  stringsAsFactors = FALSE)
res <- tg_agent_brief(
  agent = "Optimizer",
  title = "WT-R20260829_007 OPTIMIZER_DONE — 회전 제약 충족, netIR 0.220",
  sections = list(
    list(type="summary", heading="현재 리서치 상황",
         body="강화 프로세스 비중 결정 완료 — 수신 사양이 회전율 상한을 이미 넘고 있었다"),
    list(type="text", heading="무엇이 문제였나",
         body=paste0("52주 신고가 근접도 전략의 수신 사양은 연 회전율 15.31(왕복)로 상한 11.0을 위반한 상태로 넘어왔다. ",
                     "매매 유예 구간(순위 50 유지)을 넣어 10.35로 낮췄다. 선택 기준은 비용차감 정보비율로 사전 선언했다.")),
    list(type="table", heading="방법론 비교", df=df),
    list(type="bullet", heading="확인 사항", items=c(
      "종목수 25 · 롱온리 · 비중합 1 — 260개 리밸런싱일 전부 충족",
      "제약 훅 양방향 실증 — 정상 1건 통과 + 위반 주입 3건 전량 차단",
      "회전율 15.31 → 10.35 · 용량 상한 중앙 14.9억 → 24.0억원",
      "정직 보고 — 비용 74bp 절감보다 알파 127bp 손실이 커 순활성 52bp 감소",
      "베타를 위험 대리변수로 쓰지 않았다 — 꼬리는 극단값이론으로만 병기")),
    list(type="kv", heading="핵심 수치", kv=list(
      "선택 비중방법"="등가중 25종 + 매매유예 구간 50",
      "비용차감 정보비율"="0.220 (수신 사양 0.243)",
      "연 회전율(왕복)"="10.35 · 상한 11.0",
      "손익분기 편도비용"="47.7bp (수신 40.5bp)",
      "월간 기대손실 99%"="21.2% (극단값이론)",
      "다음 단계"="Forge 통합 후 권위 등급 산출"))
  ),
  footer = "산출물 = optimization_package.json · weights.csv(260 리밸런싱일) · weight_method_selected.md"
)
cat("telegram ok\n")
