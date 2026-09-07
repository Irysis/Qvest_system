#==============================================================================
# rawdata_source_priority.R — RAWDATA 원천 우선순위 리졸버 (R 정본)
#
# 도훈 지시 2026-09-07: "퀀티와이즈 데이터가 있으면 이 데이터를 최우선 순위로 놓고,
#   네이버 크롤링으로 최신데이터 업데이트하기. 추후 퀀티와이즈 데이터 업데이트 되면
#   네이버 크롤링한 데이터를 퀀티 기준으로 바꿔주기." + 후속 확인 "퀀티 그대로 덮기".
#
# ─── 왜 리졸버가 따로 필요한가 (실측) ───────────────────────────────────────
# rawdata.parquet 을 쓰는 writer 가 넷인데 넷이 서로 다른 규칙으로 승패를 정하고 있었다:
#   ① incremental_update_file.R  : raw[!Date %in% update_dates] + append  → 날짜 단위 무조건 교체
#   ② naver_data_collector.R     : (Date,Ticker) 키 값 갱신               → incumbent source 를 **안 본다**
#   ③ krx_build_rawdata.R        : rbind(old, new) + unique(by=Date,Ticker) → 행 순서가 승패
#   ④ incremental_cache_update.R : rbindlist(new, api_only) + unique(...)   → 행 순서가 승패
# ②는 명백한 역전이다 — 재수집 범위에 퀀티 구간이 들어가면 정본이 보충 레인에 **조용히** 진다.
# ③④는 규칙이 아니라 우연이다(unique 는 첫 행을 남긴다는 구현 사실에 얹혀 있다).
# 한 곳만 고치면 다른 경로로 역전이 다시 들어오므로, 넷 전부가 이 파일을 경유한다.
#
# ─── 설계 원칙 ───────────────────────────────────────────────────────────────
# ① **판정은 설정에서 온다.** rank 는 06_Registry/rawdata_source_priority.json 이 정한다.
#    설정 부재 = 조용한 기본값이 아니라 stop(하드코딩 금지 규약).
# ② **결정 가능하면 규칙을 적용하고, 결정 불가면 정지한다.** 낮은 rank 가 높은 rank 를
#    덮으려 하면 그 행은 **적용하지 않고 기록**한다(스킵 = 규칙의 결과). 모르는 라벨·NA 는
#    스킵이 아니라 stop 이다 — 모르는 것을 최하위로 조용히 배정하면 새 원천이 영원히 안 보인다.
# ③ **조용한 통과 없음.** 어느 원천이 어느 원천을 몇 행 덮었는지 사이드카에 남는다.
#
# 사용법:
#   source(file.path(DATA_DIR, "rawdata_source_priority.R"))
#   cfg <- rawdata_priority_config()
#   d   <- rawdata_priority_decide(incumbent_source, incoming_source, cfg)   # 행별 판정
#   res <- rawdata_priority_dedup(dt, cfg)          # rbind 뒤 중복 해소(승자만 남김)
#   rawdata_priority_sidecar(summary, label = "naver_backfill")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# ─── 루트 해석 (r-portability: 정규화 먼저 → marker 검증 → 침묵 낙하 금지) ────
.rsp_root <- function() {
  if (exists("PROJECT_ROOT", envir = globalenv(), inherits = FALSE)) {
    p <- gsub("\\\\", "/", get("PROJECT_ROOT", envir = globalenv()))
    if (file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) return(p)
  }
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""))
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  for (p in cands) {
    if (file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) return(p)
    cat(sprintf("[rawdata_priority] 루트 후보 기각(marker 부재): %s\n", p), file = stderr())
  }
  stop("[rawdata_priority] PROJECT_ROOT 미해석 — marker 를 가진 후보 없음")
}

RAWDATA_SOURCE_PRIORITY_PATH <- file.path(.rsp_root(), "06_Registry/rawdata_source_priority.json")

.rsp_cfg_cache <- new.env(parent = emptyenv())

