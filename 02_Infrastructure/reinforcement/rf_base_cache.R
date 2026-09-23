#==============================================================================
# rf_base_cache.R — 강화 기저 신호 캐시의 **키·적재·저장** (2026-09-23 수리)
#
# 소비자: rf_cell_engine.R 의 .load_one() 하나(기저 엔진 산출 = .cache/rf_base_signal/*.rds).
#
# 왜 이 파일이 생겼는가 (실측 2026-09-23 적대 검증):
#   구 키 = paste(엔진 md5, as.character(RAWDATA mtime), nrow, start) 를 영숫자만 남긴 뒤
#   substr(1, 40) 으로 잘랐다. md5 가 32자라 남는 8자는 mtime 의 **날짜(yyyymmdd)** 뿐이었다.
#   시각·행수·시작일은 키 문자열에 적혀 있었지만 절단이 지웠다 — 적힌 것이 쓰인 것은 아니다.
#   결과: 같은 날 RAWDATA 가 바뀌어도(Size 수리 18:49 · BM_Ret 20:52) factor DB 가 재빌드돼도
#   (18:53 / 18:56 / 20:58) 교정 전 기저 신호를 재사용했다(당일 셀 로그 38건 적중).
#
# 현행 키 — 구성요소 전문을 한 줄로 적고 md5 로 접는다(절단 없음). 전문은 캐시 객체 속성
#   rf_base_cache_key 에 같이 저장하고, 적중 시 **전문 일치**까지 확인한다(파일명 충돌·구판 잔재 방어).
#   ① 기저 엔진 내용 md5
#   ② RAWDATA 파일 도장   = mtime(초, 소수 3자리) + size
#   ③ benchmark 파일 도장 = mtime + size        (기저 엔진이 BM_DT 를 받는다)
#   ④ factor DB 도장      = build_hash.txt 내용 + 월 파일(factor_db_YYYYMM.parquet) 수·총크기·최신 mtime
#        기저 엔진이 load_month_factors 를 쓰는지와 무관하게 보수적으로 포함한다.
#        build_hash 를 안 갱신하는 월 파일 재작성 경로가 있어도 ④ 뒷부분이 잡는다.
#   ⑤ 메모리 RAWDATA 내용 지문 — 워커가 파일을 읽은 **뒤** 파일이 교체되면 ②는 새 판본을 적는데
#        메모리는 옛 판본이다(옛 신호가 새 키로 저장된다). 파일 도장만으로는 이 경합을 못 막는다.
#   ⑥ nrow · 시작일 (구 키에 적혀 있었으나 절단으로 사라졌던 것)
#   ⑦ 보조 데이터원 도장(2026-09-24 적대 검증 발견 1) — 기저 엔진이 RAWDATA 밖에서 **직접** 읽는 패널.
#        오늘 적중 42건의 엔진(RP_AUTO_2002_06975)은 consensus/*.parquet · fundamental_merged.parquet 를
#        읽는데 ①~⑥ 어디에도 없었다. daily [0b] 는 RAWDATA 를 먼저, consensus 를 나중에 쓰므로 그 사이
#        시작한 셀이 옛 consensus 신호를 새 RAWDATA 키로 저장할 수 있었다.
#        목록 = RP_AUTO_*/engine.R 가 file.path(root, ".cache", ...) 로 읽는 파일 전수(grep 2026-09-24).
#        새 엔진이 다른 패널을 읽으면 여기에 더한다(빠뜨리면 그 패널 갱신이 캐시를 못 깬다).
#
# 저장 규약:
#   · 실행 전후 파일 도장(②③④)이 다르면 저장하지 않는다 — 실행 중 재빌드 = 혼합 판본.
#   · tmp → rename 원자 교체(병렬 워커가 반쯤 쓴 파일을 읽지 않게).
#   · 도장을 못 읽으면(엔진 md5 실패·build_hash 읽기 실패·파일 stat 실패) 캐시를 **쓰지도 읽지도 않는다**.
#     구판은 실패 시 "nohash"/"nomtime" 상수를 키에 넣었다 — 상수 키는 영원히 적중한다.
#
# 비용: 키가 바뀌므로 구 키 파일(base_<md5><yyyymmdd>.rds)은 더 이상 적중하지 않는다.
#   엔진별 첫 셀이 기저를 한 번 재계산한다. 이후 같은 판본에서는 다시 적중한다.
#   구 파일은 참조되지 않는 잔재로 남는다(이 파일은 지우지 않는다).
#==============================================================================
suppressMessages(library(data.table))

RF_BASE_CACHE_VERSION <- "rf_base_cache_v2"
RF_BASE_CACHE_AUX_FILES <- c("fundamental_merged.parquet", "fundamental_xlsx.parquet",
                             "ecos_bond_rates.parquet", "investor_wide.parquet")
