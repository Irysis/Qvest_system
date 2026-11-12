#!/usr/bin/env Rscript
#==============================================================================
# test_fc_combiner_gen.R — 결합기 T1 자체 사양 엔진(FC_*_ICW) PIT 값 검사: 절단 불변성 + 돌연변이 양성 대조
#   생성기 02_Infrastructure/factor_db/fc_combiner_gen.R · 설계 04_Research/01_reports/factor_spine_design_20261111/README.md §3-7 시험 1 · 2 · §4-2 T1
#   T0 시험(08_Tests/factor_db/test_fc_engine_gen.R)과 같은 틀에 T1 이 새로 읽는 길(IC 원장 — compute_rolling_ic_all)을 더했다.
#   그 밖의 시험 묶음은 없다(도훈 11-12 '테스트 좀 그만하자' · 11-13 '테스트에 갇히지 말고').
#
# 1 절단 불변성 — 대상 FC_TOTAL_ICW(구성원 334 · 가족 14개 경로 전부 · IC 가중) · 창 = τ_D 이전 월말 4개(2022-08 ~ 11)
#   전체 실행 = 실제 결합용 뷰 + IC 원장 스냅샷(시험 시작 때 바이트 복사 — 시험 중 원장이 갱신돼도 거짓 실패가 나지 않게).
#   절단 실행(t = 2022-08 · 09 · 10) = 그 시점의 세계:
#     결합용 뷰 사본 = t 이하 달 파일 + t 이하로 자른 메타 · 부호표 · 커버리지(T0 시험과 같다)
#     IC 원장 사본 = Usable_Date ≤ t 달 끝인 행만(그 시점에 알 수 있던 IC) · RAWDATA(거래일 달력)도 t 달 끝까지
#   엔진의 최상위 sys.source 두 곳만 가로챈다 — factor_combinable.R(fc_load_month 의 저장 폴더를 사본으로) ·
#     factor_db_connector.R(IC 원장 경로 FACTOR_IC_MONTHLY_PATH 를 사본으로 · 캐시 비움). 엔진 텍스트 · 접근자 코드는 그대로.
#   판정 = 절단 실행 FACTORS 가 전체 실행의 Date ≤ t 부분과 비트 동일.
# 2 양성 대조 — 엔진 소스 텍스트 치환 사본 둘(저장소 밖 · 치환 성사 단정):
#   M1 뷰 = 다음 달 결합용 뷰를 읽고 날짜표는 이번 달(T0 시험과 같은 돌연변이)
#   M2 IC = IC 를 다음 달 끝 as-of 로 읽는다(이번 달 IC = 다음 달 수익을 쓴 값을 가중에 넣는다 — 미래 참조)
#   둘 다 살아 있어야 하고(실제 엔진과 점수가 다르다) 1번에서 절단 t 모두 깨져야 한다.
# 격리: 임시 파일은 저장소 밖(tempdir()) · 저장소 무수정 전후 md5 · 성과 계산 없음(점수 비교만) · 엔진 실행 = 자식 Rscript 하나씩.
# 쓰기(저장소 루트): Rscript 08_Tests/factor_db/test_fc_combiner_gen.R → 마지막 줄 {"test":"test_fc_combiner_gen","pass":N,"fail":M}
#==============================================================================