#' 우선순위 정본 — 06_Registry JSON. 부재 = 조용한 기본값이 아니라 stop.
rawdata_priority_config <- function(path = RAWDATA_SOURCE_PRIORITY_PATH, reload = FALSE) {
  if (!reload && !is.null(.rsp_cfg_cache[[path]])) return(.rsp_cfg_cache[[path]])
  if (!file.exists(path))
    stop("[rawdata_priority] 우선순위 정본 부재: ", path,
         " — 순위를 코드에 되살리지 말 것(하드코딩 금지). 원천이 늘었으면 그 파일에 등재하라.")
  cfg <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  req <- c("schema", "rank_semantics", "sources", "on_unknown_source", "on_na_source",
           "override_env", "post_overwrite_seam_recheck", "sidecar_dir")
  miss <- setdiff(req, names(cfg))
  if (length(miss)) stop("[rawdata_priority] 설정 키 결손: ", paste(miss, collapse = ", "))
  if (!identical(cfg$rank_semantics, "lower_wins"))
    stop("[rawdata_priority] 미지원 rank_semantics: ", cfg$rank_semantics,
         " — 의미를 바꾸려면 소비자도 함께 바꿔라(선언만 바꾸면 판정이 뒤집힌다)")
  src <- as.data.table(cfg$sources)
  if (!all(c("source", "rank") %in% names(src)))
    stop("[rawdata_priority] sources 에 source/rank 열이 없다")
  if (anyDuplicated(src$source))
    stop("[rawdata_priority] 중복 source 등재: ", paste(src$source[duplicated(src$source)], collapse = ", "))
  if (anyDuplicated(src$rank))
    stop("[rawdata_priority] 동률 rank 등재 — 동률이면 writer 실행 순서가 승패를 정한다: ",
         paste(src$source[duplicated(src$rank) | duplicated(src$rank, fromLast = TRUE)], collapse = ", "))
  cfg$sources <- src
  cfg$config_path <- path
  .rsp_cfg_cache[[path]] <- cfg
  cfg
}

#' source 라벨 → rank. 미등재/NA 는 NA_real_ (판정은 호출자가 정책으로 내린다).
rawdata_source_rank <- function(src, cfg = rawdata_priority_config()) {
  s <- as.character(src)
  s[!is.na(s) & !nzchar(trimws(s))] <- NA_character_   # 빈 문자열 = 라벨 부재로 읽는다
  as.numeric(cfg$sources$rank[match(s, cfg$sources$source)])
}

#' 명시 우회가 켜져 있는가 — env 이름조차 설정에서 온다(코드에 박지 않는다).
rawdata_priority_override <- function(cfg = rawdata_priority_config()) {
  nm <- as.character(cfg$override_env)
  if (!length(nm) || is.na(nm) || !nzchar(nm)) return(FALSE)
  identical(Sys.getenv(nm, unset = "0"), "1")
}

