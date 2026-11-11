## round_core v3 · rules_p2 — P2 규칙 종류를 rules.R 선언 형식에 더한다(위기 과반 · β 짝 승 · 비열등 알파 · 상승 포착 · 축 감사)
##   선언 하나 → 사전등록 문장(rc_rules_sentences) · 판정 실행(rc_rules_apply — 판정 표 열) · DESIGN 표(rc_rules_table_md). 기본 종류(threshold · all_of ·
##   any_of · report)와 섞어 쓴다(Kleene 논리 · 미측정 = NA · na 의미는 rules.R 그대로).
##   판정 표 = rc_p2_rule_table(칸 판정 기록) — 짝 평가 기록(out)에 이미 있는 계약 산출 값만 옮긴다(손계산 없음 · AX-008).
##   출처(같은 판정): P2R04 evaluate.R ①·② p2_crisis_majority + p2_maj(L166 · L94) · ③·④ β 짝(L1158-1163) · ⑦ p2_alpha_ok(L298) ·
##   ⑥ 강세(L1214-1215 · 헌장 빈칸 7) · 축 감사(round_kit rk_axis_audit — 칸 평가 status evaluated/axis_violation).

## 위기 집합 × 비교 대상 → 판정 표 열 접두(n_pair · share)
RC_P2_CRISIS_COLS <- c(rx0.all = "crisis", rx0.deep = "deep", beta_copy.deep = "beta_deep", beta_copy.fast = "fast", beta_copy.slow = "slow",
                       beta_copy.fast_excl_no_month_end = "fast_x")
.rc_p2_num_or_ref <- function(r, key, root) {
  ref <- r[[paste0(key, "_ref")]]; v <- r[[key]]
  if (!is.null(ref)) { x <- rc_ref_value(ref, root); if (!is.numeric(x) || length(x) != 1L || !is.finite(x)) .rc_rule_err(r, paste(key, "_ref 가 유한 수 1개가 아니다:", ref)); return(list(v = as.numeric(x), src = ref)) }
  list(v = as.numeric(v), src = paste("근거:", r[["basis"]] %||% ""))
}
.rc_p2_need_num <- function(r, key) {
  has_v <- !is.null(r[[key]]); has_ref <- !is.null(r[[paste0(key, "_ref")]])
  if (has_v == has_ref) .rc_rule_err(r, sprintf("%s 와 %s_ref 중 정확히 하나", key, key))
  if (has_v && (!is.numeric(r[[key]]) || length(r[[key]]) != 1L || !is.finite(r[[key]]))) .rc_rule_err(r, paste(key, "는 유한 수 1개"))
  if (has_v && (is.null(r[["basis"]]) || !nzchar(r[["basis"]]))) .rc_rule_err(r, paste("수치", key, "의 근거(basis)가 없다 — 하드코딩 금지"))
  invisible(TRUE)
}
.rc_col <- function(T, nm) if (nm %in% names(T)) suppressWarnings(as.numeric(T[[nm]])) else rep(NA_real_, nrow(T))
.rc_lcol <- function(T, nm) if (nm %in% names(T)) as.logical(T[[nm]]) else rep(NA, nrow(T))

