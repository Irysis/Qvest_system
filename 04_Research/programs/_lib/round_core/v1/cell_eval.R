## round_core v1 · cell_eval — 칸 1개 평가(round_kit rk_eval_cell 이관 · 같은 계약 호출 · 같은 기록 필드)
##   더한 것: 내용 주소 캐시(eval.key) — 칸 산출물 · 칸 사양 · 코어 매니페스트 · 행동 카드 설정 · τ_D 중 하나라도 바뀌면 다시 평가한다.
##   현행 rk_eval_cell 은 eval.json 이 있으면 그대로 돌려줘, 재측정 뒤 옛 평가를 쓰는 결함이 있었다(P3R03 격리 점검 · 체크리스트 2).
##   원자료(위생 raw)는 프로세스당 한 번 적재해 env 에 둔다(속도 계획 5-2 '한 번 읽는다').

RC_EVAL_KEY_FILES <- c("authoritative_remeasure.json", "02_nav.csv", "03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv")

## 축 감사 — 04_holdings 실보유(롱온리 · ≤ max_names · Σw ≤ 1) — rk_axis_audit 이관
rc_axis_audit <- function(root, dir) {
  CD <- rc_json_read(file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"))
  MAXN <- as.integer(CD$tier_soft_deployment$max_names)
  H <- fread(file.path(dir, "04_holdings.csv"))
  wc <- intersect(c("target_weight", "actual_weight"), names(H))[1]
  H[, w := as.numeric(get(wc))]
  per <- H[is.finite(w) & w != 0, .(n = .N, s = sum(w), mn = min(w)), by = date]
  list(max_names = MAXN, n_max_realized = max(per$n), w_min = min(per$mn), sigma_w_max = max(per$s),
       ok = max(per$n) <= MAXN && min(per$mn) >= -1e-9 && max(per$s) <= 1 + 1e-6)
}

## 시험 창 성과 — 등급 v3 의 같은 창 함수(2023-01~) — rk_test_perf 이관
rc_test_perf <- function(E, root, dir, tau) {
  rd <- .dp_read(E, dir)
  prt <- rd$pr[date > tau][order(date)]; brt <- rd$br[date > tau][order(date)]; nvt <- rd$nv[date > tau][order(date)]
  if (nrow(prt) < 20L) return(list(status = "insufficient"))
  emptyM <- data.table(metric_name = character(0), metric_value = numeric(0)); emptyC <- data.table(metric_name = character(0), active_value = numeric(0))
  X <- E$.gv3_prep(prt, brt, nvt, emptyM, emptyC)
  p <- E$gv3_window(X$pr, X$br, X$nv, root = root)
  c(list(status = "ok", window = c(format(min(prt$date)), format(max(prt$date)))), p[intersect(names(p), c("cagr", "mdd", "calmar", "sharpe", "port_t"))])
}

rc_getf <- function(x, path) { for (k in strsplit(path, ".", fixed = TRUE)[[1]]) { if (is.null(x)) return(NA_real_); x <- x[[k]] }
                               v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L) v else NA_real_ }

## 캐시 키 — 산출물 파일 · 칸 사양 · 코어 매니페스트 · 행동 카드 설정 · τ_D 의 md5 를 한 줄로
rc_eval_key <- function(artifacts, cell_spec_path, bcfg_md5, tau, manifest_md5 = rc_core_manifest()$manifest_md5) {
  src <- .rc_artifact_dir(artifacts)
  parts <- c(vapply(RC_EVAL_KEY_FILES, function(f) { p <- file.path(src, f); if (file.exists(p)) rc_md5(p) else "absent" }, character(1)),
             spec = if (!is.null(cell_spec_path) && file.exists(cell_spec_path)) rc_md5(cell_spec_path) else "none",
             core = manifest_md5, bcfg = bcfg_md5 %||% "default", tau = format(as.Date(tau)))
  paste(names(parts), parts, sep = "=", collapse = ";")
}
## 산출물 디렉터리 해석 — 계약의 ta_resolve_artifact 와 같은 규칙(경로 그대로가 기본)
.rc_artifact_dir <- function(dir) {
  E <- .RC$E
  if (!is.null(E) && is.function(E$ta_resolve_artifact)) tryCatch(E$ta_resolve_artifact(dir)$dir, error = function(e) dir) else dir
}