## ── 자식 모드 — 엔진 1회 실행(셀 경로 기저 엔진과 같은 꼴) · 결과는 RDS 로 ────────────────────────────────
if (identical(commandArgs(trailingOnly = TRUE)[1L], "--child")) local({
  job <- readRDS(commandArgs(trailingOnly = TRUE)[2L])
  t0 <- Sys.time()
  hk <- new.env(parent = emptyenv()); hk$n_view <- 0L; hk$n_ic <- 0L; hk$req <- character(0)
  run_env <- new.env(parent = globalenv())
  run_env$RAWDATA <- data.table::data.table(Date = job$dates)
  run_env$.RP_START_DATE <- job$start
  run_env$sys.source <- function(file, envir = baseenv(), ...) {
    base::sys.source(file, envir = envir, ...)
    if (!is.null(job$view_dir) && identical(basename(file), "factor_combinable.R") && exists("fc_load_month", envir = envir, inherits = FALSE)) {
      f0 <- get("fc_load_month", envir = envir, inherits = FALSE); vd <- job$view_dir
      base::assign("fc_load_month", function(sig_date, ..., dir = NULL) {
        if (!is.null(dir)) stop("[절단 시험] 엔진이 저장 폴더(dir)를 직접 넘겼다 — 절단 사본으로 돌릴 수 없다")
        hk$req <- c(hk$req, format(as.Date(sig_date), "%Y%m"))
        f0(sig_date, ..., dir = vd)
      }, envir = envir)
      hk$n_view <- hk$n_view + 1L
    }
    if (identical(basename(file), "factor_db_connector.R") && exists("compute_rolling_ic_all", envir = envir, inherits = FALSE)) {
      base::assign("FACTOR_IC_MONTHLY_PATH", job$ic_path, envir = envir)
      base::assign(".fdc_ic_hist", NULL, envir = envir)
      hk$n_ic <- hk$n_ic + 1L
    }
    invisible(NULL)
  }
  dir.create(job$diag_dir, recursive = TRUE, showWarnings = FALSE)
  options(fce.diag_dir = job$diag_dir)
  err <- tryCatch({ sys.source(job$engine, envir = run_env); NA_character_ }, error = function(e) conditionMessage(e))
  FX <- if (exists("FACTORS", envir = run_env, inherits = FALSE)) as.data.frame(get("FACTORS", envir = run_env, inherits = FALSE)) else NULL
  dg <- file.path(job$diag_dir, "fce_diag.csv")
  saveRDS(list(err = err, FACTORS = FX, diag = if (file.exists(dg)) utils::read.csv(dg, stringsAsFactors = FALSE) else NULL,
               n_fam_declared = length(get0(".FCE_FAMILIES", envir = run_env, inherits = FALSE)), hooked_view = hk$n_view, hooked_ic = hk$n_ic,
               req = hk$req, engine_md5 = unname(tools::md5sum(job$engine)), secs = as.numeric(difftime(Sys.time(), t0, units = "secs"))), job$out)
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
same_bits <- function(a, b) {
  if (is.null(a) || is.null(b)) return(FALSE)
  a <- as.data.frame(a); b <- as.data.frame(b)
  identical(names(a), names(b)) && nrow(a) == nrow(b) &&
    all(vapply(names(a), function(k) identical(a[[k]], b[[k]], num.eq = FALSE), logical(1)))
}
diff_desc <- function(a, b) {
  if (is.null(a) || is.null(b)) return("한쪽 산출 없음")
  da <- sort(unique(format(a$Date))); db <- sort(unique(format(b$Date)))
  if (!identical(da, db)) return(sprintf("날짜가 다르다(전체 ≤t %s | 절단 %s)", paste(da, collapse = ","), if (length(db)) paste(db, collapse = ",") else "없음"))
  if (nrow(a) != nrow(b)) return(sprintf("행 수가 다르다(%s | %s)", fmt(nrow(a)), fmt(nrow(b))))
  sprintf("값이 다르다(%s행)", fmt(sum(a$Ticker != b$Ticker | a$Score != b$Score, na.rm = TRUE)))
}

## 시험 설정(성과를 읽지 않는 시험 매개 — 연구 결정 아님 · T0 시험과 같은 창)
TAU_D <- as.Date("2022-12-31")
WIN   <- c("202208", "202209", "202210", "202211")
CUTS  <- WIN[-length(WIN)]
SUBS_M1 <- list(
  c(from = '.fce_fc$fc_load_month(.fce_d, direction = "registry"',
    to   = '.fce_fc$fc_load_month(seq(as.Date(format(.fce_d, "%Y-%m-01")), by = "month", length.out = 3L)[3L] - 1L, direction = "registry"'),
  c(from = '.fce_asof <- as.Date(.fce_in$asof)',
    to   = '.fce_asof <- .fce_d'))
SUBS_M2 <- list(
  c(from = '.fce_ic$compute_rolling_ic_all(.fce_asof, .FCE_IC_MIN, .FCE_IC_MAX)',
    to   = '.fce_ic$compute_rolling_ic_all(seq(as.Date(format(.fce_asof, "%Y-%m-01")), by = "month", length.out = 3L)[3L] - 1L, .FCE_IC_MIN, .FCE_IC_MAX)'))
TMP <- NULL

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
  ## IC 원장 사본 = Usable_Date ≤ t 달 끝
  icp <- file.path(TMP, sprintf("ic_le_%s.parquet", tym))
  write_parquet(ICF[Usable_Date <= month_end(tym)], icp)
  rx <- paste0("^", gsub(".", "[.]", sprintf(ST$month_file, "([0-9]{6})"), fixed = TRUE), "$")
  mf <- sort(sub(rx, "\\1", list.files(d, pattern = rx)))
  M2 <- fromJSON(file.path(d, ST$meta_file), simplifyVector = TRUE)
  I2 <- as.data.table(read_parquet(icp)); I2[, Usable_Date := as.Date(Usable_Date)]
  ok <- identical(mf, keep) &&
    all(vapply(keep, function(ym) identical(md5(file.path(d, sprintf(ST$month_file, ym))), md5(file.path(VIEW, sprintf(ST$month_file, ym)))), logical(1))) &&
    identical(M2$stored_direction, META$stored_direction) && identical(max(M2$months$ym), tym) &&
    nrow(I2) == ICF[Usable_Date <= month_end(tym), .N] && max(I2$Usable_Date) <= month_end(tym) && nrow(I2) < nrow(ICF)
  list(dir = d, ic = icp, ok = ok, n_files = length(mf), n_ic = nrow(I2))
}

run_job <- function(tag, engine, dates, view_dir = NULL, ic_path) {
  jd <- file.path(TMP, tag); dir.create(jd, recursive = TRUE, showWarnings = FALSE)
  job <- list(engine = engine, dates = dates, start = START, view_dir = view_dir, ic_path = ic_path,
              diag_dir = file.path(jd, "diag"), out = file.path(jd, "res.rds"))
  jf <- file.path(jd, "job.rds"); saveRDS(job, jf)
  t1 <- Sys.time()
  o <- suppressWarnings(system2(RS, c(shQuote(SELF), "--child", shQuote(jf)), stdout = TRUE, stderr = TRUE))
  r <- if (file.exists(job$out)) readRDS(job$out) else
    list(err = sprintf("자식 실행 결과 없음(rc %s): %s", attr(o, "status") %||% "?", paste(utils::tail(o, 3L), collapse = " | ")),
         FACTORS = NULL, hooked_view = 0L, hooked_ic = 0L, req = character(0), engine_md5 = NA_character_)
  r$wall <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  s <- grep("FACTORS [0-9]+|패널 마지막 달", o, value = TRUE, useBytes = TRUE)
  cat(sprintf("    · %-16s %5.1f초 · %s\n", tag, r$wall, if (!is.na(r$err)) paste("엔진 멈춤:", r$err) else paste(trimws(s), collapse = " / ")))
  r
}

inv_eval <- function(full, cr, cut, tym) {
  harness <- isTRUE(cut$ok) && identical(as.integer(cr$hooked_view), 1L) && identical(as.integer(cr$hooked_ic), 1L) && length(cr$req) > 0L
  F_le <- if (!is.null(full$FACTORS)) full$FACTORS[full$FACTORS$Date <= month_end(tym), , drop = FALSE] else NULL
  same <- is.na(full$err) && is.na(cr$err) && same_bits(F_le, cr$FACTORS)
  why <- if (!is.na(full$err)) paste("전체 실행 멈춤:", full$err) else if (!is.na(cr$err)) paste("절단 실행 멈춤:", cr$err) else
    if (same) "비트 동일" else diff_desc(F_le, cr$FACTORS)
  list(harness = harness, same = same, why = why, n_full = if (is.null(F_le)) NA_integer_ else nrow(F_le),
       n_cut = if (is.null(cr$FACTORS)) NA_integer_ else nrow(cr$FACTORS), req = cr$req, md5 = cr$engine_md5)
}
check1 <- function(engine, tag) {
  cat(sprintf("  [%s] %s (md5 %s)\n", tag, engine, md5(engine)))
  full <- run_job(paste0(tag, "_full"), engine, CAL, VIEW_FULL, IC_FULL)
  per <- setNames(lapply(CUTS, function(tym)
    inv_eval(full, run_job(sprintf("%s_le_%s", tag, tym), engine, CAL[CAL <= month_end(tym)], CUT[[tym]]$dir, CUT[[tym]]$ic), CUT[[tym]], tym)), CUTS)
  list(full = full, per = per, ok = all(vapply(per, function(p) p$harness && p$same, logical(1))))
}
mk_mutant <- function(txt, subs, tag) {
  mp <- file.path(TMP, paste0("mutant_", tag), "engine.R"); dir.create(dirname(mp), recursive = TRUE, showWarnings = FALSE)
  m <- txt; for (s in subs) m <- sub(s[["from"]], s[["to"]], m, fixed = TRUE)
  back <- m; for (s in rev(subs)) back <- sub(s[["to"]], s[["from"]], back, fixed = TRUE)
  writeBin(charToRaw(m), mp)
  cnt <- vapply(subs, function(s) c(n_fixed(txt, s[["from"]]), n_fixed(txt, s[["to"]]), n_fixed(m, s[["from"]]), n_fixed(m, s[["to"]])), integer(4))
  parsed <- !inherits(tryCatch(parse(file = mp, keep.source = FALSE), error = function(e) e), "error")
  ok <- all(cnt[1L, ] == 1L) && all(cnt[2L, ] == 0L) && all(cnt[3L, ] == 0L) && all(cnt[4L, ] == 1L) && identical(back, txt) &&
    identical(rd_txt(mp), m) && !under_root(mp) && parsed && !identical(md5(mp), md5(ENG))
  list(path = mp, ok = ok, md5 = md5(mp), cnt = paste(cnt, collapse = ""))
}

err_main <- tryCatch({
  ROOT <- local({ r <- Sys.getenv("CLAUDE_PROJECT_DIR", ""); if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", ""); gsub("\\\\", "/", r) })
  if (!nzchar(ROOT) || !dir.exists(ROOT)) stop("CLAUDE_PROJECT_DIR · QM_ROOT 미설정 또는 없는 폴더")
  Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
  SELF <- local({ a <- commandArgs(FALSE); f <- sub("^--file=", "", a[startsWith(a, "--file=")])
    if (length(f) != 1L) stop("이 시험 파일 경로를 읽지 못했다(Rscript 로 실행할 것)")
    normalizePath(gsub("~+~", " ", f, fixed = TRUE), winslash = "/", mustWork = TRUE) })
  RS <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  ENG <- file.path(ROOT, "04_Research", "strategies", "FC_TOTAL_ICW", "engine.R")
  if (!file.exists(ENG)) stop("대상 엔진 없음: ", ENG)
  FAMS <- fromJSON(file.path(dirname(ENG), "own_spec.json"), simplifyVector = TRUE)$core$families
  RT <- unique(tolower(sub("/+$", "", c(ROOT, normalizePath(ROOT, winslash = "/")))))
  under_root <- function(p) { q <- tolower(normalizePath(p, winslash = "/", mustWork = FALSE)); any(q == RT | startsWith(q, paste0(RT, "/"))) }
  TMP <- file.path(normalizePath(tempdir(), winslash = "/"), sprintf("tfc_%d", Sys.getpid()))
  if (under_root(TMP)) stop("임시 폴더가 저장소 안이다: ", TMP)
  dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
  ST <- fromJSON(file.path(ROOT, "06_Registry", "factor_combinable.json"), simplifyVector = TRUE)$storage
  VIEW <- file.path(ROOT, ST$dir)
  META <- fromJSON(file.path(VIEW, ST$meta_file), simplifyVector = TRUE)
  TB <- list(signs_file = as.data.table(read_parquet(file.path(VIEW, ST$signs_file), mmap = FALSE)),
             coverage_file = as.data.table(read_parquet(file.path(VIEW, ST$coverage_file), mmap = FALSE)))
  ## IC 원장 스냅샷(바이트 복사) — 전체 실행도 이 사본으로(시험 중 갱신에 흔들리지 않게)
  IC_SRC <- file.path(ROOT, ".cache", "factor_db", "factor_ic_monthly.parquet")
  IC_FULL <- file.path(TMP, "ic_full.parquet")
  if (!isTRUE(file.copy(IC_SRC, IC_FULL))) stop("IC 원장 복사 실패")
  if (!identical(md5(IC_FULL), md5(IC_SRC))) stop("IC 원장 사본 md5 ≠ 원본(복사 중 갱신?)")
  ICF <- as.data.table(read_parquet(IC_FULL, mmap = FALSE)); ICF[, `:=`(Date = as.Date(Date), Usable_Date = as.Date(Usable_Date))]
  VIEW_FULL <- NULL                                                   # 전체 실행 = 실제 결합용 뷰
  PEEK <- format(month_end(WIN[length(WIN)]) + 1L, "%Y%m")
  if (month_end(PEEK) > TAU_D) stop("창 설정 오류 — 돌연변이가 엿보는 달 ", PEEK, " 이 τ_D 뒤다")
  ASOF <- META$months$asof[match(c(WIN, PEEK), META$months$ym)]
  if (anyNA(ASOF)) stop("결합용 뷰에 창 · 엿보는 달이 없다")
  START <- as.Date(paste0(WIN[1L], "01"), "%Y%m%d")
  CAL <- local({
    lo <- START; hi <- month_end(WIN[length(WIN)])
    q <- dplyr::filter(arrow::open_dataset(file.path(ROOT, ".cache", "rawdata.parquet")), Date >= lo, Date <= hi)
    sort(unique(as.Date(dplyr::collect(dplyr::distinct(dplyr::select(q, Date)))$Date)))
  })
  ME_chr <- vapply(WIN, function(ym) format(max(CAL[format(CAL, "%Y%m") == ym])), character(1), USE.NAMES = FALSE)
  DIAG_REPO <- file.path(dirname(ENG), "fce_diag.csv")
  H0 <- c(engine = md5(ENG), diag = md5(DIAG_REPO), ic = md5(IC_SRC))
  cat(sprintf("[test_fc_combiner_gen] 루트 %s · 창 %s ~ %s(월말 %d · 거래일 %d) · 절단 t %s · 엿보는 달 %s ≤ τ_D · IC 원장 %s행(md5 %s)\n",
              ROOT, ME_chr[1L], ME_chr[length(ME_chr)], length(WIN), length(CAL), paste(CUTS, collapse = ","), PEEK,
              fmt(nrow(ICF)), substr(H0[["ic"]], 1, 8)))
  CUT <- setNames(lapply(CUTS, mk_cut), CUTS)

  cat("=== 1. 절단 불변성 — FC_TOTAL_ICW(실제 엔진 · 뷰 + IC 원장) ===\n")
  RC <- check1(ENG, "real")
  F0 <- RC$full$FACTORS; D0 <- RC$full$diag
  chk(sprintf("1a 전체 실행 — FACTORS(Date · Ticker · Score) · Date = 창 월말 %d개 = 그 달 뷰 as-of · IC 접근자 1회 적재 · 날짜마다 양의 가중 가족 ≥ 1 · 가중 대체(T0) 없음",
              length(WIN)),
      is.na(RC$full$err) && !is.null(F0) && identical(names(F0), c("Date", "Ticker", "Score")) && inherits(F0$Date, "Date") &&
        identical(sort(unique(format(F0$Date))), ME_chr) && identical(ME_chr, ASOF[seq_along(WIN)]) &&
        identical(as.integer(RC$full$hooked_ic), 1L) && identical(as.integer(RC$full$n_fam_declared), length(FAMS)) &&
        !is.null(D0) && nrow(D0) == length(WIN) && all(D0$n_families_weighted >= 1) && !any(as.logical(D0$fallback_t0)) &&
        all(F0$Score >= -1 & F0$Score <= 1),
      sprintf("%s행 · 날짜 %s · 양의 가중 가족 %s · 양의 가중 구성원 %s", fmt(nrow(F0)), paste(sort(unique(format(F0$Date))), collapse = ","),
              paste(D0$n_families_weighted, collapse = "/"), paste(D0$n_pos_weight, collapse = "/")))
  for (tym in CUTS) {
    p <- RC$per[[tym]]
    chk(sprintf("1b t = %s — 뷰 사본(≤t) + IC 원장 사본(Usable_Date ≤ t) + RAWDATA(≤t)로 돌린 FACTORS = 전체 실행 Date ≤ t 부분(비트 동일)", tym),
        p$harness && p$same,
        sprintf("사본 달 %d · IC 행 %s · 절단 확인 %s · 요청 %s · 행 %s = %s · %s", CUT[[tym]]$n_files, fmt(CUT[[tym]]$n_ic), CUT[[tym]]$ok,
                paste(p$req, collapse = ","), fmt(p$n_full), fmt(p$n_cut), p$why))
  }
  ok1c <- FALSE
  if (!is.null(F0)) {
    A <- F0[F0$Date <= month_end(CUTS[length(CUTS)]), , drop = FALSE]; B <- A
    i <- which(B$Score != 0)[1L]; B$Score[i] <- B$Score[i] * (1 + .Machine$double.eps)
    ok1c <- same_bits(A, A) && !same_bits(A, B) && isTRUE(all.equal(A$Score, B$Score)) && !identical(A$Score[i], B$Score[i])
  }
  chk("1c 비교기 = 비트 비교 — 같은 표는 같다 · 점수 1개를 1 ulp 바꾸면 다르다", ok1c)

  TXT <- rd_txt(ENG)
  for (mm in list(list(tag = "M1_view", subs = SUBS_M1, what = "다음 달 결합용 뷰를 읽고 날짜표는 이번 달"),
                  list(tag = "M2_ic", subs = SUBS_M2, what = "IC 를 다음 달 끝 as-of 로 읽는다(이번 달 IC = 다음 달 수익)"))) {
    cat(sprintf("=== 2. 양성 대조 %s — %s ===\n", mm$tag, mm$what))
    MU <- mk_mutant(TXT, mm$subs, mm$tag)
    chk(sprintf("2a %s 치환 성사 — 각 자리 원본 1곳 → 사본 0곳 · 새 문구 원본 0 → 사본 1 · 되돌리면 원본과 바이트 동일 · 저장소 밖 · parse 통과", mm$tag),
        MU$ok, sprintf("사본 %s (md5 %s) · 횟수 %s", MU$path, MU$md5, MU$cnt))
    MC <- check1(MU$path, mm$tag)
    MF <- MC$full$FACTORS
    alive <- is.na(MC$full$err) && !is.null(MF) && identical(MC$full$engine_md5, MU$md5) && !same_bits(MF, F0)
    chk(sprintf("2b %s 는 살아 있다 — 사본 자신이 돌았다(md5) · 전체 실행 성공 · 점수가 실제 엔진과 다르다", mm$tag), alive,
        if (!is.null(MF) && !is.null(F0)) diff_desc(F0, MF) else paste("산출 없음:", MC$full$err))
    hm <- vapply(MC$per, function(p) p$harness && identical(p$md5, MU$md5), logical(1))
    br <- vapply(MC$per, function(p) !p$same, logical(1))
    chk(sprintf("2c %s 가 1번에서 실패 — 절단 장치 정상인 채로 절단 t %d개 모두 깨진다", mm$tag, length(CUTS)), !MC$ok && all(hm) && all(br),
        paste(sprintf("t=%s: %s", CUTS, vapply(MC$per, function(p) p$why, "")), collapse = "\n             "))
  }

  H1 <- c(engine = md5(ENG), diag = md5(DIAG_REPO), ic = md5(IC_SRC))
  chk("H 저장소 무수정 — 엔진 md5 · 엔진 폴더 진단 파일 · IC 원장 전후 같음", identical(H0, H1),
      sprintf("engine %s · fce_diag.csv %s · ic %s", H1[["engine"]], H1[["diag"]], H1[["ic"]]))
  NULL
}, error = function(e) conditionMessage(e))
if (!is.null(err_main)) chk("시험 실행", FALSE, paste("멈춤:", err_main))
if (!is.null(TMP) && dir.exists(TMP)) unlink(TMP, recursive = TRUE)
cat(sprintf("\n== test_fc_combiner_gen: PASS %d · FAIL %d · %.0f초 ==\n", PASS, FAIL, as.numeric(difftime(Sys.time(), T0, units = "secs"))))
cat(toJSON(list(test = "test_fc_combiner_gen", pass = PASS, fail = FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0L) quit(save = "no", status = 1L)
