## P2R05 캐시 워밍 드라이버(DESIGN §7.3 ④ · ⑤ · ⑥) — 셀 엔진 밖에서 엔진 파일 1개를 단독 실행해 내용 주소 예측 캐시를 채운다(평가 없음 · 측정 결과 없음).
##   ★RAWDATA 는 셀 경로와 같은 함수 · 같은 순서로 만든다(캐시 키 = 과제 + X · y · Xp 바이트 + 종목이라 패널이 1바이트라도 다르면 측정 때 다시 학습한다):
##     셀 경로 = rf_cell_worker.R → run_paper_replication.R §1(config.R · backtest_harness.R::load_rawdata(use_cache = TRUE) · Date(Asia/Seoul)) ·
##               §1-c(universe ALL_HYG → ma_inject_universe(ma_epoch_by_universe("ALL_HYG"))) → rf_cell_engine.R §0(DT <- RAWDATA · Date · setorder(Ticker, Date)) →
##               기저 엔진 = new.env(parent = globalenv()) 에 RAWDATA · BM_DT 만 넣고 sys.source
##     · .RP_START_DATE 는 넣지 않는다 — 셀 엔진도 기저 엔진에 안 넘긴다(엔진 기본 시작 2005-01-01 · 월 순번 k · 시드 = 20020697 + k 가 셀 측정과 같아야 키가 맞는다 · DESIGN §2.1)
##     · 엔진은 RAWDATA 의 .REQ ∪ Open 열만 고른다(engine.R §3) — 셀 엔진이 더하는 .TV · .adv20_l1 · .mom_12_1 열은 엔진 입력이 아니라 만들지 않는다
##     · 검증 = 측정 때 RX0 셀 로그의 '(trained 0, cache N)' — 아니면 measure.sh 가 분위 엔진 첫 칸을 단독으로 먼저 잰다(같은 GPU 에 분위 학습 둘이 겹치지 않게)
## 실행(warm_cache.sh 가 부른다 — 잠금 · 배리어 · 정적 검사 · GPU 게이트를 거친 뒤에만 · 직접 실행 = --force-direct):
##   Rscript warm_engine.R run <엔진 경로(저장소 상대)> <꼬리표 q50 | rx0>   → warm/<꼬리표>.json(학습 · 캐시 달 수 · 장치 · 양성 대조 · 예측표 · 작업본)
##   Rscript warm_engine.R monitor <엔진 로그> [배수]                      → 진행 줄 감시 한 번(월당 학습 초 추정 > 실행 중앙값 × 배수 · 진행 줄 정체 · CPU 학습 = 경고 줄) · 판정 아님 · 끄지 않는다
##   Rscript warm_engine.R finalize --fp-start=<파일> --fp-end=<파일> --mem-start=<MiB> --mem-end=<MiB> [--gate=<json>] [--lane=<값>] [--monitor-log=<파일>]
##                                                                          → 센티널 04_Research/programs/_lib/night_state/p2r05_warm.done(JSON · schema p2r05_warm_v1 · 원자적 쓰기)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
if (!file.exists(file.path(ROOT, "02_Infrastructure/hooks/qvest_hook_router.py"))) stop("[warm] 프로젝트 루트 표지 없음: ", ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROUND <- "P2R05_distribution_target"
RD_REL <- "04_Research/programs/P2_DEFENSE/P2R05_distribution_target"; RD <- file.path(ROOT, RD_REL); WD <- file.path(RD, "warm")
SENT <- file.path(ROOT, "04_Research/programs/_lib/night_state/p2r05_warm.done")
PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R05_distribution_target/prereg.json")
A <- commandArgs(trailingOnly = TRUE); MODE <- if (length(A)) A[1] else ""
argv <- function(k, d = NULL) { v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), A, value = TRUE, perl = TRUE)); if (length(v)) v[1] else d }
source(file.path(RD, "engine_checks.R")); DTC <- P2R05_DTC                       # register.R · precheck.R 과 같은 정의
.now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
.md5 <- function(f) if (!is.na(f) && file.exists(f)) unname(as.character(tools::md5sum(f))) else NA_character_
.rel <- function(p) if (is.na(p)) NA_character_ else sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", p))
.rd_json <- function(f) if (!is.null(f) && file.exists(f)) tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL) else NULL
.wjson <- function(x, f) {                                                      # 원자적 쓰기(임시 → 이름 바꾸기) — 읽는 쪽이 반쯤 쓴 파일을 보지 않게
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(f, ".tmp", Sys.getpid())
  writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), tmp, useBytes = TRUE)
  if (file.exists(f)) unlink(f)
  if (!file.rename(tmp, f)) { file.copy(tmp, f, overwrite = TRUE); unlink(tmp) }
}

