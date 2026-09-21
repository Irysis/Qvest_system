#!/usr/bin/env Rscript
#==============================================================================
# rf_director.R — 리서치 디렉터 · 프로그램 수준 진단 (D0 · 2026-09-21 도훈 승인 플랜 Part 3)
#
# 왜: 루프의 결정은 전부 국소다(entry 안 블록 순서·배치·승자·승격, 논문 하나의 기저 관문).
#   프로그램 전체를 보는 부품이 없어서 ① 모든 계보가 같은 벽(Calmar)에 부딪힌다는 것
#   ② 어느 레버가 죽었는지(오버레이 적대검증 0 pass) ③ 벽을 깨라고 만든 2계층이 놀고 있다는 것을
#   어디서도 판단하지 못했다. 이 파일은 그 판단을 매일 아침 기계가 내리게 한다.
#
# 계약:
#   · 정본만 읽는다(AX-008). 등급·PORT_t·Calmar 는 원장/카탈로그/레지스트리 값을 **옮길 뿐** 재계산하지 않는다.
#   · 문턱은 essence_score.R::.graduation_params() 에서 온다 — 2.95/0.64 리터럴을 여기 쓰지 않는다.
#   · 백테스트 0 · 원장 쓰기 0 · 러너 무접촉. 산출은 캐시 JSON 1개 + 06_Registry/layer_bottleneck_map.md 뿐.
#   · 날짜를 산출에 넣지 않는다(낙폭 해부는 형태만 — rf_b5_design_lib 규약과 같다). 지도(map)는
#     research_continuity_guard 가 내용 sha 로 신선도를 재므로 "진단이 안 바뀌면 W3 WARN" 이 곧 반증 신호다.
#   · D0 = 진단만. 행동(π_dir 의 (a)(b)(c))은 config director.act=true 인 D3 부터이고, 여기서는 권고를 계산해 적기만 한다.
#
# 호출: Rscript 02_Infrastructure/ops/rf_director.R [--unattended] [--dry-run] [--root=<data root>]
#   --dry-run  : 계산·출력만, 쓰기 0.   --root= : 데이터 루트(검사 샌드박스용). 코드 루트는 이 파일의 위치.
#   검사가 함수만 쓰려면 QVEST_DIRECTOR_NO_MAIN=1 로 source 한다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ARGS <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) {
  v <- grep(paste0("^", flag, "="), ARGS, value = TRUE)
  if (length(v)) sub(paste0("^", flag, "="), "", v[1]) else default
}
DR_DRY   <- "--dry-run" %in% ARGS
DR_UNATT <- "--unattended" %in% ARGS
.norm <- function(p) sub("/+$", "", gsub("\\", "/", p, fixed = TRUE))
DR_ROOT <- .norm(.arg("--root", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
DR_CODE_ROOT <- local({
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a)) { sp <- .norm(sub("^--file=", "", a[1]))
    cr <- sub("/02_Infrastructure/ops/?$", "", dirname(sp))
    if (file.exists(file.path(cr, "02_Infrastructure/contracts/essence_score.R"))) return(cr) }
  ov <- Sys.getenv("QVEST_DIRECTOR_CODE_ROOT", "")
  if (nzchar(ov)) return(.norm(ov))
  DR_ROOT
})

.num <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA_real_)); if (length(v)) v[1] else NA_real_ }
.chr <- function(x) { v <- suppressWarnings(as.character(x %||% "")); v <- v[!is.na(v)]; if (length(v)) v[1] else "" }
.f2 <- function(x) { v <- .num(x); if (is.finite(v)) formatC(v, digits = 2, format = "f") else "NA" }
.f3 <- function(x) { v <- .num(x); if (is.finite(v)) formatC(v, digits = 3, format = "f") else "NA" }
.pct <- function(x) { v <- .num(x); if (is.finite(v)) sprintf("%.1f%%", 100 * v) else "NA" }
.rj <- function(p) if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
.age_h <- function(p) if (file.exists(p)) as.numeric(difftime(Sys.time(), file.info(p)$mtime, units = "hours")) else NA_real_
.P <- function(...) file.path(DR_ROOT, ...)

# ── config (director 블록 · 부재 = 기본값 · 전부 provenance 는 플랜 Part 3 §4/§5) ─────────────
dir_cfg <- function(root = DR_ROOT) {
  c0 <- (.rj(file.path(root, "06_Registry/reinforce_auto_config.json")) %||% list())$director %||% list()
  list(enabled = isTRUE(c0$enabled %||% TRUE),
       act = isTRUE(c0$act %||% FALSE),                       # D0/D1 = 진단·권고만
       top_k = as.integer(c0$top_k %||% 5L),                  # 상위 계보 수 = lcode_harvester PC_TOP_N 과 동일
       min_adversary_n = as.integer(c0$min_adversary_n %||% 10L),  # 레버 '죽음' 판정에 필요한 최소 반증 arm 수
       max_units_per_day = as.integer(c0$max_units_per_day %||% 1L),
       stale_pool_days = as.numeric(c0$stale_pool_days %||% 7),
       stale_catalog_hours = as.numeric(c0$stale_catalog_hours %||% 36),
       episode_shape_months = as.numeric(c0$episode_shape_months %||% 6),  # 고점→저점 ≤ N개월 = 급락형(서술 라벨)
       telegram = .chr(c0$telegram %||% "on_change"),
       llm_advisory = isTRUE(c0$llm_advisory %||% FALSE))
}

# ── 문턱: essence_score.R 정본 ────────────────────────────────────────────────────────────────
dir_thresholds <- function(root = DR_ROOT, code_root = DR_CODE_ROOT) {
  E <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(suppressWarnings(
    sys.source(file.path(code_root, "02_Infrastructure/contracts/essence_score.R"), envir = E)))))
  p <- suppressWarnings(E$.graduation_params(root = root))
  list(port_t_min = .num(p$port_t_min), calmar_min = .num(p$calmar_min), oos_min = .num(p$oos_min),
       oos_floor = .num(p$oos_floor), sharpe_min = .num(p$sharpe_min), cagr_min = .num(p$cagr_min),
       source = .chr(attr(p, "source") %||% "essence_score.R::.graduation_params"))
}

# ── B5 설계 라이브러리(낙폭 해부·오버레이 반증 집계) — 격리 env 에 적재 ─────────────────────
dir_b5lib <- function(root = DR_ROOT, code_root = DR_CODE_ROOT) {
  Sys.setenv(QVEST_RF_ROOT = root, QVEST_B5_CODE_ROOT = code_root)
  B <- new.env(parent = globalenv())
  ok <- tryCatch({ invisible(capture.output(suppressMessages(suppressWarnings(
          sys.source(file.path(code_root, "02_Infrastructure/ops/rf_b5_design_lib.R"), envir = B))))); TRUE },
        error = function(e) { message("[rf_director] b5 lib 적재 실패: ", conditionMessage(e)); FALSE })
  if (!ok) return(NULL)
  B
}

