#!/usr/bin/env Rscript
# test_rawdata_source_priority.R — RAWDATA 원천 우선순위 정본과 그 **소비 전수** (2026-09-07)
#
# 도훈 지시: "퀀티와이즈 데이터가 있으면 최우선, 네이버는 최신 보충. 추후 퀀티와이즈가
#   업데이트되면 네이버 데이터를 퀀티 기준으로 바꿔라." + "퀀티 그대로 덮기".
#
# 왜 이 검사가 있나: rawdata.parquet 을 쓰는 writer 가 넷인데 넷이 **서로 다른 규칙**으로
#   승패를 정하고 있었다 — 하나는 날짜 무조건 교체, 하나는 incumbent 를 안 보는 값 갱신
#   (=역전), 둘은 `unique()` 가 첫 행을 남긴다는 구현 사실(=행 순서라는 우연). 한 곳만
#   고치면 다른 경로로 역전이 다시 들어온다. 그래서 이 파일은 리졸버만 재지 않고
#   **소비 지점 전수**를 재도출로 확인한다.
#
# 양방향: 양성(규칙대로 이긴다/진다) + 위반 주입(설정 부재·미등재 라벨·역전·순서 뒤집기).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m,
                                                     if (nzchar(why)) paste0(" - ", why) else "", "\n") }
fin <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rawdata_source_priority","pass":%d,"fail":%d,"total":%d}\n',
              PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L)
}
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DATA_DIR <- file.path(ROOT, "02_Infrastructure/data")
PRI_JSON <- file.path(ROOT, "06_Registry/rawdata_source_priority.json")
PROJECT_ROOT <- ROOT
Sys.unsetenv("QVEST_ALLOW_BASIS_REGRESSION")
suppressWarnings(source(file.path(DATA_DIR, "rawdata_source_priority.R")))

## ── A. 정본 위치와 계약 ──────────────────────────────────────────────────────
cat("=== A. 우선순위 정본 ===\n")
if (file.exists(PRI_JSON)) ok("A1 06_Registry/rawdata_source_priority.json 존재") else {
  ng("A1 정본 부재"); fin() }
cfg <- tryCatch(rawdata_priority_config(reload = TRUE), error = function(e) e)
if (inherits(cfg, "error")) { ng("A2 정본 로드 실패", conditionMessage(cfg)); fin() }
if (identical(as.character(cfg$config_path), PRI_JSON))
  ok("A2 리졸버가 그 파일을 읽는다 (경로 재도출 일치)") else
  ng("A2 리졸버가 다른 파일을 읽는다", as.character(cfg$config_path))

r <- rawdata_source_rank(c("quantiwise", "quantiwise_update", "naver"))
if (all(is.finite(r))) ok("A3 세 원천이 모두 등재돼 있다") else ng("A3 미등재 원천 존재")
if (max(r[1:2]) < r[3])
  ok(sprintf("A4 퀀티 계열(%s) < naver(%s) — lower_wins 에서 퀀티가 이긴다",
             paste(r[1:2], collapse = "/"), r[3])) else
  ng("A4 퀀티가 naver 를 못 이긴다 — 도훈 지시와 반대")

## 설정 부재 = stop (조용한 기본값 없음)
bad <- tryCatch({ rawdata_priority_config(path = file.path(tempdir(), "nope_pri.json")); NULL },
                error = function(e) conditionMessage(e))
if (!is.null(bad) && grepl("부재", bad, fixed = TRUE)) ok("A5 설정 부재 = stop") else
  ng("A5 설정 부재가 통과했다", bad %||% "(정지 안 함)")

## 계약 위반 주입 — 동률 rank / 미지원 semantics / 키 결손
inj <- function(mut) {
  j <- jsonlite::fromJSON(PRI_JSON, simplifyVector = TRUE)
  j <- mut(j)
  p <- file.path(tempdir(), sprintf("pri_inj_%d.json", sample.int(1e6, 1)))
  writeLines(jsonlite::toJSON(j, auto_unbox = TRUE, pretty = TRUE, na = "null"), p, useBytes = TRUE)
  tryCatch({ rawdata_priority_config(path = p, reload = TRUE); NULL },
           error = function(e) conditionMessage(e))
}
m <- inj(function(j) { j$sources$rank[j$sources$source == "naver"] <-
                         j$sources$rank[j$sources$source == "quantiwise"]; j })
