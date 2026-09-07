#==============================================================================
# seam_scale_guard.R — 수출본 이음매 레벨 연속성 가드 (R 정본)
#
# 도훈 승인 2026-09-07 (A안). 벤치 배관(naver_benchmark_update.py)이 이미 갖고 있던
# canonical scale + 앵커 후퇴 + SEAM_MAX_RET 로직을 **종목 배관에 이식**한다.
#
# ─── 왜 (실측) ───────────────────────────────────────────────────────────────
# incremental_update_file.R 은 base 수출본(quantiwise)과 증분 수출본(quantiwise_update)을
# 이어붙인 뒤 `Ret := Close / shift(Close) - 1` 로 수익률을 재계산한다. 그런데 두 수출본은
# **수정주가 조정기준이 다르다**. 그 이음매를 생가격 비율로 가로지르면 분할·액면 비율이
# 그대로 하루 수익률이 된다.
#
#   실측 2026-03-30: 2,548종 중 275종(10.8%)이 |Ret| > 0.35, 최대 Ret = +7,863%.
#     A000040: 2026-03-27 종가 398 → 03-30 종가 2015 (Ret +406%) 이고 그 뒤 2060 에 머문다.
#     배율이 5x(118) · 2x(49) · 10x(23) · 0.5x(13) · 0.2x(10) 로 깨끗이 군집한다 = 분할 지문.
#     인접일(03-27, 03-31)은 0건 — 실제 등락이 아니라 조정기준 단절이다.
#   같은 병이 naver 경계(2026-08-28 → 08-31)에도 5건 있다. 그쪽 배관은
#     naver_data_collector.R 의 `Ret := Close / Prev_Close - 1` 로, **기전이 동일**하다.
#
# 기존 가드(incremental_update_file.R L124 부근)는 **날짜 커버리지 구멍만** 본다.
# 레벨 연속성 가드가 없었다.
#
# ─── 어휘 (벤치 배관과 동일) ─────────────────────────────────────────────────
#   canonical_scale · anchor_date · anchor_close · seam_ret · n_offscale
#   SEAM_MAX_RET · SCALE_TOL · SCALE_LOOKBACK_DAYS   ← 값은 seam_guard_config.json 단일 정본
# 두 배관이 다른 이름으로 같은 일을 하면 다음 사람이 또 한쪽만 고친다.
#
# ─── 설계 원칙 ───────────────────────────────────────────────────────────────
# ① **부재를 거짓으로 읽지 않는다.** 비율을 못 구하는 종목(한쪽에만 존재 / 앵커 창 밖)은
#    "정상" 이 아니라 no_anchor · no_seam_close 로 남고, no_anchor 는 **차단**된다
#    (shift() 는 200일 전 행과도 비율을 만들어 내므로 미측정을 통과시키면 그게 오염이다).
# ② **조용히 통과시키지 않는다.** 어느 종목 몇 건을 어떻게 처리했는지 전부 사이드카에 남는다.
# ③ **문턱은 설정 + 데이터 구조.** 임의 문턱 대신 가격제한폭(데이터에서 관측)과
#    정수배 군집(분할 지문)을 쓴다. 값은 seam_guard_config.json.
#
# 사용법:
#   source(file.path(DATA_DIR, "seam_scale_guard.R"))
#   rep <- seam_scale_report(raw, seam_date = as.Date("2026-03-30"))   # ★Ret 재계산 앞
#   raw[, Ret := Close / shift(Close) - 1, by = Ticker]
#   raw <- seam_apply_actions(raw, rep)                                 # 처분 적용
#   seam_write_sidecar(rep, label = "quantiwise_update")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# ─── 루트 해석 (r-portability ③④: 정규화 먼저 → marker 검증 → 침묵 낙하 금지) ──
.seam_root <- function() {
  if (exists("PROJECT_ROOT", envir = globalenv(), inherits = FALSE)) {
    p <- gsub("\\\\", "/", get("PROJECT_ROOT", envir = globalenv()))
    if (file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) return(p)
  }
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""))
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])   # ★검사 전에 정규화
  for (p in cands) {
    if (file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) return(p)
    cat(sprintf("[seam_guard] 루트 후보 기각(marker 부재): %s\n", p), file = stderr())
  }
  stop("[seam_guard] PROJECT_ROOT 미해석 — marker 를 가진 후보 없음")
}

SEAM_GUARD_CONFIG_PATH <- file.path(.seam_root(), "02_Infrastructure/data/seam_guard_config.json")

.seam_cfg_cache <- new.env(parent = emptyenv())