# ── 계보 ①: 강화 원장 L1 — 계보 = 승격 사슬(_promoN 제거) · 대표 칸 = PORT_t 최고 측정 칸 ─────
dir_lineages_ledger <- function(led) {
  rows <- list()
  for (e in led$entries %||% list()) {
    bid <- .chr(e$base_id); lin <- sub("_promo[0-9]+$", "", bid)
    for (a in e$attempts %||% list()) {
      es <- a$essence; if (!is.list(es)) next
      pt <- .num(es$port_t); if (!is.finite(pt)) next
      if (!is.null(es$inherited_from)) next                       # 승계 칸은 자기 측정이 아니다
      rows[[length(rows) + 1L]] <- data.table(
        lineage = lin, sid = sprintf("%s:%s", bid, .chr(a$cell_code %||% es$cell_code)), source = "reinforce_ledger_l1",
        grade = .chr(a$grade), port_t = pt, calmar = .num(es$calmar), cagr = .num(es$cagr), mdd = .num(es$mdd),
        sharpe = .num(es$net_sharpe), oos_retention = .num(es$oos_retention), artifacts = .chr(a$artifacts))
    }
  }
  if (!length(rows)) return(data.table())
  D <- rbindlist(rows, fill = TRUE)
  D[D[, .I[which.max(port_t)], by = lineage]$V1]
}

# ── 계보 ②: module_catalog authoritative_essence — 술어 = lcode_harvester.py::_pc_top_strategies ─
dir_lineages_catalog <- function(cat, root = DR_ROOT) {
  rows <- list(); seen <- character(0)
  for (sid in names(cat$modules %||% list())) {
    m <- cat$modules[[sid]]; if (!is.list(m)) next
    if (isTRUE(m$label_contaminated) || isTRUE(m$grade_contaminated)) next
    es <- (m$meta %||% list())$authoritative_essence; if (!is.list(es)) next
    pt <- .num(es$portfolio_alpha_t_nw_lag3); if (!is.finite(pt)) next
    h <- .chr(m$module_hash %||% paste0("__nohash__", sid)); if (h %in% seen) next; seen <- c(seen, h)
    sr <- .chr(m$sim_result_path)
    rows[[length(rows) + 1L]] <- data.table(
      lineage = .chr(m$strategy_id %||% sid), sid = .chr(m$strategy_id %||% sid), source = "module_catalog",
      grade = .chr(m$grade), port_t = pt, calmar = .num(es$calmar), cagr = .num(es$cagr), mdd = .num(es$mdd),
      sharpe = .num(es$net_sharpe), oos_retention = .num(es$oos_retention),
      artifacts = if (nzchar(sr)) file.path(root, dirname(sr)) else "")
  }
  if (!length(rows)) data.table() else rbindlist(rows, fill = TRUE)
}

dir_top_lineages <- function(led, cat, k = 5L, root = DR_ROOT) {
  D <- rbindlist(list(dir_lineages_ledger(led), dir_lineages_catalog(cat, root)), fill = TRUE)
  if (!nrow(D)) return(D)
  D[, rank0 := ifelse(grade %in% c("A", "B"), 0L, 1L)]        # 하비스터 정렬 규칙: A/B 우선 → PORT_t
  setorder(D, rank0, -port_t)
  D[, rank0 := NULL]
  head(D, k)
}

# ── 구속 조건: 어느 A 조건이 막는가 (essence 값 대 정본 문턱 · 산술은 rf_round_review.R:74-83 동형) ─
dir_binding <- function(L, th) {
  if (!nrow(L)) return(list(lineages = list(), verdict = list(binding_condition = "unmeasured", n_lineages_bound = 0L,
                                                             revenue_axes_met = FALSE, note = "측정된 계보 없음")))
  per <- lapply(seq_len(nrow(L)), function(i) {
    r <- L[i]; fails <- character(0)
    if (!is.finite(r$port_t) || r$port_t < th$port_t_min) fails <- c(fails, "port_t")
    if (!is.finite(r$cagr) || r$cagr < th$cagr_min) fails <- c(fails, "cagr")
    if (!is.finite(r$sharpe) || r$sharpe < th$sharpe_min) fails <- c(fails, "sharpe")
    if (!is.finite(r$calmar) || r$calmar < th$calmar_min) fails <- c(fails, "calmar")
    if (!is.finite(r$oos_retention) || r$oos_retention < th$oos_min) fails <- c(fails, "oos_retention")
    list(sid = r$sid, lineage = r$lineage, source = r$source, grade = r$grade, port_t = r$port_t, calmar = r$calmar,
         cagr = r$cagr, mdd = r$mdd, sharpe = r$sharpe, oos_retention = r$oos_retention, binding = fails,
         gap = list(port_t = r$port_t - th$port_t_min, calmar = r$calmar - th$calmar_min,
                    cagr_needed_at_mdd = if (is.finite(r$mdd) && r$mdd > 0) th$calmar_min * r$mdd else NA_real_))
  })
  tab <- table(unlist(lapply(per, `[[`, "binding")))
  best <- per[[1]]
  rev_ok <- !any(c("port_t", "cagr", "sharpe") %in% best$binding)
  co <- character(0)
  if (!length(tab)) bc <- "none"
  else {
    # 최다 계보를 막는 조건. 동률이면 수익 축(port_t·cagr·sharpe)보다 위험 축(calmar)을 우선 보고한다 —
    # 수익 축이 충족된 프로그램에서 남는 벽은 위험 축이라는 lean-loop 4단계 규약(위험 축 = Calmar 하나).
    # 같은 수의 계보를 막는 다른 조건은 **공동 구속(co_binding)** 으로 같이 적는다 — 하나만 적으면 OOS 같은 축이 조용히 사라진다.
    top <- names(tab)[tab == max(tab)]
    bc <- if ("calmar" %in% top && rev_ok) "calmar" else top[1]
    co <- setdiff(top, bc)
  }
  list(lineages = per,
       verdict = list(binding_condition = bc, co_binding = as.list(co),
                      n_lineages_bound = if (bc %in% names(tab)) as.integer(tab[[bc]]) else 0L,
                      n_lineages = length(per), revenue_axes_met = rev_ok,
                      counts = as.list(tab),
                      note = if (bc == "none") "상위 계보에 A 조건 미달 없음 — Judge/BOOK 경로 확인"
                             else sprintf("상위 %d 계보 중 %d 이 %s 미달%s · 최고 %s(%s) PORT_t %s · Calmar %s · MDD %s · OOS %s",
                                          length(per), if (bc %in% names(tab)) tab[[bc]] else 0L, bc,
                                          if (length(co)) sprintf(" (공동 구속 %s)", paste(co, collapse = "+")) else "",
                                          best$sid, best$grade, .f3(best$port_t), .f3(best$calmar), .pct(best$mdd), .f2(best$oos_retention))))
}

# ── 2계층 단위 요청 슬롯(D2 에서 rf_l2_auto 가 소비) — 부재 = 미결 없음 ────────────────────────
dir_l2_request <- function(root = DR_ROOT) {
  r <- .rj(file.path(root, "06_Registry/l2_unit_request.json"))
  st <- .chr(r$status %||% "none")
  list(status = st, busy = st %in% c("pending", "in_progress"), requested_at = .chr(r$requested_at), base_id = .chr(r$base_id))
}

