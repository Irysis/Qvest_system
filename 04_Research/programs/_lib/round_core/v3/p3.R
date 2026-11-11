## round_core v3 · p3 — P3(구성 변형 × 엔진) 판정 템플릿 · 도우미 · 라운드 판정
##   출처 = P3R03 evaluate.R(등록 c7166d2ca · 파일 53bce362d · 543줄)의 결정 판정 a~e · S · 알파 비열등 · β 짝(중앙값형) · 기전(선택) 방어 ·
##   집중 · 이력 탈락(선택 교락) · 기록 · 후보 꼬리표. 공용 단계(상태 · 실효 시작 · 창 · 엔진 알파 · 위기 짝)는 pair.R 을 쓴다. 함수 본문은 같은 동작.

## ── 순수 도우미 ────────────────────────────────────────────────────────────────────
## β 짝 판정(중앙값형) — 출처: P3R03 L146-152 — k 비유한 · 사본 · 패킷 실패 · 판정 입력 NA = unmeasured · k ≥ 1 = not_needed · 그 밖 = ok(중앙값이 사본보다 낮고 깊은 위기 과반)
rc_p3_beta_verdict <- function(k, dcm, dcb, deep_share, maj, err = NULL) {
  if (!length(k) || !is.finite(k)) return(list(status = "unmeasured", beats = NA, why = "k 비유한"))
  if (k >= 1) return(list(status = "not_needed", beats = TRUE))
  if (!is.null(err)) return(list(status = "unmeasured", beats = NA, why = paste("β 사본 · 패킷 실패:", err)))
  if (!length(dcb) || !is.finite(dcb) || !length(deep_share) || !is.finite(deep_share)) return(list(status = "unmeasured", beats = NA, why = "β 사본 판정 입력 NA"))
  list(status = "ok", beats = (dcm < dcb) && (deep_share > maj))
}
## 셀 로그 — 엔진 커버리지 줄 · 방법 진단 줄('[<tag>] d=… n=… maxw=… effn=…') · 래퍼 폴백 줄 — 출처: P3R03 L154-173
rc_p3_parse_cell_log <- function(lines, tag) {
  cov <- grep("^\\[rf_cell_engine\\] catalog ", lines, value = TRUE)
  cv <- if (length(cov)) {
    s <- cov[length(cov)]
    num <- function(p) suppressWarnings(as.numeric(sub(p, "\\1", s)))
    list(diff = num(".*차별화 ([0-9]+).*"), ew_fallback = num(".*EW폴백 ([0-9]+).*"),
         n_hit = num(".*선정일 ([0-9]+)/[0-9]+.*"), n_try = num(".*선정일 [0-9]+/([0-9]+).*"))
  } else NULL
  if (!is.null(cv)) cv$carry_days <- cv$n_try - cv$n_hit
  dl <- grep(sprintf("^\\[%s\\] d=", tag), lines, value = TRUE)
  D <- if (length(dl)) rbindlist(lapply(dl, function(s) {
    s2 <- sub(sprintf("^\\[%s\\]", tag), "", s)
    g <- function(k) if (grepl(paste0(" ", k, "="), s2, fixed = TRUE)) sub(paste0(".* ", k, "=([^ ]+).*"), "\\1", s2) else NA_character_
    data.table(d = as.Date(g("d")), n = suppressWarnings(as.integer(g("n"))), maxw = suppressWarnings(as.numeric(g("maxw"))),
               effn = suppressWarnings(as.numeric(g("effn"))))
  })) else data.table(d = as.Date(character(0)), n = integer(0), maxw = numeric(0), effn = numeric(0))
  fb <- grep("어댑터 실패", lines, fixed = TRUE, value = TRUE)
  list(coverage = cv, diag = D, n_method_fallback = length(fb),
       fallback_by_reason = list(under_3_assets = sum(grepl("자산 3종 미만", fb, fixed = TRUE)), other = sum(!grepl("자산 3종 미만", fb, fixed = TRUE))))
}
## 처치 전달률 — 출처: P3R03 L175-178 — 방법 해를 낸 고유 신호일 / 선정 신호일(n_try) · 커버리지 줄 없음 = NA(미시험)
rc_p3_delivery <- function(pl) {
  if (is.null(pl$coverage) || !is.finite(pl$coverage$n_try) || pl$coverage$n_try <= 0) return(NA_real_)
  length(unique(pl$diag$d[!is.na(pl$diag$d)])) / pl$coverage$n_try
}
## 위기 안 집행일 — 출처: P3R03 L179-187
rc_p3_crisis_execs <- function(exec_dates, crises) {
  ex <- sort(unique(as.Date(exec_dates))); cr <- .rc_rows_dt(crises)
  if (!length(ex) || !nrow(cr)) return(as.Date(character(0)))
  out <- unlist(lapply(seq_len(nrow(cr)), function(i) {
    p0 <- as.Date(as.character(cr$peak_date[i])); t0 <- as.Date(as.character(cr$trough_date[i]))
    c(suppressWarnings(max(ex[ex <= p0])), ex[ex > p0 & ex <= t0])
  }))
  out <- as.Date(out, origin = "1970-01-01"); sort(unique(out[is.finite(out)]))
}
## 선택 항 짝 비교 — 출처: P3R03 L188-195
rc_p3_selection_vs_ref <- function(ex_m, ex_r) {
  m <- .rc_rows_dt(ex_m); r <- .rc_rows_dt(ex_r)
  need <- c("peak_date", "trough_date", "selection_sum")
  if (!nrow(m) || !nrow(r) || !all(need %in% names(m)) || !all(need %in% names(r))) return(list(n_pair = 0L, share = NA_real_))
  m[, k := .rc_key(m)]; r[, k := .rc_key(r)]
  J <- merge(m[, .(k, sm = as.numeric(selection_sum))], r[, .(k, sr = as.numeric(selection_sum))], by = "k")[is.finite(sm) & is.finite(sr)]
  list(n_pair = nrow(J), n_better = sum(J$sm - J$sr > 0), share = if (nrow(J)) mean(J$sm - J$sr > 0) else NA_real_, per_crisis = J)
}
## 이력 탈락 — 출처: P3R03 L196-202
rc_p3_history_drops <- function(D, H_rx0) {
  if (!nrow(D) || !nrow(H_rx0)) return(data.table())
  sel <- H_rx0[is.finite(w) & w > 0, .(n_sel = uniqueN(ticker)), by = date][order(date)]
  out <- D[, { ex <- sel[date > d][1]; list(exec = ex$date, n_sel = ex$n_sel, n = n) }, by = d]
  out[, drops := pmax(n_sel - n, 0L)][, drop_share := drops / n_sel]
  out[]
}
## 같은 선정 집합(방법판) — 출처: P3R03 L205-219 — 방법 해를 낸 신호일마다 그 뒤 첫 RX0 집행일에서 변형 보유 ⊆ RX0 보유
rc_p3_subset_check <- function(D, H_var, H_rx0) {
  dd <- sort(unique(as.Date(D$d[!is.na(D$d)])))
  hv <- H_var[is.finite(w) & w > 0]; hr <- H_rx0[is.finite(w) & w > 0]
  if (!length(dd) || !nrow(hv) || !nrow(hr)) return(list(status = "unmeasured", n_checked = 0L, n_violate = NA_integer_, n_missing = NA_integer_))
  ex <- sort(unique(hr$date)); idx <- findInterval(as.numeric(dd), as.numeric(ex)) + 1L
  xe <- ex[idx[idx <= length(ex)]]
  viol <- character(0); miss <- character(0)
  for (i in seq_along(xe)) {
    tv <- unique(hv[date == xe[i], ticker]); tr <- unique(hr[date == xe[i], ticker])
    if (!length(tv)) { miss <- c(miss, format(xe[i])); next }
    if (!all(tv %in% tr)) viol <- c(viol, format(xe[i]))
  }
  list(status = "ok", n_checked = length(xe), n_violate = length(viol), n_missing = length(miss), violate_dates = utils::head(viol, 10L),
       missing_dates = utils::head(miss, 10L))
}
## 후보 꼬리표 — 출처: P3R03 L240-247
rc_p3_candidate_tags <- function(xs) {
  stt <- function(f) vapply(xs, function(x) as.character(f(x) %||% "unmeasured")[1], character(1))
  c(if (any(stt(function(x) x$beta_matched$status) == "unmeasured")) "β 대조 미측정",
    if (any(vapply(xs, function(x) identical(x$beta_matched$beats, FALSE), logical(1)))) "노출(β) 방어",
    if (!all(vapply(xs, function(x) isTRUE(x$attribution$mechanism), logical(1)))) "기전(선택) 방어 미확인",
    if (any(vapply(xs, function(x) isTRUE(x$history_drop_tag), logical(1)))) "선택 교락(이력 탈락)",
    if (any(stt(function(x) x$history_drop_status) == "unmeasured")) "선택 교락 미측정")
}
## 이력 탈락 꼬리표 — 출처: P3R03 L274-277 — 판독할 위기 집행 행 없음 · 탈락 몫 전부 비유한 = 미측정
rc_p3_history_drop_eval <- function(hd_cr, drop_tag_share, has_holdings = TRUE) {
  if (!isTRUE(has_holdings) || is.null(hd_cr) || !nrow(hd_cr) || !any(is.finite(hd_cr$drop_share))) return(list(status = "unmeasured", tag = FALSE))
  list(status = "ok", tag = mean(hd_cr$drop_share, na.rm = TRUE) > drop_tag_share)
}

