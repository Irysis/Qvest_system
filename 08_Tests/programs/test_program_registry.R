## test_program_registry.R — v10.01 리서치 프로그램 등록부 writer 검사 (양방향: 정상 + 위반 주입)
## 운영 등록부를 건드리지 않는다 — 임시 사본에서만 쓴다.
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else dirname(sys.frame(1)$ofile %||% ".")
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- normalizePath(file.path(.qv_self_dir(), "..", ".."), mustWork = FALSE)
if (dir.exists(file.path(SELF, "02_Infrastructure/programs"))) ROOT <- SELF
setwd(ROOT)
source("02_Infrastructure/programs/program_registry.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
errs <- function(expr) inherits(tryCatch(expr, error = function(e) e), "error")

live <- pr_path()
live_md5 <- tools::md5sum(live)
tmp <- tempfile(fileext = ".json"); file.copy(live, tmp)

cat("=== A. 운영 등록부 검사 통과 ===\n")
chk("운영 등록부 스키마 통과", length(pr_validate(pr_load(path = live))) == 0L,
    paste(pr_validate(pr_load(path = live)), collapse = "; "))

cat("\n=== B. 큐 — 정상과 중복 차단 ===\n")
ok1 <- pr_enqueue("P1_RETURN", list(key = "arxiv:9999.00001", title = "t1", label = "return"), path = tmp)
chk("새 key 는 들어간다", isTRUE(ok1))
ok2 <- pr_enqueue("P2_DEFENSE", list(key = "arxiv:9999.00001", title = "t1-dup", label = "defense"), path = tmp)
chk("같은 key 는 다른 프로그램 큐에도 못 들어간다(위반 주입)", identical(ok2, FALSE))
chk("key 없는 항목은 거부", errs(pr_enqueue("P1_RETURN", list(title = "no key"), path = tmp)))
h <- pr_dequeue("P1_RETURN", consumer = "test", path = tmp)
chk("꺼낸 항목 = 넣은 항목", identical(h$key, "arxiv:9999.00001"))
chk("꺼낸 뒤 큐가 비고 소비 기록이 남는다",
    length(pr_get(pr_load(path = tmp), "P1_RETURN")$queue) == 0L &&
      length(pr_get(pr_load(path = tmp), "P1_RETURN")$consumed) == 1L)
chk("빈 큐에서 꺼내면 NULL", is.null(pr_dequeue("P1_RETURN", path = tmp)))
chk("이미 소비한 key 는 다시 못 들어간다(동기화 재실행 · 위반 주입)",
    identical(pr_enqueue("P1_RETURN", list(key = "arxiv:9999.00001", title = "again"), path = tmp), FALSE))

cat("\n=== C. 라운드 — 사전등록 강제(R2) ===\n")
chk("prereg 없는 라운드는 거부(위반 주입)", errs(pr_record_round("P0_FRONTIER", list(round_id = "R1"), path = tmp)))
pr_record_round("P0_FRONTIER", list(round_id = "R1", prereg = "x/prereg.json"), path = tmp)
pr_record_round("P0_FRONTIER", list(round_id = "R1", prereg = "x/prereg.json", verdict = "reached"), path = tmp)
## 운영 사본에는 이미 라운드(P0R01 등)가 있다 — 개수는 이 검사가 쓴 round_id 로만 센다(운영 상태를 빌리면 라운드가 기록될 때 깨진다 · 2026-10-15)
r <- Filter(function(x) identical(x$round_id, "R1"), pr_get(pr_load(path = tmp), "P0_FRONTIER")$rounds)
chk("같은 round_id 결과는 덮어 쓴다(한 줄 유지)", length(r) == 1L && identical(r[[1]]$verdict, "reached"))
chk("결과 뒤 사전등록 변경은 거부(위반 주입)",
    errs(pr_record_round("P0_FRONTIER", list(round_id = "R1", prereg = "y/other.json"), path = tmp)))

cat("\n=== D. 상태 · 선행 조건 ===\n")
chk("어휘 밖 상태는 거부(위반 주입)", errs(pr_set_status("P1_RETURN", "running", path = tmp)))
reg <- pr_load(path = tmp)
## 운영 P0 는 이미 active 일 수 있다 — 전이를 재려면 사본에서 blocked 로 되돌린 뒤 잰다(선행 조건 = 측정 계약 전부)
i0 <- which(vapply(reg$programs, function(p) identical(p$id, "P0_FRONTIER"), logical(1)))
reg$programs[[i0]]$status <- "blocked"
reg$programs[[i0]]$blocked_by <- lapply(reg$measurement_contract$items, function(m) m$id)
chk("측정 계약이 하나라도 남으면 P0 는 blocked 유지(음성 대조)",
    length(reg$measurement_contract$items) == 0L ||
      { rr <- reg; rr$measurement_contract$items[[1]]$status <- "todo"; identical(pr_get(pr_refresh_blocks(rr), "P0_FRONTIER")$status, "blocked") })
for (m in seq_along(reg$measurement_contract$items)) reg$measurement_contract$items[[m]]$status <- "done"
reg <- pr_refresh_blocks(reg)
chk("측정 계약이 다 끝나면 P0 는 ready", identical(pr_get(reg, "P0_FRONTIER")$status, "ready"))
chk("P4 는 P0 가 끝나기 전엔 blocked 유지", identical(pr_get(reg, "P4_ASSEMBLY")$status, "blocked"))
reg2 <- pr_load(path = tmp); reg2$programs[[1]]$blocked_by <- list("NO_SUCH")
chk("없는 선행 조건 참조는 검사 실패(위반 주입)", length(pr_validate(reg2)) > 0L)
chk("검사 실패 등록부는 저장 거부(부분 쓰기 없음)", errs(pr_save(reg2, path = tmp)))

cat("\n=== D2. 측정 계약 제외(pr_mc_drop) — 지우지 않고 결정 기록으로 옮긴다 ===\n")
tmp2 <- tempfile(fileext = ".json"); file.copy(live, tmp2)
r0 <- pr_load(path = tmp2); id0 <- r0$measurement_contract$items[[2]]$id
dep0 <- names(Filter(function(p) id0 %in% unlist(p$blocked_by), setNames(r0$programs, vapply(r0$programs, function(p) p$id, ""))))
chk("사유 없는 제외는 거부(위반 주입)", errs(pr_mc_drop(id0, reason = "", decided_by = "test", path = tmp2)))
chk("없는 항목 제외는 거부(위반 주입)", errs(pr_mc_drop("MC_NO_SUCH", reason = "x", decided_by = "test", path = tmp2)))
pr_mc_drop(id0, reason = "검사용 제외", decided_by = "test", path = tmp2)
r1 <- pr_load(path = tmp2)
chk("항목이 items 에서 빠지고 dropped 에 사유·결정자·직전 상태와 함께 남는다",
    !(id0 %in% vapply(r1$measurement_contract$items, function(m) m$id, "")) &&
      identical(r1$measurement_contract$dropped[[length(r1$measurement_contract$dropped)]]$id, id0) &&
      identical(r1$measurement_contract$dropped[[length(r1$measurement_contract$dropped)]]$dropped_reason, "검사용 제외") &&
      !is.null(r1$measurement_contract$dropped[[length(r1$measurement_contract$dropped)]]$status_before))
chk("프로그램 blocked_by 에서도 빠진다(검사 통과 · 참조 깨짐 없음)",
    length(pr_validate(r1)) == 0L && !any(vapply(r1$programs, function(p) id0 %in% unlist(p$blocked_by), logical(1))),
    paste(dep0, collapse = ","))

cat("\n=== E. 상태 줄 ===\n")
L <- pr_status_lines(pr_load(path = tmp))
chk("상태 줄 = 측정 계약 1줄 + 프로그램 수", length(L) == 1L + length(pr_load(path = tmp)$programs))

cat("\n=== F. 운영 등록부는 그대로 ===\n")
chk("검사가 운영 등록부를 바꾸지 않았다", identical(unname(tools::md5sum(live)), unname(live_md5)))

cat(sprintf("\n== program_registry: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"program_registry","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))   # 배터리 요약 계약(run_all_hooks.sh _last_summary_json)
if (FAIL > 0L) quit(status = 1L)
