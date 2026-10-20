## test_round_core_measure_server.R — 측정 서버(04_Research/programs/_lib/round_core/measure_server.R · 1계층 속도 계획 WP2 §6) 검사
##   A 칸 사양 정규화 · API(경로 · 목록 · data.frame · md5 불일치 · 중복 · 자동 워커 수)
##   B 스냅샷 압축 왕복(정수 키) — 꺼낸 표 = 원형 identical · 뮤테이션 양성 대조(NaN · −0 · 비정수 · 속성)
##   C 워커 격리(스텁 루트 · 실제 워커 프로세스) — 칸마다 새 프로세스와 같은 출발 상태(전역 · 옵션 · 환경변수 · 부착 · 난수 · 싱크 ·
##     장치 · 임시 파일) · load_rawdata 스냅샷 = 파일 원형 · 사본 변경이 스냅샷에 새지 않음 · 축 멤버십 재사용(1회 계산) · out_root ·
##     quit 상태 전달 · 죽은 워커 1회 재큐 → worker_died · 배리어 잡힘 = 전 칸 init_failed(fail-closed)
##   D (무거움 · QVEST_MS_TEST_HEAVY=1) 결과 동일 — 같은 칸들을 ① 기존 경로 새 프로세스(rf_cell_worker.R) ② 서버(순서 A) ③ 서버(순서 역순)로
##     재고 run_id · strategy_id · 산출 경로 · 실행 시각만 가린 바이트 대조(보유 · 기간 수익 · NAV · authoritative_remeasure · 계약 표 전부 ·
##     bt_result.rds 구성 요소 identical). 칸 = QVEST_MS_TEST_CELLS(기본 P0R01_E1_C0 · C1 · C4 — GPU 불필요 칸).
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
throws <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
MS_FILE <- file.path(ROOT, "04_Research/programs/_lib/round_core/measure_server.R")
source(MS_FILE)
## 표 동일(.internal.selfref 포인터 제외 — 같은 내용의 두 data.table 은 그 포인터만 다르다)
same_dt <- function(a, b) {
  strip <- function(x) { at <- attributes(x); at[[".internal.selfref"]] <- NULL; at }
  identical(as.list(a), as.list(b)) && identical(strip(a), strip(b))
}
sl <- function(p) gsub("\\\\", "/", p)          # 경로 구분자 통일(tempfile 은 역슬래시 · 서버는 슬래시)

cat("A 칸 사양 정규화 · API\n")
td <- sl(tempfile("ms_test_")); dir.create(file.path(td, "rd", "specs"), recursive = TRUE)
sp1 <- file.path(td, "rd", "specs", "X_C0.json"); writeLines('{"code":"X_C0","label":"t"}', sp1)
sp2 <- file.path(td, "other.json"); writeLines('{"label":"no code"}', sp2)
n1 <- .ms_norm_specs(c(sp1, sp2), ROOT)
chk("A1 경로 벡터 — 코드는 사양의 code · 없으면 파일명", identical(vapply(n1, `[[`, "", "code"), c("X_C0", "other")))
chk("A2 결과 경로 기본값 = <라운드>/results/<code>.json(specs 아래일 때) · 그 밖 NA", identical(n1[[1]]$result, file.path(td, "rd", "results", "X_C0.json")) && is.na(n1[[2]]$result))
n2 <- .ms_norm_specs(list(list(spec = sp1, code = "Y", role = "reference", env = list(QVEST_RP_NO_FACTOR_ANALYSIS = "0"))), ROOT)
chk("A3 role ≠ variant = 등재 끔 · 요인 분석 끔(v1 규칙) · env 가 덮는다", identical(n2[[1]]$env$QVEST_RP_REGISTER, "0") && identical(n2[[1]]$env$QVEST_RP_NO_FACTOR_ANALYSIS, "0"))
n3 <- .ms_norm_specs(data.frame(spec = sp1, code = "Z", role = "variant", stringsAsFactors = TRUE), ROOT)
chk("A4 data.frame 입력 · variant = env 없음", identical(n3[[1]]$code, "Z") && !length(n3[[1]]$env))
chk("A5 코드 중복 = 거부", throws(.ms_norm_specs(c(sp1, sp1), ROOT)))
chk("A6 사양 없음 = 거부", throws(.ms_norm_specs(file.path(td, "none.json"), ROOT)))
chk("A7 코드 형식 오류 = 거부", throws(.ms_norm_specs(list(list(spec = sp1, code = "a b")), ROOT)))
chk("A8 자동 워커 수 = floor((여유 − 예비) ÷ 워커당 GB) · 최소 1 · 칸 수 이하",
    ms_workers_auto(10, free_gb = 9.5, gb_per_worker = 4) == 1L && ms_workers_auto(10, free_gb = 20, gb_per_worker = 4) == 4L &&
    ms_workers_auto(2, free_gb = 40, gb_per_worker = 4) == 2L && ms_workers_auto(5, free_gb = NA) == 1L && ms_workers_auto(5, free_gb = 1) == 1L)
