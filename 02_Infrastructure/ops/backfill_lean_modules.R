#!/usr/bin/env Rscript
#==============================================================================
# backfill_lean_modules.R — v9 lean 산출물 소급 등재 (일회성, v9.1 §7-S2c)
#
# 왜 있나: v9 lean 라운드는 register_module 을 deep 뒤로 보냈다(run_alpha_search.R:313/390/499).
#   그래서 2026-08-23 하루 13+ 라운드가 돌았는데 module_quarantine 등재 0건 —
#   overlay_candidate_queue.R:65-87 이 이미 quarantine 을 스캔하고 있는데(배관 선설치)
#   입력이 비어 있어 소비자가 영원히 놀고 있었다. 이 스크립트가 그 공백만 메운다.
#
# ★장애물과 해법: lean run 디렉터리에는 sim_result.rds 가 **없다**(bt_result.rds 만).
#   register_module.R:69-80 은 sim_result$DAILY_NAV_DT[Date, Strategy_Ret] + bm_xts 를 요구한다.
#   → bt_result.rds 에 **이미 저장된 계열**로 그 둘만 재구성한다:
#       DAILY_NAV_DT$Date         <- bt$nav$date            (저장값)
#       DAILY_NAV_DT$NAV          <- bt$nav$nav_net          (저장값 — 재계산하지 않는다)
#       DAILY_NAV_DT$Strategy_Ret <- bt$period_returns$ret_net (저장값)
#       bm_xts                    <- xts(bt$benchmark_returns$benchmark_ret, order.by = date)
#   NAV 를 수익률에서 다시 만들지 않는다(자체합성 금지 — python-policy §4). 저장된 계열을
#   그대로 옮겨 담는 것뿐이고, 그 사실을 meta 에 못박는다.
#
# ★필수 기록(다른 등재분과 구분 가능해야 한다):
#   meta$sim_reconstructed = TRUE
#   meta$sim_fields        = "DAILY_NAV_DT,bm_xts only (HOLDINGS_LOG/PORTFOLIO_LOG 없음)"
#   meta$reconstructed_from = "bt_result.rds"
#
# 계약상 결과: metric_type="proxy" 는 register_module.R:133-142 의 FR input floor
#   (metric_type=="backtested" 요구)를 통과하지 못한다 → 전건 module_quarantine 행이고
#   module_catalog 는 불변이다. build_module_performance.R 의 .is_fr_eligible 도
#   metric_type=="backtested" 를 재확인하므로 FR 입력면 무오염이 **계약으로** 보장된다.
#
# Usage:
#   Rscript 02_Infrastructure/ops/backfill_lean_modules.R              # dry-run (기본)
#   Rscript 02_Infrastructure/ops/backfill_lean_modules.R --apply      # 실제 등재
#   ... --date 20260823        (기본) · --glob '2026082*' · --include-registered · --json
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts) })

.bl_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[dir.exists(file.path(cands, "02_Infrastructure")) &
               dir.exists(file.path(cands, "06_Registry"))]
  if (!length(hit)) stop("[backfill_lean] project root 미발견 (QM_ROOT 확인)")
  hit[1]
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.bl_nz <- function(a, b) if (is.null(a) || length(a) == 0L || all(is.na(a))) b else a
.bl_chr <- function(x) if (is.null(x) || length(x) == 0L) NA_character_ else as.character(x[[1]])
.bl_num <- function(x) if (is.null(x) || length(x) == 0L) NA_real_ else suppressWarnings(as.numeric(x[[1]]))
.bl_json <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE),
                                                     error = function(e) NULL) else NULL

# register_module.R 은 전용 env 에 적재한다 — 그 파일의 %||% 는 ""를 NULL 로 취급해서
# 호출자 전역을 덮으면 다른 판정을 만든다(run_alpha_search 가 매 호출 뒤 %||% 를 복원하는 이유).
.bl_rm_env <- function(root) {
  e <- new.env(parent = globalenv())
  sys.source(file.path(root, "02_Infrastructure", "contracts", "register_module.R"), envir = e)
  e
}

