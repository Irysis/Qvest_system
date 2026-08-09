## WT-D20260809_003 P7 — 세션 간 연구 배정 충돌 방지 (도훈 지시 2026-08-09)
## 공유면 = 원장(alpha_frontier_queue). 소유권을 owner 필드에 **명시적으로** 쓰고, 착수 전 그것을 읽는다.
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[own] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
ow <- vapply(Q$entries, function(e) if (is.null(e$owner)) "" else paste(e$owner, collapse=" "), character(1))
st <- vapply(Q$entries, function(e) if (is.null(e$status)) "" else as.character(e$status)[1], character(1))
ti <- vapply(Q$entries, function(e) gsub("[\r\n]+"," ", as.character(e$title)[1]), character(1))

say("=== 원장 %d 항목 · 오늘(2026-08-09) 소유권 표기분 ===", length(ids))
today <- grepl("2026-08-09", ow, fixed = TRUE)
for (i in which(today)) say("  %-8s | %-38s | %s", ids[i], substr(st[i],1,38), substr(ti[i],1,58))

say("=== 오늘 생성된 WorkTask (세션 간 in-flight 신호) ===")
d <- list.dirs("qepm/mailbox/worktask", recursive = FALSE)
d <- sort(basename(d)[grepl("20260809", basename(d), fixed = TRUE)])
for (x in d) {
  f <- file.path("qepm/mailbox/worktask", x, "task.json")
  h <- if (file.exists(f)) tryCatch(fromJSON(f)$hypothesis_title, error=function(e) "?") else "?"
  say("  %-20s %s", x, substr(gsub("[\r\n]+"," ", h), 1, 72))
}

say("=== 내 세션 소유 (WT-D20260809_001/003) ===")
mine_ids <- ids[grepl("WT-D20260809_00[13]", ow) | grepl("session 2026-08-09", ow)]
say("  %s", paste(mine_ids, collapse = ", "))

## 내가 낳은 후속 3건에 소유권 상태를 '미배정(사용가능)' 으로 **명시** — 다른 세션이 집어갈 수 있게
for (k in c("FQ-164","FQ-165","FQ-169","FQ-170")) {
  i <- which(ids == k); if (!length(i)) next
  Q$entries[[i]]$owner <- paste0(
    "UNCLAIMED — WT-D20260809_00", if (k %in% c("FQ-164","FQ-165")) "1" else "3",
    " 이 발행한 next_probe. 착수 세션은 이 필드를 'CLAIMED <session> <ts>' 로 먼저 갱신하고 시작할 것(세션 간 중복 착수 방지, 도훈 지시 2026-08-09).")
  say("  %s owner 를 UNCLAIMED 규약 문구로 표기", k)
}

## 원장 헤더에 배정 규약 명문화 — 이것이 세션 간 공유되는 유일한 표면
Q$consume_rule <- paste0(Q$consume_rule,
  " ★세션 간 배정 규약(도훈 지시 2026-08-09): ①착수 전 owner 필드 확인 — 'CLAIMED' 면 착수 금지, 'UNCLAIMED' 면 자기 세션으로 CLAIMED 갱신 후 시작",
  " ②신규 ID 는 **하드코딩 금지** — 원장 최대 번호+1 을 계산해 배정하고, 기록 후 **재읽기로 존재 확인**",
  " (2026-08-09 실사고: FQ-167/168 등재가 병렬 세션 선점과 충돌해 조용히 생략됐고 close_round 서술이 거짓이 됨 → FQ-169/170 재배정)",
  " ③close_round 의 frontier_update 는 **실제 기록 결과에서 파생**시킬 것(선언에서 파생 금지).")
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("=== 기록 완료 · 재읽기 항목 %d ===", length(read_frontier_queue()$entries))
