#!/usr/bin/env Rscript
#==============================================================================
# test_fc_engine_gen.R — 팩터 척추 자체 사양 엔진(FC_*) 절단 불변성 시험 — 설계 §3-7 시험 1 · 2 만
#   설계 04_Research/01_reports/factor_spine_design_20261111/README.md §3-7 · 결정 FACTOR-SPINE-STAGE1-20261112
#   시험 3 ~ 7 은 만들지 않는다(도훈 '테스트 좀 그만하자' · 판단 Superfan T1 C-20261112-001 수용분).
#   자격 라운드 P1R03 사양 tests 에 들어가 등록 때 한 번 돈다(round_core/v3/register.R — 마지막 {"test" 줄의 fail = 0 이어야 등록).
#
# 1 절단 불변성 — 대상 FC_TOTAL_EW(구성원 334 · 가족 14개 경로 전부) · 창 = τ_D(2022-12-31) 이전 월말 4개(2022-08 ~ 11)
#   전체 실행 = 운영 그대로(실제 결합용 뷰). 셀 경로(rf_cell_engine.R 기저 엔진)와 같은 꼴 — 새 환경에 RAWDATA · .RP_START_DATE 를
#     넣고 sys.source · 엔진 진단 파일만 임시 폴더로(options(fce.diag_dir)).
#   절단 실행(t = 2022-08 · 09 · 10) = 그 시점의 세계:
#     결합용 뷰 사본 = t 이하 달 파일(바이트 동일 복사) + t 이하로 자른 메타(fc_meta.json months) · 부호표 · 커버리지
#     + RAWDATA(거래일 달력)도 t 달 끝까지 — 엔진의 '패널 마지막 달' 규칙이 패널 끝에 묶여 있어, 뷰만 자르고 패널을 두면
#       정직한 엔진도 t 뒤 달이 없어 멈추거나 뺀다.
#     엔진 텍스트 · 접근자 코드는 그대로 두고, 엔진이 결합용 뷰 모듈을 싣는 sys.source 호출만 가로채 fc_load_month 의
#     저장 폴더(dir)를 사본으로 돌린다(설정 · 등록부 · 부호 곱 · 순위 복원은 운영 그대로).
#   판정 = 절단 실행 FACTORS 가 전체 실행의 Date ≤ t 부분과 비트 동일(열 이름 · 행 순서 · 값 비트 — identical(num.eq = FALSE)).
#     미래 달을 읽는 엔진은 절단 세계에 그 달이 없어 멈추거나 · 그 달을 빼거나 · 다른 값을 내서 깨진다.
#   한계: 사본은 접근자를 거친 읽기만 자른다 — 저장본 직접 읽기(C15 위반)는 c15_load_path_scan.R 의 일이다.
#     창 앞 달 파일은 복사하지 않는다(엔진이 읽지 않는다 · 읽으면 '그 달이 없다'로 멈춰 실패 쪽이지 거짓 통과 쪽이 아니다).
# 2 양성 대조 — 엔진 소스 텍스트 치환 사본(저장소 밖 임시 폴더 · 두 곳 각각 원본에 정확히 1곳 · 치환 성사 단정):
#   읽기 = 다음 달 결합용 뷰 파일 · 날짜표 = 이번 달 → 신호일 t 의 점수를 t+1 달 정보로 만든다(미래 참조) → 1번에서 깨져야 한다.
#   (날짜표까지 다음 달로 옮긴 사본은 행과 정보 시점이 맞아 미래 참조가 아니다 — 그래서 날짜표를 이번 달에 묶는다.)
# 격리: 임시 파일은 저장소 밖(tempdir() — %TEMP%) · 저장소 무수정을 전후 md5 로 확인 · 성과 계산 없음(점수 비교만) ·
#   엔진 실행은 자식 Rscript(같은 R) 한 번에 하나 — 이 파일을 --child 로 다시 부른다.
# 쓰기(저장소 루트): Rscript 08_Tests/factor_db/test_fc_engine_gen.R → 마지막 줄 {"test":"test_fc_engine_gen","pass":N,"fail":M}
#==============================================================================

