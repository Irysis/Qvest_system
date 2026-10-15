## round_kit.R — 프로그램 라운드 공용 부품(측정 · 칸 평가) — P0R01 평가 절차를 일반화(2026-10-13 밤)
##   측정 = 정본 셀 워커(rf_cell_worker.R) · 칸 평가 = 축 감사 + 보는 창 진단 패킷(dp_build · 사전등록 행동 카드 설정 · 위생 raw)
##   + 전기간 행동 카드(mc_card) + 시험 창 성과(등급 v3 의 gv3_window). 수치는 전부 R 계약 산출(손계산 없음 · AX-008).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
rk_md5 <- function(f) unname(as.character(tools::md5sum(f)))

## 칸 평가 분할(병렬 · 2026-10-15) — 인자 `--shard=i/K` 가 있으면 칸 목록의 i 번째 몫(1-based · 교차 배정 = 칸 순서상
##   (j−1) mod K = i−1 — 엔진 · 부품이 몫마다 고르게 섞인다)만 돌려준다. 없으면 전부. 몫들은 서로 겹치지 않고 합치면 전부다.
##   칸 평가는 칸마다 results/<code>/ 에만 쓰므로 몫끼리 경합하지 않는다. 종합 판정(--cells-only 아님)에는 쓰지 않는다.
rk_shard <- function(cells, args = commandArgs(trailingOnly = TRUE)) {
  a <- grep("^--shard=", args, value = TRUE)
  if (!length(a)) return(cells)
  v <- suppressWarnings(as.integer(strsplit(sub("^--shard=", "", a[1]), "/", fixed = TRUE)[[1]]))
  if (length(v) != 2L || anyNA(v) || v[2] < 1L || v[1] < 1L || v[1] > v[2]) stop("[round_kit] --shard=i/K 형식 오류: ", a[1])
  cells[(seq_along(cells) - 1L) %% v[2] == (v[1] - 1L)]
}