if (!is.null(m) && grepl("동률", m, fixed = TRUE)) ok("A6 동률 rank = stop (순서가 승패를 정하는 것 차단)") else
  ng("A6 동률 rank 가 통과했다", m %||% "(정지 안 함)")
m <- inj(function(j) { j$rank_semantics <- "higher_wins"; j })
if (!is.null(m) && grepl("rank_semantics", m, fixed = TRUE))
  ok("A7 미지원 semantics = stop (선언만 바꾸면 판정이 뒤집힌다)") else
  ng("A7 semantics 변조가 통과했다", m %||% "(정지 안 함)")
m <- inj(function(j) { j$on_na_source <- NULL; j })
if (!is.null(m) && grepl("결손", m, fixed = TRUE)) ok("A8 키 결손 = stop") else
  ng("A8 키 결손이 통과했다", m %||% "(정지 안 함)")

## ── B. 판정 — 양성 + 역전 ────────────────────────────────────────────────────
cat("=== B. 판정 ===\n")
d <- rawdata_priority_decide(c("naver", "quantiwise"), "quantiwise_update",
                             cfg = cfg, has_incumbent = TRUE)
if (all(d$decision == "incoming_wins")) ok("B1 quantiwise_update 가 naver·quantiwise 를 덮는다(정상 경로)") else
  ng("B1 퀀티 덮기가 허용되지 않는다", paste(d$decision, collapse = ","))
d <- rawdata_priority_decide("quantiwise", "naver", cfg = cfg, has_incumbent = TRUE)
if (identical(d$decision, "incumbent_wins") && identical(d$allow, FALSE))
  ok("B2 naver 는 quantiwise 를 못 덮는다 (역전 차단)") else
  ng("B2 역전이 통과했다", paste(d$decision, d$allow))
d <- rawdata_priority_decide("naver", "naver", cfg = cfg, has_incumbent = TRUE)
if (identical(d$decision, "same_source")) ok("B3 같은 원천 재수집은 갱신된다") else ng("B3 same_source 오판")
d <- rawdata_priority_decide(NA_character_, "naver", cfg = cfg, has_incumbent = FALSE)
if (identical(d$decision, "no_incumbent") && isTRUE(d$allow))
  ok("B4 빈 자리(신규 append)는 겨룰 상대가 없다 — 통과") else ng("B4 신규 append 가 막혔다")

## ★길이 0 — 전량 신규 append(매칭 0) 는 naver 일상 전진의 정상 경로다.
##   max(0, 1)=1 로 잡으면 0행이 1행으로 늘고, 호출자의 `hit[!allow]` 가
##   integer(0)[TRUE] = NA 로 번져 set(i = NA) 가 된다 — 실사고 형태로 잰다.
d0 <- rawdata_priority_decide(character(0), "naver", cfg = cfg, has_incumbent = logical(0))
if (nrow(d0) == 0L) ok("B4b incumbent 0행이면 판정도 0행 (스칼라 재활용으로 늘어나지 않는다)") else
  ng("B4b 0행이 늘어났다", sprintf("nrow=%d", nrow(d0)))

## 결정 불가 = stop (스킵이 아니다)
e1 <- tryCatch({ rawdata_priority_decide("bloomberg", "naver", cfg = cfg, has_incumbent = TRUE); NULL },
               error = function(e) conditionMessage(e))
if (!is.null(e1) && grepl("미등재", e1, fixed = TRUE))
  ok("B5 미등재 라벨 = stop (조용한 최하위 배정 금지)") else ng("B5 미등재가 통과했다", e1 %||% "")
e2 <- tryCatch({ rawdata_priority_decide(NA_character_, "naver", cfg = cfg, has_incumbent = TRUE); NULL },
               error = function(e) conditionMessage(e))
if (!is.null(e2) && grepl("NA", e2, fixed = TRUE))
  ok("B6 행은 있는데 라벨 NA = stop ('없다'와 '모른다'를 구분한다)") else
  ng("B6 라벨 NA 가 통과했다", e2 %||% "")

## 우회 env — 이름조차 설정에서 온다
onm <- as.character(cfg$override_env)
if (identical(onm, "QVEST_ALLOW_BASIS_REGRESSION"))
  ok("B7 override_env 이름이 정본에 선언돼 있다 (구 역행차단 env 재정의)") else
  ng("B7 override_env 선언 이상", onm)
