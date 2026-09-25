#==============================================================================
# pin_cache.R — Cache Vintage Pinning (Governance⑤ / 감사 DATA-P1-1)
# Version: 1.0.0 (2026-07-03)
#
# 배경: 2026-07-02 실사고 — 세션 중 benchmark.parquet 재생성이 graduation
#       경계 판정을 반전시킴 ([[project-cache-vintage-pinning]]).
#       세션 도중 캐시가 갱신되어도 판정 입력이 흔들리지 않도록,
#       판정 시작 시점의 캐시 스냅샷(vintage)을 고정(pin)하고
#       이후 모든 판정 소비는 pin된 사본 경로만 사용한다.
#
# 사용 규약 (HARD):
#   - HARD 게이트 판정(graduation PORT_t / oos_retention / calmar 등)과
#     다중라운드 A/B 비교는 시작 시점에 pin_cache()로 입력 캐시를 스냅샷하고,
#     이후 read_pinned() 경로만 소비한다 (원본 .cache/ 직접 재로드 금지).
#   - pin tag는 산출물 manifest(bt_result$manifest 등)에 기록해
#     사후 감사 시 어떤 vintage로 판정했는지 재구성 가능해야 한다.
#   - (measurement-graduation 조항 문구는 docs 그룹이 룰 문서에 추가 —
#      본 파일은 코드 + 본 주석이 전부.)
#
# OneDrive 안전수칙:
#   - 복사는 file.copy() 순수 바이트 복사만 사용 (arrow read→write 아님 →
#     Windows arrow mmap 1224 버그와 무관, [[project-windows-arrow-mmap-1224]]).
#   - pin 디렉토리는 .cache/pins/<tag>/ (프로젝트 .cache 하위 고정).
#
# 함수:
#   pin_cache(paths, tag)   — 캐시 파일들을 .cache/pins/<tag>/ 에 복사 +
#                             manifest.json(원경로·md5·시각) 기록
#   read_pinned(path, tag)  — pin된 사본 경로 반환 (부재 시 명시 에러)
#   list_pins()             — pin 목록·파일수·용량 data.frame
#   pin_fingerprint(cutoff, raw, bm, root, …)   — 데이터 빈티지 지문 (P0-07 · 2026-09-24 · v2 2026-09-25 적대검증 F1 · 아래 절)
#   pin_fingerprint_load(root, …)               — 지문용 적재(키 + 소비 열 · 여러 컷오프를 한 번 적재로)
#   pin_fingerprint_compare(a, b)               — 같은 컷오프·같은 열 두 지문 대조(match/mismatch/… · 다른 연도·열 지목)
#   pin_fp_consumers(code_root, engines)        — 측정 경로 소비자 코드(+source 폐포) 토큰 → 소비 열 재도출(열 목록 하드코딩 없음)
#   pin_complete_month_end(raw_dates, bm_dates) — 직전 완결 월말(데이터가 그 월말을 넘어섰음이 증명된 마지막 월말)
#
# ★스냅샷(pin_cache) 호출 지점 — P0-07 은 **표시만**, 배선은 P2(플랜 qvest-1-drifting-eclipse):
#   ① A 발행 시(run_paper_replication.R §11 Grade A 분기 · 러너 A 관문 rf_a_eligibility 통과 직후)
#   ② floor v2 산출 시(P1 — 보유 기반 재시뮬 입력 고정)
#   지문(pin_fingerprint)은 복사 없이 판본을 **식별**만 한다 — 모든 entry 개설에 싣는다(reinforce_ledger.R::rf_open_entry).
#
# 사용 예:
#   source(file.path("02_Infrastructure", "data", "pin_cache.R"))
#   tag <- format(Sys.time(), "grad_%Y%m%d_%H%M%S")
#   pin_cache(c(BM_CACHE, RAWDATA_CACHE), tag)
#   bm <- arrow::read_parquet(read_pinned(BM_CACHE, tag))
#==============================================================================

# ─── config.R 경유 PROJECT_ROOT / CACHE_DIR 확보 (이미 source된 경우 재사용) ──
if (!exists("CACHE_DIR")) {
  .pin_cfg_candidates <- c(
    file.path(Sys.getenv("QM_ROOT", unset = ""), "02_Infrastructure/config.R"),
    file.path(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), "02_Infrastructure/config.R"),
    "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/config.R",
    "02_Infrastructure/config.R"
  )
  .pin_cfg <- .pin_cfg_candidates[file.exists(.pin_cfg_candidates)][1]
  if (is.na(.pin_cfg)) stop("[pin_cache] config.R를 찾을 수 없습니다 — QM_ROOT 설정 필요")
  source(.pin_cfg)
  rm(.pin_cfg_candidates, .pin_cfg)
}

PINS_DIR <- file.path(CACHE_DIR, "pins")

.pin_manifest_path <- function(tag) file.path(PINS_DIR, tag, "manifest.json")

.pin_validate_tag <- function(tag) {
  if (length(tag) != 1L || !is.character(tag) || !nzchar(tag))
    stop("[pin_cache] tag는 비어있지 않은 문자열 1개여야 합니다")
  if (grepl("[^A-Za-z0-9_.-]", tag))
    stop("[pin_cache] tag는 [A-Za-z0-9_.-]만 허용: '", tag, "'")
  invisible(tag)
}

