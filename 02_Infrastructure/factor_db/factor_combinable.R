#!/usr/bin/env Rscript
#==============================================================================
# factor_combinable.R — 결합용 팩터 뷰(월간 저장형 · 일간 즉석) + 자동 갱신 빌더
#   2026-11-09 도훈 '만들기 · 이론 방향 선택지도 추가(C13 해석 확장)' + '결합용 뷰도 자동 업데이트 되게끔 만들어줘'
#   decision_register FACTOR-COMBINABLE-VIEW-20261109 · 설정 정본 06_Registry/factor_combinable.json(출처 전부)
#
# 무엇을 하나(매 시점 횡단면 · PIT):
#   ① 값 = 정본 접근자 load_month_factors(direction = "registry", coverage_min = 0) — 등록부 방향으로 정렬된 z
#      (팩터 DB parquet 직접 읽기 없음 · C15)
#   ② 변환 = 팩터별 횡단면 순위 → [−1, 1](동순위 평균) — Gu, Kelly & Xiu (2020) RFS 33(5):2223-2273
#   ③ 저장 = .cache/factor_combinable/fc_YYYYMM.parquet(wide Ticker × 팩터 · int16 = 값 × 10000 · 결측 = NA)
#   ④ 방향 = 저장값은 저장 원값 방향(v1.1 · 정렬된 순위 × 빌드 때 등록부 부호 s_reg — 순위는 부호를 뒤집으면 정확히 −1 배라
#      되돌리기가 정확하다 · 시험 P2). 읽을 때 부호표 fc_signs.parquet 의 부호를 곱한다: registry = s_reg(기대수익) ·
#      ic_asof = s_ic(그 달 as-of 36개월 IC → 등록부 → +1) · defensive = s_def(등록부 방어 방향 · 위험 · 유동성 계열만).
#      등록부 방향이 바뀌어도 월 파일을 다시 지을 필요가 없다 — 부호표는 빌드마다 전부 다시 만든다
#      (v1.0 은 등록부 방향으로 저장해, 등록부가 바뀌면 증분 빌드가 옛 방향 달과 새 방향 달을 섞었다 · TWO-VIEWS-20261109)
#   ⑤ 읽기 = fc_load_month(sig_date, direction, factors, tickers, missing, dedup, family) — tickers 를 주면 그 안에서 다시
#      순위(저장값은 원값의 단조 변환이라 부분집합 순위가 정확) · 결측 0(= 횡단면 중앙값) · 계열 평균 · 별칭 접기
#   ⑥ 갱신 = 증분 — 원천 월 파일(크기 · 수정 시각)이 바뀐 달 + 가장 최근 달 · 부호표 · 커버리지는 매번 다시
#   일간 = fc_daily(): load_daily_factors(direction) → 날짜별 같은 변환(저장 없음 — 쓰는 달만 즉석)
#
# 쓰기: Rscript 02_Infrastructure/factor_db/factor_combinable.R --build [--full] [--out DIR] [--months 201006,201007]
#   source() 하면 함수만 싣는다(시험 = 08_Tests/factor_db/test_factor_combinable.R).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
FC_BUILDER <- "factor_combinable.R v1.1"
FC_STORED <- "stored_raw_value"      # 저장값 방향(v1.1) — 이 값이 아닌 저장본은 읽지 않고(멈춤) 빌드는 전부 다시 짓는다

fc_root <- function() {
  r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) stop("[fc] QM_ROOT · CLAUDE_PROJECT_DIR 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
}

fc_config <- function(root = fc_root()) {
  p <- file.path(root, "06_Registry", "factor_combinable.json")
  if (!file.exists(p)) stop("[fc] 설정 없음: ", p)
  cfg <- fromJSON(p, simplifyVector = TRUE)
  if (!identical(cfg$transform$rule, "cross_sectional_rank_to_pm1") || !identical(cfg$transform$ties, "average"))
    stop("[fc] transform 어휘 밖(cross_sectional_rank_to_pm1 · ties average 만)")
  if (!cfg$missing$default %in% cfg$missing$options || !cfg$direction$default %in% cfg$direction$options)
    stop("[fc] missing · direction 기본값이 선택지 밖")
  sc <- suppressWarnings(as.numeric(cfg$storage$value_scale))
  if (length(sc) != 1L || !is.finite(sc) || sc <= 0 || sc > 32767) stop("[fc] storage.value_scale 판독 실패(int16 범위)")
  cfg
}

