#!/usr/bin/env Rscript
#==============================================================================
# rf_b5_design_lib.R — B5(리스크 오버레이) 블록 **매 강화 사이클 LLM 자체 설계** 레인의 재료·가드·검증 (v10.5 2026-09-17)
#
# 도훈 지시 2026-09-17:
#   "매 강화 사이클마다 LLM 이 해당 강화 프로세스와 전체 리서치 아키텍처에 축적된 지식 기반으로 오버레이를 자체 설계"
#   + "오버레이 한 칸에 여러 오버레이 중첩" + "오버레이층만 무한대로 탐색하는 버그 방지" + "오버레이 적대적 검증부".
#
# 무엇을 바꾸나:
#   구판 B5 는 (a) 앞 블록 기전 에이전트가 낸 next_block_design(rf_block_design) 또는 (b) 규칙 선정(rf_overlay_arms)이 채웠고,
#   새 arm 은 별도 일간 레인(rf_overlay_propose · 하루 1건 · 성과 무열람)이 기전 지도의 빈 칸을 겨눠 만들었다.
#   이제 B5 진입 시 **설계 에이전트 1회**가 (1) 이 entry 의 측정표·바닥 낙폭 해부·앞선 논문 B5 교훈·증류 지식·arm 성과 이력을 읽고
#   (2) 기존 활성 arm 을 **스택**(≤ max_layers 층 · 엔진은 층 노출을 종목별 곱으로 합성)으로 배합한 칸과
#   (3) 필요하면 **새 arm 몇 개**(≤ max_new_arms)를 함께 낸다. 새 arm 은 probe(기계 6검사) → G1 적대 감사(다른 모델) → 등재(R) 를
#   통과한 것만 설계에 남고, 측정 뒤엔 G2 사후 반증(rf_overlay_adversary)이 pass 인 칸만 소비된다.
#
# 경계 (구조로 강제 — LLM 은 제안만 한다):
#   ① 산출은 설계 JSON 하나 + arm 파일(overlay_arms/<kind>.R · .arm.json). 카탈로그·원장·최종 설계는 **R 이** 쓴다.
#   ② 설계 칸은 카탈로그 **active** id 만 · 상주 칸(pg2_risk_overlay_v1 · B5_31)은 절대 포함 금지(상주가 매 세대 따로 잰다).
#   ③ 검증 실패 = 기존 기전 설계 보존 + design_fallback(조용한 통과 없음) · 라운드는 fallback=true 로 기록된다.
#   ④ 방출 정직성: probe/감사/할당 초과로 **등재 전** 거부된 arm 도 원장(overlay_arm_ledger.jsonl)에 admitted=false 로 남는다.
#
# ★오버레이층 무한 탐색 방지 — 가드 H1~H8 (모든 판정은 jlog overlay_guard_<name> 으로 남긴다 · 침묵 없음):
#   H1 entry 당 자동 설계 1회(round 1 기록이 있으면 skip) · 수동 재설계 ≤ guards.max_redesign_rounds
#   H2 새 arm 사이클당 ≤ max_new_arms · 오늘 source=b5_design 방출 ≤ guards.daily_arm_cap(원장 집계 = rf_overlay_ledger_count.py)
#   H3 정체: 최근 guards.stagnation_window 라운드(전 entry · 시각순)가 모두 새 arm 을 냈는데 그 arm 중 어느 것도
#      G2 pass(attempt$adversary$verdict=="pass") 칸의 자기 층에 없다 → compose_only(기존 arm 배합만)
#   H4 활성 생성 arm(source∈{b5_design,overlay_propose} 또는 kind gen_/b5gen_) > guards.max_active_generated → compose_only
#   H5 설계 크기: 라운드당 ≤ max_cells · ≥ min_cells(미달 = 폴백) · 스택 ≤ max_layers · 총 ≤ 15(B5_16..B5_30)
#   H6 상주 칸 제외 · 스택 중복(정렬 id 키) 금지 · active arm 만 (rfbd_verify 재도출)
#   H7 방출 정직성(위 ④) · H8 폴백 무성 금지(위 ③)
#
# 루트 2층 (b1 lib 규약): 데이터 루트 ROOT = QVEST_RF_ROOT > QM_ROOT · 코드 루트 = 이 파일의 위치(self-first).
#   ★자식 Rscript 는 ~/.Renviron 의 QM_ROOT 가 상속값을 **덮는다**(2026-09-17 실사고: 검사 자식이 운영 원장에 썼다) —
#     샌드박스 호출자는 R_ENVIRON_USER 를 빈 파일로 물려야 한다(rf_b5_design.sh 가 QVEST_RF_ROOT 있을 때 자동으로 한다).
#
# 사용:
#   Rscript rf_b5_design_lib.R active_entry
#   Rscript rf_b5_design_lib.R next_is_b5 <base_id>                      → 1/0
#   Rscript rf_b5_design_lib.R guards <base_id> <auto|redesign> <out.json>
#   Rscript rf_b5_design_lib.R materials <base_id> <out.txt> <compose_only 0|1> <arm_quota> <round>
#   Rscript rf_b5_design_lib.R probe <kind>                               → 0 pass · 3 fail (마지막 줄 probe: …)
#   Rscript rf_b5_design_lib.R record_emission <kind> <action> <state> <model> <n_siblings> <stage> <reason>
#   Rscript rf_b5_design_lib.R verify <base_id> <lane_design.json> <round> <compose_only 0|1> <admitted_csv> <rejected_csv>
#   Rscript rf_b5_design_lib.R claim <claim_dir> <owner_pid> <stale_hours> / release <claim_dir>
#   Rscript rf_b5_design_lib.R outcomes <out.csv>
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- { .r <- Sys.getenv("QVEST_RF_ROOT", "")
          if (nzchar(.r)) .r else Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot") }
ROOT <- sub("/+$", "", gsub("\\", "/", ROOT, fixed = TRUE))

## ★코드 루트는 데이터 루트가 아니다 — 자기 라이브러리는 **자기 위치**에서 읽는다(self-first · b1 lib 규약).
##   Rscript --file= 이면 그 경로, source() 되면 ofile, 둘 다 없으면 QVEST_B5_CODE_ROOT > QM_ROOT. (normalizePath 금지 — 한글 경로 파손)
.b5_self_path <- function() {
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a)) return(sub("^--file=", "", a[1]))
  for (i in rev(seq_len(sys.nframe()))) {
    of <- tryCatch(get0("ofile", envir = sys.frame(i), inherits = FALSE), error = function(e) NULL)
    if (is.character(of) && length(of) == 1L && grepl("rf_b5_design_lib", of)) return(of)
  }
  ""
}
.CODE_ROOT <- local({
  ov <- Sys.getenv("QVEST_B5_CODE_ROOT", "")
  if (nzchar(ov)) return(sub("/+$", "", gsub("\\", "/", ov, fixed = TRUE)))
  sp <- gsub("\\", "/", .b5_self_path(), fixed = TRUE)
  if (nzchar(sp) && file.exists(sp)) {
    d <- dirname(sp)                                  # …/02_Infrastructure/ops
    cr <- sub("/02_Infrastructure/ops/?$", "", d)
    if (file.exists(file.path(cr, "02_Infrastructure/reinforcement/rf_block_design.R"))) return(cr)
  }
  sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
})
.b5_lib <- function(rel) file.path(.CODE_ROOT, rel)
.b5_py  <- function() {
  p <- Sys.getenv("QVEST_PY", "")
  if (nzchar(p) && file.exists(p)) return(p)
  v <- file.path(.CODE_ROOT, ".venv_qvest_ml/Scripts/python.exe")
  if (file.exists(v)) v else "python"
}
## 의존 모듈 — 정본에서만 (복제 금지). rf_mechanism_map.R 은 .ov_own_layers/rfbd_standing_picks 가 이미 있으면 재적재하지 않는다.
##   순서: rf_claim(평범한 %||%) → rf_spec_sig → rf_block_design → rf_mechanism_map → reinforce_ledger(NA 도 NULL 로 보는 %||% 가 최종).
invisible(capture.output(suppressMessages({
  source(.b5_lib("02_Infrastructure/ops/rf_claim.R"))
  source(.b5_lib("02_Infrastructure/reinforcement/rf_spec_sig.R"))
  source(.b5_lib("02_Infrastructure/reinforcement/rf_block_design.R"))
  source(.b5_lib("02_Infrastructure/reinforcement/rf_mechanism_map.R"))
  source(.b5_lib("02_Infrastructure/reinforcement/reinforce_ledger.R"))
})))

## ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04 규약: 검사 픽스처가 운영 로그를 오염시켰다)
.b5_jlog_path <- function() Sys.getenv("QVEST_RP_JLOG", file.path(ROOT, ".cache/reinforce_auto_log.jsonl"))
.b5_log <- function(event, ...) {
  p <- .b5_jlog_path(); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "b5_design"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = p, append = TRUE)
  cat(sprintf("[b5_design] %s\n", event))
}
.num <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA_real_)); if (length(v)) v[1] else NA_real_ }
.chr <- function(x) { v <- suppressWarnings(as.character(x %||% "")); v <- v[!is.na(v)]; if (length(v)) v[1] else "" }
.cap <- function(x, n) { x <- .chr(x); if (nchar(x) > n) paste0(substr(x, 1L, n), "…") else x }
.f3 <- function(x) { v <- .num(x); if (is.finite(v)) formatC(v, digits = 3, format = "f") else "NA" }

