## test_program_paper_sync.R — 라우팅 산출(v5) → 프로그램 큐 동기화 검사 (양방향 · 멱등)
## 운영 등록부 · 운영 라우팅 산출을 건드리지 않는다 — 임시 디렉터리에서만.
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else dirname(sys.frame(1)$ofile %||% ".")
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- file.path(.qv_self_dir(), "..", "..")
if (dir.exists(file.path(SELF, "02_Infrastructure/programs"))) ROOT <- SELF
setwd(ROOT); ROOT <- getwd()
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/programs/program_paper_sync.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
live_md5 <- tools::md5sum(pr_path())

sb <- file.path(tempdir(), "pps_sb"); dir.create(file.path(sb, "stage_artifacts/paper_recharge"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(sb, "06_Registry"), showWarnings = FALSE)
file.copy(pr_path(), file.path(sb, "06_Registry/research_programs.json"), overwrite = TRUE)
mk <- function(key, engine, verdict) list(title = paste("t", key), id = key, paper_key = key, source = "arxiv",
                                          engine = engine, engine_secondary = list(), verdict = verdict,
                                          route = if (verdict == "testable") "replication" else "skip", reason = "r")
v5 <- list(date = "20261013", schema_version = "paper_router_v5",
           papers = list(mk("axv:1", "return", "testable"), mk("axv:2", "defense", "data_pipeline_required"),
                         mk("axv:3", "construction", "testable"), mk("axv:4", "not_relevant", "skip"),
                         mk("axv:5", "defense", "redundant"), mk("axv:6", "bogus_engine", "testable")))
v4 <- list(date = "20261012", schema_version = "paper_router_v4",
           papers = list(list(title = "old", paper_key = "axv:9", route = "replication", verdict = "testable")))
writeLines(toJSON(v5, auto_unbox = TRUE), file.path(sb, "stage_artifacts/paper_recharge/alpha_search_route_20261013.json"))
writeLines(toJSON(v4, auto_unbox = TRUE), file.path(sb, "stage_artifacts/paper_recharge/alpha_search_route_20261012.json"))

cat("=== A. 수집(순수 함수) ===\n")
it <- pps_collect(Sys.glob(file.path(sb, "stage_artifacts/paper_recharge/alpha_search_route_*.json")))
keys <- vapply(it, function(x) x$item$key, character(1))
chk("엔진 3종 × 허용 verdict 만 수집(3건)", setequal(keys, c("axv:1", "axv:2", "axv:3")), paste(keys, collapse = ","))
chk("not_relevant · redundant · 어휘 밖 엔진은 제외(위반 주입)", !any(c("axv:4", "axv:5", "axv:6") %in% keys))
chk("v4 산출(엔진 필드 없음)은 건너뛴다", !("axv:9" %in% keys))
chk("엔진 → 프로그램 대응", identical(sort(vapply(it, function(x) x$program, character(1))),
                                    sort(c("P1_RETURN", "P2_DEFENSE", "P3_CONSTRUCTION"))))

cat("\n=== B. 실행 · 멱등 ===\n")
reg_p <- file.path(sb, "06_Registry/research_programs.json")
a1 <- pps_run(root = sb, registry_path = reg_p)
chk("첫 실행에 3건 들어간다", sum(a1) == 3L, paste(names(a1), a1))
a2 <- pps_run(root = sb, registry_path = reg_p)
chk("두 번째 실행은 0건(멱등)", length(a2) == 0L || sum(a2) == 0L)
pr_dequeue("P1_RETURN", consumer = "test", path = reg_p)
a3 <- pps_run(root = sb, registry_path = reg_p)
chk("소비한 재료도 되살아나지 않는다", length(a3) == 0L || sum(a3) == 0L)
chk("등록부 스키마 유지", length(pr_validate(pr_load(path = reg_p))) == 0L)

cat("\n=== C. 운영 등록부는 그대로 ===\n")
chk("검사가 운영 등록부를 바꾸지 않았다", identical(unname(tools::md5sum(pr_path())), unname(live_md5)))

cat(sprintf("\n== program_paper_sync: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"program_paper_sync","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))   # 배터리 요약 계약(run_all_hooks.sh _last_summary_json)
if (FAIL > 0L) quit(status = 1L)