## ── P3 판정 1칸 단계(출처: P3R03 p3_eval_pair L315-459 — 같은 순서 · 같은 필드) ─────────────────────────
rc_p3_init <- function(ctx, opts) list(engine = ctx$engine, method = ctx$unit, cell = ctx$cm$code, rx0 = ctx$cr$code, status = ctx$em$status %||% NA, status_rx0 = ctx$er$status %||% NA)
rc_p3_untested <- function(out, why) {
  out$tested <- FALSE; out$verdict <- "untested"; out$why <- why
  out$tbl <- data.table(engine = out$engine, method = out$method, tested = FALSE, pass = FALSE, excluded = FALSE)
  out
}
## ③ 처치 전달률 — P3R03 L322-326
rc_p3_st_delivery <- function(S) {
  X <- S$X; FS <- X$fs; cm <- S$ctx$cm; opts <- S$opts
  lg <- opts[["log"]] %||% file.path(X$res, paste0(cm$code, ".log"))
  L <- if (file.exists(lg)) readLines(lg, warn = FALSE, encoding = "UTF-8") else character(0)
  S$pl <- rc_p3_parse_cell_log(L, opts[["tag"]] %||% S$T$cfg[["methods"]][[S$ctx$unit]]$tag); dlv <- rc_p3_delivery(S$pl); S$out$delivery <- dlv
  if (!is.finite(dlv) || dlv < as.numeric(FS[["delivery_min"]])) return(sprintf("처치 전달률 %s < %s", format(dlv), FS[["delivery_min"]]))
  NULL
}
## 같은 선정 집합(방법 해를 낸 보는 창 신호일) — P3R03 L334-339
rc_p3_st_subset <- function(S) {
  FS <- S$X$fs; TAU <- S$X$tau
  S$Hm <- tryCatch(rc_read_holdings(S$dm), error = function(e) data.table()); S$Hr <- tryCatch(rc_read_holdings(S$dr), error = function(e) data.table())
  ss <- rc_p3_subset_check(S$pl$diag[!is.na(d) & d <= TAU], S$Hm, S$Hr); S$out$same_selection <- ss
  if (!identical(ss$status, "ok") || !identical(ss$n_violate, 0L) || ss$n_missing > (1 - as.numeric(FS[["delivery_min"]])) * ss$n_checked)
    return(sprintf("선정 집합 %s — 변형 보유 ⊄ RX0 보유 %s · 변형 집행 결측 %s / %s 집행일", ss$status, format(ss$n_violate), format(ss$n_missing), format(ss$n_checked)))
  NULL
}
## 판정 입력 — P3R03 L364-385(중앙값 · 사이클 · 경로 · S 입력 · 알파 — NA = 미시험)
rc_p3_st_inputs <- function(S) {
  X <- S$X; FS <- X$fs; g <- rc_getf; PM <- S$PM; PRX <- S$PRX
  S$dcm <- g(PM, "behavior.summary.crisis_cum_capture_median"); S$dcr <- g(PRX, "behavior.summary.crisis_cum_capture_median")
  S$ucm <- g(PM, "behavior.summary.bull_up_capture_median"); S$ucr <- g(PRX, "behavior.summary.bull_up_capture_median")
  S$cyc <- rc_cycle_compound(PM$behavior$bull_phases %||% list(), S$crm, PRX$behavior$bull_phases %||% list(), S$crr)
  S$mvb <- c(g(PM, "behavior.summary.mdd_vs_bench"), g(PRX, "behavior.summary.mdd_vs_bench"))
  S$cdr <- c(g(PM, "behavior.stats.cdar"), g(PRX, "behavior.stats.cdar"))
  S$cmv <- g(PM, "performance.strategy.calmar"); S$crv <- g(PRX, "performance.strategy.calmar")
  S$ptm <- g(PM, "performance.strategy.port_t"); S$ptr <- g(PRX, "performance.strategy.port_t")
  S$pa <- tryCatch(rc_pair_alpha(X$env$E, S$am, S$ar, X$tau),
                   error = function(e) list(visible = list(d_alpha = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e)), test = NULL))
  S$aok <- rc_alpha_ok(S$pa$visible, as.numeric(FS[["alpha_t_floor"]]), S$ea$alpha_ann, as.numeric(FS[["alpha_margin_frac"]]))
  inp <- c(dc = S$dcm, dc_rx0 = S$dcr, uc = S$ucm, b = S$maj$share, d = S$dmj$share, cycle = S$cyc$share, mdd_vs_bench = S$mvb, cdar = S$cdr,
           calmar = S$cmv, calmar_rx0 = S$crv, port_t = S$ptm, port_t_rx0 = S$ptr)
  if (any(!is.finite(inp)) || is.na(S$aok)) {
    S$out$inputs <- c(as.list(inp), list(alpha_t = S$pa$visible$t, engine_alpha = S$ea$alpha_ann, cycle_pairs = S$cyc$n_pair, cycle_unpaired = S$cyc$unpaired_crises))
    return(sprintf("판정 입력 NA(%s)", paste(c(names(inp)[!is.finite(inp)], if (is.na(S$aok)) "alpha"), collapse = ",")))
  }
  NULL
}
## 결정 판정 a~e · S 비열등 · 알파 비열등 — P3R03 L386-403
rc_p3_st_decisive <- function(S) {
  X <- S$X; FS <- X$fs; MAJ <- S$MAJ
  a <- S$dcm < S$dcr
  b <- S$maj$share > MAJ
  cc <- S$ucm >= as.numeric(FS[["uc_floor"]]) && S$cyc$share > MAJ
  d <- S$dmj$share > MAJ
  e <- S$mvb[1] <= S$mvb[2] && S$cdr[1] <= S$cdr[2]
  Sm <- rc_S(S$cmv, S$ptm, FS); Sr <- rc_S(S$crv, S$ptr, FS)
  ni <- if (Sr > 0) Sm >= Sr - as.numeric(FS[["tie_eps"]]) else S$cmv >= S$crv
  maj <- S$maj; dmj <- S$dmj; cyc <- S$cyc
  S$out$decisive <- list(a_median = list(variant = S$dcm, rx0 = S$dcr, ok = a), b_majority = c(maj[setdiff(names(maj), "per_crisis")], list(ok = b)),
                         c_participation = list(variant = S$ucm, rx0 = S$ucr, ratio = S$ucm / S$ucr, floor = FS[["uc_floor"]], cycle = cyc[setdiff(names(cyc), "per_cycle")], ok = cc),
                         d_deep = c(dmj[setdiff(names(dmj), "per_crisis")], list(deep_keys = S$deep, ok = d)),
                         e_path = list(mdd_vs_bench = S$mvb, cdar = S$cdr, ok = e), ok = a && b && cc && d && e)
  S$out$mild_only <- a && b && !(d && e)
  S$out$non_inferiority <- list(S = Sm, S_rx0 = Sr, calmar = S$cmv, calmar_rx0 = S$crv, port_t = S$ptm, port_t_rx0 = S$ptr,
                                basis = if (Sr > 0) "S_vis − tie_eps" else "Calmar(S_rx0 = 0)", ok = isTRUE(ni))
  pa <- S$pa
  se <- if (is.finite(pa$visible$t) && pa$visible$t != 0) pa$visible$d_alpha / pa$visible$t else NA_real_
  mg <- as.numeric(FS[["alpha_margin_frac"]]) * max(S$ea$alpha_ann, 0)
  S$out$alpha_non_loss <- list(d_alpha = pa$visible$d_alpha, t = pa$visible$t, se = se, n = pa$visible$n, engine_alpha = S$ea, t_floor = FS[["alpha_t_floor"]],
                               margin_frac = FS[["alpha_margin_frac"]], margin = mg, margin_over_se = if (is.finite(se) && se > 0) mg / se else NA_real_, ok = isTRUE(S$aok))
  NULL
}
## β 짝 대조(중앙값형 · 철학 C-003) — P3R03 L404-423(k = 변형 β / RX0 β · 상승장 β 비 기록)
rc_p3_st_beta <- function(S) {
  X <- S$X; g <- rc_getf; PM <- S$PM; PRX <- S$PRX; cfg <- S$T$cfg; cm <- S$ctx$cm; cr <- S$ctx$cr; tol <- S$tol
  bm <- g(PM, "behavior.stats.beta"); br0 <- g(PRX, "behavior.stats.beta")
  bu <- c(g(PM, "behavior.stats.beta_up"), g(PRX, "behavior.stats.beta_up")); bd <- c(g(PM, "behavior.stats.beta_down"), g(PRX, "behavior.stats.beta_down"))
  fk <- S$opts[["force_k"]]
  k <- if (!is.null(fk)) as.numeric(fk) else if (is.finite(bm) && is.finite(br0) && br0 > 0) bm / br0 else NA_real_
  bmc <- list(k = k, k_forced = !is.null(fk), k_up = if (all(is.finite(bu)) && bu[2] > 0) bu[1] / bu[2] else NA_real_,
              beta = list(variant = bm, rx0 = br0, down = bd, up = bu))
  dcb <- NA_real_; dsh <- NA_real_; berr <- NULL
  if (is.finite(k) && k < 1) {
    rb <- tryCatch({
      base <- file.path(X$out, cm$code, S$W$sub); bdir <- file.path(base, "rx0_beta_scaled")
      rc_beta_scaled_copy(S$ar, bdir, k, mark = isTRUE(cfg[["mark_full"]]), minimal = isTRUE(X[["minimal_copy"]]), errtag = cfg[["beta_errtag"]] %||% "p3_beta")
      PB <- rc_pk_build(X, .rc_cell_spec(cr), bdir, file.path(base, "visible_rx0_beta"))
      list(dcb = g(PB, "behavior.summary.crisis_cum_capture_median"), dmb = rc_crisis_majority(S$crm, PB$behavior$crises %||% list(), tol, metric = "dd_capture", subset = S$deep))
    }, error = function(e) list(err = conditionMessage(e)))
    if (!is.null(rb$err)) berr <- rb$err else {
      dcb <- rb$dcb; dsh <- if (rb$dmb$n_pair >= 2L) rb$dmb$share else NA_real_
      bmc$scaled <- list(dc_median = dcb, deep = rb$dmb[setdiff(names(rb$dmb), "per_crisis")])
    }
  }
  S$out$beta_matched <- c(bmc, rc_p3_beta_verdict(k, S$dcm, dcb, dsh, S$MAJ, berr))
  NULL
}
## 기전(선택) 방어 · 집중 · 이력 탈락 · 기록 · 판정어 — P3R03 L424-458
rc_p3_st_records <- function(S) {
  X <- S$X; FS <- X$fs; g <- rc_getf; PM <- S$PM; PRX <- S$PRX; MAJ <- S$MAJ
  sv <- rc_p3_selection_vs_ref(PM$exposure$crises %||% list(), PRX$exposure$crises %||% list())
  S$out$attribution <- list(label = as.character(PM$controls$attribution$label %||% NA)[1], selection_vs_rx0 = sv[setdiff(names(sv), "per_crisis")])
  S$out$attribution$mechanism <- identical(S$out$attribution$label, "selection_defense") && is.finite(sv$share) && sv$share > MAJ
  deep_peaks <- vapply(strsplit(S$deep, " "), `[`, "", 1)
  tl <- rc_top_loss(PM$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS[["single_name_loss_floor"]]))
  tl0 <- rc_top_loss(PRX$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS[["single_name_loss_floor"]]))
  conc <- tryCatch(rc_concentration(S$am, X$tau), error = function(e) list(visible = list(error = conditionMessage(e))))
  cst <- rc_conc_status(tl); S$cst <- cst
  S$out$concentration <- list(status = cst, visible = conc$visible, eff_n_mean = c(g(PM, "profile.eff_n_mean"), g(PRX, "profile.eff_n_mean")),
                              top_loss = tl[setdiff(names(tl), "per_crisis")], top_loss_rx0 = tl0[setdiff(names(tl0), "per_crisis")], per_crisis = tl$per_crisis,
                              concentration_loss_tag = identical(cst, "breach"), unmeasured_tag = identical(cst, "unmeasured"))
  Hr <- S$Hr; pl <- S$pl
  hd <- if (nrow(Hr)) rc_p3_history_drops(pl$diag, Hr) else data.table()
  cx <- if (nrow(hd)) rc_p3_crisis_execs(hd$exec, S$crr) else as.Date(character(0))
  hd_cr <- if (nrow(hd)) hd[exec %in% cx] else hd
  hde <- rc_p3_history_drop_eval(hd_cr, as.numeric(FS[["drop_tag_share"]]), has_holdings = nrow(Hr) > 0L)
  S$out$history_drop_status <- hde$status; S$out$history_drop_tag <- hde$tag
  ann <- .rc_rows_dt(PM$performance$annual %||% list())
  rec <- tryCatch({ R0 <- .rc_rows_dt(S$crm); as.list(R0[, intersect(c("peak_date", "st_recovery_obs", "st_recovery_censored"), names(R0)), with = FALSE]) },
                  error = function(e) NULL)
  S$out$record <- list(coverage = pl$coverage, method_fallback_lines = pl$n_method_fallback, fallback_by_reason = pl$fallback_by_reason,
                       diag = list(n_days = nrow(pl$diag), effn_median = stats::median(pl$diag$effn, na.rm = TRUE), maxw_max = suppressWarnings(max(pl$diag$maxw, na.rm = TRUE)),
                                   n_le4 = sum(pl$diag$effn <= 4, na.rm = TRUE)),
                       history_drops = if (nrow(hd)) list(mean = mean(hd$drops), max = max(hd$drops), crisis_mean_share = if (nrow(hd_cr)) mean(hd_cr$drop_share, na.rm = TRUE) else NA_real_) else NULL,
                       recovery = rec, rolling = PM$behavior$rolling,
                       negative_years = if (nrow(ann) && "strategy" %in% names(ann)) sum(as.numeric(ann$strategy) < 0, na.rm = TRUE) else NA_integer_,
                       size_decile = "exposure.by_size_decile(패킷) — 유동성 3분위는 미측정", turnover_annual = list(variant = g(PM, "profile.turnover_annual"), rx0 = g(PRX, "profile.turnover_annual")),
                       per_crisis = S$maj$per_crisis, per_cycle = S$cyc$per_cycle, alpha_test_window = S$pa$test)
  NULL
}
rc_p3_st_verdict <- function(S) {
  out <- S$out
  S$out$pass <- isTRUE(out$decisive$ok) && isTRUE(out$non_inferiority$ok) && isTRUE(out$alpha_non_loss$ok)
  S$out$verdict <- if (S$out$pass) "pass" else if (isTRUE(out$mild_only)) "mild_only" else if (isTRUE(out$decisive$ok)) "decisive_but_inferior" else "not_decisive"
  S$out$tested <- TRUE
  S$out$tbl <- data.table(engine = S$ctx$engine, method = S$ctx$unit, tested = TRUE, pass = S$out$pass, excluded = !identical(S$cst, "clear"))
  NULL
}
## 템플릿 — P3R03 판 기본값(방법 표 · 판정어는 사양 · 라운드 고유 훅이 덮는다)
rc_p3_template <- function(cfg = list(), hooks = list()) {
  dc <- list(methods = list(), mark_full = FALSE, trim_errtag = "p3_trim", beta_errtag = "p3_beta", unit = "method")
  cfg <- rc_merge_shallow(dc, cfg)
  dh <- list(init = rc_p3_init, untested = rc_p3_untested, treatment = list(rc_p3_st_delivery), selection_set = list(rc_p3_st_subset),
             records = list(rc_p3_st_records), verdict = list(rc_p3_st_verdict))
  h <- rc_merge_shallow(dh, hooks)
  stages <- h[["stages"]] %||% c(list(rc_st_consts, rc_st_status), h[["treatment"]], list(rc_st_effective_start_auth), h[["selection_set"]],
                            list(rc_st_window_packets, rc_st_engine_alpha, rc_st_crisis_pairs, rc_p3_st_inputs, rc_p3_st_decisive, rc_p3_st_beta), h[["records"]], h[["verdict"]])
  list(name = "p3_construction", cfg = cfg, hooks = h, init = h[["init"]], untested = h[["untested"]], stages = stages)
}