# ── 설정 ─────────────────────────────────────────────────────────────────────
B5_DEFAULTS <- list(enabled = TRUE, max_cells = 8L, min_cells = 3L, max_new_arms = 3L, max_layers = 3L, prior_entries = 12L,
                    guards = list(max_redesign_rounds = 1L, daily_arm_cap = 6L, stagnation_window = 2L, max_active_generated = 40L))
.b5_cfg_path <- function(root = ROOT) Sys.getenv("QVEST_RF_CONFIG", file.path(root, "06_Registry/reinforce_auto_config.json"))
b5_cfg <- function(root = ROOT) {
  cfg <- tryCatch(fromJSON(.b5_cfg_path(root), simplifyVector = FALSE), error = function(e) list())
  b <- cfg$b5_design %||% list()
  out <- B5_DEFAULTS
  for (k in setdiff(names(B5_DEFAULTS), "guards")) if (!is.null(b[[k]])) out[[k]] <- b[[k]]
  for (k in names(B5_DEFAULTS$guards)) if (!is.null((b$guards %||% list())[[k]])) out$guards[[k]] <- b$guards[[k]]
  for (k in c("max_cells", "min_cells", "max_new_arms", "max_layers", "prior_entries")) {
    v <- suppressWarnings(as.integer(out[[k]])); out[[k]] <- if (length(v) == 1L && !is.na(v) && v >= 0L) v else B5_DEFAULTS[[k]] }
  for (k in names(B5_DEFAULTS$guards)) {
    v <- suppressWarnings(as.integer(out$guards[[k]])); out$guards[[k]] <- if (length(v) == 1L && !is.na(v) && v >= 0L) v else B5_DEFAULTS$guards[[k]] }
  out$enabled <- isTRUE(out$enabled)
  out
}

# ── 경로 ─────────────────────────────────────────────────────────────────────
b5_design_dir  <- function(root, base_id) file.path(root, ".cache/rf_b5_design", base_id)
b5_lane_design <- function(root, base_id, round) file.path(b5_design_dir(root, base_id), sprintf("design_r%d.json", as.integer(round)))
b5_final_path  <- function(root, base_id) rfbd_path(root, base_id, "B5")     # 러너가 읽는 정본 위치(rf_block_design)
.b5_atomic_write <- function(txt, p) {
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(p, ".tmp"); write(txt, tmp)
  ok <- suppressWarnings(file.rename(tmp, p))
  if (!ok) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
  invisible(p)
}

# ── 원장 ─────────────────────────────────────────────────────────────────────
.b5_ledger <- function(root = ROOT) tryCatch(rf_load(1L, root), error = function(e) NULL)
.b5_entry  <- function(root, base_id) {
  led <- .b5_ledger(root); if (is.null(led)) return(NULL)
  for (e in led$entries %||% list()) if (identical(as.character(e$base_id), base_id)) return(e)
  NULL
}
b5_active_entry <- function(root = ROOT) {
  led <- .b5_ledger(root); if (is.null(led)) return(NULL)
  a <- Filter(function(e) identical(e$status, "active"), led$entries %||% list())
  if (length(a)) a[[1]] else NULL
}
.b5_measured <- function(a) is.list(a$essence) && is.finite(.num(a$essence$port_t))
.b5_codes    <- function(atts) vapply(atts %||% list(), .rf_attempt_code, character(1))

#' 블록 칸 수 — 설계 파일이 있으면 그 칸 수(B1 = rf_b1_design · B2/B3/B5 = rf_block_design), 없으면 격자 칸 수.
#'   ★rf_b1_design_lib.R 은 source 시 자기 CLI 블록이 이 프로세스의 commandArgs 를 읽고 실행해 버리므로 적재하지 않는다 —
#'     경로 규약(.cache/rf_b1_design/<base_id 앞 60자>.json · rf_b1_design_cells 정의부)만 여기서 읽는다.
.b5_grid_n <- function(root, block) {
  g <- tryCatch(fromJSON(file.path(root, "06_Registry/reinforce_program.json"), simplifyVector = FALSE), error = function(e) NULL)
  for (b in g$blocks %||% list()) if (identical(as.character(b$id), block)) return(length(b$cells %||% list()))
  5L
}
.b5_block_n_cells <- function(root, E, block) {
  bid <- as.character(E$base_id)
  if (identical(block, "B1")) {
    dp <- file.path(root, ".cache/rf_b1_design", sprintf("%s.json", substr(bid, 1, 60)))
    D <- if (file.exists(dp)) tryCatch(fromJSON(dp, simplifyVector = FALSE), error = function(e) NULL) else NULL
    n <- length(D$cells %||% list()); return(if (n > 0L) n else .b5_grid_n(root, "B1"))
  }
  if (block %in% RFBD_BLOCKS && file.exists(rfbd_path(root, bid, block))) {
    n <- length(tryCatch(rfbd_cells(root, bid, block), error = function(e) NULL) %||% list())
    if (n > 0L) return(n)
  }
  .b5_grid_n(root, block)
}

#' 다음 블록이 B5 인가 — 자동 설계의 발화 조건.
#'   TRUE ⇔ entry active ∧ block_order 기록됨 ∧ B5 시도 0 ∧ block_order 에서 B5 앞의 모든 블록이 **완전 측정**
#'   (그 블록 칸 수만큼 서로 다른 셀 코드가 측정 또는 terminal 로 닫혔고, 미결(pending) 시도가 없다).
#'   ★block_order 는 러너가 B1 배치 종료 뒤 **다음 배치 직전**에 기록한다(rf_record_block_order · 덮어쓰기 금지) —
#'     기록 전에는 어느 순서로 갈지 원장만으로 확정되지 않으므로 발화하지 않는다(러너 배선이 순서를 보장한다).
b5_next_block_is_b5 <- function(E, root = ROOT) {
  if (is.null(E) || !identical(E$status, "active")) return(FALSE)
  ord <- as.character(unlist(E$block_order %||% list())); ord <- ord[nzchar(ord)]
  if (!length(ord) || !("B5" %in% ord)) return(FALSE)
  atts <- E$attempts %||% list()
  codes <- .b5_codes(atts)
  if (any(!is.na(codes) & startsWith(codes, "B5_"))) return(FALSE)
  before <- ord[seq_len(match("B5", ord) - 1L)]
  for (b in before) {
    idx <- which(!is.na(codes) & startsWith(codes, paste0(b, "_")))
    done <- unique(codes[idx][vapply(atts[idx], function(a) .b5_measured(a) || isTRUE(a$terminal), logical(1))])
    pend <- any(vapply(atts[idx], function(a) !.b5_measured(a) && !isTRUE(a$terminal), logical(1)))
    if (pend || length(done) < .b5_block_n_cells(root, E, b)) return(FALSE)
  }
  TRUE
}