do.call(Sys.setenv, setNames(list("1"), onm))
d <- rawdata_priority_decide("quantiwise", "naver", cfg = cfg, has_incumbent = TRUE)
Sys.unsetenv(onm)
if (identical(d$decision, "override_inversion") && isTRUE(d$allow))
  ok("B8 명시 우회로만 역전이 통과하고 라벨이 남는다") else ng("B8 우회가 안 먹거나 라벨이 없다")

## ── C. dedup — 순서가 아니라 rank 가 승패를 정한다 ───────────────────────────
cat("=== C. 중복 해소 ===\n")
dt <- data.table(Date = as.Date(c("2026-08-31", "2026-08-31")), Ticker = c("A1", "A1"),
                 Close = c(100, 500), source = c("naver", "quantiwise_update"))
r1 <- rawdata_priority_dedup(dt, cfg = cfg)
r2 <- rawdata_priority_dedup(dt[c(2, 1)], cfg = cfg)
if (identical(r1$dt$source, "quantiwise_update")) ok("C1 승자는 rank 상위(quantiwise_update)") else
  ng("C1 승자 오판", paste(r1$dt$source))
if (identical(r1$dt$Close, r2$dt$Close))
  ok("C2 행 순서를 뒤집어도 같은 승자 — unique() 의 '첫 행' 에 얹지 않는다") else
  ng("C2 순서에 따라 승자가 바뀐다 (구판 병 재발)")
if (nrow(r1$dropped_by) == 1L && r1$dropped_by$dropped == "naver")
  ok("C3 무엇이 무엇에게 졌는지 남는다 (조용한 통과 없음)") else ng("C3 탈락 기록 부재")
## 위반 주입 — 미등재 라벨이 섞이면 stop
dt2 <- copy(dt); dt2[1, source := "bloomberg"]
e3 <- tryCatch({ rawdata_priority_dedup(dt2, cfg = cfg); NULL }, error = function(e) conditionMessage(e))
if (!is.null(e3) && grepl("미등재", e3, fixed = TRUE)) ok("C4 dedup 도 미등재 라벨에서 정지") else
  ng("C4 dedup 이 미등재를 삼켰다", e3 %||% "")

## ── D. 소비 지점 전수 — 재도출로 편입 드리프트를 막는다 ──────────────────────
cat("=== D. 소비 지점 전수 (재도출) ===\n")
## rawdata 를 쓰는 파일을 **긁어서** 구한다 (정본의 목록을 그대로 되읽지 않는다)
rfiles <- list.files(DATA_DIR, pattern = "[.]R$", full.names = TRUE)
is_writer <- function(p) {
  x <- readLines(p, encoding = "UTF-8", warn = FALSE)
  any(grepl("(write_parquet|qvest_atomic_write_parquet|file[.]rename)\\(.*(RAWDATA_CACHE|[.]rawdata_out|raw_path)", x))
}
does_merge <- function(p) {
  x <- readLines(p, encoding = "UTF-8", warn = FALSE)
  any(grepl("rbind(list)?\\(", x))
}
writers <- rfiles[vapply(rfiles, is_writer, logical(1))]
mergers <- writers[vapply(writers, does_merge, logical(1))]
rel <- function(p) sub(paste0("^", ROOT, "/"), "", gsub("\\\\", "/", normalizePath(p, winslash = "/")))
cat(sprintf("  재도출: rawdata writer %d개 · 그중 행결합 %d개\n", length(writers), length(mergers)))
if (length(mergers) >= 4L) ok(sprintf("D0 병합 writer 재도출 %d개", length(mergers))) else
  ng("D0 병합 writer 를 못 찾았다 — 재도출 패턴 점검 필요")

declared_c <- as.character(cfg$consumers)
declared_n <- as.character(as.data.table(cfg$non_merging_writers)$path)
undeclared <- setdiff(vapply(mergers, rel, ""), character(0))
undeclared <- undeclared[!vapply(undeclared, function(p)
  any(startsWith(declared_c, p)) || p %in% declared_n, logical(1))]
if (!length(undeclared))
  ok("D1 행결합 writer 전부가 정본의 consumers 에 등재돼 있다 (편입 드리프트 0)") else
  ng("D1 미등재 병합 writer", paste(undeclared, collapse = ", "))