# ── 낙폭 해부 (프로그램 범위 · 날짜 없음) — b5_drawdown_episodes 재사용 ────────────────────────
dir_episodes <- function(L, B5, cfg) {
  per <- list(); deepest <- list()
  for (i in seq_len(nrow(L))) {
    r <- L[i]; ad <- .chr(r$artifacts)
    np <- c(file.path(ad, "02_nav.csv"), file.path(ad, "stage_artifacts", "02_nav.csv"))
    np <- np[file.exists(np)]
    if (is.null(B5) || !nzchar(ad) || !length(np)) { per[[length(per) + 1L]] <- list(sid = r$sid, episodes = list(), note = "02_nav.csv 부재"); next }
    NV <- tryCatch(fread(np[1]), error = function(e) NULL)
    if (is.null(NV) || !all(c("date", "nav_net") %in% names(NV))) { per[[length(per) + 1L]] <- list(sid = r$sid, episodes = list(), note = "열 부재"); next }
    bnav <- NULL; bp <- file.path(dirname(np[1]), "05_benchmark_returns.csv")
    if (file.exists(bp)) { BM <- tryCatch(fread(bp), error = function(e) NULL)
      if (!is.null(BM) && all(c("date", "benchmark_nav") %in% names(BM))) {
        m <- match(as.character(NV$date), as.character(BM$date)); bnav <- as.numeric(BM$benchmark_nav)[m] } }
    eps <- tryCatch(B5$b5_drawdown_episodes(as.numeric(NV$nav_net), as.Date(as.character(NV$date)), bnav, 3L),
                    error = function(e) list())
    eps2 <- lapply(eps, function(z) list(depth = .num(z$depth), m_peak_trough = .num(z$m_peak_trough),
                                          m_underwater = .num(z$m_underwater), m_recover = .num(z$m_recover),
                                          recovered = isTRUE(z$recovered), bench_depth = .num(z$bench_depth), ratio = .num(z$ratio)))
    per[[length(per) + 1L]] <- list(sid = r$sid, episodes = eps2)
    if (length(eps2)) deepest[[length(deepest) + 1L]] <- eps2[[1]]
  }
  rc <- if (!length(deepest)) list(shape = "unmeasured", n_lineages_sharing = 0L) else {
    d <- vapply(deepest, function(z) z$depth, numeric(1)); m <- vapply(deepest, function(z) z$m_peak_trough, numeric(1))
    rt <- vapply(deepest, function(z) z$ratio, numeric(1))
    shape <- if (is.finite(stats::median(m, na.rm = TRUE)) && stats::median(m, na.rm = TRUE) <= cfg$episode_shape_months) "급락형" else "침식형"
    list(shape = shape, shape_rule = sprintf("최심 에피소드 고점→저점 중앙 ≤ %g개월 = 급락형 (config director.episode_shape_months)", cfg$episode_shape_months),
         depth_median = stats::median(d, na.rm = TRUE), m_peak_trough_median = stats::median(m, na.rm = TRUE),
         ratio_median = if (any(is.finite(rt))) stats::median(rt, na.rm = TRUE) else NA_real_,
         n_lineages_sharing = length(deepest))
  }
  list(per_lineage = per, recurring_class = rc)
}

# ── 레버 건강 ──────────────────────────────────────────────────────────────────────────────────
dir_lever_overlay <- function(B5, cfg, root = DR_ROOT) {
  o <- if (is.null(B5)) NULL else tryCatch(B5$rf_overlay_outcomes(root), error = function(e) NULL)
  if (is.null(o) || !nrow(o)) return(list(arms_measured = 0L, adv_pass = 0L, adv_fail = 0L, adv_other = 0L,
                                          pass_rate = NA_real_, status = "unmeasured", med_d_calmar_median = NA_real_))
  ap <- sum(o$adv_pass, na.rm = TRUE); af <- sum(o$adv_fail, na.rm = TRUE); ao <- sum(o$adv_other, na.rm = TRUE)
  n_verdict <- ap + af + ao
  st <- if (ap > 0L) "alive" else if (nrow(o) >= cfg$min_adversary_n && n_verdict > 0L) "dead" else "unmeasured"
  list(arms_measured = nrow(o), adv_pass = ap, adv_fail = af, adv_other = ao,
       pass_rate = if (n_verdict > 0L) ap / n_verdict else NA_real_, status = st,
       med_d_calmar_median = { v <- o$med_d_calmar[is.finite(o$med_d_calmar)]; if (length(v)) stats::median(v) else NA_real_ },
       status_rule = sprintf("pass>0 = alive · arms ≥ %d ∧ pass 0 = dead · 그 외 unmeasured", cfg$min_adversary_n))
}

dir_lever_block_order <- function(led) {
  fired <- 0L; ent <- 0L
  for (e in led$entries %||% list()) { ent <- ent + 1L
    if (isTRUE(e$search_adaptive) || grepl("Calmar|calmar", .chr(e$block_order_reason))) fired <- fired + 1L }
  list(entries = ent, entries_fired_calmar_rule = fired, rule = "reinforcement/rf_lesson.R::rf_block_order_decide (CAGR 충족 ∧ Calmar 미달 → B5 먼저)")
}

dir_lever_l2 <- function(root = DR_ROOT) {
  reg <- .rj(file.path(root, "06_Registry/factor_rotation_registry.json"))
  frs <- reg$factor_rotations %||% list(); if (is.list(frs) && !is.null(names(frs)) && length(frs) && is.list(frs[[1]]) && is.null(frs[[1]]$fr_id)) frs <- unname(frs)
  ids <- vapply(frs, function(f) .chr(f$fr_id), character(1)); grades <- vapply(frs, function(f) .chr(f$grade), character(1))
  cal <- vapply(frs, function(f) .num((f$essence %||% list())$calmar), numeric(1))
  pt  <- vapply(frs, function(f) .num((f$essence %||% list())$port_t %||% (f$essence %||% list())$portfolio_alpha_t_nw_lag3), numeric(1))
  nmod <- vapply(frs, function(f) .num(f$n_modules), numeric(1))
  last_id <- if (length(ids)) ids[length(ids)] else ""
  mc1 <- NA; mc_path <- ""
  if (nzchar(last_id)) {
    fs <- list.files(file.path(root, "04_Research/factor_rotation/output", last_id), pattern = "manipulation_check\\.json$", full.names = TRUE)
    if (length(fs)) { pref <- fs[!grepl("_arm", basename(fs))]; mc_path <- if (length(pref)) pref[1] else fs[1]
      mc <- .rj(mc_path); mc1 <- isTRUE((mc$MC1_membership %||% list())$delivered) }
  }
  l2 <- .rj(file.path(root, "06_Registry/reinforce_ledger_l2.json"))
  act <- Filter(function(e) identical(e$status, "active"), l2$entries %||% list())
  pool <- .rj(file.path(root, "06_Registry/module_performance.json"))
  list(fr_ids = ids, grades = grades, best_calmar = if (length(cal) && any(is.finite(cal))) max(cal, na.rm = TRUE) else NA_real_,
       best_port_t = if (length(pt) && any(is.finite(pt))) max(pt, na.rm = TRUE) else NA_real_,
       last_fr = last_id, last_mc1_delivered = mc1, mc1_source = basename(mc_path),
       pool_n_at_last_run = if (length(nmod)) nmod[length(nmod)] else NA_real_, pool_n_now = .num(pool$n_modules),
       active_entry = if (length(act)) .chr(act[[1]]$base_id) else "", attempts_used = if (length(act)) .num(act[[1]]$attempts_used %||% 0) else NA_real_,
       n_entries = length(l2$entries %||% list()))
}

dir_lever_combination <- function(led, root = DR_ROOT) {
  rq <- .rj(file.path(root, "06_Registry/replication_request.json")); cc <- .rj(file.path(root, "06_Registry/combination_candidates.json"))
  cr <- led$combination_review %||% list()
  list(request_status = .chr(rq$status %||% "none"), request_source = .chr(rq$source), candidates_n = length(cc$candidates %||% list()),
       last_review_date = .chr(cr$last_review_date), papers_since_last_review = .num(cr$papers_since_last_review))
}

