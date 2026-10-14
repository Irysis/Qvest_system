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
## 사본의 미분류 보류는 비운다 — 운영 보류 건수를 빌리면 아래 개수 단정이 운영 상태에 따라 깨진다(2026-10-14 리뷰 U2)
local({ f <- file.path(sb, "06_Registry/research_programs.json"); r0 <- fromJSON(f, simplifyVector = FALSE)
  if (is.null(r0$paper_routing)) r0$paper_routing <- list()
  r0$paper_routing$unrouted <- list()
  writeLines(toJSON(r0, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), f, useBytes = TRUE) })
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

cat("\n=== D. 미분류 재료 — 검증기 보류분을 v5 분류로 큐에 옮긴다(2026-10-14 · 1810.08384 감독 실측) ===\n")
em <- pps_engine_map(Sys.glob(file.path(sb, "stage_artifacts/paper_recharge/alpha_search_route_*.json")))
chk("engine map: 판정 무관(redundant 도 분류) · axv: 제거 키 · not_relevant 표식 · 어휘 밖 · v4 제외",
    identical(em[["5"]], "P2_DEFENSE") && identical(em[["3"]], "P3_CONSTRUCTION") && identical(em[["4"]], "NOT_RELEVANT") &&
      !("6" %in% names(em)) && !("9" %in% names(em)), paste(names(em), em, collapse = " "))
h1 <- pr_hold_unrouted(list(key = "engine:RP_X", kind = "engine", paper_key = "5", base_id = "RP_X"), path = reg_p)
h2 <- pr_hold_unrouted(list(key = "engine:RP_X", kind = "engine", paper_key = "5"), path = reg_p)
h3 <- pr_hold_unrouted(list(key = "engine:RP_Y", kind = "engine", paper_key = "77", base_id = "RP_Y"), path = reg_p)
chk("보류 1회 · 같은 key 재보류 거부", isTRUE(h1) && isFALSE(h2) && isTRUE(h3))
chk("부팅 줄에 미분류 재료 수가 뜬다", any(grepl("미분류 재료 2", pr_status_lines(pr_load(path = reg_p)), fixed = TRUE)))
pps_run(root = sb, registry_path = reg_p)
R1 <- pr_load(path = reg_p)
q2 <- Filter(function(q) identical(q$key, "engine:RP_X"), pr_get(R1, "P2_DEFENSE")$queue)
chk("v5 분류된 보류분(논문 5 → defense)은 P2 큐로 · routed_by=router_v5",
    length(q2) == 1L && identical(q2[[1]]$routed_by, "router_v5"))
chk("분류 없는 보류분은 그대로 남는다(추측 배정 없음)",
    length(R1$paper_routing$unrouted) == 1L && identical(R1$paper_routing$unrouted[[1]]$key, "engine:RP_Y"))
mv <- pr_route_unrouted("engine:RP_Y", "P3_CONSTRUCTION", routed_by = "session", path = reg_p)
R2 <- pr_load(path = reg_p)
chk("세션 분류(pr_route_unrouted) → P3 큐 · 보류 비움",
    isTRUE(mv) && identical(pr_find_key(R2, "engine:RP_Y"), "P3_CONSTRUCTION") && !length(R2$paper_routing$unrouted))
chk("등록부 스키마 유지(보류 포함)", length(pr_validate(R2)) == 0L)

cat("\n=== E. 검증기 재료 배정 — 기본값 없이 라우팅 정본에서만(검증기 소스의 정의를 잘라 실행) ===\n")
## 구판: 등록부에 없으면 'P1_RETURN' 기본값 · 기저 음수(skipped)면 어느 큐에도 안 넣음 → 구성(P3) 논문이 '수익 엔진'으로 보고됐다.
VL <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), warn = FALSE)
.take <- function(nm) {
  i <- grep(paste0(nm, " <- function("), VL, fixed = TRUE)[1]
  if (is.na(i)) return(NULL)
  for (j in i:min(length(VL), i + 200L)) {
    e <- tryCatch(parse(text = VL[i:j]), error = function(e) NULL)
    if (!is.null(e)) return(e)
  }
  NULL
}
DEFS <- lapply(c(".v1001_key_forms", ".v1001_route", ".v1001_prog_name", ".v1001_handoff", ".v1001_material_line"), .take)
dir.create(file.path(sb, "02_Infrastructure/programs"), recursive = TRUE, showWarnings = FALSE)
for (f in c("program_registry.R", "program_paper_sync.R"))
  file.copy(file.path(ROOT, "02_Infrastructure/programs", f), file.path(sb, "02_Infrastructure/programs", f), overwrite = TRUE)
