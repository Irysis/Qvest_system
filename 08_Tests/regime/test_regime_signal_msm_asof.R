# test_regime_signal_msm_asof.R — 국면 신호의 MSM as-of 입력 계약(소비자 쪽) 위반 주입 시험 (2026-11-06 신설 · 적대 검토 #3 · #21)
#
# 지키는 것 (결정 PIT-C1-MSM-PARAMS 안 A · MSM-ASOF-SWITCH-20261017 D1 A · D4 B):
#   02_Infrastructure/regime/regime_signal.R 의 MSM 로더 3종(.msm_asof_load · load_msm_signal · load_msm_daily)은
#   .cache/msm_asof_daily.parquet(연말 재적합 as-of 경로 · 생산자 msm_asof_update.R)만 읽고, 아래 셋이면 stop 한다(폴백 없음):
#     ① 파일 없음  ② 추정기 표식(스키마 메타 msm_estimator) ≠ asof_yearly:v1  ③ 벤치 최신일보다 낡음(옵션 경로일 땐 생략 — 설계).
#   구판은 RData 분기 · 빈 표 반환(→ 일간 90/50 재척도) · LOCF 로 낡음을 숨겨 전 표본 MLE 모수(C1) 값을 조용히 되살렸다.
#   통합 신호는 as-of 첫 달/첫날 전 행을 자르고(D1 A) 행 열 + 파일 속성 msm_estimator 로 표식하며, Gate M 은 그 표식이
#   parquet 왕복 뒤 asof_yearly:v1 인지 본다. ★Gate M 판정 정본 = 02_Infrastructure/ops/gate_msm_asof.sh(같은 날 run_pg2_rebalance_full.sh
#   의 인라인 R 판독식이 이 스크립트 호출로 바뀌었다 — 예약 러너 run_nolayer4_monthly.sh [0b] 와 한 벌). 그래서 ⑧ 은 판독식을
#   재현하지 않고 그 스크립트를 그대로 돌린다(관문 자체의 위반 주입 · 돌연변이 · 배선 = 08_Tests/ops/test_gate_msm_asof.sh).
#
# ★양방향(pit.md: 양성 대조 없는 계기는 방어선으로 세지 않는다):
#   양성 대조(정상 입력은 통과)와 위반 주입(없음 · 다른 표식 · 표식 없음 · 낡음 · 표식 없는/혼합 parquet)이 빨개지는가에 더해,
#   설치본 사본의 돌연변이(소스 텍스트 치환 — deparse 아님 · 치환 성사 단정 · 사본 생존 단정)가 해당 단정을 빨갛게 하는지 잰다.
#   ★낡음 분기는 options(qvest.msm_asof_path) 를 켜면 꺼지므로 ③ 은 옵션을 끄고 CACHE_DIR 을 tempdir 로 돌려 잰다.
#   ★죽은 계측의 rc 가 기대값과 겹치지 않게: 관문 OK = rc 0 ∧ 'OK ' 줄 · BAD = rc 1 ∧ 'BAD ' 줄 ∧ [marker] 태그만. 그 밖 = DEAD(실패).
#
# 축:
#   ① 파일 없음 → stop(메시지에 경로) — 옵션 경로 · CACHE_DIR 기본 경로 · 로더 3종
#   ② 메타 msm_estimator 'other' → stop(로더 3종) · 표식 없는 파일(구 C1 캐시 꼴) → stop
#   ③ 벤치 최신일 > as-of 최신일(옵션 미설정 · CACHE_DIR 경로) → stop(로더 3종) · 같은 날 · 앞선 벤치 = 통과(양성 대조)
#   ③b 옵션 미설정 · CACHE_DIR 에 벤치 없음 → stop(fail-closed · 11-06 적대 검증 — 구판은 낡음 검사를 조용히 건너뛰었다)
#   ①′ 메시지에 로더 고유 문구('MSM as-of 경로 없음') — arrow IOError 도 경로를 담으므로 경로만으로는 명시 가드를 못 가린다(11-06)
#   ④ 정상 → 반환 열 · Date 정렬(역순 기록 입력) · 값 · 결측 행 제외 · 속성 msm_estimator
#   ⑤ 월 집계 = 달력 월평균(독립 계산 대조) · Date = 그 달 자료의 최대일(달력 말일 아님)
#   ⑥ parquet 왕복(write_parquet → read_parquet)에서 .msm_stamp 의 속성 · 열 생존(+ 표식 없는 대조 = 속성 없음)
#   ⑦ classify_regime_basis — MSM ≥0.9 + 점수 <45 → msm_override · 점수만으로 같은 범주 → score (경계 · NA 포함)
#   ⑧ Gate M(gate_msm_asof.sh 그대로 · 신선도는 맞춘 합성 루트) — 표식 없는 · 혼합 · 정상 월간 parquet → BAD/BAD/OK
#        (BAD 사유 = [marker] 만) · 열만 · 속성만 = BAD [marker]
#   ⑨ D1 절단 · 빌드 표식 — 합성 3층(MSM 2004-01-02~ · FRED 2003-07~ · KTRI 2003-09~)으로 월 · 일 빌드를 실제로 돌린다:
#        첫 행 = as-of 첫 달/첫날 · 절단 전 LOCF 이월 보존 · 일간 평활은 절단 뒤 시작 · 표식 열/속성 · C11 키에 MSM 미혼입 ·
#        fw_* 없음 · Category_basis(단락 CRISIS = msm_override · 현금 0) · regime_current.json(regime_tag_basis · cash_pct)
#   ⑧×⑨ 설치본 빌드 산출(월 · 일) → 실제 Gate M 관문 OK(생산 표식 · avail_date · 일간 전진 = 관문 판정과 정합)
#   돌연변이(설치본 사본): M2 추정기 비교 삭제 → ② red · M3 낡음 비교 삭제 → ③ red · M1m 월 절단 삭제 → ⑨월 red ·
#        M1d 일 절단 삭제 → ⑨일 red (M2 ↔ M3 서로의 단정은 초록 = 단정이 그 비교만 잰다) ·
#        M4 벤치 부재 정지 삭제 → ③b red(③ 은 초록) · M5 파일 없음 명시 가드 삭제 → ①′ red(정지 자체는 arrow 가 대신 한다)
#
# 쓰기: tempdir() 만(합성 .cache · 합성 루트 · 돌연변이 사본). 운영 .cache 는 읽지도 쓰지도 않는다.
#   (관문 스크립트는 자기 R 임시 파일을 Git Bash /tmp 에 mktemp 했다가 trap 으로 지운다 — 관문 설계 그대로)
#   읽기 전용 = 설치본 regime_signal.R · fred_availability.R · gate_msm_asof.sh · run_pg2_rebalance_full.sh.
#   C11 규칙 키는 시험용 고정값으로 덮는다(fred_avail_rules_meta 대역) — 운영 규칙 키 문자열에 기대지 않는다.
# ★Rscript 는 이 파일을 콘솔 입력처럼 한 줄씩 읽는다 — parse(text = NULL) · readline · scan(file = "") 처럼 콘솔을 읽는
#   호출은 뒤 줄을 삼켜 시험을 조용히 망가뜨린다(초판에서 실제로 겪음). 그런 호출을 두지 말 것.
# 실행: Rscript 08_Tests/regime/test_regime_signal_msm_asof.R

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite); library(arrow) }))