chk("A8b 워커당 GB 기본값 = 실측 정점 근거(PERF_measure.json · 요인 분석 켠 칸 ≈ 9.9GB → 10)",
    identical(eval(formals(ms_workers_auto)$gb_per_worker), 10) || nzchar(Sys.getenv("QVEST_MS_GB_PER_WORKER")))
r_md5 <- ms_submit(list(list(spec = sp1, md5 = "00000000000000000000000000000000", result = file.path(td, "r.json"))), workers = 1)
chk("A9 사양 md5 ≠ 사전등록 = 측정하지 않는다(R2 · 워커 기동 없음)", identical(r_md5$status, "spec_md5_mismatch") && identical(r_md5$ok, FALSE))
writeLines('{"ok": true}', file.path(td, "ok.json"))
r_skip <- ms_submit(list(list(spec = sp1, result = file.path(td, "ok.json"))), workers = 1)
chk("A10 결과가 이미 ok = 건너뜀(skip_if_ok 기본)", identical(r_skip$status, "skipped_ok") && isTRUE(r_skip$ok))

cat("B 스냅샷 압축 왕복(정수 키)\n")
set.seed(7)
X <- data.table(Date = as.Date("2020-01-01") + c(0:7, NA, 9), Ticker = c("A005930", "가나다", NA, "A005930", "Z", "Z", "가나다", "A", "B", "A"),
                flag = c(0, 1, 1, NA, 0, 0, 1, 0, 1, 1), px = c(1.5, 2, 3, 4, 5, 6, 7, 8, 9, 10), z = c(0, -0, 1, 2, 3, 4, 5, 6, 7, 8),
                nn = c(1, NaN, 2, 3, 4, 5, 6, 7, 8, 9), big = c(3e9, 1, 2, 3, 4, 5, 6, 7, 8, 9), lg = c(TRUE, NA, FALSE, TRUE, TRUE, FALSE, TRUE, TRUE, FALSE, NA),
                i = 1:10)
setattr(X, "custom_attr", list(a = 1))
pk <- .ms_pack(X); U <- .ms_unpack(pk)
chk("B1 왕복 identical(열 · 형 · 속성 — selfref 제외)", same_dt(U, X))
kinds <- vapply(pk$cols, `[[`, "", "k")
chk("B2 압축 대상 = 문자 · Date · 정수값 실수(flag) / 원형 유지 = 비정수(px) · −0(z) · NaN(nn) · int 범위 밖(big) · 논리 · 정수",
    identical(unname(kinds[c("Ticker", "Date", "flag")]), rep(c("chr", "dbl_int", "dbl_int"), c(1, 1, 1))) &&
      all(kinds[c("px", "z", "nn", "big", "lg", "i")] == "raw"), paste(names(kinds), kinds, collapse = " "))
chk("B3 뮤테이션 ① NaN 을 정수로 접으면 원형이 깨진다(검사가 잡는 차이)", !identical(as.double(as.integer(X$nn)), X$nn))
chk("B4 뮤테이션 ② −0 을 정수로 접으면 부호 비트가 사라진다(1/x 로 탐지)", 1 / X$z[2] < 0 && 1 / as.double(as.integer(X$z[2])) > 0)
U$px[1] <- 99
chk("B5 꺼낸 사본을 바꿔도 스냅샷 불변(다음 사본 = 원형)", same_dt(.ms_unpack(pk), X))