#' bt_result.rds → register_module 이 요구하는 최소 sim_result 재구성.
#'   저장된 계열만 옮겨 담는다. 파생 계산 0 (NAV 재계산·수익 재합성 없음).
bl_sim_from_bt <- function(bt) {
  need <- c("nav", "period_returns", "benchmark_returns")
  miss <- need[!need %in% names(bt)]
  if (length(miss)) stop("bt_result 계열 부재: ", paste(miss, collapse = ","))
  NV <- as.data.table(bt$nav)[, .(Date = as.Date(date), NAV = as.numeric(nav_net))]
  PR <- as.data.table(bt$period_returns)[, .(Date = as.Date(date), Strategy_Ret = as.numeric(ret_net))]
  BR <- as.data.table(bt$benchmark_returns)[, .(Date = as.Date(date), BM = as.numeric(benchmark_ret))]
  D <- merge(NV, PR, by = "Date")
  setorder(D, Date)
  B <- BR[Date %in% D$Date]
  setorder(B, Date)
  bmx <- xts::xts(matrix(B$BM, ncol = 1L, dimnames = list(NULL, "Benchmark")), order.by = B$Date)
  list(DAILY_NAV_DT = D[, .(Date, NAV, Strategy_Ret)], bm_xts = bmx)
}

#' 런 디렉터리 1건 → 등재 계획(판정만; 쓰기 없음)
bl_plan_one <- function(dir_path, root, registered_ids, rm_env) {
  rid <- basename(dir_path)
  hp <- file.path(dir_path, "hurdle_result.json")
  mp <- file.path(dir_path, "strategy_manifest.json")
  bp <- file.path(dir_path, "bt_result.rds")
  out <- list(run_dir = rid, strategy_id = NA_character_, action = NA_character_,
              grade = NA_character_, score = NA_real_, screen_route = NA_character_,
              screen_pass = NA, n_days = NA_integer_, fr_reason = NA_character_, note = "")

  if (!file.exists(hp)) { out$action <- "SKIPPED_NO_HURDLE"
    out$note <- "hurdle_result.json 부재 — 판정이 없는 런은 등재 대상 아님"; return(out) }
  if (!file.exists(mp)) { out$action <- "SKIPPED_NO_MANIFEST"; out$note <- "strategy_manifest.json 부재"; return(out) }
  if (!file.exists(bp)) { out$action <- "SKIPPED_NO_BT"; out$note <- "bt_result.rds 부재 — 재구성 원료 없음"; return(out) }

  hg <- .bl_json(hp); mf <- .bl_json(mp)
  if (is.null(hg) || is.null(mf)) { out$action <- "SKIPPED_UNREADABLE"; out$note <- "JSON 파싱 실패"; return(out) }

  sid <- .bl_chr(mf$strategy_id)
  if (is.na(sid) || !nzchar(sid)) sid <- paste0("STR_AS_", rid)
  out$strategy_id <- sid
  scr <- hg$screening %||% list()
  out$grade        <- .bl_nz(.bl_chr(hg$grade), .bl_chr(mf$verdict$grade))
  out$score        <- .bl_nz(.bl_num(hg$total_score), .bl_num(mf$verdict$score))
  out$screen_route <- .bl_nz(.bl_chr(scr$screen_route), "NONE")
  out$screen_pass  <- isTRUE(scr$screen_pass)

  pit <- .bl_chr(mf$pit$status)
  if (!identical(pit, "CLEAN")) { out$action <- "SKIPPED_PIT_NOT_CLEAN"
    out$note <- sprintf("pit.status=%s — PIT 미확인분은 등재하지 않는다", pit %||% "?"); return(out) }

  if (sid %in% registered_ids && !isTRUE(getOption("bl.include_registered", FALSE))) {
    out$action <- "SKIPPED_ALREADY_REGISTERED"
    out$note <- "module_catalog 또는 module_quarantine 에 이미 존재 (--include-registered 로 강제 갱신)"
    return(out)
  }

  bt <- tryCatch(readRDS(bp), error = function(e) NULL)
  if (is.null(bt)) { out$action <- "SKIPPED_BT_UNREADABLE"; out$note <- "bt_result.rds 로드 실패"; return(out) }
  sim <- tryCatch(bl_sim_from_bt(bt), error = function(e) conditionMessage(e))
  if (is.character(sim)) { out$action <- "SKIPPED_RECONSTRUCT_FAIL"; out$note <- sim; return(out) }
  v <- tryCatch({ rm_env$.validate_module_sim(sim); TRUE }, error = function(e) conditionMessage(e))
  if (!isTRUE(v)) { out$action <- "SKIPPED_SIM_INVALID"; out$note <- as.character(v); return(out) }
  out$n_days <- nrow(sim$DAILY_NAV_DT)

  meta <- bl_meta(mf, hg, dir_path, root)
  # 예상 fr_eligible 사유 — 계약 함수 그대로 호출(중복 구현 금지)
  ctr <- rm_env$.contract_from_args(meta, "proxy", NULL, NULL, NULL, "backfill_preview_hash",
                                    NULL, NULL, meta$bt_result_path)
  out$fr_reason <- rm_env$.eligibility_reason(ctr)
  out$action <- "REGISTER"
  attr(out, "sim")  <- sim
  attr(out, "meta") <- meta
  out
}