#' 이음매 가드 설정 — 단일 정본 JSON. 부재 = 조용한 기본값이 아니라 stop.
seam_guard_config <- function(path = SEAM_GUARD_CONFIG_PATH, reload = FALSE) {
  key <- path
  if (!reload && !is.null(.seam_cfg_cache[[key]])) return(.seam_cfg_cache[[key]])
  if (!file.exists(path))
    stop("[seam_guard] 설정 부재: ", path, " — 문턱을 코드에 되살리지 말 것(하드코딩 금지)")
  cfg <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  req <- c("SEAM_MAX_RET", "SCALE_TOL", "SCALE_LOOKBACK_DAYS", "SCALE_SNAP_TOL",
           "SCALE_SPLIT_MAX", "SCALE_FAMILY", "SCALE_MAX_ANCHOR_GAP_SESSIONS",
           "SEAM_SCAN_SESSIONS", "rescale_ret_enabled")
  miss <- setdiff(req, names(cfg))
  if (length(miss)) stop("[seam_guard] 설정 키 결손: ", paste(miss, collapse = ", "))
  cfg$config_path <- path
  .seam_cfg_cache[[key]] <- cfg
  cfg
}

#' 후보 배율 계열 — 정수배와 그 역수(분할 지문). 임의 문턱이 아니라 구조.
seam_scale_candidates <- function(cfg = seam_guard_config()) {
  if (!identical(cfg$SCALE_FAMILY, "integer_and_reciprocal"))
    stop("[seam_guard] 미지원 SCALE_FAMILY: ", cfg$SCALE_FAMILY)
  p <- 2:as.integer(cfg$SCALE_SPLIT_MAX)
  sort(unique(c(as.numeric(p), 1 / p)))
}

#' 이음매 비율 1건 분류 — 벡터화.
#'
#' @param ratio  seam_close / anchor_close
#' @param gap    앵커와 이음매 사이 시장 세션 수 (정상 = 1)
#' @return data.table(canonical_scale, implied_ret, verdict, n_snap)
seam_classify_ratio <- function(ratio, gap = 1L, cfg = seam_guard_config()) {
  n <- length(ratio)
  gap <- rep_len(as.integer(gap), n)
  cand <- seam_scale_candidates(cfg)
  max_ret <- as.numeric(cfg$SEAM_MAX_RET)
  snap_tol <- as.numeric(cfg$SCALE_SNAP_TOL)
  max_gap <- as.integer(cfg$SCALE_MAX_ANCHOR_GAP_SESSIONS)

  out <- data.table(canonical_scale = rep(NA_real_, n), implied_ret = rep(NA_real_, n),
                    verdict = rep(NA_character_, n), n_snap = rep(NA_integer_, n))

  for (i in seq_len(n)) {
    r <- ratio[i]
    if (!is.finite(r) || r <= 0) { out$verdict[i] <- "no_seam_close"; next }
    g <- max(1L, gap[i])
    # 세션이 여러 개면 하루 상한을 그만큼 누적해 넓힌다 — 좁은 창의 상한을 넓은 창에
    # 그대로 쓰면 정상 종목을 오검거한다.
    tol_ret <- (1 + max_ret)^g - 1

    if (abs(r - 1) <= tol_ret) {
      out$canonical_scale[i] <- 1; out$implied_ret[i] <- r - 1
      out$verdict[i] <- "on_scale"; out$n_snap[i] <- 1L
      next
    }
    if (g > max_gap) { out$verdict[i] <- "stale_anchor"; out$implied_ret[i] <- r - 1; next }

    hit <- cand[abs(r / cand - 1) <= snap_tol]
    out$n_snap[i] <- length(hit)
    if (length(hit) == 1L) {
      out$canonical_scale[i] <- hit
      out$implied_ret[i] <- r / hit - 1
      out$verdict[i] <- "adjustment_basis_break"
    } else if (length(hit) >= 2L) {
      out$verdict[i] <- "ambiguous_scale"; out$implied_ret[i] <- r - 1
    } else {
      out$verdict[i] <- "unattributed_jump"; out$implied_ret[i] <- r - 1
    }
  }
  out
}