#------------------------------------------------------------------------------
# pin_cache(paths, tag)
#   paths: pin할 캐시 파일 경로 벡터 (예: c(BM_CACHE, RAWDATA_CACHE))
#   tag  : 스냅샷 식별자 (예: "grad_20260703_1015"). 이미 존재하는 tag에
#          동일 basename 재-pin은 거부 (vintage 불변성 — overwrite 금지).
#   반환: manifest list (invisible)
#------------------------------------------------------------------------------
pin_cache <- function(paths, tag) {
  .pin_validate_tag(tag)
  paths <- normalizePath(paths, winslash = "/", mustWork = FALSE)
  missing_src <- paths[!file.exists(paths)]
  if (length(missing_src) > 0)
    stop("[pin_cache] 원본 파일 부재: ", paste(missing_src, collapse = ", "))
  bn <- basename(paths)
  if (anyDuplicated(bn))
    stop("[pin_cache] basename 중복 — 한 tag 안에서 파일명은 고유해야 합니다: ",
         paste(bn[duplicated(bn)], collapse = ", "))

  tag_dir <- file.path(PINS_DIR, tag)
  dir.create(tag_dir, recursive = TRUE, showWarnings = FALSE)

  mf_path <- .pin_manifest_path(tag)
  manifest <- if (file.exists(mf_path)) {
    jsonlite::fromJSON(mf_path, simplifyDataFrame = FALSE)
  } else {
    list(tag = tag, created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
         files = list())
  }
  existing_bn <- vapply(manifest$files, function(f) f$basename, character(1))
  clash <- bn[bn %in% existing_bn]
  if (length(clash) > 0)
    stop("[pin_cache] tag '", tag, "'에 이미 pin된 파일 재-pin 거부 (불변성): ",
         paste(clash, collapse = ", "))

  for (i in seq_along(paths)) {
    src  <- paths[i]
    dest <- file.path(tag_dir, bn[i])
    ok <- file.copy(src, dest, overwrite = FALSE, copy.date = TRUE)
    if (!ok) stop("[pin_cache] 복사 실패: ", src, " -> ", dest)
    md5_src  <- unname(tools::md5sum(src))
    md5_dest <- unname(tools::md5sum(dest))
    if (!identical(md5_src, md5_dest)) {
      file.remove(dest)
      stop("[pin_cache] md5 불일치 (복사 무결성 실패): ", src)
    }
    manifest$files[[length(manifest$files) + 1L]] <- list(
      original_path = src,
      basename      = bn[i],
      md5           = md5_dest,
      size_bytes    = file.size(dest),
      pinned_at     = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
    )
  }

  jsonlite::write_json(manifest, mf_path, auto_unbox = TRUE, pretty = TRUE)
  message("[pin_cache] tag '", tag, "' — ", length(paths), "개 파일 pin 완료 (",
          tag_dir, ")")
  invisible(manifest)
}

#------------------------------------------------------------------------------
# read_pinned(path, tag)
#   path: pin 시점에 사용한 원본 경로 (또는 basename)
#   tag : pin_cache에 사용한 tag
#   반환: pin된 사본의 절대경로 (부재/변조 시 명시 에러 — silent fallback 없음)
#------------------------------------------------------------------------------
read_pinned <- function(path, tag) {
  .pin_validate_tag(tag)
  mf_path <- .pin_manifest_path(tag)
  if (!file.exists(mf_path))
    stop("[read_pinned] tag '", tag, "' manifest 부재: ", mf_path,
         " — pin_cache()로 먼저 스냅샷하세요")
  manifest <- jsonlite::fromJSON(mf_path, simplifyDataFrame = FALSE)

  want_norm <- normalizePath(path, winslash = "/", mustWork = FALSE)
  want_bn   <- basename(path)
  hit <- NULL
  for (f in manifest$files) {
    if (identical(f$original_path, want_norm) || identical(f$basename, want_bn)) {
      hit <- f; break
    }
  }
  if (is.null(hit))
    stop("[read_pinned] tag '", tag, "'에 pin된 항목 없음: ", path,
         " (pin된 파일: ",
         paste(vapply(manifest$files, function(f) f$basename, character(1)),
               collapse = ", "), ")")

  pinned <- file.path(PINS_DIR, tag, hit$basename)
  if (!file.exists(pinned))
    stop("[read_pinned] manifest에는 있으나 사본 파일 부재 (pin 디렉토리 손상): ",
         pinned)
  md5_now <- unname(tools::md5sum(pinned))
  if (!identical(md5_now, hit$md5))
    stop("[read_pinned] pin 사본 md5 변조 감지 (기대 ", hit$md5,
         " / 실측 ", md5_now, "): ", pinned)
  pinned
}

