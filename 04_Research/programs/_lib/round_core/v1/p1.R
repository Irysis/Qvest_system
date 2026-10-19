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

## P1 표준 구성 칸 사양 — 등록된 선례(P0R01 C0 사양)를 그대로 복사하고 엔진 · 논문 · 시행 회계 · 측정 축(활성 epoch)만 바꾼다(재량 없음).
##   고정 축 값(종목 수 · 비용 · 유동성 · 롱온리)은 정본(constraint_defaults.json)과 대조한다 — 다르면 멈춘다(하드코딩 금지 · 정본 표류 탐지).
RC_P1_LIKE <- "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs/P0R01_E2_C0.json"
rc_p1_cell_spec <- function(code, engine_path, paper, family_root, n_family_at_registration, n_trials_basis, like = RC_P1_LIKE, root = rc_root()) {
  s <- rc_json_read(rc_abs(like, root))
  CD <- "02_Infrastructure/worktask/constraint_defaults.json::"
  want <- list(n_max = rc_ref_value(paste0(CD, "tier_soft_deployment.max_names"), root),
               commission_bps = rc_ref_value(paste0(CD, "tier_soft_deployment.transaction_cost_bps_one_way"), root),
               liq_adv20_min = rc_ref_value(paste0(CD, "tier_soft_deployment.liquidity_min_won_20d_avg"), root),
               long_only = rc_ref_value(paste0(CD, "tier_soft_deployment.long_only"), root))
  for (k in names(want)) if (!isTRUE(all.equal(as.numeric(s[["fixed_axes"]][[k]]), as.numeric(want[[k]]))))
    stop(sprintf("[round_core p1] 표준 구성 선례의 고정 축 %s = %s ≠ 정본 %s — 선례를 새로 정해야 한다", k, s[["fixed_axes"]][[k]], want[[k]]))
  ep <- rc_abs(gsub("\\\\", "/", engine_path), root)
  if (!file.exists(ep)) stop("[round_core p1] 엔진 파일 없음: ", engine_path)
  for (k in c("url", "title", "paper_key")) if (is.null(paper[[k]]) || !nzchar(paper[[k]])) stop("[round_core p1] paper$", k, " 없음")
  s[["code"]] <- code
  s[["label"]] <- sprintf("%s × 표준 구성(P0R01 C0 형식 · 롱온리 %s종 EW)", paper[["paper_key"]], want$n_max)
  s[["fixed_axes"]][["measurement_axis"]] <- rc_ref_value(paste0(CD, "measurement_axis.active"), root)
  s[["base_signal"]] <- list(kind = "engine", path = ep)
  s[["root_paper"]] <- paper[c("url", "title", "paper_key")]; s[["root_papers"]] <- list(paper[c("url", "title", "paper_key")])
  s[["idea"]] <- sprintf("[P1 엔진 자격 · 표준 구성] %s — 엔진 신호 그대로 · 처치 없음", paper[["paper_key"]])
  s[["selection_accounting"]] <- list(selection_type = "sweep", family_root = family_root, lineage = "P1_qualification",
                                      n_family_at_registration = n_family_at_registration, n_trials_basis = n_trials_basis)
  s
}

## P1 라운드 골격 — round_spec.json(P1R01 규칙 승계 · 설계 재량으로 고칠 수 있다) + 칸 사양 + DESIGN.md 템플릿
##   engines = list(list(engine = "E4", engine_path = , paper = list(url, title, paper_key), family_root = , n_family = , n_trials_basis = ), ...)
rc_init_p1 <- function(round_dir, round_id, engines, purpose, hypothesis, root = rc_root()) {
  if (file.exists(file.path(round_dir, "round_spec.json"))) stop("[round_core init] 이미 사양이 있다 — 덮어쓰지 않는다: ", round_dir)
  dir.create(file.path(round_dir, "specs"), recursive = TRUE, showWarnings = FALSE)
  tag <- rc_round_tag(round_id); cells <- list()
  for (e in engines) {
    code <- sprintf("%s_%s_C0", tag, e$engine)
    cs <- rc_p1_cell_spec(code, e$engine_path, e$paper, e$family_root, e$n_family, e$n_trials_basis, root = root)
    sp <- file.path(round_dir, "specs", paste0(code, ".json")); rc_json_write(cs, sp)
    cells[[length(cells) + 1L]] <- list(code = code, engine = e$engine, role = "variant", spec = rc_rel(sp, root))
  }
  spec <- list(schema = RC_SPEC_SCHEMA, program = "P1_RETURN", round_id = round_id, template = "p1_qualification", core_version = RC_VERSION,
               tau_d = "2022-12-31", purpose = purpose, hypothesis = hypothesis, cells = cells,
               rules = list(
                 list(id = "qualify", type = "all_of", label = "수익 엔진 자격", na = "untested", of = list(
                   list(id = "q_t_alpha", type = "threshold", label = "보는 창 β-통제 t(α)", metric = "t_alpha_vis", op = ">=",
                        value_ref = "02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t", na = "untested"),
                   list(id = "q_uc", type = "threshold", label = "보는 창 상승 포착", metric = "uc_vis", op = ">=", value = 0.55,
                        basis = "투자철학 헌장 — 강세 참여 ≥ 55%(P1R01 rules.qualify.uc_floor 승계)", na = "untested"))),
                 list(id = "test_hold", type = "report", label = "시험 창 유지(사람 쪽 보고)", when = "qualify", metric = "alpha_ann_test", op = ">", value = 0,
                      basis = "P1R01 rules.test_window 승계 — 자격 엔진만 · 판정 아님")),
               selection = list(rule = "none", text = "선택 없음 — 자격 엔진 목록이 P4 수익 엔진 후보(P4 에서 고를 때 시행 수로 센다)"),
               exposures = list("Q 는 시험 창(2023~)을 본 상태다 — 선택 · 판정 규칙은 보는 창 열만 쓴다(검사가 강제)"),
               conclusion_scope = list(), changes_after_review = list(), changes_after_superfan = list(), tests = list())
  rc_json_write(spec, file.path(round_dir, "round_spec.json"))
  tpl <- file.path(dirname(RC_DIR), "templates", "DESIGN_p1.md")
  if (file.exists(tpl)) invisible(file.copy(tpl, file.path(round_dir, "DESIGN.md")))
  invisible(file.path(round_dir, "round_spec.json"))
}
