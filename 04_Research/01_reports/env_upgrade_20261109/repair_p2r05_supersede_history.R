## repair_p2r05_supersede_history.R — 등록부 P2R05 의 supersede_history 에 빠진 두 번째 이력(dedc7a49 → bf45f4e7)을 보충한다 · 2026-11-08
##
## 왜: 두 번째 재핀(PerformanceAnalytics 2.1.0 → 2.0.8) 때 pr_record_round 가 modifyList 로 병합해 덧붙인 이력 원소를 버렸다
##     (이름 없는 리스트는 modifyList 가 합치지 못한다). writer 는 .pr_merge 로 수리했다(배열 = 통째로 교체).
## 원본 = 사전등록 파일 repins[2](from_md5 · at · reason) — 손으로 적지 않는다. 표시: recorded_late = 보충 시각 · 사유.
## 실행: Rscript repair_p2r05_supersede_history.R          계획만(쓰기 0)
##       Rscript repair_p2r05_supersede_history.R --apply  등록부 writer(pr_record_round) 경유로 보충
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
APPLY <- "--apply" %in% commandArgs(trailingOnly = TRUE)
md5 <- function(f) unname(as.character(tools::md5sum(f)))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R")))
if (!exists(".pr_merge")) stop("[repair] writer 가 아직 옛 판(.pr_merge 없음) — 수리 전엔 보충해도 또 버려진다 · 중단")
PR <- "stage_artifacts/programs/P2_DEFENSE/P2R05_distribution_target/prereg.json"
pre <- fromJSON(file.path(ROOT, PR), simplifyVector = FALSE)
rr <- Filter(function(r) identical(r$round_id, "P2R05_distribution_target"), pr_get(pr_load(ROOT), "P2_DEFENSE")$rounds)[[1]]
H <- rr$supersede_history %||% list()
cur <- md5(file.path(ROOT, PR))
stopifnot(identical(rr$status, "registered"), identical(rr$prereg_md5, cur), length(pre$repins) == 2L,
          length(H) == 1L, identical(H[[1]]$to_md5, pre$repins[[2]]$from_md5))
rp <- pre$repins[[2]]
add <- list(from_md5 = rp$from_md5, to_md5 = cur, at = rp$at, reason = rp$reason,
            recorded_late = paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), " — writer 결함(modifyList 가 이름 없는 리스트를 합치지 못해 이력 원소를 버림)으로 빠진 이력을 ",
                                   "writer 수리(.pr_merge) 뒤 사전등록 repins[2] 값으로 보충"))
cat(sprintf("[repair] 현재 이력 %d건(마지막 %s → %s) · 보충 %s → %s (%s)\n", length(H), substr(H[[1]]$from_md5, 1, 8), substr(H[[1]]$to_md5, 1, 8),
            substr(add$from_md5, 1, 8), substr(add$to_md5, 1, 8), add$at))
if (!APPLY) { cat("[repair] 계획만 — 쓰지 않았다(--apply 로 적용)\n"); quit(status = 0L) }
pr_record_round("P2_DEFENSE", list(round_id = "P2R05_distribution_target", prereg = PR, prereg_md5 = cur, status = "registered",
                                   supersede_history = c(H, list(add))), root = ROOT)
r2 <- Filter(function(r) identical(r$round_id, "P2R05_distribution_target"), pr_get(pr_load(ROOT), "P2_DEFENSE")$rounds)[[1]]
stopifnot(length(r2$supersede_history) == 2L, identical(r2$supersede_history[[2]]$to_md5, cur), identical(r2$prereg_md5, cur))
cat(sprintf("[repair] 적용 — 이력 %d건 · prereg_md5 %s 그대로\n", length(r2$supersede_history), substr(r2$prereg_md5, 1, 8)))