# ── arm 성과 이력 (전 L1 entry) ─────────────────────────────────────────────
.b5_catalog <- function(root = ROOT) {
  d <- tryCatch(fromJSON(file.path(root, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE), error = function(e) NULL)
  d$arms %||% list()
}
.b5_kind_to_id <- function(arms) { m <- vapply(arms, function(a) .chr(a$id), character(1)); names(m) <- vapply(arms, function(a) .chr(a$kind), character(1)); m }
.b5_layer_id <- function(o, k2i) {   # arm_id 없는 층은 kind 로 카탈로그 id 를 되찾는다 — 그것도 없으면 kind
  aid <- .chr(o$arm_id); if (nzchar(aid)) return(aid)
  knd <- .chr(o$kind); if (nzchar(knd) && knd %in% names(k2i) && nzchar(k2i[[knd]])) return(k2i[[knd]])
  knd
}
.b5_own_ids <- function(S, carry_ov, k2i) {
  own <- .ov_own_layers(S, carry = carry_ov)
  ids <- unique(vapply(own, .b5_layer_id, character(1), k2i = k2i))
  list(ids = ids[nzchar(ids)], n_layers = length(own))
}

#' arm id 별 성과 이력 — 전 L1 entry 의 B5 자기 층(overlay_cell > overlay − carry)을 모아
#'   Δ = 그 칸 − **같은 entry 의 B1 시도 중앙값**(MDD·CAGR·PORT_t·Calmar) 을 arm 별 중앙값으로 접는다.
#'   ★부호: ΔMDD < 0 = 낙폭이 줄었다 · ΔCalmar > 0 = 개선. B1 기준이 없는 entry 는 Δ 를 정의할 수 없어 뺀다.
#'   adv_pass/adv_fail = 그 칸의 G2 사후 반증 verdict 집계(rf_record_adversary). 상주 arm 은 뺀다(상주 칸은 별도 측정).
#' @return data.table(arm_id, uses, stacked_uses, n_entries, med_d_mdd, med_d_cagr, med_d_port_t, med_d_calmar, adv_pass, adv_fail, adv_other)
rf_overlay_outcomes <- function(root = ROOT) {
  empty <- data.table(arm_id = character(), uses = integer(), stacked_uses = integer(), n_entries = integer(),
                      med_d_mdd = numeric(), med_d_cagr = numeric(), med_d_port_t = numeric(), med_d_calmar = numeric(),
                      adv_pass = integer(), adv_fail = integer(), adv_other = integer())
  led <- .b5_ledger(root); if (is.null(led)) return(empty)
  standing <- tryCatch(rfbd_standing_picks(root), error = function(e) character(0))
  k2i <- .b5_kind_to_id(.b5_catalog(root))
  rows <- list()
  for (e in led$entries %||% list()) {
    atts <- Filter(.b5_measured, e$attempts %||% list())
    if (!length(atts)) next
    codes <- .b5_codes(atts)
    b1 <- atts[!is.na(codes) & startsWith(codes, "B1_")]
    if (!length(b1)) next
    med <- function(f) stats::median(vapply(b1, function(a) .num(a$essence[[f]]), numeric(1)), na.rm = TRUE)
    m_mdd <- med("mdd"); m_cagr <- med("cagr"); m_pt <- med("port_t"); m_cl <- med("calmar")
    carry_ov <- (e$carry %||% list())$overlay
    for (a in atts) {
      sp <- .chr(a$essence$spec); if (!nzchar(sp) || !file.exists(sp)) next
      S <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL); if (is.null(S)) next
      o <- .b5_own_ids(S, carry_ov, k2i); ids <- setdiff(o$ids, standing)
      if (!length(ids)) next
      adv <- .chr((a$adversary %||% list())$verdict)
      for (id in ids) rows[[length(rows) + 1L]] <- data.table(
        arm_id = id, base_id = .chr(e$base_id), stacked = o$n_layers > 1L,
        d_mdd = .num(a$essence$mdd) - m_mdd, d_cagr = .num(a$essence$cagr) - m_cagr,
        d_port_t = .num(a$essence$port_t) - m_pt, d_calmar = .num(a$essence$calmar) - m_cl, adv = adv)
    }
  }
  if (!length(rows)) return(empty)
  R <- rbindlist(rows, fill = TRUE)
  out <- R[, .(uses = .N, stacked_uses = sum(stacked), n_entries = uniqueN(base_id),
               med_d_mdd = stats::median(d_mdd, na.rm = TRUE), med_d_cagr = stats::median(d_cagr, na.rm = TRUE),
               med_d_port_t = stats::median(d_port_t, na.rm = TRUE), med_d_calmar = stats::median(d_calmar, na.rm = TRUE),
               adv_pass = sum(adv == "pass"), adv_fail = sum(adv == "fail"),
               adv_other = sum(nzchar(adv) & !(adv %in% c("pass", "fail")))), by = arm_id]
  setorderv(out, "med_d_calmar", -1L, na.last = TRUE)
  out[]
}
b5_pass_arm_ids <- function(root = ROOT) { o <- rf_overlay_outcomes(root); if (!nrow(o)) character(0) else as.character(o[adv_pass > 0L]$arm_id) }

# ── 가드 H1~H4 ───────────────────────────────────────────────────────────────
.b5_rounds_of <- function(E) { r <- (E$b5_design %||% list())$rounds %||% list(); Filter(is.list, r) }
.b5_all_rounds <- function(led) {
  rows <- list()
  for (e in led$entries %||% list()) for (r in .b5_rounds_of(e)) {
    ids <- as.character(unlist(r$new_arm_ids %||% list())); ids <- ids[nzchar(ids)]
    rows[[length(rows) + 1L]] <- data.table(base_id = .chr(e$base_id), round = as.integer(.num(r$round)), at = .chr(r$at),
                                            n_new = as.integer(.num(r$new_arms_admitted %||% length(ids))), ids = list(ids))
  }
  if (!length(rows)) return(data.table(base_id = character(), round = integer(), at = character(), n_new = integer(), ids = list()))
  rbindlist(rows)
}
#' 오늘 source=b5_design 방출 수 — 정본 집계기(rf_overlay_ledger_count.py)를 태운다(인라인 사본 금지). 실패 = NA(호출자가 fail-closed).
.b5_count_today <- function(root = ROOT, day = format(Sys.Date(), "%Y-%m-%d")) {
  led <- file.path(root, "06_Registry/overlay_arm_ledger.jsonl")
  if (!file.exists(led)) return(0L)
  out <- tryCatch(suppressWarnings(system2(.b5_py(), c(shQuote(.b5_lib("02_Infrastructure/ops/rf_overlay_ledger_count.py")),
                                                        shQuote(led), day, "b5_design"), stdout = TRUE, stderr = FALSE)),
                  error = function(e) NULL)
  v <- suppressWarnings(as.integer(trimws(gsub("\r", "", as.character(out %||% character(0))))))
  v <- v[!is.na(v)]; if (length(v)) v[1] else NA_integer_
}
.b5_n_active_generated <- function(root = ROOT) {
  arms <- .b5_catalog(root)
  sum(vapply(arms, function(a) identical(.chr(a$status), "active") &&
               (.chr(a$source) %in% c("b5_design", "overlay_propose") || grepl("^(gen_|b5gen_)", .chr(a$kind))), logical(1)))
}

#' 가드 판정 — 모든 결정을 jlog 에 남긴다(overlay_guard_<name>). 거부(ok=FALSE)면 레인은 LLM 을 부르지 않는다.
#' @return list(ok, refuse_reason, mode, round, compose_only, compose_reasons, arm_quota, n_today, n_active_generated)
b5_guards <- function(E, root = ROOT, cfg = b5_cfg(root), mode = c("auto", "redesign")) {
  mode <- match.arg(mode); g <- cfg$guards; bid <- .chr(E$base_id)
  rounds <- .b5_rounds_of(E); rn <- vapply(rounds, function(r) as.integer(.num(r$round)), integer(1))
  out <- list(ok = TRUE, refuse_reason = "", mode = mode, round = 1L, compose_only = FALSE, compose_reasons = character(0),
              arm_quota = cfg$max_new_arms, n_today = NA_integer_, n_active_generated = NA_integer_)
  # H1 — entry 당 자동 설계 1회 · 수동 재설계 상한
  if (mode == "auto") {
    if (any(rn == 1L, na.rm = TRUE)) {
      .b5_log("overlay_guard_h1_once", base_id = bid, mode = mode, decision = "refuse", why = "round 1 이미 기록(entry 당 자동 설계 1회)")
      out$ok <- FALSE; out$refuse_reason <- "h1_already_designed"; return(out) }
    out$round <- 1L
    .b5_log("overlay_guard_h1_once", base_id = bid, mode = mode, decision = "pass", round = 1L)
  } else {
    n_re <- sum(rn >= 2L, na.rm = TRUE)
    if (n_re >= g$max_redesign_rounds) {
      .b5_log("overlay_guard_h1_once", base_id = bid, mode = mode, decision = "refuse",
              why = sprintf("재설계 %d회 ≥ 상한 %d(guards.max_redesign_rounds)", n_re, g$max_redesign_rounds))
      out$ok <- FALSE; out$refuse_reason <- "h1_max_redesign_rounds"; return(out) }
    out$round <- max(c(1L, rn), na.rm = TRUE) + 1L
    .b5_log("overlay_guard_h1_once", base_id = bid, mode = mode, decision = "pass", round = out$round, prior_redesigns = n_re)
  }
  # H2 — 사이클당 새 arm 상한 ∧ 일간 상한(원장 집계 · 실패 = fail-closed 0)
  n_today <- .b5_count_today(root); out$n_today <- n_today
  quota <- if (is.na(n_today)) 0L else min(cfg$max_new_arms, g$daily_arm_cap - n_today)
  quota <- max(0L, as.integer(quota)); out$arm_quota <- quota
  .b5_log("overlay_guard_h2_quota", base_id = bid, decision = if (quota > 0L) "pass" else "compose_only",
          n_today = if (is.na(n_today)) "counter_failed" else n_today, daily_arm_cap = g$daily_arm_cap,
          max_new_arms = cfg$max_new_arms, arm_quota = quota)
  if (quota <= 0L) { out$compose_only <- TRUE; out$compose_reasons <- c(out$compose_reasons, if (is.na(n_today)) "h2_counter_failed" else "h2_quota") }
  # H3 — 정체: 최근 window 라운드가 전부 새 arm 을 냈는데 G2 pass 가 하나도 없다
  led <- .b5_ledger(root); allr <- if (is.null(led)) .b5_all_rounds(list()) else .b5_all_rounds(led)
  if (nrow(allr)) { setorderv(allr, "at"); last <- utils::tail(allr, g$stagnation_window) } else last <- allr
  h3 <- FALSE; ids3 <- character(0); pass3 <- character(0)
  if (g$stagnation_window > 0L && nrow(last) == g$stagnation_window && all(last$n_new > 0L)) {
    ids3 <- unique(unlist(last$ids)); pass3 <- b5_pass_arm_ids(root)
    h3 <- length(ids3) > 0L && !any(ids3 %in% pass3)
  }
  .b5_log("overlay_guard_h3_stagnation", base_id = bid, decision = if (h3) "compose_only" else "pass",
          window = g$stagnation_window, rounds_seen = nrow(last), recent_arms = paste(ids3, collapse = ","),
          recent_arms_passed = paste(intersect(ids3, pass3), collapse = ","))
  if (h3) { out$compose_only <- TRUE; out$compose_reasons <- c(out$compose_reasons, "h3_stagnation") }
  # H4 — 활성 생성 arm 상한
  nag <- .b5_n_active_generated(root); out$n_active_generated <- nag
  h4 <- nag > g$max_active_generated
  .b5_log("overlay_guard_h4_active_generated", base_id = bid, decision = if (h4) "compose_only" else "pass",
          n_active_generated = nag, max_active_generated = g$max_active_generated)
  if (h4) { out$compose_only <- TRUE; out$compose_reasons <- c(out$compose_reasons, "h4_active_generated") }
  if (out$compose_only) out$arm_quota <- 0L
  out
}