cat("C 워커 격리(스텁 루트 · 실제 워커 프로세스)\n")
SR <- file.path(td, "root"); for (d in c("02_Infrastructure/ops", "02_Infrastructure/alpha_search", "02_Infrastructure/contracts", "02_Infrastructure/factor_db",
                                         "02_Infrastructure/validation", "04_Research/programs/_lib/round_core", ".cache", "specs")) dir.create(file.path(SR, d), recursive = TRUE)
writeLines(c('detect_lookahead <- function(run_all_path, verbose = TRUE) {',
             '  cat("1\\n", file = file.path(Sys.getenv("QM_ROOT"), ".cache", "la_calls.txt"), append = TRUE)',
             '  list(clean = TRUE, n_lines = length(readLines(run_all_path)), violations = list()) }'),
           file.path(SR, "02_Infrastructure/validation/lookahead_detector.R"))
invisible(file.copy(MS_FILE, file.path(SR, "04_Research/programs/_lib/round_core/measure_server.R")))
RD <- data.frame(Date = as.Date("2021-01-04") + 0:5, Ticker = c("A", "B", "가", "A", NA, "C"), v = c(1.5, -1, 2, 0, 3.25, -2), K200 = c(1, 0, 1, 1, 0, 1))   # v = 비정수 → 압축에서 원형 열
arrow::write_parquet(RD, file.path(SR, ".cache", "RAWDATA.parquet"))
arrow::write_parquet(data.frame(Date = as.Date("2021-01-04") + 0:5, BM_Ret = c(0.01, -0.02, 0, 0.01, 0.02, -0.01)), file.path(SR, ".cache", "benchmark.parquet"))
writeLines(c('rb_cell_wait_s <- function() 0L',
             'rb_wait <- function(max_wait_s, poll_s = 1, root = NULL) { h <- identical(Sys.getenv("WP2_STUB_BARRIER"), "held")',
             '  list(proceed = !h, status = list(state = if (h) "held" else "free"), waited_s = 0) }'), file.path(SR, "02_Infrastructure/ops/refresh_barrier.R"))
writeLines(c('suppressMessages(library(data.table))',
             'load_rawdata <- function(use_cache = TRUE) { r <- file.path(Sys.getenv("QM_ROOT"), ".cache")',
             '  list(RAWDATA = as.data.table(arrow::read_parquet(file.path(r, "RAWDATA.parquet"))), BM_DT = as.data.table(arrow::read_parquet(file.path(r, "benchmark.parquet")))) }'),
           file.path(SR, "02_Infrastructure/backtest_harness.R"))
writeLines('corp_action_member <- function(...) TRUE', file.path(SR, "02_Infrastructure/factor_db/factor_z_standard.R"))
writeLines(c('ma_membership <- function(DT, ep) {',
             '  if (!exists("corp_action_member", mode = "function")) sys.source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/factor_db/factor_z_standard.R"), envir = globalenv())',
             '  cat("1\\n", file = file.path(Sys.getenv("QM_ROOT"), ".cache", "memo_calls.txt"), append = TRUE)',
             '  !is.na(DT$v) & DT$v > 0 }'), file.path(SR, "02_Infrastructure/contracts/measurement_axis.R"))