# ── 풀 재고 — admission_reason 문자열 파서 = 파일럿 wp4_parse_pool 과 같은 정규식 ────────────
dir_pool <- function(root = DR_ROOT) {
  j <- .rj(file.path(root, "06_Registry/module_performance.json"))
  if (is.null(j)) return(list(n_modules = NA_integer_, note = "module_performance.json 부재"))
  num <- function(rs, pat) { x <- regmatches(rs, regexpr(pat, rs)); if (!length(x)) return(NA_real_)
    suppressWarnings(as.numeric(gsub("[^0-9.+-]", "", sub(pat, "\\1", x)))) }
  deep <- c(); ds_present <- 0L; routes <- character(0); grades <- character(0)
  for (m in j$modules %||% list()) {
    routes <- c(routes, .chr(m$admission_route %||% "-")); grades <- c(grades, .chr(m$grade))
    if (!is.null(m$defensive_score)) ds_present <- ds_present + 1L
    if (identical(.chr(m$admission_route), "defensive_specialist")) {
      rs <- .chr(m$admission_reason); deep <- c(deep, num(rs, "벤치-10% 이하 [0-9]+개: 초과 ([+-][0-9.]+)%")) }
  }
  dv <- deep[is.finite(deep)]
  list(n_modules = .num(j$n_modules), generated = .chr(j$generated), grade_floor = .chr(j$grade_floor),
       grade_floor_n = sum(routes == "grade_floor"), defensive_n = sum(routes == "defensive_specialist"), legacy_a_n = sum(routes == "-"),
       grades = as.list(table(grades)), admission_codes = j$admission_codes %||% list(),
       defensive_deep_dd_excess_median = if (length(dv)) stats::median(dv) else NA_real_,
       defensive_deep_dd_negative_share = if (length(dv)) mean(dv < 0) else NA_real_,
       n_surviving_binding_class = sum(dv > 0), defensive_score_field_present = ds_present)
}

dir_unreachable <- function(led) {
  st <- vapply(led$entries %||% list(), function(e) .chr(e$status), character(1))
  list(l1_parked = sum(st == "parked"), l1_exhausted = sum(st == "exhausted"), l1_active = sum(st == "active"), l1_other = sum(!(st %in% c("parked", "exhausted", "active"))))
}

dir_decisions_today <- function(root = DR_ROOT) {
  p <- file.path(root, "06_Registry/rf_decisions.jsonl"); if (!file.exists(p)) return(0L)
  L <- readLines(p, warn = FALSE, encoding = "UTF-8"); today <- format(Sys.Date(), "%Y-%m-%d"); n <- 0L
  for (l in L) { r <- tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(r) && identical(.chr(r$kind), "direction") && startsWith(.chr(r$at), today) && length(r$chosen$units %||% list())) n <- n + 1L }
  n
}

# ── 방향 규칙 π_dir v0 (플랜 Part 3 §4 · 결정적 · 각 분기의 출처는 rule 필드) ────────────────
dir_rule_v0 <- function(verdict, overlay, l2, comb, pool, cfg, units_today = 0L, inputs_stale = FALSE, l2req = list(busy = FALSE, status = "none")) {
  alt <- list()
  push <- function(action, why, unit = NULL) alt[[length(alt) + 1L]] <<- list(action = action, why = why, unit = unit)
  l2_busy <- isTRUE(l2req$busy)                       # 진행 중 단위 = l2_unit_request.json pending/in_progress (D2 소비자)
  l2_unit <- list(kind = "l2_unit", base_id = if (nzchar(l2$active_entry %||% "")) l2$active_entry else "FR_003",
                  axis = "strategy_combination", arms = c("T", "S", "C"), next_probe = 2L,
                  idea = sprintf("풀 %s(직전 실측 %s) 위 π₀ 재측정 + floor-only 대조로 방어형 재고 귀속", .chr(l2$pool_n_now), .chr(l2$pool_n_at_last_run)))
  co <- unlist(verdict$co_binding %||% list())
  base_props <- if ("oos_retention" %in% co)
    list(sprintf("OOS retention 도 상위 계보 %d/%d 미달(공동 구속) — 어떤 단위든 oos 를 같이 관찰. 레버 ①(분포 표적) 착수 여부 = 도훈 결정",
                 verdict$n_lineages_bound %||% 0L, verdict$n_lineages %||% 0L)) else list()
  decide <- function(action, rule, unit = NULL, proposals = list())
    list(action = action, rule = rule, unit = unit, alternatives = alt, proposals = c(base_props, proposals), rule_version = "pi_dir_v0",
         executed = FALSE, execute_note = if (isTRUE(cfg$act)) "D3 실행기 미배선 — 권고만" else "director.act=false — 권고만(D0/D1)")
  bc <- .chr(verdict$binding_condition)
  # 0. 행동 예산·낡은 입력 — 진단만
  if (!isTRUE(cfg$act)) push("none", "config director.act=false (D0/D1 — 진단·권고만)")
  if (units_today >= cfg$max_units_per_day) { push("none", "오늘 단위 예산 소진"); return(decide("none", "rule0_budget")) }
  if (inputs_stale) { push("none", "입력 낡음(풀 >7d 또는 카탈로그 >36h)"); return(decide("none", "rule0_stale_inputs")) }
  # 1. 수익 축이 막혀 있으면 1계층 레인이 이미 그 축 — 기록만
  if (bc %in% c("port_t", "cagr", "sharpe")) { push("none", sprintf("구속 %s = 수익 축 · 1계층 격자/다음 논문이 이미 그 축", bc)); return(decide("none", "rule1_revenue_axis_bound")) }
  # 2. Calmar 구속 ∧ 수익 축 충족 ∧ 오버레이 레버 사망 ∧ L2 단위 미결 없음 → 2계층 단위
  if (identical(bc, "calmar") && isTRUE(verdict$revenue_axes_met)) {
    if (identical(overlay$status, "dead") && !l2_busy) {
      push("open_l2_unit", sprintf("Calmar 구속(%d/%d) ∧ B5 반증 pass 0/%d(arm %d) ∧ L2 시도 %s회 · 풀 %s vs 직전 %s",
                                   verdict$n_lineages_bound, verdict$n_lineages, overlay$adv_pass + overlay$adv_fail + overlay$adv_other,
                                   overlay$arms_measured, .chr(l2$attempts_used), .chr(l2$pool_n_now), .chr(l2$pool_n_at_last_run)), l2_unit)
      push("directed_combination", "규칙 3 은 L2 단위 진행 중일 때만"); push("b5_context_only", "항상 병행 (c)")
      props <- list()
      if (identical(l2$last_mc1_delivered, FALSE)) props <- c(props, list("직전 2계층 실측 MC1 미발화(국면 채널 미전달) — 규칙 4 감시 시작. 2회 연속이면 π₀ 재실행 중단·국면식별 축 설계 제안"))
      return(decide("open_l2_unit", "rule2_calmar_bound_overlay_dead", l2_unit, props))
    }
    if (identical(overlay$status, "dead") && l2_busy) {
      if (comb$request_status %in% c("done", "failed_needs_session", "revoked", "none") && isTRUE(pool$n_surviving_binding_class >= 3)) {
        unit <- list(kind = "directed_combination", pair = "defensive_deep_dd_positive × program_best", n_defensive_eligible = pool$n_surviving_binding_class)
        push("directed_combination", "L2 단위 진행 중 ∧ 결합 슬롯 terminal ∧ 방어형 재고 ≥3", unit)
        return(decide("directed_combination", "rule3_l2_busy_combination_slot_free", unit))
      }
      push("none", "L2 진행 중 · 결합 슬롯 busy"); return(decide("none", "rule3_wait"))
    }
    push("none", sprintf("B5 오버레이 상태 %s — 사망 판정 전(arm %d < %d 또는 pass>0)", overlay$status, overlay$arms_measured, cfg$min_adversary_n))
    return(decide("b5_context_only", "rule2_overlay_not_dead", NULL,
                  list("오버레이 레버가 아직 살아 있거나 미측정 — B5 재료에 프로그램 낙폭 구조만 주입(c)")))
  }
  # 5. OOS 구속 또는 잔여 — 제안만
  if (identical(bc, "oos_retention")) { push("proposal", "OOS retention 구속 — 레버 ①(분포 표적)·재현 규율 = 세션 과제"); return(decide("proposal", "rule5_oos_bound", NULL, list("OOS retention 이 구속 — 레버 ① 착수 여부는 도훈 결정"))) }
  if (identical(bc, "none")) { push("none", "상위 계보 A 조건 전부 충족 — Judge/BOOK 경로"); return(decide("none", "rule_none_all_met")) }
  push("none", sprintf("구속 %s — 규칙 미정의", bc)); decide("none", "rule_undefined")
}