## ── 자식 모드 — 엔진 1회 실행(rf_cell_engine.R 기저 엔진 경로와 같은 꼴) · 결과는 RDS 로 ───────────────────────
if (identical(commandArgs(trailingOnly = TRUE)[1L], "--child")) local({
  job <- readRDS(commandArgs(trailingOnly = TRUE)[2L])
  t0 <- Sys.time()
  hk <- new.env(parent = emptyenv()); hk$n <- 0L; hk$req <- character(0)
  run_env <- new.env(parent = globalenv())
  run_env$RAWDATA <- data.table::data.table(Date = job$dates)
  run_env$.RP_START_DATE <- job$start
  if (!is.null(job$view_dir)) {
    vd <- job$view_dir
    # 엔진 최상위의 sys.source 호출만 여기로 온다(접근자 모듈 안 함수들의 sys.source 는 base 그대로 — 그 함수 환경은 run_env 밖)
    run_env$sys.source <- function(file, envir = baseenv(), ...) {
      base::sys.source(file, envir = envir, ...)
      if (identical(basename(file), "factor_combinable.R") && exists("fc_load_month", envir = envir, inherits = FALSE)) {
        f0 <- get("fc_load_month", envir = envir, inherits = FALSE)
        assign("fc_load_month", function(sig_date, ..., dir = NULL) {
          if (!is.null(dir)) stop("[절단 시험] 엔진이 저장 폴더(dir)를 직접 넘겼다 — 절단 사본으로 돌릴 수 없다")
          hk$req <- c(hk$req, format(as.Date(sig_date), "%Y%m"))
          f0(sig_date, ..., dir = vd)
        }, envir = envir)
        hk$n <- hk$n + 1L
      }
      invisible(NULL)
    }
  }
  dir.create(job$diag_dir, recursive = TRUE, showWarnings = FALSE)
  options(fce.diag_dir = job$diag_dir)                       # 진단 파일은 임시 폴더로(저장소 엔진 폴더에 쓰지 않는다)
  err <- tryCatch({ sys.source(job$engine, envir = run_env); NA_character_ }, error = function(e) conditionMessage(e))
  FX <- if (exists("FACTORS", envir = run_env, inherits = FALSE)) as.data.frame(get("FACTORS", envir = run_env, inherits = FALSE)) else NULL
  dg <- file.path(job$diag_dir, "fce_diag.csv")
  saveRDS(list(err = err, FACTORS = FX, diag = if (file.exists(dg)) utils::read.csv(dg, stringsAsFactors = FALSE) else NULL,
               n_fam_declared = length(get0(".FCE_FAMILIES", envir = run_env, inherits = FALSE)), hooked = hk$n, req = hk$req,
               engine_md5 = unname(tools::md5sum(job$engine)), secs = as.numeric(difftime(Sys.time(), t0, units = "secs"))), job$out)
  quit(save = "no", status = 0L)
})

## ── 부모 모드 ───────────────────────────────────────────────────────────────────────────────────────────────
options(warn = 1)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
T0 <- Sys.time()
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  tag <- if (isTRUE(ok)) { PASS <<- PASS + 1L; "[ok]  " } else { FAIL <<- FAIL + 1L; "[FAIL]" }
  cat(sprintf("  %s %s%s\n", tag, name, if (nzchar(detail)) paste0("\n           → ", detail) else ""))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
