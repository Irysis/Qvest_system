# unpark_entry.R — 파킹 entry 를 active 로 되돌린다 (도훈 지시 2026-09-18 · 파킹 5건 측정)
#
# ★원장 쓰기는 반드시 원장 모듈의 writer(.rf_write — 원자 쓰기 + 재파싱)를 경유한다.
# ★rf_park_entry 의 거울상이다: status parked → active, 사유·시각을 남기고 parked_reason 은 보존한다.
#   (2026-08-29 수동 언파크가 남긴 필드 규약 — unparked_at · unpark_reason — 을 그대로 따른다)
# 사용: Rscript run/unpark_entry.R <base_id> "<reason>"
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L || !nzchar(args[2])) stop("usage: unpark_entry.R <base_id> <reason>")
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
obj <- rf_load(1L, ROOT)
i <- .rf_find(obj, args[1])
if (is.na(i)) stop("entry 부재: ", args[1])
e <- obj$entries[[i]]
if (!identical(e$status, "parked")) stop(sprintf("status=%s — parked 만 되돌린다", e$status))
e$status        <- "active"
e$unparked_at   <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
e$unpark_reason <- as.character(args[2])
obj$entries[[i]] <- e
.rf_write(obj, 1L, ROOT)
cat(sprintf("[unpark] %s parked -> active (parked_reason 보존: %s)\n", args[1],
            substr(as.character(e$parked_reason %||% ""), 1, 60)))