#------------------------------------------------------------------------------
# list_pins()
#   반환: data.frame(tag, n_files, total_bytes, total_mb, created_at)
#         pin 없으면 0-row data.frame
#------------------------------------------------------------------------------
list_pins <- function() {
  empty <- data.frame(tag = character(0), n_files = integer(0),
                      total_bytes = numeric(0), total_mb = numeric(0),
                      created_at = character(0), stringsAsFactors = FALSE)
  if (!dir.exists(PINS_DIR)) return(empty)
  tags <- list.dirs(PINS_DIR, full.names = FALSE, recursive = FALSE)
  if (length(tags) == 0) return(empty)
  rows <- lapply(tags, function(tag) {
    mf_path <- .pin_manifest_path(tag)
    if (!file.exists(mf_path)) {
      # manifest 없는 orphan 디렉토리도 노출 (감사 가시성)
      files <- list.files(file.path(PINS_DIR, tag), full.names = TRUE)
      return(data.frame(tag = tag, n_files = length(files),
                        total_bytes = sum(file.size(files), na.rm = TRUE),
                        total_mb = NA_real_,
                        created_at = "(manifest 없음 — orphan)",
                        stringsAsFactors = FALSE))
    }
    manifest <- jsonlite::fromJSON(mf_path, simplifyDataFrame = FALSE)
    total <- sum(vapply(manifest$files, function(f) as.numeric(f$size_bytes),
                        numeric(1)))
    data.frame(tag = tag, n_files = length(manifest$files),
               total_bytes = total, total_mb = round(total / 1024^2, 2),
               created_at = manifest$created_at, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out$total_mb <- ifelse(is.na(out$total_mb),
                         round(out$total_bytes / 1024^2, 2), out$total_mb)
  out[order(out$tag), , drop = FALSE]
}

#==============================================================================
# 데이터 빈티지 지문 (P0-07 · 2026-09-24 · 감사 D4-11·D8-03 · 플랜 qvest-1-drifting-eclipse P0-07)
#   수리 2026-09-25(적대검증 F1 BLOCKING): v1(연도별 Close·Ret·K200·KQ150 **정렬 합**)은 셀 엔진이 쓰는 Vol(유동성 2e8)·Size(B3 크기 칸)
#   개정과, 합을 보존하는 맞교체(두 행 값 교환·편입 맞교체·상쇄 수정)를 못 보고 'match' 로 적었다 → scheme pin_fp_v2(아래).
#   v1 은 배포되지 않았다(운영 원장 v1 지문 0건) — 이행 없음. 두 판이 섞이면 대조가 incomparable(scheme) 로 멈춘다.
#==============================================================================
# 왜: 강화 레인은 판본을 고정하지 않는다. 한 entry 의 칸이 서로 다른 데이터 종료일에서 측정되고(원장 재도출 —
#   00_manifest end_date 혼재 entry: 감사 시점 6개 = 0-기준 색인 16·23·32·45·47·57, 09-24 재도출 8개), 09-18 벤치 축
#   이관 같은 **과거 행 개정**을 가로질러 승격이 부모 저장값과 자식 칸을 비교한다(measurement-graduation §7).
#   지문은 "이 판정이 어느 판본 위에서 났는가" 를 **식별**한다 — 복사·고정(pin_cache)이 아니다.
# 정의(scheme pin_fp_v2) — 전부 cutoff 이하 행만 본다:
#   raw : 소비 열(아래 '소비 열 재도출')의 **행 키 정렬 바이트 해시**. 행을 키(Date·Ticker)로 정렬(radix · C 로케일 바이트 순)한 뒤
#         연도별로 [키 바이트(Date 일수 · Ticker 길이접두 UTF-8)]·[열별 값 바이트(수치 = IEEE-754 double LE 원 비트 · 문자 = 길이접두
#         UTF-8 · NA 길이 -1)] 의 md5 → 연도 md5 · 열 md5 · 전체 md5.
#         → 파일 재기록으로 행 순서만 바뀌면 불변(키 정렬) · 값 1비트 변경 · 합을 보존하는 맞교체(값 교환·편입 맞교체·상쇄) ·
#           키 이동(날짜 이동·종목 코드 개명)은 전부 변화. 합이 아니라 원 비트라 플랫폼 간 부동소수 누적 차이도 없다.
#         키가 중복되면(같은 Date·Ticker 2행) 값까지 정렬 키로 써서 순서 불변을 지키고, 중복 수를 dup_keys 로 싣는다.
#   bm  : 같은 방식(키 = Date · 소비 열 = 벤치 수치 열 ∩ 소비자 토큰).
#   fdb : 팩터 DB 월 파일(factor_db_YYYYMM.parquet · YYYYMM ≤ cutoff 월) **이름·크기** 목록 md5 — 내용 md5 는
#         441파일 × 약 25MB 라 entry 개설 비용상 뺐다(한계: 같은 크기의 내용 개정은 못 본다 · 재빌드는 크기로 보인다).
#   digest = md5(scheme|cutoff|raw|bm|fdb).
# 소비 열 재도출(★열 목록 하드코딩 금지 — 적대검증 F1): 이 파일은 열 이름을 적지 않는다. 측정 경로 소비자 코드
#   (.pin_fp_CONSUMERS = RAWDATA 패널을 받아 측정을 계산하는 진입점 · + 호출자가 넘기는 엔진 파일)와 그 source() 폐포
#   (측정 계층 디렉터리 .pin_fp_CONSUMER_SCOPE · 엔진 자기 디렉터리 안)를 parse 해 **기호(SYMBOL)·문자열 상수(STR_CONST)** 토큰을
#   모으고, 데이터 스키마 열 이름과의 교집합을 소비 열로 쓴다. 함수 호출 기호(source( 등)·인자 이름·주석은 세지 않는다.
#   결과는 상위집합이다(토큰이 다른 표를 가리켜도 들어온다 — 과포함 = 오탐 쪽, 누락 = 침묵 쪽이라 과포함을 택한다).
#   한계: 계산된 열 이름(paste0 로 조립한 이름)과 폐포 밖 파일이 읽는 열은 못 본다.
#   지문은 쓴 열(cols)과 소비자 파일 md5(consumers)를 싣는다 — 승격 대조는 **부모 지문의 cols 로** 다시 잰다(비교 가능성 유지).
# 소비 원천 범위(sources · 2026-09-25 2차 적대검증 F2): 지문이 해시하는 원천은 RAWDATA·벤치·팩터 DB 월 목록뿐인데, 엔진은 그 밖
#   패널(fundamental_merged·fundamental_dart_quarterly·consensus/ 등 — 원장 엔진 35종 중 다수 · 활성 entry 포함)을 직접 읽는다.
#   그 패널이 개정돼도 raw/bm/fdb 가 같으면 대조가 'match' 였다(F1 과 같은 침묵). → 엔진 폐포 토큰 ∩ <cache_dir> 데이터 항목
#   (*.parquet 파일 · *.parquet 를 담은 디렉터리)으로 **소비 원천을 재도출**(원천 목록 하드코딩 없음)해 sources 에 싣고,
#   지문 밖 원천(uncovered)은 대조가 unverified("src:<이름>")로 드러낸다 — 원장은 그 대조를 '일치'로 세지 않는다.
#   digest 밖 정보 필드다(판본 식별 = 해시한 원천 · 범위 = 이 필드). 고정 소비자(러너·하네스·셀 엔진)의 토큰은 쓰지 않는다 —
#   그 코드의 캐시 키 목록(rf_base_cache.R)·도장 문자열이 원천으로 오인돼 모든 entry 가 상시 미확인이 된다(상시 오탐 = 상시 침묵).
#   한계: 설정 JSON 경로(rf_sleeve ic_path 등)·로더 함수 안에 숨은 경로(load_investor)·계산된 파일 이름은 못 본다.
# ★적재 = 키 + 소비 열만 · mmap=FALSE(Windows 1224 — 읽는 동안 daily_refresh 의 파일 교체를 막지 않게).
# ★이 절은 config.R·전역(CACHE_DIR/PINS_DIR)에 기대지 않는다. 소비자(reinforce_ledger.R · run_paper_replication.R)는
#   이 파일을 통째로 source 하지 않고 `pin_fingerprint*`·`pin_complete_month_end`·`pin_fp_*`·`.pin_fp_*` 정의만 parse→eval 한다
#   (파일 머리의 config.R source 부작용 회피) — 그래서 base R + arrow:: + tools:: + utils:: (+ 있으면 digest::) 만 쓴다.
.pin_fp_SCHEME   <- "pin_fp_v2"
.pin_fp_RAW_KEYS <- c("Date", "Ticker")
.pin_fp_BM_KEYS  <- "Date"
# 소비자 진입점(코드 경로 — 열 목록이 아니다): 러너(유니버스·가중·절단) · 하네스(수익 계산) · 셀 엔진(모든 강화 칸의 엔진)
.pin_fp_CONSUMERS <- c("02_Infrastructure/alpha_search/run_paper_replication.R",
                       "02_Infrastructure/replication/replication_harness.R",
                       "02_Infrastructure/reinforcement/rf_cell_engine.R")
# source() 폐포를 따라가는 범위 — 측정 계층(패널을 인자로 받는 조수 파일이 사는 곳). 공용 라이브러리(config·차트·계약)는 패널 열을
#   계산하지 않고 토큰만 넓혀 오탐을 키우므로 따라가지 않는다. 엔진 파일은 자기 디렉터리 안 source 를 따라간다.
.pin_fp_CONSUMER_SCOPE <- c("02_Infrastructure/alpha_search", "02_Infrastructure/replication", "02_Infrastructure/reinforcement")
# 지문이 해시하는 원천의 파일 이름(적재 기본 경로 = <root>/.cache/<이름>) — 소비 원천 중 '덮인 것' 판정에 같은 이름을 쓴다.
.pin_fp_RAW_FILE <- "RAWDATA.parquet"
.pin_fp_BM_FILE  <- "benchmark.parquet"
.pin_fp_FDB_DIR  <- "factor_db"

.pin_fp_md5_raw <- function(b, via_file = FALSE) {
  if (!via_file && length(b) && requireNamespace("digest", quietly = TRUE))
    return(digest::digest(b, algo = "md5", serialize = FALSE))
  f <- tempfile("pinfp_"); on.exit(unlink(f), add = TRUE)
  writeBin(b, f)
  unname(as.character(tools::md5sum(f)))
}
.pin_fp_md5 <- function(lines) .pin_fp_md5_raw(charToRaw(enc2utf8(paste(lines, collapse = "\n"))))
.pin_fp_s1 <- function(x) {
  x <- tryCatch(suppressWarnings(as.character(unlist(x))), error = function(e) character(0))
  if (length(x) != 1L || is.na(x)) "" else x
}
.pin_fp_chr <- function(x) {
  x <- tryCatch(suppressWarnings(as.character(unlist(x))), error = function(e) character(0))
  x[!is.na(x)]
}
.pin_fp_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x, tz = "Asia/Seoul"))   # run_paper_replication.R 의 Date 변환과 같은 tz
  as.Date(as.character(x))
}
.pin_fp_cutoff <- function(cutoff) {
  if (is.null(cutoff) || !length(cutoff)) return(as.Date(NA))
  c1 <- cutoff[1]
  if (is.na(c1)) return(as.Date(NA))
  d <- tryCatch(.pin_fp_date(c1), error = function(e) as.Date(NA))
  if (is.na(d)) stop("[pin_fingerprint] cutoff 해석 불가: ", as.character(c1))
  d
}
.pin_fp_root <- function(root = NULL) {
  if (!is.null(root) && length(root) && !is.na(root[1]) && nzchar(root[1])) return(as.character(root[1]))
  for (v in c("QM_ROOT", "CLAUDE_PROJECT_DIR")) { r <- Sys.getenv(v, ""); if (nzchar(r)) return(r) }
  stop("[pin_fingerprint] root 미지정 — root 인자 또는 QM_ROOT 필요(운영 경로를 추측하지 않는다)")
}

