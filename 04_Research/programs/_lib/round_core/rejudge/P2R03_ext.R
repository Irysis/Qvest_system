## P2R03 고유 규칙(round_ext) — 코어 P2 템플릿 위에서 P2R03(조건부 시변 노출 층 · lag-1 진단) 판정을 재현한다(재판정 · 픽스처 대조).
##   이 라운드가 코어에 더하는 것 = 장치 표(오버레이 arm) · ⑩ 오버레이 집행 증거 · 같은 선정 집합(오버레이판) · lag-1 꼬리표 · 보류 조건 (b) ·
##   HM · 현금 타이밍 기록 · 판정어(slow_only) · 대조 읽기 · 보는 창 파일 형식(가림 없음 — P2R04 이전 판).
##   출처: P2R03 evaluate.R(등록 9bb76f972 · 파일 5346d12da) — 각 함수 줄 번호. 공용 단계 · 도우미 = round_core v1.
P2R03_ROUND_ID <- "P2R03_conditional_overlay"
P2R03_DEVICES <- list(
  D1 = list(kind = "dbeta_tilt",          arm_id = "dbeta_tilt_rank", name = "낙폭 국면 × 하방베타 순위 축소(횡단면)"),
  D2 = list(kind = "gen_20260903_133452", arm_id = "csd_idio_tilt",   name = "횡단면분산 국면 × 특이변동 순위 축소(횡단면)"),
  D3 = list(kind = "turbulence",          arm_id = "turbulence",      name = "벤치 상태 벡터 거리 게이트(마할라노비스 · 스칼라)"),
  D4 = list(kind = "ml_tail_gate",        arm_id = "ml_tail_gate",    name = "확장창 로지스틱 꼬리 확률 게이트(노출 = 1 − p̂ · 분포 표적)"),
  D5 = list(kind = "ts_mom_gate",         arm_id = "ts_mom_sign",     name = "추세 현금(시장 12개월 수익 < 0 → 현금 · 재시험)"),
  D6 = list(kind = "dd_brake",            arm_id = "dd_brake_q",      name = "낙폭 브레이크(낙폭 중앙~90분위 선형 축소 · 재시험)"),
  D7 = list(kind = "dd_recovery",         arm_id = "dd_recovery",     name = "낙폭 국면 재진입 게이트(직전 1개월 시장 상승이면 노출 유지 · 재시험 · 철학 P1 C-045)"))
P2R03_SLOW_NOTE <- "기록 · lag-1 조건 (b)(느린 약세 개선이 lag-1 에서 무너지면 누출 조사 · 최종 선택 보류)"