## 칸 1개 측정 — 사양 md5 = 사전등록 값이어야 한다(R2) · 결과가 있으면 건너뜀
rk_measure_cell <- function(root, round_dir, prereg_path, code) {
  spec <- file.path(round_dir, "specs", paste0(code, ".json"))
  pre <- fromJSON(prereg_path, simplifyVector = FALSE)
  cell <- Filter(function(z) identical(z$code, code), pre$cells)
  if (!length(cell) || !identical(cell[[1]]$md5, rk_md5(spec))) stop("[round_kit] 사양 md5 ≠ 사전등록(R2): ", code)
  res_dir <- file.path(round_dir, "results"); dir.create(res_dir, recursive = TRUE, showWarnings = FALSE)
  out <- file.path(res_dir, paste0(code, ".json"))
  if (file.exists(out) && isTRUE(fromJSON(out)$ok)) { cat("[측정] 이미 있음:", code, "\n"); return(invisible(0L)) }
  t0 <- Sys.time()
  rc <- system2("Rscript", c(file.path(root, "02_Infrastructure/ops/rf_cell_worker.R"), shQuote(spec), "1", code, shQuote(out)),
                stdout = file.path(res_dir, paste0(code, ".log")), stderr = file.path(res_dir, paste0(code, ".err.log")))
  cat(sprintf("[측정] %s rc=%s · %.1f분\n", code, rc, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  invisible(rc)
}

## 축 감사 — 04_holdings 실보유(롱온리 · ≤ max_names · Σw ≤ 1)
rk_axis_audit <- function(root, dir) {
  CD <- fromJSON(file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
  MAXN <- as.integer(CD$tier_soft_deployment$max_names)
  H <- fread(file.path(dir, "04_holdings.csv"))
  wc <- intersect(c("target_weight", "actual_weight"), names(H))[1]
  H[, w := as.numeric(get(wc))]
  per <- H[is.finite(w) & w != 0, .(n = .N, s = sum(w), mn = min(w)), by = date]
  list(max_names = MAXN, n_max_realized = max(per$n), w_min = min(per$mn), sigma_w_max = max(per$s),
       ok = max(per$n) <= MAXN && min(per$mn) >= -1e-9 && max(per$s) <= 1 + 1e-6)
}

## 시험 창 성과 — 등급 v3 의 같은 창 함수(2023-01~)
rk_test_perf <- function(E, root, dir, tau) {
  rd <- .dp_read(E, dir)
  prt <- rd$pr[date > tau][order(date)]; brt <- rd$br[date > tau][order(date)]; nvt <- rd$nv[date > tau][order(date)]
  if (nrow(prt) < 20L) return(list(status = "insufficient"))
  emptyM <- data.table(metric_name = character(0), metric_value = numeric(0)); emptyC <- data.table(metric_name = character(0), active_value = numeric(0))
  X <- E$.gv3_prep(prt, brt, nvt, emptyM, emptyC)
  p <- E$gv3_window(X$pr, X$br, X$nv, root = root)
  c(list(status = "ok", window = c(format(min(prt$date)), format(max(prt$date)))), p[intersect(names(p), c("cagr", "mdd", "calmar", "sharpe", "port_t"))])
}

rk_getf <- function(x, path) { for (k in strsplit(path, ".", fixed = TRUE)[[1]]) { if (is.null(x)) return(NA_real_); x <- x[[k]] }
                               v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L) v else NA_real_ }

## 칸 평가(캐시 = results/<code>/eval.json) — env 는 raw · E · BCFG_L 을 담은 환경(raw 는 처음 필요할 때 한 번 읽는다)
rk_eval_cell <- function(root, round_dir, cell, env, tau) {
  RES <- file.path(round_dir, "results")
  out_dir <- file.path(RES, cell$code); ej <- file.path(out_dir, "eval.json")
  if (file.exists(ej)) return(fromJSON(ej, simplifyVector = FALSE))
  rj <- file.path(RES, paste0(cell$code, ".json"))
  if (!file.exists(rj)) return(list(code = cell$code, status = "not_measured"))
  r <- fromJSON(rj, simplifyVector = FALSE)
  if (!isTRUE(r$ok)) return(list(code = cell$code, status = "measure_failed", err = r$err %||% NA))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(env$raw)) env$raw <- mc_load_raw(root, from = "1999-11-01", hygiene = TRUE)
  t0 <- Sys.time()
  ax <- rk_axis_audit(root, r$artifacts)
  vis <- dp_build(r$artifacts, root = root, cell_spec = file.path(root, cell$path), raw = env$raw, bcfg = env$BCFG_L)
  dp_write(vis, file.path(out_dir, "visible"))
  card <- mc_card(r$artifacts, root = root, raw = env$raw, bcfg = env$BCFG_L)
  mc_write(card, file.path(out_dir, "full"), root = root)
  tp <- tryCatch(rk_test_perf(env$E, root, r$artifacts, tau), error = function(e) list(status = paste("error:", conditionMessage(e))))
  ar <- fromJSON(file.path(r$artifacts, "authoritative_remeasure.json"), simplifyVector = FALSE)
  g <- function(p) rk_getf(vis, p)
  ev <- list(code = cell$code, engine = cell$engine %||% NA, component = cell$component %||% NA, status = if (isTRUE(ax$ok)) "evaluated" else "axis_violation",
             artifacts = r$artifacts, axis = ax,
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
  writeLines(toJSON(ev, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), ej)
  cat(sprintf("[평가] %s — UC %.3f · DC %.3f · CAGR %.3f · CDaR %.3f · 축 %s · %.0f초\n", cell$code, ev$visible$uc, ev$visible$dc,
              ev$visible$cagr, ev$visible$cdar, ax$ok, ev$eval_seconds))
  ev
}

## 보는 창 종합점수 S_vis(등급 v3 의 S 식 · 상수는 사전등록이 정본에서 옮긴 값)
rk_S <- function(calmar, port_t, fs) ifelse(is.finite(calmar) & is.finite(port_t) & calmar > 0 & port_t > 0,
                                           (calmar / fs$calmar_norm)^fs$w_calmar * (port_t / fs$port_t_norm)^fs$w_port_t, 0)