writeLines(c('source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/backtest_harness.R"))',
             'source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/contracts/measurement_axis.R"))',
             'source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/validation/lookahead_detector.R"))',
             'run_paper_replication <- function(strategy_name, SPEC, out_root = NULL) {',
             '  if (is.null(out_root)) out_root <- file.path(Sys.getenv("QM_ROOT"), "stage_artifacts", "replication")',
             '  od <- file.path(out_root, strategy_name); dir.create(od, recursive = TRUE, showWarnings = FALSE)',
             '  eng <- file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/ops/rf_cell_worker.R")',
             '  la1 <- detect_lookahead(eng)',
             '  ld <- new.env(parent = globalenv()); sys.source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/validation/lookahead_detector.R"), envir = ld)',
             '  la2 <- ld$detect_lookahead(eng, verbose = FALSE)',
             '  stopifnot(identical(la1, la2))',
             '  r <- load_rawdata(use_cache = TRUE)',
             '  f <- as.data.table(arrow::read_parquet(file.path(Sys.getenv("QM_ROOT"), ".cache", "RAWDATA.parquet")))',
             '  sa <- function(x) { a <- attributes(x); a[[".internal.selfref"]] <- NULL; a }',
             '  same <- identical(as.list(r$RAWDATA), as.list(f)) && identical(sa(r$RAWDATA), sa(f))',
             '  mem <- ma_membership(r$RAWDATA, list(id = "e1", hygiene = TRUE, excluded_flags = "F", liq_min = 1, price_min = NA))',
             '  setorder(r$RAWDATA, -K200, Ticker); set(r$RAWDATA, 1L, "K200", 7); r$BM_DT[, BM_Ret := 0]   # 제자리 변경(엔진의 setorder · set 모양 — 원형 열 v 까지 재배열)',
             '  r$RAWDATA[, v := v * 100]',
             '  list(out_dir = od, same = same, mem = which(mem), cam = exists("corp_action_member", mode = "function")) }'),
           file.path(SR, "02_Infrastructure/alpha_search/run_paper_replication.R"))
writeLines(c('.OBS <- list(globals = ls(globalenv(), all.names = TRUE), digits = getOption("digits"), leak = Sys.getenv("WP2_LEAK", ""),',
             '  search = search(), seed = exists(".Random.seed", envir = globalenv()), wd = getwd(), sinks = sink.number(),',
             '  devs = length(grDevices::dev.list()), tmp = length(list.files(tempdir())), tz = Sys.getenv("TZ", ""))',
             'suppressMessages({ library(data.table); library(jsonlite) })',
             'args <- commandArgs(trailingOnly = TRUE)',
             'SPEC_P <- args[1]; SNAME <- args[3]; OUT_P <- args[4]',
             'ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT)',
             'SPEC <- fromJSON(SPEC_P, simplifyVector = FALSE)',
             'source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))',
             'res <- run_paper_replication(SNAME, SPEC)',
             'if (identical(SPEC$mode, "quit3")) quit(status = 3)',
             'if (identical(SPEC$mode, "die")) tools::pskill(Sys.getpid())',
             'assign(paste0("LEAK_", SNAME), 1, envir = globalenv()); options(digits = 3); Sys.setenv(WP2_LEAK = "1", TZ = "UTC")',
             'attach(list(x = 1), name = "leak_env"); set.seed(1); invisible(runif(1)); setwd(tempdir())',
             'writeLines("x", file.path(tempdir(), "leak.txt")); grDevices::pdf(file.path(tempdir(), "x.pdf"))',
             'jsonlite::write_json(list(ok = TRUE, code = SPEC$code, artifacts = res$out_dir, obs = .OBS, same = res$same, mem = res$mem, cam = res$cam,',
             '  cargs = commandArgs(trailingOnly = TRUE)), OUT_P, auto_unbox = TRUE)',
             'zz <- file(file.path(dirname(OUT_P), paste0(SNAME, ".sinkleak.txt")), "w"); sink(zz)',
             'quit(status = 0)'), file.path(SR, "02_Infrastructure/ops/rf_cell_worker.R"))
for (k in c("S1", "S2", "S3")) writeLines(sprintf('{"code":"%s","mode":"ok"}', k), file.path(SR, "specs", paste0(k, ".json")))
writeLines('{"code":"SQ","mode":"quit3"}', file.path(SR, "specs", "SQ.json"))
writeLines('{"code":"SD","mode":"die"}', file.path(SR, "specs", "SD.json"))
old_root <- Sys.getenv("QM_ROOT"); Sys.setenv(QM_ROOT = SR)
res_dir <- file.path(td, "res"); out_root <- file.path(td, "out")
cs <- lapply(c("S1", "S2", "S3"), function(k) list(spec = file.path(SR, "specs", paste0(k, ".json")), result = file.path(res_dir, paste0(k, ".json"))))
r1 <- ms_submit(cs, workers = 1, out_root = out_root)
J <- lapply(c("S1", "S2", "S3"), function(k) fromJSON(file.path(res_dir, paste0(k, ".json")), simplifyVector = TRUE))
chk("C1 세 칸 모두 ok · 한 워커가 차례로", all(r1$ok) && identical(sort(unique(r1$worker)), 1L), paste(r1$status, collapse = ","))
base_g <- J[[1]]$obs$globals
chk("C2 칸 시작 전역 = 비어 있음(앞 칸의 LEAK_* · SPEC · args 없음)", all(vapply(J, function(j) length(j$obs$globals) == 0L, NA)),
    paste(unlist(lapply(J, function(j) j$obs$globals)), collapse = ","))