## ① · ② · ③ · ④ 위기 과반 — 비교 대상(vs)보다 dd_capture 가 tol 넘게 낮은 위기의 비율 > majority(엄격) · 짝 < min_pairs 또는 비율 비유한 = NA(미측정)
.rc_crisis_prefix <- function(r) { k <- paste(r[["vs"]] %||% "rx0", r[["crises"]] %||% "all", sep = "."); RC_P2_CRISIS_COLS[[k]] %||% NA_character_ }
rc_rule_kind_register("crisis_majority",
  validate = function(r) {
    if (is.na(.rc_crisis_prefix(r))) .rc_rule_err(r, paste("vs × crises 조합은", paste(names(RC_P2_CRISIS_COLS), collapse = " | ")))
    .rc_p2_need_num(r, "majority")
    mp <- r[["min_pairs"]] %||% 2L; if (!is.numeric(mp) || length(mp) != 1L || mp < 1) .rc_rule_err(r, "min_pairs 는 1 이상 정수")
  },
  resolve = function(r, root) { m <- .rc_p2_num_or_ref(r, "majority", root); p <- .rc_crisis_prefix(r)
    r[["value"]] <- m$v; r[["value_source"]] <- m$src; r[["op"]] <- ">"; r[["min_pairs"]] <- as.integer(r[["min_pairs"]] %||% 2L)
    r[["metric"]] <- sprintf("%s_share (짝 %s_n_pair ≥ %d)", p, p, r[["min_pairs"]]); r },
  eval = function(r, T) { p <- .rc_crisis_prefix(r); n <- .rc_col(T, paste0(p, "_n_pair")); s <- .rc_col(T, paste0(p, "_share"))
    ifelse(is.finite(n) & n >= r[["min_pairs"]] & is.finite(s), s > r[["value"]], NA) },
  sentence = function(r) sprintf("%s: %s 위기 중 dd_capture 가 %s 보다 tol 넘게 낮은 위기 비율 > %s (짝 ≥ %d · %s)", r[["label"]],
                                 switch(r[["crises"]] %||% "all", all = "두 칸 모두의", deep = "깊은", fast = "빠른 급락", slow = "느린 약세", r[["crises"]]),
                                 if (identical(r[["vs"]], "beta_copy")) "β 짝 사본(RX0 × k)" else "같은 배치 RX0", .rc_val_str(r[["value"]]), r[["min_pairs"]], r[["value_source"]]),
  cols = function(r) { p <- .rc_crisis_prefix(r); paste0(p, c("_n_pair", "_share")) })
## ③ β 짝 승 — 위기 과반의 β 짝 사본 판(같은 계산 · 깊은 위기 기본)
rc_rule_kind_register("beta_pair_win",
  validate = function(r) { r2 <- r; r2[["vs"]] <- "beta_copy"; r2[["crises"]] <- r[["crises"]] %||% "deep"; get("crisis_majority", envir = RC_RULE_EXT)$validate(r2) },
  resolve = function(r, root) { r[["vs"]] <- "beta_copy"; r[["crises"]] <- r[["crises"]] %||% "deep"; get("crisis_majority", envir = RC_RULE_EXT)$resolve(r, root) },
  eval = function(r, T) get("crisis_majority", envir = RC_RULE_EXT)$eval(r, T),
  sentence = function(r) get("crisis_majority", envir = RC_RULE_EXT)$sentence(r),
  cols = function(r) { r[["vs"]] <- "beta_copy"; r[["crises"]] <- r[["crises"]] %||% "deep"; get("crisis_majority", envir = RC_RULE_EXT)$cols(r) })
## ⑦ 비열등 알파(헌장 빈칸 4C) — 보는 창 증분 β-통제 알파 t > t_floor ∧ 증분 ≥ −margin_frac × max(엔진 자체 α, 0) · 입력 NA = NA
rc_rule_kind_register("alpha_noninferior",
  validate = function(r) { .rc_p2_need_num(r, "t_floor"); .rc_p2_need_num(r, "margin_frac") },
  resolve = function(r, root) { a <- .rc_p2_num_or_ref(r, "t_floor", root); b <- .rc_p2_num_or_ref(r, "margin_frac", root)
    r[["t_floor"]] <- a$v; r[["margin_frac"]] <- b$v; r[["value_source"]] <- paste(a$src, "·", b$src)
    r[["metric"]] <- "alpha_t_vis · alpha_d_vis · engine_alpha_vis"; r },
  eval = function(r, T) { t <- .rc_col(T, "alpha_t_vis"); d <- .rc_col(T, "alpha_d_vis"); ea <- .rc_col(T, "engine_alpha_vis")
    ifelse(is.finite(t) & is.finite(d) & is.finite(ea), (t > r[["t_floor"]]) & (d >= -r[["margin_frac"]] * pmax(ea, 0)), NA) },
  sentence = function(r) sprintf("%s: 보는 창 증분 β-통제 알파 t > %s ∧ 증분 ≥ −%s × max(엔진 자체 알파, 0) (%s)", r[["label"]], .rc_val_str(r[["t_floor"]]),
                                 .rc_val_str(r[["margin_frac"]]), r[["value_source"]]),
  cols = function(r) c("alpha_t_vis", "alpha_d_vis", "engine_alpha_vis"))
