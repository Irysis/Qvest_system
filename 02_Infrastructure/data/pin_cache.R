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
