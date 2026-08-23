#==============================================================================
# frontier_queue_io.R — alpha_frontier_queue.json 정본 read/write
#
# 2026-08-08 신설. 근거 = 같은 날 실측 census:
#   이 원장을 **쓰는 스크립트 18개** 중 `digits` 지정 9개(50%) · `pretty=1` 지정 **0개**.
#
# ★두 축이 각각 독립적으로 원장을 훼손한다:
#   ① digits 미지정 → jsonlite 기본 `digits=4` 로 **남의 항목 측정값이 반올림**된다
#      (실사고 2026-08-08: 0.009541984 → 0.0095). 파일은 유효 JSON이고 스키마도 맞아 **조용하다**.
#   ② pretty 불일치 → 이 파일의 정본 들여쓰기는 **1칸**인데 `pretty=TRUE`(2칸)로 쓰면
#      **3357추가/3333삭제** 전면 재직렬화가 난다. 데이터는 안 죽지만 **diff 를 못 읽게 되고**,
#      diff 를 못 읽으면 "순수 추가 확인"이라는 ①의 방어 규약이 **함께 무력해진다**.
#      (실사고 같은 날: 내가 검증한 13/4 가 병행 세션 재직렬화로 3417/3333 에 파묻힘.)
#
# ★★규약만으로는 안 됐다는 것이 census 의 결론이다 — `digits=NA` 규약은 메모리 카드로 전파돼
#   9/18 까지 갔지만 나머지 절반은 여전히 무방비였고, 형식 축(②)은 아무도 몰랐다.
#   ⇒ 방어를 **문서에서 함수로** 옮긴다. 앞으로 이 원장에 쓰는 모든 경로는 이 파일을 경유할 것.
#
#------------------------------------------------------------------------------
# 2026-08-08 개정 — ③ 동시쓰기(FQ-122 사건). 도훈 지시.
#------------------------------------------------------------------------------
# 위 ①②가 있는데도 FQ-122 갱신이 **두 번 유실**됐다. 이유: 유실 형태가 ①도 ②도 아니다.
#   · 항목 수 불변(167→167) → 가드1(소실) 통과
#   · 정밀도 불변(양쪽 digits=NA) → 가드2(반올림) 통과
#   · 유실된 것은 **그 사이 다른 실행이 넣은 필드 편집**이다.
#     A 가 읽고 → B 가 읽고 → B 가 쓰고 → A 가 **자기가 읽은 옛 판본**을 썼다.
#     A 의 판본도 완전한 유효 JSON 이라 형상 검사는 전부 통과한다.
#
# ⇒ 형상 검사로는 원리적으로 못 잡는다. 추가된 층(전부 shared_registry_io.R 제공):
#   ③ **CAS(기준 판본 검사)** — read 시 지문을 잡아두고, write 직전 디스크 지문과 대조.
#      바뀌었으면 거부하고 "재-read 후 재적용" 을 요구한다. ★이번 사고의 직접 대응.
#   ④ **churn 예산** — 변경 항목에서 정당한 줄 이동량을 도출해 실제와 대조.
#      전체 재직렬화(형식 드리프트 포함)는 예산을 수십 배 넘겨 걸린다.
#   ⑤ **뮤텍스** — fq_update_entry() 가 read-modify-write 를 직렬화한다.
#      ③이 있어도 ⑤가 없으면 정직한 두 실행이 서로를 계속 거부하며 진전하지 못한다
#      (③은 안전성, ⑤는 진행성).
#
# 사용 (권장 = 이 한 줄. 뮤텍스·CAS·예산이 전부 안에서 걸린다):
#   source("02_Infrastructure/ops/frontier_queue_io.R")
#   fq_update_entry("FQ-122", function(e) { e$status <- "..."; e })
#
# 저수준 (여러 항목을 한 번에 다룰 때):
#   Q <- read_frontier_queue(); Q$entries[[i]]$foo <- "bar"; write_frontier_queue(Q)
#   write_frontier_queue(Q, allow_shrink = "FQ-999 폐기 — 도훈 confirm 20260808")
#==============================================================================

suppressMessages(library(jsonlite))