## ── 소비 열 재도출 ─────────────────────────────────────────────────────────────
# 코드 루트 후보 — 호출자가 code_root 를 주면 그것(+ root)만(결정론 · 검사 격리), 안 주면 root → QM_ROOT → CLAUDE_PROJECT_DIR.
.pin_fp_code_roots <- function(code_root = NULL, root = NULL) {
  r <- if (length(code_root)) c(code_root, root) else c(root, Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""))
  r <- unique(as.character(r[!is.na(r) & nzchar(r)]))
  if (!length(r)) stop("[pin_fingerprint] 코드 루트 미지정 — 소비 열을 재도출할 소비자 코드를 찾을 수 없다")
  r
}
.pin_fp_norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
.pin_fp_resolve <- function(rel, bases) {
  if (!length(rel) || is.na(rel) || !nzchar(rel)) return(NA_character_)
  if (grepl("^([A-Za-z]:)?[/\\\\]", rel) && file.exists(rel)) return(.pin_fp_norm(rel))
  for (b in bases) { p <- file.path(b, rel); if (file.exists(p) && !dir.exists(p)) return(.pin_fp_norm(p)) }
  NA_character_
}
# source()/sys.source() 의 파일 인자에서 문자열 상수를 모아 상대 경로로 잇는다(file.path(.X, "a", "b.R") → "a/b.R").
#   변수만으로 된 경로(source(factor_engine_path))는 정적으로 풀 수 없어 건너뛴다 — 엔진은 호출자가 engines 로 넘긴다.
.pin_fp_src_refs <- function(ex) {
  out <- character(0)
  lits <- function(e) {
    if (is.character(e)) return(e)
    if (!is.call(e)) return(character(0))
    l <- as.list(e); r <- character(0)
    for (i in seq_along(l)[-1L]) if (!identical(l[[i]], quote(expr = ))) r <- c(r, lits(l[[i]]))
    r
  }
  walk <- function(e) {
    if (!is.call(e)) return(invisible(NULL))
    l <- as.list(e)
    f <- l[[1L]]
    if (is.name(f) && as.character(f) %in% c("source", "sys.source") && length(l) >= 2L && !identical(l[[2L]], quote(expr = ))) {
      s <- lits(l[[2L]]); s <- s[!is.na(s) & nzchar(s)]
      if (length(s) && grepl("\\.[Rr]$", s[length(s)])) out <<- c(out, paste(s, collapse = "/"))
    }
    for (i in seq_along(l)) if (!identical(l[[i]], quote(expr = ))) walk(l[[i]])
    invisible(NULL)
  }
  for (e in as.list(ex)) walk(e)
  unique(out)
}
# 파일 토큰 — 기호(SYMBOL)·문자열 상수(STR_CONST 의 값). 함수 호출 기호·인자 이름·주석은 세지 않는다.
.pin_fp_tokens <- function(path) {
  ex <- parse(path, encoding = "UTF-8", keep.source = TRUE)
  pd <- utils::getParseData(ex, includeText = TRUE)
  tk <- character(0)
  if (!is.null(pd) && nrow(pd)) {
    sy <- pd$text[pd$token == "SYMBOL"]
    st <- pd$text[pd$token == "STR_CONST"]
    st <- vapply(st, function(s) tryCatch({ v <- eval(str2lang(s), baseenv()); if (is.character(v) && length(v) == 1L) v else "" },
                                          error = function(e) ""), character(1), USE.NAMES = FALSE)
    tk <- unique(c(sy, st[nzchar(st)]))
  }
  list(tokens = tk, ex = ex)
}
#' 측정 경로 소비자 코드와 그 토큰 — 진입점(.pin_fp_CONSUMERS) + 엔진(engines) + source() 폐포(범위 안).
#' @param code_root 코드 루트 후보(벡터 · 앞이 우선) — 없으면 root·QM_ROOT·CLAUDE_PROJECT_DIR. 진입점이 한 곳에도 없으면 멈춘다.
#' @return list(files = 상대/절대 경로, md5, tokens, engines_missing)
pin_fp_consumers <- function(code_root = NULL, engines = NULL, root = NULL) {
  roots <- .pin_fp_code_roots(code_root, root)
  nroots <- .pin_fp_norm(roots)
  queue <- character(0)
  for (rel in .pin_fp_CONSUMERS) {
    p <- .pin_fp_resolve(rel, roots)
    if (is.na(p)) stop(sprintf("[pin_fingerprint] 소비자 코드 부재: %s (코드 루트 %s) — 소비 열을 재도출할 수 없다",
                               rel, paste(roots, collapse = " | ")))
    queue <- c(queue, p)
  }
  eng <- as.character(engines); eng <- eng[!is.na(eng) & nzchar(eng)]
  eng_dirs <- character(0); eng_missing <- character(0); eng_q <- character(0)
  for (e in eng) {
    p <- .pin_fp_resolve(e, roots)
    if (is.na(p)) { eng_missing <- c(eng_missing, e); next }
    queue <- c(queue, p); eng_q <- c(eng_q, p); eng_dirs <- c(eng_dirs, dirname(p))
  }
  scope <- tolower(c(as.vector(outer(nroots, .pin_fp_CONSUMER_SCOPE, file.path)), eng_dirs))
  walk <- function(queue) {
    seen <- character(0); md5 <- character(0); toks <- character(0)
    while (length(queue)) {
      p <- queue[1L]; queue <- queue[-1L]
      if (tolower(p) %in% tolower(seen)) next
      seen <- c(seen, p)
      tk <- .pin_fp_tokens(p)
      toks <- union(toks, tk$tokens)
      md5 <- c(md5, unname(as.character(tools::md5sum(p))))
      for (ref in .pin_fp_src_refs(tk$ex)) {
        q <- .pin_fp_resolve(ref, c(roots, file.path(roots, "02_Infrastructure"), dirname(p)))
        if (is.na(q) || tolower(q) %in% tolower(seen)) next
        if (any(startsWith(tolower(q), paste0(scope, "/")))) queue <- c(queue, q)
      }
    }
    list(seen = seen, md5 = md5, toks = toks)
  }
  W <- walk(queue)
  # 엔진 폐포만의 토큰(F2 — 소비 원천 재도출용). 고정 소비자 토큰은 원천 재도출에 쓰지 않는다(.pin_fp_sources 머리 주석).
  WE <- if (length(eng_q)) walk(eng_q) else list(seen = character(0), toks = character(0))
  rel_of <- function(p) {
    for (r in nroots) { pre <- paste0(tolower(r), "/"); if (startsWith(tolower(p), pre)) return(substring(p, nchar(pre) + 1L)) }
    p
  }
  list(files = vapply(W$seen, rel_of, character(1), USE.NAMES = FALSE), md5 = W$md5, tokens = W$toks, engines_missing = eng_missing,
       engine_files = vapply(WE$seen, rel_of, character(1), USE.NAMES = FALSE), engine_tokens = WE$toks)
}
#' 소비 원천 재도출(F2 · ★원천 목록 하드코딩 없음) — 엔진 폐포 토큰 ∩ <cache_dir> 데이터 항목(*.parquet 파일 · *.parquet 를 담은 디렉터리).
#'   파일 이름은 대소문자 무시(Windows 파일 시스템) · 디렉터리 이름은 정확 일치(필터 문자열 "DART" 가 dart/ 를 가리키지 않게).
#'   고정 소비자 토큰은 쓰지 않는다 — 셀 엔진의 기저 캐시 키 목록(rf_base_cache.R 보조 원천 이름)·도장 문자열이 원천으로 오인돼
#'   모든 entry 가 상시 미확인이 된다. 고정 소비자가 읽는 원천 = RAWDATA·벤치(load_rawdata)·팩터 DB(load_month_factors) = covered.
#' @param covered 지문이 해시하는 원천 이름(RAWDATA·벤치 파일 · 팩터 DB 디렉터리)
#' @return list(status = ok|not_derived|cache_dir_absent, consumed, covered, uncovered) — uncovered = 소비하나 지문 밖(대조가 unverified 로)
.pin_fp_sources <- function(consumers, cache_dir, covered) {
  if (is.null(consumers)) return(list(status = "not_derived"))
  if (!length(cache_dir) || is.na(cache_dir[1]) || !nzchar(cache_dir[1]) || !dir.exists(cache_dir[1]))
    return(list(status = "cache_dir_absent"))
  cd <- cache_dir[1]
  ent <- list.files(cd, all.files = FALSE, no.. = TRUE)
  isd <- dir.exists(file.path(cd, ent))
  fl <- ent[!isd & grepl("\\.parquet$", ent, ignore.case = TRUE)]
  dd <- ent[isd]
  dd <- dd[vapply(dd, function(d) length(list.files(file.path(cd, d), pattern = "\\.parquet$", ignore.case = TRUE)) > 0L,
                  logical(1), USE.NAMES = FALSE)]
  tk <- as.character(consumers$engine_tokens); tk <- tk[!is.na(tk) & nzchar(tk) & nchar(tk, type = "bytes") < 1024L]   # 경로가 될 수 없는 긴 문자열 제외
  tk <- unique(c(tk, tryCatch(basename(gsub("\\\\", "/", tk)), error = function(e) character(0))))
  cons <- sort(unique(c(fl[tolower(fl) %in% tolower(tk)], dd[dd %in% tk])), method = "radix")
  cov <- cons[tolower(cons) %in% tolower(as.character(covered))]
  list(status = "ok", basis = "engine_tokens_x_cache_listing", consumed = cons, covered = cov, uncovered = setdiff(cons, cov))
}
#' 소비 열 = 스키마 열 ∩ 소비자 토큰(키 제외 · radix 정렬 — 스키마 열 순서와 무관한 결정론)
pin_fp_consumed_cols <- function(schema, consumers, keys = .pin_fp_RAW_KEYS) {
  sort(setdiff(intersect(as.character(schema), consumers$tokens), keys), method = "radix")
}

