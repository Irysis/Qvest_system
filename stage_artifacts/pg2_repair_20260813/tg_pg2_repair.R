## PG2 수리 완료 브리핑 — 텔레그램 v7 SOT 정합
##  진입점: tg_agent_brief() 단일 (직접 tg_send 는 hook 차단)
##  표준 5섹션 + 원칙 8 3장치(평문 요약·쉬운 설명·자동 용어풀이) + 원칙 9(실측 = 차트 첨부)
##  ★force 미사용 — force=TRUE 는 중복차단(TTL)을 꺼서 재실행마다 재발송된다(08-13 실사고)
if (identical(as.integer(Sys.getenv("ARROW_IO_THREADS", "0")), 1L)) Sys.setenv(ARROW_IO_THREADS = "2")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))

DRY <- "--dry-run" %in% commandArgs(TRUE)
OUT <- file.path(ROOT, "stage_artifacts/pg2_repair_20260813")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

## 차트 = 배포 결정 분해 (manifest 기록값 그대로 — 계산 없음, 차트팩 규율 ①)
png_path <- tg_chart_sweep(
  labels = c("AE·M4 게이트", "R05 베타", "최종 투자비중", "현금비중"),
  values = c(0.70, 0.30, 0.21, 0.79),
  out_dir = OUT,
  title = "2026-08 배포 비중 분해 (위기 국면)",
  value_label = "비율",
  highlight = "최종 투자비중",
  filename = "pg2_202608_exposure.png")

res <- tg_agent_brief(
  agent = "Q-Lead",
  title = "PG2 월간 리밸런싱 체인 수리 완료 — 조용히 멈춰 있던 결함 제거",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "매달 자동으로 돌아야 할 배포 절차가 조용히 멈춰 있었습니다. 원인을 찾아 고쳤습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 매달 도는 배포 절차 전체를 처음부터 끝까지 한 번 돌려봤습니다",
           "방법: 실제 예약 작업과 같은 경로로 실행해 결과를 이전 값과 대조했습니다",
           "결과: 중간에 영원히 멈추는 결함을 찾아 고쳤고 과거 값은 안 바뀝니다",
           "의미: 9월 리밸런싱이 소리 없이 멈출 위험이 사라졌습니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "체인 완주"    = "정상 종료 (4분 30초)",
           "산출물 재현"  = "10종 중 9종 완전 일치",
           "과거 값 변경" = "0건",
           "배포 검사"    = "14개 항목 전부 통과",
           "투자 비중"    = "21% (현금 79%)")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "배포 비중 검사가 예약 경로에는 배선돼 있지 않습니다",
           "이번 통과는 제가 손으로 돌려 확인한 결과입니다",
           "9월은 자동 검사 없이 비중이 나갈 수 있습니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "수리 완료 — 실제 자본 배분 규칙은 바뀌지 않았습니다",
           "검사 배선 여부는 도훈 결정 사항입니다 (운용 행동 변경)",
           "다음 자원은 비대칭 알파 발굴 라운드로 배분 권고")),

    list(type = "text", emoji = "🔍", heading = "결함의 성격",
         body = paste("두 설정이 각각은 옳은데 겹칠 때만 멈추는 결함이었습니다.",
                      "그래서 코드 검토로도 단독 시험으로도 안 잡히고,",
                      "실제 호출 경로째 돌리는 예행 연습에서만 드러났습니다."))
  ),
  charts = png_path,
  dry_run = DRY,
  footer = "📚 수리 7건 · 커밋 1aa04207 · 검증 위반 주입 5/5"
)

cat(sprintf("\n[tg] dry_run=%s · 반환=%s\n", DRY, paste(utils::capture.output(str(res)), collapse = " ")))