## 칸 평가 — env = new.env()(E · BCFG_L · bcfg_md5 · raw) · cell = 사양의 칸(code · engine · component · spec) · 측정 결과 = results/<code>.json
rc_eval_cell <- function(root, round_dir, cell, env, tau) {
  RES <- file.path(round_dir, "results")
  out_dir <- file.path(RES, cell[["code"]]); ej <- file.path(out_dir, "eval.json"); ek <- file.path(out_dir, "eval.key")
  rj <- file.path(RES, paste0(cell[["code"]], ".json"))
  if (!file.exists(rj)) return(list(code = cell[["code"]], status = "not_measured"))
  r <- rc_json_read(rj)
  if (!isTRUE(r$ok)) return(list(code = cell[["code"]], status = "measure_failed", err = r$err %||% NA))
  spec_path <- if (!is.null(cell[["spec"]])) rc_abs(cell[["spec"]], root) else NULL
  key <- rc_eval_key(r$artifacts, spec_path, env$bcfg_md5, tau)
  if (file.exists(ej) && file.exists(ek) && identical(readLines(ek, warn = FALSE)[1], key)) return(rc_json_read(ej))
  unlink(out_dir, recursive = TRUE); dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(env$raw)) env$raw <- mc_load_raw(root, from = "1999-11-01", hygiene = TRUE)
  t0 <- Sys.time()
  ax <- rc_axis_audit(root, r$artifacts)
  vis <- dp_build(r$artifacts, root = root, cell_spec = spec_path, raw = env$raw, bcfg = env$BCFG_L)
  dp_write(vis, file.path(out_dir, "visible"))
  card <- mc_card(r$artifacts, root = root, raw = env$raw, bcfg = env$BCFG_L)
  mc_write(card, file.path(out_dir, "full"), root = root)
  tp <- tryCatch(rc_test_perf(env$E, root, r$artifacts, tau), error = function(e) list(status = paste("error:", conditionMessage(e))))
  ar <- rc_json_read(file.path(r$artifacts, "authoritative_remeasure.json"))
  g <- function(p) rc_getf(vis, p)
  ev <- list(code = cell[["code"]], engine = cell[["engine"]] %||% NA, component = cell[["component"]] %||% NA,
             status = if (isTRUE(ax$ok)) "evaluated" else "axis_violation", artifacts = r$artifacts, axis = ax,
             visible = list(window = vis$window, uc = g("behavior.summary.bull_up_capture_median"), dc = g("behavior.summary.crisis_cum_capture_median"),
                            dc_strong = g("behavior.dc_strong_max"), cagr = g("performance.strategy.cagr"), calmar = g("performance.strategy.calmar"),
                            port_t = g("performance.strategy.port_t"), mdd = g("performance.strategy.mdd"), sharpe = g("performance.strategy.sharpe"),
                            cdar = g("behavior.stats.cdar"), beta = g("behavior.stats.beta"),
                            dd_capture_median = g("behavior.summary.crisis_dd_capture_median"), dd_capture_worst = g("behavior.summary.crisis_dd_capture_worst"),
                            n_crisis = g("behavior.summary.n_crisis"), n_bull = g("behavior.summary.n_bull"), verdict = vis$behavior$verdict,
                            attribution = vis$controls$attribution$label %||% NA, exposure_mean = g("controls.exposure_profile.mean"),
                            turnover_annual = g("profile.turnover_annual"), cost_drag_annual = g("profile.cost_drag_annual")),
             test = list(uc = card$test$bull_up_capture_median %||% NA, dc = card$test$crisis_cum_capture_median %||% NA,
                         n_bull = card$test$n_bull %||% NA, n_crisis = card$test$n_crisis %||% NA, verdict = card$test$verdict %||% NA,
                         dc_strong = card$dc_strong_max %||% NA, perf = tp),
             full = list(grade = ar$essence_grade, S = ar$grade_v3$S %||% NA, cr = card$overall$verdict, attribution = card$controls$attribution$overall$label %||% NA,
                         cdar = card$stats$cdar %||% NA, effective_start = ar$measurement_axis$effective_start$date %||% NA),
             eval_seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  rc_json_write(ev, ej)
  writeLines(key, ek, useBytes = TRUE)
  ev
}

## 평가 환경 — 행동 카드 설정(사전등록 사본 경로가 있으면 그 판 · R2) · 원자료는 처음 필요할 때 한 번
rc_eval_env <- function(root = rc_root(), bcfg_path = NULL) {
  env <- new.env(); env$E <- rc_deps(root)
  env$BCFG_L <- if (!is.null(bcfg_path)) env$E$bc_cfg(root, path = rc_abs(bcfg_path, root)) else NULL
  env$bcfg_md5 <- if (!is.null(bcfg_path)) rc_md5(rc_abs(bcfg_path, root)) else NULL
  env$raw <- NULL
  env
}