# ── 날짜 제거 — 설계자는 특정 시기를 알면 안 된다(사후 지식 = 달력 리터럴의 씨앗) ─────────
#'   식별자(RP_20260917_… · L-RF-20260905_… · arXiv 2002.06975 · v10.4 · 소수 0.2008)는 보존한다.
B5_DATE_RULES <- c(
  iso_date = "(?<![\\w.])(19[89]\\d|20[0-3]\\d)-(0[1-9]|1[0-2])(-(0[1-9]|[12]\\d|3[01]))?(?![\\w])",
  slash    = "(?<![\\w.])(19[89]\\d|20[0-3]\\d)/(0?[1-9]|1[0-2])(/\\d{1,2})?(?![\\w])",
  dot_ym   = "(?<![\\w.])(19[89]\\d|20[0-3]\\d)\\.(0[1-9]|1[0-2])(?![\\d\\w])",
  kor      = "(?<![\\w.])(19[89]\\d|20[0-3]\\d)년(\\s?(0?[1-9]|1[0-2])월)?",
  bare_yr  = "(?<![\\w.\\-/])(19[89]\\d|20[0-3]\\d)(?![\\w.\\-/])")
b5_strip_dates <- function(x) {
  for (nm in names(B5_DATE_RULES))
    x <- gsub(B5_DATE_RULES[[nm]], if (nm == "bare_yr") "<yr>" else "<date>", x, perl = TRUE)
  x
}
b5_has_dates <- function(x) any(vapply(B5_DATE_RULES, function(rx) any(grepl(rx, x, perl = TRUE)), logical(1)))

# ── 바닥 낙폭 해부 (날짜 없음) ───────────────────────────────────────────────
#' floor = 측정된 시도 중 PORT_t 최고 칸. 산출물 02_nav.csv(nav_net) 의 낙폭 에피소드 상위 3 을 깊이·고점→저점 개월·수중 개월·회복 개월로,
#'   같은 창(고점일~저점일)의 KOSPI200(05_benchmark_returns.csv benchmark_nav) 점대점 낙폭과 그 비를 붙인다. 날짜는 내지 않는다.
.b5_months_between <- function(d1, d2) { if (is.na(d1) || is.na(d2)) return(NA_real_); round(as.numeric(difftime(d2, d1, units = "days")) / 30.44, 1) }
b5_drawdown_episodes <- function(nav, dates, bnav = NULL, top = 3L) {
  ok <- is.finite(nav) & !is.na(dates); nav <- nav[ok]; dates <- dates[ok]; if (!is.null(bnav)) bnav <- bnav[ok]
  n <- length(nav); if (n < 3L) return(list())
  cm <- cummax(nav); dd <- 1 - nav / cm
  under <- dd > 1e-12
  eps <- list(); i <- 1L
  while (i <= n) {
    if (!under[i]) { i <- i + 1L; next }
    j <- i; while (j <= n && under[j]) j <- j + 1L      # [i, j-1] 수중 · j = 회복(있으면)
    peak <- max(1L, i - 1L); seg <- i:(j - 1L); trough <- seg[which.max(dd[seg])]
    rec <- if (j <= n) j else NA_integer_
    bdep <- if (!is.null(bnav) && is.finite(bnav[peak]) && is.finite(bnav[trough]) && bnav[peak] > 0) 1 - bnav[trough] / bnav[peak] else NA_real_
    eps[[length(eps) + 1L]] <- list(depth = dd[trough], m_peak_trough = .b5_months_between(dates[peak], dates[trough]),
      m_underwater = .b5_months_between(dates[peak], if (is.na(rec)) dates[n] else dates[rec]),
      m_recover = if (is.na(rec)) NA_real_ else .b5_months_between(dates[trough], dates[rec]),
      recovered = !is.na(rec), bench_depth = bdep,
      ratio = if (is.finite(bdep) && bdep > 0.01) dd[trough] / bdep else NA_real_)
    i <- j
  }
  if (!length(eps)) return(list())
  eps[order(-vapply(eps, function(z) z$depth, numeric(1)))][seq_len(min(top, length(eps)))]
}
b5_floor_anatomy <- function(E, root = ROOT) {
  atts <- Filter(.b5_measured, E$attempts %||% list())
  if (!length(atts)) return(c("## 바닥 낙폭 해부: 측정된 칸이 없다"))
  pt <- vapply(atts, function(a) .num(a$essence$port_t), numeric(1)); a <- atts[[which.max(pt)]]
  code <- .rf_attempt_code(a); es <- a$essence
  hdr <- c(sprintf("## 바닥(floor) 낙폭 해부 — 이 entry 최고 PORT_t 칸 %s (PORT_t %s · CAGR %s · MDD %s · Calmar %s)",
                   code, .f3(es$port_t), .f3(es$cagr), .f3(es$mdd), .f3(es$calmar)),
           "  ★날짜는 주지 않는다 — 설계는 특정 시기에 기대면 안 된다(달력 리터럴은 probe 가 거부한다). 형태만 읽어라.")
  ad <- .chr(a$artifacts); np <- file.path(ad, "02_nav.csv"); bp <- file.path(ad, "05_benchmark_returns.csv")
  if (!nzchar(ad) || !file.exists(np)) return(c(hdr, "  (산출물 02_nav.csv 부재 — 해부 생략)"))
  NV <- tryCatch(fread(np), error = function(e) NULL)
  if (is.null(NV) || !all(c("date", "nav_net") %in% names(NV))) return(c(hdr, "  (02_nav.csv 열 부재 — 해부 생략)"))
  dts <- as.Date(as.character(NV$date)); nav <- as.numeric(NV$nav_net)
  bnav <- NULL
  if (file.exists(bp)) { BM <- tryCatch(fread(bp), error = function(e) NULL)
    if (!is.null(BM) && all(c("date", "benchmark_nav") %in% names(BM))) {
      m <- match(as.character(NV$date), as.character(BM$date)); bnav <- as.numeric(BM$benchmark_nav)[m] } }
  eps <- b5_drawdown_episodes(nav, dts, bnav)
  if (!length(eps)) return(c(hdr, "  낙폭 에피소드 없음"))
  L <- hdr
  for (k in seq_along(eps)) { z <- eps[[k]]
    L <- c(L, sprintf("  에피소드 %d: 깊이 %.1f%% · 고점→저점 %s개월 · 수중 %s개월%s · 회복 %s · 같은 창 KOSPI200 낙폭 %s · 비(전략/벤치) %s · 형태 %s",
      k, 100 * z$depth, .f1(z$m_peak_trough), .f1(z$m_underwater), if (z$recovered) "" else "(미회복 — 표본 끝까지)",
      if (z$recovered) paste0(.f1(z$m_recover), "개월") else "미회복",
      if (is.finite(z$bench_depth)) sprintf("%.1f%%", 100 * z$bench_depth) else "NA",
      if (is.finite(z$ratio)) sprintf("%.2f", z$ratio) else "NA",
      if (is.finite(z$m_peak_trough) && z$m_peak_trough > 12) "침식형(느린 하락)" else "급락형"))
  }
  L
}
.f1 <- function(x) if (is.finite(.num(x))) formatC(.num(x), digits = 1, format = "f") else "NA"

