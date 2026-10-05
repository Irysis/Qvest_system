#==============================================================================
# rf_organic_ledger_adapter.R — 원장 투영 어댑터(유기체의 **유일한** 원장 판독 파일 · O0a 2026-09-25 · 설계 organic_design_final §1.0(d) · §3 G2)
#
# ★왜: 유기체 결정은 as-of 정보만 봐야 한다(결정 ORGANIC-DE — τ_D 이후·전기간 파생 필드 금지). 원장에는 전기간 essence·등급·retention·
#   DSR·적대검증 판정이 같이 들어 있다. 그래서 원장을 읽는 파일을 **하나로** 두고, 그 파일의 출력 열을 config 허용목록
#   (reinforce_auto_config.json::organic.view.columns)으로 묶는다. view·model·policy·replay 파일은 원장 파일명·rf_load·essence 토큰을
#   쓰지 못한다(rf_organic_guard.R::rfo_static_scan decision 역할) — 이 파일만 그 봉쇄에서 면제되고, 대신 열 검사를 받는다.
# 계약:
#   · rfo_project(root, r = NULL) → data.frame — 열 집합 = 허용목록과 **정확히 같다**(모자라도 넘쳐도 stop). 허용목록에 금지 이름
#     (전기간 지표·등급·retention·DSR·적대검증 판정)이 들어오면 fail-closed(config 오기입으로 봉쇄가 풀리지 않게).
#   · 행 = 원장 L1 의 등록 칸(entry × attempt) · 결정론 정렬(base_id, n) · r(연구 시점)이 주어지면 closed_at < r 인 칸만.
#   · 블록 = 격자 코드 정본(attempt$cell_code 접두) — essence$block 은 B4 에서 빠뜨린 축을 적으므로 쓰지 않는다(기억 카드 09-18).
#   · 상속 여부·측정 여부·종결 여부는 **불리언으로만** 투영한다(값 없음). 규약 사실·창 편차는 관문과 같은 술어(rf_runner_gates.R::
#     rf_candidate_facts)로 — 사본 금지. as-of 지표는 06_Registry/organic/asof/<epoch>/ 가 생기면(O0b) 열로 들어온다(지금은 asof_status).
#   · 이 파일은 아무것도 쓰지 않는다(정적 봉쇄 adapter 역할 — 쓰기 호출·동적 평가 금지).
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
## `%||%` — 호출자가 이미 둔 판(러너·이월·결합·사람 명령 스크립트 · 원장의 NA 처리판)을 덮지 않는다(O0a s2 · 2026-09-26): 이 파일이 전역에
##   source 되면 정의 한 줄이 호출자 함수 전부의 `%||%` 의미를 바꾼다(pi0 비트 동일 위협 — rf_combination_launch.R 는 전역 source).
##   보이는 판이 없거나 base 판(R ≥ 4.4 · NULL 만 대체)뿐일 때만 길이 0 도 대체하는 판을 이 파일 환경에 둔다.
if (!exists("%||%", mode = "function") || identical(environmentName(environment(`%||%`)), "base"))
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
# 금지 열 이름(정확 일치 + 접두) — 허용목록이 이것을 담으면 어댑터가 멈춘다
RFO_VIEW_FORBID_EXACT  <- c("port_t", "calmar", "cagr", "mdd", "net_sharpe", "sharpe", "oos_retention", "retention", "dsr", "grade", "grade_base",
                            "essence", "essence_grade", "verdict", "adversary", "adversary_verdict", "net_ir", "sr", "best_port_t")
RFO_VIEW_FORBID_PREFIX <- c("essence_", "grade_", "adversary_", "full_")

.rfoa_env <- new.env(parent = emptyenv())
.rfoa_s1 <- function(x) { x <- tryCatch(suppressWarnings(as.character(unlist(x %||% ""))), error = function(e) "")
  if (length(x) < 1L || is.na(x[1])) "" else trimws(x[1]) }
