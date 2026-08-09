#!/usr/bin/env Rscript
# p12b_tg_only.R — 게이트 해제 정정 보고 재발송 (큐 갱신은 p12 에서 완료 — 재쓰기 없음)
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "정정 — 재측정분이 이미 있었습니다. 대기열 2건 게이트 해제, 전제는 유효 확인",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "직전 폐쇄 조치를 정정합니다 — 수리된 벤치마크 재실행분이 이미 있었고 F등급이 유지됐습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "정정: 오염 딱지를 찾아 폐쇄했는데 한 시간 전의 재실행분을 놓쳤습니다",
           "확인: 깨끗한 벤치마크에서도 그 전략은 F등급 그대로입니다",
           "의미: 대기 중인 연구 2건의 전제는 유효합니다 — 폐쇄를 해제했습니다",
           "교훈: 오염 발견과 재실행 확인은 같은 검사에서 함께 해야 합니다")),
    list(type = "kv", emoji = "📊", heading = "요지",
         kv = list(
           "재실행분" = "14시13분 실행 · 오염 없음 · F등급 유지",
           "조치"     = "폐쇄 해제 · 인용을 깨끗한 실행분으로 교체 지시",
           "영향"     = "대기열 2건 착수 가능 복원 (미배정 유지)")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "두 연구는 깨끗한 실행분 산출물 기준으로 착수 가능합니다",
           "판정: 자본 영향 없음 — 대기열 상태 정정입니다"))
  ),
  footer = "📚 FQ-167/168 게이트 해제 · ASBT_20260809_141324_57032",
  force = TRUE)  # 직전 발송 정정 — 30분 잠금 명시 우회
cat("[tg] 발송 완료\n")