nonmerge_missing <- setdiff(vapply(setdiff(writers, mergers), rel, ""), declared_n)
if (!length(nonmerge_missing))
  ok("D2 비결합 writer 도 전부 정본에 사유와 함께 분류돼 있다") else
  ng("D2 미분류 writer", paste(nonmerge_missing, collapse = ", "))

## consumers 에 적힌 파일이 실제로 리졸버를 부르는가 (진술이 아니라 재도출)
bad_c <- character(0)
for (cline in declared_c) {
  p <- sub("[ ].*$", "", cline)
  if (!grepl("[.]R$", p)) next
  fp <- file.path(ROOT, p)
  if (!file.exists(fp)) { bad_c <- c(bad_c, paste0(p, "(부재)")); next }
  x <- readLines(fp, encoding = "UTF-8", warn = FALSE)
  if (!any(grepl("rawdata_priority_", x, fixed = TRUE))) bad_c <- c(bad_c, paste0(p, "(미호출)"))
}
if (!length(bad_c)) ok(sprintf("D3 등재 consumer %d개가 전부 리졸버를 실제로 호출한다",
                               sum(grepl("[.]R", declared_c)))) else
  ng("D3 등재만 되고 안 부르는 consumer", paste(bad_c, collapse = ", "))

## D4 — **함수 안에서** 부르는가 (AST 재도출). grep 은 주석·죽은 코드도 초록으로 만든다.
calls_in_fn <- function(path, fn_name) {
  ex <- parse(path); found <- character(0)
  walk <- function(e) {
    if (is.call(e)) { h <- e[[1]]; if (is.name(h)) found <<- c(found, as.character(h)) }
    if (is.recursive(e)) for (i in seq_along(e)) if (!is.null(e[[i]])) try(walk(e[[i]]), silent = TRUE)
  }
  for (i in seq_along(ex)) {
    e <- ex[[i]]
    if (is.call(e) && length(e) >= 3 && as.character(e[[1]]) %in% c("<-", "=") &&
        identical(as.character(e[[2]]), fn_name)) walk(e[[3]])
  }
  unique(found)
}
NEED <- list(
  list(f = "incremental_update_file.R",  fn = "incremental_ohlcvs",
       need = c("rawdata_priority_decide", "rawdata_priority_dedup", "seam_detect_changed")),
  list(f = "naver_data_collector.R",     fn = ".naver_apply_update",
       need = "rawdata_priority_decide"),
  list(f = "naver_data_collector.R",     fn = "naver_backfill_range",
       need = "rawdata_priority_decide"),
  list(f = "krx_build_rawdata.R",        fn = "krx_merge_rawdata",
       need = "rawdata_priority_dedup"),
  list(f = "incremental_cache_update.R", fn = "incremental_rawdata",
       need = "rawdata_priority_dedup"))
bad4 <- character(0)
for (k in seq_along(NEED)) {
  it <- NEED[[k]]
  cl <- tryCatch(calls_in_fn(file.path(DATA_DIR, it$f), it$fn), error = function(e) character(0))
  ms <- setdiff(it$need, cl)
  if (length(ms)) bad4 <- c(bad4, sprintf("%s::%s{%s}", it$f, it$fn, paste(ms, collapse = ",")))
}
if (!length(bad4))
  ok(sprintf("D4 병합 함수 %d개가 AST 상에서 실제로 리졸버를 호출한다 (주석·죽은 코드 아님)",
             length(NEED))) else
  ng("D4 함수 안에서 안 부른다", paste(bad4, collapse = " | "))

## ── E. naver 경로 — 역전이 실제로 막히는가 (실코드 함수를 꺼내 실행) ─────────
cat("=== E. naver 병합 함수 실측 ===\n")
NAV <- file.path(DATA_DIR, "naver_data_collector.R")
env <- new.env(parent = globalenv())
assign("NAVER_VALUE_COLS", c("Open", "High", "Low", "Close", "Vol", "Size", "Ret"), envir = env)
assign("DATA_DIR", DATA_DIR, envir = env)
got <- FALSE
for (ex in as.list(parse(NAV))) {
  if (is.call(ex) && length(ex) == 3L && identical(as.character(ex[[1]]), "<-") &&
      identical(as.character(ex[[2]]), ".naver_apply_update")) { eval(ex, envir = env); got <- TRUE }
}
if (got) ok("E0 .naver_apply_update 를 소스에서 꺼냈다 (재구현 아님)") else {
  ng("E0 .naver_apply_update 를 못 찾았다 — 표적 상실"); fin() }