obs_txt <- function(f) paste(vapply(J, function(j) paste(unlist(j$obs[f]), collapse = "/"), ""), collapse = " | ")
chk("C3 옵션 · 환경변수 · TZ · 작업 디렉터리 원상(앞 칸의 digits=3 · WP2_LEAK · TZ=UTC · setwd(tempdir))",
    all(vapply(J, function(j) j$obs$digits == 7 && !nzchar(j$obs$leak) && !identical(j$obs$tz, "UTC") && identical(sl(j$obs$wd), SR), NA)),
    obs_txt(c("digits", "leak", "tz", "wd")))
## 싱크 1 = 서버의 칸 로그 싱크 하나뿐(앞 칸이 남긴 싱크는 없다 · 새 프로세스는 stdout 리디렉션이라 0 — 측정 경로에 sink.number 소비자 없음)
chk("C4 부착 · 난수 · 싱크 · 장치 · 임시 파일 원상(leak_env · set.seed · 남긴 sink · pdf · tempdir 파일)",
    all(vapply(J, function(j) !("leak_env" %in% j$obs$search) && !any(grepl("^package:(data.table|jsonlite)$", j$obs$search)) &&
                 !isTRUE(j$obs$seed) && j$obs$sinks == 1 && j$obs$devs == 0 && j$obs$tmp == 0, NA)),
    obs_txt(c("seed", "sinks", "devs", "tmp", "search")))
chk("C5 load_rawdata = 파일 원형 identical(칸마다 · 앞 칸이 사본을 바꿔도)", all(vapply(J, function(j) isTRUE(j$same), NA)))
calls <- if (file.exists(file.path(SR, ".cache", "memo_calls.txt"))) length(readLines(file.path(SR, ".cache", "memo_calls.txt"))) else 0L
chk("C6 축 멤버십 재사용 — 3칸에 원 함수 1회 · 결과 동일 · 원 함수 전역 부수효과 재현", calls == 1L &&
      all(vapply(J, function(j) identical(as.integer(j$mem), c(1L, 3L, 5L)) && isTRUE(j$cam), NA)) &&
      identical(r1$memo_axis, c("miss", "hit", "hit")), sprintf("calls=%d memo=%s", calls, paste(r1$memo_axis, collapse = ",")))
la_calls <- if (file.exists(file.path(SR, ".cache", "la_calls.txt"))) length(readLines(file.path(SR, ".cache", "la_calls.txt"))) else 0L
chk("C6b 정적 PIT 검사 재사용 — 3칸 × 2회(전역 source · 사적 sys.source)에 검출기 1회 · 결과 identical", la_calls == 1L, sprintf("calls=%d", la_calls))
chk("C7 out_root 기본값 주입 · 칸 산출물 사이드카(판본)", all(file.exists(file.path(out_root, c("S1", "S2", "S3"), "measure_server.json"))) &&
      identical(unname(vapply(J, function(j) sl(dirname(j$artifacts)), "")), rep(out_root, 3)),
    paste(vapply(J, function(j) j$artifacts, ""), collapse = " | "))
chk("C8 commandArgs = Rscript rf_cell_worker.R <spec> 1 <code> <result>", identical(sl(J[[2]]$cargs), c(file.path(SR, "specs", "S2.json"), "1", "S2", file.path(res_dir, "S2.json"))),
    paste(J[[2]]$cargs, collapse = " "))
chk("C9 판본 지문 하나(같은 워커 · 같은 스냅샷)", length(unique(r1$data_version)) == 1L && all(nzchar(r1$data_version)))
sc <- fromJSON(file.path(out_root, "S1", "measure_server.json"), simplifyVector = TRUE)
chk("C9b 스냅샷 압축(정수 키) — 기동 때 풀어 원형 identical 확인 뒤 사용(사이드카 기록) · C5 가 칸마다 파일 원형과 identical",
    isTRUE(sc$packed) && identical(sc$pack_note, "verified_identical"), paste(sc$packed, sc$pack_note))