#' 행별 판정 — incoming 이 incumbent 를 덮어도 되는가.
#'
#' @param has_incumbent 그 자리에 **행이 실제로 있는가**. NULL 이면 incumbent_source 의
#'   비-NA 여부로 대신한다. ★이 인자가 필요한 이유: "겨룰 상대가 없다(신규 append)" 와
#'   "행은 있는데 라벨이 NA 다(출처 미상)" 는 완전히 다른 사건인데 둘 다 NA 로 보인다.
#'   구분 없이 NA 를 통과시키면 라벨 잃은 행을 아무 원천이나 덮게 된다.
#' @return data.table(incumbent_source, incoming_source, rank_*, decision, allow)
#'   decision ∈ {"no_incumbent", "incoming_wins", "incumbent_wins", "same_source",
#'               "override_inversion", "override_undecidable"}
#'   ★결정 불가(미등재 라벨 / NA 라벨)는 decision 이 아니라 **stop** 이다 —
#'     정책 on_unknown_source / on_na_source 가 'stop' 인 한.
rawdata_priority_decide <- function(incumbent_source, incoming_source,
                                    cfg = rawdata_priority_config(), context = "",
                                    has_incumbent = NULL) {
  # ★길이 0 은 "겨룰 행이 없다" 이지 재활용 대상이 아니다. max() 로 잡으면 스칼라
  #   incoming(=항상 길이 1) 때문에 n=1 이 되어 **0행이 1행으로 늘어난다**. 그 1행이
  #   호출자에서 `hit[!allow]` 같은 색인을 만나면 integer(0)[TRUE] = NA 가 되어
  #   set(i = NA) 로 번진다 — naver 일상 전진(전량 신규 append, 매칭 0)이 정확히 이 경로다.
  if (length(incumbent_source) == 0L || length(incoming_source) == 0L)
    return(data.table(incumbent_source = character(0), incoming_source = character(0),
                      rank_incumbent = numeric(0), rank_incoming = numeric(0),
                      decision = character(0), allow = logical(0),
                      has_incumbent = logical(0)))
  n <- max(length(incumbent_source), length(incoming_source))
  inc <- rep_len(as.character(incumbent_source), n)
  new <- rep_len(as.character(incoming_source), n)
  inc[!is.na(inc) & !nzchar(trimws(inc))] <- NA_character_
  new[!is.na(new) & !nzchar(trimws(new))] <- NA_character_
  hasi <- if (is.null(has_incumbent)) !is.na(inc) else rep_len(as.logical(has_incumbent), n)

  known <- cfg$sources$source
  ovr <- rawdata_priority_override(cfg)
  ctx <- if (nzchar(context)) paste0(" [", context, "]") else ""

  # ── 결정 불가 두 종류: 미등재 라벨 · NA 라벨 ──────────────────────────────
  bad_unknown <- (!is.na(inc) & !inc %in% known) | (!is.na(new) & !new %in% known)
  if (any(bad_unknown) && identical(cfg$on_unknown_source, "stop") && !ovr) {
    labs <- unique(c(inc[!is.na(inc) & !inc %in% known], new[!is.na(new) & !new %in% known]))
    stop(sprintf(paste0("[rawdata_priority]%s 미등재 원천 라벨 %d종(%s) — 판정 불가. ",
                        "세 번째 원천이 생겼다는 뜻이다. %s 에 등재하거나, 의도한 것이면 %s=1 로 우회하라."),
                 ctx, length(labs), paste(head(labs, 5), collapse = ", "),
                 basename(as.character(cfg$config_path)), as.character(cfg$override_env)))
  }
  # incoming 라벨 NA = writer 가 라벨을 안 찍었다 / incumbent 행은 있는데 라벨 NA = 출처 미상
  bad_na <- is.na(new) | (hasi & is.na(inc))
  if (any(bad_na) && identical(cfg$on_na_source, "stop") && !ovr)
    stop(sprintf(paste0("[rawdata_priority]%s source 가 NA 인 행 %d건(incoming %d · incumbent %d) — ",
                        "출처 미상은 최하위도 최상위도 아니다(관측이 아니다). ",
                        "writer 가 라벨을 찍게 하거나 %s=1 로 우회하라."),
                 ctx, sum(bad_na), sum(is.na(new)), sum(hasi & is.na(inc)),
                 as.character(cfg$override_env)))

  r_inc <- as.numeric(cfg$sources$rank[match(inc, known)])
  r_new <- as.numeric(cfg$sources$rank[match(new, known)])

  out <- data.table(incumbent_source = inc, incoming_source = new,
                    rank_incumbent = r_inc, rank_incoming = r_new,
                    decision = NA_character_, allow = NA, has_incumbent = hasi)
  out[!has_incumbent, `:=`(decision = "no_incumbent", allow = TRUE)]
  out[is.na(decision) & incumbent_source == incoming_source,
      `:=`(decision = "same_source", allow = TRUE)]
  # lower_wins: incoming rank 가 더 작거나 같으면 이긴다(같은 rank 는 위에서 same_source 로 걸렀다)
  out[is.na(decision) & is.finite(rank_incoming) & is.finite(rank_incumbent) &
        rank_incoming < rank_incumbent, `:=`(decision = "incoming_wins", allow = TRUE)]
  out[is.na(decision) & is.finite(rank_incoming) & is.finite(rank_incumbent) &
        rank_incoming > rank_incumbent,
      `:=`(decision = if (ovr) "override_inversion" else "incumbent_wins", allow = ovr)]
  # 여기까지 안 걸린 잔여 = 미등재/NA 인데 위 stop 을 안 밟은 행. 정상 경로에서는 우회를
  # 켰을 때만 생긴다. 정책이 'stop' 이 아니게 바뀌면 이 자리가 **조용한 통과**가 되므로
  # 우회가 아닌 잔여는 여기서 다시 막는다(부재를 판정으로 읽지 않는다).
  if (any(is.na(out$decision)) && !ovr)
    stop(sprintf(paste0("[rawdata_priority]%s 판정 불가 잔여 %d행 — 정책이 stop 이 아니다",
                        "(on_unknown_source=%s · on_na_source=%s). 조용한 통과를 만들지 말 것."),
                 ctx, sum(is.na(out$decision)),
                 paste(as.character(cfg$on_unknown_source), collapse = ""),
                 paste(as.character(cfg$on_na_source), collapse = "")))
  out[is.na(decision), `:=`(decision = "override_undecidable", allow = TRUE)]
  out[]
}

