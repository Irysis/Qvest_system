#==============================================================================
# rf_l2_lib.R — 2계층(전략 로테이션) 무인 레인 라이브러리 (2026-09-21 도훈 승인 플랜 Part 3 · D2)
#
# 왜: 2계층은 낙폭 벽(Calmar)을 깨라고 만든 기구인데 세션에서 사람이 열 때만 돌았다(강화 시도 0회).
#   디렉터(rf_director.R)가 "구속 = Calmar ∧ 오버레이 레버 사망" 을 판정하면 2계층 단위를 **요청 파일**로 발행하고,
#   이 레인이 8분 tick 마다 그 요청을 집어 π₀(현행 국면 신호 + RCMA + rp⊕IR 배분기)를 T/S/C 세 arm 으로 실측한다.
# 계약:
#   · 측정은 04_Research/factor_rotation/run_wf_ensemble.R(기존 러너) 그대로 — 등급 사슬(build_bt_result→audit→essence→등재→L-code)은 러너 안.
#   · 원장 = reinforce_ledger_l2.json: rf_append_attempt **실행 전** · rf_record_result 실행 후 (원장 밖 강화는 없다).
#   · R1(selection_type) 은 config l2_auto.selection_type 에 decided_by/at 과 함께 기록될 때만 러너에 넘긴다 — 조용한 반전 없음.
#   · 실행 직렬화: 드라이버가 러너 claim(.cache/reinforce_auto.claim)을 쥔다 → 그동안 L1 러너는 halt_claimed.
#   · MC1(국면 채널 미전달)이면 교훈에 "국면조건부" 라벨 금지를 강제한다. Judge/BOOK 은 세션 전용 — A 면 요청 파일 + 텔레그램까지.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.l2_num <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA_real_)); if (length(v)) v[1] else NA_real_ }
.l2_chr <- function(x) { v <- suppressWarnings(as.character(x %||% "")); v <- v[!is.na(v)]; if (length(v)) v[1] else "" }
.l2_f3 <- function(x) { v <- .l2_num(x); if (is.finite(v)) formatC(v, digits = 3, format = "f") else "NA" }
.l2_rj <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
.l2_write_atomic <- function(obj, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  txt <- if (is.character(obj)) obj else toJSON(obj, auto_unbox = TRUE, null = "null", na = "null", digits = 6, pretty = TRUE)
  tmp <- sprintf("%s.tmp.%d", path, Sys.getpid()); writeLines(enc2utf8(txt), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}
l2_jlog <- function(event, ..., root) {
  p <- Sys.getenv("QVEST_RP_JLOG", file.path(root, ".cache/reinforce_auto_log.jsonl"))
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "l2_auto"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null"), "\n", sep = "", file = p, append = TRUE)
  cat(sprintf("[l2_auto] %s\n", event))
}

# ── config ────────────────────────────────────────────────────────────────────────────────────
l2_cfg <- function(root) {
  cp <- Sys.getenv("QVEST_RF_CONFIG", file.path(root, "06_Registry/reinforce_auto_config.json"))
  c0 <- .l2_rj(cp) %||% list(); l <- c0$l2_auto %||% list()
  list(loop_enabled = isTRUE(c0$enabled), enabled = isTRUE(l$enabled),
       selection_type = .l2_chr(l$selection_type), decided_by = .l2_chr(l$decided_by), decided_at = .l2_chr(l$decided_at),
       arm_timeout_min = .l2_num(l$arm_timeout_min %||% 40), min_free_gb = .l2_num(l$min_free_gb %||% 6),
       fallback_max_modules = as.integer(l$fallback_max_modules %||% 200L), stale_pool_days = .l2_num(l$stale_pool_days %||% 7),
       arms = as.character(unlist(l$arms %||% list("T", "S", "C"))), label_gate = .l2_chr(l$label_gate %||% "block"),
       claim_stale_hours = .l2_num(c0$claim_stale_hours %||% 6))
}
# R1 결정 상자 — chain/sweep 중 하나가 결정자·시각과 함께 기록됐을 때만 참
l2_r1_decided <- function(cfg) cfg$selection_type %in% c("chain", "sweep") && nzchar(cfg$decided_by) && nzchar(cfg$decided_at)

# ── 요청 파일 (디렉터 → 레인) ───────────────────────────────────────────────────────────────
l2_request_path <- function(root) Sys.getenv("QVEST_L2_REQUEST", file.path(root, "06_Registry/l2_unit_request.json"))
l2_request_read <- function(root) .l2_rj(l2_request_path(root))
l2_request_write <- function(req, root) .l2_write_atomic(req, l2_request_path(root))
l2_request_new <- function(base_id, idea, keyword_axis = "strategy_combination", arms = c("T", "S", "C"), next_probe = character(0),
                           root_papers = list(), requested_by = "manual", note = "") {
  list(schema = "l2_unit_request_v1", status = "pending", requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
       requested_by = requested_by, base_id = base_id, keyword_axis = keyword_axis, idea = idea, arms = as.list(arms),
       next_probe = as.list(next_probe), root_papers = root_papers, attempt_n = NULL, started_at = NULL, completed_at = NULL,
       deferred_count = 0L, result = NULL, note = note)
}
l2_request_validate <- function(req, led2) {
  if (!is.list(req)) return("요청 파일 부재/파손")
  if (!identical(.l2_chr(req$status), "pending")) return(sprintf("status=%s (pending 아님)", .l2_chr(req$status)))
  if (!nzchar(.l2_chr(req$idea))) return("idea 비어 있음 — 원장이 거부한다")
  if (!(.l2_chr(req$keyword_axis) %in% c("regime_identification", "strategy_combination"))) return("keyword_axis 가 L2 축이 아님")
  act <- Filter(function(e) identical(e$status, "active") && identical(e$base_id, .l2_chr(req$base_id)), led2$entries %||% list())
  if (!length(act)) return(sprintf("L2 원장에 active entry %s 없음", .l2_chr(req$base_id)))
  ""
}

# ── 풀 신선도 · 대조 풀 · 메모리 가드 ───────────────────────────────────────────────────────
l2_pool_age_days <- function(root) {
  mp <- .l2_rj(file.path(root, "06_Registry/module_performance.json")); g <- suppressWarnings(as.Date(.l2_chr(mp$generated)))
  if (is.na(g)) NA_real_ else as.numeric(Sys.Date() - g)
}
l2_builder <- function(code_root) Sys.getenv("QVEST_L2_BUILDER", file.path(code_root, "02_Infrastructure/regime/build_module_performance.R"))
l2_runner  <- function(code_root) Sys.getenv("QVEST_L2_RUNNER",  file.path(code_root, "04_Research/factor_rotation/run_wf_ensemble.R"))
# 빌더 dry-run 모드(QVEST_L2_DRY_RUN=1 · _OUT=경로)로 **정본 풀을 건드리지 않고** 변형 풀을 만든다 (build_module_performance.R:289-291)
l2_build_variant_pool <- function(root, code_root, out_path, defensive_route = "OFF", max_modules = NULL, log_path = NULL, timeout_s = 900) {
  env <- c(QVEST_L2_DRY_RUN = "1", QVEST_L2_DRY_RUN_OUT = out_path, QVEST_L2_DEFENSIVE_ROUTE = defensive_route,
           CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
  if (!is.null(max_modules)) env <- c(env, FR_MAX_MODULES = as.character(max_modules))
  old <- Sys.getenv(names(env), unset = NA); on.exit({ for (k in names(env)) if (is.na(old[[k]])) Sys.unsetenv(k) else Sys.setenv(k = old[[k]]) }, add = TRUE)
  do.call(Sys.setenv, as.list(env))
  rc <- tryCatch(system2("Rscript", shQuote(l2_builder(code_root)), stdout = log_path %||% FALSE, stderr = log_path %||% FALSE, timeout = timeout_s), error = function(e) 99L)
  if (!identical(as.integer(rc), 0L) || !file.exists(out_path)) return(list(ok = FALSE, rc = rc, path = out_path))
  mp <- .l2_rj(out_path); list(ok = !is.null(mp), rc = rc, path = out_path, n_modules = .l2_num(mp$n_modules))
}
l2_free_gb <- function() {
  v <- tryCatch(suppressWarnings(system2("powershell", c("-NoProfile", "-Command", "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"), stdout = TRUE, stderr = FALSE, timeout = 30)),
                error = function(e) character(0))
  v <- suppressWarnings(as.numeric(gsub("[^0-9.]", "", v))); v <- v[is.finite(v)]
  if (length(v)) v[1] / 1024^2 else NA_real_
}

# ── arm 실행 — 러너는 env 로만 조종한다(기본값 = 구동작). Windows 는 system2(env=) 가 무시되므로 부모 env 에 심는다 ─
l2_run_arm <- function(arm, run_id, root, code_root, cfg, diag_dir, module_perf = "", log_path, extra_lag = 0L, register = TRUE) {
  env <- c(FR_RUN_ID = run_id, FR_REGISTER = if (register) "1" else "0", FR_ARM_TAG = arm$tag, FR_EXTRA_REGIME_LAG = as.character(extra_lag),
           FR_DIAG_DIR = diag_dir, FR_SELECTION_TYPE = cfg$selection_type, QVEST_LABEL_GATE_MODE = cfg$label_gate,
           FR_MODULE_PERF = module_perf, CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
  old <- Sys.getenv(names(env), unset = NA); on.exit({ for (k in names(env)) if (is.na(old[[k]])) Sys.unsetenv(k) else Sys.setenv(k = old[[k]]) }, add = TRUE)
  do.call(Sys.setenv, as.list(env))
  t0 <- Sys.time()
  rc <- tryCatch(system2("Rscript", shQuote(l2_runner(code_root)), stdout = log_path, stderr = log_path, timeout = cfg$arm_timeout_min * 60), error = function(e) 99L)
  # 결과 파일 = 러너의 FR_ID 규칙(run_wf_ensemble.R:264-266): FR_ID = FR_RUN_ID [+ "_" + FR_ARM_TAG] · <FR_ID>_result.json ·
  #   진단 = <FR_DIAG_DIR>/<FR_ID>_manipulation_check.json. 이번 실행분만 인정(mtime ≥ 시작 시각).
  fr_id <- if (nzchar(arm$tag)) paste0(run_id, "_", arm$tag) else run_id
  rp <- file.path(root, "04_Research/factor_rotation/output", paste0(fr_id, "_result.json"))
  fresh <- function(p) file.exists(p) && file.info(p)$mtime >= t0 - 5
  res <- if (fresh(rp)) .l2_rj(rp) else NULL
  mp_ <- file.path(diag_dir, paste0(fr_id, "_manipulation_check.json"))
  mc <- if (fresh(mp_)) .l2_rj(mp_) else NULL
  fs <- if (fresh(rp)) rp else character(0)
  list(arm = arm$id, tag = arm$tag, rc = as.integer(rc), minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1),
       result_path = if (length(fs)) fs[1] else "", result = res, mc = mc, ok = identical(as.integer(rc), 0L) && !is.null(res))
}
L2_ARMS <- list(T = list(id = "T", tag = "", register = TRUE, lag = 0L, pool = "full",  label = "π₀ 기준"),
                S = list(id = "S", tag = "S_lag1", register = FALSE, lag = 1L, pool = "full",  label = "lag+1 PIT 스트레스"),
                C = list(id = "C", tag = "C_flooronly", register = FALSE, lag = 0L, pool = "floor", label = "floor-only 대조(방어형 제외)"))

# ── MC 게이트 · 교훈 ─────────────────────────────────────────────────────────────────────────
l2_mc_gates <- function(mc) {
  m1 <- (mc %||% list())$MC1_membership %||% list(); m2 <- (mc %||% list())$MC2_weights %||% list()
  list(mc1_delivered = if (is.null(m1$delivered)) NA else isTRUE(m1$delivered), mc1_jaccard = .l2_num(m1$jaccard_median),
       mc2_delivered = if (is.null(m2$delivered)) NA else isTRUE(m2$delivered), mc2_retention = .l2_num(m2$retention_median))
}
l2_lessons <- function(runs, gates, cfg, pool_truncated = FALSE, pool_n = NA) {
  T <- runs$T; S <- runs$S; C <- runs$C; eT <- (T$result %||% list())$essence %||% list()
  L <- character(0)
  L <- c(L, sprintf("[T π₀] grade %s · PORT_t %s · Calmar %s · CAGR %s · MDD %s · DSR %s · n_modules %s · selection_type=%s(%s %s)",
                    .l2_chr((T$result %||% list())$grade), .l2_f3(eT$portfolio_alpha_t_nw_lag3), .l2_f3(eT$calmar), .l2_f3(eT$cagr), .l2_f3(eT$mdd), .l2_f3(eT$dsr),
                    .l2_chr((T$result %||% list())$n_modules), cfg$selection_type, cfg$decided_by, cfg$decided_at))
  if (!is.null(S) && !is.null(S$result)) { eS <- S$result$essence %||% list()
    L <- c(L, sprintf("[S lag+1] SR %s vs T %s (Δ %+.3f) · PORT_t %s vs %s — C5 동월누출 스트레스(붕괴하면 누출 의심)",
                      .l2_f3(eS$net_sharpe), .l2_f3(eT$net_sharpe), .l2_num(eS$net_sharpe) - .l2_num(eT$net_sharpe), .l2_f3(eS$portfolio_alpha_t_nw_lag3), .l2_f3(eT$portfolio_alpha_t_nw_lag3))) }
  if (!is.null(C) && !is.null(C$result)) { eC <- C$result$essence %||% list()
    d <- .l2_num(eT$portfolio_alpha_t_nw_lag3) - .l2_num(eC$portfolio_alpha_t_nw_lag3)
    L <- c(L, sprintf("[C floor-only %s모듈] PORT_t %s vs T %s (T−C %+.3f) · Calmar %s vs %s — 방어형 재고 귀속: %s",
                      .l2_chr(C$result$n_modules), .l2_f3(eC$portfolio_alpha_t_nw_lag3), .l2_f3(eT$portfolio_alpha_t_nw_lag3), d, .l2_f3(eC$calmar), .l2_f3(eT$calmar),
                      if (is.finite(d) && d < 0) "희석(방어형이 알파를 깎았다)" else if (is.finite(d)) "기여" else "판정 불가")) }
  if (identical(gates$mc1_delivered, FALSE))
    L <- c(L, sprintf("regime_channel_not_delivered — MC1 Jaccard 중앙 %s ≥ 0.9: 국면별 admitted 집합이 같다. 이 결과에 '국면조건부' 라벨을 붙이지 않는다(준-EW over RCMA-filtered pool)", .l2_f3(gates$mc1_jaccard)))
  if (identical(gates$mc2_delivered, FALSE))
    L <- c(L, sprintf("dispatcher_signal_lost — MC2 retention 중앙 %s < 0.25: 배분기 신호가 softmax 에서 소실(풀 %s 에 hp 5~10 기준)", .l2_f3(gates$mc2_retention), .l2_chr(pool_n)))
  if (isTRUE(pool_truncated)) L <- c(L, sprintf("pool_truncated — 메모리 가드로 풀을 %s 로 잘라 측정(조용한 축소 아님 · 원장에 표기)", .l2_chr(pool_n)))
  L
}
l2_forbidden_label <- function(text, gates) identical(gates$mc1_delivered, FALSE) && any(grepl("국면조건부", text, fixed = TRUE) & !grepl("붙이지 않는다", text, fixed = TRUE))

# ── 텔레그램 [2계층·강화 n] ─────────────────────────────────────────────────────────────────
l2_notify <- function(base_id, n, runs, gates, lessons, root, code_root, grade) {
  ok <- tryCatch({
    TG <- new.env(parent = globalenv())
    invisible(capture.output(suppressMessages(suppressWarnings(sys.source(file.path(code_root, "02_Infrastructure/telegram/telegram_notify.R"), envir = TG)))))
    g <- function(a) .l2_chr(((runs[[a]] %||% list())$result %||% list())$grade %||% "-")
    secs <- list(
      list(type = "kv", heading = "현재 리서치 상황", kv = list(
        "단계" = sprintf("2계층 강화 %d회차 (무인 레인 첫 실측)", n), "대상" = base_id,
        "위치" = "π₀ = unified_regime Category(t-1) · walk-forward RCMA · rp⊕IR 배분기 · 풀 = module_performance.json",
        "직전 판정" = sprintf("T %s · S %s · C %s · MC1 %s", g("T"), g("S"), g("C"), if (isTRUE(gates$mc1_delivered)) "전달" else if (identical(gates$mc1_delivered, FALSE)) "미전달" else "?"))),
      list(type = "bullet", heading = "arm 결과", items = vapply(names(runs), function(a) { r <- runs[[a]]; e <- (r$result %||% list())$essence %||% list()
        sprintf("%s(%s): grade %s · PORT_t %s · Calmar %s · MDD %s · %s분%s", a, L2_ARMS[[a]]$label, g(a), .l2_f3(e$portfolio_alpha_t_nw_lag3), .l2_f3(e$calmar), .l2_f3(e$mdd), .l2_chr(r$minutes), if (isTRUE(r$ok)) "" else " ★실패") }, character(1))),
      list(type = "bullet", heading = "교훈", items = if (length(lessons) >= 2L) substr(lessons, 1, 220) else c(substr(lessons, 1, 220), "다음 회차 = 디렉터 규칙 4 감시(MC1 2회 연속 미전달이면 π₀ 재실행 중단)")))
    res <- TG$tg_agent_brief(agent = "Q-Lead", title = sprintf("[2계층·강화 %d] %s — T %s · S %s · C %s%s", n, base_id, g("T"), g("S"), g("C"), if (identical(grade, "A")) " ★A — Judge 요청" else ""),
                             sections = secs, lock_scope = sprintf("rf_l2_%s_%d", base_id, n), relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off")
    isTRUE(res$ok %||% TRUE)
  }, error = function(e) { message("[l2_auto] 텔레그램 실패: ", conditionMessage(e)); FALSE })
  ok
}