.fq_self_dir <- tryCatch({
  f <- sys.frame(1)$ofile
  if (is.null(f)) NA_character_ else dirname(normalizePath(f, winslash = "/", mustWork = FALSE))
}, error = function(e) NA_character_)
.fq_source_shared <- function() {
  cands <- c(if (!is.na(.fq_self_dir)) file.path(.fq_self_dir, "shared_registry_io.R"),
             "02_Infrastructure/ops/shared_registry_io.R",
             file.path(Sys.getenv("CLAUDE_PROJECT_DIR", ""), "02_Infrastructure/ops/shared_registry_io.R"),
             file.path(Sys.getenv("QM_ROOT", ""), "02_Infrastructure/ops/shared_registry_io.R"))
  for (cand in cands) if (nzchar(cand) && file.exists(cand)) {
    source(cand, local = globalenv()); return(invisible(TRUE))
  }
  ## ★fail-closed: 가드 모듈이 없으면 **로드 자체를 실패시킨다**. 조용히 구판 동작으로
  ##   떨어지면 CAS 가 꺼진 채로 초록이 나온다 = 이 저장소의 "검사 사망" 형태.
  stop("[fq_io] shared_registry_io.R 를 찾지 못했다 — 동시쓰기 가드 없이 진행할 수 없다.")
}
.fq_source_shared()

FRONTIER_QUEUE_PATH <- "06_Registry/alpha_frontier_queue.json"

## 이 파일의 정본 직렬화 설정 — 무수정 왕복이 **바이트 동일**임을 2026-08-08 실측으로 확정
##   pretty=1 → 3335줄 원본과 완전 동일 / pretty=2·TRUE → 불일치 6328줄
.fq_serialize <- function(Q) {
  toJSON(Q, auto_unbox = TRUE, pretty = 1, digits = NA, null = "null", na = "null")
}

.fq_path <- function(path) {
  if (!is.null(path)) return(path)
  root <- Sys.getenv("QM_ROOT", "")
  if (nzchar(root) && dir.exists(root)) file.path(root, FRONTIER_QUEUE_PATH) else FRONTIER_QUEUE_PATH
}

## 고정밀 리터럴(소수 5자리 이상) 집합 — ①의 검거 축.
## 값이 아니라 **리터럴 문자열**로 비교한다: 반올림되면 문자열이 사라지므로 그것만 보면 된다.
## ★perl=TRUE 필수 (r-portability 금칙 ⑥, 2026-08-09 수리).
##   Windows TRE 는 매치 위치를 **UTF-16 코드유닛**으로 보고하는데 regmatches 는
##   **코드포인트**로 자른다 → 매치 **앞**에 non-BMP 문자(이모지)가 1개 있을 때마다
##   추출 창이 1칸 밀린다. 실측(R 4.5.2 / TRE 0.8.0, 이 저장소):
##     이모지 0개 → "-0.0715107"(정상) / 1개 → "0.0715107}" / 2개 → ".0715107}"
##   ★길이가 맞아 **오류가 아니라 숫자처럼 생긴 쓰레기**가 나온다 — 그래서 위험하다.
##   현 원장은 non-BMP 0개라 오늘은 정상값이 나오지만(TRE 54 == perl 54), 항목에
##   이모지가 한 글자 섞이는 순간 이 함수가 조용히 틀린 집합을 낸다. 그 집합이
##   정밀도 손실의 **검거 축**이므로, 밀리면 가드가 살아 있는 채로 눈이 먼다.
## ★2026-08-13 재적용: 본 파일의 CAS/뮤텍스 층(08-08 eloquent-cray)이 좌초해 있던 동안
##   main 에서 위 수리(3113ac4f)가 따로 들어갔다. 좌초분을 되살릴 때 구판을 그대로
##   덮으면 이 수리가 **조용히 되돌아간다** — 병합은 합집합이어야 한다.
.fq_precise_literals <- function(txt) {
  m <- unlist(regmatches(txt, gregexpr("-?[0-9]+[.][0-9]{5,}", txt, perl = TRUE)))
  unique(m)
}

#------------------------------------------------------------------------------
# (2026-08-23 v9 Lean Loop) 가드 2종 신설
#------------------------------------------------------------------------------
## ⑥ 사이드카 거부 — `06_Registry/*.bak*` 로는 쓰지 않는다.
##   실측: 06_Registry 에 `alpha_frontier_queue.json.bak*` 41개(19.3MB)가 쌓여 있고
##   그 각각이 원장의 옛 판본이다. 그래서 원장을 grep 하면 **사본이 함께 걸려**
##   "어느 판본을 인용했나" 가 사후에 구별되지 않는다. 백업은 이 계층이 만들 것이
##   아니라(CAS·뮤텍스가 이미 동시쓰기를 막는다) git 이 만든다.
##   ★거부는 **경로** 축이다 — 내용 검사로는 사본 쓰기를 못 잡는다(내용이 정상이니까).
FQ_SIDECAR_RX <- "06_Registry/[^/]*[.]bak"
.fq_refuse_sidecar <- function(p) {
  norm <- gsub("\\\\", "/", p)
  if (grepl(FQ_SIDECAR_RX, norm, perl = TRUE))
    stop("[fq_io] 사이드카 백업 경로에는 쓰지 않는다: ", basename(norm),
         "\n  06_Registry/*.bak* 는 원장 grep 을 오염시킨다(사본이 함께 걸린다).",
         "\n  판본 보존은 git 이 한다 — 백업을 만들려거든 06_Registry/_archive/ 아래 ",
         "이름 있는 파일로 둘 것.")
  invisible(TRUE)
}

