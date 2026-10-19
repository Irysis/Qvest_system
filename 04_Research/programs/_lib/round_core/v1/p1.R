## round_core v1 · p1 — P1 엔진 자격 판정 틀(첫 소비자 · P1R01 evaluate.R 일반화)
##   칸마다: 칸 평가 기록(eval.json) → 보는 창 · 시험 창 β-통제 알파(계약) + 상승 포착(보는 창 패킷) → 사양의 규칙 선언을 기계 적용.
##   시험 창(τ_D 이후) 값은 보고 전용 열(*_test)로만 실리고 규칙은 보는 창 열만 쓴다(규칙이 *_test 를 쓰면 판정 전에 멈춘다).

RC_P1_COLS <- c("engine", "code", "status", "t_alpha_vis", "alpha_ann_vis", "beta_vis", "port_t_vis", "n_vis", "uc_vis", "cagr_vis",
                "t_alpha_test", "alpha_ann_test", "n_test", "uc_test")

## 판정 규칙이 시험 창 열을 쓰는지(τ_D — 선택 · 판정 규칙은 보는 창 정보만) — report(보고 전용)는 허용
rc_rules_test_window_use <- function(rules) {
  bad <- character(0)
  walk <- function(r) {
    if (identical(r[["type"]], "threshold") && grepl("_test$", r[["metric"]])) bad <<- c(bad, r[["id"]])
    if (r[["type"]] %in% c("all_of", "any_of")) for (k in r[["of"]]) walk(k)
  }
  for (r in rules) walk(r)
  bad
}

rc_p1_table <- function(spec, root = rc_root()) {
  E <- rc_deps(root); tau <- as.Date(spec$tau_d)
  rows <- list()
  for (c in spec$cells) {
    src <- rc_abs(c[["source_results"]] %||% file.path(dirname(spec$.path %||% "."), "results"), root)
    ev <- tryCatch(rc_json_read(file.path(src, c[["code"]], "eval.json")), error = function(z) NULL)
    if (is.null(ev) || !identical(ev$status, "evaluated")) {
      rows[[c[["code"]]]] <- data.table(engine = c[["engine"]], code = c[["code"]], status = ev$status %||% "not_evaluated"); next
    }
    m <- rc_safe(rc_metric_beta_alpha, E, ev$artifacts, tau, what = c[["code"]])
    if (!m$ok) { rows[[c[["code"]]]] <- data.table(engine = c[["engine"]], code = c[["code"]], status = "untested", error = m$error); next }
    e <- rc_metric_from_eval(ev); a <- m$value
    rows[[c[["code"]]]] <- data.table(engine = c[["engine"]], code = c[["code"]], status = "evaluated",
                                 t_alpha_vis = a$t_alpha_vis, alpha_ann_vis = a$alpha_ann_vis, beta_vis = a$beta_vis, port_t_vis = a$port_t_vis, n_vis = a$n_vis,
                                 uc_vis = e$uc_vis, cagr_vis = e$cagr_vis,
                                 t_alpha_test = a$t_alpha_test, alpha_ann_test = a$alpha_ann_test, n_test = a$n_test, uc_test = e$uc_test)
  }
  T <- rbindlist(rows, fill = TRUE)
  setcolorder(T, intersect(c(RC_P1_COLS, "error"), names(T)))
  T
}

## 판정 — rules = rc_rules_resolve 산출(해석된 문턱 · 출처) · 반환 = 판정 기록(표 · 자격 엔진 · 규칙 문장)
rc_p1_evaluate <- function(spec, rules, root = rc_root(), qualify_rule = spec$qualify_rule %||% "qualify") {
  tw <- rc_rules_test_window_use(rules)
  if (length(tw)) stop("[round_core p1] 판정 규칙이 시험 창 열을 쓴다(τ_D 위반): ", paste(tw, collapse = ","))
  T <- rc_p1_table(spec, root)
  T <- rc_rules_apply(rules, T, eligible = T$status == "evaluated")
  q <- if (qualify_rule %in% names(T)) T[get(qualify_rule) %in% TRUE]$engine else character(0)
  list(schema = "round_core_p1_evaluation_v1", core = RC_VERSION, round_id = spec$round_id, evaluated_at = rc_now(),
       rules = rules, sentences = as.list(rc_rules_sentences(rules)), table = T, qualified = q)
}
