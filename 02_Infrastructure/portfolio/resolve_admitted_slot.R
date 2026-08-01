## ============================================================================
## resolve_admitted_slot.R — 운용 중인 북(admitted book)의 슬롯·보유파일을 실측 해석
##
## 왜 필요한가 (도훈 mandate 2026-08-01 "날짜 하드코딩은 다 없애라"):
##   라이브 추적 스크립트들이 슬롯 경로와 보유 파일명을 **문자열로 박아** 두고 있었다.
##       ".../2-3.STR_1715_on_M4_R05_noLayer4_PG2/02_holdings_universe/20260701_..._cap_0p20.csv"
##   ① 파일명 안의 `20260701` 때문에 매달 낡아갔고(리밸런싱해도 7월 보유를 계속 읽음)
##   ② 슬롯 `2-3` 고정 때문에 2026-07-19 D3 swap-in(admitted = 슬롯 2-4) 이후
##      운용 중이 아닌 구 변형을 봤다.
##   두 결함 모두 **조용히** 틀린 값을 낸다 — 에러가 안 나므로 감지되지 않는다.
##
## 설계 원칙
##   - 권위 = `qepm/mailbox/governor/book_state.json` 의 `admitted_ids` (자본 게이트 SOT).
##   - 슬롯 매칭은 **정확 일치**: `^<번호>-<번호>.<ID>$`. substring 매칭 금지 —
##     `..._v2` / `OLD_...` / `..._DEPRECATED` 같은 형제 디렉토리를 함께 물어온다
##     (shell 판 `resolve_admitted_slot.sh` 에서 주입으로 실증: 순진한 substring = 4건).
##   - `admitted_ids` 는 **키 접근**으로만 읽는다. grep 하면 `admitted_ids_prior_pre_d3_swapin`
##     같은 형제 키가 섞인다(실측 24건).
##   - 실패 시 **조용히 넘어가지 않는다**: strict=TRUE 면 중단, FALSE 면 경고 + fallback 반환.
##   - 최신 보유 파일 = 파일명 사전순 최대(`YYYYMMDD` 접두). mtime 금지 —
##     재생성·복사에 흔들린다. ★`which.max(basename(x))` 금지: 문자를 숫자로
##     강제변환해 NA 를 낸다(2026-08-01 실측 버그).
##
## 사용
##   source(file.path(ROOT, "02_Infrastructure/portfolio/resolve_admitted_slot.R"))
##   s <- resolve_admitted_slot()      # list(id, slot, slot_dir, holdings_dir, holdings, tag, as_of, source)
## ============================================================================
suppressPackageStartupMessages({library(jsonlite)})

resolve_admitted_slot <- function(root       = Sys.getenv("CLAUDE_PROJECT_DIR",
                                                Sys.getenv("QM_ROOT", getwd())),
                                  book_state = NULL,
                                  fallback_id = NULL,
                                  strict     = TRUE,
                                  quiet      = FALSE) {

  .say <- function(...) if (!quiet) cat(sprintf(...))
  .fail <- function(msg) {
    if (strict) stop("[slot] ", msg, call. = FALSE)
    .say("[slot] ★해석 실패: %s\n", msg)
    NULL
  }

  if (is.null(book_state))
    book_state <- file.path(root, "qepm/mailbox/governor/book_state.json")
  fm_base <- file.path(root, "05_Production/2.Factor_Model")

  ## ── 1. admitted id ────────────────────────────────────────────────────────
  id <- NULL
  if (file.exists(book_state)) {
    bs  <- tryCatch(fromJSON(book_state), error = function(e) NULL)
    ## ★키 접근 (grep 금지 — admitted_ids_prior_* 형제 키 오염)
    ids <- if (is.null(bs)) NULL else bs[["admitted_ids"]]
    if (is.list(ids)) ids <- unlist(ids, use.names = FALSE)
    ids <- ids[!is.na(ids) & nzchar(ids)]
    if (length(ids) == 1L) {
      id <- ids[1]
    } else if (length(ids) > 1L) {
      return(.fail(sprintf("admitted_ids 가 %d건 — 단일 북 전제 위반. 호출부가 명시 선택해야 한다: %s",
                           length(ids), paste(ids, collapse = ", "))))
    }
  }
  if (is.null(id)) {
    if (is.null(fallback_id))
      return(.fail(sprintf("admitted_ids 해석 불가 (book_state=%s) 이고 fallback_id 미지정", book_state)))
    .say("[slot] ⚠ admitted_ids 해석 불가 — fallback_id 사용: %s\n", fallback_id)
    id <- fallback_id
  }

  ## ── 2. 슬롯 디렉토리 (정확 일치) ──────────────────────────────────────────
  if (!dir.exists(fm_base)) return(.fail(sprintf("2.Factor_Model 부재: %s", fm_base)))
  dirs <- list.dirs(fm_base, full.names = FALSE, recursive = FALSE)
  hit  <- grep(sprintf("^[0-9]+-[0-9]+\\.%s$", id), dirs, value = TRUE)   # 정확 일치만
  if (length(hit) != 1L)
    return(.fail(sprintf("슬롯 %d건 매칭 (정확히 1건이어야) — id=%s / 후보=%s",
                         length(hit), id,
                         if (length(hit)) paste(hit, collapse = ", ") else "(없음)")))
  slot_dir <- file.path(fm_base, hit)
  slot_no  <- sub("\\..*$", "", hit)

  ## ── 3. 최신 보유 파일 ─────────────────────────────────────────────────────
  hu <- file.path(slot_dir, "02_holdings_universe")
  wf <- if (dir.exists(hu)) list.files(hu, pattern = "_weights_cap_0p20\\.csv$", full.names = TRUE)
        else character(0)
  if (!length(wf)) return(.fail(sprintf("보유 파일 0건: %s", hu)))
  holdings <- wf[order(basename(wf))][length(wf)]     # 사전순 최대 = YYYYMMDD 최신
  bn <- basename(holdings)

  ## ── 4. 날짜·태그를 파일명에서 파생 (매핑표 하드코딩 금지) ────────────────
  m <- regmatches(bn, regexec("^(\\d{8})_(.+)_weights_cap_0p20\\.csv$", bn))[[1]]
  if (length(m) != 3L)
    return(.fail(sprintf("보유 파일명이 규약(YYYYMMDD_TAG_weights_cap_0p20.csv)과 불일치: %s", bn)))
  as_of <- as.Date(m[2], format = "%Y%m%d")
  tag   <- m[3]
  if (is.na(as_of)) return(.fail(sprintf("보유 파일명 날짜 파싱 불가: %s", bn)))

  .say("[slot] admitted=%s · 슬롯 %s · 보유 %s (as_of %s · tag %s)\n",
       id, slot_no, bn, as.character(as_of), tag)

  list(id = id, slot = slot_no, slot_dir = slot_dir, holdings_dir = hu,
       holdings = holdings, tag = tag, as_of = as_of,
       source = if (file.exists(book_state)) "book_state" else "fallback")
}