## ── 해시 ─────────────────────────────────────────────────────────────────────
.pin_fp_keyvec <- function(x) if (is.factor(x) || is.character(x)) enc2utf8(as.character(x)) else as.double(unclass(x))
# 값 바이트 — 수치 = IEEE-754 double LE 원 비트 · 문자 = 사전 부호화(정렬된 고유값[길이접두 UTF-8 · NA 길이 -1] + 행별 사전 색인 int32).
#   사전 부호화는 단사(사전과 색인이 행 열을 정확히 결정)이고, 행마다 문자열을 잇는 것보다 약 3배 빠르다(1,400만 행 실측).
.pin_fp_bytes <- function(x) {
  if (is.factor(x)) x <- as.character(x)
  if (is.character(x)) {
    x <- enc2utf8(x)
    u <- sort(unique(x), method = "radix", na.last = TRUE)
    na <- is.na(u); us <- u; us[na] <- ""
    ln <- nchar(us, type = "bytes"); ln[na] <- -1L
    return(c(writeBin(c(length(u), as.integer(ln)), raw(), size = 4L, endian = "little"), charToRaw(paste(us, collapse = "")),
             writeBin(match(x, u), raw(), size = 4L, endian = "little")))
  }
  writeBin(as.double(unclass(x)), raw(), size = 8L, endian = "little")
}
# 키 정렬 바이트 해시(연도별 · 첫 키 = Date). 반환 = 지문 부분(raw/bm) list.
.pin_fp_keyed <- function(tab, cutoff, keys, cols, absent_why) {
  if (is.null(tab) || !all(keys %in% names(tab))) return(list(status = "absent", why = absent_why))
  d <- .pin_fp_date(tab[["Date"]])
  obs <- if (any(!is.na(d))) format(max(d, na.rm = TRUE)) else NA_character_
  keep <- !is.na(d)
  if (!is.na(cutoff)) keep <- keep & d <= cutoff
  have <- as.character(cols[cols %in% names(tab)])
  if (!any(keep)) return(list(status = "empty", why = "no_rows_le_cutoff", observed_max_date = obs))
  ri <- which(keep)
  kv <- c(list(as.integer(d[ri])), lapply(keys[-1L], function(k) .pin_fp_keyvec(tab[[k]][ri])))
  o <- do.call(order, c(unname(kv), list(method = "radix")))
  kv <- lapply(kv, `[`, o); ri <- ri[o]; n <- length(ri)
  dup <- 0L
  if (n > 1L) {
    same <- Reduce(`&`, lapply(kv, function(v) { a <- v[-1L]; b <- v[-n]; (a == b & !is.na(a) & !is.na(b)) | (is.na(a) & is.na(b)) }))
    dup <- sum(same)
    if (dup > 0L) {   # 키 중복 — 값까지 정렬 키로(행 순서 불변 유지)
      vv <- lapply(have, function(cn) .pin_fp_keyvec(tab[[cn]][ri]))
      o2 <- do.call(order, c(unname(kv), unname(vv), list(method = "radix")))
      kv <- lapply(kv, `[`, o2); ri <- ri[o2]
    }
  }
  dd <- kv[[1L]]
  y0 <- as.integer(format(as.Date(dd[1L], origin = "1970-01-01"), "%Y"))
  y1 <- as.integer(format(as.Date(dd[n], origin = "1970-01-01"), "%Y"))
  yrs <- y0:y1
  st <- as.integer(as.Date(sprintf("%04d-01-01", c(yrs, y1 + 1L))))
  lo <- findInterval(st[-length(st)] - 1L, dd) + 1L; hi <- findInterval(st[-1L] - 1L, dd)
  y_id <- integer(0); y_n <- integer(0); y_h <- character(0); body <- character(0)
  key_y <- character(0); col_y <- stats::setNames(vector("list", length(have)), have)
  for (k in seq_along(yrs)) {
    if (hi[k] < lo[k]) next
    j <- lo[k]:hi[k]
    kh <- .pin_fp_md5_raw(do.call(c, lapply(kv, function(v) .pin_fp_bytes(v[j]))))
    ch <- vapply(have, function(cn) .pin_fp_md5_raw(.pin_fp_bytes(tab[[cn]][ri[j]])), character(1))
    ln <- sprintf("y=%d|n=%d|keys=%s|%s", yrs[k], length(j), kh, paste(sprintf("%s=%s", have, ch), collapse = "|"))
    y_id <- c(y_id, yrs[k]); y_n <- c(y_n, length(j)); y_h <- c(y_h, .pin_fp_md5(ln)); body <- c(body, ln)
    key_y <- c(key_y, kh)
    for (cn in have) col_y[[cn]] <- c(col_y[[cn]], ch[[cn]])
  }
  list(status = "ok", basis = "keyed_bytes", keys = keys, cols = have, cols_missing = setdiff(as.character(cols), have),
       n_rows = n, dup_keys = dup, max_date = format(as.Date(dd[n], origin = "1970-01-01")), observed_max_date = obs,
       years = y_id, year_n = y_n, year_md5 = y_h,
       key_md5 = .pin_fp_md5(key_y), col_md5 = lapply(col_y, .pin_fp_md5),
       md5 = .pin_fp_md5(c(paste0("keys=", paste(keys, collapse = ",")), paste0("cols=", paste(have, collapse = ",")), body)))
}
.pin_fp_raw <- function(raw, cutoff, cols) .pin_fp_keyed(raw, cutoff, .pin_fp_RAW_KEYS, cols, "raw_absent_or_no_keys")
.pin_fp_bm  <- function(bm, cutoff, cols)  .pin_fp_keyed(bm, cutoff, .pin_fp_BM_KEYS, cols, "bm_absent_or_no_date")