md5 <- function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent"
fmt <- function(n) if (is.null(n) || is.na(n)) "NA" else format(n, big.mark = ",")
rd_txt <- function(p) { x <- rawToChar(readBin(p, "raw", n = file.info(p)$size)); Encoding(x) <- "UTF-8"; x }
n_fixed <- function(x, pat) sum(gregexpr(pat, x, fixed = TRUE)[[1L]] > 0L)
month_end <- function(ym) { d <- as.Date(paste0(ym, "01"), "%Y%m%d"); seq(d, by = "1 month", length.out = 2L)[2L] - 1L }
## 비트 비교 — 열 이름 · 행 수 · 열마다 identical(num.eq = FALSE)(실수는 비트 · 날짜는 저장값 비트 · 문자열은 그대로)
same_bits <- function(a, b) {
  if (is.null(a) || is.null(b)) return(FALSE)
  a <- as.data.frame(a); b <- as.data.frame(b)
  identical(names(a), names(b)) && nrow(a) == nrow(b) &&
    all(vapply(names(a), function(k) identical(a[[k]], b[[k]], num.eq = FALSE), logical(1)))
}
diff_desc <- function(a, b) {
  da <- sort(unique(format(a$Date))); db <- sort(unique(format(b$Date)))
  if (!identical(da, db)) return(sprintf("날짜가 다르다(전체 ≤t %s | 절단 %s)", paste(da, collapse = ","), if (length(db)) paste(db, collapse = ",") else "없음"))
  if (nrow(a) != nrow(b)) return(sprintf("행 수가 다르다(%s | %s)", fmt(nrow(a)), fmt(nrow(b))))
  sprintf("값이 다르다(%s행 · 열 이름 · 저장형 포함 비트 비교)", fmt(sum(a$Ticker != b$Ticker | a$Score != b$Score, na.rm = TRUE)))
}

## 시험 설정(성과를 읽지 않는 시험 매개 — 연구 결정 아님)
TAU_D <- as.Date("2022-12-31")                    # 정보 경계(.claude/rules/lean-loop.md) — 창도, 돌연변이가 엿보는 다음 달도 이 안
WIN   <- c("202208", "202209", "202210", "202211") # 창 = 월말 4개
CUTS  <- WIN[-length(WIN)]                         # 절단 t = 앞 3개(끝 달 절단은 전체 실행과 같은 세계)
## 돌연변이 — 읽기 = 다음 달 뷰(그 달 마지막 달력일을 신호일로) · 날짜표 = 이번 달 월말 거래일
SUBS <- list(
  c(from = '.fce_fc$fc_load_month(.fce_d, direction = "registry"',
    to   = '.fce_fc$fc_load_month(seq(as.Date(format(.fce_d, "%Y-%m-01")), by = "month", length.out = 3L)[3L] - 1L, direction = "registry"'),
  c(from = '.fce_asof <- as.Date(.fce_in$asof)',
    to   = '.fce_asof <- .fce_d'))
TMP <- NULL