if (identical(MODE, "run")) {
  if (length(A) < 3L) stop("usage: warm_engine.R run <엔진 경로(저장소 상대)> <꼬리표>")
  eng_rel <- A[2]; tag <- A[3]
  if (!identical(Sys.getenv("P2R05_WARM_FROM_SCRIPT"), "1") && !("--force-direct" %in% A))
    stop("[warm] warm_cache.sh 로만 부른다 — 잠금 · 배리어 · 정적 검사 · GPU 게이트를 거치지 않은 단독 실행 금지(같은 GPU 에 엔진 둘 = VRAM 초과 · DESIGN §7.3) · 우회 = --force-direct")
  if (!grepl("^[a-z0-9_]+$", tag, perl = TRUE)) stop("[warm] 꼬리표는 소문자 · 숫자 · 밑줄")
  eng <- file.path(ROOT, eng_rel); if (!file.exists(eng)) stop("[warm] 엔진 파일 없음: ", eng_rel)
  if (exists(".RP_START_DATE", envir = globalenv(), inherits = FALSE)) stop("[warm] 전역에 .RP_START_DATE 가 있다 — 셀 경로와 다른 시작일 · 월 순번 · 시드가 된다")
  kind <- DTC$engine_kind(eng_rel, ROOT)                                       # quantile(규칙 엔진 7 · 예측표 · cuda) · reseed(재시드 · cuda) · mean(RX0 평균 엔진 · 기존 캐시 공유)
  is_dt <- identical(kind, "quantile"); need_cuda <- kind %in% c("quantile", "reseed")
  t0 <- Sys.time(); eng_md5 <- .md5(eng)
  cat(sprintf("[warm %s] %s 시작 — 엔진 %s (md5 %s) · PYTORCH_CUDA_ALLOC_CONF=%s · pid %d\n", tag, .now(), eng_rel, eng_md5,
              Sys.getenv("PYTORCH_CUDA_ALLOC_CONF", "(없음)"), Sys.getpid()))
  ## 셀 경로와 같은 데이터(run_paper_replication §1 · §1-c 와 같은 함수 · 같은 순서)
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/config.R")))
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/backtest_harness.R")))
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/measurement_axis.R")))
  res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
  ep <- ma_epoch_by_universe("ALL_HYG", root = ROOT)
  ## 사양 측정 축 = 이 epoch(워커는 사양 fixed_axes.measurement_axis 의 epoch universe 로 러너를 부르고, 러너는 그 universe 의 활성 epoch 를 주입한다)
  sp_ax <- unique(vapply(Sys.glob(file.path(RD, "specs", "P2R05_*.json")), function(f) as.character(fromJSON(f, simplifyVector = FALSE)$fixed_axes$measurement_axis %||% NA_character_), ""))
  if (length(sp_ax) != 1L || !identical(sp_ax, ep$id)) stop(sprintf("[warm] 사양 측정 축(%s) ≠ 주입 epoch %s — 셀 경로와 같은 데이터가 아니다", paste(sp_ax, collapse = ","), ep$id))
  inj <- ma_inject_universe(RAWDATA, ep); RAWDATA <- inj$RAWDATA
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
  setorder(RAWDATA, Ticker, Date)                                               # rf_cell_engine §0 과 같은 정렬(안정 정렬 — 중복 키의 첫 행이 셀 경로와 같다)
  cat(sprintf("[warm %s] 데이터 — RAWDATA %d행(~ %s) · 측정 축 %s 주입(멤버 하루 중앙 %s종) · 엔진 실행(셀 엔진 밖 · 다른 칸 동시 실행 없음)\n", tag, nrow(RAWDATA),
              format(max(RAWDATA$Date)), ep$id, format(inj$diag$members_per_day_median)))
  .env <- new.env(parent = globalenv()); .env$RAWDATA <- RAWDATA; .env$BM_DT <- BM_DT
  err <- tryCatch({ sys.source(eng, envir = .env); NULL }, error = function(e) conditionMessage(e))
  t1 <- Sys.time()
  run_dir <- if (exists(".RD", envir = .env, inherits = FALSE)) gsub("\\\\", "/", as.character(get(".RD", envir = .env))[1]) else {
    c0 <- Sys.glob(file.path(dirname(eng), "_work", sprintf("run_*_%d", Sys.getpid()))); if (length(c0)) c0[which.max(file.mtime(c0))] else NA_character_ }
  rd_pq <- function(f) if (!is.na(run_dir) && file.exists(file.path(run_dir, f))) tryCatch(as.data.table(arrow::read_parquet(file.path(run_dir, f))), error = function(e) NULL) else NULL
  dg <- rd_pq("diag.parquet"); sch <- rd_pq("schedule.parquet")
  col <- function(k) if (!is.null(dg) && k %in% names(dg)) dg[[k]] else NULL
  src <- as.character(col("source") %||% character(0)); dev <- as.character(col("device") %||% character(0))
  ntr <- suppressWarnings(as.integer(col("n_train") %||% integer(0))); npr <- suppressWarnings(as.integer(col("n_pred") %||% integer(0)))
  secs <- suppressWarnings(as.numeric(col("secs") %||% numeric(0)))
  n_sched <- if (!is.null(sch)) nrow(sch) else NA_integer_
  n_diag <- if (!is.null(dg)) nrow(dg) else NA_integer_
  warm_m <- if (length(src) && length(npr) == length(src)) sum(src %in% c("train", "cache") & npr > 0L, na.rm = TRUE) else NA_integer_
  devs <- if (length(dev) && length(ntr) == length(dev)) sort(unique(dev[ntr > 0L])) else character(0)
  pc_cols <- if (!is.null(dg)) grep("^(synthetic|pc_|positive)", names(dg), value = TRUE, perl = TRUE) else character(0)
  pc <- lapply(setNames(pc_cols, pc_cols), function(k) { v <- dg[[k]][1]; if (is.numeric(v)) v else as.character(v) })
  FX <- if (exists("FACTORS", envir = .env, inherits = FALSE)) get("FACTORS", envir = .env) else NULL
  qp <- NULL
  if (is_dt) {                                                                  # 분위 예측표(DESIGN §7.2 — 엔진 판 = _work/qpred/<CODE_VERSION md5 8자>_<데이터 지문 8자>.parquet · 7 엔진 공유)
    q <- if (exists(".DT_QP", envir = .env, inherits = FALSE)) gsub("\\\\", "/", as.character(get(".DT_QP", envir = .env))[1]) else NA_character_
    how <- "engine_env(.DT_QP)"
    if (is.na(q) || !file.exists(q)) {                                          # 엔진 변수가 없으면 이 실행 뒤에 쓰인 가장 새 예측표(잠금 = 동시 실행 없음)
      cand <- list.files(file.path(ROOT, DTC$QPRED_DIR), pattern = "\\.parquet$", full.names = TRUE)
      cand <- cand[file.mtime(cand) >= t0 - 1]
      q <- if (length(cand)) cand[which.max(file.mtime(cand))] else NA_character_; how <- "newest_after_start"
    }
    if (!is.na(q) && file.exists(q)) qp <- list(path = .rel(q), md5 = .md5(q), bytes = unname(file.size(q)), match = how)
  }
  fails <- c(if (!is.null(err)) paste("엔진 오류:", err),
             if (is.null(dg)) "diag.parquet 없음(작업본 diag 를 못 읽었다)",
             if (is.null(sch)) "schedule.parquet 없음",
             if (!is.na(n_sched) && !is.na(n_diag) && n_sched != n_diag) sprintf("diag 행 %d ≠ 일정 %d", n_diag, n_sched),
             if (is.na(warm_m) || is.na(n_sched) || n_sched < 1L || warm_m != n_sched) sprintf("캐시 달 %s/%s — 전 달이 아니다(학습 · 예측 없는 달 = source none)", format(warm_m), format(n_sched)),
             if (need_cuda && !(length(devs) == 1L && identical(devs, "cuda"))) sprintf("학습 달 장치 [%s] — 전부 cuda 가 아니다(혼합 장치 캐시)", paste(devs, collapse = ",")),
             if (is_dt && is.null(qp)) "분위 예측표(_work/qpred) 를 이 실행에서 못 찾았다")
  out <- list(schema = "p2r05_warm_run_v1", tag = tag, ok = !length(fails), fail = as.list(fails),
              engine = list(path = eng_rel, md5 = eng_md5, kind = kind, quantile = is_dt), code_version = DTC$code_version_of(eng),
              started_at = format(t0, "%Y-%m-%dT%H:%M:%S%z"), finished_at = format(t1, "%Y-%m-%dT%H:%M:%S%z"),
              minutes = round(as.numeric(difftime(t1, t0, units = "mins")), 1), pid = Sys.getpid(),
              alloc_conf = Sys.getenv("PYTORCH_CUDA_ALLOC_CONF", NA_character_),
              data = list(epoch = ep$id, rawdata_rows = nrow(RAWDATA), rawdata_last = format(max(RAWDATA$Date)), members_per_day_median = inj$diag$members_per_day_median),
              run_dir = .rel(run_dir), sched_months = n_sched, diag_rows = n_diag, warm_months = warm_m,
              trained = sum(src == "train"), cached = sum(src == "cache"), none = sum(!(src %in% c("train", "cache"))),
              devices = as.list(devs), all_cuda = length(devs) == 1L && identical(devs, "cuda"),
              secs = list(median = if (any(src == "train")) stats::median(secs[src == "train"]) else NA_real_, max = if (any(src == "train")) max(secs[src == "train"]) else NA_real_),
              positive_control = list(pass = is.null(err) && !is.null(dg), fields = pc,
                                      note = "엔진이 학습 전 양성 대조를 돌리고 실패면 rc 3 으로 멈춘다(엔진 계약) — 끝까지 돌았으면 통과 · 수치 = diag 의 synthetic* · pc_* 열"),
              factors = list(rows = if (!is.null(FX)) nrow(FX) else NA_integer_, n_dates = if (!is.null(FX)) data.table::uniqueN(FX$Date) else NA_integer_,
                             first = if (!is.null(FX) && nrow(FX)) format(min(FX$Date)) else NA_character_),
              qpred = qp)
  .wjson(out, file.path(WD, paste0(tag, ".json")))
  cat(sprintf("[warm %s] %s %s — %.1f분 · 일정 %s · 캐시 달 %s(학습 %d · 적중 %d · 없음 %d) · 장치 [%s] · 예측표 %s%s\n", tag, .now(), if (out$ok) "끝" else "실패", out$minutes,
              format(n_sched), format(warm_m), out$trained, out$cached, out$none, paste(devs, collapse = ","), if (is.null(qp)) "-" else qp$path,
              if (length(fails)) paste0("\n  · ", paste(fails, collapse = "\n  · ")) else ""))
  quit(status = if (out$ok) 0L else 1L)
}