.pin_fp_fdb <- function(fdb_dir, cutoff) {
  if (is.null(fdb_dir) || !length(fdb_dir) || is.na(fdb_dir[1]) || !nzchar(fdb_dir[1]) || !dir.exists(fdb_dir[1]))
    return(list(status = "absent", why = "fdb_dir_absent"))
  f <- sort(list.files(fdb_dir[1], pattern = "^factor_db_[0-9]{6}\\.parquet$"), method = "radix")
  ym <- sub("^factor_db_([0-9]{6})\\.parquet$", "\\1", f)
  if (!is.na(cutoff)) { k <- ym <= format(cutoff, "%Y%m"); f <- f[k]; ym <- ym[k] }
  if (!length(f)) return(list(status = "empty", why = "no_fdb_month_files_le_cutoff"))
  sz <- file.size(file.path(fdb_dir[1], f))
  list(status = "ok", basis = "names_sizes", n_files = length(f), first_ym = ym[1], last_ym = ym[length(ym)],
       md5 = .pin_fp_md5(sprintf("%s|%.0f", f, sz)))
}
.pin_fp_bm_numeric <- function(bm) {
  if (is.null(bm)) return(character(0))
  names(bm)[vapply(names(bm), function(cn) cn != "Date" && (is.numeric(bm[[cn]]) || is.logical(bm[[cn]])), logical(1))]
}