RF_BASE_CACHE_AUX_DIRS  <- c("consensus")

# 문자열 md5 — R >= 4.5 는 bytes= 로, 그 이전은 임시 파일로.
.rfbc_md5_str <- function(s) {
  r <- charToRaw(enc2utf8(as.character(s)))
  h <- tryCatch(unname(tools::md5sum(bytes = r)), error = function(e) NULL)
  if (is.null(h) || !length(h) || is.na(h)) {
    tf <- tempfile("rfbc_")
    on.exit(unlink(tf), add = TRUE)
    writeBin(r, tf)
    h <- unname(tools::md5sum(tf))
  }
  as.character(h)
}

# 파일 도장 — "absent" 는 정상 상태(파일 없음), NA 는 판독 실패(캐시 금지).
rf_base_cache_file_stamp <- function(path) {
  if (!length(path) || is.na(path) || !nzchar(path) || !file.exists(path)) return("absent")
  fi <- tryCatch(file.info(path, extra_cols = FALSE), error = function(e) NULL)
  if (is.null(fi) || !nrow(fi) || is.na(fi$size) || is.na(fi$mtime)) return(NA_character_)
  sprintf("%.3f:%.0f", as.numeric(fi$mtime), as.numeric(fi$size))
}

# factor DB 도장 — build_hash.txt 내용 + 월 파일 집계.
rf_base_cache_factor_db_stamp <- function(fdb_dir) {
  if (!length(fdb_dir) || is.na(fdb_dir) || !dir.exists(fdb_dir)) return("absent")
  bh <- file.path(fdb_dir, "build_hash.txt")
  bh_txt <- if (!file.exists(bh)) "absent" else
    tryCatch(paste(trimws(readLines(bh, warn = FALSE, encoding = "UTF-8")), collapse = "/"),
             error = function(e) NA_character_)
  if (is.na(bh_txt)) return(NA_character_)
  mf <- list.files(fdb_dir, pattern = "^factor_db_[0-9]{6}\\.parquet$", full.names = TRUE)
  months <- if (!length(mf)) "0" else {
    fi <- tryCatch(file.info(mf, extra_cols = FALSE), error = function(e) NULL)
    if (is.null(fi) || anyNA(fi$size) || anyNA(fi$mtime)) return(NA_character_)
    sprintf("%d:%.0f:%.3f", length(mf), sum(as.numeric(fi$size)), max(as.numeric(fi$mtime)))
  }
  paste0("build_hash=", bh_txt, ";months=", months)
}

# 보조 데이터원 도장(⑦) — cache_dir = RAWDATA 가 놓인 .cache. 파일은 개별 도장, 디렉터리는
#   *.parquet 수·총크기·최신 mtime. 판독 실패 = NA(캐시 금지), 부재 = "absent"(정상).
rf_base_cache_aux_stamp <- function(cache_dir) {
  if (!length(cache_dir) || is.na(cache_dir) || !nzchar(cache_dir)) return(NA_character_)
  fs <- vapply(RF_BASE_CACHE_AUX_FILES, function(f) rf_base_cache_file_stamp(file.path(cache_dir, f)), character(1))
  ds <- vapply(RF_BASE_CACHE_AUX_DIRS, function(d) {
    dd <- file.path(cache_dir, d)
    if (!dir.exists(dd)) return("absent")
    mf <- list.files(dd, pattern = "\\.parquet$", full.names = TRUE)
    if (!length(mf)) return("0")
    fi <- tryCatch(file.info(mf, extra_cols = FALSE), error = function(e) NULL)
    if (is.null(fi) || anyNA(fi$size) || anyNA(fi$mtime)) return(NA_character_)
    sprintf("%d:%.0f:%.3f", length(mf), sum(as.numeric(fi$size)), max(as.numeric(fi$mtime)))
  }, character(1))
  if (anyNA(c(fs, ds))) return(NA_character_)
  paste(c(paste0(names(fs), "=", fs), paste0(names(ds), "/=", ds)), collapse = ";")
}

# 파일 도장 묶음(②③④⑦) — 실행 전후 대조에도 같은 함수를 쓴다.
rf_base_cache_stamps <- function(rawdata_path, bench_path, factor_db_dir) {
  list(rawdata   = rf_base_cache_file_stamp(rawdata_path),
       bench     = rf_base_cache_file_stamp(bench_path),
       factor_db = rf_base_cache_factor_db_stamp(factor_db_dir),
       aux       = rf_base_cache_aux_stamp(if (length(rawdata_path) && !is.na(rawdata_path))
                                              dirname(rawdata_path) else NA_character_))
}