## HM 타이밍 회귀(기록 · C-044) — 출처: P2R03 L155-161(계약 beta_controlled_alpha.R .nw_fit)
p2r03_hm_fit <- function(diff, bench, nw_lag = 3L) {
  d <- suppressWarnings(as.numeric(diff)); k <- suppressWarnings(as.numeric(bench)); ok <- is.finite(d) & is.finite(k)
  if (sum(ok) < 24L || !exists(".nw_fit", mode = "function")) return(list(status = if (sum(ok) < 24L) "n<24" else "nw_fit 없음", gamma = NA_real_, t_gamma = NA_real_))
  f <- tryCatch(.nw_fit(d[ok], cbind(k[ok], pmax(0, -k[ok])), lag = nw_lag), error = function(e) NULL)
  if (is.null(f)) return(list(status = "fit 실패", gamma = NA_real_, t_gamma = NA_real_))
  list(status = "ok", n = f$n, alpha_m = f$coef[1], beta = f$coef[2], t_beta = f$t[2], gamma = f$coef[3], t_gamma = f$t[3])
}
## 현금 타이밍(기록 · C-048) — 출처: P2R03 L164-179
p2r03_cash_timing <- function(expo_m, crises, cash_thr = 0.5) {
  E <- as.data.table(expo_m); cr <- .rc_rows_dt(crises)
  if (!nrow(E) || !all(c("ym", "e") %in% names(E))) return(list(status = "unmeasured"))
  E <- E[is.finite(e)][order(ym)]
  cm <- if (nrow(cr)) unique(unlist(lapply(seq_len(nrow(cr)), function(i) {
    s <- as.Date(paste0(substr(as.character(cr$peak_date[i]), 1, 7), "-01")); t <- as.Date(paste0(substr(as.character(cr$trough_date[i]), 1, 7), "-01"))
    format(seq(s, t, by = "month"), "%Y-%m") }))) else character(0)
  E[, crisis := ym %in% cm][, cash := e <= cash_thr]
  reb <- function(h) { v <- unlist(lapply(seq_len(nrow(cr)), function(i) {
    t <- as.Date(paste0(substr(as.character(cr$trough_date[i]), 1, 7), "-01")); w <- format(seq(t, by = "month", length.out = h + 1L)[-1], "%Y-%m")
    E[ym %in% w, e] })); if (length(v)) mean(v) else NA_real_ }
  list(status = "ok", cash_thr = cash_thr, n_months = nrow(E), cash_share = mean(E$cash), expo_mean = mean(E$e),
       precision = if (any(E$cash)) mean(E$crisis[E$cash]) else NA_real_, recall = if (any(E$crisis)) mean(E$cash[E$crisis]) else NA_real_,
       expo_crisis = if (any(E$crisis)) mean(E$e[E$crisis]) else NA_real_, expo_noncrisis = if (any(!E$crisis)) mean(E$e[!E$crisis]) else NA_real_,
       rebound_3m = reb(3L), rebound_6m = reb(6L))
}
## 오버레이 집행 줄(⑩) — 출처: P2R03 L247-257
p2r03_parse_overlay_log <- function(lines) {
  s <- grep("^\\[rf_cell_engine\\] overlay [^ ]+ \\| 축 ", lines, value = TRUE)
  shift1 <- any(grepl("^\\[rf_cell_engine\\] overlay_shift=1 적용", lines))
  if (!length(s)) return(list(found = FALSE, shift1 = shift1))
  s <- s[length(s)]
  num <- function(p) { v <- suppressWarnings(as.numeric(sub(p, "\\1", s))); if (grepl(p, s)) v else NA_real_ }
  list(found = TRUE, shift1 = shift1, kind = sub("^\\[rf_cell_engine\\] overlay ([^ ]+) \\|.*", "\\1", s),
       axis = sub(".*\\| 축 ([^ ]+) \\|.*", "\\1", s), expo_mean = num(".*평균노출 ([0-9.]+).*"), expo_min = num(".*최소 ([0-9.]+).*"),
       full_cash_months = num(".*완전현금 ([0-9]+)/[0-9]+개월.*"), n_months = num(".*완전현금 [0-9]+/([0-9]+)개월.*"),
       xs_sd_max = num(".*횡단면 sd 최대 ([0-9.]+).*"), cash_exec = num(".*현금 집행\\(표현 하한\\) ([0-9]+)신호일.*"))
}
## 같은 선정 집합(오버레이판) — 출처: P2R03 L260-271
p2r03_subset_check <- function(H_var, H_rx0, tau) {
  hv <- H_var[is.finite(w) & w > 0]; hr <- H_rx0[is.finite(w) & w > 0 & date <= as.Date(tau)]
  if (!nrow(hv) || !nrow(hr)) return(list(status = "unmeasured", n_checked = 0L, n_violate = NA_integer_, n_missing = NA_integer_))
  dd <- sort(unique(hr$date)); viol <- character(0); miss <- character(0)
  for (d in as.list(dd)) {
    tv <- unique(hv[date == d, ticker]); tr <- unique(hr[date == d, ticker])
    if (!length(tv)) { miss <- c(miss, format(d)); next }
    if (!all(tv %in% tr)) viol <- c(viol, format(d))
  }
  list(status = "ok", n_checked = length(dd), n_violate = length(viol), n_missing = length(miss),
       violate_dates = utils::head(viol, 10L), missing_dates = utils::head(miss, 10L))
}
## lag-1 진단 꼬리표 · 보류 조건 (b) — 출처: P2R03 L302-319
p2r03_lag_hold <- function(d_out, l_out) {
  if (!isTRUE(d_out$tested)) return(FALSE)
  if (!isTRUE(l_out$tested)) return(TRUE)
  isTRUE(d_out$rules$slow$ok) && identical(l_out$rules$slow$ok, FALSE)
}
p2r03_lag_tag <- function(d_out, l_out) {
  if (!isTRUE(d_out$tested)) return("장치 칸 미시험 — lag-1 비교 없음")
  if (!isTRUE(l_out$tested)) return(sprintf("lag-1 판 미시험(%s) — 최종 선택 보류(pit.md C5 의무 2 · 격리 교차 점검 필수 3)", l_out$why %||% "?"))
  d3 <- isTRUE(d_out$rules$beta_deep$ok); d4 <- isTRUE(d_out$rules$fast$ok)
  l3 <- isTRUE(l_out$rules$beta_deep$ok); l4 <- isTRUE(l_out$rules$fast$ok)
  hold <- if (p2r03_lag_hold(d_out, l_out)) " · 느린 약세 개선이 lag-1 에서 붕괴 — 누출 조사 · 최종 선택 보류(철학 P1 C-052 (b))" else ""
  if (!d3 && !d4) return(sprintf("lag-1 비교 대상 없음(장치 ③ · ④ 미통과 · lag-1 ③ %s · ④ %s)%s", l3, l4, hold))
  lost <- c(if (d3 && !l3) "③", if (d4 && !l4) "④")
  paste0(if (!length(lost)) "lag-1 유지" else sprintf("지연 민감(lag-1 에서 %s 붕괴)", paste(lost, collapse = " · ")), hold)
}
## 보는 창 칸 — 출처: P2R03 L628-634(시험 창 알파 · 표 행 제거 · 집행 줄 수치 제거 — τ_D 가림 없음)
P2R03_OVERLAY_VISIBLE_KEYS <- c("found", "shift1", "kind", "axis", "kind_expected", "kind_ok")
p2r03_visible_only <- function(x) {
  x$alpha_test_window <- NULL; x$tbl <- NULL
  if (!is.null(x$overlay)) x$overlay <- x$overlay[intersect(names(x$overlay), P2R03_OVERLAY_VISIBLE_KEYS)]
  if (!is.null(x$rules$construction$overlay)) x$rules$construction$overlay <- x$rules$construction$overlay[intersect(names(x$rules$construction$overlay), P2R03_OVERLAY_VISIBLE_KEYS)]
  x
}