# ── 재료 ─────────────────────────────────────────────────────────────────────
B5_DISTILL_KEYWORDS <- c("오버레이", "낙폭", "MDD", "국면", "현금", "overlay", "drawdown", "regime")
.b5_axiom_brief <- function(root = ROOT) {
  sh <- .b5_lib("02_Infrastructure/ops/rf_axiom_brief.sh"); if (!file.exists(sh)) return(character(0))
  old <- Sys.getenv("QVEST_RF_ROOT", NA); Sys.setenv(QVEST_RF_ROOT = root, QVEST_PY = .b5_py())   # Windows 는 system2(env=) 무시 — 부모에 심는다
  on.exit(if (is.na(old)) Sys.unsetenv("QVEST_RF_ROOT") else Sys.setenv(QVEST_RF_ROOT = old), add = TRUE)
  out <- tryCatch(suppressWarnings(system2("bash", c("-c", shQuote(sprintf(". '%s' && rf_axiom_brief", gsub("\\", "/", sh, fixed = TRUE)))),
                                           stdout = TRUE, stderr = FALSE)), error = function(e) character(0))
  gsub("\r", "", as.character(out %||% character(0)))
}
.b5_measure_tokens <- function() {
  wc <- .b5_lib("02_Infrastructure/portfolio/weight_catalog.R")
  tk <- tryCatch({ en <- new.env(parent = globalenv())
    invisible(capture.output(suppressMessages(source(wc, local = en)))); get(".WC_MEASURE_TOKENS", envir = en) }, error = function(e) NULL)
  if (is.null(tk)) tk <- c("hurdle_result", "bt_result", "essence_score", "module_performance", "information_ratio", "portfolio_alpha_t",
                           "abs_net_sr", "net_sr", "h1b_sigma_ab", "ladder_table", "period_returns", "measured", "sharpe", "calmar")
  as.character(tk)
}
.b5_spec_of <- function(a) { sp <- .chr(a$essence$spec); if (nzchar(sp) && file.exists(sp)) tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL) else NULL }