## ============================================================================
## live_track_lane() — 추적 레인(06_Registry/live_track/<id>) 확보 + 1회성 이력 승계
##
## 왜 승계가 필요한가:
##   추적 레인 이름은 북 ID다. 북이 교체되면(2026-07-19 D3 swap-in) 레인도 바뀌는데,
##   새 레인엔 `paper_nav.csv`/`daily_nav.csv` 가 없다. 그냥 두면 트래커가 **새로 seed** 해
##   배포 시작일이 교체일로 리셋되고 이전 추적이 끊긴 것처럼 보인다.
##   → 직전 레인에서 **한 번만** 복사하고 `LANE_MIGRATION` 행으로 사실을 남긴다.
##      (덮어쓰기 없음: 새 레인에 이미 파일이 있으면 손대지 않는다.)
##
## carry_from : 승계 원본 레인 id (없으면 승계 없이 디렉토리만 확보)
## files      : 승계 대상 파일명
## ============================================================================
live_track_lane <- function(id, root = Sys.getenv("CLAUDE_PROJECT_DIR",
                                        Sys.getenv("QM_ROOT", getwd())),
                            carry_from = NULL,
                            files = c("paper_nav.csv", "daily_nav.csv",
                                      "holdout_interval.json"),
                            quiet = FALSE) {
  .say <- function(...) if (!quiet) cat(sprintf(...))
  lt <- file.path(root, "06_Registry/live_track", id)
  dir.create(lt, recursive = TRUE, showWarnings = FALSE)
  if (is.null(carry_from) || identical(carry_from, id)) return(lt)

  src <- file.path(root, "06_Registry/live_track", carry_from)
  if (!dir.exists(src)) { .say("[lane] 승계 원본 부재: %s\n", src); return(lt) }

  for (f in files) {
    dst_f <- file.path(lt, f); src_f <- file.path(src, f)
    if (file.exists(dst_f) || !file.exists(src_f)) next     # 이미 있으면 절대 덮지 않는다
    file.copy(src_f, dst_f)
    .say("[lane] 이력 승계: %s  (%s → %s)\n", f, carry_from, id)
    ## paper_nav 는 승계 사실을 데이터에도 남긴다 (감사 가능성)
    if (identical(f, "paper_nav.csv")) {
      pn <- tryCatch(data.table::fread(dst_f), error = function(e) NULL)
      if (!is.null(pn) && all(c("date", "event", "note") %in% names(pn))) {
        pn[, date := as.character(date)]
        pn <- rbind(pn, data.table::data.table(
          date = as.character(Sys.Date()), event = "LANE_MIGRATION",
          note = sprintf("추적 레인 이관 %s → %s (admitted 북 교체 반영)", carry_from, id)),
          fill = TRUE)
        data.table::fwrite(pn, dst_f)
      }
    }
  }
  lt
}