#' rbind 뒤 중복 해소 — **승자만 남긴다**. unique() 의 '첫 행을 남긴다'에 얹지 않는다.
#'
#' ★부작용 고지: 입력 `dt` 는 **참조로 재정렬**되고 보조 열 두 개가 붙었다 떼어진다.
#'   rawdata 는 1,400만 행이라 copy() 를 쓰면 메모리가 두 배가 된다 — 구판 `unique()` 와
#'   같은 비용에 맞춘다. 호출자는 전부 반환값을 곧바로 쓰므로 재정렬은 관측되지 않는다.
#'
#' @param dt   Date/Ticker/source 를 가진 data.table
#' @param key  중복 판정 키
#' @return list(dt=, n_before=, n_after=, n_dropped=, dropped_by=data.table(kept,dropped,n))
rawdata_priority_dedup <- function(dt, cfg = rawdata_priority_config(),
                                   key = c("Date", "Ticker"), context = "dedup") {
  stopifnot(is.data.table(dt))
  if (!all(key %in% names(dt))) stop("[rawdata_priority] 키 열 부재: ", paste(key, collapse = ", "))
  if (!"source" %in% names(dt))
    stop("[rawdata_priority] source 열 부재 — 우선순위를 판정할 축이 없다: ", context)
  n0 <- nrow(dt)
  if (n0 == 0L)
    return(list(dt = dt, n_before = 0L, n_after = 0L, n_dropped = 0L,
                dropped_by = data.table(kept = character(0), dropped = character(0), n = integer(0))))

  known <- cfg$sources$source
  ovr <- rawdata_priority_override(cfg)
  s <- as.character(dt$source); s[!is.na(s) & !nzchar(trimws(s))] <- NA_character_
  bad <- unique(s[!is.na(s) & !s %in% known])
  if (length(bad) && identical(cfg$on_unknown_source, "stop") && !ovr)
    stop(sprintf("[rawdata_priority][%s] 미등재 원천 라벨: %s — %s 에 등재하라.",
                 context, paste(head(bad, 5), collapse = ", "),
                 basename(as.character(cfg$config_path))))
  if (anyNA(s) && identical(cfg$on_na_source, "stop") && !ovr)
    stop(sprintf("[rawdata_priority][%s] source NA 행 %d건 — 출처 미상은 판정 불가.",
                 context, sum(is.na(s))))

  rk <- as.numeric(cfg$sources$rank[match(s, known)])
  # 미등재/NA 가 우회로 살아남은 경우: 최하위 + 원 순서 유지(등재된 어느 원천도 못 이긴다)
  rk[is.na(rk)] <- max(cfg$sources$rank) + 1
  d <- dt                                     # ★사본 없음 (부작용 고지는 위 docstring)
  set(d, j = ".rsp_rank", value = rk)
  set(d, j = ".rsp_ord", value = seq_len(nrow(d)))
  on.exit({ for (cc in c(".rsp_rank", ".rsp_ord"))
              if (cc %in% names(d)) set(d, j = cc, value = NULL) }, add = TRUE)
  setorderv(d, c(key, ".rsp_rank", ".rsp_ord"))
  win <- unique(d, by = key)

  # 무엇이 무엇에게 졌는지 — 세지 말고 재라. 탈락 0이면 14M setdiff 를 돌리지 않는다.
  n_drop <- nrow(d) - nrow(win)
  dropped_by <- if (n_drop > 0L) {
    lost <- d[!.rsp_ord %in% win$.rsp_ord]
    kk <- win[, c(key, "source"), with = FALSE]; setnames(kk, "source", "kept")
    m <- merge(lost[, c(key, "source"), with = FALSE], kk, by = key, all.x = TRUE)
    m[, .(n = .N), by = .(kept, dropped = source)][order(-n)]
  } else data.table(kept = character(0), dropped = character(0), n = integer(0))

  win[, c(".rsp_rank", ".rsp_ord") := NULL]
  list(dt = win, n_before = n0, n_after = nrow(win), n_dropped = n0 - nrow(win),
       dropped_by = dropped_by)
}