r2 <- ms_submit(list(list(spec = file.path(SR, "specs", "SQ.json"), result = file.path(res_dir, "SQ.json")),
                     list(spec = file.path(SR, "specs", "SD.json"), result = file.path(res_dir, "SD.json")),
                     list(spec = file.path(SR, "specs", "S1.json"), code = "S1b", result = file.path(res_dir, "S1b.json"))), workers = 1, out_root = out_root)
chk("C10 quit(status = 3) = rc 3 · 결과 없음(no_result)", identical(as.integer(r2$rc[r2$code == "SQ"]), 3L) && identical(r2$status[r2$code == "SQ"], "no_result"),
    sprintf("rc=%s(%s) status=%s", r2$rc[r2$code == "SQ"], class(r2$rc), r2$status[r2$code == "SQ"]))
chk("C11 죽은 워커 — 그 칸 1회 재큐 뒤 worker_died · 나머지 칸은 새 워커가 완주", identical(r2$status[r2$code == "SD"], "worker_died") &&
      isTRUE(r2$ok[r2$code == "S1b"]), paste(r2$code, r2$status, collapse = " · "))
Sys.setenv(WP2_STUB_BARRIER = "held")
r3 <- ms_submit(list(list(spec = file.path(SR, "specs", "S2.json"), code = "S2b", result = file.path(res_dir, "S2b.json"))), workers = 1, out_root = out_root)
Sys.unsetenv("WP2_STUB_BARRIER")
chk("C12 배리어 잡힘 = 스냅샷 없이 전 칸 init_failed(fail-closed)", grepl("^init_failed:refresh_lock", r3$status) && identical(r3$ok, FALSE), r3$status)
Sys.setenv(QVEST_MS_PROFILE = "1")
r4 <- ms_submit(list(list(spec = file.path(SR, "specs", "S3.json"), code = "S3p", result = file.path(res_dir, "S3p.json"))), workers = 1, out_root = out_root)
Sys.unsetenv("QVEST_MS_PROFILE")
st4 <- tryCatch(fromJSON(file.path(attr(r4, "batch_dir"), "done", "S3p.json"), simplifyVector = FALSE)$stages, error = function(e) NULL)
chk("C13 단계 시간(QVEST_MS_PROFILE=1) — 칸 ok · 감싼 함수(run_paper_replication · load_rawdata)의 시간 기록",
    isTRUE(r4$ok) && all(c("run_paper_replication", "load_rawdata") %in% vapply(st4, function(z) z$fn, "")) &&
      identical(as.integer(fromJSON(file.path(res_dir, "S3p.json"))$mem), c(1L, 3L, 5L)),
    paste(r4$status, length(st4), paste(utils::tail(readLines(file.path(res_dir, "S3p.err.log"), warn = FALSE), 3), collapse = " | ")))
## 뮤테이션 양성 대조 — 원형 열 깊은 사본(raw = data.table::copy)을 빼면 칸의 제자리 변경이 스냅샷에 샌다 → 파수꾼이 잡아 워커를 바꾼다(결과는 그대로 원형)
ms_src <- readLines(MS_FILE, encoding = "UTF-8", warn = FALSE)
hit <- grepl("raw = data.table::copy(p$v))", ms_src, fixed = TRUE)
chk("M0 뮤테이션 치환 성사(원형 열 사본 제거)", sum(hit) == 1L)
ms_mut <- ms_src; ms_mut[hit] <- sub("raw = data.table::copy(p$v))", "raw = p$v)", ms_mut[hit], fixed = TRUE)
writeLines(ms_mut, file.path(SR, "04_Research/programs/_lib/round_core/measure_server.R"), useBytes = TRUE)
cm <- lapply(c("S1", "S2", "S3"), function(k) list(spec = file.path(SR, "specs", paste0(k, ".json")), code = paste0("MUT_", k), result = file.path(res_dir, paste0("MUT_", k, ".json"))))
r5 <- ms_submit(cm, workers = 1, out_root = out_root)
J5 <- lapply(c("S1", "S2", "S3"), function(k) fromJSON(file.path(res_dir, paste0("MUT_", k, ".json")), simplifyVector = TRUE))
corrupt_logs <- list.files(file.path(attr(r5, "batch_dir"), "logs"), pattern = "^snapshot_corrupt_")
chk("M1 사본을 빼면 파수꾼이 제자리 변경을 잡는다(워커 교체 기록) · 그래도 칸마다 원형 identical(fail-closed)",
    length(corrupt_logs) >= 1L && length(unique(r5$worker)) >= 2L && all(r5$ok) && all(vapply(J5, function(j) isTRUE(j$same), NA)),
    sprintf("corrupt_logs=%d workers=%s same=%s", length(corrupt_logs), paste(r5$worker, collapse = ","), paste(vapply(J5, function(j) isTRUE(j$same), NA), collapse = ",")))