## 구 칸 평가 기록(round_kit rk_eval_cell 단일 eval.json) 읽기 — 출처: round_kit.R L62-104(캐시 = results/<code>/eval.json 이 있으면 그대로)
##   write = FALSE(재판정) — 저장분이 없으면 계산하지 않고 멈춘다(라운드 결과 폴더 무수정)
rc_eval_cell_single_legacy <- function(res_dir, cell) {
  ej <- file.path(res_dir, cell[["code"]], "eval.json")
  if (file.exists(ej)) return(fromJSON(ej, simplifyVector = FALSE))
  rj <- file.path(res_dir, paste0(cell[["code"]], ".json"))
  if (!file.exists(rj)) return(list(code = cell[["code"]], status = "not_measured"))
  r <- fromJSON(rj, simplifyVector = FALSE)
  if (!isTRUE(r$ok)) return(list(code = cell[["code"]], status = "measure_failed", err = r$err %||% NA))
  stop("저장된 칸 평가(eval.json)가 없다 — 재판정은 칸 평가를 새로 쓰지 않는다: ", cell[["code"]])
}

## ── P3 라운드 판정(출처: P3R03 본 실행 L467-542) ──────────────────────────────────────────────
##   R = list(round_id · program · pre · prereg_path · root · res · out · precheck · fingerprint · evaluate_md5 · schema · tag · cell_eval(function(cell) → 칸 평가))
rc_p3_round <- function(R, T, shard = NULL, merge = FALSE) {
  pre <- R$pre; root <- R$root; RES <- R$res; tag <- R$tag %||% "P3"
  E <- rc_deps(root)
  if (isTRUE(R$memo)) { rc_memo_install(E); if (isTRUE(R$mc8_memo)) rc_mc_memo_install(E, root) }
  if (!is.null(R$program)) {
    reg <- pr_load(root); rr <- Filter(function(r) identical(r$round_id, R$round_id), pr_get(reg, R$program)$rounds)
    if (!length(rr) || !identical(rr[[1]]$prereg_md5, rc_md5(R$prereg_path))) stop("[", tag, "] 사전등록 md5 불일치(R2)")
  }
  BCFG <- file.path(root, pre[["behavior_card_cfg"]][["path"]])
  if (!identical(rc_md5(BCFG), pre[["behavior_card_cfg"]][["md5"]])) stop("[", tag, "] 행동 카드 설정 사본 변경")
  if (isTRUE(R$check_pins)) { pin <- rc_legacy_pin_mismatches(pre, root)
    if (length(pin)) stop("[", tag, "] 핀 불일치 — 평가하지 않는다:\n", paste0("  · ", pin, collapse = "\n")) }
  if (!is.null(R$precheck) && (!file.exists(R$precheck) || !isTRUE(fromJSON(R$precheck)$ok))) stop("[", tag, "] precheck 통과 기록이 없다 — 측정 조건 미확인")
  TAU <- as.Date(pre[["tau_d"]]); FS <- pre[["final_selection_rule"]]
  env <- new.env(); env$E <- E; env$BCFG_L <- E$bc_cfg(root, path = BCFG); env$raw <- NULL
  t0 <- Sys.time()
  EVS <- lapply(pre[["cells"]], R$cell_eval); names(EVS) <- vapply(pre[["cells"]], function(z) z$code, character(1))
  rc_assert_eval_artifacts(EVS, RES, paste(tag, "평가"))
  .rc_perf_round(R, "cells", t0)
  cell_of <- function(eng, comp) Filter(function(z) identical(z$engine, eng) && identical(z$component, comp), pre[["cells"]])[[1]]
  dfr <- rc_deferred_cells(pre[["cells"]], RES)
  if (length(dfr)) stop("[", tag, "] 측정 연기 칸 — 재측정 뒤 평가: ", paste(vapply(dfr, function(z) z$code, ""), collapse = ","))
  worker <- !is.null(shard) && !isTRUE(merge)
  FP_EVAL <- if (worker) NA_character_ else rc_fingerprint(R$fingerprint$script, "equality", R$fingerprint$args %||% character(0))
  X <- list(root = root, res = RES, out = R$out, env = env, fs = FS, tau = TAU, ea = new.env(), meta = new.env(),
            minimal_copy = isTRUE(R$minimal_copy), raw_disk_cache = isTRUE(R$raw_disk_cache), perf = R$perf_env)
  ENGINES <- unique(vapply(pre[["cells"]], function(z) z$engine, character(1)))
  METHODS <- names(pre[["variants"]])
  FPG <- list(); jobs <- list()
  for (eng in ENGINES) {
    cr <- cell_of(eng, "RX0")
    codes <- unname(c(vapply(METHODS, function(m) cell_of(eng, m)$code, character(1)), cr$code))
    fps <- unname(unlist(lapply(codes, function(cd) c(rc_fp_of(RES, cd, "start"), rc_fp_of(RES, cd, "end")))))
    if (anyNA(fps) || length(unique(fps)) != 1L) stop(sprintf("[%s] %s 묶음 데이터 지문 불일치 또는 부재 — 그 묶음을 재측정한 뒤 평가(rules.vintage_group)", tag, eng))
    FPG[[eng]] <- list(measure = fps[1], eval_matches_measure = rc_fp_same(fps[1], FP_EVAL))   # ★P3R03 구판은 이름 붙은 벡터 비교로 늘 거짓(결함 — 이름 지운 비교)
    for (mth in METHODS) jobs[[length(jobs) + 1L]] <- list(eng = eng, mth = mth, cm = cell_of(eng, mth), cr = cr)
  }
  jcode <- vapply(jobs, function(j) j$cm$code, character(1))
  run_job <- function(j) rc_pair_run_safe(X, T, list(engine = j$eng, unit = j$mth, cm = j$cm, cr = j$cr, em = EVS[[j$cm$code]], er = EVS[[j$cr$code]]))
  pdir <- file.path(R$out, ".pairs"); t0 <- Sys.time()
  if (worker) {
    for (i in rc_shard_index(length(jobs), shard)) {
      tj <- Sys.time(); od <- run_job(jobs[[i]]); ek <- X$meta[[jcode[i]]]
      rc_pair_save(pdir, jcode[i], list(out = od, ek = ek, ea = if (!is.null(ek)) X$ea[[ek]] else NULL, seconds = as.numeric(difftime(Sys.time(), tj, units = "secs"))))
      cat(sprintf("[%s 짝] %s — %s · %.0f초\n", tag, jcode[i], od$verdict %||% "-", as.numeric(difftime(Sys.time(), tj, units = "secs"))))
    }
    .rc_perf_round(R, paste0("pairs_shard_", shard), t0)
    return(invisible(TRUE))
  }
  if (isTRUE(merge)) {
    PR <- lapply(jcode, function(cd) rc_pair_load(pdir, cd))
    miss <- jcode[vapply(PR, is.null, logical(1))]
    if (length(miss)) stop("[", tag, "] 샤드 결과 없음: ", paste(miss, collapse = ","))
    res_l <- lapply(PR, `[[`, "out")
    vals <- list(); for (p in PR) if (!is.null(p$ek) && is.null(vals[[p$ek]])) vals[[p$ek]] <- p$ea
    X$ea <- rc_ea_replay(jcode, setNames(lapply(PR, `[[`, "ek"), jcode), vals)
  } else res_l <- lapply(jobs, run_job)
  .rc_perf_round(R, "pairs", t0)
  OUT <- list(); TBL <- list()
  for (i in seq_along(jobs)) { o <- res_l[[i]]; TBL[[jcode[i]]] <- o$tbl; o$tbl <- NULL; OUT[[jcode[i]]] <- o }
  TB <- rbindlist(TBL)
  rv <- rc_round_verdict(TB, "method")
  sel <- lapply(rv$both, function(m) {
    xs <- Filter(function(x) identical(x$method, m), OUT); tags <- rc_p3_candidate_tags(xs)
    list(method = m, catalog_id = T$cfg[["methods"]][[m]]$catalog, tag = if (length(tags)) paste0("구성 부품 후보(", paste(tags, collapse = " · "), ")") else "구성 부품 후보",
         dc_gain_mean = mean(vapply(xs, function(x) x$decisive$a_median$rx0 - x$decisive$a_median$variant, numeric(1))))
  })
  if (length(sel)) sel <- sel[order(-vapply(sel, `[[`, numeric(1), "dc_gain_mean"))]
  excl <- lapply(rv$excluded, function(m) list(method = m, concentration = unique(vapply(Filter(function(x) identical(x$method, m), OUT),
                                                                                           function(x) as.character(x$concentration$status %||% "NA"), character(1)))))
  res <- list(schema = R$schema %||% "round_core_p3_evaluation_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rc_md5(R$prereg_path),
              evaluate_md5 = R$evaluate_md5 %||% NA_character_, cells = OUT, table = TB, verdict = rv$verdict, verdict_label = rv$label,
              n_judged = rv$n_judged, n_total = rv$n_total, pass_both = rv$both, pass_one = rv$one, excluded = excl, selected = sel,
              engine_alpha = as.list(X$ea), fingerprint = list(eval = FP_EVAL, eval_record = rc_fingerprint(R$fingerprint$script, "record", R$fingerprint$record_args %||% character(0)), groups = FPG),
              precheck = if (!is.null(R$precheck)) fromJSON(R$precheck, simplifyVector = FALSE) else NULL)
  dir.create(R$out, recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(R$out, R$out_file %||% "evaluation.json"), useBytes = TRUE)
  if (!isFALSE(R$log)) {
    pj <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
    for (x in OUT) cat(sprintf("[%s 평가] %s %s — %s%s · 결정 %s · S %s · 알파 %s · β짝 %s · 집중 %s\n", tag, x$engine, x$method, x$verdict,
                               if (!isTRUE(x$tested)) paste0("(", .rc_redact_chr(x$why %||% "-", TAU), ")") else "", isTRUE(x$decisive$ok), isTRUE(x$non_inferiority$ok),
                               isTRUE(x$alpha_non_loss$ok), x$beta_matched$status %||% "-", x$concentration$status %||% "-"))
    cat(sprintf("[%s 평가] 판정 %s · 두 엔진 통과 %s · 한 엔진 %s · 집중 제외 %s\n", tag, rv$label, pj(rv$both), pj(rv$one), pj(rv$excluded)))
  }
  invisible(res)
}