## ⑦ status enum 검증 (schema 2.0) — `status` 는 4종만, 원문은 `status_raw` 에.
##   왜: schema 1.0 에서 `status` 가 자유서술이라 251건에 **137종**이 들어 있었다.
##   그 상태에서는 "지금 착수 가능한 항목이 몇 개인가" 를 기계가 답할 수 없다 —
##   큐가 있는데 큐 역할을 못 한다. v2 는 판정 축(enum)과 서술 축(status_raw)을 나눈다.
##   ★`status_raw` 는 자유롭게 둔다 — 접는 것이지 버리는 것이 아니다.
FQ_STATUS_ENUM <- c("open", "claimed", "done", "parked")
validate_status_enum <- function(entries, strict = TRUE) {
  bad <- character(0)
  for (e in entries) {
    s <- if (is.null(e$status)) NA_character_ else as.character(e$status)[1]
    if (is.na(s) || !(s %in% FQ_STATUS_ENUM))
      bad <- c(bad, sprintf("%s: '%s'", if (is.null(e$id)) "(id없음)" else e$id,
                            if (is.na(s)) "" else s))
  }
  if (length(bad) && strict)
    stop("[fq_io] status 가 enum 밖이다 (", length(bad), "건). ",
         "허용 = ", paste(FQ_STATUS_ENUM, collapse = "/"),
         "\n  ", paste(utils::head(bad, 8), collapse = "\n  "),
         "\n  ★원문 서술은 `status_raw` 에 넣을 것 — 그 필드는 자유다. ",
         "판정 축을 자유서술로 되돌리면 137종 상태로 되돌아간다(v2 마이그레이션의 사유).")
  invisible(bad)
}

#------------------------------------------------------------------------------
# 판본 상태 — read 가 잡고 write 가 대조한다 (③ CAS 의 보관소).
#
# ★attribute 가 아니라 별도 환경에 두는 이유: R 에서 리스트를 편집하다 보면
#   attribute 가 조용히 떨어지는 경로가 흔하다(재구성·lapply). 지문이 조용히 사라지면
#   CAS 가 **조용히 꺼진다** — "검사 사망" 은 이 저장소가 반복해 온 실패 형태이고,
#   검사가 죽은 모습은 통과와 겉보기가 같다.
#------------------------------------------------------------------------------
.fq_state <- new.env(parent = emptyenv())
.fq_key <- function(p) gsub("\\\\", "/", p)

read_frontier_queue <- function(path = NULL) {
  p <- .fq_path(path)
  if (!file.exists(p)) stop("[fq_io] 원장 부재: ", p)
  st <- sr_read(p)
  assign(.fq_key(p), st, envir = .fq_state)
  st$data
}

#' 방금 읽은 판본의 지문 (검사기·진단용)
fq_base_fingerprint <- function(path = NULL) {
  k <- .fq_key(.fq_path(path))
  if (!exists(k, envir = .fq_state, inherits = FALSE)) return(NA_character_)
  get(k, envir = .fq_state)$fingerprint
}

#------------------------------------------------------------------------------
# churn 예산 도출 — 임의 상수가 아니라 **변경 항목에서 계산**한다.
#   예산 = (변경·삭제된 옛 항목들의 줄 수) + 헤더 여유
#   ⇒ 1항목 편집이면 그 항목 줄 수 언저리, 전체 재직렬화면 수천 줄이 필요해져 걸린다.
#------------------------------------------------------------------------------
.FQ_HEADER_SLACK <- 60L   # schema_version/sot/updated/consume_rule 등 상단 필드 교체 여유

.fq_entry_txt <- function(e) as.character(.fq_serialize(e))
.fq_entry_lines <- function(e) length(strsplit(.fq_entry_txt(e), "\n", fixed = TRUE)[[1]])

