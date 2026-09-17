# ledger_io.R — 강화 원장 읽기 전용 로더 (Axiom 효능 축 1단계)
#
# ★원장·스펙·로그는 **읽기만** 한다. 이 디렉터리 밖으로 쓰지 않는다.
# ★파생 필드는 전부 원장에서 재도출한다 — 손계산 상수 금지.
#
# 제공:
#   ar_root()                  프로젝트 루트
#   ar_load_ledger(layer)      원장 JSON (list)
#   ar_attempts_df(led)        시도 1행 = 1칸 (long)
#   ar_entries_df(led, att)    entry 1행 (derived: best/cells/minutes/kind/regime)
#   ar_lineage(ent)            승격 사슬 — parent 링크로 조상·자손 집합

suppressPackageStartupMessages(library(jsonlite))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 ||
                            (length(a) == 1 && is.na(a))) b else a

ar_root <- function() {
  cands <- c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

# 체제 경계 — 09-04 커서(개수→코드)·블록 누적 규칙 변경. 세계는 그 전후로 생성과정이 다르다.
AR_REGIME_CUT <- as.POSIXct("2026-09-04 00:00:00", tz = "Asia/Seoul")

.ar_num <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA)); if (length(v) != 1) NA_real_ else v }
.ar_chr <- function(x) { v <- as.character(x %||% NA); if (length(v) != 1) NA_character_ else v }
.ar_ts  <- function(x) {
  s <- .ar_chr(x); if (is.na(s) || !nzchar(s)) return(as.POSIXct(NA))
  suppressWarnings(as.POSIXct(sub("([+-][0-9]{2}):?([0-9]{2})$", "", s),
                              format = "%Y-%m-%dT%H:%M:%S", tz = "Asia/Seoul"))
}

ar_load_ledger <- function(layer = 1L, root = ar_root()) {
  p <- file.path(root, "06_Registry", sprintf("reinforce_ledger_l%d.json", as.integer(layer)))
  if (!file.exists(p)) stop("ledger not found: ", p)
  fromJSON(p, simplifyVector = FALSE)
}