b5_materials <- function(base_id, root = ROOT, cfg = b5_cfg(root), compose_only = FALSE, arm_quota = cfg$max_new_arms,
                         round = 1L, out_p = NULL) {
  E <- .b5_entry(root, base_id); if (is.null(E)) stop("[b5_design] entry 부재: ", base_id)
  arms <- .b5_catalog(root); k2i <- .b5_kind_to_id(arms)
  standing <- tryCatch(rfbd_standing_picks(root), error = function(e) character(0))
  carry_ov <- (E$carry %||% list())$overlay
  sec <- list()
  # (1) entry 문맥 ───────────────────────────────────────────────────────────
  ap <- file.path(.chr(E$base_artifacts), "authoritative_remeasure.json")
  AR <- if (file.exists(ap)) tryCatch(fromJSON(ap, simplifyVector = FALSE), error = function(e) NULL) else NULL
  sp0 <- AR$replication$source_paper %||% list(); es0 <- AR$essence %||% list()
  papers <- E$combo$papers %||% list()
  ptxt <- if (length(papers)) paste(vapply(utils::head(papers, 6L), function(p) sprintf("%s(%s)", .cap(p$title, 60), .chr(p$key)), character(1)), collapse = " + ")
          else .chr(sp0$title %||% E$paper_key)
  L1 <- c(sprintf("## (1) 이 entry — %s", base_id),
          sprintf("- 논문: %s", .cap(ptxt, 400)),
          sprintf("- 기저 등급 %s · 기저 PORT_t %s · CAGR %s · MDD %s · Calmar %s · OOS %s", .chr(E$base_grade),
                  .f3(es0$portfolio_alpha_t_nw_lag3 %||% es0$port_t), .f3(es0$cagr), .f3(es0$mdd %||% es0$max_drawdown), .f3(es0$calmar), .f3(es0$oos_retention)),
          sprintf("- 블록 순서: %s · 시도 %s/%s · 이번 설계 라운드 %d", paste(unlist(E$block_order %||% list("미기록")), collapse = ">"),
                  .chr(E$attempts_used), .chr(E$max_attempts %||% "25"), as.integer(round)))
  cy <- E$carry
  if (!is.null(cy)) {
    .fid <- function(x) .chr((x %||% list())$id %||% (x %||% list())$catalog_id)
    L1 <- c(L1, sprintf("- ★승격 entry — 승계 팩터 %s · 승계 비중 %s · 승계 오버레이 %s (이미 켜져 있다 — 다시 고르지 마라)",
                        paste(vapply(cy$factors %||% list(), .fid, character(1)), collapse = ","),
                        .chr((cy$weighting %||% list())$label %||% (cy$weighting %||% list())$kind %||% "ew"),
                        paste(.ov_arm_ids(cy$overlay), collapse = "×") %||% "없음"))
  }
  L1 <- c(L1, "", "### 측정표 (권위 등급 essence · 15bps 판) — 자기 오버레이 스택 = 그 칸이 직접 얹은 층",
          "| 코드 | 블록 | 라벨 | 자기 오버레이 스택 | PORT_t | CAGR | MDD | Calmar | OOS | G2 반증 |", "|---|---|---|---|---|---|---|---|---|---|")
  measured_keys <- character(0); nrow_tab <- 0L
  for (a in E$attempts %||% list()) {
    if (nrow_tab >= 45L) { L1 <- c(L1, "| … | (표 상한 45행) | | | | | | | | |"); break }
    code <- .rf_attempt_code(a); if (is.na(code)) code <- sprintf("n%s", .chr(a$n))
    S <- .b5_spec_of(a); lab <- .cap(S$label %||% sub("^\\[[^]]*\\]\\s*", "", .chr(a$idea)), 40)
    stk <- if (!is.null(S)) .b5_own_ids(S, carry_ov, k2i)$ids else character(0)
    if (length(stk)) measured_keys <- c(measured_keys, rfbd_stack_key(stk))
    adv <- .chr((a$adversary %||% list())$verdict); if (!nzchar(adv)) adv <- if (startsWith(code, "B5_")) "미실행" else "-"
    if (.b5_measured(a)) { es <- a$essence
      L1 <- c(L1, sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |", code, .chr(es$block %||% sub("_.*$", "", code)), lab,
                          if (length(stk)) paste(stk, collapse = "×") else "-", .f3(es$port_t), .f3(es$cagr), .f3(es$mdd), .f3(es$calmar), .f3(es$oos_retention), adv))
    } else L1 <- c(L1, sprintf("| %s | %s | %s | %s | 미측정 | | | | | %s |", code, sub("_.*$", "", code), lab,
                               if (length(stk)) paste(stk, collapse = "×") else "-", .cap(a$terminal_reason %||% "pending", 60)))
    nrow_tab <- nrow_tab + 1L
  }
  # 이 entry 의 블록 L-code 기전·회피
  ld <- file.path(root, "stage_artifacts/l_code/reinforcement")
  for (blk in c("B1", "B5", "B2", "B3", "B4")) {
    f <- file.path(ld, sprintf("l_code_%s_%s.json", base_id, blk)); if (!file.exists(f)) next
    x <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL); if (is.null(x)) next
    mech <- .chr(x$mechanism); av <- as.character(unlist(x$avoid %||% list()))
    if (!nzchar(mech) && !length(av)) next
    L1 <- c(L1, "", sprintf("### 이 entry 의 %s 블록 기전 (L-code %s)", blk, .chr(x$l_code)))
    if (nzchar(mech)) L1 <- c(L1, sprintf("- 기전: %s", .cap(mech, 700)))
    if (length(av)) L1 <- c(L1, sprintf("- 쓰지 말 것: %s", paste(vapply(utils::head(av, 3L), .cap, character(1), n = 200), collapse = " / ")))
  }
  # 기전 단계 B5 설계(있으면)
  fp <- b5_final_path(root, base_id)
  if (file.exists(fp)) {
    D0 <- tryCatch(fromJSON(fp, simplifyVector = FALSE), error = function(e) NULL)
    if (length(D0$cells %||% list())) {
      L1 <- c(L1, "", sprintf("### 현재 B5 설계 파일 (%s · %d칸) — 재설계면 이 칸들은 **그대로 남고** 네 칸이 뒤에 붙는다",
                              .chr(D0$source %||% "기전 단계(next_block_design)"), length(D0$cells)))
      for (i in seq_along(D0$cells)) { ce <- D0$cells[[i]]; ids <- rfbd_cell_picks(ce)
        L1 <- c(L1, sprintf("- 칸 %d(B5_%d): %s — %s%s", i, 16L + i - 1L, paste(ids, collapse = "×"), .cap(ce$label, 40),
                            if (rfbd_stack_key(ids) %in% measured_keys) " [측정됨]" else " [미측정]")) }
    }
  }
  sec$entry <- L1
  # (2) 바닥 낙폭 해부 ───────────────────────────────────────────────────────
  sec$floor <- b5_floor_anatomy(E, root)
  # (3) arm 성과 이력 ───────────────────────────────────────────────────────
  O <- tryCatch(rf_overlay_outcomes(root), error = function(e) NULL)
  L3 <- c("## (3) arm 성과 이력 (전 entry · Δ = 그 칸 − 같은 entry B1 중앙값 · arm 별 중앙값 · ΔMDD<0 이 개선) — 상위 8 / 하위 8",
          "| arm_id | 사용 | 스택사용 | entry수 | ΔMDD | ΔCAGR | ΔPORT_t | ΔCalmar | G2 pass/fail |", "|---|---|---|---|---|---|---|---|---|")
  if (!is.null(O) && nrow(O)) {
    idx <- unique(c(utils::head(seq_len(nrow(O)), 8L), utils::tail(seq_len(nrow(O)), 8L)))
    for (i in idx) L3 <- c(L3, sprintf("| %s | %d | %d | %d | %s | %s | %s | %s | %d/%d |", O$arm_id[i], O$uses[i], O$stacked_uses[i], O$n_entries[i],
                                       .f3(O$med_d_mdd[i]), .f3(O$med_d_cagr[i]), .f3(O$med_d_port_t[i]), .f3(O$med_d_calmar[i]), O$adv_pass[i], O$adv_fail[i]))
  } else L3 <- c(L3, "| (이력 없음) | | | | | | | | |")
  sec$outcomes <- L3
  # (4) 앞선 논문들의 B5 교훈 ───────────────────────────────────────────────
  fs <- list.files(ld, pattern = "^l_code_.*_B5\\.json$", full.names = TRUE)
  fs <- fs[!grepl(base_id, basename(fs), fixed = TRUE)]
  L4 <- c(sprintf("## (4) 앞선 논문들의 B5 블록 교훈 (최근 %d entry) — 수치는 그 논문의 것 · **기전과 회피**만 옮겨 붙는다 · 금지 목록이 아니다(AX-000)", cfg$prior_entries))
  if (length(fs)) {
    fs <- fs[order(file.info(fs)$mtime, decreasing = TRUE)]
    for (f in utils::head(fs, cfg$prior_entries)) {
      x <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL); if (is.null(x)) next
      mech <- .chr(x$mechanism); av <- as.character(unlist(x$avoid %||% list()))
      if (!nzchar(mech) && !length(av)) next
      L4 <- c(L4, sprintf("### %s", .chr(x$strategy_id)))
      if (nzchar(mech)) L4 <- c(L4, sprintf("- 기전: %s", .cap(mech, 700)))
      if (length(av)) L4 <- c(L4, sprintf("- 쓰지 말 것: %s", paste(vapply(utils::head(av, 3L), .cap, character(1), n = 160), collapse = " / ")))
    }
  } else L4 <- c(L4, "(없음)")
  sec$prior <- L4
  # (5) 증류 지식 ──────────────────────────────────────────────────────────
  L5 <- c("## (5) 증류 지식 (distilled · 키워드: 오버레이/낙폭/MDD/국면/현금/overlay/drawdown/regime · 상한 20)")
  rows5 <- tryCatch({
    invisible(capture.output(suppressMessages(source(.b5_lib("02_Infrastructure/axiom/distilled.R"), local = TRUE))))
    acc <- list()
    for (kw in B5_DISTILL_KEYWORDS) { r <- tryCatch(suppressMessages(lookup_distilled(kw, root = root, max_rows = 10L)), error = function(e) NULL)
      if (is.data.frame(r) && nrow(r)) acc[[length(acc) + 1L]] <- r }
    if (length(acc)) { d <- do.call(rbind, acc); d[!duplicated(d$dist_id), , drop = FALSE] } else NULL
  }, error = function(e) NULL)
  if (is.data.frame(rows5) && nrow(rows5)) {
    for (i in seq_len(min(20L, nrow(rows5))))
      L5 <- c(L5, sprintf("- %s [%s] %s%s", rows5$dist_id[i], rows5$polarity[i], .cap(rows5$statement[i], 120),
                          if (nzchar(.chr(rows5$retry_policy[i]))) paste0(" (", .cap(rows5$retry_policy[i], 80), ")") else ""))
  } else L5 <- c(L5, "(일치 항목 없음)")
  sec$distilled <- L5
  # (6) 기전 지도 + 활성 카탈로그 ─────────────────────────────────────────
  tb <- tryCatch(rf_target_brief(root), error = function(e) "(기전 지도 산출 실패)")
  L6 <- c("## (6) 기전 지도 (action × state · 측정 횟수·포화만) 와 활성 카탈로그", tb, "",
          "### 활성 arm (여기 있는 id 만 picks 에 쓸 수 있다 · 상주 arm 은 목록에서 뺐다)")
  for (a in arms) { if (!identical(.chr(a$status), "active") || .chr(a$id) %in% standing) next
    z <- rfm_arm_axis(a)
    L6 <- c(L6, sprintf("- %s · kind=%s · family=%s · %s/%s%s — %s", .chr(a$id), .chr(a$kind), .chr(a$family), z$action, z$state,
                        if (nzchar(.chr(a$source))) paste0(" · source=", .chr(a$source)) else "", .cap(a$basis, 200))) }
  sec$catalog <- L6
  # (7) 계약·엔진 사실·중첩·PIT·금칙·검증부 ────────────────────────────────
  axes <- tryCatch(fromJSON({ p <- file.path(root, "06_Registry/rf_overlay_adversary_axes.json"); if (file.exists(p)) p else .b5_lib("06_Registry/rf_overlay_adversary_axes.json") },
                            simplifyVector = FALSE), error = function(e) NULL)
  L7 <- c("## (7) arm 계약 · 엔진 사실 · 중첩 의미론 · PIT · 금칙 · 검증부",
    "### arm 계약 (overlay_arms/<kind>.R · 정본 엔진 = 02_Infrastructure/reinforcement/rf_cell_engine.R)",
    "- 함수 하나: overlay_expo_<kind> <- function(H, t, ctx) → 스칼라 e ∈ [0,1] 또는 data.table(Ticker, e). 추정 불가·표본 부족이면 e <- 1(무개입). 오류를 던지지 마라.",
    "- H = 월별 특징 **확장창**(t 행까지만 존재 · 미래 행 없음). 열: Date, i, rv20, rv60, rv120, dd, r252, nav, ew1..ew10, xs, fwd.",
    "  ★H 는 전부 **KOSPI200 벤치마크 계열**에서 만든 시장 상태다(rv = 실현변동성 창 · dd = 벤치 낙폭 · r252 = 12개월 수익 · nav = 벤치 누적 · xs = 횡단면분산). 책(전략) NAV 는 오버레이 시점에 존재하지 않는다.",
    "  ★H$fwd 의 t 행 = 익월 수익 = 신호일에 미실현. 읽으면 누출(probe 가 fwd[t] 섭동으로 잡는다). shift(type='lead')·tail·전체 열 통계도 같다.",
    "- ctx = list(t, date, v_now = H$rv60[t], tgt = 자기 이력 중앙 rv60, n_min = **그 층 자신의** 표본 하한, hold, strict). hold = 그 달 보유 종목의 확장창 상태 data.table(Ticker, beta, dbeta(하방베타), ovol(자체변동성), bcorr(시장상관), n_obs) — 없으면 NULL.",
    "- action 이 cross_sectional 이면 **반드시 종목별 표**를 내라(스칼라만 내면 처치 미전달로 등재 거부). scalar_exposure 는 스칼라 하나.",
    "### 중첩(스택) 의미론 — 한 칸에 여러 arm",
    "- 날짜마다 보유 전 종목 위에서 층별 노출을 만든 뒤 **종목별 곱**으로 합성한다(클립 [0,1]). 스칼라 층은 모든 보유에 같은 값, 벡터 층은 표의 값 · 표에 없는 보유 = 1 · 빈 표 = 그 달 그 층 무개입.",
    "- 층마다 자기 n_min 으로 워밍업 축소 e = 1 − min(1, t/n_min)·(1 − e_raw) 를 마친 뒤 곱한다(기본 24 · turbulence/ewma 36 · har_vol/ml_tail_gate 48).",
    "- 층별 가드: 어느 층이든 노출이 상수이거나 상시 1 이면 **측정 무효**(처치 미전달) · 커버리지 결손은 층 이름으로 장부에 남는다. 같은 kind 두 층 금지 · 같은 id 두 번 금지.",
    sprintf("- 스택은 층 ≤ %d · 정렬 id 키가 같은 스택은 같은 칸([A,B] ≡ [B,A]) · 칸끼리 같은 스택 금지 · 라운드당 칸 ≤ %d · 유효 칸 ≥ %d(미달 = 폴백) · entry 총 ≤ 15칸(B5_16..B5_30).",
            cfg$max_layers, cfg$max_cells, cfg$min_cells),
    "- ★상주 칸 B5_31(pg2_risk_overlay_v1 · BOOK PG2 사양 이식)은 매 세대 **따로** 측정된다 — 설계에 절대 넣지 마라(검증이 뺀다).",
    "### PIT (절대 규칙 · .claude/rules/pit.md)",
    "- C5: 오버레이 신호는 홀딩월(ctx$date 의 익월) 시작 **이전** 데이터로만. 컷오프 = 익월 1일 미만.",
    "- C11: 외부 데이터(패널·파일)는 as-of 시차를 증명해야 한다 — external_data 를 쓰면 overlay_pit_guard::assert_overlay_pit 로 매 호출 HARD 확인(본보기 overlay_arms/pg2_risk_overlay.R).",
    "- C15: 팩터 DB 는 load_month_factors() 단일 경유 · parquet 직접 load 금지. C1: H 밖 원천의 전기간 통계 금지(H 위 확장창 통계는 정상).",
    "### 금칙 (probe 가 자동 거부한다)",
    sprintf("- 성과 토큰(주석 포함): %s", paste(.b5_measure_tokens(), collapse = ", ")),
    "- 임의 상수 문턱: H·hold 의 열을 숫자 리터럴과 직접 비교(H$dd[t] > 0.2 · hold$beta > 1.2) 금지 — 문턱은 quantile/median/ecdf 등 확장창 추정.",
    "- 달력 리터럴: 특정 연·월·날짜·인덱스 창(2008 이후만 · t %in% 146:153 · year(ctx$date) >= …) 금지. probe 는 합성 픽스처(240개월 · 위기 2구간 주입 · 종목 T001~T025)로 도니 픽스처에서 안 켜지고 실데이터에서만 켜지는 조건도 회피로 잡는다.",
    "### G1 적대적 설계시점 감사 (새 arm 마다 · 설계자와 **다른 모델** · 축 정본 06_Registry/rf_overlay_adversary_axes.json · 판정은 R 병합기가 근거를 재도출)")
  for (ax in axes$axes %||% list()) L7 <- c(L7, sprintf("- [%s] %s — %s", .chr(ax$id), .chr(ax$title), .cap(ax$focus, 420)))
  L7 <- c(L7,
    "### G2 사후 반증 (측정 뒤 · rf_overlay_adversary.R) — pass 인 B5 칸만 블록 승자·승격 carry·Grade A 후보로 소비된다",
    "- T1 lag-1(노출을 한 달 늦게 적용해도 바닥 Calmar 를 넘는가) · T2 strict-PIT A/B(외부 패널 arm) · T3 노출 짝지은 원형 블록 순열 placebo · T3b 횡단면 placebo(벡터 arm) · T4 정적 등가(상수 노출 mean(E) 를 넘는가) · T5 에피소드 집중(보고).",
    "- '개선이 있다' 와 '개선이 타이밍에서 왔다' 는 다른 명제다 — 동월 누출·정적 디레버리지·임의 타이밍으로도 Calmar 는 오른다. 설계는 이 반증을 견딜 기전이어야 한다.")
  sec$contract <- L7
  # (8) 공리 ────────────────────────────────────────────────────────────────
  axb <- .b5_axiom_brief(root); sec$axioms <- if (length(axb) && any(nzchar(axb))) axb else "## 공리: (활성 공리 없음)"
  # (9) 가드 상태 ──────────────────────────────────────────────────────────
  sec$guard <- c("## (9) 이번 라운드의 가드 상태",
    sprintf("- compose_only = %s — %s", if (isTRUE(compose_only)) "TRUE" else "FALSE",
            if (isTRUE(compose_only)) "★새 arm 을 내지 마라(내도 무시·삭제된다). 기존 활성 arm 의 배합(스택)만 설계한다." else sprintf("새 arm 은 최대 %d개(그 이상은 무시·삭제). 필요 없으면 0개도 정상이다.", as.integer(arm_quota))),
    sprintf("- 라운드 %d · 설계 칸 ≤ %d · 유효 칸 ≥ %d · 층 ≤ %d", as.integer(round), cfg$max_cells, cfg$min_cells, cfg$max_layers),
    "- ★설계는 특정 시기(연·월)에 기대면 안 된다 — 이 재료의 날짜는 전부 지웠고(<date>/<yr>), arm 의 달력 리터럴은 probe 가 거부한다.")
  # 조립 + 날짜 제거 ────────────────────────────────────────────────────────
  order <- c("axioms", "entry", "floor", "outcomes", "prior", "distilled", "catalog", "contract", "guard")
  txt <- unlist(lapply(order, function(k) c(sec[[k]], "")))
  txt <- b5_strip_dates(txt)
  sizes <- vapply(order, function(k) sum(nchar(b5_strip_dates(sec[[k]]), type = "chars")) + length(sec[[k]]), integer(1))
  if (!is.null(out_p)) {
    dir.create(dirname(out_p), recursive = TRUE, showWarnings = FALSE)
    writeLines(txt, out_p, useBytes = TRUE)
    write(toJSON(as.list(sizes), auto_unbox = TRUE), paste0(out_p, ".sizes.json"))
    .b5_log("materials_written", base_id = base_id, round = as.integer(round), compose_only = isTRUE(compose_only),
            arm_quota = as.integer(arm_quota), chars_total = sum(nchar(txt, type = "chars")), sizes = paste(sprintf("%s=%d", names(sizes), sizes), collapse = " "),
            out = out_p)
  }
  invisible(list(text = txt, sizes = sizes))
}