.fq_churn_budget <- function(old_entries, new_entries) {
  gid <- function(e) if (is.null(e$id)) NA_character_ else as.character(e$id)[1]
  oid <- vapply(old_entries, gid, character(1))
  nid <- vapply(new_entries, gid, character(1))
  new_txt_by_id <- setNames(vapply(new_entries, .fq_entry_txt, character(1)), nid)
  touched <- 0L
  for (i in seq_along(old_entries)) {
    id <- oid[i]
    nt <- if (!is.na(id) && id %in% nid) new_txt_by_id[[id]] else NULL
    if (is.null(nt) || !identical(.fq_entry_txt(old_entries[[i]]), nt))
      touched <- touched + .fq_entry_lines(old_entries[[i]])
  }
  as.integer(touched + .FQ_HEADER_SLACK)
}

#' 정본 기록 — 손실 가드 통과 시에만 디스크에 쓴다.
#'
#' @param allow_shrink   항목 수가 줄어드는 기록을 허용할 사유(문자열).
#' @param allow_reformat 전체 재직렬화(형식 수렴)를 허용할 사유(문자열).
#' @param allow_stale_base ★CAS 를 끄는 유일한 문. 사유 필수 — 남의 갱신을 덮어쓴다는 뜻이다.
#' @return 불가시 side effect. invisible list(added=, removed=, n=, churn=, numstat=)
write_frontier_queue <- function(Q, path = NULL, allow_shrink = NULL,
                                 allow_reformat = NULL, allow_stale_base = NULL) {
  p <- .fq_path(path)
  .fq_refuse_sidecar(p)
  if (is.null(Q$entries) || !length(Q$entries)) stop("[fq_io] entries 가 비어 있다 — 기록 거부")
  validate_status_enum(Q$entries)

  new_txt <- .fq_serialize(Q)
  new_ids <- vapply(Q$entries, function(e) if (is.null(e$id)) NA_character_ else as.character(e$id)[1],
                    character(1))
  if (anyNA(new_ids)) stop("[fq_io] id 없는 항목 ", sum(is.na(new_ids)), "건 — 기록 거부")
  if (anyDuplicated(new_ids)) stop("[fq_io] 중복 id: ",
                                   paste(unique(new_ids[duplicated(new_ids)]), collapse = ", "))

  added <- character(0); removed <- character(0); churn <- NULL
  if (file.exists(p)) {
    ## ── ③ CAS — 내가 읽은 판본이 아직 디스크에 있는가 ──────────────────────
    k  <- .fq_key(p)
    st <- if (exists(k, envir = .fq_state, inherits = FALSE)) get(k, envir = .fq_state) else NULL
    if (is.null(st)) {
      if (is.null(allow_stale_base))
        stop(sprintf(paste0(
          "[fq_io] 이 프로세스는 %s 를 read_frontier_queue() 로 읽은 적이 없다 — 기준 판본이 없다.\n",
          "  기준 없는 쓰기는 병행 세션의 갱신을 덮어써도 아무도 모른다(2026-08-08 FQ-122).\n",
          "  read_frontier_queue() 로 읽어 편집하거나, fq_update_entry() 를 쓸 것."), basename(p)))
      message("[fq_io] ⚠ 기준 판본 없이 기록 (사유: ", allow_stale_base, ")")
      st <- sr_read(p)
    } else if (is.null(allow_stale_base)) {
      sr_assert_base_unchanged(p, st$fingerprint, what = basename(p))
    } else {
      message("[fq_io] ⚠ CAS 우회 (사유: ", allow_stale_base, ") — 남의 갱신을 덮어쓸 수 있다")
      st <- sr_read(p)
    }

    old_txt <- st$text
    old <- st$data
    old_ids <- vapply(old$entries, function(e) if (is.null(e$id)) NA_character_ else as.character(e$id)[1],
                      character(1))
    added   <- setdiff(new_ids, old_ids)
    removed <- setdiff(old_ids, new_ids)

    ## 가드 1 — 항목 소실 (병행 세션이 그 사이 등재한 항목을 덮어쓰는 사고의 검거 축)
    if (length(removed) && is.null(allow_shrink))
      stop("[fq_io] 항목 ", length(removed), "건이 사라진다: ",
           paste(head(removed, 8), collapse = ", "),
           "\n  병행 세션 등재분을 덮어쓰는 중일 수 있다 — 재-read 후 다시 적용하거나, ",
           "의도한 삭제라면 allow_shrink=<사유> 를 넘길 것.")

    ## 가드 2 — 정밀도 훼손 (digits 축). 리터럴이 사라졌으면 반올림된 것이다.
    lost <- setdiff(.fq_precise_literals(old_txt), .fq_precise_literals(new_txt))
    ## 삭제가 허용된 항목에서 유래한 소실은 정상 — 남은 텍스트에 없으면서 삭제분에도 없을 때만 위반
    if (length(lost)) {
      still <- vapply(lost, function(x) grepl(x, new_txt, fixed = TRUE), logical(1))
      lost <- lost[!still]
    }
    if (length(lost))
      stop("[fq_io] 고정밀 값 ", length(lost), "개가 소실된다 (digits 반올림 의심): ",
           paste(head(lost, 6), collapse = ", "),
           "\n  toJSON(digits=NA) 경유인지 확인할 것 — 남의 항목 측정값이 훼손된다.")

    ## ── ④ churn 예산 — 전체 재직렬화 금지 ─────────────────────────────────
    budget <- .fq_churn_budget(old$entries, Q$entries)
    churn <- sr_churn_guard(old_txt, new_txt, budget, path = p, allow_reformat = allow_reformat)
  }

  writeLines(new_txt, p, useBytes = TRUE)

  ## 기록 후 재읽기 — 쓴 것이 실제로 읽히는지 (침묵 실패 차단)
  chk <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk)) stop("[fq_io] ★기록 후 재읽기 실패 — 파일이 깨졌다: ", p)
  if (length(chk$entries) != length(Q$entries))
    stop("[fq_io] ★기록 후 항목 수 불일치: 의도 ", length(Q$entries), " vs 디스크 ", length(chk$entries))

  ## 기록 후 지문 갱신 — 같은 프로세스가 연속으로 쓸 수 있게 한다(CAS 자기충돌 방지)
  assign(.fq_key(p), sr_read(p), envir = .fq_state)

  ns <- tryCatch(sr_numstat(p), error = function(e) NULL)
  message(sprintf("[fq_io] 기록 완료 — 항목 %d (추가 %d · 삭제 %d)%s%s%s",
                  length(new_ids), length(added), length(removed),
                  if (!is.null(churn)) sprintf(" · churn +%d/-%d", churn$added, churn$removed) else "",
                  if (!is.null(ns) && isTRUE(ns$tracked_change))
                    sprintf(" · numstat(vs HEAD, 누적) +%d/-%d", ns$added, ns$removed) else "",
                  if (!is.null(allow_shrink)) paste0(" · 축소사유: ", allow_shrink) else ""))
  invisible(list(added = added, removed = removed, n = length(new_ids),
                 churn = churn, numstat = ns))
}

