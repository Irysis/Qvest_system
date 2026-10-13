## test_mechanism_atlas.R — 메커니즘 지도 writer · 검증기 검사 (양방향: 정상 + 위반 주입 · 멱등)
## 운영 지도 · 등록부를 건드리지 않는다 — 임시 경로에서만.
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
source("02_Infrastructure/programs/mechanism_atlas.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}

good <- list(paper_key = "axv:2401.00001", extract_version = "v1", engine = "defense",
             mechanism = list(name = "10개월 이동평균 추세 현금 규칙", family = "time_series_trend", description = "지수가 10개월 평균 아래면 현금"),
             market = list(country = "US", universe = "S&P 500"), period = list(start = "1973", end = "2012"),
             claims = list(list(metric = "max_drawdown", value = -0.233, t = NULL, net_of_cost = FALSE, where = "Table 2")),
             crisis = list(label = "reported", episodes = list(list(name = "2008", metric = "drawdown", value = -0.1, vs_benchmark = -0.5, where = "Figure 4"))),
             extraction = list(model = "opus", confidence = 0.8, source_url = "https://arxiv.org/abs/2401.00001"))
bad_nowhere <- good; bad_nowhere$paper_key <- "axv:2"; bad_nowhere$claims[[1]]$where <- ""
bad_engine <- good; bad_engine$paper_key <- "axv:3"; bad_engine$engine <- "alpha"
bad_missing <- good; bad_missing$paper_key <- "axv:4"; bad_missing$market <- NULL
null_value <- good; null_value$paper_key <- "axv:5"; null_value$claims[[1]]$value <- NULL; null_value$claims[[1]]$where <- ""

cat("=== A. 검증기 ===\n")
chk("정상 레코드 통과", length(ma_validate(good)) == 0L, paste(ma_validate(good), collapse = ";"))
chk("원문 위치 없는 수치 주장 거부(위반 주입 — 날조 차단)", length(ma_validate(bad_nowhere)) > 0L)
chk("어휘 밖 엔진 거부", length(ma_validate(bad_engine)) > 0L)
chk("필수 필드 누락 거부", length(ma_validate(bad_missing)) > 0L)
chk("수치가 null 이면 위치 없어도 통과(모르면 null)", length(ma_validate(null_value)) == 0L)

cat("\n=== B. 합치기 · 멱등 ===\n")
ap <- tempfile(fileext = ".jsonl"); st <- tempfile(fileext = ".json")
writeLines(toJSON(list(good, bad_nowhere, bad_engine, null_value), auto_unbox = TRUE, null = "null"), st)
r1 <- ma_ingest(st, path = ap)
chk("통과분만 추가(2건) · 거부 2건", r1$added == 2L && length(r1$rejected) == 2L, sprintf("(added=%d rej=%d)", r1$added, length(r1$rejected)))
r2 <- ma_ingest(st, path = ap)
chk("다시 합쳐도 0건(키 중복)", r2$added == 0L && r2$duplicate == 2L)
chk("지도 줄 수 = 2", length(ma_load(path = ap)) == 2L)
v2 <- good; v2$extract_version <- "v2"
writeLines(toJSON(list(v2), auto_unbox = TRUE, null = "null"), st)
chk("추출 판(version)이 다르면 새로 쌓인다", ma_ingest(st, path = ap)$added == 1L)

cat("\n=== C. 일감 목록(ma_pending) ===\n")
rp <- tempfile(fileext = ".json"); file.copy(pr_path(), rp)
pr_enqueue("P2_DEFENSE", list(key = "axv:2401.00001", kind = "paper", title = "done one", engine = "defense"), path = rp)
pr_enqueue("P1_RETURN", list(key = "axv:2401.99999", kind = "paper", title = "new one", engine = "return"), path = rp)
pe <- ma_pending(10L, registry_path = rp, atlas_path = ap)
pk <- vapply(pe, function(x) x$paper_key, character(1))
chk("지도에 이미 있는 논문은 일감에서 빠진다", !("axv:2401.00001" %in% pk))
chk("지도에 없는 논문은 일감에 든다", "axv:2401.99999" %in% pk)

cat(sprintf("\n== mechanism_atlas: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"mechanism_atlas","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))   # 배터리 요약 계약(run_all_hooks.sh _last_summary_json)
if (FAIL > 0L) quit(status = 1L)