#' 지문용 적재 — RAWDATA(키 + 소비 열 [+ extra_raw_cols] 중 있는 열) · benchmark(전 열 · 소형). 파일 부재는 why 로 남긴다(조용한 대체 없음).
#' @param raw_cols,bm_cols NULL = 소비자에서 재도출(code_root·engines) · 문자 벡터 = 그 열(재현·부모 지문 재측정)
#' @param extra_raw_cols 추가로 적재할 열(부모 지문 열 — 한 번 적재로 두 지문)
#' @return list(raw, bm, fdb_dir, why, raw_cols, bm_cols, consumers)
pin_fingerprint_load <- function(root = NULL, raw_path = NULL, bm_path = NULL, fdb_dir = NULL,
                                 raw_cols = NULL, bm_cols = NULL, code_root = NULL, engines = NULL, extra_raw_cols = NULL) {
  root <- .pin_fp_root(root)
  raw_path <- if (is.null(raw_path)) file.path(root, ".cache", .pin_fp_RAW_FILE) else raw_path
  bm_path  <- if (is.null(bm_path))  file.path(root, ".cache", .pin_fp_BM_FILE) else bm_path
  fdb_dir  <- if (is.null(fdb_dir))  file.path(root, ".cache", .pin_fp_FDB_DIR) else fdb_dir
  out <- list(raw = NULL, bm = NULL, fdb_dir = fdb_dir, why = character(0), raw_cols = raw_cols, bm_cols = bm_cols, consumers = NULL)
  if ((is.null(raw_cols) && file.exists(raw_path)) || (is.null(bm_cols) && file.exists(bm_path))) {   # 재도출은 적재할 파일이 있을 때만
    out$consumers <- pin_fp_consumers(code_root, engines, root)
    if (length(out$consumers$engines_missing)) out$why <- c(out$why, paste0("engine_absent:", out$consumers$engines_missing))
  }
  if (file.exists(raw_path)) {
    nm <- arrow::ParquetFileReader$create(raw_path, mmap = FALSE)$GetSchema()$names
    if (is.null(out$raw_cols)) out$raw_cols <- pin_fp_consumed_cols(nm, out$consumers, .pin_fp_RAW_KEYS)
    sel <- intersect(nm, unique(c(.pin_fp_RAW_KEYS, out$raw_cols, as.character(extra_raw_cols))))
    out$raw <- arrow::read_parquet(raw_path, col_select = tidyselect::all_of(sel), mmap = FALSE)
  } else out$why <- c(out$why, "raw_file_absent")
  if (file.exists(bm_path)) {
    out$bm <- arrow::read_parquet(bm_path, mmap = FALSE)
    if (is.null(out$bm_cols)) out$bm_cols <- pin_fp_consumed_cols(.pin_fp_bm_numeric(out$bm), out$consumers, .pin_fp_BM_KEYS)
  } else out$why <- c(out$why, "bm_file_absent")
  out
}

#' 직전 완결 월말 — 데이터가 그 월말을 **넘어섰음이 증명된** 마지막 월말.
#'   = min(RAWDATA 최대일, benchmark 최대일, today) 가 속한 달의 전달 말일.
#'   달력만 보면(오늘의 전달 말일) 월초 적재 전·장중 봉 적재(재발 사고) 때 덜 찬 달을 완결로 본다 — 그래서 데이터로 증명한다.
pin_complete_month_end <- function(raw_dates, bm_dates = NULL, today = Sys.Date()) {
  mx <- function(x) { x <- .pin_fp_date(x); x <- x[!is.na(x)]; if (length(x)) max(x) else as.Date(NA) }
  m <- mx(raw_dates)
  if (!is.null(bm_dates)) m <- min(m, mx(bm_dates))
  if (!is.null(today)) m <- min(m, as.Date(today))
  if (is.na(m)) return(as.Date(NA))
  as.Date(format(m, "%Y-%m-01")) - 1L
}