#' 앵커/이음매 종가 쌍 → 판정. **두 배관의 단일 진입점**.
#'
#' ★부재를 거짓으로 읽지 않는다: 비율을 못 구하는 두 경우가 서로 다른 사유로 갈린다.
#'   no_seam_close = 이음매 당일 행 자체가 없다(고칠 것이 없다)
#'   no_anchor     = 직전 유효 종가가 없다 — 비율 미측정이지 "정상" 이 아니다(차단)
seam_classify_pair <- function(anchor_close, seam_close, gap = 1L, cfg = seam_guard_config()) {
  n <- length(seam_close)
  anchor_close <- rep_len(anchor_close, n)
  out <- seam_classify_ratio(seam_close / anchor_close, gap, cfg)
  no_seam <- !is.finite(seam_close) | seam_close <= 0
  no_anch <- !no_seam & (!is.finite(anchor_close) | anchor_close <= 0)
  out[no_seam, `:=`(verdict = "no_seam_close", canonical_scale = NA_real_,
                    implied_ret = NA_real_, n_snap = NA_integer_)]
  out[no_anch, `:=`(verdict = "no_anchor", canonical_scale = NA_real_,
                    implied_ret = NA_real_, n_snap = NA_integer_)]
  out
}

#' 판정 → 처분. **두 배관이 같은 표를 쓴다** (한쪽만 고쳐지는 것을 막는 자리).
seam_action_for <- function(verdict, cfg = seam_guard_config()) {
  resc <- isTRUE(cfg$rescale_ret_enabled)
  fifelse(verdict == "on_scale", "none",
    fifelse(verdict == "adjustment_basis_break", if (resc) "rescale_ret" else "block_ret",
      fifelse(verdict %in% c("no_seam_close", "absent_at_seam"), "no_measure", "block_ret")))
}

#' 이음매 판정표 — 지정한 거래일들에 대해 종목별 레벨 연속성을 잰다.
#'
#' ★Ret 재계산 **앞**에서 부른다 — 판정은 오염된 Ret 이 아니라 Close 에서만 나온다.
#'
#' ★왜 하루가 아니라 창인가 (2026-09-07 실측): 이음매 당일 값이 **직전 수출본의 정지값
#'   그대로**인 종목이 있다. A001470 은 08-20~08-31 내내 347 로 붙어 있다가 09-01 에
#'   5820 으로 뛴다 — 이음매 당일(08-31)에는 비율 1.000 이라 '정상' 으로 보이고 단절은
#'   하루 뒤에 나타난다. 실측 08-31 5건 · 09-01 8건(|ret|>0.5)이 정확히 이 갈림이다.
#'   그래서 이음매 뒤 SEAM_SCAN_SESSIONS 세션까지 훑는다. 하루만 보면 절반을 놓친다.
#'
#' @param dt    Date/Ticker/Close 를 가진 data.table (rawdata)
#' @param dates 판정할 거래일 벡터 (보통 이음매 첫날 + 뒤 몇 세션)
#' @return list(dates, cfg, tbl, counts, actions, ...) — tbl 이 (Ticker, Date) 별 판정
seam_scan_report <- function(dt, dates, cfg = seam_guard_config()) {
  stopifnot(is.data.table(dt), all(c("Date", "Ticker", "Close") %in% names(dt)))
  dates <- sort(unique(as.Date(dates)))
  lookback <- as.integer(cfg$SCALE_LOOKBACK_DAYS)
  win_from <- min(dates) - lookback

  # 시장 세션 축 — 종목이 아니라 **시장**의 거래일로 간격을 센다(거래정지 식별용)
  sess <- sort(unique(dt[Date >= win_from & Date <= max(dates)]$Date))

  # ── 앵커 후퇴: 유효 종가 행만 남기고 shift 하면 직전 **유효** 종가가 앵커다 ──
  #    (벤치의 anchor 후퇴와 동형 — 정지·결측일을 건너뛰어 뒤로 물러난다)
  val <- dt[Date >= win_from & Date <= max(dates) & is.finite(Close) & Close > 0,
            .(Date, Ticker, Close)]
  setorder(val, Ticker, Date)
  val[, `:=`(anchor_close = shift(Close), anchor_date = shift(Date)), by = Ticker]

  tbl <- unique(dt[Date %in% dates, .(Ticker, Date, seam_close = Close)], by = c("Ticker", "Date"))
  tbl <- merge(tbl, val[, .(Ticker, Date, anchor_close, anchor_date)],
               by = c("Ticker", "Date"), all.x = TRUE)
  tbl[, anchor_gap_sessions := as.integer(match(Date, sess) - match(anchor_date, sess))]
  tbl[, ratio := seam_close / anchor_close]

  cls <- seam_classify_pair(tbl$anchor_close, tbl$seam_close,
                            ifelse(is.na(tbl$anchor_gap_sessions), 1L,
                                   tbl$anchor_gap_sessions), cfg)
  tbl[, `:=`(canonical_scale = cls$canonical_scale, implied_ret = cls$implied_ret,
             verdict = cls$verdict, n_snap = cls$n_snap)]
  # ── ★한쪽에만 존재하는 종목: "정상" 이 아니라 별도 사유로 남긴다 ──────────────
  #    이음매 직전까지 거래하다 창 안에서 **행 자체가 사라진** 종목. 고칠 Ret 은
  #    없지만(no_measure) 비율 미측정이므로 조용히 없던 일이 되면 안 된다.
  before <- val[Date < min(dates)]
  if (nrow(before)) {
    last_before <- before[, .(anchor_date = Date[.N], anchor_close = Close[.N]), by = Ticker]
    last_before[, gap_to_seam := as.integer(match(min(dates), sess) - match(anchor_date, sess))]
    gone <- last_before[gap_to_seam <= as.integer(cfg$SCALE_MAX_ANCHOR_GAP_SESSIONS) &
                        !Ticker %in% tbl$Ticker]
    if (nrow(gone))
      tbl <- rbind(tbl, data.table(
        Ticker = gone$Ticker, Date = as.Date(NA), seam_close = NA_real_,
        anchor_close = gone$anchor_close, anchor_date = gone$anchor_date,
        anchor_gap_sessions = gone$gap_to_seam, ratio = NA_real_,
        canonical_scale = NA_real_, implied_ret = NA_real_,
        verdict = "absent_at_seam", n_snap = NA_integer_), fill = TRUE)
  }

  tbl[, action := seam_action_for(verdict, cfg)]
  setorder(tbl, Date, verdict, Ticker, na.last = TRUE)

  counts <- tbl[, .N, by = verdict][order(-N)]
  acts <- tbl[, .N, by = action][order(-N)]
  list(schema = "seam_scale_report_v2",
       seam_date = as.character(min(dates)),
       dates = as.character(dates),
       n_tickers = nrow(tbl),
       n_offscale = tbl[!verdict %in% c("on_scale", "no_seam_close", "absent_at_seam"), .N],
       counts = counts, actions = acts, tbl = tbl,
       cfg = cfg[c("SEAM_MAX_RET", "SCALE_TOL", "SCALE_LOOKBACK_DAYS", "SCALE_SNAP_TOL",
                   "SCALE_SPLIT_MAX", "SCALE_FAMILY", "SCALE_MAX_ANCHOR_GAP_SESSIONS",
                   "SEAM_SCAN_SESSIONS", "rescale_ret_enabled", "config_path")])
}