# 메모리 패널 내용 지문(⑤). 엔진 파생 열(이름이 '.' 으로 시작)은 제외한다.
#   수치열: NA 수 · 전합 · 간격 7 표본의 위치가중합(값 교환도 잡는다) — 전부 %.17g(정확 표기).
#   문자열: NA 수 · 간격 7 표본의 고유값 수 · 위치가중 바이트 길이합.
#   같은 데이터·같은 정렬이면 결정론적이다(엔진이 캐시 앞에서 setorder(Ticker, Date) 를 한다).
rf_base_data_fingerprint <- function(DT) {
  cols <- names(DT)
  cols <- cols[!startsWith(cols, ".")]
  n <- nrow(DT)
  idx <- if (n > 0L) seq.int(1L, n, by = 7L) else integer(0)
  wv <- as.numeric(seq_along(idx))
  parts <- vapply(cols, function(cn) {
    x <- DT[[cn]]
    na <- sum(is.na(x))
    if (is.numeric(x) || is.logical(x) || inherits(x, "Date") || inherits(x, "POSIXt")) {
      v <- as.numeric(unclass(x))
      s1 <- sum(v, na.rm = TRUE)
      s2 <- if (length(idx)) sum(v[idx] * wv, na.rm = TRUE) else 0
      sprintf("%s:%d:%.17g:%.17g", cn, na, s1, s2)
    } else {
      xs <- as.character(x)[idx]
      nb <- nchar(xs, type = "bytes"); nb[is.na(xs)] <- 0L
      sprintf("%s:%d:%d:%.17g", cn, na, data.table::uniqueN(xs), sum(as.numeric(nb) * wv))
    }
  }, character(1))
  paste(c(sprintf("n=%d", n), parts), collapse = "|")
}

# 키(①~⑥). data_fp 는 rf_base_data_fingerprint() 결과(엔진이 한 번 계산해 재사용).
rf_base_cache_key <- function(engine_md5, rawdata_path, bench_path, factor_db_dir,
                              data_fp, n_rows, start) {
  st <- rf_base_cache_stamps(rawdata_path, bench_path, factor_db_dir)
  eng_ok <- length(engine_md5) == 1L && !is.na(engine_md5) && grepl("^[0-9a-f]{32}$", engine_md5)
  fp_ok  <- length(data_fp) == 1L && !is.na(data_fp) && nzchar(data_fp)
  cacheable <- eng_ok && fp_ok && !anyNA(unlist(st))
  key <- paste0(RF_BASE_CACHE_VERSION,
                "|engine_md5=", if (eng_ok) engine_md5 else "NA",
                "|rawdata=",    st$rawdata,
                "|bench=",      st$bench,
                "|factor_db=",  st$factor_db,
                "|aux=",        st$aux,
                "|data_fp=",    if (fp_ok) .rfbc_md5_str(data_fp) else "NA",
                "|nrow=",       as.character(n_rows),
                "|start=",      as.character(start))
  hash <- .rfbc_md5_str(key)
  list(key = key, hash = hash, cacheable = cacheable, stamps = st,
       paths = list(rawdata = rawdata_path, bench = bench_path, factor_db = factor_db_dir),
       file = paste0("base_v2_", if (eng_ok) substr(engine_md5, 1L, 12L) else "nohash",
                     "_", hash, ".rds"))
}

# 적재 — 키 전문이 일치할 때만 적중. list(obj, why).
rf_base_cache_load <- function(cpath, key) {
  if (!file.exists(cpath)) return(list(obj = NULL, why = "absent"))
  b <- tryCatch(readRDS(cpath), error = function(e) NULL)
  if (is.null(b)) return(list(obj = NULL, why = "unreadable"))
  if (!identical(attr(b, "rf_base_cache_key", exact = TRUE), key))
    return(list(obj = NULL, why = "key_mismatch"))
  list(obj = b, why = "hit")
}

# 저장 — 실행 전후 도장이 같을 때만, tmp → rename. 반환 = 사유 문자열("saved" 가 성공).
rf_base_cache_save <- function(obj, cpath, ck) {
  if (!isTRUE(ck$cacheable)) return("uncacheable")
  post <- rf_base_cache_stamps(ck$paths$rawdata, ck$paths$bench, ck$paths$factor_db)
  if (!identical(post, ck$stamps)) {
    chg <- names(post)[!mapply(identical, post, ck$stamps[names(post)])]
    return(paste0("stamp_changed_during_run:", paste(chg, collapse = ",")))
  }
  o <- data.table::copy(obj)
  data.table::setattr(o, "rf_base_cache_key", ck$key)
  tmp <- paste0(cpath, ".tmp", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  saveRDS(o, tmp)
  if (!file.rename(tmp, cpath)) stop("rename 실패: ", basename(tmp), " -> ", basename(cpath))
  "saved"
}