#' 데이터 빈티지 지문
#' @param cutoff NULL/NA = 전 행(절단 없음) · "YYYY-MM-DD"/Date = 그 날 이하 행만
#' @param raw,bm 적재된 데이터(data.frame/data.table) — NULL 이면 root 의 .cache 에서 키 + 소비 열만 적재
#' @param raw_cols,bm_cols NULL = 소비자 코드에서 재도출(code_root·engines) · 문자 벡터 = 그 열로(부모 지문 재측정 · 재현)
#' @param engines 측정 엔진 파일(충실구현 엔진 · 기저 엔진) — 그 파일(과 자기 디렉터리 안 source)이 읽는 열도 소비 열이다
#' @param consumers 이미 재도출한 소비자(pin_fp_consumers 결과) — 기록용 · 재계산 생략
#' @param cache_dir 소비 원천 재도출(F2)의 데이터 디렉터리 — NULL = raw_path 의 디렉터리 → fdb_dir 의 부모 → <root>/.cache
#' @return list(scheme, cutoff, status = ok|incomplete, digest, raw, bm, fdb, consumers, sources) — 같은 데이터·같은 cutoff·같은 열이면 identical
pin_fingerprint <- function(cutoff = NULL, raw = NULL, bm = NULL, root = NULL,
                            raw_path = NULL, bm_path = NULL, fdb_dir = NULL,
                            raw_cols = NULL, bm_cols = NULL, code_root = NULL, engines = NULL, consumers = NULL,
                            cache_dir = NULL) {
  co <- .pin_fp_cutoff(cutoff)
  why <- character(0)
  basis <- if (is.null(raw_cols) || is.null(bm_cols) || !is.null(consumers)) "derived" else "given"
  if (is.null(raw) || is.null(bm)) {
    L <- pin_fingerprint_load(root, raw_path, bm_path, fdb_dir, raw_cols, bm_cols, code_root, engines)
    if (is.null(raw)) raw <- L$raw
    if (is.null(bm)) bm <- L$bm
    if (is.null(fdb_dir)) fdb_dir <- L$fdb_dir
    if (is.null(raw_cols)) raw_cols <- L$raw_cols
    if (is.null(bm_cols)) bm_cols <- L$bm_cols
    if (is.null(consumers)) consumers <- L$consumers
    why <- L$why
  } else if (is.null(fdb_dir) && !is.null(root)) fdb_dir <- file.path(root, ".cache", .pin_fp_FDB_DIR)
  if (is.null(raw_cols) || is.null(bm_cols)) {   # 적재본을 받은 경우 — 받은 표의 열 이름이 스키마
    if (is.null(consumers)) {
      consumers <- pin_fp_consumers(code_root, engines, root)
      if (length(consumers$engines_missing)) why <- c(why, paste0("engine_absent:", consumers$engines_missing))
    }
    if (is.null(raw_cols)) raw_cols <- if (is.null(raw)) character(0) else pin_fp_consumed_cols(names(raw), consumers, .pin_fp_RAW_KEYS)
    if (is.null(bm_cols))  bm_cols  <- pin_fp_consumed_cols(.pin_fp_bm_numeric(bm), consumers, .pin_fp_BM_KEYS)
  }
  R <- .pin_fp_raw(raw, co, raw_cols); B <- .pin_fp_bm(bm, co, bm_cols); Fd <- .pin_fp_fdb(fdb_dir, co)
  ok <- identical(R$status, "ok") && identical(B$status, "ok")
  fp <- list(scheme = .pin_fp_SCHEME, cutoff = if (is.na(co)) NA_character_ else format(co),
             status = if (ok) "ok" else "incomplete", digest = NA_character_, raw = R, bm = B, fdb = Fd, cols_basis = basis)
  if (!is.null(consumers)) fp$consumers <- list(files = consumers$files, md5 = consumers$md5)
  # 소비 원천 범위(F2) — digest 밖 정보 필드. 지문 밖 원천(uncovered)은 대조가 unverified("src:<이름>")로 드러낸다.
  cdir <- if (length(cache_dir)) as.character(cache_dir[1]) else if (length(raw_path)) dirname(as.character(raw_path[1])) else
    if (length(fdb_dir)) dirname(as.character(fdb_dir[1])) else if (!is.null(root)) file.path(root, ".cache") else NA_character_
  fp$sources <- .pin_fp_sources(consumers, cdir,
                                c(if (length(raw_path)) basename(as.character(raw_path[1])) else .pin_fp_RAW_FILE,
                                  if (length(bm_path)) basename(as.character(bm_path[1])) else .pin_fp_BM_FILE,
                                  if (length(fdb_dir)) basename(as.character(fdb_dir[1])) else .pin_fp_FDB_DIR))
  # 창 완결 — 데이터(RAWDATA·벤치 모두)가 cutoff 를 넘어섰는가(pin_complete_month_end 의 증명과 같은 뜻). digest 밖 정보 필드:
  #   FALSE 인 지문은 덜 찬 달을 담았을 수 있다 — 나중에 그 달이 차면 같은 cutoff 대조가 history 개정으로 드러난다.
  fp$window_complete <- if (!ok || is.na(co)) NA else
    isTRUE(as.Date(R$observed_max_date) > co && as.Date(B$observed_max_date) > co)
  if (length(why)) fp$why <- why
  if (ok) fp$digest <- .pin_fp_md5(c(fp$scheme, fp$cutoff, R$md5, B$md5,
                                     if (identical(Fd$status, "ok")) Fd$md5 else paste0("fdb:", Fd$status)))
  fp
}

#' 두 지문 대조 — 같은 scheme·cutoff·열일 때만 비교한다(다르면 incomparable · 판정하지 않는다).
#' @return list(status = match|mismatch|incomparable|unknown, why, parts(다른 부분 raw/bm/fdb), years(raw 가 다른 연도),
#'   cols(다른 열 "raw:Vol"·"raw:keys"·"bm:BM_Ret"), unverified(한쪽만 확인 가능해 판정에서 뺀 부분 · 지문 밖 소비 원천 "src:<이름>"))
#'   ★status 는 해시한 원천(raw·bm·fdb)만의 판정이다 — unverified 가 비지 않은 match 를 '같은 판본'으로 읽지 말 것(원장 = unknown).
#'   원장에서 읽은 지문(simplifyVector=FALSE → 벡터가 list)도 그대로 받는다.
pin_fingerprint_compare <- function(a, b) {
  s1 <- .pin_fp_s1; ch <- .pin_fp_chr
  if (!is.list(a) || !is.list(b)) return(list(status = "unknown", why = "fingerprint_absent"))
  if (!identical(s1(a$status), "ok") || !identical(s1(b$status), "ok"))
    return(list(status = "unknown", why = sprintf("status:%s/%s", s1(a$status), s1(b$status))))
  if (!identical(s1(a$scheme), s1(b$scheme))) return(list(status = "incomparable", why = "scheme"))
  if (!identical(s1(a$cutoff), s1(b$cutoff))) return(list(status = "incomparable", why = "cutoff"))
  for (pt in c("raw", "bm"))
    if (!identical(ch(a[[pt]]$cols), ch(b[[pt]]$cols)) || !identical(ch(a[[pt]]$keys), ch(b[[pt]]$keys)))
      return(list(status = "incomparable", why = paste0(pt, "_cols")))
  parts <- character(0); unv <- character(0); cols <- character(0)
  for (pt in c("raw", "bm")) if (!identical(s1(a[[pt]]$md5), s1(b[[pt]]$md5))) {
    parts <- c(parts, pt)
    if (!identical(s1(a[[pt]]$key_md5), s1(b[[pt]]$key_md5))) cols <- c(cols, paste0(pt, ":keys"))
    for (cn in ch(a[[pt]]$cols)) if (!identical(s1(a[[pt]]$col_md5[[cn]]), s1(b[[pt]]$col_md5[[cn]]))) cols <- c(cols, paste0(pt, ":", cn))
  }
  fa <- s1(a$fdb$status); fb <- s1(b$fdb$status)
  if (identical(fa, "ok") && identical(fb, "ok")) {
    if (!identical(s1(a$fdb$md5), s1(b$fdb$md5))) parts <- c(parts, "fdb")
  } else if (!identical(fa, fb)) unv <- c(unv, "fdb")
  us <- sort(unique(c(ch(a$sources$uncovered), ch(b$sources$uncovered))), method = "radix")   # F2 — 지문 밖 소비 원천
  if (length(us)) unv <- c(unv, paste0("src:", us))
  yrs <- integer(0)
  if ("raw" %in% parts) {
    ya <- stats::setNames(ch(a$raw$year_md5), ch(a$raw$years))
    yb <- stats::setNames(ch(b$raw$year_md5), ch(b$raw$years))
    u <- sort(union(names(ya), names(yb)), method = "radix")
    yrs <- as.integer(u[is.na(ya[u]) | is.na(yb[u]) | ya[u] != yb[u]])
  }
  list(status = if (length(parts)) "mismatch" else "match", why = if (length(parts)) paste(parts, collapse = "+") else "",
       parts = parts, years = yrs, cols = cols, unverified = unv)
}