## ⑥ 상승 포착 — 보는 창 상승 포착 중앙값 ≥ floor[ ∧ 강세 구간별 참여 비율 > majority(segments = TRUE · 짝 ≥ 2)] · 입력 NA = NA
rc_rule_kind_register("up_capture",
  validate = function(r) { .rc_p2_need_num(r, "floor"); if (isTRUE(r[["segments"]])) .rc_p2_need_num(r, "majority") },
  resolve = function(r, root) { f <- .rc_p2_num_or_ref(r, "floor", root); r[["floor"]] <- f$v; src <- f$src
    if (isTRUE(r[["segments"]])) { m <- .rc_p2_num_or_ref(r, "majority", root); r[["majority"]] <- m$v; src <- paste(src, "·", m$src) }
    r[["value_source"]] <- src; r[["metric"]] <- if (isTRUE(r[["segments"]])) "uc_vis · bull_share" else "uc_vis"; r },
  eval = function(r, T) { uc <- .rc_col(T, "uc_vis")
    if (!isTRUE(r[["segments"]])) return(ifelse(is.finite(uc), uc >= r[["floor"]], NA))
    bs <- .rc_col(T, "bull_share"); ifelse(is.finite(uc) & is.finite(bs), (bs > r[["majority"]]) & (uc >= r[["floor"]]), NA) },
  sentence = function(r) sprintf("%s: 보는 창 상승 포착 중앙값 ≥ %s%s (%s)", r[["label"]], .rc_val_str(r[["floor"]]),
                                 if (isTRUE(r[["segments"]])) sprintf(" ∧ 강세 구간별 참여(기준의 비율 이상) 비율 > %s", .rc_val_str(r[["majority"]])) else "", r[["value_source"]]),
  cols = function(r) if (isTRUE(r[["segments"]])) c("uc_vis", "bull_share") else "uc_vis")
## 축 감사 — 04_holdings 실보유(롱온리 · ≤ max_names · Σw ≤ 1) — 칸 평가 status(evaluated = 참 · axis_violation = 거짓 · 그 밖 = NA)
rc_rule_kind_register("axis_audit",
  validate = function(r) invisible(TRUE),
  resolve = function(r, root) { r[["metric"]] <- "axis_ok"; r[["value_source"]] <- "정본 constraint_defaults.json::tier_soft_deployment.max_names(칸 평가 rc_axis_audit)"; r },
  eval = function(r, T) .rc_lcol(T, "axis_ok"),
  sentence = function(r) sprintf("%s: 실보유 롱온리 · 종목 수 ≤ 정본 상한 · Σw ≤ 1(칸 평가 축 감사)", r[["label"]]),
  cols = function(r) "axis_ok")

## 판정 규칙이 시험 창 열(*_test)을 쓰는가(τ_D) — 확장 종류는 cols 로 본다
rc_rules_cols <- function(rules) {
  out <- character(0)
  walk <- function(r) {
    ext <- .rc_rule_ext(r[["type"]])
    if (!is.null(ext)) out <<- c(out, ext[["cols"]](r)) else if (r[["type"]] %in% c("threshold", "report")) out <<- c(out, r[["metric"]])
    if (r[["type"]] %in% c("all_of", "any_of")) for (k in r[["of"]]) walk(k)
  }
  for (r in rules) if (!identical(r[["type"]], "report")) walk(r)
  unique(out)
}
rc_p2_rules_tau_check <- function(rules) { b <- grep("_test$", rc_rules_cols(rules), value = TRUE); if (length(b)) stop("[round_core rules_p2] 판정 규칙이 시험 창 열을 쓴다(τ_D 위반): ", paste(b, collapse = ",")); invisible(TRUE) }