# ── 검증 + 최종 설계 쓰기 ────────────────────────────────────────────────────
.b5_grid_b5_cells <- function(root) {   # 설계 파일이 없던 entry 의 재설계 — 격자 칸을 picks 로 옮겨 자리를 지킨다(코드 충돌 방지)
  g <- tryCatch(fromJSON(file.path(root, "06_Registry/reinforce_program.json"), simplifyVector = FALSE), error = function(e) NULL)
  for (b in g$blocks %||% list()) if (identical(as.character(b$id), "B5"))
    return(lapply(b$cells %||% list(), function(cl) list(picks = list(.chr((cl$overlay %||% list())$arm_id %||% (cl$overlay %||% list())$kind)),
                                                         label = .chr(cl$label), why = "격자 규칙 칸(이미 측정됨 · 자리 보존)")))
  list()
}
#' @return list(ok, fallback, n_new, n_total, why, path)
b5_verify_and_write <- function(base_id, root = ROOT, cfg = b5_cfg(root), lane_out, admitted_ids = character(0),
                                rejected_ids = character(0), round = 1L, compose_only = FALSE) {
  round <- as.integer(round); fp <- b5_final_path(root, base_id)
  n_adm <- length(admitted_ids); n_rej <- length(rejected_ids)
  .fallback <- function(why) {
    .b5_log("design_fallback", base_id = base_id, round = round, why = why, note = "기존 설계(기전/규칙) 보존 — 러너는 그것으로 돈다")
    tryCatch(rf_record_b5_design(1L, base_id, list(round = round, n_cells = 0L, new_arms_admitted = n_adm, new_arms_rejected = n_rej,
                                                    compose_only = isTRUE(compose_only), fallback = TRUE, fallback_reason = why,
                                                    new_arm_ids = as.list(admitted_ids)), root = root),
             error = function(e) .b5_log("ledger_record_failed", base_id = base_id, err = conditionMessage(e)))
    list(ok = FALSE, fallback = TRUE, n_new = 0L, n_total = NA_integer_, why = why, path = fp)
  }
  if (!file.exists(lane_out) || file.size(lane_out) == 0L) return(.fallback("설계 파일 부재"))
  D <- tryCatch(fromJSON(lane_out, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(D)) return(.fallback("설계 JSON 파싱 실패"))
  cells <- Filter(is.list, D$cells %||% list())
  if (!length(cells)) return(.fallback("cells 0건"))
  cat_map <- rfbd_catalog("B5", root); cat_ids <- vapply(cat_map, function(x) .chr(x$id), character(1))
  standing <- tryCatch(rfbd_standing_picks(root), error = function(e) character(0))
  # 바닥 칸(재설계) — 기존 설계 파일 > 격자 B5 칸 · 이미 측정된 칸의 자리를 지킨다(코드 = 위치)
  base <- list()
  if (round >= 2L) {
    D0 <- if (file.exists(fp)) tryCatch(fromJSON(fp, simplifyVector = FALSE), error = function(e) NULL) else NULL
    base <- Filter(is.list, D0$cells %||% list())
    if (!length(base)) base <- .b5_grid_b5_cells(root)
  }
  base_keys <- vapply(base, function(ce) rfbd_stack_key(rfbd_cell_picks(ce)), character(1))
  keep <- list(); seen <- character(0)
  for (i in seq_along(cells)) {
    ce <- cells[[i]]; ids <- rfbd_cell_picks(ce)
    drop <- function(why) .b5_log("design_cell_dropped", base_id = base_id, round = round, cell = i, picks = paste(ids, collapse = "×"), why = why)
    if (!length(ids)) { drop("picks 없음"); next }
    if (length(ids) > cfg$max_layers) { drop(sprintf("층 %d > 상한 %d", length(ids), cfg$max_layers)); next }
    if (anyDuplicated(ids)) { drop("같은 id 두 번"); next }
    if (any(ids %in% standing)) { drop("상주 arm(pg2) 포함 — 상주 칸이 따로 잰다"); next }
    if (any(ids %in% rejected_ids)) { drop(sprintf("등재 거부된 새 arm 참조: %s", paste(intersect(ids, rejected_ids), collapse = ","))); next }
    miss <- setdiff(ids, cat_ids); if (length(miss)) { drop(sprintf("active 카탈로그에 없음: %s", paste(miss, collapse = ","))); next }
    key <- rfbd_stack_key(ids)
    if (key %in% seen) { drop("앞 칸과 같은 스택"); next }
    if (key %in% base_keys) { drop("기존 설계 칸과 같은 스택(이미 자리가 있다)"); next }
    if (!nzchar(.chr(ce$label))) ce$label <- paste(ids, collapse = "×")
    if (length(keep) >= cfg$max_cells) { drop(sprintf("라운드 상한 %d칸 초과", cfg$max_cells)); next }
    if (length(base) + length(keep) >= 15L) { drop("entry 총 15칸(B5_16..B5_30) 초과"); next }
    seen <- c(seen, key); keep[[length(keep) + 1L]] <- list(picks = as.list(ids), label = .chr(ce$label), why = .cap(ce$why %||% "", 400))
  }
  if (length(keep) < cfg$min_cells) return(.fallback(sprintf("유효 칸 %d < 최소 %d", length(keep), cfg$min_cells)))
  # 최종 관문 — 새 칸은 정본 검증기가 재도출한다(실재·active·kind·중복·상주·층). 진술은 근거가 아니다.
  v <- rfbd_verify(list(cells = keep), "B5", root, max_cells = cfg$max_cells)
  if (!isTRUE(v)) return(.fallback(paste("rfbd_verify:", as.character(v))))
  if (round == 1L && file.exists(fp)) {
    bk <- paste0(fp, ".mech.json"); file.copy(fp, bk, overwrite = TRUE)
    .b5_log("design_backed_up", base_id = base_id, from = fp, to = bk)
  }
  final <- list(block = "B5", base_id = base_id, source = "b5_design_lane", round = round,
                written_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                rationale = .cap(D$rationale %||% "", 600), base_design_cells = length(base),
                cells = c(base, keep))
  .b5_atomic_write(toJSON(final, auto_unbox = TRUE, pretty = TRUE, null = "null"), fp)
  fields <- list(round = round, n_cells = length(keep), new_arms_admitted = n_adm, new_arms_rejected = n_rej,
                 compose_only = isTRUE(compose_only), fallback = FALSE, new_arm_ids = as.list(admitted_ids),
                 n_total_cells = length(base) + length(keep), design_path = fp)
  if (round >= 2L) fields$redesign <- list(cells_added = length(keep), base_design_cells = length(base))
  tryCatch(rf_record_b5_design(1L, base_id, fields, root = root),
           error = function(e) .b5_log("ledger_record_failed", base_id = base_id, err = conditionMessage(e)))
  .b5_log("design_verified", base_id = base_id, round = round, cells = length(keep), total_cells = length(base) + length(keep),
          new_arms_admitted = n_adm, new_arms_rejected = n_rej, compose_only = isTRUE(compose_only), path = fp)
  list(ok = TRUE, fallback = FALSE, n_new = length(keep), n_total = length(base) + length(keep), why = "", path = fp)
}

# ── claim (pid-aware · 소유자 = 호출 레인의 Windows pid) ─────────────────────
#'   rf_claim_acquire 는 R 자신의 pid 를 적어 자식 R 이 끝나면 곧 '사망 소유자' 가 된다 — 레인(bash)의 pid 를 받아 적는다.
#'   생존 판정은 rf_claim.R::rf_claim_pid_alive(tasklist · 정본) 을 쓴다.
b5_claim_acquire <- function(claim, owner_pid, stale_hours = 6) {
  owner_pid <- suppressWarnings(as.integer(owner_pid))
  .take <- function(why) {
    dir.create(claim, recursive = TRUE, showWarnings = FALSE); unlink(file.path(claim, "released.json"))
    writeLines(toJSON(list(pid = owner_pid, started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), host = Sys.info()[["nodename"]], lane = "b5_design"),
                      auto_unbox = TRUE), file.path(claim, "owner.json"))
    list(ok = TRUE, reason = "acquired", note = why)
  }
  if (!dir.exists(claim)) return(.take("신규"))
  op <- file.path(claim, "owner.json")
  o <- if (file.exists(op)) tryCatch(fromJSON(op, simplifyVector = TRUE), error = function(e) NULL) else NULL
  pid <- suppressWarnings(as.integer(o$pid %||% NA)); age_h <- suppressWarnings(as.numeric(difftime(Sys.time(), file.info(claim)$mtime, units = "hours")))
  if (file.exists(file.path(claim, "released.json"))) return(.take("해제 표식 — 제자리 인수"))
  if (is.na(pid) && is.finite(age_h) && age_h * 3600 > 60) return(.take("owner 부재 — 빈 고아 인수"))
  if (!is.na(pid) && !rf_claim_pid_alive(pid)) return(.take(sprintf("owner pid %d 사망 — 인수", pid)))
  if (is.finite(age_h) && age_h > stale_hours) return(.take(sprintf("나이 %.2fh > %.1fh — 시간 폴백 인수", age_h, stale_hours)))
  list(ok = FALSE, reason = "claimed", note = sprintf("owner pid %s · %.2fh", .chr(pid), age_h))
}