#' 사이드카 — 어느 원천이 어느 원천을 몇 행 덮었고 무엇이 스킵됐는지. .cache 아래.
rawdata_priority_sidecar <- function(payload, label, cfg = rawdata_priority_config(),
                                     root = .rsp_root(), dir_ = NULL) {
  dir_ <- if (is.null(dir_)) file.path(root, as.character(cfg$sidecar_dir)) else dir_
  dir.create(dir_, recursive = TRUE, showWarnings = FALSE)
  body <- c(list(schema = "rawdata_source_priority_sidecar_v1",
                 generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                 label = as.character(label),
                 config_path = as.character(cfg$config_path),
                 override_env = as.character(cfg$override_env),
                 override_active = rawdata_priority_override(cfg)), payload)
  js <- jsonlite::toJSON(body, auto_unbox = TRUE, digits = 10, na = "null", pretty = TRUE)
  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out <- file.path(dir_, sprintf("priority_%s_%s.json", as.character(label), ts))
  tmp <- paste0(out, ".tmp", Sys.getpid()); writeLines(js, tmp, useBytes = TRUE)
  if (file.exists(out)) file.remove(out); file.rename(tmp, out)
  latest <- file.path(dir_, sprintf("latest_%s.json", as.character(label)))
  tmp2 <- paste0(latest, ".tmp", Sys.getpid()); writeLines(js, tmp2, useBytes = TRUE)
  if (file.exists(latest)) file.remove(latest); file.rename(tmp2, latest)
  out
}

#' 요약 1줄 — 침묵 통과 금지.
rawdata_priority_print <- function(dec, label = "") {
  lbl <- if (nzchar(label)) paste0(":", label) else ""
  if (!is.data.table(dec) || nrow(dec) == 0L) {
    cat(sprintf("[rawdata_priority%s] 판정 대상 0행\n", lbl)); return(invisible(dec))
  }
  cnt <- dec[, .N, by = .(decision, incumbent_source, incoming_source)][order(-N)]
  cat(sprintf("[rawdata_priority%s] 판정 %d행 · 적용 %d · 스킵 %d\n",
              lbl, nrow(dec), sum(dec$allow %in% TRUE), sum(!(dec$allow %in% TRUE))))
  # ★sprintf 는 인자 하나가 길이 0이면 문자열 전체를 없앤다 — NA 를 문자로 바꿔 길이를 지킨다
  fmt1 <- function(x) { y <- as.character(x); y[is.na(y) | !nzchar(y)] <- "(none)"; y }
  for (i in seq_len(nrow(cnt)))
    cat(sprintf("    %-22s %-18s <- %-18s %7d\n", fmt1(cnt$decision[i]),
                fmt1(cnt$incumbent_source[i]), fmt1(cnt$incoming_source[i]), cnt$N[i]))
  invisible(dec)
}

cat("[rawdata_source_priority] Loaded. rawdata_priority_decide() / rawdata_priority_dedup() / rawdata_priority_sidecar()\n")