bl_meta <- function(mf, hg, dir_path, root) {
  scr <- hg$screening %||% list()
  fmt <- vapply(mf$fmt %||% list(), function(x) .bl_chr(x$code), character(1))
  sdd <- if (!is.null(scr$structural_dd)) isTRUE(scr$structural_dd) else ("FMT-01" %in% fmt)
  sdd_src <- if (!is.null(scr$structural_dd)) "hurdle screening$structural_dd" else
    "파생: FMT-01(Structural MDD) 발화 여부 (S2b 이전 산출물이라 원 필드 부재)"
  btp <- .bl_nz(.bl_chr(mf$backtest_contract$bt_result_path),
                sub(root, "", file.path(dir_path, "bt_result.rds"), fixed = TRUE))
  btp <- sub("^/+", "", btp)
  list(
    strategy_idea      = .bl_chr(mf$strategy_idea),
    strategy_name      = .bl_chr(mf$strategy_name),
    score              = .bl_nz(.bl_num(hg$total_score), .bl_num(mf$verdict$score)),
    f_grade_reasons    = as.character(unlist(mf$verdict$f_grade_reasons %||% list())),
    fmt_codes          = fmt,
    screen_route       = .bl_nz(.bl_chr(scr$screen_route), "NONE"),
    screen_pass        = isTRUE(scr$screen_pass),
    structural_dd      = sdd,
    structural_dd_source = sdd_src,
    bt_result_path     = btp,
    bt_contract_status = .bl_nz(.bl_chr(mf$backtest_contract$status), "UNKNOWN"),
    lean               = TRUE,
    grade_basis        = "proxy_diagnostic",   # ★run_alpha_search.R 6c 와 키 동형

    ## ★재구성 표식 — 이것이 없으면 정상 등재분과 구분 불가하다
    sim_reconstructed  = TRUE,
    sim_fields         = "DAILY_NAV_DT,bm_xts only (HOLDINGS_LOG/PORTFOLIO_LOG 없음)",
    reconstructed_from = "bt_result.rds",
    reconstruct_note   = paste0("저장된 nav$nav_net · period_returns$ret_net · ",
                                "benchmark_returns$benchmark_ret 를 그대로 옮겨 담았다(재계산 0)."),
    backfill_ref       = "02_Infrastructure/ops/backfill_lean_modules.R (v9.1 §7-S2c 소급 등재)",
    labeled_at         = .bl_chr(mf$created_at)
  )
}