#' 이음매 첫날 + 뒤 SEAM_SCAN_SESSIONS 세션의 거래일 목록.
seam_scan_dates <- function(dt, seam_date, cfg = seam_guard_config()) {
  seam_date <- as.Date(seam_date)
  n <- as.integer(cfg$SEAM_SCAN_SESSIONS)
  sess <- sort(unique(dt[Date >= seam_date]$Date))
  head(sess, max(1L, n))
}

#' 단일 이음매일 판정 (창 = 하루). seam_scan_report 의 특수형.
seam_scale_report <- function(dt, seam_date, cfg = seam_guard_config()) {
  seam_scan_report(dt, as.Date(seam_date), cfg)
}

#' 판정표의 처분을 Ret 에 적용한다 (Ret 재계산 **뒤**).
#'
#' rescale_ret : Ret := ratio / canonical_scale - 1  (조정계수 재정렬 — 벤치가 canonical
#'               scale 을 나눠 재체인하는 것과 같은 연산을 수익률 축에서 한 것)
#' block_ret   : Ret := NA  (특정 불가 = 조용히 통과시키지 않고 미측정으로 남긴다)
seam_apply_actions <- function(dt, rep) {
  stopifnot(is.data.table(dt), "Ret" %in% names(dt))
  tbl <- rep$tbl
  # ★판정된 **(Ticker, Date) 행만** 만진다. 티커 조인으로 전 이력을 건드리면 사고
  #   반경이 이음매를 넘어간다(이 저장소의 반복 병 — 결함 크기 ≠ 오염 크기).
  key_dt <- paste0(as.character(dt$Date), "|", dt$Ticker)
  key_tb <- paste0(as.character(tbl$Date), "|", tbl$Ticker)
  pos <- match(key_tb, key_dt)                    # tbl 행 → dt 행
  rep$ret_before <- ifelse(is.na(pos), NA_real_, dt$Ret[pos])

  wb <- which(tbl$action == "block_ret" & !is.na(pos))
  if (length(wb)) set(dt, i = pos[wb], j = "Ret", value = NA_real_)

  wr <- which(tbl$action == "rescale_ret" & !is.na(pos))
  if (length(wr)) {
    set(dt, i = pos[wr], j = "Ret", value = tbl$implied_ret[wr])
    # 사후검증(SCALE_TOL): 재정렬 결과가 정말 canonical scale 을 나눈 값인가
    if (max(abs(dt$Ret[pos[wr]] - tbl$implied_ret[wr]), na.rm = TRUE) > as.numeric(rep$cfg$SCALE_TOL))
      stop("[seam_guard] 재정렬 사후검증 FAIL — Ret 이 implied_ret 과 불일치")
  }
  rep$ret_after <- ifelse(is.na(pos), NA_real_, dt$Ret[pos])
  # ★처분이 있는 판정만 센다 — absent_at_seam 은 Date 가 없는(=행이 없는) 사유라
  #   구조적으로 미매칭이다. 그것까지 세면 경고가 상시 울려 진짜 유실을 덮는다.
  rep$n_unmatched <- sum(is.na(pos) & tbl$action %in% c("block_ret", "rescale_ret"))
  if (rep$n_unmatched > 0)
    cat(sprintf("  ⚠ [seam_guard] 판정 %d행이 dt 에서 미발견 — 처분 미적용\n", rep$n_unmatched))
  attr(dt, "seam_report") <- rep
  dt
}