## ── 순수 변환 ───────────────────────────────────────────────────────────────
#' 횡단면 순위 → [−1, 1](동순위 평균 · 결측 유지). 값이 하나면 0(순위 정보 없음)
fc_rank_pm1 <- function(x) {
  ok <- !is.na(x)
  n <- sum(ok)
  out <- rep(NA_real_, length(x))
  if (n == 1L) out[ok] <- 0
  else if (n > 1L) out[ok] <- 2 * (frank(x[ok], ties.method = "average") - 1) / (n - 1) - 1
  out
}

#' 저장 원값 방향 순위 — 정렬된 값의 순위 × 그 정렬에 쓴 부호(s0 = ±1). 순위는 부호를 뒤집으면 정확히 −1 배(동순위 평균)라
#' fc_rank_pm1(저장 원값)과 같다(시험 P6)
fc_to_stored <- function(z_aligned, s0) {
  if (length(s0) != 1L || !s0 %in% c(-1L, 1L)) stop("[fc] 정렬 부호는 +1 · −1 하나여야 한다")
  fc_rank_pm1(z_aligned) * s0
}

#' 별칭 접기(열 단위) — 정본이 같은 패널에 있을 때만 별칭을 뺀다(이름을 바꾸지 않는다 · collapse_alias_rows 와 같은 규칙)
fc_alias_drop <- function(cols, resolve) {
  canon <- resolve(cols)
  drop <- cols[canon != cols & canon %in% cols]
  setdiff(cols, drop)
}

#' 계열 평균 — 계열마다 값이 있는 팩터의 평균(없으면 NA) · W 는 Ticker + 팩터 열(값 [−1, 1])
fc_family_scores <- function(W, cat_map) {
  cols <- setdiff(names(W), "Ticker")
  cm <- cat_map[cols]; cm <- cm[!is.na(cm)]
  out <- data.table(Ticker = W$Ticker)
  for (g in sort(unique(cm))) {
    m <- as.matrix(W[, names(cm)[cm == g], with = FALSE])
    k <- rowSums(!is.na(m))
    s <- rowSums(m, na.rm = TRUE)
    set(out, j = g, value = ifelse(k > 0L, s / pmax(k, 1L), NA_real_))
  }
  out
}

## ── 접근자 환경(정본 접근자 · 별칭 해석) ─────────────────────────────────────
.FC <- new.env(parent = emptyenv())
.fc_env <- function(root) {
  if (isTRUE(.FC$loaded) && identical(.FC$root, root)) return(.FC$e)
  e <- new.env(parent = globalenv())
  infra <- file.path(root, "02_Infrastructure")
  owd <- setwd(infra); on.exit(setwd(owd), add = TRUE)
  invisible(utils::capture.output(suppressMessages({
    sys.source(file.path(infra, "config.R"), envir = e, keep.source = FALSE)
    sys.source(file.path(infra, "factor_db", "factor_db_connector.R"), envir = e, keep.source = FALSE)
    sys.source(file.path(infra, "factor_db", "factor_dup_scan.R"), envir = e, keep.source = FALSE)
  })))
  .FC$e <- e; .FC$root <- root; .FC$loaded <- TRUE
  e
}

.fc_reg_signs <- function(reg) {
  if (is.null(reg) || !length(reg)) return(data.table(Factor_Name = character(0), s_reg = integer(0), s_def = integer(0), category = character(0)))
  sg <- function(d) if (identical(d, "lower_better")) -1L else if (identical(d, "higher_better")) 1L else NA_integer_
  data.table(Factor_Name = names(reg),
             s_reg = vapply(reg, function(x) if (identical(x$direction %||% "higher_better", "lower_better")) -1L else 1L, integer(1)),
             s_def = vapply(reg, function(x) if (length(x$direction_defensive) == 1L) sg(x$direction_defensive) else NA_integer_, integer(1)),
             category = vapply(reg, function(x) as.character(x$category %||% NA_character_)[1], character(1)))
}

## ── 빌드(월간 저장형 · 증분) ─────────────────────────────────────────────────
.fc_month_end <- function(ym) { d <- as.Date(paste0(ym, "01"), "%Y%m%d"); seq(d, by = "1 month", length.out = 2L)[2L] - 1L }