backfill_lean_modules <- function(root = .bl_root(), pattern = "20260823_*",
                                  apply = FALSE, include_registered = FALSE) {
  options(bl.include_registered = isTRUE(include_registered))
  rm_env <- .bl_rm_env(root)
  cat_ids <- names((.bl_json(file.path(root, "06_Registry/module_catalog.json")) %||% list())$modules %||% list())
  qua_ids <- names((.bl_json(file.path(root, "06_Registry/module_quarantine.json")) %||% list())$modules %||% list())
  registered <- unique(c(cat_ids, qua_ids))

  dirs <- sort(Sys.glob(file.path(root, "stage_artifacts", "alpha_search", pattern)))
  dirs <- dirs[dir.exists(dirs)]
  plans <- lapply(dirs, bl_plan_one, root = root, registered_ids = registered, rm_env = rm_env)

  tbl <- rbindlist(lapply(plans, function(p) as.data.table(
    p[c("run_dir", "strategy_id", "action", "grade", "score", "screen_route",
        "screen_pass", "n_days", "fr_reason", "note")])), fill = TRUE)

  todo <- plans[vapply(plans, function(p) identical(p$action, "REGISTER"), logical(1))]
  cat(sprintf("=== backfill_lean_modules — %s (%s) ===\n", pattern,
              if (isTRUE(apply)) "APPLY (원장 기록)" else "DRY-RUN (원장 무변경)"))
  cat(sprintf("  스캔 %d개 런 · 등재 대상 %d건 · 제외 %d건\n\n",
              length(dirs), length(todo), length(dirs) - length(todo)))
  if (nrow(tbl)) {
    print(tbl[action == "REGISTER",
              .(run_dir, grade, score = round(score, 1), screen_route, n_days,
                예상_fr_eligible_사유 = fr_reason)], row.names = FALSE)
    ex <- tbl[action != "REGISTER"]
    if (nrow(ex)) { cat("\n  -- 제외 --\n"); print(ex[, .(run_dir, action, note)], row.names = FALSE) }
  }
  cat(sprintf("\n  ★계약 예측: 등재 대상 %d건 중 FR_ELIGIBLE %d건 (proxy 는 floor 상 전부 quarantine 이 정상)\n",
              length(todo), sum(tbl$action == "REGISTER" & tbl$fr_reason == "FR_ELIGIBLE", na.rm = TRUE)))

  if (!isTRUE(apply)) {
    cat("  (--apply 를 붙이면 실제로 register_module 을 호출한다)\n")
    return(invisible(list(plans = plans, table = tbl, applied = 0L)))
  }

  n_ok <- 0L
  for (p in todo) {
    r <- tryCatch({
      rm_env$register_module(attr(p, "sim"), p$strategy_id, grade = p$grade,
                             origin_mode = "alpha_search", role = NA_character_,
                             meta = attr(p, "meta"), metric_type = "proxy",
                             bt_result_path = attr(p, "meta")$bt_result_path)
      TRUE
    }, error = function(e) { cat("  [FAIL]", p$strategy_id, "—", conditionMessage(e), "\n"); FALSE })
    if (isTRUE(r)) n_ok <- n_ok + 1L
  }
  cat(sprintf("\n  등재 완료 %d/%d\n", n_ok, length(todo)))
  invisible(list(plans = plans, table = tbl, applied = n_ok))
}

# ── CLI ───────────────────────────────────────────────────────────────────────
.bl_invoked_directly <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  length(f) > 0L && identical(basename(f[1]), "backfill_lean_modules.R")
}

if (.bl_invoked_directly()) {
  args <- commandArgs(trailingOnly = TRUE)
  gv <- function(key, dflt) {
    i <- which(args == paste0("--", key))
    if (length(i) && length(args) >= i[1] + 1L) return(args[i[1] + 1L])
    h <- grep(paste0("^--", key, "="), args, value = TRUE)
    if (length(h)) return(sub(paste0("^--", key, "="), "", h[1]))
    dflt
  }
  pat <- gv("glob", paste0(gv("date", "20260823"), "_*"))
  res <- backfill_lean_modules(root = .bl_root(), pattern = pat,
                               apply = ("--apply" %in% args),
                               include_registered = ("--include-registered" %in% args))
  if ("--json" %in% args)
    cat(toJSON(res$table, auto_unbox = TRUE, pretty = TRUE, na = "null"), "\n")
  quit(save = "no", status = 0L)
}
