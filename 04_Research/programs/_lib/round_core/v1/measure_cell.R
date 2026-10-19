## round_core v1 · 칸 1개 측정 — 정본 셀 워커(rf_cell_worker.R → run_paper_replication) · round_kit rk_measure_cell 이관
##   사양 md5 = 사전등록 값이어야 한다(R2) · 결과가 ok 면 건너뛴다 · 등재: 변형 칸만 2계층 모듈 풀(기준 · 진단 = QVEST_RP_REGISTER=0) ·
##   기준 · 진단 칸은 요인 분석을 끈다(라운드가 읽지 않음 · 등급 산출 뒤 단계) — 변형 칸은 WP2 프로파일이 소비처를 확인할 때까지 유지.
##   실행: Rscript measure_cell.R <round_dir> <code>   (측정 서버 ms_submit 이 생기면 실행기가 그쪽을 먼저 쓴다 — WP2)
suppressPackageStartupMessages(library(jsonlite))
source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), "04_Research/programs/_lib/round_core/v1/load.R"))
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 2L) stop("usage: measure_cell.R <round_dir> <code>")
ROOT <- rc_root(); setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
rd <- rc_abs(a[1], ROOT); code <- a[2]
spec <- rc_spec_load(file.path(rd, "round_spec.json"), ROOT); P <- rc_paths(rd, spec, ROOT)
if (!file.exists(P$prereg)) stop("[measure] 등록 전 — 측정하지 않는다(R2)")
pre <- rc_json_read(P$prereg)
cell <- Filter(function(z) identical(z$code, code), pre$cells)
if (!length(cell) || is.null(cell[[1]]$spec)) stop("[measure] 사전등록에 측정할 칸이 없다: ", code)
cs <- rc_abs(cell[[1]]$spec, ROOT)
if (!identical(rc_md5(cs), cell[[1]]$md5)) stop("[measure] 칸 사양 md5 ≠ 사전등록(R2): ", code)
dir.create(P$results, recursive = TRUE, showWarnings = FALSE)
out <- file.path(P$results, paste0(code, ".json"))
if (file.exists(out) && isTRUE(fromJSON(out)$ok)) { cat("[측정] 이미 있음:", code, "\n"); quit(status = 0) }
role <- cell[[1]]$role %||% "variant"
if (!identical(role, "variant")) Sys.setenv(QVEST_RP_REGISTER = "0", QVEST_RP_NO_FACTOR_ANALYSIS = "1")
t0 <- Sys.time()
rc <- system2("Rscript", c(file.path(ROOT, "02_Infrastructure/ops/rf_cell_worker.R"), shQuote(cs), "1", code, shQuote(out)),
              stdout = file.path(P$results, paste0(code, ".log")), stderr = file.path(P$results, paste0(code, ".err.log")))
sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
rc_perf_log(spec[["round_id"]], "measure_cell", sec, list(code = code, role = role, rc = rc), root = ROOT)
cat(sprintf("[측정] %s rc=%s · %.1f분\n", code, rc, sec / 60))
quit(status = if (identical(as.integer(rc), 0L)) 0L else 1L)