if (identical(MODE, "monitor")) {
  ## 엔진 진행 줄(12개월마다 · 파이썬 main) — '[dnn]   d/n months | trained t cache c | … | e min elapsed' 와 '… | k worker processes …' 를 읽는다(engine.R 3판 형식 · 템플릿 비지정 구역)
  lg <- if (length(A) >= 2L) A[2] else ""; mult <- suppressWarnings(as.numeric(if (length(A) >= 3L) A[3] else "3")); if (!is.finite(mult) || mult <= 1) mult <- 3
  if (!file.exists(lg)) { cat(sprintf("%s 로그 없음 — %s\n", .now(), lg)); quit(status = 0L) }
  L <- sub("\r$", "", readLines(lg, warn = FALSE, encoding = "UTF-8"))
  hd <- grep("worker processes", L, value = TRUE, fixed = TRUE)
  wk <- NA_integer_; devline <- NA_character_
  if (length(hd)) {
    m <- regmatches(hd[1], regexec("\\| ([0-9]+) worker processes", hd[1], perl = TRUE))[[1]]; if (length(m) == 2L) wk <- as.integer(m[2])
    m2 <- regmatches(hd[1], regexec("device ([A-Za-z]+)", hd[1], perl = TRUE))[[1]]; if (length(m2) == 2L) devline <- m2[2]
  }
  rx <- "\\[dnn\\]\\s+([0-9]+)/([0-9]+) months \\| trained ([0-9]+) cache ([0-9]+) .*\\| ([0-9.]+) min elapsed"
  P <- grep(rx, L, value = TRUE, perl = TRUE)
  cpu_warn <- !is.na(devline) && !identical(devline, "cuda")
  if (!length(P)) { cat(sprintf("%s 진행 줄 아직 없음(패널 구성 · 양성 대조 중)%s\n", .now(), if (cpu_warn) " · ★경고 — 장치 cuda 아님(CPU 학습 = 혼합 장치 캐시 · 수일 소요)" else "")); quit(status = 0L) }
  M <- do.call(rbind, lapply(regmatches(P, regexec(rx, P, perl = TRUE)), function(x) as.numeric(x[2:6])))
  colnames(M) <- c("done", "total", "trained", "cache", "elapsed_min")
  dtr <- diff(M[, "trained"]); del <- diff(M[, "elapsed_min"]) * 60; okb <- dtr > 0
  w <- if (is.na(wk)) 1L else wk
  rate <- if (any(okb)) del[okb] * w / dtr[okb] else numeric(0)                # 월당 학습 초(워커 1개 기준 추정 — 진행 줄 사이 경과 × 워커 ÷ 학습 달)
  med <- if (length(rate) >= 3L) stats::median(rate) else NA_real_
  last <- if (length(rate)) rate[length(rate)] else NA_real_
  age <- as.numeric(difftime(Sys.time(), file.mtime(lg), units = "secs"))
  blk <- if (sum(okb) >= 3L) stats::median(del[okb]) else NA_real_
  slow <- is.finite(med) && is.finite(last) && last > mult * med
  stall <- is.finite(blk) && age > mult * blk && M[nrow(M), "done"] < M[nrow(M), "total"]
  cur <- M[nrow(M), ]
  cat(sprintf("%s 진행 %d/%d · 학습 %d · 적중 %d · %.1f분 · 월당 학습 초(추정 · 워커 %s) 최근 %s · 실행 중앙 %s · 마지막 진행 줄 %.0f초 전%s%s%s\n", .now(),
              as.integer(cur["done"]), as.integer(cur["total"]), as.integer(cur["trained"]), as.integer(cur["cache"]), cur["elapsed_min"], format(w),
              if (is.finite(last)) sprintf("%.0f", last) else "-", if (is.finite(med)) sprintf("%.0f", med) else "-", age,
              if (slow) sprintf(" · ★경고 — 최근 월당 초 > 중앙 × %s(VRAM 시스템 메모리 폴백 의심 · 완료 달은 캐시에 남는다 · 워커를 줄인 재기동 판단 = Q)", format(mult)) else "",
              if (stall) sprintf(" · ★경고 — 진행 줄 정체(> 진행 줄 간격 중앙 × %s)", format(mult)) else "",
              if (cpu_warn) " · ★경고 — 장치 cuda 아님(CPU 학습)" else ""))
  quit(status = 0L)
}