writeLines(ms_src, file.path(SR, "04_Research/programs/_lib/round_core/measure_server.R"), useBytes = TRUE)
Sys.setenv(QM_ROOT = old_root)

## ---- D 결과 동일(무거움) ----
## 가림 순서: 산출 경로(현재 · 산출물에 기록된 경로 — 둘 다 run_id 를 품는다) → run_id · strategy_id → 실행 시각
.mask_txt <- function(p, ar, dir) {
  t <- rawToChar(readBin(p, "raw", file.info(p)$size)); Encoding(t) <- "UTF-8"
  for (d in unique(c(dir, dirname(as.character(ar$bt_result_path)))))
    for (s in unique(c(d, gsub("/", "\\\\", d), gsub("/", "\\\\\\\\", d)))) t <- gsub(s, "<DIR>", t, fixed = TRUE)
  for (s in unique(c(ar$strategy_id, ar$run_id))) t <- gsub(s, "<RUN>", t, fixed = TRUE)
  gsub("20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:?[0-9]{2}", "<TS>", t)
}
## 산출물 디렉터리 대조 — 같으면 character(0) · 다르면 다른 파일 이름(+ bt_result 구성 요소)
ms_cmp_artifacts <- function(A, B, ignore = c("measure_server.json")) {
  ra <- fromJSON(file.path(A, "authoritative_remeasure.json"), simplifyVector = FALSE); rb <- fromJSON(file.path(B, "authoritative_remeasure.json"), simplifyVector = FALSE)
  fa <- setdiff(list.files(A), ignore); fb <- setdiff(list.files(B), ignore)
  bad <- c(if (length(setdiff(fa, fb))) paste0("only_A:", setdiff(fa, fb)), if (length(setdiff(fb, fa))) paste0("only_B:", setdiff(fb, fa)))
  for (f in intersect(fa, fb)) {
    if (identical(f, "bt_result.rds")) {
      x <- readRDS(file.path(A, f)); y <- readRDS(file.path(B, f))
      for (k in union(names(x), names(y))) {
        if (identical(k, "manifest")) {
          m <- function(z) { z <- as.data.frame(z); z[intersect(names(z), c("run_id", "strategy_id", "run_datetime", "created_at"))] <- NULL; z }
          if (!identical(m(x[[k]]), m(y[[k]]))) bad <- c(bad, "bt_result.rds$manifest")
        } else {
          dz <- function(z) { if (is.data.frame(z)) { z <- as.data.frame(z); z[intersect(names(z), c("run_id", "strategy_id"))] <- NULL }; z }
          if (!isTRUE(all.equal(dz(x[[k]]), dz(y[[k]]), tolerance = 0)) || !identical(dz(x[[k]]), dz(y[[k]]))) bad <- c(bad, paste0("bt_result.rds$", k))
        }
      }
    } else if (grepl("\\.(png|parquet)$", f)) {
      if (!identical(unname(tools::md5sum(file.path(A, f))), unname(tools::md5sum(file.path(B, f))))) bad <- c(bad, f)
    } else if (!identical(.mask_txt(file.path(A, f), ra, A), .mask_txt(file.path(B, f), rb, B))) bad <- c(bad, f)
  }
  bad
}
if (identical(Sys.getenv("QVEST_MS_TEST_HEAVY"), "1")) {
  cat("D 결과 동일(무거움 — 실제 칸 · 기존 경로 새 프로세스 vs 서버 순서 A · 역순)\n")
  cells <- strsplit(Sys.getenv("QVEST_MS_TEST_CELLS", "P0R01_E1_C0,P0R01_E1_C1,P0R01_E1_C4"), ",")[[1]]
  sdir <- Sys.getenv("QVEST_MS_TEST_SPECDIR", file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs"))
  hd <- Sys.getenv("QVEST_MS_TEST_OUT", file.path(td, "heavy")); dir.create(hd, recursive = TRUE, showWarnings = FALSE)
  spec_of <- function(k) file.path(sdir, paste0(k, ".json"))
  ## ① 기존 경로 — rf_cell_worker.R 새 프로세스(산출 = 정본 기본값 stage_artifacts/replication → 대조 뒤 옮긴다)
  fresh <- list(); t_fresh <- c()
  for (k in cells) {
    out <- file.path(hd, "fresh", paste0(k, ".json")); dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    t0 <- Sys.time()
    rc <- system2(.ms_rscript(), c("--no-environ", file.path(ROOT, "02_Infrastructure/ops/rf_cell_worker.R"), spec_of(k), "1", k, out),
                  stdout = sub("\\.json$", ".log", out), stderr = sub("\\.json$", ".err.log", out))
    t_fresh[k] <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    j <- fromJSON(out, simplifyVector = TRUE); fresh[[k]] <- j$artifacts
    cat(sprintf("    새 프로세스 %s rc=%s · %.1f초\n", k, rc, t_fresh[k]))
  }
  run_srv <- function(order, tag) {
    cs <- lapply(order, function(k) list(spec = spec_of(k), code = k, result = file.path(hd, tag, paste0(k, ".json"))))
    t0 <- Sys.time(); r <- ms_submit(cs, workers = as.integer(Sys.getenv("QVEST_MS_TEST_WORKERS", "1")), out_root = file.path(hd, tag, "art"))
    list(r = r, sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
         art = stats::setNames(r$artifacts, r$code))
  }
  sA <- run_srv(cells, "srvA"); sB <- run_srv(rev(cells), "srvB")
  cat(sprintf("    서버 순서 A %.1f초 · 역순 %.1f초 · 새 프로세스 합 %.1f초\n", sA$sec, sB$sec, sum(t_fresh)))
  for (k in cells) {
    dA <- ms_cmp_artifacts(fresh[[k]], sA$art[[k]]); dB <- ms_cmp_artifacts(fresh[[k]], sB$art[[k]])
    chk(sprintf("D %s — 새 프로세스 = 서버(순서 A)", k), !length(dA), paste(dA, collapse = ","))
    chk(sprintf("D %s — 새 프로세스 = 서버(역순)", k), !length(dB), paste(dB, collapse = ","))
  }
  chk("D 서버 칸 전부 ok · 판본 하나", all(sA$r$ok) && all(sB$r$ok) && length(unique(c(sA$r$data_version, sB$r$data_version))) == 1L)
  if (length(cells) >= 2L)
    chk("D 대조기 양성 대조 — 다른 칸끼리는 다르다고 잡는다", length(ms_cmp_artifacts(fresh[[cells[1]]], sA$art[[cells[2]]])) > 0L)
  writeLines(toJSON(list(cells = cells, fresh_s = as.list(t_fresh), server_a_s = sA$sec, server_b_s = sB$sec,
                         server_a = sA$r, server_b = sB$r, fresh_artifacts = fresh), auto_unbox = TRUE, pretty = TRUE, digits = NA),
             file.path(hd, "heavy_result.json"))
  for (k in cells) if (startsWith(gsub("\\\\", "/", fresh[[k]]), file.path(ROOT, "stage_artifacts/replication/")))
    file.rename(fresh[[k]], file.path(hd, "fresh", paste0(k, "_art")))
} else cat("D 결과 동일 — 건너뜀(QVEST_MS_TEST_HEAVY=1 이면 실제 칸으로 잰다)\n")

unlink(td, recursive = TRUE)
cat(sprintf("\n== test_round_core_measure_server: PASS %d · FAIL %d ==\n", PASS, FAIL))
if (FAIL > 0L) quit(status = 1)