## 절단 사본 — t 이하 창 달 파일(바이트 동일) + t 이하로 자른 메타 · 부호표 · 커버리지 → 다시 읽어 정말 t 까지인지 확인
mk_cut <- function(tym) {
  d <- file.path(TMP, paste0("view_le_", tym)); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  keep <- WIN[WIN <= tym]
  for (ym in keep) {
    f <- sprintf(ST$month_file, ym)
    if (!isTRUE(file.copy(file.path(VIEW, f), file.path(d, f)))) stop("달 파일 복사 실패: ", f)
  }
  M <- META; M$months <- META$months[META$months$ym <= tym, , drop = FALSE]
  M$n_months <- nrow(M$months); M$last <- max(M$months$ym)
  writeLines(toJSON(M, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null"), file.path(d, ST$meta_file), useBytes = TRUE)
  for (k in c("signs_file", "coverage_file")) write_parquet(TB[[k]][TB[[k]]$ym <= tym], file.path(d, ST[[k]]))
  rx <- paste0("^", gsub(".", "[.]", sprintf(ST$month_file, "([0-9]{6})"), fixed = TRUE), "$")
  mf <- sort(sub(rx, "\\1", list.files(d, pattern = rx)))
  M2 <- fromJSON(file.path(d, ST$meta_file), simplifyVector = TRUE)
  S2 <- read_parquet(file.path(d, ST$signs_file)); C2 <- read_parquet(file.path(d, ST$coverage_file))
  ok <- identical(mf, keep) &&
    all(vapply(keep, function(ym) identical(md5(file.path(d, sprintf(ST$month_file, ym))), md5(file.path(VIEW, sprintf(ST$month_file, ym)))), logical(1))) &&
    identical(M2$stored_direction, META$stored_direction) && identical(M2$builder, META$builder) && isTRUE(M2$value_scale == META$value_scale) &&
    identical(max(M2$months$ym), tym) && identical(M2$months$asof, M$months$asof) &&
    identical(max(S2$ym), tym) && nrow(S2) == sum(TB$signs_file$ym <= tym) &&
    identical(max(C2$ym), tym) && nrow(C2) == sum(TB$coverage_file$ym <= tym)
  list(dir = d, ok = ok, n_files = length(mf))
}

## 엔진 1회 = 자식 Rscript 1개(한 번에 하나)
run_job <- function(tag, engine, dates, view_dir = NULL) {
  jd <- file.path(TMP, tag); dir.create(jd, recursive = TRUE, showWarnings = FALSE)
  job <- list(engine = engine, dates = dates, start = START, view_dir = view_dir, diag_dir = file.path(jd, "diag"), out = file.path(jd, "res.rds"))
  jf <- file.path(jd, "job.rds"); saveRDS(job, jf)
  t1 <- Sys.time()
  o <- suppressWarnings(system2(RS, c(shQuote(SELF), "--child", shQuote(jf)), stdout = TRUE, stderr = TRUE))
  r <- if (file.exists(job$out)) readRDS(job$out) else
    list(err = sprintf("자식 실행 결과 없음(rc %s): %s", attr(o, "status") %||% "?", paste(utils::tail(o, 3L), collapse = " | ")),
         FACTORS = NULL, hooked = 0L, req = character(0), engine_md5 = NA_character_)
  r$wall <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  s <- grep("FACTORS [0-9]+|패널 마지막 달", o, value = TRUE, useBytes = TRUE)
  cat(sprintf("    · %-14s %5.1f초 · %s\n", tag, r$wall, if (!is.na(r$err)) paste("엔진 멈춤:", r$err) else paste(trimws(s), collapse = " / ")))
  r
}

## 1번 검사 — 전체 실행 1 + 절단 실행 t 마다 1
inv_eval <- function(full, cr, cut, tym) {
  harness <- isTRUE(cut$ok) && identical(as.integer(cr$hooked), 1L) && length(cr$req) > 0L
  F_le <- if (!is.null(full$FACTORS)) full$FACTORS[full$FACTORS$Date <= month_end(tym), , drop = FALSE] else NULL
  same <- is.na(full$err) && is.na(cr$err) && same_bits(F_le, cr$FACTORS)
  why <- if (!is.na(full$err)) paste("전체 실행 멈춤:", full$err) else if (!is.na(cr$err)) paste("절단 실행 멈춤:", cr$err) else
    if (same) "비트 동일" else diff_desc(F_le, cr$FACTORS)
  list(harness = harness, same = same, why = why, n_full = if (is.null(F_le)) NA_integer_ else nrow(F_le),
       n_cut = if (is.null(cr$FACTORS)) NA_integer_ else nrow(cr$FACTORS), req = cr$req, hooked = cr$hooked, md5 = cr$engine_md5)
}
check1 <- function(engine, tag) {
  cat(sprintf("  [%s] %s (md5 %s)\n", tag, engine, md5(engine)))
  full <- run_job(paste0(tag, "_full"), engine, CAL)
  per <- setNames(lapply(CUTS, function(tym)
    inv_eval(full, run_job(sprintf("%s_le_%s", tag, tym), engine, CAL[CAL <= month_end(tym)], CUT[[tym]]$dir), CUT[[tym]], tym)), CUTS)
  list(full = full, per = per, ok = all(vapply(per, function(p) p$harness && p$same, logical(1))))
}

err_main <- tryCatch({
  ROOT <- local({ r <- Sys.getenv("CLAUDE_PROJECT_DIR", ""); if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", ""); gsub("\\\\", "/", r) })
  if (!nzchar(ROOT) || !dir.exists(ROOT)) stop("CLAUDE_PROJECT_DIR · QM_ROOT 미설정 또는 없는 폴더")
  Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)                                # 자식(엔진 · 접근자)이 같은 루트를 쓴다(금칙 ④ 순서)
  SELF <- local({ a <- commandArgs(FALSE); f <- sub("^--file=", "", a[startsWith(a, "--file=")])
    if (length(f) != 1L) stop("이 시험 파일 경로를 읽지 못했다(Rscript 로 실행할 것)")
    normalizePath(gsub("~+~", " ", f, fixed = TRUE), winslash = "/", mustWork = TRUE) })
  RS <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  ENG <- file.path(ROOT, "04_Research", "strategies", "FC_TOTAL_EW", "engine.R")
  FAMS <- fromJSON(file.path(dirname(ENG), "own_spec.json"), simplifyVector = TRUE)$core$families
  RT <- unique(tolower(sub("/+$", "", c(ROOT, normalizePath(ROOT, winslash = "/")))))
  under_root <- function(p) { q <- tolower(normalizePath(p, winslash = "/", mustWork = FALSE)); any(q == RT | startsWith(q, paste0(RT, "/"))) }
  TMP <- file.path(normalizePath(tempdir(), winslash = "/"), sprintf("tfe_%d", Sys.getpid()))
  if (under_root(TMP)) stop("임시 폴더가 저장소 안이다: ", TMP)
  dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
  ST <- fromJSON(file.path(ROOT, "06_Registry", "factor_combinable.json"), simplifyVector = TRUE)$storage
  VIEW <- file.path(ROOT, ST$dir)
  META <- fromJSON(file.path(VIEW, ST$meta_file), simplifyVector = TRUE)
  TB <- list(signs_file = as.data.table(read_parquet(file.path(VIEW, ST$signs_file), mmap = FALSE)),
             coverage_file = as.data.table(read_parquet(file.path(VIEW, ST$coverage_file), mmap = FALSE)))
  PEEK <- format(month_end(WIN[length(WIN)]) + 1L, "%Y%m")
  if (month_end(PEEK) > TAU_D) stop("창 설정 오류 — 돌연변이가 엿보는 달 ", PEEK, " 이 τ_D 뒤다")
  ASOF <- META$months$asof[match(c(WIN, PEEK), META$months$ym)]
  if (anyNA(ASOF)) stop("결합용 뷰에 창 · 엿보는 달이 없다: ", paste(c(WIN, PEEK)[is.na(ASOF)], collapse = ","))
  START <- as.Date(paste0(WIN[1L], "01"), "%Y%m%d")
  CAL <- local({                                                     # RAWDATA 거래일 달력(창만 · 셀 경로 패널과 같은 원천)
    lo <- START; hi <- month_end(WIN[length(WIN)])
    q <- dplyr::filter(arrow::open_dataset(file.path(ROOT, ".cache", "rawdata.parquet")), Date >= lo, Date <= hi)
    sort(unique(as.Date(dplyr::collect(dplyr::distinct(dplyr::select(q, Date)))$Date)))
  })
  ME_chr <- vapply(WIN, function(ym) format(max(CAL[format(CAL, "%Y%m") == ym])), character(1), USE.NAMES = FALSE)
  ME <- as.Date(ME_chr)
  DIAG_REPO <- file.path(dirname(ENG), "fce_diag.csv")
  H0 <- c(engine = md5(ENG), diag = md5(DIAG_REPO))
  cat(sprintf("[test_fc_engine_gen] 루트 %s · 창 %s ~ %s(월말 %d · 거래일 %d) · 절단 t %s · 엿보는 달 %s ≤ τ_D %s · 뷰 빌드 %s\n",
              ROOT, ME_chr[1L], ME_chr[length(ME_chr)], length(WIN), length(CAL), paste(CUTS, collapse = ","), PEEK, format(TAU_D),
              META$built_at %||% "?"))
  CUT <- setNames(lapply(CUTS, mk_cut), CUTS)

  cat("=== 1. 절단 불변성 — FC_TOTAL_EW(실제 엔진) ===\n")
  RC <- check1(ENG, "real")
  F0 <- RC$full$FACTORS; D0 <- RC$full$diag
  chk(sprintf("1a 전체 실행 — FACTORS(Date · Ticker · Score) · Date = 창 월말 거래일 %d개 = 그 달 뷰 as-of · 날짜마다 가족 %d개 전부 산출(모든 가족 경로)",
              length(WIN), length(FAMS)),
      is.na(RC$full$err) && !is.null(F0) && identical(names(F0), c("Date", "Ticker", "Score")) && inherits(F0$Date, "Date") &&
        identical(sort(unique(format(F0$Date))), ME_chr) && identical(ME_chr, ASOF[seq_along(WIN)]) &&
        identical(as.integer(RC$full$n_fam_declared), length(FAMS)) && !is.null(D0) && nrow(D0) == length(WIN) &&
        all(D0$n_families_present == length(FAMS)),
      sprintf("%s행 · 날짜 %s · 가족(선언 %s · 날짜별 %s)", fmt(nrow(F0)), paste(sort(unique(format(F0$Date))), collapse = ","),
              fmt(RC$full$n_fam_declared), paste(D0$n_families_present, collapse = "/")))
  for (tym in CUTS) {
    p <- RC$per[[tym]]
    chk(sprintf("1b t = %s — 뷰 사본(≤t) + RAWDATA(≤t)로 돌린 FACTORS = 전체 실행 Date ≤ t 부분(비트 동일)", tym), p$harness && p$same,
        sprintf("사본 달 파일 %d · 절단 확인 %s · 접근자 감싸기 %d회 · 요청 %s · 행 %s = %s · %s", CUT[[tym]]$n_files, CUT[[tym]]$ok, p$hooked,
                paste(p$req, collapse = ","), fmt(p$n_full), fmt(p$n_cut), p$why))
  }
  ok1c <- FALSE
  if (!is.null(F0)) {
    A <- F0[F0$Date <= month_end(CUTS[length(CUTS)]), , drop = FALSE]; B <- A
    i <- which(B$Score != 0)[1L]; B$Score[i] <- B$Score[i] * (1 + .Machine$double.eps)
    ok1c <- same_bits(A, A) && !same_bits(A, B) && isTRUE(all.equal(A$Score, B$Score)) && !identical(A$Score[i], B$Score[i])
  }
  chk("1c 비교기 = 비트 비교 — 같은 표는 같다 · 점수 1개를 1 ulp 바꾸면 다르다(all.equal 은 같다고 하는 차이)", ok1c)

  cat("=== 2. 양성 대조 — 다음 달 뷰를 읽는 돌연변이 사본(소스 텍스트 치환) ===\n")
  TXT <- rd_txt(ENG)
  MUT <- file.path(TMP, "mutant", "engine.R"); dir.create(dirname(MUT), recursive = TRUE, showWarnings = FALSE)
  m <- TXT; for (s in SUBS) m <- sub(s[["from"]], s[["to"]], m, fixed = TRUE)
  back <- m; for (s in rev(SUBS)) back <- sub(s[["to"]], s[["from"]], back, fixed = TRUE)
  writeBin(charToRaw(m), MUT)
  cnt <- vapply(SUBS, function(s) c(n_fixed(TXT, s[["from"]]), n_fixed(TXT, s[["to"]]), n_fixed(m, s[["from"]]), n_fixed(m, s[["to"]])), integer(4))
  parsed <- !inherits(tryCatch(parse(file = MUT, keep.source = FALSE), error = function(e) e), "error")
  MUT_MD5 <- md5(MUT)
  chk("2a 치환 성사 — 두 곳 각각 원본 1곳 → 사본 0곳 · 새 문구 원본 0곳 → 사본 1곳 · 되돌리면 원본과 바이트 동일 · 사본은 저장소 밖 · parse 통과",
      all(cnt[1L, ] == 1L) && all(cnt[2L, ] == 0L) && all(cnt[3L, ] == 0L) && all(cnt[4L, ] == 1L) && identical(back, TXT) &&
        identical(rd_txt(MUT), m) && !under_root(MUT) && parsed && !identical(MUT_MD5, md5(ENG)),
      sprintf("사본 %s (md5 %s) · 횟수 %s", MUT, MUT_MD5, paste(cnt, collapse = "")))
  MC <- check1(MUT, "mutant")
  MF <- MC$full$FACTORS
  nd <- function(x) { x$Date <- as.Date(format(x$Date)); x }       # 날짜 저장형(정수 · 실수) 차이만 지운다
  shift <- if (is.null(MF) || is.null(F0)) FALSE else vapply(seq_len(length(WIN) - 1L), function(i) {
    a <- MF[format(MF$Date) == ME_chr[i], , drop = FALSE]; b <- F0[format(F0$Date) == ME_chr[i + 1L], , drop = FALSE]
    b$Date <- rep(ME[i], nrow(b)); nrow(a) > 0L && same_bits(nd(a), b)
  }, logical(1))
  chk("2b 돌연변이는 살아 있다 — 사본 자신이 돌았다(md5) · 전체 실행 성공 · 날짜표는 그대로 · t 달 점수 = 실제 엔진의 t+1 달 점수(다음 달 뷰를 정확히 읽었다)",
      is.na(MC$full$err) && !is.null(MF) && identical(MC$full$engine_md5, MUT_MD5) && identical(sort(unique(format(MF$Date))), ME_chr) && all(shift),
      sprintf("다음 달 점수와 비트 동일한 달 %d/%d", sum(shift), length(WIN) - 1L))
  hm <- vapply(MC$per, function(p) p$harness && identical(p$md5, MUT_MD5), logical(1))
  br <- vapply(MC$per, function(p) !p$same, logical(1))
  chk(sprintf("2c 돌연변이가 1번에서 실패 — 절단 장치 정상(사본 절단 · 접근자 감싸기 · 사본 엔진 실행)인 채로 절단 t %d개 모두 깨진다", length(CUTS)),
      !MC$ok && all(hm) && all(br),
      paste(sprintf("t=%s: %s(요청 %s)", CUTS, vapply(MC$per, function(p) p$why, ""), vapply(MC$per, function(p) paste(p$req, collapse = ","), "")),
            collapse = "\n             "))

  H1 <- c(engine = md5(ENG), diag = md5(DIAG_REPO))
  chk("H 저장소 무수정 — 엔진 md5 전후 같음 · 엔진 폴더 진단 파일 전후 같음(진단은 임시 폴더로)", identical(H0, H1),
      sprintf("engine %s · fce_diag.csv %s", H1[["engine"]], H1[["diag"]]))
  NULL
}, error = function(e) conditionMessage(e))
if (!is.null(err_main)) chk("시험 실행", FALSE, paste("멈춤:", err_main))
if (!is.null(TMP) && dir.exists(TMP)) unlink(TMP, recursive = TRUE)
cat(sprintf("\n== test_fc_engine_gen: PASS %d · FAIL %d · %.0f초 ==\n", PASS, FAIL, as.numeric(difftime(Sys.time(), T0, units = "secs"))))
cat(toJSON(list(test = "test_fc_engine_gen", pass = PASS, fail = FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0L) quit(save = "no", status = 1L)