#' 빌드 잠금 — 같은 저장 폴더에 빌드 두 개가 동시에 쓰지 않게(일일 체인 [6e] 증분 · 수동/진행기 --full).
#' 잠금 = 폴더 생성(원자적). 다른 빌드가 쥐고 있으면 NULL(건너뜀 · CLI rc 5). max_age_h 보다 오래된 잠금은 죽은 빌드로 보고 넘겨받는다.
fc_lock <- function(out, max_age_h = 6) {
  lk <- file.path(out, ".build.lock")
  if (dir.exists(lk)) {
    age <- as.numeric(difftime(Sys.time(), file.info(lk)$mtime, units = "hours"))
    if (is.finite(age) && age < max_age_h) return(NULL)
    if (!.fc_rmdir(lk)) { warning("[fc] 묵은 잠금 폴더를 지우지 못했다 — 건너뛴다: ", lk); return(NULL) }
  }
  if (!dir.create(lk, showWarnings = FALSE)) return(NULL)
  writeLines(sprintf("pid=%d at=%s", Sys.getpid(), format(Sys.time(), "%Y-%m-%dT%H:%M:%S")), file.path(lk, "owner"))
  lk
}
fc_release <- function(lk) if (!.fc_rmdir(lk)) warning("[fc] 잠금 폴더를 지우지 못했다 — 다음 빌드가 6시간 건너뛴다: ", lk)

#' 폴더 지우기 — OneDrive 동기화 폴더는 수 초 안에 읽기 전용(R) 속성을 받고, R unlink 는 그 폴더를 조용히 남긴다.
#'   11-10 실측: 첫 전체 빌드 뒤 잠금 폴더가 남아 다음 빌드가 모두 건너뛰었고, 6시간 뒤 넘겨받기도 같은 unlink 라 영영 막힐 뻔했다
#'   (같은 함정 = 충실구현 레인 claim 폴더 · 0cacde89b). 남으면 속성을 풀고(Sys.chmod — Windows 에서는 읽기 전용 비트) 한 번 더 지운다.
.fc_rmdir <- function(p) {
  unlink(p, recursive = TRUE)
  if (dir.exists(p)) { Sys.chmod(p, "777", use_umask = FALSE); unlink(p, recursive = TRUE) }
  !dir.exists(p)
}

.fc_write_atomic <- function(tbl, path) {
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  write_parquet(tbl, tmp, compression = "zstd")
  if (file.exists(path) && !file.remove(path)) { unlink(tmp); stop("[fc] 기존 파일 제거 실패: ", path) }
  if (!file.rename(tmp, path)) stop("[fc] 이름 바꾸기 실패: ", path)
}