## ── 코어 사양 라운드(round_spec.json · template = p3_construction) — driver evaluate 가 부른다 ─────────────────────────
##   사양이 쓰는 것: cells(code · engine · role · component · spec) · params · methods(방법 → catalog · tag) · rules · behavior_card_cfg · ext(RC_EXT_CFG · RC_EXT_HOOKS)
##   P3 사전등록 결정 규칙(a~e · S · 알파)은 템플릿 단계가 판정한다 · 칸 평가 = 보는 창 / 사람 쪽 분리판(키 캐시) · 작업 사본 = 표식 + 최소 파일
rc_p3_evaluate <- function(spec, pre, root, round_dir, P, shard = NULL, merge = FALSE) {
  ext <- rc_spec_ext(spec, root)
  T <- rc_p3_template(cfg = rc_merge_shallow(list(methods = spec[["methods"]] %||% list(), mark_full = TRUE), ext[["cfg"]]), hooks = ext[["hooks"]])
  FS <- rc_spec_params(spec, root)
  pl <- list(cells = rc_spec_cells_legacy(spec, root), final_selection_rule = FS, tau_d = spec[["tau_d"]], behavior_card_cfg = pre[["behavior_card_cfg"]],
             variants = setNames(vector("list", length(spec[["methods"]])), names(spec[["methods"]])))
  env <- rc_eval_env(root, spec[["behavior_card_cfg"]]); env$mc8_cache <- TRUE; tau <- as.Date(spec[["tau_d"]])
  R <- list(round_id = spec[["round_id"]], tag = rc_round_tag(spec[["round_id"]]), pre = pl, prereg_path = P$prereg, root = root, res = P$results, out = P$results,
            precheck = NULL, fingerprint = list(script = file.path(RC_DIR, "fingerprint.sh")), evaluate_md5 = rc_core_manifest()$manifest_md5,
            schema = "round_core_p3_evaluation_v1", out_file = "evaluation_full.json", memo = TRUE, mc8_memo = TRUE, minimal_copy = TRUE, perf_env = new.env(),
            cell_eval = function(cell) rc_eval_cell_split_safe(root, P$results, cell, env, tau, cache = "key"))
  r <- rc_p3_round(R, T, shard = shard, merge = merge)
  if (!is.null(shard) && !isTRUE(merge)) return(invisible(list(worker = TRUE)))
  vis <- r; vis$cells <- lapply(r$cells, function(x) { x$record$alpha_test_window <- NULL; x })
  vis <- rc_redact_after_tau(vis, as.Date(spec[["tau_d"]]))
  lk <- unique(c(dp_scan_dates(vis[setdiff(names(vis), c("evaluated_at", "precheck", "fingerprint"))], as.Date(spec[["tau_d"]])),
                 rc_after_tau_leaks(vis[setdiff(names(vis), c("evaluated_at", "precheck", "fingerprint"))], as.Date(spec[["tau_d"]]))))
  if (length(lk)) stop("[round_core p3] 보는 창 파일에 τ_D 이후 날짜가 남았다: ", paste(head(lk, 5), collapse = ","))
  vis$audience <- "보는 창(τ_D 이전) — 시험 창 증분 알파 제외 · 처방 · 리뷰 레인 열람 가능"
  rc_json_write(vis, file.path(P$results, "evaluation_visible.json"))
  for (st in names(R$perf_env)) rc_perf_log(spec[["round_id"]], st, R$perf_env[[st]], root = root)
  list(schema = "round_core_p3_verdict_v1", core = RC_VERSION, round_id = spec[["round_id"]], evaluated_at = rc_now(), rules = pre[["rules_resolved"]],
       sentences = pre[["sentences"]], table = r$table, verdict = r$verdict, verdict_label = r$verdict_label, n_judged = r$n_judged, n_total = r$n_total,
       selected = r$selected, writes_visible = TRUE)
}