## ── 판정 1칸 단계(고유) ──
p2r03_init <- function(ctx, opts) list(engine = ctx$engine, device = ctx$unit, cell = ctx$cm$code, rx0 = ctx$cr$code, lag = isTRUE(ctx$cm$lag),
                                       status = ctx$em$status %||% NA, status_rx0 = ctx$er$status %||% NA)
p2r03_untested <- function(out, why) {                                           # 출처: P2R03 L417-421
  out$tested <- FALSE; out$verdict <- "untested"; out$why <- why
  out$tbl <- data.table(engine = out$engine, device = out$device, lag = isTRUE(out$lag), tested = FALSE, pass = FALSE, excluded = FALSE)
  out
}
## ⑩ 오버레이 집행 증거 — 출처: P2R03 L449-459
p2r03_st_overlay <- function(S) {
  X <- S$X; cm <- S$ctx$cm; opts <- S$opts; dev <- S$ctx$unit; lag <- isTRUE(S$out$lag)
  lg <- opts[["log"]] %||% file.path(X$res, paste0(cm$code, ".log"))
  L <- if (file.exists(lg)) readLines(lg, warn = FALSE, encoding = "UTF-8") else character(0)
  ol <- p2r03_parse_overlay_log(L)
  ol$kind_expected <- opts[["expect_kind"]] %||% (S$T$cfg$devices[[dev]]$kind %||% NA_character_)
  ol$kind_ok <- isTRUE(ol$found) && (is.na(ol$kind_expected) || identical(ol$kind, ol$kind_expected))
  S$out$overlay <- ol; S$ol <- ol
  want_shift <- if (!is.null(opts[["expect_shift"]])) isTRUE(opts[["expect_shift"]]) else lag
  if (!isTRUE(ol$found) || !identical(isTRUE(ol$shift1), want_shift) || !isTRUE(ol$kind_ok))
    return(sprintf("오버레이 집행 증거 불일치(집행 줄 %s · shift=1 줄 %s · 기대 %s · 층 %s/%s)", isTRUE(ol$found), isTRUE(ol$shift1), want_shift,
                   ol$kind %||% "-", ol$kind_expected %||% "-"))
  NULL
}
## 같은 선정 집합 — 출처: P2R03 L466-471
p2r03_st_subset <- function(S) {
  S$Hm <- tryCatch(rc_read_holdings(S$dm), error = function(e) data.table()); S$Hr <- tryCatch(rc_read_holdings(S$dr), error = function(e) data.table())
  ss <- p2r03_subset_check(S$Hm, S$Hr, S$X$tau); S$out$same_selection <- ss
  if (!identical(ss$status, "ok") || !identical(ss$n_violate, 0L) || !identical(ss$n_missing, 0L))
    return(sprintf("선정 집합 %s — 변형 보유 ⊄ RX0 보유 %s · 변형 보유 결측 %s / %s 보유일", ss$status, format(ss$n_violate),
                   format(ss$n_missing), format(ss$n_checked)))
  NULL
}
## 귀속 · HM · 현금 타이밍 · 기록 — 출처: P2R03 L589-609
p2r03_st_records <- function(S) {
  X <- S$X; g <- rc_getf; PM <- S$PM; PRX <- S$PRX; RL <- S$RL; TAU <- X$tau
  S$out$attribution <- list(label = as.character(PM$controls$attribution$label %||% NA)[1], label_rx0 = as.character(PRX$controls$attribution$label %||% NA)[1],
                            share_beats_size_exposure = g(PM, "controls.attribution.share_beats_size_exposure"),
                            share_beats_size_exposure_path = g(PM, "controls.attribution.share_beats_size_exposure_path"),
                            beta_copy_deep = RL$beta_deep$share, timing_vs_selection = if (isTRUE(RL$beta_deep$ok)) "시변 노출(타이밍) 방어 후보 — β 짝 통과" else "β 짝 미통과 — 노출(β) 방어 또는 방어 없음")
  hm <- tryCatch({
    E <- X$env$E; v <- .dp_read(E, S$am); b <- .dp_read(E, S$ar); mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
    S2 <- merge(mon(v$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(b$pr[, .(date, ret_net)], "ret_net")[, .(ym, b = r)], by = "ym")
    D2 <- merge(S2, mon(b$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)], by = "ym")[ym <= format(TAU, "%Y-%m")][order(ym)]
    p2r03_hm_fit(D2$s - D2$b, D2$k)
  }, error = function(e) list(status = paste("오류:", conditionMessage(e))))
  ct <- tryCatch({
    Hv <- S$Hm[date <= TAU & is.finite(w) & w > 0, .(e = sum(w)), by = date][order(date)][, .(ym = format(date, "%Y-%m"), e)][, .(e = e[.N]), by = ym]
    list(expo_m = Hv, timing = p2r03_cash_timing(Hv, S$crm))
  }, error = function(e) list(expo_m = NULL, timing = list(status = paste("오류:", conditionMessage(e)))))
  S$out$record <- list(hm_timing = hm, cash_timing = ct$timing, expo_m = ct$expo_m,
                       rolling = PM$behavior$rolling, turnover_annual = c(variant = g(PM, "profile.turnover_annual"), rx0 = g(PRX, "profile.turnover_annual")),
                       cost_drag_annual = c(variant = g(PM, "profile.cost_drag_annual"), rx0 = g(PRX, "profile.cost_drag_annual")),
                       exposure_mean = c(variant = g(PM, "controls.exposure_profile.mean"), rx0 = g(PRX, "controls.exposure_profile.mean")),
                       crisis_dd_capture_median = c(variant = g(PM, "behavior.summary.crisis_dd_capture_median"), rx0 = g(PRX, "behavior.summary.crisis_dd_capture_median")),
                       size_decile = "exposure.by_size_decile(패킷) — 유동성 3분위는 미측정")
  NULL
}
## 칸 통과 · 판정어(slow_only 포함) — 출처: P2R03 L610-618
p2r03_st_verdict <- function(S) {
  RL <- S$RL; r3 <- S$r3; r4 <- S$r4
  decisive <- RL$crisis$ok && RL$deep$ok && isTRUE(r3) && isTRUE(r4)
  strength <- isTRUE(S$r5) && RL$bull$ok && isTRUE(S$aok) && RL$cycle$ok
  S$out$pass <- decisive && strength && isTRUE(S$r12) && isTRUE(S$r13) && RL$construction$ok
  S$out$verdict <- if (S$out$pass) "pass" else if (!is.null(S$berr) || is.na(r3)) "beta_unmeasured" else if (is.na(r4) && isTRUE(r3)) "fast_unmeasured" else
                   if (RL$crisis$ok && RL$deep$ok && !isTRUE(r3)) "exposure_only" else if (isTRUE(r3) && !isTRUE(r4)) "slow_only" else
                   if (decisive) "defense_but_strength_or_path" else "not_decisive"
  S$out$tested <- TRUE
  S$out$tbl <- data.table(engine = S$ctx$engine, device = S$ctx$unit, lag = isTRUE(S$out$lag), tested = TRUE, pass = S$out$pass, excluded = !identical(S$cst, "clear"))
  NULL
}
## 템플릿 — 코어 P2 단계(창 = 패킷 포함판 · β 짝 구판 계획 · RL 위기 표 per_crisis 제외 · ⑭ 없음) + 고유 단계
P2R03_T <- rc_p2_template(
  cfg = list(devices = P2R03_DEVICES, mark_full = FALSE, rl_keep_per_crisis = FALSE, slow_note = P2R03_SLOW_NOTE, beta_plan = rc_beta_plan_v1,
             beta_unmeasured_why = function(k) "k 비유한", alpha_degenerate = FALSE, fast_err_no_month_end = FALSE, selection = FALSE),
  hooks = list(init = p2r03_init, untested = p2r03_untested, construction_rule = function(S) list(overlay = S$ol, ok = TRUE),
               stages = list(rc_st_consts, rc_st_status, p2r03_st_overlay, rc_st_effective_start, p2r03_st_subset, rc_st_window_packets, rc_st_engine_alpha,
                             rc_st_crisis_pairs, rc_p2_st_beta, rc_p2_st_inputs, rc_p2_st_judge, rc_p2_st_concentration, p2r03_st_records, p2r03_st_verdict)))

