#!/usr/bin/env Rscript
# p12_gate_lift.R — FQ-167/168 게이트 해제 (자기정정: 사전 확인이 기존 재실행분을 놓침)
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))

lift <- paste0(
  "★게이트 해제 (2026-08-09 — 등재 직후 자기정정): 수리 벤치 위 clean 재실행분이 **이미 존재**했다 — ",
  "ASBT_20260809_141324_57032 (contaminated=FALSE, **grade F 유지**). 내 사전 확인(15:44)이 오염 딱지(14:18)는 ",
  "찾고 재실행분(14:13)은 놓쳤다 — '오염 발견 시 재실행분 존재 여부를 같은 스캔에서 확인' 규약화 대상. ",
  "⇒ 전제 재검증 완료: Grade F 는 clean 벤치에서도 유지 — 본 항목의 가설은 유효 전제 위에 있다. ",
  "인용은 clean run(141324_57032) 산출물로 교체할 것(12:33 오염 run 인용 금지). data_gate 원상 복구."
)
for (fq in c("FQ-167", "FQ-168")) {
  i <- which(ids == fq)
  if (length(i) == 1) {
    Q$entries[[i]]$contamination_precheck_20260809 <- paste0(
      as.character(Q$entries[[i]]$contamination_precheck_20260809)[1], " || ", lift)
    dg <- as.character(Q$entries[[i]]$data_gate)[1]
    Q$entries[[i]]$data_gate <- sub("^★폐쇄 2026-08-09: .*? 구: ", "", dg)
    cat("[lift]", fq, "게이트 해제·data_gate 복구\n")
  }
}
res <- write_frontier_queue(Q)
cat("[fq167/168-lift] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "정정 — 재측정분이 이미 있었습니다. 대기열 2건 게이트 해제, 전제는 유효 확인",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "직전 폐쇄 조치를 정정합니다 — 수리된 벤치마크 재실행분이 이미 있었고 F등급이 유지됐습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "정정: 오염 딱지를 찾고 폐쇄했는데 한 시간 전 재실행분을 놓쳤습니다",
           "확인: 깨끗한 벤치마크에서도 그 전략은 F등급 그대로입니다",
           "의미: 대기 중인 연구 2건의 전제는 유효합니다 — 폐쇄를 해제했습니다",
           "교훈: 오염 발견과 재실행 확인은 같은 검사에서 함께 해야 합니다")),
    list(type = "kv", emoji = "📊", heading = "요지",
         kv = list(
           "clean재실행" = "14:13 run · 오염 없음 · F등급 유지",
           "조치"       = "폐쇄 해제 · 인용을 clean run 으로 교체 지시",
           "영향"       = "대기열 2건 착수 가능 상태 복원 (미배정 유지)")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "두 연구는 clean run 산출물 기준으로 착수 가능합니다",
           "판정: 자본 영향 없음 — 대기열 상태 정정입니다"))
  ),
  footer = "📚 FQ-167/168 게이트 해제 · ASBT_20260809_141324_57032",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 직전 발송 정정 보고 명시 우회
cat("[tg] 발송 완료\n")