apply_fn <- get(".naver_apply_update", envir = env)

raw0 <- data.table(Date = as.Date(c("2026-08-28", "2026-08-31")), Ticker = c("A1", "A1"),
                   Close = c(5000, 1000), Ret = c(0, 0), K200 = c(1, 1),
                   source = c("quantiwise", "naver"))
upd0 <- data.table(Date = as.Date(c("2026-08-28", "2026-08-31")), Ticker = c("A1", "A1"),
                   Close = c(77, 88), Ret = c(0.1, 0.2))
a <- apply_fn(raw0, upd0, cfg_pri = cfg)
if (a$n_skipped == 1L) ok("E1 퀀티 행은 naver 갱신에서 스킵된다") else
  ng("E1 스킵이 안 일어났다", sprintf("n_skipped=%d", a$n_skipped))
if (a$dt[Date == as.Date("2026-08-28")]$Close == 5000)
  ok("E2 퀀티 값이 보존됐다 (정본이 보충 레인에 지지 않는다)") else
  ng("E2 퀀티 값이 덮였다 — 역전 재발")
if (a$dt[Date == as.Date("2026-08-28")]$source == "quantiwise")
  ok("E3 라벨도 안 바뀐다 (구판은 값과 함께 source 를 naver 로 찍었다)") else
  ng("E3 라벨이 naver 로 바뀌었다")
if (a$dt[Date == as.Date("2026-08-31")]$Close == 88 && a$n_updated == 1L)
  ok("E4 naver 자기 구간은 정상 갱신된다 (과잉 차단 없음)") else ng("E4 정상 갱신이 막혔다")
if (a$dt[Date == as.Date("2026-08-28")]$K200 == 1)
  ok("E5 이 writer 가 안 만드는 축(K200)은 그대로 승계된다") else ng("E5 승계 축 소실")
## 위반 주입 — 우회를 켜면 덮인다(그리고 그때만 덮인다)
do.call(Sys.setenv, setNames(list("1"), onm))
a2 <- apply_fn(raw0, upd0, cfg_pri = cfg)
Sys.unsetenv(onm)
if (a2$n_skipped == 0L && a2$dt[Date == as.Date("2026-08-28")]$Close == 77)
  ok("E6 명시 우회에서만 덮인다 — E1~E3 이 죽은 검사가 아니다") else
  ng("E6 우회해도 안 덮인다 — 양성 대조 실패")
## ★전량 신규 append (매칭 0) — 일상 전진 경로가 색인 사고 없이 도는가
raw_fwd <- data.table(Date = as.Date("2026-08-28"), Ticker = "A1", Close = 5000,
                      Ret = 0, K200 = 1, source = "quantiwise")
upd_fwd <- data.table(Date = as.Date("2026-09-01"), Ticker = c("A1", "A2"),
                      Close = c(101, 202), Ret = c(0.01, 0.02))
a3 <- tryCatch(apply_fn(raw_fwd, upd_fwd, cfg_pri = cfg), error = function(e) conditionMessage(e))
if (is.list(a3) && a3$n_updated == 0L && a3$n_appended == 2L && a3$n_skipped == 0L &&
    nrow(a3$dt) == 3L && all(a3$dt[Date == as.Date("2026-09-01")]$source == "naver"))
  ok("E8 전량 신규 append 가 색인 사고 없이 돈다 (일상 전진 경로)") else
  ng("E8 전진 경로가 깨진다", if (is.character(a3)) a3 else
       sprintf("upd=%s add=%s skip=%s n=%s", a3$n_updated, a3$n_appended, a3$n_skipped, nrow(a3$dt)))

## source 열이 없으면 판정 축이 없다 = stop
raw_nolabel <- copy(raw0)[, source := NULL]
e4 <- tryCatch({ apply_fn(raw_nolabel, upd0, cfg_pri = cfg); NULL },
                error = function(e) conditionMessage(e))
if (!is.null(e4) && grepl("source", e4, fixed = TRUE))
  ok("E7 라벨 없는 패널은 덮지 않는다 (판정 축 부재 = stop)") else
  ng("E7 라벨 없이 덮었다", e4 %||% "")

fin()