.rfoa_libs <- function(root) {
  if (identical(.rfoa_env$root, root)) return(.rfoa_env$g)
  g <- new.env(parent = globalenv())
  invisible(utils::capture.output(suppressMessages(sys.source(file.path(root, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = g, keep.source = FALSE))))
  invisible(utils::capture.output(suppressMessages(sys.source(file.path(root, "02_Infrastructure/reinforcement/rf_spec_sig.R"), envir = g, keep.source = FALSE))))
  invisible(utils::capture.output(suppressMessages(sys.source(file.path(root, "02_Infrastructure/reinforcement/rf_runner_gates.R"), envir = g, keep.source = FALSE))))
  .rfoa_env$g <- g; .rfoa_env$root <- root
  g
}
#' 열 허용목록 — config organic.view.columns(사람 소유). 부재·금지 이름 포함 = stop(fail-closed).
rfo_view_columns <- function(root) {
  cfg <- tryCatch(fromJSON(file.path(root, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE), error = function(e) NULL)
  cols <- as.character(unlist((cfg$organic %||% list())$view$columns %||% list()))
  if (!length(cols)) stop("[rf_organic_adapter] organic.view.columns 부재 — 열 허용목록 없이 원장을 투영하지 않는다(fail-closed)")
  bad <- cols[cols %in% RFO_VIEW_FORBID_EXACT | vapply(cols, function(c) any(startsWith(c, RFO_VIEW_FORBID_PREFIX)), logical(1))]
  if (length(bad)) stop(sprintf("[rf_organic_adapter] 허용목록에 금지 열(전기간 지표·등급·retention·DSR·판정): %s — 투영하지 않는다", paste(bad, collapse = ",")))
  if (anyDuplicated(cols)) stop("[rf_organic_adapter] 허용목록 중복")
  cols
}
.rfoa_lineage <- function(entries, bid) {
  idx <- vapply(entries, function(e) .rfoa_s1(e$base_id), character(1)); chain <- bid; cur <- bid
  for (k in seq_len(length(entries))) {
    i <- match(cur, idx); if (is.na(i)) break
    p <- .rfoa_s1((entries[[i]]$parent %||% list())$base_id); if (!nzchar(p) || p %in% chain) break
    chain <- c(chain, p); cur <- p
  }
  chain
}
.rfoa_treatment <- function(sp, block) {
  if (!is.list(sp)) return("")
  switch(block,
    B1 = { f <- sp$factors %||% list(); paste(sort(vapply(f, function(z) .rfoa_s1(if (is.list(z)) z$id %||% z$kind else z), character(1))), collapse = "+") },
    B2 = .rfoa_s1(sp$weighting$catalog_id %||% sp$weighting$label %||% sp$weighting$kind),
    B3 = paste(.rfoa_s1(sp$universe$kind), .rfoa_s1(sp$universe$flag %||% sp$universe$field), sep = ":"),
    B5 = paste(vapply(sp$overlay_cell %||% list(), function(z) .rfoa_s1(if (is.list(z)) z$arm_id %||% z$kind else z), character(1)), collapse = "+"),
    B6 = .rfoa_s1((sp[["rebalance"]] %||% list())$kind), B7 = .rfoa_s1((sp[["defense_sleeve"]] %||% list())$kind),
    "")
}
#' 원장 투영 — 허용 열만. r = 연구 시점("%Y-%m-%dT%H:%M:%S%z" 또는 POSIXct) · NULL 이면 전부.
rfo_project <- function(root, r = NULL, cols = rfo_view_columns(root), epoch = NULL) {
  g <- .rfoa_libs(root)
  L <- g$rf_load(1L, root); ctx <- g$rf_runner_ctx(root)
  rt <- if (is.null(r)) NA else if (inherits(r, "POSIXct")) r else as.POSIXct(.rfoa_s1(r), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  ts <- function(s) as.POSIXct(.rfoa_s1(s), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  adir <- if (!is.null(epoch) && nzchar(.rfoa_s1(epoch))) file.path(root, "06_Registry/organic/asof", .rfoa_s1(epoch)) else ""
  rows <- list()
  for (e in L$entries %||% list()) {
    bid <- .rfoa_s1(e$base_id); ch <- .rfoa_lineage(L$entries, bid)
    for (a in e$attempts %||% list()) {
      es <- a[["essence"]]; code <- .rfoa_s1(a$cell_code); if (!nzchar(code)) code <- .rfoa_s1((es %||% list())$cell_code)
      blk <- if (grepl("^B[0-9]+_", code)) sub("_.*$", "", code) else ""
      measured <- is.list(es) && length(es) && is.finite(suppressWarnings(as.numeric((es %||% list())$port_t %||% NA)))
      if (!is.na(rt)) { ca <- ts(a$closed_at); if (is.na(ca) || !(ca < rt)) next }
      sp <- if (measured) tryCatch(g$.rfg_spec_read(a), error = function(e2) NULL) else NULL
      fx <- if (measured) tryCatch(g$rf_candidate_facts(a, ctx, c("regime", "window")), error = function(e2) list(fail = "facts_error", facts = list())) else
        list(fail = "unmeasured", facts = list())
      ds <- .rfoa_s1((a$design %||% list())$design_source); if (!nzchar(ds)) ds <- "unknown"
      tr <- .rfoa_treatment(sp, blk)
      fl <- vapply(a$vintage_flags %||% list(), function(z) .rfoa_s1(z$flag), character(1))
      ck <- sprintf("%s#%d", bid, as.integer(a$n))
      asof <- if (nzchar(adir)) { p <- file.path(adir, paste0(gsub("[^A-Za-z0-9_.-]", "_", ck), ".json")); if (file.exists(p)) "present" else "absent" } else "no_epoch"
      rows[[length(rows) + 1L]] <- list(
        cell_key = ck, base_id = bid, n = as.integer(a$n), root_lineage = ch[length(ch)], parent_chain = paste(ch, collapse = ">"),
        block = blk, cell_code = code, lever_key = sprintf("%s|%s|%s", blk, ds, tr), design_source = ds,
        design_lane = .rfoa_s1((a$design %||% list())$design_lane),
        regime = .rfoa_s1(fx$facts$regime), regime_ok = measured && !any(startsWith(fx$fail, "regime")),
        flags = paste(sort(unique(fl[nzchar(fl)])), collapse = "+"),
        window_deviation_months = suppressWarnings(as.numeric(fx$facts$window_dev %||% NA)),
        floor_code = .rfoa_s1((sp %||% list())$floor_code), closed_at = .rfoa_s1(a$closed_at),
        measured = measured, inherited = is.list(es) && !is.null(es$inherited_from),
        terminal = isTRUE(a$terminal), cell_no_treatment = isTRUE(a$terminal) && startsWith(.rfoa_s1(a$terminal_reason), "무처치"),
        asof_status = asof)
    }
  }
  all_cols <- if (length(rows)) names(rows[[1]]) else cols
  miss <- setdiff(cols, all_cols)
  if (length(miss)) stop(sprintf("[rf_organic_adapter] 허용목록 열을 만들 수 없다(어댑터가 모르는 열): %s", paste(miss, collapse = ",")))
  df <- if (length(rows)) do.call(rbind.data.frame, c(lapply(rows, function(x) as.data.frame(x[cols], stringsAsFactors = FALSE)), stringsAsFactors = FALSE)) else
        as.data.frame(stats::setNames(replicate(length(cols), character(0), simplify = FALSE), cols), stringsAsFactors = FALSE)
  if (nrow(df)) df <- df[order(df$base_id, df$n), , drop = FALSE]
  rownames(df) <- NULL
  if (!identical(names(df), cols)) stop("[rf_organic_adapter] 출력 열 ≠ 허용목록 — 투영하지 않는다")
  df
}
#' 투영 정규형 — 결정론 확인·view_md5(시행 로그 organic 필드)의 입력. 해시는 호출자가 낸다(이 파일은 아무것도 쓰지 않는다).
rfo_project_canonical <- function(df) enc2utf8(as.character(toJSON(df, dataframe = "rows", na = "null", digits = NA)))