.self <- tryCatch({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SRC_SIGNAL <- file.path(ROOT, "02_Infrastructure/regime/regime_signal.R")
SRC_PG2    <- file.path(ROOT, "02_Infrastructure/ops/run_pg2_rebalance_full.sh")
GATE       <- file.path(ROOT, "02_Infrastructure/ops/gate_msm_asof.sh")
HELPER     <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
EST        <- "asof_yearly:v1"            # 계약 토큰(msm_asof.R::MSMA_ESTIMATOR · gate_msm_asof.sh 와 같은 값)
C11_STUB   <- "c11_avail:TEST:0000beef"   # 시험용 C11 규칙 키(운영 규칙 키 문자열에 기대지 않는다)

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
skip <- function(axis, reason, missing) {
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat(sprintf("  SKIP  %s — %s [%s]\n", axis, reason, missing))
}
note <- function(msg) cat(sprintf("  NOTE  %s\n", msg))
quiet <- function(expr) { v <- NULL; invisible(capture.output(v <- suppressWarnings(force(expr)))); v }
# 구역 실행 — 예기치 못한 오류는 그 구역 FAIL 1건으로 남기고 다음 구역으로 간다(요약 JSON 이 끊기지 않게 · 오류 ≠ 통과)
section <- function(title, expr) {
  cat(sprintf("\n=== %s ===\n", title))
  tryCatch(force(expr), error = function(e) chk(paste(title, "— 구역 실행"), FALSE, paste("오류:", conditionMessage(e))))
  invisible(NULL)
}
mkd <- function(...) { p <- file.path(...); dir.create(p, recursive = TRUE, showWarnings = FALSE); p }
# LF 로 쓴다(Windows 텍스트 모드 CRLF 회피) · 바이트 그대로(UTF-8)
write_lf <- function(lines, path) { con <- file(path, open = "wb"); on.exit(close(con)); writeLines(lines, con, sep = "\n", useBytes = TRUE) }
count_fixed <- function(txt, pat) { m <- gregexpr(pat, txt, fixed = TRUE)[[1]]; if (m[1] == -1L) 0L else length(m) }

TD <- gsub("\\\\", "/", file.path(tempdir(), sprintf("msmasof_%d_%d", Sys.getpid(), as.integer(runif(1, 1e6, 9e6)))))
invisible(mkd(TD))

# 전역 = 격리 경로 (config.R 을 source 하지 않는다 — 운영 경로가 섞이지 않게. regime_signal.R 은 PROJECT_ROOT 가 있으면 config 를 안 부른다)
PROJECT_ROOT <- mkd(TD, "root"); FUNC_PATH <- file.path(ROOT, "02_Infrastructure")
RESEARCH_OUTPUT <- mkd(TD, "research"); CACHE_DIR <- mkd(TD, "cache_none")
options(qvest.msm_asof_path = NULL, fred_avail.root = PROJECT_ROOT, fred_avail.data_root = TD)

NEED_FUN <- c(".msm_asof_path", ".msm_asof_load", "load_msm_signal", "load_msm_daily", ".msm_stamp", "classify_regime_basis",
              "classify_regime_category", "build_regime_signal_table", "build_regime_signal_table_daily")
has_funs <- function(E) !is.null(E) && all(vapply(NEED_FUN, exists, logical(1), envir = E, inherits = FALSE))
# 설치본(또는 돌연변이 사본)을 새 환경에 sys.source — 함수의 자유 변수(CACHE_DIR 등)는 전역(격리 경로)에서 찾는다
load_signal <- function(path) {
  E <- new.env(parent = globalenv())
  err <- tryCatch({ quiet(sys.source(path, envir = E, keep.source = FALSE)); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(err)) { cat("  (적재 오류) ", err, "\n"); return(NULL) }
  E
}
EI <- NULL

section("전제: 설치본 · 도우미 · 격리", {
  for (p in c(SRC_SIGNAL, SRC_PG2, GATE, HELPER)) chk(paste("존재", basename(p)), file.exists(p), p)
  quiet(source(HELPER))   # fred_kr_calendar 등(월 빌드의 avail_date) — 전역에 둔다(.rs_need_fred_avail 가 찾는다)
  # C11 규칙 키 대역: 운영 06_Registry 규칙 파일을 읽지 않고, MSM 표식이 C11 키에 섞이지 않는지 고정값으로 잰다
  fred_avail_rules_meta <- function(rules_path = NULL) list(version = "TEST", md5 = "0000beef", path = NA_character_, regime_key = C11_STUB)
  EI <- load_signal(SRC_SIGNAL)
  chk("설치본 regime_signal.R 적재 · 로더/표식/근거/빌더 함수 존재 · 추정기 상수 = asof_yearly:v1",
      has_funs(EI) && identical(EI$MSM_ESTIMATOR_EXPECTED, EST))
  chk("격리: CACHE_DIR · PROJECT_ROOT · RESEARCH_OUTPUT · 기본 as-of 경로가 tempdir",
      all(startsWith(c(CACHE_DIR, PROJECT_ROOT, RESEARCH_OUTPUT), TD)) && startsWith(EI$.msm_asof_path(), TD), EI$.msm_asof_path())
})

# ─── 합성 입력 ─────────────────────────────────────────────────────────────────────────────────────
bdays <- function(from, to) { d <- seq(as.Date(from), as.Date(to), by = "day"); d[!(as.POSIXlt(d)$wday %in% c(0L, 6L))] }
ASOF_D <- bdays("2004-01-02", "2004-06-30")            # as-of 경로 = 2004-01-02 첫날(운영과 같은 시작) ~ 06-30
ASOF_FIRST <- min(ASOF_D); ASOF_MAX <- max(ASOF_D); FIRST_YM <- format(ASOF_FIRST, "%Y-%m")
.i <- seq_along(ASOF_D); .mo <- format(ASOF_D, "%m")
prob <- 0.05 + 0.09 * ((.i * 7L) %% 10L) / 10                                    # 평시 0.05~0.131(달 안에서 변한다 — 월평균 ≠ 마지막 값)
prob[.mo == "03"] <- 0.93 + 0.04 * ((.i[.mo == "03"] * 3L) %% 5L) / 5            # 위기 달(월평균 ≥ 0.9 → 단락 CRISIS)
prob[.mo == "04"] <- 0.72 + 0.05 * ((.i[.mo == "04"] * 3L) %% 5L) / 5            # 0.7~0.9(점수 NEUTRAL 이면 CAUTION 승격)
prob[ASOF_D >= as.Date("2004-06-28")] <- 0.95                                     # 마지막 날들 = 단락 CRISIS(regime_current 근거 = msm_override)
NA_DAY <- as.Date("2004-02-16"); prob[ASOF_D == NA_DAY] <- NA_real_               # 결측 행(로더가 버린다)
RAW <- data.table(Date = ASOF_D, Price = 100 + .i, Vol_Est = 0.01, Crisis_Prob = prob,
                  msm_fit_date = as.Date("2003-12-30"), guard_action = "mle")     # 생산자 msma_path 의 열 꼴
REF <- RAW[!is.na(Crisis_Prob)]                                                   # 로더가 돌려줄 것(결측 행 제외 · 날짜순)
BENCH_STALE_MAX <- as.Date("2004-07-01")

# 생산자(msm_asof.R::msma_update)와 같은 방식으로 쓴다: R 속성 + 스키마 최상위 메타 msm_estimator. est = NULL = 표식 없음(구 C1 캐시 꼴)
write_asof <- function(path, est = EST) {
  P <- RAW[order(-as.integer(Date))]                    # 역순 기록 — 로더의 정렬을 잰다
  if (!is.null(est)) setattr(P, "msm_estimator", est)
  tb <- arrow::arrow_table(P)
  if (!is.null(est)) tb$metadata$msm_estimator <- est
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(tb, path)
  invisible(path)
}
write_bench <- function(dir, dates) arrow::write_parquet(data.table(Date = as.Date(dates), Close = 100), file.path(dir, "benchmark.parquet"))

P_OK <- P_OTHER <- P_NOMETA <- P_MISS <- C_EMPTY <- C_STALE <- C_SAME <- C_AHEAD <- C_NOBENCH <- NA_character_
section("합성 입력(as-of 경로 · 벤치) — 고정물 자체 점검", {
  P_OK     <- write_asof(file.path(TD, "asof", "ok.parquet"))
  P_OTHER  <- write_asof(file.path(TD, "asof", "est_x.parquet"), est = "other")   # 파일명에 'other' 를 넣지 않는다(메시지 대조 오염 방지)
  P_NOMETA <- write_asof(file.path(TD, "asof", "nometa.parquet"), est = NULL)
  P_MISS   <- file.path(TD, "asof", "absent", "msm_asof_daily.parquet")
  C_EMPTY  <- mkd(TD, "cache_empty")
  C_STALE  <- mkd(TD, "cache_stale");   write_asof(file.path(C_STALE, "msm_asof_daily.parquet"));   write_bench(C_STALE, c(ASOF_D, BENCH_STALE_MAX))
  C_SAME   <- mkd(TD, "cache_same");    write_asof(file.path(C_SAME, "msm_asof_daily.parquet"));    write_bench(C_SAME, ASOF_D)
  C_AHEAD  <- mkd(TD, "cache_ahead");   write_asof(file.path(C_AHEAD, "msm_asof_daily.parquet"));   write_bench(C_AHEAD, ASOF_D[ASOF_D < ASOF_MAX])
  C_NOBENCH <- mkd(TD, "cache_nobench"); write_asof(file.path(C_NOBENCH, "msm_asof_daily.parquet"))
  meta <- function(p) arrow::read_parquet(p, as_data_frame = FALSE)$metadata$msm_estimator
  chk("고정물: 정상 · 'other' · 표식 없음 파일의 스키마 메타 = asof_yearly:v1 · other · 없음(생산자 꼴)",
      identical(meta(P_OK), EST) && identical(meta(P_OTHER), "other") && is.null(meta(P_NOMETA)))
  chk("고정물: 낡음 벤치 최신일 > as-of 최신일 · 같은 날 · 앞선 벤치 · 없는 파일",
      max(arrow::read_parquet(file.path(C_STALE, "benchmark.parquet"))$Date) > ASOF_MAX &&
        max(arrow::read_parquet(file.path(C_SAME, "benchmark.parquet"))$Date) == ASOF_MAX &&
        max(arrow::read_parquet(file.path(C_AHEAD, "benchmark.parquet"))$Date) < ASOF_MAX && !file.exists(P_MISS))
})

# ─── 로더 호출 도구 ────────────────────────────────────────────────────────────────────────────────
LOADERS <- c(".msm_asof_load", "load_msm_signal", "load_msm_daily")
# opt = NULL 이면 옵션을 지운다(→ 낡음 검사 켜짐 · 경로 = CACHE_DIR 기본). cache = 그 호출 동안의 CACHE_DIR
call_loader <- function(E, fn, opt = NULL, cache = NULL) {
  old_opt <- options(qvest.msm_asof_path = opt); old_cache <- CACHE_DIR
  if (!is.null(cache)) CACHE_DIR <<- cache
  on.exit({ options(old_opt); CACHE_DIR <<- old_cache }, add = TRUE)
  tryCatch({ f <- get(fn, envir = E, inherits = FALSE); list(ok = TRUE, value = quiet(f()), msg = "") },
           error = function(e) list(ok = FALSE, value = NULL, msg = conditionMessage(e)))
}
probe <- function(E, opt = NULL, cache = NULL) lapply(setNames(LOADERS, LOADERS), function(fn) call_loader(E, fn, opt = opt, cache = cache))
# stop 했고 메시지에 needles 가 전부 있다(다른 이유의 오류를 '정지'로 세지 않게)
stopped_with <- function(res, needles) vapply(res, function(x) !isTRUE(x$ok) && all(vapply(needles, grepl, logical(1), x = x$msg, fixed = TRUE)), logical(1))
went_through <- function(res) vapply(res, function(x) isTRUE(x$ok), logical(1))
fmt <- function(res) paste(sprintf("%s:%s", names(res), vapply(res, function(x) if (isTRUE(x$ok)) "통과" else substr(x$msg, 1, 140), "")), collapse = " | ")

MISS_MSG <- "MSM as-of 경로 없음"   # 로더 고유 문구(regime_signal.R .msm_asof_load) — arrow IOError 와 가른다
a1_missing <- function(E) all(stopped_with(probe(E, opt = P_MISS), c(MISS_MSG, P_MISS)))
a2_other <- function(E) all(stopped_with(probe(E, opt = P_OTHER), c("(other", EST, P_OTHER)))
a3_stale <- function(E) all(stopped_with(probe(E, cache = C_STALE), c(format(ASOF_MAX), format(BENCH_STALE_MAX))))
a3b_nobench <- function(E) all(stopped_with(probe(E, cache = C_NOBENCH), c("벤치 없음", file.path(C_NOBENCH, "benchmark.parquet"))))
a4_normal <- function(E) {
  r <- probe(E, opt = P_OK)
  okd <- function(x) { d <- x$value
    isTRUE(x$ok) && is.data.frame(d) && identical(names(d), c("Date", "MSM_Crisis_Prob")) && inherits(d$Date, "Date") &&
      nrow(d) == nrow(REF) && identical(as.integer(d$Date), as.integer(REF$Date)) &&
      isTRUE(all.equal(as.numeric(d$MSM_Crisis_Prob), REF$Crisis_Prob, tolerance = 1e-14)) && identical(attr(d, "msm_estimator"), EST) }
  okd(r[[".msm_asof_load"]]) && okd(r[["load_msm_daily"]]) && isTRUE(r[["load_msm_signal"]]$ok) &&
    identical(names(r[["load_msm_signal"]]$value), c("Date", "YM", "MSM_Crisis_Prob"))
}

section("① 파일 없음 → stop(메시지에 경로)", {
  r <- probe(EI, opt = P_MISS)
  chk("① 옵션 경로가 없는 파일 → 로더 3종 stop · 메시지에 로더 고유 문구 + 그 경로", a1_missing(EI), fmt(r))
  r <- probe(EI, cache = C_EMPTY)
  pdef <- file.path(C_EMPTY, "msm_asof_daily.parquet")
  chk("① 옵션 미설정 · CACHE_DIR 에 as-of 파일 없음 → 로더 3종 stop · 메시지에 로더 고유 문구 + 기본 경로(CACHE_DIR/msm_asof_daily.parquet)",
      all(stopped_with(r, c(MISS_MSG, pdef))), fmt(r))
})

section("② 추정기 표식 불일치 → stop", {
  r <- probe(EI, opt = P_OTHER)
  chk("② 메타 msm_estimator = 'other' → 로더 3종 stop(메시지 = other · 기대값 · 경로)", all(stopped_with(r, c("(other", EST, P_OTHER))), fmt(r))
  r <- probe(EI, opt = P_NOMETA)
  chk("② 표식 없는 파일(구 C1 캐시 꼴 · 메타 r 뿐) → 로더 3종 stop(메시지 = 기대값 · 경로)", all(stopped_with(r, c(EST, P_NOMETA))), fmt(r))
})

section("③ 낡음(벤치 최신일 > as-of 최신일 · 옵션 미설정 · CACHE_DIR 경로) → stop", {
  r <- probe(EI, cache = C_STALE)
  chk("③ 벤치 2004-07-01 > as-of 2004-06-30 → 로더 3종 stop(메시지에 두 날짜)", a3_stale(EI), fmt(r))
  r <- probe(EI, cache = C_SAME)
  chk("③ 양성 대조: 벤치 최신일 = as-of 최신일 → 로더 3종 통과", all(went_through(r)), fmt(r))
  r <- probe(EI, cache = C_AHEAD)
  chk("③ 양성 대조: 벤치가 as-of 보다 앞섬(as-of 가 더 새것) → 로더 3종 통과", all(went_through(r)), fmt(r))
  # ③b fail-closed(11-06 적대 검증 수리): 옵션 미설정인데 벤치가 없으면 낡음을 잴 수 없다 → 정지(구판 = 조용히 통과)
  r <- probe(EI, cache = C_NOBENCH)
  chk("③b 옵션 미설정 · CACHE_DIR 에 벤치 없음 → 로더 3종 stop(fail-closed · 메시지 = '벤치 없음' + 벤치 경로)", a3b_nobench(EI), fmt(r))
  # 측정만(단정 아님 — 설계): 옵션 경로로 낡음 검사를 끄는 길
  r <- probe(EI, opt = file.path(C_STALE, "msm_asof_daily.parquet"), cache = C_STALE)
  note(sprintf("옵션 경로로 같은 낡은 파일을 주면 낡음 검사 생략(설계) — 로더 통과 %d/3", sum(went_through(r))))
})

section("④ 정상 → 반환 열 · 정렬 · 값 · 속성", {
  x <- call_loader(EI, ".msm_asof_load", opt = P_OK); d <- x$value
  chk("④ .msm_asof_load 정상 통과", isTRUE(x$ok), x$msg)
  chk("④ 반환 열 = Date · MSM_Crisis_Prob(부가 열 Price · Vol_Est · msm_fit_date · guard_action 제거) · Date 형",
      identical(names(d), c("Date", "MSM_Crisis_Prob")) && inherits(d$Date, "Date"), paste(names(d), collapse = ","))
  chk("④ 날짜순(역순 기록 입력) · 결측 행(2004-02-16) 제외 · 값 = 파일 Crisis_Prob",
      nrow(d) == nrow(REF) && !is.unsorted(d$Date) && !(NA_DAY %in% d$Date) &&
        identical(as.integer(d$Date), as.integer(REF$Date)) && isTRUE(all.equal(d$MSM_Crisis_Prob, REF$Crisis_Prob, tolerance = 1e-14)),
      sprintf("(n %d vs %d)", nrow(d), nrow(REF)))
  y <- call_loader(EI, "load_msm_daily", opt = P_OK)$value
  chk("④ 속성 msm_estimator = asof_yearly:v1(.msm_asof_load · load_msm_daily)",
      identical(attr(d, "msm_estimator"), EST) && identical(attr(y, "msm_estimator"), EST))
  m <- call_loader(EI, "load_msm_signal", opt = P_OK)$value
  chk("④ load_msm_signal 반환 열 = Date · YM · MSM_Crisis_Prob", identical(names(m), c("Date", "YM", "MSM_Crisis_Prob")), paste(names(m), collapse = ","))
  chk("④ 종합 판정(돌연변이 생존 대조에 쓰는 같은 함수) = 설치본 초록", a4_normal(EI))
})

section("⑤ 월 집계 = 달력 월평균 · Date = 그 달 자료 최대일", {
  m <- call_loader(EI, "load_msm_signal", opt = P_OK)$value
  ym <- format(REF$Date, "%Y-%m")                                   # 독립 계산(로더 코드를 쓰지 않는다)
  e_mean <- tapply(REF$Crisis_Prob, ym, mean); e_max <- tapply(as.integer(REF$Date), ym, max)
  chk("⑤ 월 = 2004-01~06 6개 · 날짜순 · YM 문자", identical(m$YM, names(e_mean)) && length(e_mean) == 6L && is.character(m$YM), paste(m$YM, collapse = ","))
  chk("⑤ MSM_Crisis_Prob = 달력 월평균(결측 행 제외 · 독립 계산과 차 < 1e-12)",
      length(m$MSM_Crisis_Prob) == 6L && max(abs(m$MSM_Crisis_Prob - as.numeric(e_mean))) < 1e-12)
  chk("⑤ Date = 그 달 자료 최대일(2004-01 = 01-30 · 달력 말일 01-31 아님 · 02 = 02-27)",
      identical(as.integer(m$Date), as.integer(e_max)) && m[YM == "2004-01", Date] == as.Date("2004-01-30") &&
        m[YM == "2004-02", Date] == as.Date("2004-02-27"), paste(format(m$Date), collapse = ","))
})

section("⑥ parquet 왕복에서 표식(속성 · 열) 생존", {
  s <- data.table(Date = as.Date(c("2004-01-30", "2004-02-27", "2004-03-31")), Regime_Score = c(14.25, 20, 41.75))
  EI$.msm_stamp(s)
  chk("⑥ .msm_stamp = 행 열 전부 + 파일 속성(제자리)", identical(unique(s$msm_estimator), EST) && identical(attr(s, "msm_estimator"), EST))
  p <- file.path(mkd(TD, "roundtrip"), "stamp.parquet"); write_parquet(s, p); y <- read_parquet(p)
  chk("⑥ write_parquet → read_parquet 뒤 속성 msm_estimator 생존", identical(attr(y, "msm_estimator"), EST), paste(attr(y, "msm_estimator")))
  chk("⑥ write_parquet → read_parquet 뒤 열 msm_estimator 전 행 생존", nrow(y) == 3L && identical(unique(as.character(y$msm_estimator)), EST))
  p0 <- file.path(TD, "roundtrip", "nostamp.parquet"); write_parquet(s[, .(Date, Regime_Score)], p0)
  chk("⑥ 음성 대조: 표식 안 한 표는 왕복 뒤 속성 없음(위 단정이 늘 초록인 계기가 아니다)", is.null(attr(read_parquet(p0), "msm_estimator")))
})

section("⑦ classify_regime_basis", {
  cs <- data.table(
    score = c(42.45, 41.75, 75,    30,    44.99,  50,    30,    20,  30,     60),
    msm   = c(0.945, 0.90,  0.95,  0.75,  0.8999, 0.75,  0.20,  NA,  0.6999, 0.30),
    want  = c("msm_override", "msm_override", "msm_override", "msm_override", "msm_override",
              "score", "score", "score", "score", "score"))
  got <- EI$classify_regime_basis(cs$score, cs$msm)
  chk("⑦ MSM ≥0.9 + 점수 <45 → msm_override(2026-10 실례 42.45/0.945 · 경계 0.90)", identical(got[1:2], cs$want[1:2]), paste(got[1:2], collapse = ","))
  chk("⑦ 점수만으로 같은 범주 → score(CAUTION 50/0.75 · NEUTRAL 30/0.20 · MSM 결측 · 0.6999 · CAUTION 60/0.30)",
      identical(got[6:10], cs$want[6:10]), paste(got[6:10], collapse = ","))
  chk("⑦ 단락이 올린 그 밖의 경우도 msm_override(RISK_OFF 75/0.95 → CRISIS · NEUTRAL 30/0.75 → CAUTION · 44.99/0.8999 → CAUTION)",
      identical(got[3:5], cs$want[3:5]), paste(got[3:5], collapse = ","))
  chk("⑦ 근거 = 두 분류의 차이(단락 분류 ≠ 점수 분류 ⇔ msm_override) — 벡터 전부",
      identical(got == "msm_override", EI$classify_regime_category(cs$score, cs$msm) != EI$classify_regime_category(cs$score)))
})

# ─── ⑧ Gate M 관문(gate_msm_asof.sh 그대로) ─────────────────────────────────────────────────────────
BASH <- local({
  c1 <- "C:/Program Files/Git/bin/bash.exe"
  if (file.exists(c1)) c1 else { s <- Sys.which("bash"); if (nzchar(s) && !grepl("system32", s, ignore.case = TRUE)) gsub("\\\\", "/", s) else NA_character_ }
})
RSCRIPT_BIN <- local({
  exe <- if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  cand <- c(file.path(R.home("bin"), exe), file.path(R.home(), "bin", exe))
  p <- cand[file.exists(cand)][1]; if (is.na(p)) exe else gsub("\\\\", "/", p)
})
EMPTY_IN <- file.path(TD, "empty_stdin.txt"); invisible(file.create(EMPTY_IN))   # 자식의 표준 입력(러너의 입력을 물려주지 않는다)
GATE_AS_OF <- "2004-04-01"                                                         # 홀딩월 → sig 월 2004-03 · SIG_DATE = 2004-03-31
# 관문 1회 — 실행기는 QVEST_RSCRIPT 로 이 R 을 준다. 판정: OK = rc 0 ∧ 'OK ' 줄 · BAD = rc 1 ∧ 'BAD ' 줄 · 그 밖 = DEAD
gate_run <- function(root, as_of) {
  old <- Sys.getenv("QVEST_RSCRIPT", unset = NA); Sys.setenv(QVEST_RSCRIPT = RSCRIPT_BIN)
  on.exit(if (is.na(old)) Sys.unsetenv("QVEST_RSCRIPT") else Sys.setenv(QVEST_RSCRIPT = old), add = TRUE)
  out <- suppressWarnings(system2(BASH, c(shQuote(GATE), as_of, shQuote(root)), stdout = TRUE, stderr = FALSE, stdin = EMPTY_IN))
  rc <- attr(out, "status"); rc <- if (is.null(rc)) 0L else as.integer(rc)
  out <- sub("\r$", "", out, useBytes = TRUE)
  ln <- grep("^(OK|BAD) ", out, value = TRUE, useBytes = TRUE); ln <- if (length(ln)) ln[length(ln)] else ""
  v <- if (rc == 0L && startsWith(ln, "OK ")) "OK" else if (rc == 1L && startsWith(ln, "BAD ")) "BAD" else "DEAD"
  why <- sub(" \\| .*$", "", ln)                     # 계약 = 'BAD [태그] 사유 ; … | 진단…' — 태그는 사유 부분에서만 센다(진단 문구는 계약 아님)
  tags <- unique(gsub("^\\[|\\]$", "", regmatches(why, gregexpr("\\[[a-z_]+\\]", why))[[1]]))
  list(rc = rc, line = ln, verdict = v, tags = tags)
}
gate_desc <- function(g) sprintf("(%s rc=%d · %s)", g$verdict, g$rc, substr(g$line, 1, 220))
# 합성 루트: 벤치 · 일간 신호는 sig 월까지 맞춘다(신선도 통과) — 월간 신호의 표식만 바꾼다
gate_root <- function(tag, monthly) {
  root <- mkd(TD, "gate", tag); cd <- mkd(root, ".cache")
  write_bench(cd, ASOF_D)
  write_parquet(monthly, file.path(cd, "unified_regime_signal.parquet"))
  write_parquet(data.table(Date = ASOF_D[ASOF_D <= as.Date("2004-03-31")], Regime_Score = 10), file.path(cd, "unified_regime_signal_daily.parquet"))
  root
}
gate_monthly <- function(col = NULL, attr_val = NULL) {
  x <- data.table(Date = as.Date(c("2004-01-31", "2004-02-29", "2004-03-31")), YM = c("2004-01", "2004-02", "2004-03"),
                  Regime_Score = c(14.25, 20, 41.75), Category = c("RISK_ON", "RISK_ON", "CRISIS"),
                  avail_date = as.Date(c("2004-01-30", "2004-02-27", "2004-03-31")))
  if (!is.null(col)) x[, msm_estimator := col]
  if (!is.null(attr_val)) setattr(x, "msm_estimator", attr_val)
  x
}
marker_only <- function(g) identical(g$verdict, "BAD") && identical(g$tags, "marker")

section("⑧ Gate M 관문(gate_msm_asof.sh 그대로 · 표식만 바꾼 합성 월간 parquet)", {
  SH <- readLines(SRC_PG2, encoding = "UTF-8", warn = FALSE)
  chk("⑧ 전제: run_pg2_rebalance_full.sh 의 Gate M 이 gate_msm_asof.sh 를 부른다(판정 정본 한 벌)",
      any(grepl("^GM=", SH) & grepl("gate_msm_asof.sh", SH, fixed = TRUE)))
  if (is.na(BASH)) {
    skip("⑧ Gate M 관문", "bash(Git Bash) 없음 — 셸 관문 미실행(판정 미측정)", "C:/Program Files/Git/bin/bash.exe")
  } else {
    G <- list(none     = gate_run(gate_root("none",     gate_monthly()), GATE_AS_OF),                                    # 표식 없음(구판 산출)
              mixed    = gate_run(gate_root("mixed",    gate_monthly(col = c(EST, "legacy", EST), attr_val = EST)), GATE_AS_OF),  # 혼합
              ok       = gate_run(gate_root("ok",       gate_monthly(col = EST, attr_val = EST)), GATE_AS_OF),           # 정상
              colonly  = gate_run(gate_root("colonly",  gate_monthly(col = EST)), GATE_AS_OF),                           # 열만
              attronly = gate_run(gate_root("attronly", gate_monthly(attr_val = EST)), GATE_AS_OF))                      # 속성만
    v <- vapply(G, `[[`, "", "verdict")
    chk("⑧ 표식 없음 · 혼합 · 정상 합성 parquet → BAD/BAD/OK", identical(unname(v[c("none", "mixed", "ok")]), c("BAD", "BAD", "OK")),
        paste(names(v), v, collapse = " · "))
    chk("⑧ 정상 = rc 0 · 'OK ' 줄 — 고정물의 신선도 부분(벤치 · sig 행 · avail_date · 일간)이 통과한다는 양성 대조",
        identical(G$ok$verdict, "OK"), gate_desc(G$ok))
    chk("⑧ 표식 없음 → rc 1 · BAD 사유 = [marker] 만(다른 검사가 막은 게 아니다)", marker_only(G$none), gate_desc(G$none))
    chk("⑧ 혼합(행 열 asof_yearly:v1 · legacy 섞임 · 속성은 정상) → rc 1 · BAD [marker] 만", marker_only(G$mixed), gate_desc(G$mixed))
    chk("⑧ 열만 · 속성만 → BAD [marker] 만(둘 다 있어야 OK)", marker_only(G$colonly) && marker_only(G$attronly),
        paste(gate_desc(G$colonly), gate_desc(G$attronly)))
  }
})

# ─── ⑨ D1 절단 · 빌드 표식 ────────────────────────────────────────────────────────────────────────
C_BUILD <- P_BUILD <- NA_character_; KT_D <- as.Date(character(0)); FRED_D <- as.Date(character(0))
build_month <- function(E, tag) {
  old_opt <- options(qvest.msm_asof_path = P_BUILD); old_cache <- CACHE_DIR; CACHE_DIR <<- C_BUILD
  on.exit({ options(old_opt); CACHE_DIR <<- old_cache }, add = TRUE)
  sp <- file.path(TD, "out_m", tag, "unified_regime_signal.parquet")
  dt <- tryCatch(quiet(E$build_regime_signal_table(save_path = sp)),
                 error = function(e) { cat("  (월 빌드 오류) ", conditionMessage(e), "\n"); NULL })
  list(dt = dt, path = sp)
}
build_day <- function(E, tag) {
  dc <- mkd(TD, paste0("cache_daily_", tag))          # FRED wide 없음(L2 부분 빌드) · regime_current.json 도 여기
  old_opt <- options(qvest.msm_asof_path = P_BUILD); old_cache <- CACHE_DIR; CACHE_DIR <<- dc
  on.exit({ options(old_opt); CACHE_DIR <<- old_cache }, add = TRUE)
  sp <- file.path(dc, "unified_regime_signal_daily.parquet")   # 운영 파일명 → regime_current.json 방출 경로를 탄다
  dt <- tryCatch(quiet(E$build_regime_signal_table_daily(save_path = sp, verbose = FALSE)),
                 error = function(e) { cat("  (일 빌드 오류) ", conditionMessage(e), "\n"); NULL })
  list(dt = dt, path = sp, json = file.path(dc, "regime_current.json"))
}
d1_month_ok <- function(S) is.data.frame(S) && nrow(S) == 6L && identical(min(S$YM), FIRST_YM) && !any(S$YM < FIRST_YM)
d1_day_ok   <- function(S) is.data.frame(S) && nrow(S) > 0L && min(S$Date) == ASOF_FIRST && !any(S$Date < ASOF_FIRST)
stamped     <- function(S) is.data.frame(S) && "msm_estimator" %in% names(S) &&
  identical(unique(as.character(S$msm_estimator)), EST) && identical(attr(S, "msm_estimator"), EST)
c11_clean   <- function(S) identical(unique(as.character(S$c11_regime_key)), C11_STUB) && identical(attr(S, "c11_avail_regime_key"), C11_STUB)

section("⑨ 합성 3층 입력(MSM 2004-01-02~ · FRED 2003-07~ · KTRI 2003-09~)", {
  C_BUILD <- mkd(TD, "cache_build")
  cal <- bdays("2003-01-02", "2004-12-31")
  write_parquet(data.table(Date = cal), file.path(C_BUILD, "trading_calendar.parquet"))      # 월 빌드 avail_date 용
  P_BUILD <- write_asof(file.path(C_BUILD, "msm_asof_daily.parquet"))
  fm <- format(cal, "%Y-%m"); FRED_D <- cal[fm >= "2003-07" & fm <= "2004-06"]
  FRED_D <- FRED_D[!duplicated(format(FRED_D, "%Y-%m"), fromLast = TRUE)]                  # 달마다 마지막 거래일 1행
  write_parquet(data.table(Date = FRED_D, Macro_Risk_Score = 5), file.path(C_BUILD, "macro_regime.parquet"))
  KT_D <- c(bdays("2003-09-01", "2003-12-31"), bdays("2004-03-01", "2004-06-30"))          # 2004-01~02 공백(LOCF 이월로 채워진다)
  kt <- data.table(DATE = format(KT_D), KTRI = 50, VEA = 50); kt[DATE == "2003-12-31", KTRI := 33]
  fwrite(kt, file.path(mkd(PROJECT_ROOT, "04_Regime_Engine", "output"), "ktri_v3_signals.csv"))
  chk("⑨ 전제: FRED · KTRI 가 as-of 첫날보다 먼저 시작(절단할 달 · 날이 있다 — 없으면 절단 단정이 공허)",
      min(FRED_D) < ASOF_FIRST && min(KT_D) < ASOF_FIRST && sum(KT_D < ASOF_FIRST) > 0L)
})

BM <- BD <- NULL
section("⑨월 build_regime_signal_table(설치본)", {
  BM <- build_month(EI, "inst"); S <- BM$dt
  chk("⑨월 빌드 실행(합성 3층 · tempdir 저장)", is.data.frame(S) && nrow(S) > 0L && file.exists(BM$path))
  chk("⑨월 D1: 첫 행 = as-of 첫 달 2004-01 · 그 전 달(2003-07~12) 0행 · 6개월", d1_month_ok(S), paste(S$YM, collapse = ","))
  chk("⑨월 D1 은 LOCF 뒤: 2004-01 KTRI_Score = 2003-12 마지막 값 33(절단 전 이월 보존) · FRED_MRS 결측 0",
      isTRUE(S[YM == "2004-01", KTRI_Score] == 33) && !anyNA(S$FRED_MRS), paste(S$KTRI_Score, collapse = ","))
  chk("⑨월 표식: msm_estimator 열 전 행 · 파일 속성 = asof_yearly:v1", stamped(S))
  chk("⑨월 C11 키에 MSM 미혼입: c11_regime_key 열 · 속성 = 시험 고정 키 그대로", c11_clean(S),
      paste(unique(S$c11_regime_key), attr(S, "c11_avail_regime_key")))
  chk("⑨월 fw_* 4열 없음 · Category_basis = 끝 열", !any(grepl("^fw_", names(S))) && identical(utils::tail(names(S), 1), "Category_basis"),
      paste(names(S), collapse = ","))
  cr <- S[!is.na(MSM_Crisis_Prob) & MSM_Crisis_Prob >= 0.9 & Regime_Score < 45]
  chk("⑨월 단락 CRISIS(MSM ≥0.9 · 점수 <45 — 2026-10 꼴) = Category CRISIS · 근거 msm_override · 현금 0 (1행 이상 · 전부)",
      nrow(cr) >= 1L && all(cr$Category == "CRISIS") && all(cr$Category_basis == "msm_override") && all(cr$Cash_Pct == 0),
      sprintf("(n=%d)", nrow(cr)))
  sm <- S[EI$classify_regime_category(Regime_Score) == Category]
  chk("⑨월 점수 범주 그대로인 행 = score (1행 이상 · 전부)", nrow(sm) >= 1L && all(sm$Category_basis == "score"), sprintf("(n=%d)", nrow(sm)))
  y <- read_parquet(BM$path)
  chk("⑨월 저장 parquet 왕복: 표식 열 · 속성 · C11 속성 생존", stamped(y) && c11_clean(y))
})

section("⑨일 build_regime_signal_table_daily(설치본)", {
  BD <- build_day(EI, "inst"); S <- BD$dt
  chk("⑨일 빌드 실행(MSM · KTRI · FRED 없음 부분 빌드)", is.data.frame(S) && nrow(S) > 0L && file.exists(BD$path))
  chk("⑨일 D1: 첫 행 = as-of 첫날 2004-01-02 · 그 전 날(KTRI 2003-09~12) 0행", d1_day_ok(S), format(min(S$Date)))
  chk("⑨일 D1 은 LOCF 뒤: 2004-01-02 KTRI_Score = 33(2003-12-31 이월 보존) · MSM 결측 행 0",
      isTRUE(S[Date == ASOF_FIRST, KTRI_Score] == 33) && !anyNA(S$MSM_Crisis_Prob))
  f1 <- S[Date == ASOF_FIRST]
  chk("⑨일 D1 은 평활 앞: 첫 행 Regime_Score_smooth = Regime_Score(EWMA 가 절단 뒤에서 시작)",
      nrow(f1) == 1L && isTRUE(all.equal(f1$Regime_Score_smooth, f1$Regime_Score)), sprintf("(%s vs %s)", f1$Regime_Score_smooth, f1$Regime_Score))
  chk("⑨일 표식 열 · 속성 · C11 키 미혼입 · fw_* 없음 · Category_basis 끝 열",
      stamped(S) && c11_clean(S) && !any(grepl("^fw_", names(S))) && identical(utils::tail(names(S), 1), "Category_basis"))
  last <- S[which.max(Date)]
  J <- if (file.exists(BD$json)) tryCatch(jsonlite::fromJSON(BD$json), error = function(e) NULL) else NULL
  chk("⑨일 regime_current.json: regime_tag_basis = 마지막 행 근거(msm_override — 단락 CRISIS) · regime_tag = CRISIS · cash_pct = 마지막 행 현금(4자리)",
      !is.null(J) && identical(J$regime_tag_basis, last$Category_basis) && identical(J$regime_tag_basis, "msm_override") &&
        identical(J$regime_tag, "CRISIS") && isTRUE(all.equal(J$cash_pct, round(last$Cash_Pct, 4))),
      if (is.null(J)) "(json 없음)" else sprintf("(basis %s · tag %s · cash %s vs %s)", J$regime_tag_basis, J$regime_tag, J$cash_pct, round(last$Cash_Pct, 4)))
  chk("⑨일 저장 parquet 왕복: 표식 열 · 속성 생존", stamped(read_parquet(BD$path)))
})

section("⑧×⑨ 설치본 빌드 산출(월 · 일) → 실제 Gate M 관문 OK", {
  if (is.na(BASH)) {
    skip("⑧×⑨ 빌드 산출 → 관문", "bash(Git Bash) 없음 — 셸 관문 미실행(판정 미측정)", "C:/Program Files/Git/bin/bash.exe")
  } else {
    root <- mkd(TD, "gate", "build"); cd <- mkd(root, ".cache")
    ok_cp <- file.copy(BM$path, file.path(cd, "unified_regime_signal.parquet"), overwrite = TRUE) &&
      file.copy(BD$path, file.path(cd, "unified_regime_signal_daily.parquet"), overwrite = TRUE)
    write_bench(cd, ASOF_D)                                      # 벤치 = as-of 경로와 같은 날들(06-30 까지)
    g <- gate_run(root, "2004-07-01")                            # sig 월 2004-06 · SIG_DATE 2004-06-30
    chk("⑧×⑨ 빌드 산출 → 관문 OK(표식 · sig 월 avail_date = SIG_DATE 2004-06-30 · 일간 max ≥ SIG_DATE — 어긋나면 [marker]/[avail]/[daily])",
        ok_cp && identical(g$verdict, "OK"), gate_desc(g))
  }
})

# ─── 돌연변이 — 설치본 사본(소스 텍스트 치환 · deparse 아님) ───────────────────────────────────────
SRC_TXT <- if (file.exists(SRC_SIGNAL)) paste(readLines(SRC_SIGNAL, encoding = "UTF-8", warn = FALSE), collapse = "\n") else ""
make_mutant <- function(tag, pattern, replacement) {
  n0 <- count_fixed(SRC_TXT, pattern); r0 <- count_fixed(SRC_TXT, replacement)
  mut <- sub(pattern, replacement, SRC_TXT, fixed = TRUE)
  n1 <- count_fixed(mut, pattern); r1 <- count_fixed(mut, replacement)
  p <- file.path(mkd(TD, "mutants"), paste0("regime_signal_", tag, ".R")); write_lf(mut, p)
  list(applied = n0 == 1L && n1 == 0L && r1 == r0 + 1L && !identical(mut, SRC_TXT), path = p,
       detail = sprintf("(대상 %d→%d곳 · 치환문 %d→%d곳)", n0, n1, r0, r1))
}

section("돌연변이 M2 — 추정기 비교 삭제(!identical(est, 기대값) → FALSE)", {
  M <- make_mutant("M2", "!identical(as.character(est), MSM_ESTIMATOR_EXPECTED)", "FALSE")
  chk("M2 치환 성사(설치본 1곳 → 사본 0곳)", M$applied, M$detail)
  E <- load_signal(M$path)
  chk("M2 사본 생존(적재 · 함수 존재 · ④ 정상 경로 초록)", has_funs(E) && a4_normal(E))
  r <- if (has_funs(E)) probe(E, opt = P_OTHER) else list()
  chk("M2 → ② red: 'other' 표식 파일이 로더를 통과한다", has_funs(E) && !a2_other(E), fmt(r))
  chk("M2 특이성: ③ 낡음 정지는 그대로 초록(단정 ③ 은 추정기 비교를 재지 않는다)", has_funs(E) && a3_stale(E))
  x <- if (has_funs(E)) call_loader(E, ".msm_asof_load", opt = P_OTHER) else list(ok = FALSE)
  if (isTRUE(x$ok)) note(sprintf("M2 사본은 'other' 자료에 속성 msm_estimator = %s 를 단다(도장 = 상수) — 하류 Gate M · 원장은 그 도장만 보므로 ② 가 유일한 출처 대조선",
                                 paste(attr(x$value, "msm_estimator"))))
})

section("돌연변이 M3 — 낡음 비교 삭제(if (max(dt$Date) < bmax) → if (FALSE))", {
  M <- make_mutant("M3", "if (max(dt$Date) < bmax)", "if (FALSE)")
  chk("M3 치환 성사(설치본 1곳 → 사본 0곳)", M$applied, M$detail)
  E <- load_signal(M$path)
  chk("M3 사본 생존(적재 · 함수 존재 · ④ 정상 경로 초록)", has_funs(E) && a4_normal(E))
  r <- if (has_funs(E)) probe(E, cache = C_STALE) else list()
  chk("M3 → ③ red: 벤치보다 낡은 as-of 경로가 로더를 통과한다", has_funs(E) && !a3_stale(E), fmt(r))
  chk("M3 특이성: ② 'other' 정지는 그대로 초록", has_funs(E) && a2_other(E))
})

section("돌연변이 M4 — 벤치 부재 정지 삭제(if (!file.exists(bp)) → if (FALSE))", {
  M <- make_mutant("M4", "if (!file.exists(bp))", "if (FALSE)")
  chk("M4 치환 성사(설치본 1곳 → 사본 0곳)", M$applied, M$detail)
  E <- load_signal(M$path)
  chk("M4 사본 생존(적재 · 함수 존재 · ④ 정상 경로 초록)", has_funs(E) && a4_normal(E))
  r <- if (has_funs(E)) probe(E, cache = C_NOBENCH) else list()
  chk("M4 → ③b red: 벤치 없는 CACHE_DIR 에서 로더가 '벤치 없음'으로 정지하지 않는다", has_funs(E) && !a3b_nobench(E), fmt(r))
  chk("M4 특이성: ③ 낡음 정지 · ② 'other' 정지는 그대로 초록", has_funs(E) && a3_stale(E) && a2_other(E))
})

section("돌연변이 M5 — 파일 없음 명시 가드 삭제(if (!file.exists(p)) stop( → if (FALSE) stop()", {
  M <- make_mutant("M5", "if (!file.exists(p)) stop(", "if (FALSE) stop(")
  chk("M5 치환 성사(설치본 1곳 → 사본 0곳)", M$applied, M$detail)
  E <- load_signal(M$path)
  chk("M5 사본 생존(적재 · 함수 존재 · ④ 정상 경로 초록)", has_funs(E) && a4_normal(E))
  r <- if (has_funs(E)) probe(E, opt = P_MISS) else list()
  chk("M5 → ①′ red: 없는 파일에서 로더 고유 문구 없이(arrow 오류로) 정지한다", has_funs(E) && !a1_missing(E), fmt(r))
  chk("M5 안전 면: 정지 자체는 유지(fail-closed 는 arrow 가 대신) — 통과한 로더 0", has_funs(E) && !any(went_through(r)), fmt(r))
  chk("M5 특이성: ② 'other' 정지 · ③ 낡음 정지는 그대로 초록", has_funs(E) && a2_other(E) && a3_stale(E))
})

section("돌연변이 M1m — 월 D1 절단 삭제(base[YM >= .cut_ym] → base)", {
  M <- make_mutant("M1m", "base <- base[YM >= .cut_ym]", "base <- base  # MUTANT-M1m")
  chk("M1m 치환 성사(설치본 1곳 → 사본 0곳)", M$applied, M$detail)
  E <- load_signal(M$path)
  b <- if (has_funs(E)) build_month(E, "M1m") else list(dt = NULL)
  chk("M1m 사본 생존(월 빌드 실행 · 표식 있음)", has_funs(E) && is.data.frame(b$dt) && nrow(b$dt) > 0L && stamped(b$dt))
  chk("M1m → ⑨월 D1 red: 첫 행이 as-of 첫 달 앞(2003-07)으로 샌다", is.data.frame(b$dt) && !d1_month_ok(b$dt),
      if (is.data.frame(b$dt)) sprintf("(첫 달 %s · %d개월)", min(b$dt$YM), nrow(b$dt)) else "")
})

section("돌연변이 M1d — 일 D1 절단 삭제(base[Date >= .cut_d] → base)", {
  M <- make_mutant("M1d", "base <- base[Date >= .cut_d]", "base <- base  # MUTANT-M1d")
  chk("M1d 치환 성사(설치본 1곳 → 사본 0곳)", M$applied, M$detail)
  E <- load_signal(M$path)
  b <- if (has_funs(E)) build_day(E, "M1d") else list(dt = NULL)
  chk("M1d 사본 생존(일 빌드 실행 · 표식 있음)", has_funs(E) && is.data.frame(b$dt) && nrow(b$dt) > 0L && stamped(b$dt))
  chk("M1d → ⑨일 D1 red: 첫 행이 as-of 첫날 앞(2003-09-01)으로 샌다", is.data.frame(b$dt) && !d1_day_ok(b$dt),
      if (is.data.frame(b$dt)) sprintf("(첫날 %s)", format(min(b$dt$Date))) else "")
})

invisible(gc()); unlink(TD, recursive = TRUE)
cat(sprintf("\n=== 결과: PASS %d · FAIL %d · SKIP %d ===\n", PASS, FAIL, length(SKIPS)))
cat(toJSON(list(test = "regime_signal_msm_asof", pass = PASS, fail = FAIL, skipped = length(SKIPS),
                total = PASS + FAIL, skips = SKIPS), auto_unbox = TRUE), "\n", sep = "")
quit(status = if (FAIL > 0L) 1L else 0L, save = "no")
