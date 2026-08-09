#!/usr/bin/env Rscript
# fq002_correct_next_action_20260809.R — FQ-002 next_action ① 무효 재라벨 (착수 전 확인 산물).
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue()
i <- which(vapply(Q$entries, function(x) identical(as.character(x$id %||% ""), "FQ-002"), logical(1)))
stopifnot(length(i) == 1L)

Q$entries[[i]]$next_action_prior_20260802 <- Q$entries[[i]]$next_action   # 원문 보존(지식 손실 금지)

Q$entries[[i]]$next_action <- paste0(
  "★①(구 next_action: '분모 시총 primary 신규 사전등록 라운드')는 **착수 금지 — 설계상 독립 확인이 아니다**. ",
  "파일럿에서 사전등록 **1급(계약금액/최근매출액 12M)이 t_NW 0.570 으로 미달**했고 ",
  "**2급(시총 분모)이 t_plain 1.972 로 살았다**. ①은 그 2급을 새 1급으로 승격해 재는 것인데, ",
  "'데이터 이미 지불됨(재크롤 불요)' = **같은 36개월**이라 t 가 그대로 재현될 뿐이다(selection 후 재보고). ",
  "1급이 떨어지면 그것이 판정이다([[feedback-preregistered-primary-fails-that-is-the-verdict]] · FQ-182 동형). ",
  "파일럿 자신도 \"'lead'이지 '확립' 아님\" + 섭동 취약성 sd 0.378 을 명시했다. ",
  "▶정당 경로 2개: ",
  "(A) **전구간 크롤 지불** — revival_conditions 의 정본 경로. 2005~2016 조선·플랜트 수주 사이클(미검) 포함 259개월에서 ",
  "**독립 표본** 확인. 비용 체결만 10,360 호출(1.5일)/전량 22,533(3.2일) @ 일 7,000. ",
  "(B) **소비면 전환(구 ②)** — 랭킹이 아니라 **필터/오버레이**로 측정. 같은 데이터라도 **질문이 다르므로 갈아타기가 아니다**. ",
  "선례: MAX5 랭킹 -1.616 → 필터 ΔIR +0.169 ([[project-consumption-path-changes-verdict-20260802]]). ",
  "▶권고 순서 = (B) 먼저. 데이터 비용 0 이고, (B) 결과가 (A)의 3.2일 지불 EV 를 알려준다 — 필터로도 안 되면 크롤 EV 급락.")

Q$entries[[i]]$design_flaw_note <- paste0(
  "2026-08-09 착수 전 확인에서 검거. 이 항목은 '라운드를 없앤' 사례다 — ",
  "구 next_action 을 그대로 따랐으면 같은 데이터에서 2급을 1급으로 올려 재고 t≈1.97 을 '재현'으로 보고했을 것이다.")

Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("FQ-002 정정 — added=%d removed=%d 총 %d\n", res$added, res$removed, res$n))
cat(sprintf("  status 유지: %s\n", Q$entries[[i]]$status))