# ── 시도(칸) 테이블 ────────────────────────────────────────────────────────
# grade 는 "NA (사유)" 형태가 존재한다 — 등급 enum 과 실패 사유를 분리해 둔다.
ar_attempts_df <- function(led) {
  rows <- list()
  for (E in led$entries %||% list()) {
    bid <- .ar_chr(E$base_id)
    for (a in E$attempts %||% list()) {
      es <- a$essence
      g_raw <- .ar_chr(a$grade)
      g <- if (!is.na(g_raw) && grepl("^[ABCF]$", g_raw)) g_raw else NA_character_
      fail <- if (!is.na(g_raw) && !grepl("^[ABCF]$", g_raw)) {
        trimws(gsub("[()]", "", sub("^NA", "", g_raw)))
      } else .ar_chr(a$terminal_reason)
      o <- .ar_ts(a$opened_at); c_ <- .ar_ts(a$closed_at)
      mins <- if (!is.na(o) && !is.na(c_)) as.numeric(difftime(c_, o, units = "mins")) else NA_real_
      rows[[length(rows) + 1L]] <- data.frame(
        base_id   = bid,
        n         = as.integer(a$n %||% NA),
        cell_code = .ar_chr(a$cell_code %||% es$cell_code),
        block     = .ar_chr(es$block),
        axis      = .ar_chr(a$keyword_axis),
        grade     = g,
        grade_raw = g_raw,
        fail_class= fail,
        port_t    = .ar_num(es$port_t),
        calmar    = .ar_num(es$calmar),
        cagr      = .ar_num(es$cagr),
        mdd       = .ar_num(es$mdd),
        oos       = .ar_num(es$oos_retention),
        sharpe    = .ar_num(es$net_sharpe),
        spec      = .ar_chr(es$spec),
        artifacts = .ar_chr(a$artifacts),
        evidence  = .ar_chr(a$evidence),
        axiom_inj = isTRUE(a$axiom_injected),
        terminal  = isTRUE(a$terminal),
        inherited = .ar_chr(es$inherited_from),
        opened_at = o, closed_at = c_, minutes = mins,
        l_code    = .ar_chr(a$l_code),
        stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) return(data.frame())
  d <- do.call(rbind, rows)
  d$measured <- is.finite(d$port_t)
  d$regime   <- ifelse(!is.na(d$opened_at) & d$opened_at >= AR_REGIME_CUT, "post_0904", "pre_0904")
  d
}

# ── entry 테이블 ──────────────────────────────────────────────────────────
ar_entries_df <- function(led, att = NULL) {
  if (is.null(att)) att <- ar_attempts_df(led)
  rows <- list()
  for (E in led$entries %||% list()) {
    bid <- .ar_chr(E$base_id)
    sub <- if (nrow(att)) att[att$base_id == bid, , drop = FALSE] else att
    ms  <- if (nrow(sub)) sub[sub$measured, , drop = FALSE] else sub
    bi  <- if (nrow(ms)) which.max(ms$port_t) else integer(0)
    kind <- if (grepl("_combo", bid)) "combo"
            else if (!is.null(E$parent)) "promo"
            else if (grepl("rescued", bid)) "rescued" else "root"
    rows[[length(rows) + 1L]] <- data.frame(
      base_id      = bid,
      status       = .ar_chr(E$status),
      kind         = kind,
      base_grade   = .ar_chr(E$base_grade),
      paper_key    = .ar_chr(E$paper_key),
      parent_id    = .ar_chr(E$parent$base_id),
      parent_depth = as.integer(E$parent$depth %||% 0L),
      parent_best  = .ar_num(E$parent$best_port_t),
      attempts_used= as.integer(E$attempts_used %||% 0L),
      n_cells      = nrow(sub),
      n_measured   = nrow(ms),
      best_port_t  = if (length(bi)) ms$port_t[bi] else NA_real_,
      best_cell    = if (length(bi)) ms$cell_code[bi] else NA_character_,
      best_grade   = if (length(bi)) ms$grade[bi] else NA_character_,
      best_calmar  = if (length(bi)) ms$calmar[bi] else NA_real_,
      minutes      = if (nrow(sub)) sum(sub$minutes[is.finite(sub$minutes) & sub$minutes < 720], na.rm = TRUE) else 0,
      opened_at    = .ar_ts(E$opened_at),
      exhausted_at = .ar_ts(E$exhausted_at),
      parked_reason= .ar_chr(E$parked_reason),
      handed_off   = isTRUE(E$handed_off),
      block_order  = paste(as.character(E$block_order %||% character(0)), collapse = ">"),
      search_adapt = isTRUE(E$search_adaptive),
      max_attempts = as.integer(E$max_attempts %||% (led$max_attempts %||% 25L)),
      stringsAsFactors = FALSE)
  }
  d <- do.call(rbind, rows)
  d$regime <- ifelse(!is.na(d$opened_at) & d$opened_at >= AR_REGIME_CUT, "post_0904", "pre_0904")
  d
}

# ── 승격 사슬 ─────────────────────────────────────────────────────────────
# 자손 집합(자기 포함)을 준다 — 승격을 막았을 때 사라지는 칸을 세기 위함.
ar_descendants <- function(ent, base_id) {
  out <- character(0); frontier <- base_id
  while (length(frontier)) {
    kids <- ent$base_id[!is.na(ent$parent_id) & ent$parent_id %in% frontier]
    kids <- setdiff(kids, out)
    out <- c(out, kids); frontier <- kids
  }
  out
}

ar_lineage_root <- function(ent, base_id) {
  cur <- base_id
  while (TRUE) {
    p <- ent$parent_id[ent$base_id == cur]
    if (!length(p) || is.na(p[1]) || !(p[1] %in% ent$base_id)) return(cur)
    cur <- p[1]
  }
}