# ── CLI ───────────────────────────────────────────────────────────────────────
if (!interactive()) {
  a <- commandArgs(TRUE)
  cmd <- if (length(a)) a[1] else ""
  .cmds <- c("active_entry", "next_is_b5", "guards", "materials", "probe", "record_emission", "verify", "claim", "release", "outcomes")
  if (cmd %in% .cmds) {
    if (cmd == "active_entry") { E <- b5_active_entry(ROOT); cat(if (is.null(E)) "-" else .chr(E$base_id), "\n", sep = "")
    } else if (cmd == "next_is_b5") { E <- .b5_entry(ROOT, a[2]); cat(if (b5_next_block_is_b5(E, ROOT)) "1" else "0", "\n", sep = "")
    } else if (cmd == "guards") {
      E <- .b5_entry(ROOT, a[2]); if (is.null(E)) { cat("entry 부재\n"); quit(status = 2L) }
      g <- b5_guards(E, ROOT, b5_cfg(ROOT), mode = a[3]); write(toJSON(g, auto_unbox = TRUE, null = "null"), a[4])
      quit(status = if (isTRUE(g$ok)) 0L else 3L)
    } else if (cmd == "materials") {
      b5_materials(a[2], ROOT, b5_cfg(ROOT), compose_only = identical(a[4], "1"), arm_quota = as.integer(a[5]), round = as.integer(a[6]), out_p = a[3])
    } else if (cmd == "probe") {
      invisible(capture.output(suppressMessages(source(.b5_lib("02_Infrastructure/reinforcement/overlay_probe.R")))))
      pr <- tryCatch(overlay_probe_arm(a[2], ROOT), error = function(e) list(ok = FALSE, reason = conditionMessage(e)))
      cat(sprintf("probe: %s | %s | %s | %s\n", a[2], if (isTRUE(pr$ok)) "pass" else "fail", .chr(pr$axis %||% "NA"), gsub("[\r\n|]+", " ", .chr(pr$reason %||% ""))))
      quit(status = if (isTRUE(pr$ok)) 0L else 3L)
    } else if (cmd == "record_emission") {
      invisible(capture.output(suppressMessages(source(.b5_lib("02_Infrastructure/reinforcement/rf_overlay_admit.R")))))
      rf_overlay_record_emission(a[2], target = list(action = a[3], state = a[4]), n_siblings = as.integer(a[6]), generator_model = a[5],
                                 root = ROOT, source = "b5_design", stage = a[7], reason = if (length(a) >= 8L) a[8] else "")
    } else if (cmd == "verify") {
      .csv <- function(x) { v <- if (length(x) && nzchar(x)) strsplit(x, ",", fixed = TRUE)[[1]] else character(0); v[nzchar(v)] }
      r <- b5_verify_and_write(a[2], ROOT, b5_cfg(ROOT), lane_out = a[3], round = as.integer(a[4]), compose_only = identical(a[5], "1"),
                               admitted_ids = .csv(if (length(a) >= 6L) a[6] else ""), rejected_ids = .csv(if (length(a) >= 7L) a[7] else ""))
      cat(sprintf("verify: %s | %s | new %d | %s\n", a[2], if (isTRUE(r$ok)) "written" else "fallback", r$n_new, r$why))
      quit(status = if (isTRUE(r$ok)) 0L else 1L)
    } else if (cmd == "claim") {
      r <- b5_claim_acquire(a[2], a[3], as.numeric(if (length(a) >= 4L) a[4] else 6))
      cat(sprintf("claim: %s | %s\n", r$reason, r$note)); quit(status = if (isTRUE(r$ok)) 0L else 1L)
    } else if (cmd == "release") { r <- rf_claim_release(a[2]); cat(sprintf("release: %s\n", r$reason)); quit(status = if (isTRUE(r$ok)) 0L else 1L)
    } else if (cmd == "outcomes") { O <- rf_overlay_outcomes(ROOT); fwrite(O, a[2]); cat(sprintf("outcomes: %d arms -> %s\n", nrow(O), a[2])) }
  } else if (nzchar(cmd)) stop("[b5_design] 알 수 없는 명령: ", cmd)
}
