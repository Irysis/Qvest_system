suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
source(file.path(ROOT,"02_Infrastructure/worktask/worktask_manager.R"))
wt_record_challenge_review(task_id="WT-R20260829_007", from_agent="optimizer", objection=FALSE,
  targets_reviewed=c("alpha_vector","confidence_vector","risk_sigma","tail_risk_evt","bound_feasibility",
                     "turnover_hard_cap","liquidity_floor","schedule_density"))
cat("challenge review recorded\n")
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
res <- tg_agent_brief(
  agent = "Optimizer",
  title = "WT-R20260829_007 OPTIMIZER_DONE — 회전 제약 충족 우선, netIR 0.22",
  sections = list(
    list(type="summary", text=paste0(
      "강화 프로세스 WT-R20260829_007(JT1993 강화 7/20 · 52주 신고가 근접도) 비중 결정 완료. ",
      "수신 사양이 회전율 hard cap(연 11.0 왕복)을 15.31 로 이미 위반한 상태였다. ",
      "no-trade band(순위 50 유지)로 10.35 까지 낮춰 제약을 충족시켰다. ",
      "선택축은 net_IR 로 사전 선언했고 결과를 보고 바꾸지 않았다.")),
    list(type="table", header=c("방법","netIR","통과"), rows=list(
      c("등가중 top25(수신)","0.243","회전 초과"),
      c("등가중+버퍼50 채택","0.220","통과"),
      c("Alpha 비례 tilt","0.153","회전 초과"),
      c("MVO+회전벌점","0.063","회전 초과"),
      c("버퍼40+MVO","0.093","통과"))),
    list(type="bullet", items=c(
      "종목수 25 / 롱온리 / 비중합 1 — 260개 리밸일 전부 충족",
      "제약 훅 양방향 실증: 정상 통과 1 + 위반 주입 3건 전량 차단",
      "회전율 15.31 → 10.35(-32%) · 용량 상한 중앙 14.9억 → 24.0억",
      "정직 보고 — 비용 절감 74bp보다 알파 손실 127bp가 커서 순활성은 52bp 감소했다",
      "Beta 를 위험 대리변수로 쓰지 않았다 — 꼬리는 EVT 로만 병기(ES99 월 21.2%)")),
    list(type="kv", kv=list(
      "선택 방법"="등가중 25종 + no-trade band 50",
      "netIR"="0.220 (수신 사양 0.243)",
      "연 회전율(왕복)"="10.35 / 상한 11.0",
      "손익분기 편도비용"="47.7bp (수신 40.5bp)",
      "다음"="Forge 통합 → 권위 등급 산출"))
  ),
  footer = "산출물: optimization_package.json · weights.csv(260 리밸일) · weight_method_selected.md"
)
cat("telegram sent\n")