fc_build <- function(root = fc_root(), out = NULL, full = FALSE, months = NULL, verbose = TRUE) {
  t0 <- Sys.time()
  cfg <- fc_config(root); E <- .fc_env(root)
  out <- out %||% file.path(root, cfg$storage$dir)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  lk <- fc_lock(out)
  if (is.null(lk)) {
    if (verbose) cat("[fc] 다른 빌드가 잠금(.build.lock)을 쥐고 있다 — 건너뛴다\n")
    return(invisible(structure(list(skipped = "locked"), class = "fc_skipped")))
  }
  on.exit(fc_release(lk), add = TRUE)
  sc <- as.numeric(cfg$storage$value_scale)
  src <- list.files(E$FACTOR_DB_DIR, pattern = "^factor_db_[0-9]{6}\\.parquet$", full.names = TRUE)
  if (!length(src)) stop("[fc] 팩터 DB 월 파일 없음: ", E$FACTOR_DB_DIR)
  fi <- file.info(src)
  FP <- data.table(ym = sub("^factor_db_([0-9]{6})\\.parquet$", "\\1", basename(src)), size = as.numeric(fi$size),
                   mtime = format(fi$mtime, "%Y-%m-%dT%H:%M:%S"))
  setorder(FP, ym)
  meta_p <- file.path(out, cfg$storage$meta_file)
  old <- if (file.exists(meta_p)) tryCatch(fromJSON(meta_p, simplifyVector = TRUE), error = function(e) NULL) else NULL
  if (!is.null(old) && !identical(old$stored_direction, FC_STORED)) {
    if (verbose) cat(sprintf("[fc] 저장본 방향이 '%s'(현행 '%s' 아님) — 전부 다시 짓는다\n", old$stored_direction %||% "?", FC_STORED))
    full <- TRUE
  }
  OM <- if (!is.null(old$months)) as.data.table(old$months) else NULL
  have <- file.exists(file.path(out, sprintf(cfg$storage$month_file, FP$ym)))
  if (isTRUE(full) || is.null(OM)) todo <- FP$ym else {
    J <- merge(FP, OM[, .(ym, size_o = as.numeric(size), mtime_o = as.character(mtime))], by = "ym", all.x = TRUE)
    todo <- J[is.na(size_o) | size != size_o | mtime != mtime_o, ym]
    todo <- union(todo, FP$ym[!have])
    todo <- union(todo, max(FP$ym))                                     # 가장 최근 달은 매번(당월 파일은 매일 갱신된다)
  }
  if (!is.null(months)) todo <- intersect(as.character(months), FP$ym)
  todo <- sort(todo)
  if (verbose) cat(sprintf("[fc] 원천 월 %d · 다시 만들 달 %d%s\n", nrow(FP), length(todo), if (length(todo)) sprintf(" (%s ~ %s)", min(todo), max(todo)) else ""))
  NM <- list(); COV <- list()
  RS0 <- .fc_reg_signs(E$.load_registry())                              # 접근자가 정렬에 쓴 바로 그 등록부(같은 환경 캐시)
  for (ym in todo) {
    invisible(utils::capture.output(L0 <- E$load_month_factors(.fc_month_end(ym), coverage_min = 0, direction = "registry")))
    f_used <- attr(L0, "factor_db_file") %||% NA_character_
    asof <- attr(L0, "factor_db_asof_date")
    L <- as.data.table(L0); rm(L0)
    if (!identical(f_used, paste0("factor_db_", ym, ".parquet"))) stop("[fc] 접근자가 다른 달 파일을 돌려줬다(", f_used, ") — ", ym)
    if (!nrow(L)) next
    # 저장 = 저장 원값 방향: 정렬된 순위 × 그 정렬에 쓴 등록부 부호(등록부에 없는 팩터 = 접근자 기본 +1)
    L[RS0, on = "Factor_Name", s0 := i.s_reg]
    L[is.na(s0), s0 := 1L]
    L[, v := fc_to_stored(Z_Score_Aligned, s0[1L]), by = Factor_Name]
    L[, s0 := NULL]
    nt <- uniqueN(L$Ticker)
    COV[[ym]] <- L[, .(ym = ym, n = sum(!is.na(v)), coverage = sum(!is.na(v)) / nt), by = Factor_Name]
    W <- dcast(L, Ticker ~ Factor_Name, value.var = "v")
    fc <- setdiff(names(W), "Ticker")
    for (c in fc) set(W, j = c, value = as.integer(round(W[[c]] * sc)))
    tbl <- arrow_table(W)
    tbl <- tbl$cast(do.call(arrow::schema, c(list(Ticker = arrow::utf8()), setNames(rep(list(arrow::int16()), length(fc)), fc))))
    .fc_write_atomic(tbl, file.path(out, sprintf(cfg$storage$month_file, ym)))
    NM[[ym]] <- data.table(ym = ym, asof = format(as.Date(asof)), n_tickers = nt, n_factors = length(fc))
    if (verbose && (match(ym, todo) %% 24L == 0L)) cat(sprintf("  [fc] %s (%d/%d · %.0fs)\n", ym, match(ym, todo), length(todo), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
  # 달별 기록 = 원천 지문 + as-of(다시 만든 달은 새로, 나머지는 이전 기록)
  NMt <- rbindlist(NM)
  MM <- merge(FP, if (nrow(NMt)) NMt else data.table(ym = character(0), asof = character(0), n_tickers = integer(0), n_factors = integer(0)),
              by = "ym", all.x = TRUE)
  if (!is.null(OM)) {
    keep <- OM[!(ym %in% NMt$ym), .(ym, asof_o = as.character(asof), nt_o = as.integer(n_tickers), nf_o = as.integer(n_factors))]
    MM <- merge(MM, keep, by = "ym", all.x = TRUE)
    MM[is.na(asof) & !is.na(asof_o), `:=`(asof = asof_o, n_tickers = nt_o, n_factors = nf_o)]
    MM[, c("asof_o", "nt_o", "nf_o") := NULL]
  }
  MM <- MM[!is.na(asof)]
  # 커버리지 표 — 다시 만든 달은 새 값 · 나머지는 이전 표에서
  cov_p <- file.path(out, cfg$storage$coverage_file)
  CV <- rbindlist(COV)
  if (file.exists(cov_p) && !isTRUE(full)) {
    CO <- as.data.table(read_parquet(cov_p, mmap = FALSE))
    CV <- rbind(CO[!(ym %in% names(COV))], CV, use.names = TRUE, fill = TRUE)
  }
  CV <- CV[ym %in% MM$ym]
  setorder(CV, ym, Factor_Name)
  .fc_write_atomic(arrow_table(CV), cov_p)
  # 부호표 — 매번 전부(IC 이력 · 등록부가 바뀌면 과거 달 부호도 바뀔 수 있다 · 저장값은 저장 원값 방향이라 부호만 곱하면 된다)
  RS <- .fc_reg_signs(E$.load_registry())
  SG <- rbindlist(lapply(MM$ym, function(m) {
    a <- as.Date(MM[ym == m]$asof)
    f <- CV[ym == m, .(Factor_Name)]
    ic <- NULL
    invisible(utils::capture.output(ic <- tryCatch(E$.load_ic_direction_cached(a, 36L), error = function(e) NULL)))
    f <- merge(f, RS[, .(Factor_Name, s_reg, s_def)], by = "Factor_Name", all.x = TRUE)
    if (!is.null(ic) && nrow(ic)) f <- merge(f, ic[!is.na(ic_sign), .(Factor_Name, ic_sign)], by = "Factor_Name", all.x = TRUE)
    else f[, ic_sign := NA_integer_]
    # align_factor_direction 의 IC 경로와 같은 대체 순서: IC → 등록부(기대수익) → +1 · 방어 방향은 대체 없음(없으면 NA)
    f[, `:=`(s_ic = as.integer(fifelse(!is.na(ic_sign), ic_sign, fifelse(!is.na(s_reg), s_reg, 1L))),
             src_ic = fifelse(!is.na(ic_sign), "ic", fifelse(!is.na(s_reg), "registry", "default")),
             s_reg = as.integer(fcoalesce(s_reg, 1L)), s_def = as.integer(s_def))]
    f[, .(ym = m, asof = format(a), Factor_Name, s_reg, s_ic, src_ic, s_def)]
  }))
  .fc_write_atomic(arrow_table(SG), file.path(out, cfg$storage$signs_file))
  bh <- tryCatch(readLines(file.path(E$FACTOR_DB_DIR, "build_hash.txt"), n = 1L), error = function(e) NA_character_)
  meta <- list(schema = "factor_combinable_meta_v1", builder = FC_BUILDER, cfg_version = cfg$version,
               built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), factor_db_build_hash = bh,
               stored_direction = FC_STORED, value_scale = sc, transform = cfg$transform$rule,
               n_months = nrow(MM), first = min(MM$ym), last = max(MM$ym), rebuilt = length(NM),
               months = MM)
  writeLines(toJSON(meta, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null"), meta_p, useBytes = TRUE)
  if (verbose) cat(sprintf("[fc] 끝 — 달 %d(다시 %d) · 부호표 %s행 · %.0fs\n", nrow(MM), length(NM), format(nrow(SG), big.mark = ","),
                           as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  invisible(meta)
}

## ── 읽기(월간) ───────────────────────────────────────────────────────────────
#' @param sig_date 신호일(그 달 as-of 이상 — 월말 신호일로 부른다 · 더 이르면 멈춘다 · PIT)
#' @param direction "ic_asof"(기본) | "registry"(등록부 기대수익 방향) | "defensive"(등록부 방어 방향 — 없는 팩터는 factors 로
#'   명시하면 멈추고, 아니면 빼고 info$dropped_no_defensive 에 적는다) · @param tickers 이 종목 안에서 다시 순위(예: 측정 축 멤버)
#' @param missing "zero"(기본 = 횡단면 중앙값) | "na" · @param dedup 별칭 접기(기본 TRUE) · @param family 계열 평균 표
#' @return list(panel = Ticker × 팩터, families = Ticker × 계열, n_avail, meta = 팩터 표, info)
fc_load_month <- function(sig_date, direction = NULL, factors = NULL, tickers = NULL, missing = NULL, dedup = NULL,
                          family = TRUE, root = fc_root(), dir = NULL, registry = NULL, resolve = NULL) {
  cfg <- fc_config(root)
  direction <- direction %||% cfg$direction$default; missing <- missing %||% cfg$missing$default
  dedup <- if (is.null(dedup)) isTRUE(cfg$dedup$default) else isTRUE(dedup)
  if (!direction %in% cfg$direction$options) stop("[fc] direction 어휘 밖: ", direction)
  if (!missing %in% cfg$missing$options) stop("[fc] missing 어휘 밖: ", missing)
  dir <- dir %||% file.path(root, cfg$storage$dir)
  sig <- as.Date(sig_date); key_ym <- format(sig, "%Y%m")
  p <- file.path(dir, sprintf(cfg$storage$month_file, key_ym))
  if (!file.exists(p)) stop("[fc] 결합용 뷰에 그 달이 없다(", key_ym, ") — 이전 달로 대체하지 않는다")
  meta <- fromJSON(file.path(dir, cfg$storage$meta_file), simplifyVector = TRUE)
  if (!identical(meta$stored_direction, FC_STORED))
    stop(sprintf("[fc] 저장본 방향 '%s' — 이 판(%s)은 '%s' 저장본만 읽는다(--build --full 로 다시 지을 것)",
                 meta$stored_direction %||% "?", FC_BUILDER, FC_STORED))
  MM <- as.data.table(meta$months)
  asof <- as.Date(MM[ym == key_ym, asof][1])
  if (is.na(asof)) stop("[fc] 그 달 as-of 기록 없음: ", key_ym)
  if (sig < asof) stop(sprintf("[fc] 신호일 %s 가 그 달 as-of %s 보다 이르다 — 월말 신호일로 부르라(PIT)", sig, asof))
  sc <- as.numeric(meta$value_scale)
  W <- as.data.table(read_parquet(p, mmap = FALSE))                 # 메모리 매핑 없이(열어 둔 세션이 밤 갱신의 덮어쓰기를 막지 않게 · Windows 1224)
  fc <- setdiff(names(W), "Ticker")
  if (!is.null(factors)) {
    miss <- setdiff(factors, fc)
    if (length(miss)) cat(sprintf("[fc] WARN: 그 달에 없는 팩터 %d개 제외: %s\n", length(miss), paste(head(miss, 8), collapse = ", ")))
    fc <- intersect(fc, factors); W <- W[, c("Ticker", fc), with = FALSE]
  }
  for (c in fc) set(W, j = c, value = as.numeric(W[[c]]) / sc)
  SG <- as.data.table(read_parquet(file.path(dir, cfg$storage$signs_file), mmap = FALSE))[ym == key_ym]
  # 방향 = 부호표의 부호를 곱한다(저장값 = 저장 원값 방향) — registry = s_reg · ic_asof = s_ic · defensive = s_def
  scol <- switch(direction, registry = "s_reg", ic_asof = "s_ic", defensive = "s_def")
  miss_s <- setdiff(fc, SG$Factor_Name)
  if (length(miss_s)) stop("[fc] 부호표에 없는 팩터(", paste(head(miss_s, 5), collapse = ","), ") — 지어내지 않는다")
  s <- SG[Factor_Name %in% fc, setNames(get(scol), Factor_Name)]
  no_def <- character(0)
  if (identical(direction, "defensive")) {
    no_def <- sort(names(s)[is.na(s)])
    if (length(no_def)) {
      if (!is.null(factors)) stop("[fc] 방어 방향이 없는 팩터(", paste(head(no_def, 8), collapse = ","), ") — 방어 방향은 위험 · 유동성 계열에만 있다")
      cat(sprintf("[fc] 방어 방향이 없는 팩터 %d개를 뺀다(info$dropped_no_defensive)\n", length(no_def)))
      fc <- setdiff(fc, no_def); W <- W[, c("Ticker", fc), with = FALSE]
    }
  }
  if (anyNA(s[fc])) stop("[fc] 부호표 부호 결측(", paste(head(fc[is.na(s[fc])], 5), collapse = ","), ") — 지어내지 않는다")
  for (c in fc) if (s[[c]] == -1L) set(W, j = c, value = -W[[c]])
  if (!is.null(tickers)) {
    W <- W[Ticker %in% as.character(tickers)]
    for (c in fc) set(W, j = c, value = fc_rank_pm1(W[[c]]))
  }
  E <- if (is.null(registry) || is.null(resolve)) .fc_env(root) else NULL
  reg <- if (is.null(registry)) E$.load_registry() else registry
  if (isTRUE(dedup)) {
    rv <- if (is.null(resolve)) function(x) E$resolve_factor_canonical(x, reg) else resolve
    keep <- fc_alias_drop(fc, rv)
    if (length(keep) < length(fc)) { W <- W[, c("Ticker", keep), with = FALSE]; fc <- keep }
  }
  RS <- .fc_reg_signs(reg)
  cat_map <- setNames(RS$category, RS$Factor_Name)
  n_avail <- data.table(Ticker = W$Ticker, n_avail = rowSums(!is.na(as.matrix(W[, fc, with = FALSE]))))
  FAM <- if (isTRUE(family)) fc_family_scores(W, cat_map) else NULL
  if (identical(missing, "zero")) {
    for (c in fc) set(W, which(is.na(W[[c]])), c, 0)
    if (!is.null(FAM)) for (c in setdiff(names(FAM), "Ticker")) set(FAM, which(is.na(FAM[[c]])), c, 0)
  }
  M <- data.table(Factor_Name = fc, category = unname(cat_map[fc]))
  M <- merge(M, SG[, .(Factor_Name, s_reg, s_ic, src_ic, s_def)], by = "Factor_Name", all.x = TRUE)
  list(panel = W, families = FAM, n_avail = n_avail, meta = M,
       info = list(ym = key_ym, asof = format(asof), sig_date = format(sig), direction = direction, missing = missing,
                   dedup = dedup, rerank_within_tickers = !is.null(tickers), n_factors = length(fc), builder = meta$builder,
                   dropped_no_defensive = no_def))
}

#' 여러 달을 쌓는다(Date = 그 달 신호일 · 패널만) — 머신러닝 학습 표용
fc_load_months <- function(sig_dates, ...) {
  rbindlist(lapply(sig_dates, function(d) { r <- fc_load_month(d, family = FALSE, ...); r$panel[, Date := as.Date(d)] }), use.names = TRUE, fill = TRUE)
}

## ── 읽기(일간 · 즉석) ────────────────────────────────────────────────────────
#' 일간 팩터 DB(윈저라이즈 원값)를 날짜별 같은 변환으로 — 저장하지 않는다(쓰는 달만)
fc_daily <- function(ym = NULL, date_range = NULL, factors = NULL, direction = NULL, tickers = NULL, missing = NULL,
                     dedup = NULL, root = fc_root()) {
  cfg <- fc_config(root); E <- .fc_env(root)
  direction <- direction %||% cfg$direction$default; missing <- missing %||% cfg$missing$default
  dedup <- if (is.null(dedup)) isTRUE(cfg$dedup$default) else isTRUE(dedup)
  D <- as.data.table(E$load_daily_factors(ym = ym, date_range = date_range, factors = factors, align_direction = TRUE, direction = direction))
  if (!is.null(tickers)) D <- D[Ticker %in% as.character(tickers)]
  fc <- setdiff(names(D), c("Date", "Ticker"))
  if (isTRUE(dedup)) { keep <- fc_alias_drop(fc, function(x) E$resolve_factor_canonical(x, E$.load_registry())); D <- D[, c("Date", "Ticker", keep), with = FALSE]; fc <- keep }
  D[, (fc) := lapply(.SD, fc_rank_pm1), by = Date, .SDcols = fc]
  if (identical(missing, "zero")) for (c in fc) set(D, which(is.na(D[[c]])), c, 0)
  D[]
}

## ── 실행 ────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  arg <- function(k) { i <- match(k, a); if (is.na(i) || i == length(a)) NULL else a[i + 1L] }
  if (!("--build" %in% a)) { cat("쓰기: Rscript factor_combinable.R --build [--full] [--out DIR] [--months YYYYMM,...]\n"); quit(save = "no", status = 2L) }
  ms <- arg("--months"); ms <- if (is.null(ms)) NULL else strsplit(ms, ",", fixed = TRUE)[[1]]
  res <- fc_build(out = arg("--out"), full = "--full" %in% a, months = ms)
  if (inherits(res, "fc_skipped")) quit(save = "no", status = 5L)   # 잠금 — 다른 빌드가 도는 중(일일 체인 [6e] 는 정보로 본다)
}