#' 사이드카 — 어느 종목 몇 건을 어떻게 처리했는지. .cache 아래(원장 미접근).
seam_write_sidecar <- function(rep, label, root = .seam_root(), dir_ = NULL) {
  dir_ <- if (is.null(dir_)) file.path(root, ".cache", "seam_scale_guard") else dir_
  dir.create(dir_, recursive = TRUE, showWarnings = FALSE)
  tbl <- copy(rep$tbl)
  if (!is.null(rep$ret_before)) tbl[, ret_before := rep$ret_before]
  if (!is.null(rep$ret_after))  tbl[, ret_after  := rep$ret_after]
  tbl[, anchor_date := as.character(anchor_date)]
  if ("Date" %in% names(tbl)) tbl[, Date := as.character(Date)]

  payload <- list(
    schema = "seam_scale_guard_sidecar_v2",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    label = label, seam_date = rep$seam_date, dates = rep$dates,
    n_tickers = rep$n_tickers, n_offscale = rep$n_offscale,
    n_unmatched = rep$n_unmatched,
    verdict_counts = as.list(setNames(rep$counts$N, rep$counts$verdict)),
    action_counts = as.list(setNames(rep$actions$N, rep$actions$action)),
    config = rep$cfg,
    tickers = tbl[verdict != "on_scale"])          # on_scale 전량은 안 싣는다(수천 행)

  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out <- file.path(dir_, sprintf("seam_%s_%s_%s.json", label, gsub("-", "", rep$seam_date), ts))
  js <- jsonlite::toJSON(payload, auto_unbox = TRUE, digits = 10, na = "null", pretty = TRUE)
  # tmp → rename (제자리 쓰기는 조용히 자른다 — 벤치 _atomic_write_table 와 같은 규약)
  tmp <- paste0(out, ".tmp", Sys.getpid())
  writeLines(js, tmp, useBytes = TRUE)
  if (file.exists(out)) file.remove(out)
  file.rename(tmp, out)
  latest <- file.path(dir_, sprintf("latest_%s.json", label))
  tmp2 <- paste0(latest, ".tmp", Sys.getpid())
  writeLines(js, tmp2, useBytes = TRUE)
  if (file.exists(latest)) file.remove(latest)
  file.rename(tmp2, latest)
  out
}

#' 요약 1줄 — 침묵 통과 금지. 어떤 이음매를 재서 무엇을 했는지 항상 찍는다.
seam_report_print <- function(rep, label = "") {
  cat(sprintf("[seam_guard%s] 이음매 %s (창 %s ~ %s, %d세션) — 판정행 %d | off-scale %d\n",
              if (nzchar(label)) paste0(":", label) else "", rep$seam_date,
              rep$dates[1], rep$dates[length(rep$dates)], length(rep$dates),
              rep$n_tickers, rep$n_offscale))
  for (i in seq_len(nrow(rep$counts)))
    cat(sprintf("    %-24s %5d\n", rep$counts$verdict[i], rep$counts$N[i]))
  cat("    ── 처분 ──\n")
  for (i in seq_len(nrow(rep$actions)))
    cat(sprintf("    %-24s %5d\n", rep$actions$action[i], rep$actions$N[i]))
  invisible(rep)
}

cat("[seam_scale_guard] Loaded. seam_scale_report() / seam_apply_actions() / seam_write_sidecar()\n")