# ── 부팅 한 줄(≤120자 · 날짜 없음) ─────────────────────────────────────────────────────────────
dir_boot_line <- function(v, best, ov, l2, rec) {
  co <- unlist(v$co_binding %||% list())
  s <- sprintf("Director: 구속=%s%s(%d/%d) · 최고 PORT_t %s Calmar %s · B5 %s(%d/%d) · L2 %s %s·%s회 · 권고=%s",
               v$binding_condition, if (length(co)) paste0("+", paste(co, collapse = "+")) else "",
               v$n_lineages_bound %||% 0L, v$n_lineages %||% 0L, .f2(best$port_t), .f2(best$calmar),
               ov$status, ov$adv_pass, ov$adv_pass + ov$adv_fail + ov$adv_other,
               if (nzchar(l2$last_fr)) l2$last_fr else "-", if (length(l2$grades)) l2$grades[length(l2$grades)] else "-", .chr(l2$attempts_used %||% 0),
               switch(rec$action, open_l2_unit = "2계층 T/S/C", directed_combination = "지시결합", b5_context_only = "B5 컨텍스트", proposal = "제안", none = "없음", rec$action))
  if (nchar(s, type = "chars") > 120L) s <- paste0(substr(s, 1L, 117L), "…")
  s
}

# ── 지도(정본 홈 부활 · 날짜 없음 · 값만) ────────────────────────────────────────────────────
dir_map_md <- function(out) {
  v <- out$verdict; b <- out$program_best; ov <- out$lever_health$overlay_B5; l2 <- out$lever_health$L2; p <- out$pool_inventory; r <- out$recommendation
  c("# layer_bottleneck_map — 리서치 디렉터 판정 (기계 생성 · 날짜 없음 · 정본 = .cache/rf_director_latest.json)",
    "",
    "| 계층 | 구속 조건 | 최고 계보 | 레버 상태 | 다음 행동 |",
    "|---|---|---|---|---|",
    sprintf("| 1계층 | %s (%d/%d 계보) | %s · PORT_t %s · Calmar %s · MDD %s · CAGR %s | B5 오버레이 %s (반증 pass %d/%d) · 블록순서 Calmar 규칙 발화 %d/%d entry | %s |",
            v$binding_condition, v$n_lineages_bound %||% 0L, v$n_lineages %||% 0L, b$sid %||% "-", .f3(b$port_t), .f3(b$calmar), .pct(b$mdd), .pct(b$cagr),
            ov$status, ov$adv_pass, ov$adv_pass + ov$adv_fail + ov$adv_other,
            out$lever_health$block_order$entries_fired_calmar_rule, out$lever_health$block_order$entries, r$action),
    sprintf("| 2계층 | FR %s · 최고 Calmar %s · 최고 PORT_t %s | 시도 %s회 · 풀 %s(직전 실측 %s) | 국면 채널 MC1 전달 %s | %s |",
            paste(l2$fr_ids, collapse = "/"), .f3(l2$best_calmar), .f3(l2$best_port_t), .chr(l2$attempts_used %||% 0), .chr(l2$pool_n_now), .chr(l2$pool_n_at_last_run),
            if (isTRUE(l2$last_mc1_delivered)) "예" else if (identical(l2$last_mc1_delivered, FALSE)) "아니오" else "미측정",
            if (identical(r$action, "open_l2_unit")) "π₀ 재측정 T/S/C" else "-"),
    sprintf("| 풀 | 모듈 %s (floor %s · 방어형 %s · legacy A %s) | 방어형 깊은낙폭 초과 중앙 %s%%/월 · 음수 비율 %s | defensive_score 필드 %s/%s | %s |",
            .chr(p$n_modules), .chr(p$grade_floor_n), .chr(p$defensive_n), .chr(p$legacy_a_n),
            .f2(p$defensive_deep_dd_excess_median), .pct(p$defensive_deep_dd_negative_share), .chr(p$defensive_score_field_present), .chr(p$n_modules),
            "재고 → 지시 결합 재료(규칙 3)"),
    "",
    sprintf("- 낙폭 구조(상위 계보 최심 에피소드): %s · 깊이 중앙 %s · 고점→저점 중앙 %s개월 · 벤치 대비 비 중앙 %s · 공유 계보 %s",
            .chr(out$dd_episodes$recurring_class$shape), .pct(out$dd_episodes$recurring_class$depth_median),
            .chr(out$dd_episodes$recurring_class$m_peak_trough_median), .f2(out$dd_episodes$recurring_class$ratio_median),
            .chr(out$dd_episodes$recurring_class$n_lineages_sharing)),
    sprintf("- 권고 규칙: %s · 대안 %d건 · 제안 %d건", r$rule, length(r$alternatives), length(r$proposals)),
    sprintf("- 문턱 출처: %s (PORT_t ≥ %s · Calmar ≥ %s · SR ≥ %s · CAGR ≥ %s · OOS ≥ %s)", out$thresholds$source,
            .f2(out$thresholds$port_t_min), .f2(out$thresholds$calmar_min), .f2(out$thresholds$sharpe_min), .f2(out$thresholds$cagr_min), .f2(out$thresholds$oos_min)),
    "",
    "> 자동 생성 — 손 편집 금지. 진단이 며칠째 같으면(research_continuity_guard W3) 그것이 곧 '디렉터가 정보를 못 준다'는 반증 신호다(플랜 Part 3 §9).")
}

# ── D1: 결정 기록(rf_decisions.jsonl · kind="direction") + 텔레그램 [무인] 디렉터 (on_change) ──────────
dir_ledger_env <- function(code_root = DR_CODE_ROOT) {
  LED <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(suppressWarnings(
    sys.source(file.path(code_root, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = LED)))))
  LED
}
dir_self_sha <- function(code_root = DR_CODE_ROOT) tryCatch(unname(tools::md5sum(file.path(code_root, "02_Infrastructure/ops/rf_director.R"))), error = function(e) "")
# 판정 서명 — 이 문자열이 전일과 같으면 "변화 없음"(텔레그램 on_change 억제 · 같은 날 중복 기록 억제)
dir_signature <- function(out) paste(out$verdict$binding_condition, paste(unlist(out$verdict$co_binding %||% list()), collapse = "+"),
                                     out$recommendation$action, out$recommendation$rule, out$lever_health$overlay_B5$status,
                                     .chr(out$lever_health$L2$attempts_used), .chr(out$lever_health$L2$last_fr), sep = "|")
