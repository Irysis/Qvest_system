#==============================================================================
# rawdata_seam_audit.R — RAWDATA 원천 이음매 감사 (전 이력 · 2026-11-13)
#
# 왜 (실측 2026-11-13 · 도훈 "원천 이음매 결함 수리를 바로 시작해주고"):
#   2026-03-30 수정주가 기준 단절(base 수출본 → 증분 수출본 이음매)이 11-11 11:28 적재부터 측정 수익 계열에
#   그대로 들어갔다 — |Ret|>0.35 351종 · 등가중 +66% · 같은 날 KOSPI200 −3.1%. P1R03 엔진은 그날 하루 +75%.
#   가드(seam_scale_guard.R)는 있었지만 적재기가 Ret 을 전 이력 재계산하는 동안 창 밖 이음매를 다시 보지 않았다.
#   ★가드가 '돌았다'는 것과 '저장된 계열이 깨끗하다'는 것은 다른 명제다 — 이 파일은 뒤의 것을 **저장된 값에서** 잰다.
#
# 무엇을 재나 (전 이력 · 저장값 기준 · 설정 = seam_guard_config.json + rawdata_seam_audit_config.json):
#   ① 종목-일 지문(basis_break_scan.R 과 같은 판정축 — 크기가 아니라 발행주식수 불변성):
#        off        : |Ret| > SEAM_MAX_RET                       (가격제한폭 밖 하루 수익)
#        unrepaired : Ret == Close / 직전 행 Close − 1           (저장 Ret 이 생비율 그대로 — 가드가 손대지 않았다)
#        basis      : |r_shares − 1| > BASIS_SHARES_TOL ∧ |r_size − 1| ≤ SEAM_MAX_RET
#                     (주식수 = Size / Close 가 뛰었는데 시가총액은 하루치로 설명된다 = 분할 · 병합 비율이 수익이 됐다)
#      hit = off ∧ unrepaired ∧ basis. 등록부(basis_break_registry.json)의 원천 내부 단절 = known(세기만) · 그 밖 = new(경보 · 차단).
#      ★진짜 급등락(정리매매 · 상한가 연속 = 주식수 그대로)과 유상증자(주식수 · 시총 둘 다 움직임)는 hit 이 아니다.
#   ② 날짜 지문: 그날 |Ret| > SEAM_MAX_RET 비율 ≥ DAY_FRAC_OFF_ALARM ∧ 개수 ≥ DAY_N_OFF_MIN — 주식수 열이 같이 틀어진
#      이음매처럼 ①이 못 보는 집단 단절을 잡는다(실측 이음매 밖 최댓값 0.825% · 03-30 13.78%).
#
# 처분 (rsa_block_new · 적재기만 부른다): new hit 의 Ret := NA — 가드 block_ret 와 같은 처분(측정 차단 · Close 는 그대로라
#   다시 판정할 수 있다). 날짜 지문은 차단하지 않는다(경보만 — 어느 종목인지 모른다). 상태 = ok | alarm.
#
# 사용:
#   source(file.path(DATA_DIR, "rawdata_seam_audit.R"))
#   a <- rsa_audit(raw); raw <- rsa_block_new(raw, a); rsa_print(a, "incr_ohlcvs"); rsa_write_sidecar(a, "incr_ohlcvs")
#   CLI: Rscript 02_Infrastructure/data/rawdata_seam_audit.R [--rawdata P] [--label L] [--no-sidecar]
#        마지막 줄 RSA<TAB>status=ok|alarm<TAB>new=<n><TAB>known=<n><TAB>days=<n> · 종료 0 정상 · 3 경보 · 1 판독 불가
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})
if (!exists("%||%", mode = "function")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# 가드 정본을 먼저 싣는다 — 설정 로더(seam_guard_config)와 루트 해석(.seam_root)을 재사용한다(상수 두 벌 금지).
if (!exists("seam_guard_config", mode = "function")) {
  .rsa_self <- tryCatch({
    a <- commandArgs(trailingOnly = FALSE)
    f <- sub("^--file=", "", a[grepl("^--file=", a)])
    if (length(f)) dirname(normalizePath(f[1], mustWork = FALSE)) else NULL
  }, error = function(e) NULL)
  .rsa_cands <- c(
    if (exists("DATA_DIR")) file.path(get("DATA_DIR"), "seam_scale_guard.R"),
    if (!is.null(.rsa_self)) file.path(.rsa_self, "seam_scale_guard.R"),
    file.path(gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", "")), "02_Infrastructure/data/seam_scale_guard.R"),
    file.path(gsub("\\\\", "/", Sys.getenv("QM_ROOT", "")), "02_Infrastructure/data/seam_scale_guard.R"))
  .rsa_hit <- .rsa_cands[nzchar(.rsa_cands) & file.exists(.rsa_cands)]
  if (!length(.rsa_hit)) stop("[seam_audit] seam_scale_guard.R 미발견 — 설정 로더를 재정의하지 말 것(하드코딩 금지)")
  source(.rsa_hit[1])
}

.rsa_cfg_cache <- new.env(parent = emptyenv())

#' 감사 설정 — 이음매 상수는 seam_guard_config.json(정본) · 감사 상수는 rawdata_seam_audit_config.json. 부재 = stop.
rsa_config <- function(root = .seam_root(), reload = FALSE) {
  key <- root
  if (!reload && !is.null(.rsa_cfg_cache[[key]])) return(.rsa_cfg_cache[[key]])
  g <- seam_guard_config(file.path(root, "02_Infrastructure/data/seam_guard_config.json"), reload = reload)
  p <- file.path(root, "02_Infrastructure/data/rawdata_seam_audit_config.json")
  if (!file.exists(p)) stop("[seam_audit] 설정 부재: ", p, " — 문턱을 코드에 되살리지 말 것(하드코딩 금지)")
  a <- jsonlite::fromJSON(p, simplifyVector = TRUE)
  req <- c("DAY_FRAC_OFF_ALARM", "DAY_N_OFF_MIN", "RET_MATCH_TOL", "KNOWN_REGISTRY", "MAX_LIST", "SIDECAR_DIR")
  miss <- setdiff(req, names(a))
  if (length(miss)) stop("[seam_audit] 설정 키 결손: ", paste(miss, collapse = ", "))
  if (!all(c("SEAM_MAX_RET", "BASIS_SHARES_TOL") %in% names(g))) stop("[seam_audit] 가드 설정에 SEAM_MAX_RET · BASIS_SHARES_TOL 없음")
  cfg <- list(SEAM_MAX_RET = as.numeric(g$SEAM_MAX_RET), BASIS_SHARES_TOL = as.numeric(g$BASIS_SHARES_TOL),
              DAY_FRAC_OFF_ALARM = as.numeric(a$DAY_FRAC_OFF_ALARM), DAY_N_OFF_MIN = as.integer(a$DAY_N_OFF_MIN),
              RET_MATCH_TOL = as.numeric(a$RET_MATCH_TOL), MAX_LIST = as.integer(a$MAX_LIST),
              KNOWN_REGISTRY = file.path(root, a$KNOWN_REGISTRY), SIDECAR_DIR = file.path(root, a$SIDECAR_DIR),
              root = root, guard_config_path = g$config_path, audit_config_path = p)
  .rsa_cfg_cache[[key]] <- cfg
  cfg
}

#' 알려진 원천 내부 기준 단절 — 등록부 verdict = adjustment_basis_break 중 원천 전환 이음매 날짜 밖.
#'   (원천 전환 이음매의 단절은 가드 소관이라 '알려진 것'이 아니다 — 고쳐져 있지 않으면 그게 결함이다.)
#'   등록부 부재 = 빈 표 + 표지(known_status = "registry_absent") — 알려진 것을 지어내지 않는다.
rsa_known <- function(cfg = rsa_config()) {
  p <- cfg$KNOWN_REGISTRY
  empty <- data.table(Date = as.Date(character(0)), Ticker = character(0))
  if (!file.exists(p)) { attr(empty, "known_status") <- "registry_absent"; return(empty) }
  r <- jsonlite::fromJSON(p, simplifyVector = TRUE)
  e <- as.data.table(r$entries)
  seams <- as.character(unlist(r$scope$source_transition_seams))
  if (!nrow(e) || !all(c("Date", "Ticker", "verdict") %in% names(e))) { attr(empty, "known_status") <- "registry_unreadable"; return(empty) }
  k <- unique(e[verdict == "adjustment_basis_break" & !(as.character(Date) %in% seams), .(Date = as.Date(Date), Ticker)])
  attr(k, "known_status") <- "ok"
  attr(k, "registry_generated_at") <- as.character(r$generated_at %||% NA_character_)
  k
}

#' 전 이력 감사 — 저장값만 본다(dt 는 바꾸지 않는다). 필요 열 = Date · Ticker · Close · Size · Ret.
#' @return list(status, counts, hits_new, hits_known, days_alarm, cfg, generated_at)
rsa_audit <- function(dt, cfg = rsa_config(), known = rsa_known(cfg)) {
  need <- c("Date", "Ticker", "Close", "Size", "Ret")
  miss <- setdiff(need, names(dt))
  if (length(miss)) stop("[seam_audit] 열 부재: ", paste(miss, collapse = ", "))
  X <- data.table(i = seq_len(nrow(dt)), Date = as.Date(dt$Date), Ticker = dt$Ticker,
                  Close = as.numeric(dt$Close), Size = as.numeric(dt$Size), Ret = as.numeric(dt$Ret))
  setorder(X, Ticker, Date)
  X[, `:=`(pc = shift(Close), ps = shift(Size)), by = Ticker]
  mx <- cfg$SEAM_MAX_RET
  X[, off := is.finite(Ret) & abs(Ret) > mx]

  # ② 날짜 지문
  D <- X[is.finite(Ret), .(n = .N, n_off = sum(off)), by = Date]
  D[, frac := n_off / n]
  days_alarm <- D[frac >= cfg$DAY_FRAC_OFF_ALARM & n_off >= cfg$DAY_N_OFF_MIN][order(Date)]

  # ③ 지금 비어 있는(Ret NA) 기준 단절 — 지난 처분이 차단한 자리(예: 10-15 A250030). 채움 후보(RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114).
  B <- X[!is.finite(Ret) & is.finite(Close) & is.finite(pc) & pc > 0 & is.finite(Size) & is.finite(ps) & ps > 0]
  B[, `:=`(rc = Close / pc, rs = Size / ps)]
  B[, r_shares := rs / rc]
  hits_blocked <- B[abs(rc - 1) > mx & abs(r_shares - 1) > cfg$BASIS_SHARES_TOL & abs(rs - 1) <= mx,
                   .(i, Date, Ticker, prev_close = pc, Close, prev_size = ps, Size, Ret, r_size = rs, r_shares,
                     implied_ret_size = rs - 1)][order(Date, Ticker)]
  B <- NULL

  # ① 종목-일 지문 — off 행만(소수)
  C <- X[off == TRUE]
  X <- NULL; invisible(gc(verbose = FALSE))
  C[, rc := Close / pc]
  C[, rs := Size / ps]
  C[, raw_ret := rc - 1]
  C[, unrepaired := is.finite(raw_ret) & abs(Ret - raw_ret) <= cfg$RET_MATCH_TOL * pmax(1, abs(Ret))]
  C[, r_shares := rs / rc]
  C[, basis := is.finite(r_shares) & is.finite(rs) &
               abs(r_shares - 1) > cfg$BASIS_SHARES_TOL & abs(rs - 1) <= mx]
  H <- C[unrepaired == TRUE & basis == TRUE,
         .(i, Date, Ticker, prev_close = pc, Close, prev_size = ps, Size, Ret, r_size = rs, r_shares,
           implied_ret_size = rs - 1)]
  kk <- paste(as.character(known$Date), known$Ticker)
  H[, known := paste(as.character(Date), Ticker) %in% kk]
  hits_new <- H[known == FALSE][order(Date, Ticker)]
  hits_known <- H[known == TRUE][order(Date, Ticker)]
  # ★차단 대신 채움(RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114) — 가드와 같은 함수(seam_fill_resolve): 수동 등록부 → 시총 기준 실수익(날짜별 제한폭) → 아니면 그대로.
  #   새 단절: 채움 또는 차단(NA) · 알려진 단절(Ret 생비율) · 비어 있는 단절(NA): 채움 또는 손대지 않음(목록).
  gcfg <- seam_guard_config(cfg$guard_config_path)
  greg <- seam_fill_registry(gcfg, cfg$root)
  res <- function(h) {
    if (!nrow(h)) { h[, `:=`(fill_action = character(0), fill_ret = numeric(0), fill_limit = numeric(0))]; return(h) }
    r <- seam_fill_resolve(h$Date, h$Ticker, h$r_size - 1, 1L, gcfg, greg)
    h[, `:=`(fill_action = r$action, fill_ret = r$fill_ret, fill_limit = r$limit)]
    h
  }
  hits_new <- res(hits_new); hits_known <- res(hits_known); hits_blocked <- res(hits_blocked)
  unresolved_new <- hits_new[fill_action == "block_ret", .N]

  # 경보 = 채우지 못한 새 단절 · 집단 극단 수익일. 채운 새 단절은 [SEAM_FILL] 안내(경보 아님).
  status <- if (unresolved_new || nrow(days_alarm)) "alarm" else if (nrow(hits_new)) "filled" else "ok"
  list(schema = "rawdata_seam_audit_v1", status = status,
       generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
       counts = list(n_rows = nrow(dt), n_off = nrow(C), n_unrepaired_off = C[unrepaired == TRUE, .N],
                     hits_known = nrow(hits_known), hits_new = nrow(hits_new), hits_blocked = nrow(hits_blocked),
                     fill_new = hits_new[fill_action != "block_ret", .N], unresolved_new = unresolved_new,
                     fill_known = hits_known[fill_action != "block_ret", .N], unresolved_known = hits_known[fill_action == "block_ret", .N],
                     fill_blocked = hits_blocked[fill_action != "block_ret", .N], unresolved_blocked = hits_blocked[fill_action == "block_ret", .N],
                     hits_new_dates = length(unique(hits_new$Date)), days_alarm = nrow(days_alarm),
                     date_from = as.character(min(dt$Date, na.rm = TRUE)), date_to = as.character(max(dt$Date, na.rm = TRUE)),
                     known_status = attr(known, "known_status") %||% NA_character_),
       hits_new = hits_new, hits_known = hits_known, hits_blocked = hits_blocked, days_alarm = days_alarm, cfg = cfg)
}

#' 단절 처분 적용(이름은 구판 그대로 — 적재기 · 소급 수리가 부른다). ★2026-11-14 차단 대신 채움(RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114):
#'   새 단절(hits_new)        : 채움(fill_manual · fill_mc) 또는 차단(Ret := NA)
#'   알려진 단절(hits_known)  : 채움 또는 손대지 않음(제한폭 밖 · 등록부 없음 → 목록)
#'   비어 있는 단절(hits_blocked): 채움 또는 손대지 않음(NA 그대로 → 목록)
#'   날짜 지문(집단 극단 수익일)은 건드리지 않는다.
rsa_block_new <- function(dt, aud) {
  stopifnot(is.data.table(dt), "Ret" %in% names(dt))
  n_block <- 0L; n_fill <- 0L
  for (nm in c("hits_new", "hits_known", "hits_blocked")) {
    h <- aud[[nm]]
    if (is.null(h) || !nrow(h)) next
    # ★감사가 본 행과 지금 행이 같은지 단정 — 순서가 바뀌었으면 엉뚱한 행을 고친다(조용한 오염)
    ok <- h$i <= nrow(dt) & as.Date(dt$Date[h$i]) == h$Date & dt$Ticker[h$i] == h$Ticker
    if (!all(ok)) stop("[seam_audit] 처분 대상 행 불일치(감사 뒤 행 순서가 바뀌었다) — 쓰지 않는다")
    fa <- if ("fill_action" %in% names(h)) h$fill_action else rep("block_ret", nrow(h))
    wf <- which(fa %in% c("fill_mc", "fill_manual"))
    if (length(wf)) {
      if (anyNA(h$fill_ret[wf])) stop("[seam_audit] 채움 처분인데 fill_ret 이 비었다 — 쓰지 않는다")
      set(dt, i = h$i[wf], j = "Ret", value = h$fill_ret[wf]); n_fill <- n_fill + length(wf)
    }
    if (identical(nm, "hits_new")) {
      wb <- which(fa == "block_ret")
      if (length(wb)) { set(dt, i = h$i[wb], j = "Ret", value = NA_real_); n_block <- n_block + length(wb) }
    }
  }
  attr(dt, "seam_audit_blocked") <- n_block
  attr(dt, "seam_audit_filled") <- n_fill
  dt
}

#' 요약 — 침묵 통과 금지. 경보면 [SEAM_ALARM] 표지(감시기 superfan_watch 의 로그 규칙이 잡을 수 있는 고정 문자열).
rsa_print <- function(aud, label = "") {
  k <- aud$counts
  cat(sprintf("[seam_audit%s] 전 이력 감사(%s ~ %s · %s행) — |Ret|>%.2f %d행 · 기준 단절 지문: 알려진 %d(등록부) · 새 %d(%d일) · 경보일 %d\n",
              if (nzchar(label)) paste0(":", label) else "", k$date_from, k$date_to, format(k$n_rows, big.mark = ","),
              aud$cfg$SEAM_MAX_RET, k$n_off, k$hits_known, k$hits_new, k$hits_new_dates, k$days_alarm))
  if (!is.null(k$fill_new))
    cat(sprintf("  [SEAM_FILL] 채움(시총 기준 · 수동 등록부): 새 %d · 알려진 %d · 비어 있던 %d — 못 채움: 새 %d(차단) · 알려진 %d · 비어 있던 %d(목록)\n",
                k$fill_new, k$fill_known, k$fill_blocked, k$unresolved_new, k$unresolved_known, k$unresolved_blocked))
  if (identical(aud$status, "alarm")) {
    hn <- if ("fill_action" %in% names(aud$hits_new)) aud$hits_new[fill_action == "block_ret"] else aud$hits_new
    if (nrow(hn)) {
      by_d <- hn[, .N, by = Date][order(-N)]
      cat(sprintf("  ⛔ [SEAM_ALARM] 새 기준 단절 중 못 채운 %d행(시총 기준 값이 날짜별 가격제한폭 밖 · 수동 등록부 없음 → 차단) — 날짜 상위: %s\n", nrow(hn),
                  paste(sprintf("%s×%d", as.character(head(by_d$Date, 6)), head(by_d$N, 6)), collapse = ", ")))
    }
    if (nrow(aud$days_alarm))
      cat(sprintf("  ⛔ [SEAM_ALARM] 집단 극단 수익일 %d일 — %s\n", nrow(aud$days_alarm),
                  paste(sprintf("%s(%d/%d=%.1f%%)", as.character(head(aud$days_alarm$Date, 6)), head(aud$days_alarm$n_off, 6),
                                head(aud$days_alarm$n, 6), 100 * head(aud$days_alarm$frac, 6)), collapse = ", ")))
  }
  invisible(aud)
}

#' 사이드카 — .cache/rawdata_seam_audit/(설정). tmp → rename. latest_<label>.json + audit_<label>_<ts>.json.
rsa_write_sidecar <- function(aud, label, dir_ = aud$cfg$SIDECAR_DIR) {
  dir.create(dir_, recursive = TRUE, showWarnings = FALSE)
  cap <- aud$cfg$MAX_LIST
  fmt <- function(x) { if (is.null(x) || !nrow(x)) return(list()); y <- copy(head(x, cap)); if ("Date" %in% names(y)) y[, Date := as.character(Date)]; y }
  payload <- list(schema = aud$schema, generated_at = aud$generated_at, label = label, status = aud$status,
                  counts = aud$counts, hits_new = fmt(aud$hits_new),
                  unresolved_known = fmt(if (!is.null(aud$hits_known) && "fill_action" %in% names(aud$hits_known)) aud$hits_known[fill_action == "block_ret"] else NULL),
                  hits_blocked = fmt(aud$hits_blocked), hits_known_n_by_year =
                    if (nrow(aud$hits_known)) as.list(aud$hits_known[, .N, by = .(y = format(Date, "%Y"))][, setNames(N, y)]) else list(),
                  days_alarm = fmt(aud$days_alarm),
                  config = aud$cfg[c("SEAM_MAX_RET", "BASIS_SHARES_TOL", "DAY_FRAC_OFF_ALARM", "DAY_N_OFF_MIN", "RET_MATCH_TOL",
                                     "guard_config_path", "audit_config_path", "KNOWN_REGISTRY")])
  js <- jsonlite::toJSON(payload, auto_unbox = TRUE, digits = 10, na = "null", pretty = TRUE)
  put <- function(path) { tmp <- paste0(path, ".tmp", Sys.getpid()); writeLines(js, tmp, useBytes = TRUE)
                          if (file.exists(path)) file.remove(path); file.rename(tmp, path) }
  out <- file.path(dir_, sprintf("audit_%s_%s.json", label, format(Sys.time(), "%Y%m%d_%H%M%S")))
  put(out); put(file.path(dir_, sprintf("latest_%s.json", label)))
  out
}

# ─── CLI ─────────────────────────────────────────────────────────────────────
.rsa_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  val <- function(flag, default = NULL) { i <- match(flag, args); if (is.na(i) || i == length(args)) default else args[i + 1L] }
  root <- .seam_root()
  path <- val("--rawdata", file.path(root, ".cache", "RAWDATA.parquet"))
  label <- val("--label", "cli")
  res <- tryCatch({
    if (!requireNamespace("arrow", quietly = TRUE)) stop("arrow 패키지 없음")
    if (!file.exists(path)) stop("RAWDATA 부재: ", path)
    dt <- as.data.table(arrow::read_parquet(path, col_select = tidyselect::all_of(c("Date", "Ticker", "Close", "Size", "Ret")), mmap = FALSE))
    a <- rsa_audit(dt, rsa_config(root))
    rsa_print(a, label)
    if (!("--no-sidecar" %in% args)) cat(sprintf("  [seam_audit] 사이드카: %s\n", rsa_write_sidecar(a, label)))
    a
  }, error = function(e) { cat(sprintf("⛔ [SEAM_ALARM] [seam_audit] 판독 불가: %s\n", conditionMessage(e))); NULL })
  if (is.null(res)) { cat("RSA\tstatus=unreadable\tnew=NA\tknown=NA\tdays=NA\n"); quit(status = 1L) }
  cat(sprintf("RSA\tstatus=%s\tnew=%d\tknown=%d\tdays=%d\n", res$status, res$counts$hits_new, res$counts$hits_known, res$counts$days_alarm))
  quit(status = if (identical(res$status, "alarm")) 3L else 0L)   # filled = 채운 새 단절(경보 아님)
}

if (sys.nframe() == 0L && !interactive()) .rsa_main()