.handoff <- function(pkey, kind = "engine") {
  ev <- new.env(parent = globalenv()); J <- character(0)
  ev$ROOT <- sb; ev$PKEY <- pkey; ev$TITLE <- paste("t", pkey); ev$.fidelity <- "faithful"; ev$eng <- "x/engine.R"
  ev$.V1001_PROG_NAME <- c(P1_RETURN = "수익 엔진", P2_DEFENSE = "방어 엔진", P3_CONSTRUCTION = "구성")
  ev$jlog <- function(event, ...) J <<- c(J, event)
  for (d in DEFS) eval(d, envir = ev)
  ho <- ev$.v1001_handoff(file.path(sb, "art"), paste0("RP_T_", gsub("[^0-9]", "", pkey)), "F", kind = kind,
                          flags = list(base_below_threshold = identical(kind, "skipped")))
  list(ho = ho, J = J, line = ev$.v1001_material_line(ho))
}
if (any(vapply(DEFS, is.null, logical(1)))) chk("E0 검증기 도우미 정의 추출", FALSE, "정의 이름이 바뀌었으면 재조준") else {
  e3 <- .handoff("3")              # 큐에 axv:3 (B 절 동기화) — 정본 키 '3' 으로 찾는다
  R_e1 <- pr_load(path = reg_p)
  consumed_e1 <- any(vapply(pr_get(R_e1, "P3_CONSTRUCTION")$consumed %||% list(), function(q) identical(q$key, "axv:3"), logical(1)))
  still_q <- any(vapply(pr_get(R_e1, "P3_CONSTRUCTION")$queue %||% list(), function(q) identical(q$key, "axv:3"), logical(1)))
  chk("E1 큐의 axv: 키를 정본 키로 찾는다 → P3 · 논문 항목 소비(큐 → 소비 기록) · 엔진 재료 등록",
      identical(e3$ho$program, "P3_CONSTRUCTION") && identical(e3$ho$routed_by, "program_queue") && isTRUE(e3$ho$enqueued) &&
        consumed_e1 && !still_q,
      paste(e3$ho$program, e3$ho$routed_by, consumed_e1, still_q, paste(e3$J, collapse = ",")))
  e5 <- .handoff("5", kind = "skipped")   # v5 redundant → 큐에는 없지만 엔진 분류는 있다 · 기저 미달도 재료다
  chk("E2 큐에 없어도 v5 분류(판정 무관)로 배정 · 기저 미달(skipped)도 재료로 등록",
      identical(e5$ho$program, "P2_DEFENSE") && identical(e5$ho$routed_by, "router_v5") && isTRUE(e5$ho$enqueued))
  e4 <- .handoff("4")
  chk("E3 v5 not_relevant → 큐 · 보류 둘 다 없음(사유 줄)",
      is.na(e4$ho$program) && !isTRUE(e4$ho$enqueued) && !isTRUE(e4$ho$held) && grepl("어느 엔진 재료도 아니", e4$line))
  e8 <- .handoff("88", kind = "skipped")
  R3 <- pr_load(path = reg_p)
  chk("E4 분류 없음 → P1 기본값이 아니라 미분류 보류 · 보고 줄이 그 사실을 말한다 ★1810 재현",
      is.na(e8$ho$program) && isTRUE(e8$ho$held) && "v1001_unrouted" %in% e8$J &&
        any(vapply(R3$paper_routing$unrouted, function(u) identical(u$paper_key, "88"), logical(1))) &&
        grepl("미분류", e8$line) && !grepl("수익 엔진", e8$line), e8$line)
  chk("E5 등록부 스키마 유지", length(pr_validate(R3)) == 0L)
}

cat("\n=== F. 새 불변식 위반 주입(2026-10-14 리뷰 U14) ===\n")
Rv <- pr_load(path = reg_p)
Rv$paper_routing$unrouted <- c(Rv$paper_routing$unrouted %||% list(), list(list(key = "engine:RP_T_3", paper_key = "dup")))   # E1 이 P3 큐에 넣은 키와 같다
chk("F1 미분류 보류와 프로그램 큐의 같은 key → pr_validate 가 중복을 잡는다(쓰기 거부 사유)",
    any(grepl("중복", pr_validate(Rv), fixed = TRUE)), paste(pr_validate(Rv), collapse = " | "))
h4 <- pr_hold_unrouted(list(key = "engine:RP_NR", kind = "engine", paper_key = "4"), path = reg_p)   # v5 가 not_relevant 로 분류한 논문
pps_run(root = sb, registry_path = reg_p)
Rn <- pr_load(path = reg_p)
nr_left <- any(vapply(Rn$paper_routing$unrouted %||% list(), function(u) identical(u$key, "engine:RP_NR"), logical(1)))
nr_moved <- !is.na(pr_find_key(Rn, "engine:RP_NR"))
chk("F2 not_relevant 논문의 보류분은 동기화가 프로그램 큐로 옮기지 않는다(NOT_RELEVANT 건너뛰기)", isTRUE(h4) && nr_left && !nr_moved,
    paste(h4, nr_left, nr_moved))

cat("\n=== C. 운영 등록부는 그대로 ===\n")
chk("검사가 운영 등록부를 바꾸지 않았다", identical(unname(tools::md5sum(pr_path())), unname(live_md5)))

cat(sprintf("\n== program_paper_sync: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"program_paper_sync","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))   # 배터리 요약 계약(run_all_hooks.sh _last_summary_json)
if (FAIL > 0L) quit(status = 1L)