dir_record_decision <- function(out, cfg, root = DR_ROOT, LED = NULL) {
  LED <- LED %||% dir_ledger_env()
  today <- format(Sys.Date(), "%Y-%m-%d"); sig <- out$signature
  prev <- tryCatch(LED$rf_read_decisions(root, kind = "direction", day_prefix = today), error = function(e) list())
  if (any(vapply(prev, function(r) identical(.chr((r$scope %||% list())$signature), sig), logical(1))))
    return(list(recorded = FALSE, reason = "same_signature_today"))
  rec <- out$recommendation
  cands <- lapply(seq_along(rec$alternatives), function(i) { a <- rec$alternatives[[i]]
    list(id = .chr(a$action %||% "none"), rank = i, reason = .chr(a$why), features = list(unit = a$unit)) })
  ids <- vapply(cands, function(c) c$id, character(1))
  if (!(rec$action %in% ids)) cands <- c(list(list(id = rec$action, rank = 0L, reason = "decided", features = list(unit = rec$unit))), cands)
  chosen <- list(ids = list(rec$action), units = if (isTRUE(rec$executed) && !is.null(rec$unit)) list(rec$unit) else list(), executed = isTRUE(rec$executed))
  b <- out$program_best
  r <- tryCatch(LED$rf_record_decision("direction", "program", cands, chosen,
        rule = list(src = "02_Infrastructure/ops/rf_director.R::dir_rule_v0", version = rec$rule_version, branch = rec$rule, knobs = list(min_adversary_n = cfg$min_adversary_n, max_units_per_day = cfg$max_units_per_day)),
        policy = list(policy_id = "pi_dir_v0", policy_sha = dir_self_sha(), mode = if (isTRUE(cfg$act)) "live" else "advisory"),
        scope = list(signature = sig, run_mode = out$run_mode, binding = out$verdict$binding_condition, co_binding = out$verdict$co_binding,
                     program_best_sid = b$sid, program_best_port_t = b$port_t, program_best_calmar = b$calmar,
                     overlay_status = out$lever_health$overlay_B5$status, l2_attempts = out$lever_health$L2$attempts_used,
                     pool_n = out$pool_inventory$n_modules, proposals = rec$proposals),
        root = root), error = function(e) { message("[rf_director] 결정 기록 실패: ", conditionMessage(e)); NULL })
  if (is.null(r)) list(recorded = FALSE, reason = "write_failed") else list(recorded = TRUE, decision_id = r$decision_id)
}
# 절 규약(tg_agent_brief): bullet 은 항목 ≥2 · 1개면 summary(body) · 0개면 절 생략 — 실측 2026-09-21
.sec_list <- function(heading, items) {
  items <- as.character(items); items <- items[!is.na(items) & nzchar(items)]
  if (!length(items)) return(NULL)
  if (length(items) >= 2L) list(type = "bullet", heading = heading, items = items)
  else list(type = "summary", heading = heading, body = items[1])
}
dir_notify <- function(out, prev_sig, cfg, root = DR_ROOT, code_root = DR_CODE_ROOT) {
  changed <- !identical(out$signature, prev_sig); monday <- identical(format(Sys.Date(), "%u"), "1")
  why <- if (identical(cfg$telegram, "always")) "always" else if (identical(cfg$telegram, "off")) "" else if (changed) "changed" else if (monday) "monday_summary" else ""
  if (!nzchar(why)) return(list(sent = FALSE, reason = "unchanged"))
  v <- out$verdict; b <- out$program_best; ov <- out$lever_health$overlay_B5; l2 <- out$lever_health$L2; p <- out$pool_inventory; r <- out$recommendation
  co <- unlist(v$co_binding %||% list()); dd <- out$dd_episodes$recurring_class
  act_label <- switch(r$action, open_l2_unit = "2계층 단위(T/S/C)", directed_combination = "지시 결합", b5_context_only = "B5 컨텍스트만", proposal = "제안", none = "없음", r$action)
  secs <- list(
    list(type = "kv", heading = "현재 리서치 상황", kv = list(   # ★kv 절은 필드명이 `kv`(이름 있는 list) — `items` 가 아니다(rf_round_review.R:98 선례 · 실측 2026-09-21)
      "구속 조건" = sprintf("%s%s (%d/%d 계보)%s", v$binding_condition, if (length(co)) paste0("+", paste(co, collapse = "+")) else "", v$n_lineages_bound %||% 0L, v$n_lineages %||% 0L,
                        if (isTRUE(v$revenue_axes_met)) " · 수익 축 충족" else ""),
      "최고 계보" = sprintf("%s (%s) PORT_t %s · Calmar %s · MDD %s · CAGR %s · OOS %s", .chr(b$sid), .chr(b$grade), .f3(b$port_t), .f3(b$calmar), .pct(b$mdd), .pct(b$cagr), .f2(b$oos_retention)),
      "A 까지" = sprintf("Calmar %s → %s (MDD %s 유지 시 CAGR %s 필요)", .f3(b$calmar), .f2(out$thresholds$calmar_min), .pct(b$mdd), .pct((b$gap %||% list())$cagr_needed_at_mdd)),
      "낙폭 구조" = sprintf("%s · 깊이 중앙 %s · 고점→저점 %s개월 · 벤치 대비 %s배", .chr(dd$shape), .pct(dd$depth_median), .chr(dd$m_peak_trough_median), .f2(dd$ratio_median)))),
    .sec_list("레버 건강", c(
      sprintf("B5 오버레이: %s — 반증 pass %d / fail %d / 기타 %d (arm %d)", ov$status, ov$adv_pass, ov$adv_fail, ov$adv_other, ov$arms_measured),
      sprintf("블록순서 Calmar 규칙 발화 %d/%d entry", out$lever_health$block_order$entries_fired_calmar_rule, out$lever_health$block_order$entries),
      sprintf("2계층: %s · 최고 Calmar %s · 최고 PORT_t %s · 시도 %s회 · 풀 %s(직전 %s) · MC1 %s", paste(l2$grades, collapse = "/"), .f3(l2$best_calmar), .f3(l2$best_port_t),
              .chr(l2$attempts_used), .chr(l2$pool_n_now), .chr(l2$pool_n_at_last_run), if (isTRUE(l2$last_mc1_delivered)) "전달" else if (identical(l2$last_mc1_delivered, FALSE)) "미전달" else "?"),
      sprintf("결합: 요청 %s · 후보 %s · 최종 검토 %s", out$lever_health$combination$request_status, .chr(out$lever_health$combination$candidates_n), out$lever_health$combination$last_review_date))),
    .sec_list("풀 재고", c(
      sprintf("모듈 %s = floor %s + 방어형 %s + legacy A %s", .chr(p$n_modules), .chr(p$grade_floor_n), .chr(p$defensive_n), .chr(p$legacy_a_n)),
      sprintf("방어형 깊은낙폭 초과 중앙 %s%%/월 · 음수 %s · 생존 %s · defensive_score 필드 %s", .f2(p$defensive_deep_dd_excess_median), .pct(p$defensive_deep_dd_negative_share), .chr(p$n_surviving_binding_class), .chr(p$defensive_score_field_present)))),
    .sec_list("오늘 행동 · 대안", c(
      sprintf("권고 %s (%s) · 실행 %s — %s", act_label, r$rule, if (isTRUE(r$executed)) "예" else "아니오", .chr(r$execute_note)),
      vapply(r$alternatives, function(a) sprintf("대안 %s: %s", .chr(a$action), substr(.chr(a$why), 1, 110)), character(1)))),
    .sec_list("도훈 제안", vapply(r$proposals, function(x) substr(.chr(x), 1, 200), character(1))))
  secs <- Filter(Negate(is.null), secs)
  ok <- tryCatch({
    TG <- new.env(parent = globalenv())
    invisible(capture.output(suppressMessages(suppressWarnings(sys.source(file.path(code_root, "02_Infrastructure/telegram/telegram_notify.R"), envir = TG)))))
    res <- TG$tg_agent_brief(agent = "Q-Lead",
      title = sprintf("[무인] 디렉터 — 구속 %s · 권고 %s%s", v$binding_condition, act_label, if (identical(why, "monday_summary")) " (주간 요약)" else ""),
      sections = secs, lock_scope = sprintf("rf_director_%s", format(Sys.Date(), "%Y%m%d")),
      relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off")
    isTRUE(res$ok %||% TRUE)
  }, error = function(e) { message("[rf_director] 텔레그램 실패: ", conditionMessage(e)); FALSE })
  list(sent = ok, reason = why, dry_run = identical(Sys.getenv("QVEST_TG_DRY_RUN", ""), "1"))
}

# ── D3: 실행기 — director.act=true 일 때만 (a) 2계층 단위 요청 발행 (b) 지시 결합(결합 레인 --directed) (c) B5 컨텍스트 파일 ─────
dir_context_json <- function(out) list(
  as_of = out$as_of, binding = out$verdict$binding_condition, co_binding = out$verdict$co_binding,
  program_best = list(port_t = out$program_best$port_t, calmar = out$program_best$calmar, mdd = out$program_best$mdd, cagr = out$program_best$cagr),
  thresholds = list(calmar_min = out$thresholds$calmar_min, port_t_min = out$thresholds$port_t_min),
  recurring_class = out$dd_episodes$recurring_class,
  pool_inventory = list(defensive_n = out$pool_inventory$defensive_n, defensive_deep_dd_excess_median = out$pool_inventory$defensive_deep_dd_excess_median,
                        defensive_deep_dd_negative_share = out$pool_inventory$defensive_deep_dd_negative_share, n_surviving_binding_class = out$pool_inventory$n_surviving_binding_class),
  overlay = list(status = out$lever_health$overlay_B5$status, adv_pass = out$lever_health$overlay_B5$adv_pass,
                 n_verdict = out$lever_health$overlay_B5$adv_pass + out$lever_health$overlay_B5$adv_fail + out$lever_health$overlay_B5$adv_other))
# 지시 결합 재료 키: 프로그램 최고 계보의 논문들 + 깊은 낙폭 초과가 가장 큰 방어형 모듈의 논문 1편 (module_performance → module_catalog meta.paper_key)
dir_directed_keys <- function(out, root = DR_ROOT) {
  sid <- .chr(out$program_best$sid); bid <- sub(":.*$", "", sid)
  led <- .rj(file.path(root, "06_Registry/reinforce_ledger_l1.json")); e <- Filter(function(x) identical(x$base_id, bid), led$entries %||% list())
  pk <- if (length(e)) .chr(e[[1]]$paper_key) else ""
  if (!nzchar(pk)) return(NULL)
  lin_keys <- if (startsWith(pk, "combo:")) strsplit(sub("^combo:", "", pk), "+", fixed = TRUE)[[1]] else pk
  mp <- .rj(file.path(root, "06_Registry/module_performance.json")); cat <- .rj(file.path(root, "06_Registry/module_catalog.json"))
  num <- function(rs, pat) { x <- regmatches(rs, regexpr(pat, rs)); if (!length(x)) return(NA_real_); suppressWarnings(as.numeric(gsub("[^0-9.+-]", "", sub(pat, "\\1", x)))) }
  cands <- list()
  for (m in mp$modules %||% list()) if (identical(.chr(m$admission_route), "defensive_specialist")) {
    d <- num(.chr(m$admission_reason), "벤치-10% 이하 [0-9]+개: 초과 ([+-][0-9.]+)%"); if (!is.finite(d) || d <= 0) next
    cm <- (cat$modules %||% list())[[.chr(m$source_strategy_id)]]; key <- .chr(((cm %||% list())$meta %||% list())$paper_key)
    if (!nzchar(key) || startsWith(key, "combo:") || key %in% lin_keys) next
    cands[[length(cands) + 1L]] <- list(key = key, deep = d, sid = .chr(m$source_strategy_id)) }
  if (!length(cands)) return(list(keys = lin_keys, defensive = NULL, note = "깊은 낙폭 초과 양수 방어형 중 논문 키 해석 가능한 모듈 없음"))
  best <- cands[[which.max(vapply(cands, function(c) c$deep, numeric(1)))]]
  list(keys = c(lin_keys, best$key), defensive = best, note = "")
}
dir_execute <- function(rec, out, cfg, root = DR_ROOT, code_root = DR_CODE_ROOT) {
  rec$executed <- FALSE
  if (!isTRUE(cfg$act)) { rec$execute_note <- "director.act=false — 권고만(D0/D1)"; return(rec) }
  if (identical(rec$action, "open_l2_unit")) {
    L2 <- new.env(parent = globalenv()); sys.source(file.path(code_root, "02_Infrastructure/ops/rf_l2_lib.R"), envir = L2)
    cur <- L2$l2_request_read(root)
    if (!is.null(cur) && .chr(cur$status) %in% c("pending", "in_progress")) { rec$execute_note <- sprintf("L2 요청 슬롯 %s — 발행 안 함", .chr(cur$status)); return(rec) }
    u <- rec$unit
    req <- L2$l2_request_new(base_id = .chr(u$base_id), idea = .chr(u$idea), keyword_axis = .chr(u$axis), arms = as.character(unlist(u$arms)),
                             next_probe = c("T/S/C 결과로 배분기 hp(τ·k0·cap) 재캘리브 여부(풀 크기 기준)를 다음 attempt 로 사전 선언", "MC1 미전달이면 국면식별 축 설계 변경을 세션 과제로 제안"),
                             root_papers = list(), requested_by = "rf_director", note = sprintf("director %s · %s", .chr(rec$rule), .chr(out$verdict$note)))
    L2$l2_request_write(req, root)
    rec$executed <- TRUE; rec$unit$request_path <- L2$l2_request_path(root); rec$execute_note <- "l2_unit_request.json pending 발행 — tick 의 rf_l2_auto 가 집는다"
    return(rec)
  }
  if (identical(rec$action, "directed_combination")) {
    dk <- dir_directed_keys(out, root)
    if (is.null(dk) || is.null(dk$defensive)) { rec$execute_note <- sprintf("지시 결합 재료 해석 실패: %s", .chr((dk %||% list())$note %||% "최고 계보 paper_key 없음")); rec$unit$unreachable <- TRUE; return(rec) }
    rec$unit$keys <- dk$keys; rec$unit$defensive_sid <- dk$defensive$sid; rec$unit$defensive_deep_excess <- dk$defensive$deep
    old <- Sys.getenv("QVEST_RF_ROOT", unset = NA); Sys.setenv(QVEST_RF_ROOT = root); on.exit(if (is.na(old)) Sys.unsetenv("QVEST_RF_ROOT") else Sys.setenv(QVEST_RF_ROOT = old), add = TRUE)
    o <- tryCatch(suppressWarnings(system2("Rscript", c(shQuote(file.path(code_root, "02_Infrastructure/ops/rf_combination_launch.R")), sprintf("--directed=%s", paste(dk$keys, collapse = ","))),
                                           stdout = TRUE, stderr = TRUE, timeout = 180)), error = function(e) character(0))
    ev <- grep("^\\[combo\\] ", o, value = TRUE); last_ev <- if (length(ev)) sub("^\\[combo\\] ([a-z_]+).*$", "\\1", ev[length(ev)]) else "no_output"
    rq <- .rj(file.path(root, "06_Registry/replication_request.json"))
    issued <- !is.null(rq) && identical(.chr(rq$status), "pending") && identical(.chr(rq$source), "rf_combination_launch") && identical(.chr(rq$combo$setkey), paste(sort(unique(dk$keys)), collapse = "+"))
    rec$executed <- issued; rec$unit$launcher_event <- last_ev
    rec$execute_note <- if (issued) sprintf("지시 결합 요청 발행 setkey=%s", .chr(rq$combo$setkey)) else sprintf("결합 레인 미발행: %s", last_ev)
    if (!issued && identical(last_ev, "halt_directed_ineligible")) rec$unit$unreachable <- TRUE
    return(rec)
  }
  rec$execute_note <- sprintf("행동 없음(%s)", .chr(rec$action)); rec
}

.write_atomic <- function(txt, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- sprintf("%s.tmp.%d", path, Sys.getpid())
  writeLines(enc2utf8(txt), tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) { file.copy(tmp, path, overwrite = TRUE); unlink(tmp) }
  invisible(path)
}

dir_run <- function(root = DR_ROOT, code_root = DR_CODE_ROOT, dry = DR_DRY) {
  t0 <- Sys.time(); cfg <- dir_cfg(root)
  th  <- dir_thresholds(root, code_root)
  led <- .rj(file.path(root, "06_Registry/reinforce_ledger_l1.json")) %||% list(entries = list())
  cat <- .rj(file.path(root, "06_Registry/module_catalog.json")) %||% list(modules = list())
  B5  <- dir_b5lib(root, code_root)
  L   <- dir_top_lineages(led, cat, cfg$top_k, root)
  bind <- dir_binding(L, th)
  eps  <- dir_episodes(L, B5, cfg)
  ov   <- dir_lever_overlay(B5, cfg, root)
  bo   <- dir_lever_block_order(led)
  l2   <- dir_lever_l2(root)
  comb <- dir_lever_combination(led, root)
  pool <- dir_pool(root)
  unr  <- dir_unreachable(led)
  ages <- list(catalog_h = .age_h(file.path(root, "06_Registry/module_catalog.json")),
               ledger_h  = .age_h(file.path(root, "06_Registry/reinforce_ledger_l1.json")),
               pool_d    = { g <- suppressWarnings(as.Date(.chr(pool$generated))); if (is.na(g)) NA_real_ else as.numeric(Sys.Date() - g) })
  stale <- (is.finite(ages$pool_d) && ages$pool_d > cfg$stale_pool_days) || (is.finite(ages$catalog_h) && ages$catalog_h > cfg$stale_catalog_hours)
  l2req <- dir_l2_request(root)
  rec <- dir_rule_v0(bind$verdict, ov, l2, comb, pool, cfg, dir_decisions_today(root), stale, l2req)
  best <- if (length(bind$lineages)) bind$lineages[[1]] else list()
  out <- list(schema = "rf_director_v0", as_of = format(t0, "%Y-%m-%dT%H:%M:%S%z"), run_mode = if (DR_UNATT) "unattended" else "manual",
              runtime_s = NA_real_, dry_run = dry, inputs_age = ages, inputs_stale = stale, thresholds = th, config = cfg,
              program_best = best, lineages = bind$lineages, verdict = bind$verdict, dd_episodes = eps,
              lever_health = list(overlay_B5 = ov, block_order = bo, L2 = c(l2, list(unit_request = l2req)), combination = comb,
                                  lever_1_asymmetric = list(status = "unmeasured", source = "CLAUDE.md 조건-안 레버 프론티어 ①")),
              pool_inventory = pool, unreachable = unr, recommendation = rec)
  out$boot_line <- dir_boot_line(bind$verdict, best, ov, l2, rec)
  out$signature <- dir_signature(out)
  cache_p <- file.path(root, ".cache/rf_director_latest.json")
  prev_sig <- .chr((.rj(cache_p) %||% list())$signature)      # 덮어쓰기 전에 전일 서명을 읽는다(on_change 판정)
  out$runtime_s <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  .js <- function(o) toJSON(o, auto_unbox = TRUE, null = "null", na = "null", digits = 6, pretty = TRUE)
  if (dry) { cat(.js(out), "\n"); cat("\n[rf_director] DRY — 쓰기 0\n") }
  else {
    out$recommendation <- dir_execute(out$recommendation, out, cfg, root, code_root)     # D3 — act=false 면 권고만
    .write_atomic(.js(out), cache_p)
    .write_atomic(dir_map_md(out), file.path(root, "06_Registry/layer_bottleneck_map.md"))
    .write_atomic(.js(dir_context_json(out)), file.path(root, ".cache/rf_director_context.json"))   # D3 (c) — B5 재료가 읽는 숫자 컨텍스트(항상)
    cat(sprintf("[rf_director] wrote .cache/rf_director_latest.json + 06_Registry/layer_bottleneck_map.md + rf_director_context.json (%.1fs) · executed=%s\n",
                out$runtime_s, isTRUE(out$recommendation$executed)))
    # D1 — 결정 기록(같은 날 같은 서명이면 1회) · 텔레그램(무인/--notify 일 때만 · on_change)
    out$decision <- dir_record_decision(out, cfg, root)
    out$telegram <- if (DR_UNATT || "--notify" %in% ARGS) dir_notify(out, prev_sig, cfg, root, code_root) else list(sent = FALSE, reason = "manual_run")
    .write_atomic(.js(out), cache_p)
    cat(sprintf("[rf_director] decision %s · telegram %s\n", if (isTRUE(out$decision$recorded)) out$decision$decision_id else out$decision$reason,
                if (isTRUE(out$telegram$sent)) paste0("sent(", out$telegram$reason, if (isTRUE(out$telegram$dry_run)) "·dry" else "", ")") else out$telegram$reason))
  }
  cat(out$boot_line, "\n")
  invisible(out)
}

if (!identical(Sys.getenv("QVEST_DIRECTOR_NO_MAIN"), "1")) {
  rc <- tryCatch({ dir_run(); 0L }, error = function(e) {
    message("[rf_director] FATAL: ", conditionMessage(e))
    p <- file.path(DR_ROOT, ".cache/rf_director_latest.json")
    if (!DR_DRY && file.exists(p)) tryCatch({ j <- fromJSON(p, simplifyVector = FALSE); j$stale <- TRUE; j$stale_reason <- conditionMessage(e)
      .write_atomic(toJSON(j, auto_unbox = TRUE, null = "null", na = "null", digits = 6, pretty = TRUE), p) }, error = function(e2) NULL)
    1L })
  quit(status = rc)
}