## ── 라운드 판정(출처: P2R03 본 실행 L636-732) — 코어 블록(칸 평가 · 지문 · 짝 실행 · 샤딩 · 라운드 판정 · 선택)으로 조립 ──
p2r03_R <- function(root, res, out, perf_env = NULL, ...) {
  rd <- file.path(root, "04_Research/programs/P2_DEFENSE", P2R03_ROUND_ID)
  pp <- file.path(root, "stage_artifacts/programs/P2_DEFENSE", P2R03_ROUND_ID, "prereg.json")
  utils::modifyList(list(round_id = P2R03_ROUND_ID, program = "P2_DEFENSE", tag = "P2R03", pre = fromJSON(pp, simplifyVector = FALSE), prereg_path = pp,
                         root = root, res = res, out = out, precheck = file.path(res, "precheck.json"),
                         fingerprint = list(script = file.path(rd, "fingerprint.sh"), args = character(0), record_args = character(0)),
                         evaluate_md5 = rc_md5(file.path(rd, "evaluate.R")), cell_cache = "legacy", cell_write = FALSE, check_pins = TRUE, perf_env = perf_env), list(...))
}
p2r03_round <- function(R, T = P2R03_T, shard = NULL, merge = FALSE) {
  pre <- R$pre; root <- R$root; RES <- R$res; tag <- R$tag
  E <- rc_deps(root)
  if (isTRUE(R$memo)) { rc_memo_install(E); if (isTRUE(R$mc8_memo)) rc_mc_memo_install(E, root) }
  reg <- pr_load(root); rr <- Filter(function(r) identical(r$round_id, R$round_id), pr_get(reg, R$program)$rounds)
  if (!length(rr) || !identical(rr[[1]]$prereg_md5, rc_md5(R$prereg_path))) stop("[P2R03 평가] 사전등록 md5 불일치(R2)")
  BCFG <- file.path(root, pre[["behavior_card_cfg"]]$path)
  if (!identical(rc_md5(BCFG), pre[["behavior_card_cfg"]]$md5)) stop("[P2R03 평가] 행동 카드 설정 사본 변경")
  pin <- rc_legacy_pin_mismatches(pre, root, kinds = NULL)                       # P2R03 판 = 종류 검사 없음
  if (length(pin)) stop("[P2R03 평가] 핀 불일치 — 평가하지 않는다:\n", paste0("  · ", pin, collapse = "\n"))
  if (!file.exists(R$precheck) || !isTRUE(fromJSON(R$precheck)$ok)) stop("[P2R03 평가] precheck 통과 기록이 없다 — 측정 조건 미확인")
  TAU <- as.Date(pre[["tau_d"]]); FS <- pre[["final_selection_rule"]]
  env <- new.env(); env$E <- E; env$BCFG_L <- E$bc_cfg(root, path = BCFG); env$raw <- NULL
  t0 <- Sys.time()
  EVS <- lapply(pre[["cells"]], function(cl) rc_eval_cell_split_safe(root, RES, cl, env, TAU, cache = "legacy", diagnostic_field = FALSE, audience = RC_FULL_AUDIENCE,
                                                               tag = "평가", write = !isFALSE(R$cell_write)))
  names(EVS) <- vapply(pre[["cells"]], function(z) z$code, character(1))
  bad <- names(EVS)[vapply(EVS, function(e) identical(e$status, "eval_error"), logical(1))]
  if (isFALSE(R$cell_write) && length(bad)) stop("[P2R03 평가] 저장된 칸 평가 없음(재판정은 쓰지 않는다): ", paste(bad, collapse = ","))
  rc_assert_eval_artifacts(EVS, RES, "P2R03 평가")
  .rc_perf_round(R, "cells", t0)
  cell_of <- function(eng, comp) Filter(function(z) identical(z$engine, eng) && identical(z$component, comp), pre[["cells"]])[[1]]
  dfr <- rc_deferred_cells(pre[["cells"]], RES)
  if (length(dfr)) stop("[P2R03 평가] 측정 연기 칸 — 재측정 뒤 평가: ", paste(vapply(dfr, function(z) z$code, ""), collapse = ","))
  worker <- !is.null(shard) && !isTRUE(merge)
  FP_EVAL <- if (worker) NA_character_ else rc_fingerprint(R$fingerprint$script, "equality")
  X <- list(root = root, res = RES, out = R$out, env = env, fs = FS, tau = TAU, ea = new.env(), meta = new.env(),
            minimal_copy = isTRUE(R$minimal_copy), raw_disk_cache = isTRUE(R$raw_disk_cache), perf = R$perf_env)
  ENGINES <- unique(vapply(pre[["cells"]], function(z) z$engine, character(1)))
  DEVS <- names(pre[["variants"]])
  FPG <- list(); jobs <- list()
  for (eng in ENGINES) {
    cr <- cell_of(eng, "RX0")
    codes <- unname(c(vapply(DEVS, function(dv) cell_of(eng, dv)$code, character(1)), vapply(DEVS, function(dv) cell_of(eng, paste0("L_", dv))$code, character(1)), cr$code))
    fps <- unname(unlist(lapply(codes, function(cd) c(rc_fp_of(RES, cd, "start"), rc_fp_of(RES, cd, "end")))))
    if (anyNA(fps) || length(unique(fps)) != 1L) stop(sprintf("[P2R03 평가] %s 묶음 데이터 지문 불일치 또는 부재 — 그 묶음을 재측정한 뒤 평가(rules.vintage_group)", eng))
    FPG[[eng]] <- list(measure = fps[1], eval_matches_measure = rc_fp_same(fps[1], FP_EVAL))
    for (dv in DEVS) {
      cl <- cell_of(eng, paste0("L_", dv)); cl$lag <- TRUE
      jobs[[length(jobs) + 1L]] <- list(eng = eng, dev = dv, cm = cell_of(eng, dv), cr = cr)
      jobs[[length(jobs) + 1L]] <- list(eng = eng, dev = dv, cm = cl, cr = cr)
    }
  }
  jcode <- vapply(jobs, function(j) j$cm$code, character(1))
  run_job <- function(j) rc_pair_run_safe(X, T, list(engine = j$eng, unit = j$dev, cm = j$cm, cr = j$cr, em = EVS[[j$cm$code]], er = EVS[[j$cr$code]]))
  pdir <- file.path(R$out, ".pairs"); t0 <- Sys.time()
  if (worker) {
    for (i in rc_shard_index(length(jobs), shard)) {
      tj <- Sys.time(); od <- run_job(jobs[[i]]); ek <- X$meta[[jcode[i]]]
      rc_pair_save(pdir, jcode[i], list(out = od, ek = ek, ea = if (!is.null(ek)) X$ea[[ek]] else NULL, seconds = as.numeric(difftime(Sys.time(), tj, units = "secs"))))
      cat(sprintf("[P2R03 짝] %s — %s · %.0f초\n", jcode[i], od$verdict %||% "-", as.numeric(difftime(Sys.time(), tj, units = "secs"))))
    }
    .rc_perf_round(R, paste0("pairs_shard_", shard), t0)
    return(invisible(TRUE))
  }
  if (isTRUE(merge)) {
    PR <- lapply(jcode, function(cd) rc_pair_load(pdir, cd))
    miss <- jcode[vapply(PR, is.null, logical(1))]
    if (length(miss)) stop("[P2R03 평가] 샤드 결과 없음: ", paste(miss, collapse = ","))
    res_l <- lapply(PR, `[[`, "out")
    vals <- list(); for (p in PR) if (!is.null(p$ek) && is.null(vals[[p$ek]])) vals[[p$ek]] <- p$ea
    X$ea <- rc_ea_replay(jcode, setNames(lapply(PR, `[[`, "ek"), jcode), vals)
  } else res_l <- lapply(jobs, run_job)
  .rc_perf_round(R, "pairs", t0)
  OUT <- list(); TBL <- list(); LAGT <- list()
  for (i in seq(1L, length(jobs), by = 2L)) {
    od <- res_l[[i]]; ol <- res_l[[i + 1L]]; cm <- jobs[[i]]$cm; cl <- jobs[[i + 1L]]$cm
    od$lag_tag <- p2r03_lag_tag(od, ol); od$lag_hold <- p2r03_lag_hold(od, ol); LAGT[[cm$code]] <- od$lag_tag
    TBL[[cm$code]] <- od$tbl; OUT[[cm$code]] <- od; OUT[[cl$code]] <- ol
  }
  TB <- rbindlist(TBL)
  rv <- rc_round_verdict(TB, "device")
  held <- unique(vapply(Filter(function(x) isTRUE(x$lag_hold), OUT), function(x) x$device, character(1)))
  validated <- setdiff(rv$both, held)
  xs_by <- setNames(lapply(validated, function(dv) Filter(function(x) identical(x$device, dv) && !isTRUE(x$lag), OUT)), validated)
  sel <- rc_select(xs_by)
  TOLC <- as.numeric(FS[["crisis_improve_min"]])
  CONTRAST <- lapply(setNames(ENGINES, ENGINES), function(eng) {                 # 대조 읽기(판정 아님) — 출처: P2R03 L698-708
    xs <- Filter(function(x) identical(x$engine, eng) && !isTRUE(x$lag) && isTRUE(x$tested), OUT)
    em <- Filter(function(z) !is.null(z) && nrow(as.data.table(z)), setNames(lapply(xs, function(x) x$record$expo_m), vapply(xs, function(x) x$device, "")))
    M <- if (length(em) >= 2L) Reduce(function(a, b) merge(a, b, by = "ym"), lapply(names(em), function(dv) setnames(copy(as.data.table(em[[dv]])), "e", dv))) else NULL
    wins <- rbindlist(lapply(xs, function(x) { pc <- as.data.table(x$rules$beta_deep$per_crisis %||% data.table())
      if (!nrow(pc)) NULL else data.table(device = x$device, crisis = pc$k, beats_beta_copy = pc$m < pc$r - TOLC) }), fill = TRUE)
    list(exposure_cor = if (!is.null(M) && ncol(M) >= 3L) round(stats::cor(as.matrix(M[, -1, with = FALSE]), use = "pairwise.complete.obs"), 3) else NULL,
         deep_wins = wins, readings = c("D3 vs D6 = 일정을 고정한 상태 대조(다변량 거리 vs 낙폭)", "D1 vs D6 = 같은 상태 변수의 처치 대조(순위형 축소 vs 스칼라 현금)",
                                         "D5 vs D6 = 추세 부호 vs 깊이", "D4 vs D3 = 학습된 꼬리 확률 vs 거리", "D7 vs D6 = 재진입 규칙 vs 깊이 비례 축소"))
  })
  excl <- lapply(rv$excluded, function(dv) list(device = dv, concentration = unique(vapply(Filter(function(x) identical(x$device, dv) && !isTRUE(x$lag), OUT),
                                                                                           function(x) as.character(x$concentration$status %||% "NA"), character(1)))))
  pcj <- fromJSON(R$precheck)
  VIS <- list(schema = "p2r03_evaluation_visible_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rc_md5(R$prereg_path),
              evaluate_md5 = R$evaluate_md5, tau_d = pre[["tau_d"]], cells = lapply(OUT, p2r03_visible_only), table = TB,
              verdict = rv$verdict, verdict_label = rv$label, n_judged = rv$n_judged, n_total = rv$n_total, pass_both = rv$both, pass_one = rv$one,
              excluded = excl, held_lag1_slow = held, validated = validated, selected = sel, lag_tags = LAGT, contrast = CONTRAST, engine_alpha = as.list(X$ea),
              fingerprint = list(eval = FP_EVAL, eval_record = rc_fingerprint(R$fingerprint$script, "record"), groups = FPG),
              precheck = list(ok = isTRUE(pcj$ok), at = pcj$at, prereg_md5 = pcj$prereg_md5))
  FULL <- list(schema = "p2r03_evaluation_full_v1", audience = RC_FULL_AUDIENCE, evaluated_at = VIS$evaluated_at, prereg_md5 = VIS$prereg_md5,
               cells = lapply(names(EVS), function(cd) list(code = cd, test = EVS[[cd]]$test, full = EVS[[cd]]$full,
                                                            alpha_test_window = OUT[[cd]]$alpha_test_window %||% NULL,
                                                            overlay_log_full_period = OUT[[cd]]$overlay %||% NULL)))
  ## 이 판의 보는 창 파일은 τ_D 가림 이전 판(P2R04 C-031 이전) — 누출은 막지 않고 기록한다(구판 그대로 재현 · 결함 분류 입력)
  leaks <- unique(c(dp_scan_dates(VIS[setdiff(names(VIS), c("evaluated_at", "precheck", "fingerprint"))], TAU)))
  dir.create(R$out, recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(FULL, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(R$out, "evaluation_full.json"), useBytes = TRUE)
  writeLines(toJSON(VIS, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(R$out, "evaluation_visible.json"), useBytes = TRUE)
  pj <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
  cat(sprintf("[P2R03 평가] 판정 %s · 두 엔진 통과 %s · 한 엔진 %s · 집중 제외 %s · 선택 %s · 보는 창 τ_D 이후 날짜 %d\n", rv$label, pj(rv$both), pj(rv$one),
              pj(rv$excluded), if (length(sel)) sel[[1]]$device else "-", length(leaks)))
  invisible(list(VIS = VIS, FULL = FULL, OUT = OUT, rv = rv, visible_leaks = leaks))
}