if (identical(MODE, "finalize")) {
  q <- .rd_json(file.path(WD, "q50.json")); rs <- .rd_json(file.path(WD, "rx0s.json")); r <- .rd_json(file.path(WD, "rx0.json"))
  g <- .rd_json(argv("gate", file.path(WD, "gpu_gate.json")))
  rdl <- function(f) if (!is.null(f) && file.exists(f)) paste(sub("\r$", "", readLines(f, warn = FALSE)), collapse = "|") else NA_character_
  fps <- rdl(argv("fp-start")); fpe <- rdl(argv("fp-end"))
  mem_s <- suppressWarnings(as.numeric(argv("mem-start", NA))); mem_e <- suppressWarnings(as.numeric(argv("mem-end", NA)))
  why <- character(0); add <- function(...) why <<- c(why, paste0(...))
  if (is.null(q)) add("분위 워밍(warm/q50.json) 기록 없음") else if (!isTRUE(q$ok)) add("분위 워밍 실패 — ", paste(unlist(q$fail), collapse = " · "))
  if (!is.null(q) && !identical(q$code_version, DTC$CODE_VERSION)) add("CODE_VERSION ", q$code_version %||% "?", " ≠ ", DTC$CODE_VERSION)
  if (is.null(rs)) add("재시드 워밍(warm/rx0s.json) 기록 없음") else if (!isTRUE(rs$ok)) add("재시드 워밍 실패 — ", paste(unlist(rs$fail), collapse = " · "))
  rx0s_rel <- DTC$rx0s_rel(ROOT)
  if (!is.null(rs) && (!identical(rs$engine$path, rx0s_rel) || !identical(rs$engine$md5, .md5(file.path(ROOT, rx0s_rel))))) add("워밍 뒤 재시드 엔진이 바뀌었거나 다른 파일이다")
  if (is.null(r)) add("RX0 평균 캐시 확인(warm/rx0.json) 기록 없음") else if (!isTRUE(r$ok)) add("RX0 평균 캐시 확인 실패 — ", paste(unlist(r$fail), collapse = " · "))
  if (is.na(fps) || is.na(fpe)) add("dnn_input 지문 기록 없음") else if (!identical(fps, fpe)) add("워밍 중 데이터 판본이 바뀌었다(dnn_input 지문 시작 ≠ 끝) — 다시 워밍")
  em <- c(setNames(lapply(DTC$RULES, function(x) .md5(file.path(ROOT, DTC$rel_engine(x)))), DTC$RULES), list(RX0S = .md5(file.path(ROOT, DTC$rx0s_rel(ROOT)))))
  if (!is.null(q) && !identical(q$engine$md5, em[["Q50"]])) add("워밍 뒤 engine_Q50.R 이 바뀌었다")
  ml <- argv("monitor-log"); n_warn <- if (!is.null(ml) && file.exists(ml)) length(grep("★경고", readLines(ml, warn = FALSE, encoding = "UTF-8"), fixed = TRUE)) else NA_integer_
  lg <- file.path(WD, "warm_q50.log")
  pc_log <- if (file.exists(lg)) utils::tail(grep("positive control", readLines(lg, warn = FALSE, encoding = "UTF-8"), value = TRUE, fixed = TRUE), 5L) else character(0)
  ok <- !length(why)
  S <- list(schema = "p2r05_warm_v1", status = if (ok) "ok" else "failed", why = as.list(why), round_id = ROUND, prereg_md5 = .md5(PR),
            started_at = q$started_at %||% NA_character_, finished_at = .now(), code_version = q$code_version %||% NA_character_, engines_md5 = em,
            ## ★cache_months = "완료/전체" 문자열(판정 구현 evaluate.R .p5_cache_months 가 읽는 형식 · 과제 계약 'cache_months 261/261') · 숫자 = cache_done · cache_total
            cache_dir = DTC$CACHE_DIR, cache_months = sprintf("%s/%s", format(q$warm_months %||% NA), format(q$sched_months %||% NA)),
            cache_done = q$warm_months %||% NA_integer_, cache_total = q$sched_months %||% NA_integer_, sched_months = q$sched_months %||% NA_integer_,
            cache_months_text = sprintf("%s/%s", format(q$warm_months %||% NA), format(q$sched_months %||% NA)),
            trained_months = q$trained %||% NA_integer_, cached_months = q$cached %||% NA_integer_,
            positive_control = list(pass = isTRUE(q$positive_control$pass), fields = q$positive_control$fields %||% list(), log = as.list(pc_log)),
            qpred = q$qpred, q50 = q,
            reseed = list(status = if (!is.null(rs) && isTRUE(rs$ok)) "ok" else "failed", engine = rs$engine, code_version = rs$code_version,
                          cache_months = sprintf("%s/%s", format(rs$warm_months %||% NA), format(rs$sched_months %||% NA)),
                          cache_done = rs$warm_months %||% NA_integer_, cache_total = rs$sched_months %||% NA_integer_, sched_months = rs$sched_months %||% NA_integer_,
                          cache_months_text = sprintf("%s/%s", format(rs$warm_months %||% NA), format(rs$sched_months %||% NA)),
                          trained = rs$trained, cached = rs$cached, devices = rs$devices, all_cuda = isTRUE(rs$all_cuda), minutes = rs$minutes, run_dir = rs$run_dir),
            rx0 = list(status = if (!is.null(r) && isTRUE(r$ok)) "ok" else "failed", engine = r$engine, sched_months = r$sched_months, warm_months = r$warm_months,
                       trained = r$trained, cached = r$cached, devices = r$devices, all_cuda = r$all_cuda, minutes = r$minutes),
            gpu = list(gate = g, memory_used_mib_start = mem_s, memory_used_mib_end = mem_e, alloc_conf = Sys.getenv("PYTORCH_CUDA_ALLOC_CONF", NA_character_)),
            dnn_input_fp = list(start = fps, end = fpe), lane = argv("lane", NA_character_), monitor_warnings = n_warn,
            note = "측정 직전 precheck.R --warm-check 가 이 센티널의 유효 · 신선(워밍 끝 dnn_input 지문 = 현재)을 단정한다 · measure.sh 가 results/warm_sentinel.json 으로 사본을 둔다")
  .wjson(S, SENT)
  cat(sprintf("[warm] %s 센티널 %s — %s · 분위 캐시 %s · 학습 %s · 재시드 캐시 %s · RX0 %s · GPU memory.used %s → %s MiB%s\n", .now(), .rel(SENT), S$status, S$cache_months_text,
              format(S$trained_months), S$reseed$cache_months_text, S$rx0$status, format(mem_s), format(mem_e), if (length(why)) paste0("\n  · ", paste(why, collapse = "\n  · ")) else ""))
  quit(status = if (ok) 0L else 1L)
}

stop("usage: warm_engine.R run <엔진> <꼬리표> | monitor <로그> [배수] | finalize --fp-start=… --fp-end=… --mem-start=… --mem-end=…")