# =============================================================================
# fq_update_entry — ★paved path. 뮤텍스 + 최신 read + 편집 + 가드 기록을 한 번에.
#
#   경합이 나도 **거부가 아니라 직렬화**되므로 두 실행이 모두 진전한다.
#   (CAS 단독이면 진 쪽은 재시도해야 한다 — 여기서는 뮤텍스 안에서 다시 읽으므로 불필요.)
#
#   mutate(entry) -> entry     (항목 1건 수정)
#   create = TRUE 면 부재 시 mutate(NULL) 의 반환을 신규 항목으로 추가.
# =============================================================================
fq_update_entry <- function(id, mutate, path = NULL, create = FALSE,
                            reason = NULL, wait_s = 20) {
  p <- .fq_path(path)
  sr_with_lock(p, {
    Q <- read_frontier_queue(p)
    ids <- vapply(Q$entries, function(e) if (is.null(e$id)) NA_character_ else as.character(e$id)[1],
                  character(1))
    i <- match(as.character(id)[1], ids)
    if (is.na(i)) {
      if (!isTRUE(create)) stop("[fq_io] 항목 없음: ", id, " (신규 등재는 create=TRUE)")
      ne <- mutate(NULL)
      if (is.null(ne$id)) ne$id <- as.character(id)[1]
      Q$entries[[length(Q$entries) + 1L]] <- ne
    } else {
      Q$entries[[i]] <- mutate(Q$entries[[i]])
      if (is.null(Q$entries[[i]]$id)) Q$entries[[i]]$id <- as.character(id)[1]
    }
    res <- write_frontier_queue(Q, p)
    if (!is.null(reason)) message("[fq_io] ", id, " — ", reason)
    invisible(res)
  }, wait_s = wait_s)
}

#' 현재 디스크 파일이 정본 형식인가 — 무수정 왕복이 바이트 동일한지 시험.
#' 거짓이면 다음 정본 기록이 1회 큰 diff 를 낸다(데이터 손실 아님, 형식 수렴).
frontier_queue_format_ok <- function(path = NULL) {
  p <- .fq_path(path)
  if (!file.exists(p)) return(NA)
  orig <- readLines(p, warn = FALSE, encoding = "UTF-8")
  rt <- strsplit(.fq_serialize(fromJSON(p, simplifyVector = FALSE)), "\n", fixed = TRUE)[[1]]
  identical(orig, rt)
}