## 판정 표 — 칸 판정 기록(P2 템플릿 짝 평가 out) → 규칙 열. 시험 창 값은 싣지 않는다(τ_D).
rc_p2_rule_table <- function(OUT, EVS = NULL) {
  num <- function(x) suppressWarnings(as.numeric(x %||% NA))[1]
  rows <- lapply(OUT, function(x) {
    R <- x$rules; tested <- isTRUE(x$tested)
    sh <- function(z) if (tested) num(z$share) else NA_real_; np <- function(z) if (tested) num(z$n_pair) else NA_real_
    ev <- if (!is.null(EVS)) EVS[[x$cell]] else NULL
    data.table(code = x$cell %||% NA_character_, engine = x$engine %||% NA_character_, unit = x$device %||% x$method %||% NA_character_,
               role = x$role %||% "judge", tested = tested,
               crisis_n_pair = np(R$crisis), crisis_share = sh(R$crisis), deep_n_pair = np(R$deep), deep_share = sh(R$deep),
               beta_deep_n_pair = np(R$beta_deep), beta_deep_share = sh(R$beta_deep), fast_n_pair = np(R$fast), fast_share = sh(R$fast), slow_n_pair = np(R$slow), slow_share = sh(R$slow),
               fast_x_n_pair = if (tested) num(R$fast$record_excluding_no_month_end$n_pair) else NA_real_,
               fast_x_share = if (tested) num(R$fast$record_excluding_no_month_end$share) else NA_real_,
               beta_ratio_delta = if (tested) num(R$beta_asym$delta) else NA_real_, bull_share = sh(R$bull),
               uc_vis = if (tested) num(R$bull$uc_median) else NA_real_, cycle_share = sh(R$cycle),
               alpha_t_vis = if (tested) num(x$alpha_non_loss$t) else NA_real_, alpha_d_vis = if (tested) num(x$alpha_non_loss$d_alpha) else NA_real_,
               engine_alpha_vis = if (tested) num(x$alpha_non_loss$engine_alpha$alpha_ann) else NA_real_,
               axis_ok = if (is.null(ev)) NA else if (identical(ev$status, "evaluated")) TRUE else if (identical(ev$status, "axis_violation")) FALSE else NA)
  })
  rbindlist(rows, fill = TRUE)
}
## 선언 판정 ↔ 짝 평가 판정 대조 — 같은 규칙을 두 경로(선언 · 템플릿 단계)로 잰 값이 칸마다 같은지(어긋나면 그 칸 · 규칙 목록). 판정 코드와 사전등록 문장이
##   같은 출처인지의 기계 확인(문구 표류 탐지). map = 규칙 id → 칸 기록에서 읽는 함수(x → 논리 · NA)
rc_p2_rules_crosscheck <- function(rules_resolved, OUT, EVS, map) {
  T <- rc_p2_rule_table(OUT, EVS)
  A <- rc_rules_apply(rules_resolved, T, eligible = T$tested)
  bad <- character(0)
  for (id in names(map)) {
    if (!id %in% names(A)) { bad <- c(bad, paste("선언에 없는 규칙:", id)); next }
    proc <- vapply(OUT, function(x) { v <- map[[id]](x); if (is.null(v) || !length(v)) NA else as.logical(v)[1] }, logical(1))
    dec <- A[[id]]
    diff <- which(!(is.na(proc) & is.na(dec)) & (xor(is.na(proc), is.na(dec)) | (!is.na(proc) & !is.na(dec) & proc != dec)))
    if (length(diff)) bad <- c(bad, sprintf("%s: %s", id, paste(sprintf("%s(선언 %s · 단계 %s)", T$code[diff], dec[diff], proc[diff]), collapse = " ")))
  }
  list(ok = !length(bad), mismatches = bad, table = A)
}
