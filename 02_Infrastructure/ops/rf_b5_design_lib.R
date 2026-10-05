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
#   이제 B5 진입 직전 **설계 에이전트 1회**가 (1) 이 entry 의 측정표·바닥 낙폭 해부·앞선 논문 B5 교훈·증류 지식·arm 성과 이력을 읽고
#   (2) 기존 활성 arm 을 **스택**(≤ max_layers 층 · 엔진은 층 노출을 종목별 곱으로 합성)으로 배합한 칸과
#   (3) 필요하면 **새 arm 몇 개**(≤ max_new_arms)를 함께 낸다. 새 arm 은 probe(기계 6검사) → G1 적대 감사(다른 모델) → 등재(R) 를
#   통과한 것만 설계에 남고, 측정 뒤엔 G2 사후 반증(rf_overlay_adversary)이 pass 인 칸만 소비된다(등급은 불변 — 소비 보류만).
#
# 경계 (구조로 강제 — LLM 은 제안만 한다):
#   ① 산출은 설계 JSON 하나 + arm 파일(overlay_arms/<kind>.R · .arm.json). 카탈로그·원장·최종 설계는 **R 이** 쓴다.
#   ② 설계 칸은 카탈로그 **active** id 만 · 상주 칸(program standing_cells)은 절대 포함 금지(상주가 매 세대 따로 잰다).
#   ③ 검증 실패 = 기존 설계 보존 + design_fallback(조용한 통과 없음) · 라운드는 fallback=true 로 기록된다.
#   ④ 방출 정직성: probe/감사/할당 초과로 **등재 전** 거부된 arm 도 원장(overlay_arm_ledger.jsonl)에 admitted=false 로 남는다.
#
# ★오버레이층 무한 탐색 방지 — 가드 H1~H8 (판정은 jlog overlay_guard_<name> 으로 남긴다 · 침묵 없음):
#   H1 entry 당 자동 설계 1회(round 1 기록이 있으면 거부) · 수동 재설계 ≤ guards.max_redesign_rounds · 비활성 entry 재설계 거부
#   H2 새 arm 사이클당 ≤ max_new_arms · 오늘 source=b5_design 방출 ≤ guards.daily_arm_cap(정본 집계기 rf_overlay_ledger_count.py ·
#      집계 실패 = fail-closed 0)
#   H3 정체: **새 arm 을 낸** 최근 guards.stagnation_window 라운드(전 entry · 시각순)의 arm 이 어느 것도
#      G2 pass(attempt$adversary$verdict=="pass") B5 칸의 자기 층에 없다 → compose_only(기존 arm 배합만)
#      ★arm 을 낸 라운드만 센다(2026-09-17): 전 라운드 창이면 compose_only 라운드 하나가 창을 비워 "arm·arm·배합·arm·arm·배합"
#        교대가 영구히 가능하다 — 무한 탐색 방지 장치가 구멍 하나로 우회된다. 해제 조건 = 그 arm 중 하나가 G2 pass.
#   H4 활성 생성 arm(source∈{b5_design,overlay_propose} 또는 kind gen_/b5gen_ · 상주 arm 제외) > guards.max_active_generated → compose_only
#   H5 설계 크기: 라운드당 ≤ max_cells · ≥ min_cells(미달 = 폴백) · 스택 ≤ max_layers · 총 ≤ 15(B5_16..B5_30)
#   H6 칸 무결성: 상주 제외 · 스택 중복(정렬 id 키)·이미 측정된 스택 금지 · 같은 kind 두 층 금지 · active 만 (rfbd_verify 재도출)
#   H7 방출 정직성(위 ④) · H8 폴백 무성 금지(위 ③)
#
# ★교차 entry 수치 가림 (도훈 결정 D-E-B5-MATERIALS 2026-09-25 · pit.md C1 D-E):
#   이 레인은 arm 을 고르는 **무인 자동 선정기**다. 재료가 다른 entry 의 전기간 측정값(arm 별 ΔCalmar 순위 · G2 obs/q/p ·
#   교훈 서술 속 Calmar/MDD · 증류 지식 수치 · 프로그램 최고치)을 실으면 시점 t 보유를 그 뒤 창의 성과로 고르는 것이다.
#   그래서 자기·정적 절(B5_OWN_SECTIONS) 밖의 **모든 절**을 B1 과 같은 가림 함수(rf_b1_design_lib.R 정본 — 사본 없이
#   이름으로만 적재 · .b5_redactor)로 가린다: 식별자 보존 · 700자 등 절단 **앞뒤 2회**(.b5_capx) · 발송 전 재도출 검증
#   (잔존 = materials_rejected → 레인 materials_failed → 기존 기전/규칙 설계로 진행) · (3) arm 목록은 arm_id 순(성과 순 금지).
#   자기 entry 측정표·바닥 해부는 가리지 않는다(이 entry 의 강화 루프 자체 — 선택 정직성 = Judge).
#   가림 함수를 못 싣거나 적재 양성 대조가 실패하면 재료를 쓰지 않는다(fail-closed — 가리지 않은 재료가 나가는 길은 없다).
# ★교차 entry 결과 라벨 가림 (도훈 결정 D-E-B5-LABELS 2026-09-25 · 같은 C1 D-E):
#   수치를 가려도 라벨(G2 pass/fail · 어느 검사가 죽였나 · 기전 지도 포화/미포화 · '반증 pass k/N' 같은 개수)이 남으면 같은 선정이다.
#   같은 가림 체계에 라벨 규칙을 더했다 — .b5_capx 앞뒤 · 조립부 교차 절 기본 가림(.label_x) · 발송 전 재검증(.b5_label_residue).
#   어휘는 나열하지 않고 코드가 실제로 낸 문자열(원장 G2 기록·생산자 상수·rf_target_brief 리터럴·디렉터 상태)에서 재료마다 재도출한다(.b5_labeler).
#   (2b)·(4b)·(5)·(6) 은 라벨 자리를 원천에서 표식으로 쓴다(유무·순서 패턴 누출 차단). 자기 절 (1)(2)(7)(8) 라벨은 유지(바이트 불변).
#
# ★발화 시점 (2026-09-17 감사): 러너는 B1 종료 뒤 **다음 배치를 여는 같은 호출 안에서** block_order 를 기록한다
#   (reinforce_auto_parallel.R · used ≥ 5 ∧ 미결 0). tick 은 레인 → 러너 순서라, 기록된 순서만 보면 레인이 보는 시점엔
#   항상 미기록 → 러너가 곧바로 B5 를 규칙/기전 설계로 연다 → 레인은 영영 발화하지 못한다. 그래서 미기록이면 러너와
#   **같은 규칙**(rf_lesson.R::rf_block_order_decide · 같은 전제조건)으로 순서를 예측한다. 레인이 쓰는 B5 설계 파일은
#   그 규칙의 기전 선호(최신 설계 파일 = B5)와도 같은 쪽을 가리키므로 예측과 러너 결정이 갈리지 않는다.
#   ★그래서 기전 설계 백업은 .cache/rf_block_design/ 밖(레인 디렉터리)에 둔다 — 그 디렉터리의 최신 파일 이름이 순서 규칙의 입력이다.
#
# 루트 2층 (b1 lib 규약): 데이터 루트 ROOT = QVEST_RF_ROOT > QM_ROOT · 코드 루트 = 이 파일의 위치(self-first).
#   ★자식 Rscript 는 ~/.Renviron 의 QM_ROOT 가 상속값을 **덮는다**(2026-09-17 실사고: 검사 자식이 운영 원장에 썼다) —
#     샌드박스 호출자는 R_ENVIRON_USER 를 빈 파일로 물려야 한다(rf_b5_design.sh 가 데이터 루트 ≠ 코드 루트일 때 자동으로 한다).
#
# 사용:
#   Rscript rf_b5_design_lib.R due                                        → 마지막 줄 "<BID>\t<1|0>\t<사유>"
#   Rscript rf_b5_design_lib.R next_is_b5 <base_id>                      → 사유 줄 + 마지막 줄 1/0
#   Rscript rf_b5_design_lib.R guards <base_id> <auto|redesign> <out.json> → 0 통과 · 3 거부 · 2 entry 부재
#   Rscript rf_b5_design_lib.R materials <base_id> <out.txt> <compose_only 0|1> <arm_quota> <round>
#   Rscript rf_b5_design_lib.R probe <kind> [declared_state]              → 0 pass · 3 fail · 마지막 줄 "probe: kind | pass|fail | axis | state | reason"
#   Rscript rf_b5_design_lib.R record_emission <kind> <action> <state> <model> <n_siblings> <stage> [reason]
#   Rscript rf_b5_design_lib.R verify <base_id> <lane_design.json> <round> <compose_only 0|1> <admitted_csv|-> <rejected_csv|->
#   Rscript rf_b5_design_lib.R claim <claim_dir> <owner_pid> <stale_hours> / release <claim_dir>
#                                                                         → release: 마지막 줄 "release: <reason>[ | <err>]" · 0 인수 가능(marker_left 포함) · 1 실패
#   Rscript rf_b5_design_lib.R outcomes <out.csv>
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- { .r <- Sys.getenv("QVEST_RF_ROOT", "")
          if (nzchar(.r)) .r else Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot") }
ROOT <- sub("/+$", "", gsub("\\", "/", ROOT, fixed = TRUE))

## ★코드 루트는 데이터 루트가 아니다 — 자기 라이브러리는 **자기 위치**에서 읽는다(self-first · b1 lib 규약).
##   source() 되면 그 프레임의 ofile, Rscript <이 파일> 이면 --file=. ★--file= 은 **이 파일일 때만** 믿는다 —
##   검사 스크립트가 이 파일을 source() 하면 --file= 은 검사 파일을 가리킨다(첫 판은 그걸 코드 루트로 읽으려 했다).
##   (normalizePath 금지 — 한글 경로 파손)
.b5_self_path <- function() {
  for (i in rev(seq_len(sys.nframe()))) {
    of <- tryCatch(get0("ofile", envir = sys.frame(i), inherits = FALSE), error = function(e) NULL)
    if (is.character(of) && length(of) == 1L && grepl("rf_b5_design_lib", of)) return(of)
  }
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a) && grepl("rf_b5_design_lib", a[1])) return(sub("^--file=", "", a[1]))
  ""
}
.CODE_ROOT <- local({
  ov <- Sys.getenv("QVEST_B5_CODE_ROOT", "")
  if (nzchar(ov)) return(sub("/+$", "", gsub("\\", "/", ov, fixed = TRUE)))
  sp <- gsub("\\", "/", .b5_self_path(), fixed = TRUE)
  if (nzchar(sp) && file.exists(sp)) {
    cr <- sub("/02_Infrastructure/ops/?$", "", dirname(sp))
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
  cat(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null"), "\n", sep = "", file = p, append = TRUE)
  cat(sprintf("[b5_design] %s\n", event))
}
.num <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA_real_)); if (length(v)) v[1] else NA_real_ }
.chr <- function(x) { v <- suppressWarnings(as.character(x %||% "")); v <- v[!is.na(v)]; if (length(v)) v[1] else "" }
.cap <- function(x, n) { x <- .chr(x); if (nchar(x) > n) paste0(substr(x, 1L, n), "…") else x }
.f3 <- function(x) { v <- .num(x); if (is.finite(v)) formatC(v, digits = 3, format = "f") else "NA" }
.f1 <- function(x) { v <- .num(x); if (is.finite(v)) formatC(v, digits = 1, format = "f") else "NA" }

# ── 설정 ─────────────────────────────────────────────────────────────────────
#' 기본값은 설정이 깨졌을 때의 마지막 방어선이다 — 정책은 06_Registry/reinforce_auto_config.json::b5_design.
#'   ★enabled 는 블록이 **명시적으로** true 일 때만 켠다(b1_design 과 같은 규약 · 부재 = 꺼짐).
B5_DEFAULTS <- list(enabled = FALSE, max_cells = 8L, min_cells = 3L, max_new_arms = 3L, max_layers = 3L, prior_entries = 12L,
                    guards = list(max_redesign_rounds = 1L, daily_arm_cap = 6L, stagnation_window = 2L, max_active_generated = 40L))
B5_TOTAL_CELLS  <- 15L        # rfbd_verify 기본 상한 · rfbd_cells 코드 B5_16.. — entry 총 설계 칸(B5_16..B5_30)
B5_CODE_BASE    <- 16L        # rf_block_design.R::rfbd_cells .base_n(B5) 와 같은 값
B5_MAT_CAP_CHARS <- 60000L    # 재료 총량 상한(문자) — 넘으면 앞선 논문 교훈을 오래된 것부터 덜어낸다
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
  out$enabled <- isTRUE(b$enabled)
  out
}

# ── 경로 ─────────────────────────────────────────────────────────────────────
b5_design_dir  <- function(root, base_id) file.path(root, ".cache/rf_b5_design", base_id)
b5_lane_design <- function(root, base_id, round) file.path(b5_design_dir(root, base_id), sprintf("design_r%d.json", as.integer(round)))
b5_final_path  <- function(root, base_id) rfbd_path(root, base_id, "B5")     # 러너가 읽는 정본 위치(rf_block_design)
b5_mech_backup <- function(root, base_id) file.path(b5_design_dir(root, base_id), sprintf("%s_B5.mech.json", substr(base_id, 1, 50)))
.b5_atomic_write <- function(txt, p) {
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(p, ".tmp"); write(txt, tmp)
  ok <- suppressWarnings(file.rename(tmp, p))
  if (!ok) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
  invisible(p)
}

# ── 원장 · 격자 ──────────────────────────────────────────────────────────────
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
.b5_prog     <- function(root) tryCatch(fromJSON(file.path(root, "06_Registry/reinforce_program.json"), simplifyVector = FALSE), error = function(e) NULL)
.b5_standing <- function(root) {
  sc <- tryCatch(rfbd_standing_cells(root), error = function(e) list())
  list(codes = unique(vapply(sc, function(x) .chr(x$code), character(1))),
       picks = tryCatch(rfbd_standing_picks(root), error = function(e) character(0)),
       cells = sc)
}

#' 블록 칸 수 — 설계 파일이 있으면 그 칸 수(B1 = rf_b1_design · B2/B3/B5 = rf_block_design), 없으면 격자 칸 수.
#'   ★rf_b1_design_lib.R 은 source 시 자기 CLI 블록이 이 프로세스의 commandArgs(materials/verify)를 읽고 실행해 버리므로 적재하지 않는다 —
#'     경로 규약(.cache/rf_b1_design/<base_id 앞 60자>.json · rf_b1_design_cells 정의부)만 여기서 읽는다.
.b5_grid_n <- function(root, block) {
  g <- .b5_prog(root)
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

#' 이 entry 의 블록 순서 — 기록돼 있으면 그것, 없으면 러너와 **같은 규칙·같은 전제조건**으로 예측한다.
#'   러너(reinforce_auto_parallel.R): 미기록 ∧ used ≥ 5 ∧ 미결 0 → rf_block_order_decide 로 기록 · 그 밖엔 격자(program) 순서로 돈다.
#' @return list(order, source ∈ recorded/predicted/program/unavailable)
b5_block_order <- function(E, root = ROOT) {
  ord <- as.character(unlist(E$block_order %||% list())); ord <- ord[nzchar(ord)]
  if (length(ord)) return(list(order = ord, source = "recorded"))
  prog <- .b5_prog(root)
  ids <- vapply(prog$blocks %||% list(), function(b) .chr(b$id), character(1))
  if (!length(ids)) return(list(order = character(0), source = "unavailable"))
  used <- as.integer(.num(E$attempts_used %||% 0L)); if (is.na(used)) used <- 0L
  pending <- Filter(function(a) !.b5_measured(a) && !isTRUE(a$terminal), E$attempts %||% list())
  if (used < 5L || length(pending)) return(list(order = ids, source = "program"))
  dec <- tryCatch({
    en <- new.env(parent = globalenv())
    invisible(capture.output(suppressMessages(source(.b5_lib("02_Infrastructure/reinforcement/rf_lesson.R"), local = en))))
    en$rf_block_order_decide(E, prog, root = root)
  }, error = function(e) NULL)
  o <- as.character(unlist(dec$order %||% list())); o <- o[nzchar(o)]
  if (length(o)) list(order = o, source = "predicted") else list(order = ids, source = "program")
}

#' 다음 블록이 B5 인가 — 자동 설계의 발화 조건. TRUE ⇔ entry active ∧ B5 시도 0 ∧ 순서(기록 또는 예측)에서 B5 앞의
#'   모든 블록이 **완전 측정**(그 블록 칸 수만큼 서로 다른 코드가 측정 또는 terminal 로 닫혔고 미결 시도가 없다).
#' @return logical(1) + attr(,"why")
b5_next_block_is_b5 <- function(E, root = ROOT) {
  .no <- function(why) structure(FALSE, why = why)
  if (is.null(E)) return(.no("entry 부재"))
  if (!identical(E$status, "active")) return(.no(sprintf("entry status=%s", .chr(E$status))))
  atts <- E$attempts %||% list(); codes <- .b5_codes(atts)
  if (any(!is.na(codes) & startsWith(codes, "B5_"))) return(.no("B5 시도가 이미 있다(자동 설계는 B5 착수 전 1회)"))
  bo <- b5_block_order(E, root); ord <- bo$order
  if (!("B5" %in% ord)) return(.no(sprintf("블록 순서(%s)에 B5 가 없다", bo$source)))
  before <- ord[seq_len(match("B5", ord) - 1L)]
  for (b in before) {
    idx <- which(!is.na(codes) & startsWith(codes, paste0(b, "_")))
    done <- unique(codes[idx][vapply(atts[idx], function(a) .b5_measured(a) || isTRUE(a$terminal), logical(1))])
    pend <- any(vapply(atts[idx], function(a) !.b5_measured(a) && !isTRUE(a$terminal), logical(1)))
    need <- .b5_block_n_cells(root, E, b)
    if (pend || length(done) < need)
      return(.no(sprintf("앞 블록 %s 미완(닫힘 %d/%d%s · 순서 %s=%s)", b, length(done), need, if (pend) " · 미결 있음" else "",
                         bo$source, paste(ord, collapse = ">"))))
  }
  structure(TRUE, why = sprintf("다음 블록 = B5 (순서 %s=%s · 앞 블록 %s 완료)", bo$source, paste(ord, collapse = ">"),
                                if (length(before)) paste(before, collapse = ",") else "없음"))
}

# ── arm 성과 이력 (전 L1 entry · B5 칸만) ────────────────────────────────────
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
.b5_spec_of <- function(a) { sp <- .chr(a$essence$spec); if (nzchar(sp) && file.exists(sp)) tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL) else NULL }

#' arm id 별 성과 이력 — 전 L1 entry 의 **B5 칸** 자기 층(overlay_cell > overlay − carry)을 모아
#'   Δ = 그 칸 − **같은 entry 의 B1 시도 중앙값**(MDD·CAGR·PORT_t·Calmar) 을 arm 별 중앙값으로 접는다.
#'   ★B5 칸만 (2026-09-17 감사): 구판은 전 블록을 훑었다. B2/B3/B4 칸은 block_accumulate 바닥의 B5 층을 스펙에 싣는데
#'     구 스펙엔 overlay_cell 이 없어 .ov_own_layers 가 그 층을 **그 칸의 처치**로 돌려준다 — 실측 오염: multivar_channel_tilt
#'     사용 30회/8 entry · csd_idio_tilt 44회/16 entry(entry 당 B5 칸은 1~2개다). 기전 지도(rf_mechanism_map)도 B5_ 만 센다.
#'   ★부호: ΔMDD < 0 = 낙폭이 줄었다 · ΔCalmar > 0 = 개선. B1 기준이 없는 entry 는 Δ 를 정의할 수 없어 뺀다.
#'   adv_pass/adv_fail = 그 칸의 G2 사후 반증 verdict 집계(rf_record_adversary). 상주 arm·상주 칸은 뺀다(상주는 별도 측정).
#' @return data.table(arm_id, uses, stacked_uses, n_entries, med_d_mdd, med_d_cagr, med_d_port_t, med_d_calmar, adv_pass, adv_fail, adv_other)
rf_overlay_outcomes <- function(root = ROOT) {
  empty <- data.table(arm_id = character(), uses = integer(), stacked_uses = integer(), n_entries = integer(),
                      med_d_mdd = numeric(), med_d_cagr = numeric(), med_d_port_t = numeric(), med_d_calmar = numeric(),
                      adv_pass = integer(), adv_fail = integer(), adv_other = integer())
  led <- .b5_ledger(root); if (is.null(led)) return(empty)
  st <- .b5_standing(root)
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
    for (j in seq_along(atts)) {
      a <- atts[[j]]; cc <- codes[j]
      if (is.na(cc) || !startsWith(cc, "B5_") || cc %in% st$codes) next
      S <- .b5_spec_of(a); if (is.null(S)) next
      o <- .b5_own_ids(S, carry_ov, k2i); ids <- setdiff(o$ids, st$picks)
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
  .md <- function(x) { v <- x[is.finite(x)]; if (length(v)) stats::median(v) else NA_real_ }
  out <- R[, .(uses = .N, stacked_uses = sum(stacked), n_entries = uniqueN(base_id),
               med_d_mdd = .md(d_mdd), med_d_cagr = .md(d_cagr), med_d_port_t = .md(d_port_t), med_d_calmar = .md(d_calmar),
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
    ids <- as.character(unlist(r$new_arm_ids %||% list())); ids <- ids[!is.na(ids) & nzchar(ids)]
    n <- as.integer(.num(r$new_arms_admitted)); if (is.na(n)) n <- length(ids)
    rows[[length(rows) + 1L]] <- data.table(base_id = .chr(e$base_id), round = as.integer(.num(r$round)), at = .chr(r$at),
                                            n_new = n, ids = list(ids))
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
  if (!is.null(attr(out, "status")) && !identical(as.integer(attr(out, "status")), 0L)) return(NA_integer_)
  v <- suppressWarnings(as.integer(trimws(gsub("\r", "", as.character(out %||% character(0))))))
  v <- v[!is.na(v)]; if (length(v)) v[length(v)] else NA_integer_
}
.b5_is_generated <- function(a) .chr(a$source) %in% c("b5_design", "overlay_propose") || grepl("^(gen_|b5gen_)", .chr(a$kind))
.b5_n_active_generated <- function(root = ROOT) {
  st <- .b5_standing(root)
  sum(vapply(.b5_catalog(root), function(a) identical(.chr(a$status), "active") && !(.chr(a$id) %in% st$picks) && .b5_is_generated(a),
             logical(1)))
}

#' 가드 판정 — 모든 결정을 jlog 에 남긴다(overlay_guard_<name>). 거부(ok=FALSE)면 레인은 LLM 을 부르지 않는다.
#' @return list(ok, refuse_reason, mode, round, compose_only, compose_reasons, arm_quota, n_today, n_active_generated)
b5_guards <- function(E, root = ROOT, cfg = b5_cfg(root), mode = c("auto", "redesign")) {
  mode <- match.arg(mode); g <- cfg$guards; bid <- .chr(E$base_id)
  rounds <- .b5_rounds_of(E); rn <- vapply(rounds, function(r) as.integer(.num(r$round)), integer(1))
  out <- list(ok = TRUE, refuse_reason = "", mode = mode, round = 1L, compose_only = FALSE, compose_reasons = character(0),
              arm_quota = cfg$max_new_arms, n_today = NA_integer_, n_active_generated = NA_integer_)
  .refuse <- function(reason, why) {
    .b5_log("overlay_guard_h1_once", base_id = bid, mode = mode, decision = "refuse", reason = reason, why = why)
    out$ok <- FALSE; out$refuse_reason <- reason; out }
  # H1 — entry 당 자동 설계 1회 · 수동 재설계 상한 · 비활성 entry 거부
  if (!identical(.chr(E$status), "active"))
    return(.refuse("h1_entry_not_active", sprintf("entry status=%s — 러너가 돌지 않는 entry 의 B5 는 설계하지 않는다", .chr(E$status))))
  if (mode == "auto") {
    if (any(rn == 1L, na.rm = TRUE)) return(.refuse("h1_already_designed", "round 1 이미 기록(entry 당 자동 설계 1회)"))
    out$round <- 1L
    .b5_log("overlay_guard_h1_once", base_id = bid, mode = mode, decision = "pass", round = 1L)
  } else {
    n_re <- sum(rn >= 2L, na.rm = TRUE)
    if (n_re >= g$max_redesign_rounds)
      return(.refuse("h1_max_redesign_rounds", sprintf("재설계 %d회 ≥ 상한 %d(guards.max_redesign_rounds)", n_re, g$max_redesign_rounds)))
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
  if (quota <= 0L) out$compose_reasons <- c(out$compose_reasons, if (is.na(n_today)) "h2_counter_failed" else "h2_quota")
  # H3 — 정체: 새 arm 을 낸 최근 window 라운드의 arm 이 어느 것도 G2 pass B5 칸의 자기 층에 없다
  led <- .b5_ledger(root); allr <- .b5_all_rounds(if (is.null(led)) list() else led)
  arm_r <- allr[n_new > 0L]
  if (nrow(arm_r)) setorderv(arm_r, "at")
  last <- if (g$stagnation_window > 0L) utils::tail(arm_r, g$stagnation_window) else arm_r[0]
  h3 <- FALSE; ids3 <- character(0); pass3 <- character(0)
  if (g$stagnation_window > 0L && nrow(last) == g$stagnation_window) {
    ids3 <- unique(unlist(last$ids)); pass3 <- b5_pass_arm_ids(root)
    h3 <- length(ids3) > 0L && !any(ids3 %in% pass3)
  }
  .b5_log("overlay_guard_h3_stagnation", base_id = bid, decision = if (h3) "compose_only" else "pass",
          window = g$stagnation_window, arm_rounds_seen = nrow(last), recent_arms = paste(ids3, collapse = ","),
          recent_arms_passed = paste(intersect(ids3, pass3), collapse = ","),
          note = "창 = 새 arm 을 낸 라운드만(배합 라운드로 창을 비우는 교대 우회 차단) · 해제 = 그 arm 중 하나가 G2 pass")
  if (h3) out$compose_reasons <- c(out$compose_reasons, "h3_stagnation")
  # H4 — 활성 생성 arm 상한
  nag <- .b5_n_active_generated(root); out$n_active_generated <- nag
  h4 <- nag > g$max_active_generated
  .b5_log("overlay_guard_h4_active_generated", base_id = bid, decision = if (h4) "compose_only" else "pass",
          n_active_generated = nag, max_active_generated = g$max_active_generated)
  if (h4) out$compose_reasons <- c(out$compose_reasons, "h4_active_generated")
  out$compose_only <- length(out$compose_reasons) > 0L
  if (out$compose_only) out$arm_quota <- 0L
  out
}

# ── 날짜 제거 — 설계자는 특정 시기를 알면 안 된다(사후 지식 = 달력 리터럴의 씨앗) ─────────
#'   식별자(RP_20260917_… · L-RF-20260905_… · arXiv 2002.06975 · v10.4 · 소수 0.2008)는 보존한다.
#'   ★이름 붙은 위기 구간(GFC·리먼·코로나 …)도 시기 지시어다 — 연도를 지워도 이름이 남으면 같은 사후 지식이다.
B5_DATE_RULES <- c(
  iso_date = "(?<![\\w.])(19[89]\\d|20[0-3]\\d)-(0[1-9]|1[0-2])(-(0[1-9]|[12]\\d|3[01]))?(?![\\w])",
  slash    = "(?<![\\w.])(19[89]\\d|20[0-3]\\d)/(0?[1-9]|1[0-2])(/\\d{1,2})?(?![\\w])",
  dot_ym   = "(?<![\\w.])(19[89]\\d|20[0-3]\\d)\\.(0[1-9]|1[0-2])(?![\\d\\w])",
  kor      = "(?<![\\w.])(19[89]\\d|20[0-3]\\d)년(\\s?(0?[1-9]|1[0-2])월)?",
  kor_md   = "(?<![\\w.])(0?[1-9]|1[0-2])월\\s?(0?[1-9]|[12]\\d|3[01])일",
  bare_yr  = "(?<![\\w.\\-/])(19[89]\\d|20[0-3]\\d)(?![\\w.\\-/])")
B5_EPISODE_RULE <- "(?i:\\b(GFC|COVID(-19)?|Lehman|dot-?com|taper tantrum|Brexit)\\b)|리먼|코로나|닷컴|(글로벌\\s?|세계\\s?)?금융\\s?위기|외환\\s?위기|테이퍼\\s?탠트럼|브렉시트"
b5_strip_dates <- function(x) {
  for (nm in names(B5_DATE_RULES))
    x <- gsub(B5_DATE_RULES[[nm]], if (nm == "bare_yr") "<yr>" else "<date>", x, perl = TRUE)
  gsub(B5_EPISODE_RULE, "<episode>", x, perl = TRUE)
}
b5_has_dates <- function(x) any(vapply(c(B5_DATE_RULES, episode = B5_EPISODE_RULE), function(rx) any(grepl(rx, x, perl = TRUE)), logical(1)))

# ── 교차 entry 수치 가림 (D-E-B5-MATERIALS 2026-09-25 · pit.md C1 D-E) ─────────────────────────────
#   정본 = rf_b1_design_lib.R 의 가림 규칙·함수(R2). ★사본을 두지 않는다 — 두 레인의 규칙이 갈리면 한쪽만 새는 구멍이 된다.
#   ★그 파일을 source() 하지 않는다: 최상위에서 setwd(ROOT) 를 하고, CLI 절이 이 프로세스의 commandArgs("materials <id> <out>")를
#     자기 인자로 읽어 **B1 재료를 이 출력 경로에 쓴다**(.b5_block_n_cells 의 같은 경고). 그래서 parse 해 아래 이름의 최상위 대입만
#     baseenv 위 새 환경에서 평가한다(부수효과 0). 이름이 하나라도 없거나 둘이면 NULL(fail-closed).
#   적재마다 양성 대조 — 가림이 실제로 가리고(검증기 TRUE→FALSE) 식별자를 보존하는지 확인 못 하면 NULL(무발화 계기를 방어선으로 세지 않는다).
B5_REDACT_NAMES <- c("RF_B1_STAT_PROTECT", "RF_B1_STAT_RULES", "RF_B1_STAT_METRIC", "RF_B1_STAT_MASK", "rf_b1_redact_stats", "rf_b1_has_stats")
#' 자기·정적 절 — 이 entry 자신(측정표·기전·바닥 해부) · 정적 계약 · 이 라운드 설정. **그 밖의 절은 전부 교차 = 가림**
#'   (새 절을 조립 순서에 더하면 기본으로 가려진다 — 빠뜨려서 새는 길이 없다).
B5_OWN_SECTIONS <- c("entry", "floor", "contract", "guard")
B5_OUTCOME_ROWS <- 40L        # (3) arm 사용 이력 표 상한 — arm_id 순으로 자른다(성과와 무관한 절단)
B5_RX_CANARY <- "B5_22 xs_vol_gap_corr_brake Calmar 0.763 · MDD 0.287~0.615 · 폭 5.5%p · PORT_t 3 · arXiv 2002.06975 · v10.4"
.b5_redactor <- function(path = .b5_lib("02_Infrastructure/ops/rf_b1_design_lib.R")) {
  if (!file.exists(path)) return(NULL)
  ex <- tryCatch(parse(path, keep.source = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(ex)) return(NULL)
  en <- new.env(parent = baseenv()); got <- character(0)
  for (e in as.list(ex)) {
    if (!is.call(e) || length(e) != 3L || !(identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) || !is.name(e[[2]])) next
    nm <- as.character(e[[2]]); if (!(nm %in% B5_REDACT_NAMES)) next
    if (nm %in% got) return(NULL)                                          # 같은 이름 두 번 = 어느 것이 정본인지 모른다
    ok <- tryCatch({ eval(e, envir = en); TRUE }, error = function(err) FALSE); if (!ok) return(NULL)
    got <- c(got, nm)
  }
  if (!setequal(got, B5_REDACT_NAMES)) return(NULL)
  red <- en$rf_b1_redact_stats; has <- en$rf_b1_has_stats; mask <- en$RF_B1_STAT_MASK
  if (!is.function(red) || !is.function(has) || !is.character(mask) || length(mask) != 1L || !nzchar(mask) || grepl("[0-9]", mask)) return(NULL)
  rc <- tryCatch(red(B5_RX_CANARY), error = function(err) NA_character_)
  if (!is.character(rc) || length(rc) != 1L || is.na(rc) || !isTRUE(has(B5_RX_CANARY)) || isTRUE(has(rc)) ||
      !grepl(mask, rc, fixed = TRUE) || grepl("0.763", rc, fixed = TRUE) ||
      !all(vapply(c("B5_22 xs_vol_gap_corr_brake", "2002.06975", "v10.4"), grepl, logical(1), x = rc, fixed = TRUE))) return(NULL)
  list(redact = red, has = has, mask = mask, path = path)
}
.B5_RX <- new.env(parent = emptyenv())
.b5_rx <- function() {   # 프로세스당 1회 적재(재료 1건 = 1 프로세스) · NULL 도 캐시한다(= 매 호출 fail-closed)
  if (!exists("rx", envir = .B5_RX, inherits = FALSE)) assign("rx", .b5_redactor(), envir = .B5_RX)
  get("rx", envir = .B5_RX, inherits = FALSE)
}
#' 교차 텍스트 절단 — 가림 **앞뒤 2회**(앞: 온전한 수치를 가린다 · 뒤: 절단이 식별자 가운데를 잘라 생긴 소수 모양 조각을 가린다 · 멱등)
#'   (D-E-B5-LABELS) 결과 라벨도 같은 자리에서 앞뒤로 가린다 — 라벨 먼저(사유 문자열 "failed: T1,T3" 를 통째로 잡는다) · 수치 다음.
#'   lb = .b5_labeler() 산출(재료 1건마다 새로 세운다 · 캐시 없음) — 없으면 멈춘다(라벨을 가리지 않은 교차 텍스트는 내지 않는다).
.b5_capx <- function(x, n, lb = NULL) {
  rx <- .b5_rx(); if (is.null(rx)) stop("[b5_design] 가림 함수 부재 — 교차 텍스트를 가리지 않고 내지 않는다")
  if (!is.list(lb) || !is.function(lb$redact)) stop("[b5_design] 라벨 가림기 부재 — 교차 텍스트를 가리지 않고 내지 않는다")
  sx <- function(s) rx$redact(lb$redact(s))
  sx(.cap(sx(.chr(x)), n))
}

# ── 교차 entry 결과 라벨 가림 (도훈 결정 D-E-B5-LABELS 2026-09-25 · pit.md C1 D-E) ─────────────────────────────
#   왜: 수치를 가려도(D-E-B5-MATERIALS) 결과 **라벨**이 남으면 같은 선정이다 — (4b) "fail(failed: T1,T3)" · "실패 사인 T3 4건" ·
#   (6) 기전 지도 "포화/미포화"(+ 그 순서) · (2b) "오버레이 반증 pass 0/114 (dead)" 는 다른 entry 의 전기간 반증·측정 결과다.
#   무인 설계자가 "한 번도 안 죽은 arm · 미포화 칸" 을 고르면 평가 창 결과를 소비하는 자동 선정이다(C1 D-E).
#   방식 = B5M 가림 체계에 라벨 규칙을 더한다: ① 절단 앞뒤(.b5_capx) ② 조립부 교차 절 기본 가림(.label_x) ③ 발송 전 재도출 게이트.
#   ★어휘는 나열하지 않는다 — **코드가 실제로 낸 문자열**에서 재료 1건마다 다시 세운다(.b5_label_sources · 캐시 없음):
#     G2 = 원장 attempt$adversary 기록(verdict·analytic_verdict·reason 과 그 머리·tests.*.status·history verdict — rf_overlay_adversary 가 쓴 값)
#     생산자 상수 = rf_mechanism_map.R::RFM_VCLASSES(판정 등급) · rf_overlay_adversary.R::ADV_DEFERRED_VERDICT(parse 만 — 평가 없음)
#     포화 = rf_mechanism_map.R::rf_target_brief 본문 ifelse(<saturated>, a, b) 의 리터럴(AST) · 디렉터 = 소비하는 컨텍스트의 overlay$status
#   검사 이름(tests 의 키)은 단독으로는 가리지 않는다(정의 어휘 — (7) 계약이 쓴다). 라벨 뒤 목록("failed: T1,T3" · "fail T3")·개수("pass 3/10" · "fail 7")는 함께 가린다.
#   경계: ASCII = 영숫자·_·- 가 이어지면 안 가린다(bypass · dead-end · b5gen_pass_1 보존) · 한글 = 앞뒤가 한글이면 안 가린다(포화한다 보존 · 조사 1자는 허용).
#   절 원천 가림(구조·순서·유무 패턴으로도 새는 곳은 라벨 자리에 표식을 직접 쓴다): (2b) 구속·형태·계보 수·방어형 수·반증 집계 ·
#     (4b) 검사별 상태·판정·사유·집계(검사 칸의 '-' 유무가 후보 여부를 드러낸다) · (5) 극성 · (6) 판정·미검증 수·포화 + 행 순서(구판 = 포화 순).
#   자기·정적 절((1)·(2)·(7)·(8))은 건드리지 않는다(바이트 동일 — 자기 entry 라벨은 유지).
#   원천 결손(상수·포화 리터럴을 못 찾음) 또는 적재 양성 대조 실패 = NULL → 재료를 쓰지 않는다(materials_rejected · labeler_unavailable).
B5_LABEL_MASK <- "<label>"
B5_LABEL_PARTICLES <- "은는이가을를로와과의도만에"   # 은는이가을를로와과의도만에 — 한글 라벨 뒤 조사 1자
.B5_HANGUL <- "가-힣"
.b5_rx_esc <- function(s) gsub("([\\\\^$.|?*+()\\[\\]{}])", "\\\\\\1", s, perl = TRUE)
#' 토큰 1개의 정규식 — 앞뒤 경계는 토큰 첫·끝 글자의 종류로 정한다(ASCII 단어 / 한글) · ci = ASCII 대소문자 무시
.b5_tok_rx <- function(t, ci = TRUE) {
  a <- "A-Za-z0-9_\\-"; h <- .B5_HANGUL
  f1 <- substr(t, 1L, 1L); fn <- substr(t, nchar(t), nchar(t))
  isa <- function(ch) grepl("^[A-Za-z0-9_]$", ch, perl = TRUE); ish <- function(ch) grepl(sprintf("^[%s]$", h), ch, perl = TRUE)
  pre  <- if (isa(f1)) sprintf("(?<![%s])", a) else if (ish(f1)) sprintf("(?<![%s])", h) else ""
  post <- if (isa(fn)) sprintf("(?![%s])", a) else if (ish(fn)) sprintf("(?:(?![%s])|(?=[%s](?![%s])))", h, B5_LABEL_PARTICLES, h) else ""
  core <- .b5_rx_esc(t); if (ci && grepl("[A-Za-z]", t)) core <- sprintf("(?i:%s)", core)
  paste0(pre, core, post)
}
#' 최상위 `name <- "<문자열 1개>"` 하나 — parse 만(평가 없음 · 부수효과 0) · 없거나 둘 이상·비문자 = NULL
.b5_const_str <- function(path, name) {
  ex <- if (file.exists(path)) tryCatch(parse(path, keep.source = FALSE, encoding = "UTF-8"), error = function(e) NULL) else NULL
  if (is.null(ex)) return(NULL)
  hit <- list()
  for (e in as.list(ex)) if (is.call(e) && length(e) == 3L && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
                            identical(e[[2]], as.name(name))) hit[[length(hit) + 1L]] <- e[[3]]
  if (length(hit) != 1L || !is.character(hit[[1]]) || length(hit[[1]]) != 1L || is.na(hit[[1]]) || !nzchar(hit[[1]])) return(NULL)
  hit[[1]]
}
#' 함수 본문의 ifelse(<cond 가 든 식>, "a", "b") 리터럴 — 생산자가 실제로 내는 라벨 문자열(AST · 평가 없음)
#'   가지가 이름(생산자 상수)이면 그 함수의 환경에서 문자열 상수 1개로 풀어 쓴다(생산자가 리터럴을 상수로 옮겨도 이어진다 · 풀리지 않으면 버린다).
.b5_ifelse_literals <- function(fn, cond) {
  out <- character(0)
  lit <- function(x) {
    if (is.character(x) && length(x) == 1L) return(x)
    if (is.name(x)) { v <- tryCatch(get(as.character(x), envir = environment(fn), mode = "character"), error = function(e) NULL)
                      if (is.character(v) && length(v) == 1L) return(v) }
    NULL
  }
  walk <- function(e) {
    if (!is.call(e)) return(invisible(NULL))
    h <- e[[1]]
    if (is.name(h) && identical(as.character(h), "ifelse") && length(e) == 4L && cond %in% all.names(e[[2]])) {
      a <- lit(e[[3]]); b <- lit(e[[4]]); if (!is.null(a) && !is.null(b)) out <<- c(out, a, b)
    }
    lst <- as.list(e)
    for (i in seq_along(lst)) if (!identical(lst[[i]], quote(expr = ))) walk(lst[[i]])
    invisible(NULL)
  }
  if (is.function(fn)) walk(body(fn))
  unique(out[!is.na(out) & nzchar(out)])
}
#' 라벨 어휘 원천 — 코드가 실제로 낸 문자열(원장·디렉터 컨텍스트) + 생산자 상수 + 생산자 함수 리터럴
.b5_label_sources <- function(root = ROOT) {
  led <- .b5_ledger(root)
  g2 <- character(0); tests <- character(0)
  for (E in led$entries %||% list()) for (a in E$attempts %||% list()) {
    adv <- a$adversary; if (!is.list(adv)) next
    tl <- if (is.list(adv$tests)) adv$tests else list()
    rs <- .chr(adv$reason)
    g2 <- c(g2, .chr(adv$verdict), .chr(adv$analytic_verdict), rs, if (grepl(":", rs, fixed = TRUE)) trimws(sub(":.*$", "", rs)) else character(0),
            unname(vapply(tl, function(z) if (is.list(z)) .chr(z$status) else "", character(1))),
            unname(vapply(adv$history %||% list(), function(h) if (is.list(h)) .chr(h$verdict) else "", character(1))))
    tests <- c(tests, names(tl))
  }
  dp <- file.path(root, ".cache/rf_director_context.json")
  d <- if (file.exists(dp)) tryCatch(fromJSON(dp, simplifyVector = FALSE), error = function(e) NULL) else NULL
  list(g2 = g2, tests = tests,
       const_classes = if (exists("RFM_VCLASSES", inherits = TRUE)) as.character(get("RFM_VCLASSES", inherits = TRUE)) else character(0),
       const_deferred = .b5_const_str(.b5_lib("02_Infrastructure/reinforcement/rf_overlay_adversary.R"), "ADV_DEFERRED_VERDICT") %||% character(0),
       sat = if (exists("rf_target_brief", mode = "function")) .b5_ifelse_literals(get("rf_target_brief", mode = "function"), "saturated") else character(0),
       dir = .chr((if (is.list(d) && is.list(d$overlay)) d$overlay else list())$status))
}
.b5_vocab_clean <- function(v) {
  v <- unique(trimws(as.character(unlist(v)))); v <- v[!is.na(v) & nchar(v) >= 2L]
  v <- v[grepl(sprintf("[A-Za-z%s]", .B5_HANGUL), v, perl = TRUE)]
  # 표식 안에 든 낱말(예: 어떤 판정 값이 "label" 이면)은 표식을 다시 가려 멱등이 깨진다 — 어휘에서 뺀다(표식 = 라벨·수치 두 종)
  mk <- c(B5_LABEL_MASK, (.b5_rx() %||% list(mask = ""))$mask)
  v[!vapply(v, function(t) any(grepl(tolower(t), tolower(mk), fixed = TRUE)), logical(1))]
}
#' 라벨 가림기 — list(redact, has, mask, vocab, tests, tok, n_src) · 원천 결손 또는 적재 양성 대조 실패 = NULL(fail-closed)
.b5_labeler <- function(root = ROOT) {
  src <- tryCatch(.b5_label_sources(root), error = function(e) NULL)
  if (is.null(src) || !length(src$const_classes) || !length(src$const_deferred) || length(src$sat) < 2L) return(NULL)
  vocab <- .b5_vocab_clean(c(src$g2, src$const_classes, src$const_deferred, src$sat, src$dir))
  tests <- .b5_vocab_clean(src$tests)
  if (!length(vocab)) return(NULL)
  vocab <- vocab[order(-nchar(vocab), vocab, method = "radix")]
  tok <- sprintf("(?:%s)", paste(vapply(vocab, .b5_tok_rx, character(1), USE.NAMES = FALSE), collapse = "|"))
  tail1 <- if (length(tests)) sprintf("\\s*[:,]?\\s*(?:%s)(?![A-Za-z0-9_])", paste(.b5_rx_esc(tests[order(-nchar(tests), tests, method = "radix")]), collapse = "|")) else ""
  cnt1 <- "\\s*[:=]?\\s*\\d+(?:\\s*/\\s*\\d+)?(?:\\s*건)?"   # 라벨에 붙은 개수: "pass 3/10" · "fail 7" · "4건"
  mask_rx <- sprintf("%s(?:%s)*", tok, if (nzchar(tail1)) paste0(cnt1, "|", tail1) else cnt1)
  mk <- .b5_rx_esc(B5_LABEL_MASK)
  has_rx <- c(tok = tok, after = sprintf("%s(?:\\s*[:=]?\\s*\\d%s)", mk, if (nzchar(tail1)) paste0("|", tail1) else ""))
  redact <- function(x) {
    x <- as.character(x); if (!length(x)) return(x)
    ok <- !is.na(x) & nzchar(x); x[ok] <- gsub(mask_rx, B5_LABEL_MASK, x[ok], perl = TRUE); x
  }
  has <- function(x) {
    x <- as.character(x); x <- x[!is.na(x)]; if (!length(x)) return(FALSE)
    any(vapply(has_rx, function(rx) any(grepl(rx, x, perl = TRUE)), logical(1)))
  }
  # 적재 양성 대조 — 어휘 전부가 실제로 가려지고(검증기 TRUE→FALSE) 식별자·경계 밖 낱말은 남는가
  hg <- vocab[grepl(sprintf("[%s]$", .B5_HANGUL), vocab, perl = TRUE)]
  asc <- vocab[grepl("[A-Za-z]", vocab)]
  keep <- c("bypass", "dead-end", "B5_22 xs_vol_gap_corr_brake", "Calmar", "2002.06975", if (length(hg)) paste0(hg[1], "한다"))   # ~한다
  canary <- paste(c(paste0("· ", vocab, " ·"), if (length(asc)) paste0(asc[1], " 3/10"), if (length(asc) && length(tests)) paste0(asc[1], ": ", tests[1]),
                    keep), collapse = " ")
  rc <- tryCatch(redact(canary), error = function(e) NA_character_)
  n_mask <- if (is.character(rc) && !is.na(rc)) lengths(regmatches(rc, gregexpr(B5_LABEL_MASK, rc, fixed = TRUE))) else 0L
  if (!is.character(rc) || length(rc) != 1L || is.na(rc) || !isTRUE(has(canary)) || isTRUE(has(rc)) || n_mask < length(vocab) ||
      grepl("3/10", rc, fixed = TRUE) || !all(vapply(keep, grepl, logical(1), x = rc, fixed = TRUE))) return(NULL)
  list(redact = redact, has = has, mask = B5_LABEL_MASK, vocab = vocab, tests = tests, tok = tok,
       n_src = c(g2 = length(.b5_vocab_clean(src$g2)), const = length(.b5_vocab_clean(c(src$const_classes, src$const_deferred))),
                 sat = length(src$sat), director = length(.b5_vocab_clean(src$dir))))
}

# ── 바닥 낙폭 해부 (날짜 없음) ───────────────────────────────────────────────
#' floor = 측정된 시도 중 PORT_t 최고 칸 — 러너가 다음 B5 배치의 바닥으로 까는 것과 같은 규칙(reinforce_auto_parallel.R .wbest_spec).
#'   산출물 02_nav.csv(nav_net) 의 낙폭 에피소드 상위 3 을 깊이·고점→저점 개월·수중 개월·회복 개월로, 같은 창(고점일~저점일)의
#'   KOSPI200(05_benchmark_returns.csv benchmark_nav) 점대점 낙폭과 그 비를 붙인다. 날짜는 내지 않는다.
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
  if (!length(atts)) return(c("## (2) 바닥 낙폭 해부: 측정된 칸이 없다"))
  pt <- vapply(atts, function(a) .num(a$essence$port_t), numeric(1)); a <- atts[[which.max(pt)]]
  code <- .rf_attempt_code(a); es <- a$essence
  hdr <- c(sprintf("## (2) 바닥(floor) 낙폭 해부 — 이 entry 최고 PORT_t 칸 %s (PORT_t %s · CAGR %s · MDD %s · Calmar %s) = 다음 B5 칸이 깔릴 바닥",
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

# ── 재료 ─────────────────────────────────────────────────────────────────────
B5_DISTILL_KEYWORDS <- c("오버레이", "낙폭", "MDD", "국면", "현금", "overlay", "drawdown", "regime")
.b5_axiom_brief <- function(root = ROOT) {
  sh <- .b5_lib("02_Infrastructure/ops/rf_axiom_brief.sh"); if (!file.exists(sh)) return(character(0))
  # ★rf_axiom_brief 는 ROOT > QVEST_RF_ROOT > QM_ROOT 순으로 루트를 읽는다 — 부모 셸이 ROOT 를 export 했으면 그게 이긴다. 명시한다.
  old <- Sys.getenv("QVEST_PY", NA); Sys.setenv(QVEST_PY = .b5_py())   # Windows 는 system2(env=) 무시 — 부모에 심는다
  on.exit(if (is.na(old)) Sys.unsetenv("QVEST_PY") else Sys.setenv(QVEST_PY = old), add = TRUE)
  cmd <- sprintf("ROOT='%s'; . '%s' && rf_axiom_brief", root, gsub("\\", "/", sh, fixed = TRUE))
  out <- tryCatch(suppressWarnings(system2("bash", c("-c", shQuote(cmd)), stdout = TRUE, stderr = FALSE)), error = function(e) character(0))
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
#' (B09-ALLOWLIST-PROMPT · 도훈 결정 2026-09-25 19시) probe ③d 허용 목록 — 재료 (7) 에 싣는 줄.
#'   렌더러 정본 = overlay_allowlist_prompt.R(코드 루트). 목록은 probe 자신의 적재기(overlay_probe_allowlist_params)로
#'   **데이터 루트(ROOT)** 에서 읽는다 — 이 lib 의 probe 명령(코드 루트 overlay_probe.R · overlay_probe_arm(kind, ROOT))과
#'   같은 파일·같은 루트다. 프롬프트가 보여주는 집합 = 등재가 대조하는 집합.
#'   ★미제공 = 재료를 막지 않는다(설계 선택 — 이 레인의 산출은 배합 칸 + 선택적 새 arm · 배합은 목록과 무관). 대신 미제공 블록을
#'     싣고 호출자가 (8) 에 '새 arm 을 내지 마라' 를 더하고 jlog 에 남긴다. 새 arm 의 fail-closed 는 probe ③d 가 진다.
#' @return list(ok, reason, lines, sha256, n_names, ...) — lines 는 언제나 1줄 이상
.b5_allowlist <- function(root = ROOT) {
  r <- tryCatch({
    en <- new.env(parent = globalenv())
    invisible(capture.output(suppressMessages(sys.source(.b5_lib("02_Infrastructure/reinforcement/overlay_allowlist_prompt.R"), envir = en))))
    en$overlay_allowlist_prompt(root, probe_path = .b5_lib("02_Infrastructure/reinforcement/overlay_probe.R"))
  }, error = function(e) list(ok = FALSE, reason = sprintf("렌더러 적재 실패 — %s", conditionMessage(e))))
  if (!is.list(r) || !is.character(r$lines) || !length(r$lines)) {
    why <- gsub("[\r\n]+", " ", .chr((if (is.list(r)) r$reason) %||% "렌더러 반환 이상"))
    r <- list(ok = FALSE, reason = why, sha256 = "", n_names = 0L,
              lines = c(sprintf("### 허용 함수 목록 — 미제공 (%s)", why),
                        "- ★probe ③d 는 허용 목록을 적재하지 못하면 모든 새 arm 을 거부한다(fail-closed). 이번에는 새 arm 을 내지 마라."))
  }
  r
}
#' 이 entry 의 B5 칸이 이미 잰 스택 키(정렬 id) — 설계 검증이 같은 스택을 다시 넣는 칸을 뺀다(H6)
.b5_measured_b5_keys <- function(E, root = ROOT) {
  k2i <- .b5_kind_to_id(.b5_catalog(root)); st <- .b5_standing(root); carry_ov <- (E$carry %||% list())$overlay
  keys <- character(0)
  for (a in Filter(.b5_measured, E$attempts %||% list())) {
    cc <- .rf_attempt_code(a); if (is.na(cc) || !startsWith(cc, "B5_") || cc %in% st$codes) next
    S <- .b5_spec_of(a); if (is.null(S)) next
    ids <- setdiff(.b5_own_ids(S, carry_ov, k2i)$ids, st$picks)
    if (length(ids)) keys <- c(keys, rfbd_stack_key(ids))
  }
  unique(keys)
}

# ── (4b) G2 사후 반증 상세 — 앞선 오버레이 칸이 **어떤 검사에서** 죽었나 ──────
#' 설계자에게 verdict 만 주면 같은 죽음을 반복한다. 실측(2026-09-19, 결합 계보):
#'   B5 칸 22개(결합 14 + promo1 8)가 연속으로 소비 보류됐고 사인은 거의 전부 T3 —
#'   **노출을 짝지어 무작위로 재배치한 플라시보가 관측 Calmar 이상**이었다. 즉 "같은 빈도로
#'   아무 때나 줄여도 같은 Calmar" 이고, 타이밍 기여는 0이었다. 그 사실이 재료에 없으면
#'   설계는 계속 '개선처럼 보이는 것'을 만든다(T4 상수 등가만 넘고 T3 에서 죽는다).
#' verdict·검사 수치는 원장 attempt$adversary(rf_record_adversary 기록)에서 **재도출**한다.
.b5_adv_rows <- function(root = ROOT, max_rows = 24L) {
  led <- .b5_ledger(root); if (is.null(led)) return(list())
  rows <- list()
  for (E in led$entries %||% list()) {
    bid <- .chr(E$base_id %||% E$id)
    for (a in E$attempts %||% list()) {
      adv <- a$adversary
      if (!is.list(adv) || !nzchar(.chr(adv$verdict))) next
      tests <- if (is.list(adv$tests)) adv$tests else list()
      g <- function(k) { v <- tests[[k]]; if (is.list(v)) v else list() }
      t1 <- g("T1"); t3 <- g("T3"); t3b <- g("T3b"); t4 <- g("T4")
      lay <- vapply(adv$own_layers %||% list(), function(o) .chr(o$arm_id %||% o$kind), character(1))
      rows[[length(rows) + 1L]] <- list(
        at = .chr(adv$recorded_at %||% adv$at), entry = bid,
        code = .chr(adv$code %||% .rf_attempt_code(a)),
        stack = if (length(lay)) paste(lay, collapse = " x ") else "-",
        cell = .num(adv$cell$calmar), floor = .num(adv$floor$calmar),
        verdict = .chr(adv$verdict), reason = .chr(adv$reason),
        t1s = .chr(t1$status), t1v = .num(t1$calmar_shift),
        t3s = .chr(t3$status), t3o = .num(t3$obs_calmar), t3q = .num(t3$placebo_q), t3p = .num(t3$p_value),
        t3bs = .chr(t3b$status), t3bp = .num(t3b$p_value),
        t4s = .chr(t4$status), t4c = .num(t4$const_calmar))
    }
  }
  if (!length(rows)) return(list())
  rows[order(vapply(rows, function(r) r$at, character(1)), decreasing = TRUE)][seq_len(min(length(rows), max_rows))]
}

#' (D-E-B5-LABELS 2026-09-25) 이 절은 전부 다른 entry 의 결과다 — 판정·검사별 상태·사유·실패 사인·개수는 라벨 표식, 수치는 수치 표식.
#'   ★검사 칸을 표식으로만 바꾸면 '-'(미검정) 유무가 후보 여부(= 바닥 Calmar 를 넘었나)를 드러낸다 — 그래서 결과를 한 칸으로 접는다.
#'   남는 것 = 어느 entry 의 어느 칸이 어떤 스택으로 사후 반증을 **거쳤나**(설계 이력) · 행 = 기록 시각 역순(결과와 무관).
.b5_adv_sec <- function(root = ROOT, max_rows = 24L, lb = NULL) {
  rows <- .b5_adv_rows(root, max_rows)
  mk <- if (is.list(lb) && is.character(lb$mask)) lb$mask else B5_LABEL_MASK
  sm <- (.b5_rx() %||% list(mask = "<stat>"))$mask     # 수치 표식 = 정본 가림 함수의 표식(rx 부재면 아래 .b5_capx 가 멈춘다)
  hdr <- c(sprintf("## (4b) G2 사후 반증 이력 — 앞선 오버레이 칸이 어떤 스택으로 사후 반증을 거쳤나 (최근 %d칸 · 전 entry)", as.integer(max_rows)),
           sprintf("- ★판정·검사별 상태·사유·실패 사인·개수는 %s, Calmar·검정 수치는 %s 로 가렸다 — 다른 entry 의 전기간 결과로 arm 을 고르면 평가 창 결과를 소비하는 자동 선정이다(pit.md C1 D-E).", mk, sm),
           "- 반증 검정의 구성과 소비 규약은 (7) 에 있다. 이미 반증을 거친 스택을 재탕하지 말고, 반증을 견딜 기전을 설계하라(축을 바꿔라).")
  if (!length(rows)) return(c(hdr, "(아직 반증 기록이 없다)"))
  tab <- c("", "| entry | 코드 | 스택 | 결과 |", "|---|---|---|---|")
  for (r in rows)
    tab <- c(tab, sprintf("| %s | %s | %s | %s · %s |",
                          # entry 는 접두 타임스탬프를 벗겨 **계보만** 남긴다(전부 같은 접두어라 30자 절단이면 구분이 사라진다)
                          # (D-E-B5-MATERIALS · LABELS) 절단은 가림(라벨·수치) 앞뒤 2회
                          .b5_capx(sub("^RP_[0-9]{8}_[0-9]{6}_[0-9]+_", "", r$entry), 30, lb), r$code, .b5_capx(r$stack, 42, lb), sm, mk))
  c(hdr, tab, "", sprintf("- 집계: %d칸 (판정별 개수·실패 사인은 가렸다 %s)", length(rows), mk))
}

# ── (2b) 프로그램 낙폭 구조 — 리서치 디렉터 컨텍스트 (2026-09-21 도훈 승인 플랜 Part 3 · D3 (c)) ──────────────
#   .cache/rf_director_context.json(rf_director.R 이 매일 아침 씀)의 **숫자만** 옮긴다. 서사·지침 없음(Dream-RSI §5.1: 기록은
#   시뮬레이터 산출로만 넘긴다). 날짜 없음 · 48h 초과·부재·파손 = 절 생략(설계는 종전과 동일). 검증부(b5_has_dates)가 그대로 적용된다.
#' (D-E-B5-LABELS) label_mask 를 주면 결과 라벨 자리(구속·공동 구속 · 낙폭 형태 · 공유 계보 수 · 방어형 수 · 오버레이 반증 집계·상태)를
#'   그 표식으로 **원천에서** 쓴다(재료 경로). 라벨 규칙 문장(shape_rule)은 형태 어휘를 담아 가린 라벨을 되살리므로 싣지 않는다.
#'   NULL(기본) = 구판 그대로(디렉터 문맥 자체의 검사 · 사람용 확인).
b5_director_context <- function(root = ROOT, max_age_h = 48, label_mask = NULL) {
  p <- file.path(root, ".cache/rf_director_context.json"); if (!file.exists(p)) return(character(0))
  age <- suppressWarnings(as.numeric(difftime(Sys.time(), file.info(p)$mtime, units = "hours"))); if (!is.finite(age) || age > max_age_h) return(character(0))
  d <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL); if (!is.list(d)) return(character(0))
  rc <- d$recurring_class %||% list(); pi <- d$pool_inventory %||% list(); b <- d$program_best %||% list(); ov <- d$overlay %||% list(); th <- d$thresholds %||% list()
  co <- as.character(unlist(d$co_binding %||% list()))
  if (is.character(label_mask) && length(label_mask) == 1L && nzchar(label_mask)) {
    m <- label_mask
    return(b5_strip_dates(c("## (2b) 프로그램 낙폭 구조 (리서치 디렉터 · 상위 계보 최심 에피소드 집계 · 날짜 없음 · 형태만)",
      # ★이 절 본문엔 숫자를 쓰지 않는다 — 발송 전 검증이 본문 정수 잔존을 개수 누출로 본다(수치는 조립부가 <stat> 로 가린다)
      sprintf("- ★구속 조건·낙폭 형태·공유 계보 수·방어형 수·오버레이 반증 집계는 다른 entry 의 전기간 결과 라벨이라 %s 로 가렸다(pit.md D-E) — 수치는 조립부가 가린다.", m),
      sprintf("- 구속 조건: %s · 프로그램 최고 PORT_t %s · Calmar %s · MDD %s · CAGR %s (A 문턱 Calmar %s)",
              m, .f3(b$port_t), .f3(b$calmar), .f3(b$mdd), .f3(b$cagr), .f3(th$calmar_min)),
      sprintf("- 낙폭 형태: %s · 최심 깊이 중앙 %s · 고점→저점 중앙 %s개월 · 벤치 대비 비 중앙 %s · 공유 계보 %s",
              m, .f3(rc$depth_median), .f1(rc$m_peak_trough_median), .f3(rc$ratio_median), m),
      sprintf("- 풀 재고: 방어형 %s · 깊은 낙폭 초과 중앙 %s%%/월 · 음수 비율 %s · 오버레이 반증 %s",
              m, .f3(pi$defensive_deep_dd_excess_median), .f3(pi$defensive_deep_dd_negative_share), m))))
  }
  L <- c("## (2b) 프로그램 낙폭 구조 (리서치 디렉터 · 상위 계보 최심 에피소드 집계 · 날짜 없음 · 형태만)",
         sprintf("- 구속 조건: %s%s · 프로그램 최고 PORT_t %s · Calmar %s · MDD %s · CAGR %s (A 문턱 Calmar %s)",
                 .chr(d$binding), if (length(co)) paste0("+", paste(co, collapse = "+")) else "", .f3(b$port_t), .f3(b$calmar), .f3(b$mdd), .f3(b$cagr), .f3(th$calmar_min)),
         sprintf("- 낙폭 형태: %s · 최심 깊이 중앙 %s · 고점→저점 중앙 %s개월 · 벤치 대비 비 중앙 %s · 공유 계보 %s (라벨 규칙: %s)",
                 .chr(rc$shape), .f3(rc$depth_median), .f1(rc$m_peak_trough_median), .f3(rc$ratio_median), .chr(rc$n_lineages_sharing), .chr(rc$shape_rule)),
         sprintf("- 풀 재고: 방어형 %s · 깊은 낙폭 초과 중앙 %s%%/월 · 음수 비율 %s · 오버레이 반증 pass %s/%s (%s)",
                 .chr(pi$defensive_n), .f3(pi$defensive_deep_dd_excess_median), .f3(pi$defensive_deep_dd_negative_share), .chr(ov$adv_pass), .chr(ov$n_verdict), .chr(ov$status)))
  b5_strip_dates(L)
}
#' (D-E-B5-MATERIALS) (2b) 는 교차 절이라 통째로 가려진다 — 그 안의 A 문턱(고정 축 상수 · 측정값 아님)만 자기·정적 절 (8) 로 옮겨 싣는다.
#'   같은 원천·같은 신선도 규칙(48h) · 부재·낡음·파손 = NULL(줄 생략 — 구판에서 (2b) 가 빠질 때와 같다).
.b5_director_thresholds <- function(root = ROOT, max_age_h = 48) {
  p <- file.path(root, ".cache/rf_director_context.json"); if (!file.exists(p)) return(NULL)
  age <- suppressWarnings(as.numeric(difftime(Sys.time(), file.info(p)$mtime, units = "hours"))); if (!is.finite(age) || age > max_age_h) return(NULL)
  d <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL); th <- if (is.list(d)) d$thresholds else NULL
  if (!is.list(th)) return(NULL)
  v <- c(calmar = .num(th$calmar_min), port_t = .num(th$port_t_min)); if (any(is.finite(v))) v else NULL
}

b5_materials <- function(base_id, root = ROOT, cfg = b5_cfg(root), compose_only = FALSE, arm_quota = cfg$max_new_arms,
                         round = 1L, out_p = NULL) {
  E <- .b5_entry(root, base_id); if (is.null(E)) stop("[b5_design] entry 부재: ", base_id)
  # (D-E-B5-MATERIALS) 가림 함수가 없으면 재료를 만들지 않는다 — 레인은 materials_failed 로 기록하고 기존 설계로 진행한다
  RX <- .b5_rx()
  if (is.null(RX)) {
    .b5_log("materials_rejected", base_id = base_id, round = as.integer(round), why = "redactor_unavailable",
            note = "rf_b1_design_lib.R 가림 함수 적재·양성 대조 실패 — 교차 entry 수치를 가리지 않은 재료는 내지 않는다(pit.md C1 D-E)")
    stop("[b5_design] 교차 entry 수치 가림 함수 적재 실패 — 재료 생성 중단(pit.md C1 D-E · 기존 설계로 폴백)")
  }
  # (D-E-B5-LABELS) 결과 라벨 가림기 — 어휘는 이 재료가 읽는 원장·컨텍스트·생산자에서 지금 다시 세운다(캐시 없음) · 못 세우면 재료를 만들지 않는다
  LB <- tryCatch(.b5_labeler(root), error = function(e) NULL)
  if (is.null(LB)) {
    .b5_log("materials_rejected", base_id = base_id, round = as.integer(round), why = "labeler_unavailable",
            note = "결과 라벨 어휘 원천(RFM_VCLASSES·ADV_DEFERRED_VERDICT·rf_target_brief 포화 리터럴) 결손 또는 적재 양성 대조 실패 — 라벨을 가리지 않은 재료는 내지 않는다(pit.md C1 D-E)")
    stop("[b5_design] 교차 entry 결과 라벨 가림기 적재 실패 — 재료 생성 중단(pit.md C1 D-E · 기존 설계로 폴백)")
  }
  arms <- .b5_catalog(root); k2i <- .b5_kind_to_id(arms)
  st <- .b5_standing(root)
  carry_ov <- (E$carry %||% list())$overlay
  sec <- list()
  # (1) entry 문맥 ───────────────────────────────────────────────────────────
  ap <- file.path(.chr(E$base_artifacts), "authoritative_remeasure.json")
  AR <- if (file.exists(ap)) tryCatch(fromJSON(ap, simplifyVector = FALSE), error = function(e) NULL) else NULL
  sp0 <- AR$replication$source_paper %||% list(); es0 <- AR$essence %||% list()
  papers <- E$combo$papers %||% list()
  ptxt <- if (length(papers)) paste(vapply(utils::head(papers, 6L), function(p) sprintf("%s(%s)", .cap(p$title, 60), .chr(p$key)), character(1)), collapse = " + ")
          else .chr(sp0$title %||% E$paper_key)
  bo <- b5_block_order(E, root)
  L1 <- c(sprintf("## (1) 이 entry — %s", base_id),
          sprintf("- 논문: %s", .cap(ptxt, 400)),
          sprintf("- 기저 등급 %s · 기저 PORT_t %s · CAGR %s · MDD %s · Calmar %s · OOS %s", .chr(E$base_grade),
                  .f3(es0$portfolio_alpha_t_nw_lag3 %||% es0$port_t), .f3(es0$cagr), .f3(es0$mdd %||% es0$max_drawdown), .f3(es0$calmar), .f3(es0$oos_retention)),
          sprintf("- 블록 순서(%s): %s · 시도 %s/%s · 이번 설계 라운드 %d%s", bo$source, paste(bo$order, collapse = ">"),
                  .chr(E$attempts_used), .chr(E$max_attempts %||% "25"), as.integer(round),
                  if (as.integer(round) >= 2L) " (재설계 — 측정된 칸은 그대로 두고 새 칸이 뒤에 붙는다)" else ""))
  cy <- E$carry
  if (!is.null(cy)) {
    .fid <- function(x) .chr((x %||% list())$id %||% (x %||% list())$catalog_id)
    ov_ids <- .ov_arm_ids(cy$overlay)
    L1 <- c(L1, sprintf("- ★승격 entry — 승계 팩터 %s · 승계 비중 %s · 승계 오버레이 %s (이미 켜져 있다 — 다시 고르지 마라)",
                        paste(vapply(cy$factors %||% list(), .fid, character(1)), collapse = ","),
                        .chr((cy$weighting %||% list())$label %||% (cy$weighting %||% list())$kind %||% "ew"),
                        if (length(ov_ids)) paste(ov_ids, collapse = "×") else "없음"))
  }
  L1 <- c(L1, "", "### 측정표 (권위 등급 essence · 15bps 판) — B5 칸의 스택 = 그 칸이 **직접 얹은** 층 · 다른 블록은 바닥에서 **승계**한 층",
          "| 코드 | 블록 | 라벨 | 오버레이 스택 | PORT_t | CAGR | MDD | Calmar | OOS | G2 반증 |", "|---|---|---|---|---|---|---|---|---|---|")
  nrow_tab <- 0L
  for (a in E$attempts %||% list()) {
    if (nrow_tab >= 45L) { L1 <- c(L1, "| … | (표 상한 45행) | | | | | | | | |"); break }
    code <- .rf_attempt_code(a); if (is.na(code)) code <- sprintf("n%s", .chr(a$n))
    S <- .b5_spec_of(a); lab <- .cap(S$label %||% sub("^\\[[^]]*\\]\\s*", "", .chr(a$idea)), 40)
    is_b5 <- startsWith(code, "B5_")
    stk_txt <- if (is.null(S)) "-" else if (is_b5) {
      ids <- .b5_own_ids(S, carry_ov, k2i)$ids; if (length(ids)) paste(ids, collapse = "×") else "-"
    } else {
      ids <- unique(vapply(.ov_layers(S$overlay), .b5_layer_id, character(1), k2i = k2i)); ids <- ids[nzchar(ids)]
      if (length(ids)) paste0("(승계) ", paste(ids, collapse = "×")) else "-"
    }
    if (is_b5 && code %in% st$codes) stk_txt <- paste0(stk_txt, " [상주]")
    adv <- .chr((a$adversary %||% list())$verdict); if (!nzchar(adv)) adv <- if (is_b5) "미실행" else "-"
    if (.b5_measured(a)) { es <- a$essence
      L1 <- c(L1, sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |", code, .chr(es$block %||% sub("_.*$", "", code)), lab,
                          stk_txt, .f3(es$port_t), .f3(es$cagr), .f3(es$mdd), .f3(es$calmar), .f3(es$oos_retention), adv))
    } else L1 <- c(L1, sprintf("| %s | %s | %s | %s | 미측정 | | | | | %s |", code, sub("_.*$", "", code), lab,
                               stk_txt, .cap(a$terminal_reason %||% "pending", 60)))
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
  # 현재 B5 설계 파일(있으면) — 기전 단계 설계 또는 이전 라운드
  measured_keys <- .b5_measured_b5_keys(E, root)
  fp <- b5_final_path(root, base_id)
  if (file.exists(fp)) {
    D0 <- tryCatch(fromJSON(fp, simplifyVector = FALSE), error = function(e) NULL)
    if (length(D0$cells %||% list())) {
      L1 <- c(L1, "", sprintf("### 현재 B5 설계 파일 (%s · %d칸)%s", .chr(D0$source %||% "기전 단계(next_block_design)"), length(D0$cells),
                              if (as.integer(round) >= 2L) " — 재설계면 이 칸들은 **그대로 남고** 네 칸이 뒤에 붙는다"
                              else " — 자동 설계(라운드 1)는 이 설계를 **대체**한다(원본은 백업)"))
      for (i in seq_along(D0$cells)) { ce <- D0$cells[[i]]; ids <- rfbd_cell_picks(ce)
        L1 <- c(L1, sprintf("- 칸 %d(B5_%d): %s — %s%s", i, B5_CODE_BASE + i - 1L, if (length(ids)) paste(ids, collapse = "×") else "(자리 보존)",
                            .cap(ce$label, 40), if (!length(ids)) "" else if (rfbd_stack_key(ids) %in% measured_keys) " [측정됨]" else " [미측정]")) }
    }
  }
  sec$entry <- L1
  # (2) 바닥 낙폭 해부 ───────────────────────────────────────────────────────
  sec$floor <- b5_floor_anatomy(E, root)
  sec$director <- tryCatch(b5_director_context(root, label_mask = LB$mask), error = function(e) character(0))   # D3 (c) · 부재/낡음/오류 = 생략 · (D-E-B5-LABELS) 결과 라벨은 원천에서 표식
  # (3) arm 사용 이력 ───────────────────────────────────────────────────────
  #   (D-E-B5-MATERIALS) 구판 = ΔCalmar 순 상위 8/하위 8 + Δ 네 개 + G2 pass/fail — 전부 다른 entry 의 전기간 측정값이고, 순위 자체가
  #   "무엇을 고를지"를 정해 준다. 이제 **arm_id 순**(성과와 무관한 결정론 순서 · radix = 로캘 무관) · 성과 칸은 가림 표식만 ·
  #   남는 것은 사용 횟수(설계 이력 — 측정값이 아니다). rf_overlay_outcomes 자체(리서치 디렉터 소비)는 그대로 둔다.
  O <- tryCatch(rf_overlay_outcomes(root), error = function(e) NULL)
  L3 <- c("## (3) arm 사용 이력 (전 entry B5 칸 · arm_id 순 — 성과 순위가 아니다) — 성과 수치는 가렸다",
          sprintf("- ★ΔMDD·ΔCAGR·ΔPORT_t·ΔCalmar·G2 판정은 다른 entry 의 전기간 측정값·결과 라벨이다 — 그것으로 arm 을 고르면 평가 창 결과를 소비하는 자동 선정이다(pit.md C1 D-E). %s 로 가렸고 순위도 없앴다. 사용 횟수(어느 arm 이 이미 많이 쓰였나)만 읽어라.", RX$mask),
          "| arm_id | 사용 | 스택사용 | entry수 | 성과(Δ·G2) |", "|---|---|---|---|---|")
  if (!is.null(O) && nrow(O)) {
    O <- O[order(as.character(O$arm_id), method = "radix")]
    n_show <- min(nrow(O), B5_OUTCOME_ROWS)
    for (i in seq_len(n_show)) L3 <- c(L3, sprintf("| %s | %d | %d | %d | %s |", O$arm_id[i], as.integer(O$uses[i]), as.integer(O$stacked_uses[i]),
                                                   as.integer(O$n_entries[i]), RX$mask))
    if (nrow(O) > n_show) L3 <- c(L3, sprintf("| … | (arm_id 순 상한 %d행 · 나머지 %d arm 생략) | | | |", n_show, nrow(O) - n_show))
  } else L3 <- c(L3, "| (이력 없음) | | | | |")
  sec$outcomes <- L3
  # (4) 앞선 논문들의 B5 교훈 ───────────────────────────────────────────────
  fs <- list.files(ld, pattern = "^l_code_.*_B5\\.json$", full.names = TRUE)
  fs <- fs[!grepl(base_id, basename(fs), fixed = TRUE)]
  prior_blocks <- list()
  if (length(fs)) {
    fs <- fs[order(file.info(fs)$mtime, decreasing = TRUE)]
    for (f in utils::head(fs, cfg$prior_entries)) {
      x <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL); if (is.null(x)) next
      mech <- .chr(x$mechanism); av <- as.character(unlist(x$avoid %||% list()))
      if (!nzchar(mech) && !length(av)) next
      blk <- sprintf("### %s", .chr(x$strategy_id))
      # (D-E-B5-MATERIALS) 다른 entry 의 교훈 서술 = 그 entry 의 전기간 Calmar·MDD 가 박혀 있다 — 절단 앞뒤로 가린다
      if (nzchar(mech)) blk <- c(blk, sprintf("- 기전: %s", .b5_capx(mech, 700, LB)))
      if (length(av)) blk <- c(blk, sprintf("- 쓰지 말 것: %s", paste(vapply(utils::head(av, 3L), .b5_capx, character(1), n = 160, lb = LB), collapse = " / ")))
      prior_blocks[[length(prior_blocks) + 1L]] <- blk
    }
  }
  .prior_sec <- function(blocks) c(sprintf("## (4) 앞선 논문들의 B5 블록 교훈 (최근 %d entry) — 수치는 가렸다(%s · 다른 entry 의 전기간 측정값 · pit.md C1 D-E) · **기전과 회피**만 옮겨 붙는다 · 금지 목록이 아니다(AX-000)", length(blocks), RX$mask),
                                   if (length(blocks)) unlist(blocks) else "(없음)")
  sec$prior <- .prior_sec(prior_blocks)
  sec$adv <- .b5_adv_sec(root, lb = LB)
  # (5) 증류 지식 ──────────────────────────────────────────────────────────
  L5 <- c(sprintf("## (5) 증류 지식 (distilled · 키워드: 오버레이/낙폭/MDD/국면/현금/overlay/drawdown/regime · 상한 20 · 수치는 가렸다 %s · 극성 라벨은 %s)", RX$mask, LB$mask))
  rows5 <- tryCatch({
    en <- new.env(parent = globalenv())
    invisible(capture.output(suppressMessages(source(.b5_lib("02_Infrastructure/axiom/distilled.R"), local = en))))
    acc <- list()
    for (kw in B5_DISTILL_KEYWORDS) { r <- tryCatch(suppressMessages(en$lookup_distilled(kw, root = root, max_rows = 10L)), error = function(e) NULL)
      if (is.data.frame(r) && nrow(r)) acc[[length(acc) + 1L]] <- r }
    if (length(acc)) { d <- do.call(rbind, acc); d[!duplicated(d$dist_id), , drop = FALSE] } else NULL
  }, error = function(e) NULL)
  pol5 <- character(0)
  if (is.data.frame(rows5) && nrow(rows5)) {
    # (D-E-B5-LABELS) 극성(polarity — 그 지식이 성공/실패/조건부였나)은 다른 entry 결과의 라벨이다 — 자리에 표식을 쓴다
    pol5 <- .b5_vocab_clean(utils::head(as.character(rows5$polarity), 20L))
    for (i in seq_len(min(20L, nrow(rows5))))
      L5 <- c(L5, sprintf("- %s [%s] %s%s", rows5$dist_id[i], LB$mask, .b5_capx(rows5$statement[i], 120, LB),
                          if (nzchar(.chr(rows5$retry_policy[i]))) paste0(" (", .b5_capx(rows5$retry_policy[i], 80, LB), ")") else ""))
  } else L5 <- c(L5, "(일치 항목 없음)")
  sec$distilled <- L5
  # (6) 기전 지도 + 활성 카탈로그 ─────────────────────────────────────────
  #   (D-E-B5-LABELS) 구판 = rf_target_brief — 칸마다 "판정 k · 미검증 m · 포화/미포화" 를 싣고 **포화 순**으로 정렬했다(순서만으로도 라벨이 샌다).
  #   판정·미검증 수와 포화는 다른 entry 의 G2 결과에서 온다 — 측정 횟수·카탈로그 수만 남기고 (action, state) 순(결과와 무관 · radix)으로 쓴다.
  #   정본 집계기(rf_mechanism_map)는 그대로 쓴다(사본 없음) · rf_target_brief 자체(다른 레인 소비)는 건드리지 않는다.
  mp6 <- tryCatch(rf_mechanism_map(root), error = function(e) NULL)
  tb <- if (is.null(mp6) || !nrow(mp6)) "(기전 지도 산출 실패)" else {
    mp6 <- mp6[order(as.character(mp6$action), as.character(mp6$state), method = "radix")]
    sprintf("%-16s %-14s 측정 %d · 카탈로그 %d · 결과 라벨 %s", mp6$action, mp6$state, as.integer(mp6$n_measured), as.integer(mp6$n_arms_catalog), LB$mask)
  }
  L6 <- c(sprintf("## (6) 기전 지도 (action × state 순 · 측정 횟수·카탈로그 수만 — 판정 개수·결과 라벨은 %s 로 가렸다) 와 활성 카탈로그", LB$mask), tb, "",
          "### 활성 arm (여기 있는 id 만 picks 에 쓸 수 있다 · 상주 arm 은 목록에서 뺐다 · 새 arm 의 kind 는 아래 kind 와 겹치면 거부된다)")
  for (a in arms) { if (!identical(.chr(a$status), "active") || .chr(a$id) %in% st$picks) next
    z <- rfm_arm_axis(a)
    L6 <- c(L6, sprintf("- %s · kind=%s · family=%s · %s/%s%s — %s", .chr(a$id), .chr(a$kind), .chr(a$family), z$action, z$state,
                        if (nzchar(.chr(a$source))) paste0(" · source=", .chr(a$source)) else "", .b5_capx(a$basis, 200, LB))) }
  sec$catalog <- L6
  # (7) 계약·엔진 사실·중첩·PIT·금칙·검증부 ────────────────────────────────
  axes <- tryCatch(fromJSON({ p <- file.path(root, "06_Registry/rf_overlay_adversary_axes.json"); if (file.exists(p)) p else .b5_lib("06_Registry/rf_overlay_adversary_axes.json") },
                            simplifyVector = FALSE), error = function(e) NULL)
  st_txt <- if (length(st$cells)) paste(vapply(st$cells, function(x) sprintf("%s(%s)", .chr(x$code), .chr(x$overlay_pick)), character(1)), collapse = " · ") else "없음"
  AL <- .b5_allowlist(root)     # (B09-ALLOWLIST-PROMPT) probe ③d 허용 목록 — (7) 금칙 뒤에 싣는다 · 미제공이면 (8) 에도 명시
  .b5_log("materials_allowlist", base_id = base_id, round = as.integer(round), status = if (isTRUE(AL$ok)) "ok" else "unavailable",
          names = as.integer(.num(AL$n_names %||% 0L)), sha = substr(.chr(AL$sha256), 1L, 12L), why = .chr(AL$reason),
          note = if (isTRUE(AL$ok)) "재료 (7) 에 probe ③d 허용 목록" else "재료 (7)·(8) 에 미제공·새 arm 금지 명시 — 배합 설계는 계속 · 새 arm 은 probe ③d 가 전부 거부한다")
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
    sprintf("- 스택은 층 ≤ %d · 정렬 id 키가 같은 스택은 같은 칸([A,B] ≡ [B,A]) · 칸끼리 같은 스택 금지 · 이 entry 가 이미 잰 스택 금지 · 라운드당 칸 ≤ %d · 유효 칸 ≥ %d(미달 = 폴백) · entry 총 ≤ %d칸(B5_%d..B5_%d).",
            cfg$max_layers, cfg$max_cells, cfg$min_cells, B5_TOTAL_CELLS, B5_CODE_BASE, B5_CODE_BASE + B5_TOTAL_CELLS - 1L),
    sprintf("- ★상주 칸 %s 은 매 세대 **따로** 측정된다(대조 칸 · 승격 carry 제외) — 설계에 절대 넣지 마라(검증이 뺀다).", st_txt),
    "### PIT (절대 규칙 · .claude/rules/pit.md)",
    "- C5: 오버레이 신호는 홀딩월(ctx$date 의 익월) 시작 **이전** 데이터로만. 컷오프 = 익월 1일 미만.",
    "- C11: 외부 데이터(패널·파일)는 as-of 시차를 증명해야 한다 — external_data 를 쓰면 overlay_pit_guard::assert_overlay_pit 로 매 호출 HARD 확인(본보기 overlay_arms/pg2_risk_overlay.R).",
    "- C15: 팩터 DB 는 load_month_factors() 단일 경유 · parquet 직접 load 금지. C1: H 밖 원천의 전기간 통계 금지(H 위 확장창 통계는 정상).",
    "### 금칙 (probe 가 자동 거부한다)",
    sprintf("- 성과 토큰(주석 포함): %s", paste(.b5_measure_tokens(), collapse = ", ")),
    "- 임의 상수 문턱: H·hold 의 열을 숫자 리터럴과 직접 비교(H$dd[t] > 0.2 · hold$beta > 1.2) 금지 — 문턱은 quantile/median/ecdf 등 확장창 추정.",
    "- 달력 리터럴: 특정 연·월·날짜·인덱스 창('어느 해 이후만' · t %in% 146:153 · year(ctx$date) >= 연도) 금지. probe 는 합성 픽스처(240개월 · 위기 2구간 주입 · 종목 T001~T025)로 돌아 픽스처에서 안 켜지고 실데이터에서만 켜지는 조건도 회피로 잡는다.",
    AL$lines,
    "### G1 적대적 설계시점 감사 (새 arm 마다 · 설계자와 **다른 모델** · 축 정본 06_Registry/rf_overlay_adversary_axes.json · 판정은 R 병합기가 근거를 재도출)")
  for (ax in axes$axes %||% list()) L7 <- c(L7, sprintf("- [%s] %s — %s", .chr(ax$id), .chr(ax$title), .cap(ax$focus, 420)))
  L7 <- c(L7,
    "- 감사 reject(근거 실재) 또는 unavailable(미산출) = 등재 금지 · 파일 삭제 · 방출 원장에 admitted=false 로 남는다.",
    "### G2 사후 반증 (측정 뒤 · rf_overlay_adversary.R) — pass 인 B5 칸만 블록 승자·승격 carry·Grade A 후보로 소비된다",
    "- T1 lag-1(노출을 한 달 늦게 적용해도 바닥 Calmar 를 넘는가) · T2 strict-PIT A/B(외부 패널 arm) · T3 노출 짝지은 원형 블록 순열 placebo · T3b 횡단면 placebo(벡터 arm) · T4 정적 등가(상수 노출 mean(E) 를 넘는가) · T5 에피소드 집중(보고).",
    "- fail/error = **소비 보류**이지 등급 변경이 아니다(essence·grade 불변). '개선이 있다' 와 '개선이 타이밍에서 왔다' 는 다른 명제다 — 동월 누출·정적 디레버리지·임의 타이밍으로도 Calmar 는 오른다. 설계는 이 반증을 견딜 기전이어야 한다.")
  sec$contract <- L7
  # 공리 ────────────────────────────────────────────────────────────────────
  axb <- .b5_axiom_brief(root); sec$axioms <- if (length(axb) && any(nzchar(axb))) axb else "## 공리: (활성 공리 없음)"
  # (8) 가드 상태 ──────────────────────────────────────────────────────────
  sec$guard <- c("## (8) 이번 라운드의 가드 상태",
    sprintf("- compose_only = %s — %s", if (isTRUE(compose_only)) "TRUE" else "FALSE",
            if (isTRUE(compose_only)) "★새 arm 을 내지 마라(내도 무시·삭제되고 원장에 남는다). 기존 활성 arm 의 배합(스택)만 설계한다."
            else sprintf("새 arm 은 최대 %d개(그 이상은 무시·삭제). 필요 없으면 0개도 정상이다.", as.integer(arm_quota))),
    sprintf("- 라운드 %d · 설계 칸 ≤ %d · 유효 칸 ≥ %d · 층 ≤ %d · 새 arm kind = b5gen_<short>_%d", as.integer(round), cfg$max_cells, cfg$min_cells, cfg$max_layers, as.integer(round)),
    "- ★설계는 특정 시기(연·월·이름 붙은 위기)에 기대면 안 된다 — 이 재료의 날짜는 전부 지웠고(<date>/<yr>/<episode>), arm 의 달력 리터럴은 probe 가 거부한다.",
    sprintf("- ★교차 entry 절(공리·(2b)·(3)·(4)·(4b)·(5)·(6))의 수치는 %s 로 가렸다 — 다른 entry 의 전기간 측정값으로 arm 을 고르면 평가 창 결과를 소비하는 자동 선정이다(pit.md C1 D-E). 이 entry 자신의 측정표((1))·바닥 해부((2))는 그대로다.", RX$mask))
  thr <- tryCatch(.b5_director_thresholds(root), error = function(e) NULL)
  if (!is.null(thr)) sec$guard <- c(sec$guard, sprintf("- A 등급 문턱(고정 축 상수 — 측정값이 아니라 가리지 않는다): Calmar ≥ %s · PORT_t ≥ %s",
                                                       .f3(thr[["calmar"]]), .f3(thr[["port_t"]])))
  if (!isTRUE(AL$ok)) sec$guard <- c(sec$guard, "- ★허용 함수 목록 미제공((7) 참조) — probe ③d 가 새 arm 을 전부 거부한다. 할당과 무관하게 이번 라운드는 새 arm 을 내지 마라(기존 활성 arm 배합만).")
  # 조립 + 날짜 제거 + 총량 상한 ────────────────────────────────────────────
  order <- c("axioms", "entry", "floor", "director", "outcomes", "prior", "adv", "distilled", "catalog", "contract", "guard")
  # (D-E-B5-MATERIALS) 교차 절 = 자기·정적 절이 아닌 전부 — 조립 직전 절 전체를 가린다(절단 뒤 2회차 · 멱등) · 조립 뒤 재도출 검증
  xsecs <- setdiff(order, B5_OWN_SECTIONS)
  .redact_x <- function(S) { for (k in xsecs) if (length(S[[k]])) S[[k]] <- RX$redact(S[[k]]); S }
  .assemble <- function(S) b5_strip_dates(unlist(lapply(order, function(k) c(S[[k]], ""))))
  .x_lines <- function(S, tx) {   # 조립된 본문에서 교차 절이 차지한 줄(날짜 제거 뒤 = 실제 발송 텍스트)
    n <- vapply(order, function(k) length(S[[k]]) + 1L, integer(1)); hi <- cumsum(n); lo <- hi - n + 1L
    unlist(lapply(which(order %in% xsecs), function(j) tx[lo[j]:hi[j]]), use.names = FALSE)
  }
  # (D-E-B5-LABELS) 교차 절 결과 라벨 기본 가림 — 수치 가림보다 **먼저**(사유 문자열을 통째로 잡는다) · 멱등 · 자기·정적 절은 건드리지 않는다
  .label_x <- function(S) { for (k in xsecs) if (length(S[[k]])) S[[k]] <- LB$redact(S[[k]]); S }
  sec <- .redact_x(.label_x(sec))
  txt <- .assemble(sec)
  n_prior_dropped <- 0L
  while (sum(nchar(txt, type = "chars")) > B5_MAT_CAP_CHARS && length(prior_blocks)) {
    prior_blocks <- prior_blocks[-length(prior_blocks)]; n_prior_dropped <- n_prior_dropped + 1L
    sec$prior <- .prior_sec(prior_blocks); sec <- .redact_x(.label_x(sec)); txt <- .assemble(sec)
  }
  # 발송 전 재도출 검증 — 교차 절(발송 텍스트)에 수치가 하나라도 남으면 재료를 쓰지 않는다(조용한 통과 없음 · 레인 = materials_failed)
  xl <- .x_lines(sec, txt)
  if (length(xl) + sum(vapply(order[!(order %in% xsecs)], function(k) length(sec[[k]]) + 1L, integer(1))) != length(txt) || isTRUE(RX$has(xl))) {
    .b5_log("materials_rejected", base_id = base_id, round = as.integer(round), why = "cross_entry_stats_residual",
            note = "교차 entry 절에 전기간 수치 잔존(또는 절 경계 재도출 불일치) — pit.md C1 D-E · 기존 설계로 폴백")
    stop("[b5_design] 교차 entry 절에 전기간 수치 잔존 — 재료 생성 중단(pit.md C1 D-E · 기존 설계로 폴백)")
  }
  # (D-E-B5-LABELS) 발송 전 라벨 재검증 — 발송 텍스트(날짜 제거 뒤)에서 절마다 다시 잰다(수치 판정과 독립: 수치 가림을 한 번 더 씌운 사본 위)
  lab_bad <- .b5_label_residue(sec, txt, order, xsecs, LB, RX, pol = pol5)
  if (length(lab_bad)) {
    .b5_log("materials_rejected", base_id = base_id, round = as.integer(round), why = "cross_entry_labels_residual", detail = paste(lab_bad, collapse = ","),
            note = "교차 entry 절에 결과 라벨(G2 판정·검사 사인·포화·극성·디렉터 구속/형태·라벨 개수) 잔존 — pit.md C1 D-E · 기존 설계로 폴백")
    stop("[b5_design] 교차 entry 절에 결과 라벨 잔존(", paste(lab_bad, collapse = ","), ") — 재료 생성 중단(pit.md C1 D-E · 기존 설계로 폴백)")
  }
  n_mask <- sum(lengths(regmatches(xl, gregexpr(RX$mask, xl, fixed = TRUE))))
  n_lab <- sum(lengths(regmatches(xl, gregexpr(LB$mask, xl, fixed = TRUE))))
  sizes <- vapply(order, function(k) sum(nchar(b5_strip_dates(sec[[k]]), type = "chars")) + length(sec[[k]]), integer(1))
  if (!is.null(out_p)) {
    dir.create(dirname(out_p), recursive = TRUE, showWarnings = FALSE)
    writeLines(enc2utf8(txt), out_p, useBytes = TRUE)
    write(toJSON(as.list(sizes), auto_unbox = TRUE), paste0(out_p, ".sizes.json"))
    .b5_log("materials_written", base_id = base_id, round = as.integer(round), compose_only = isTRUE(compose_only),
            arm_quota = as.integer(arm_quota), chars_total = sum(nchar(txt, type = "chars")), prior_dropped_for_cap = n_prior_dropped,
            sizes = paste(sprintf("%s=%d", names(sizes), sizes), collapse = " "), out = out_p,
            cross_entry_stats_masked = n_mask, redacted_sections = paste(xsecs, collapse = ","),
            cross_entry_labels_masked = n_lab, label_vocab = length(LB$vocab),
            label_vocab_src = paste(sprintf("%s=%d", names(LB$n_src), as.integer(LB$n_src)), collapse = ","))
  }
  invisible(list(text = txt, sizes = sizes, prior_dropped = n_prior_dropped, n_masked = n_mask, redacted_sections = xsecs,
                 n_labels_masked = n_lab, label_vocab = LB$vocab))
}

#' (D-E-B5-LABELS) 발송 텍스트의 교차 절 라벨 잔존 — 사유 코드 벡터(빈 = 통과). 절 경계는 조립 규칙(각 절 + 빈 줄)에서 재도출한다.
#'   ① vocab:<절>   어휘(원장 G2 기록·생산자 상수·포화 리터럴·디렉터 상태) 또는 표식에 붙은 개수·검사 목록이 남았다
#'   ② director     (2b) 에 디렉터가 쓴 구속·공동 구속·형태·상태 값이 남았거나(대소문자 그대로) 본문에 개수(정수)가 남았다
#'   ③ adv_tests    (4b) 에 검사 이름(원장 tests 키)이 남았다 — 검사별 칸·실패 사인 집계의 흔적
#'   ④ map_counts   (6) 에 "판정 k"·"미검증 k" 개수가 남았다
#'   ⑤ polarity     (5) 에 소비한 극성 값이 [괄호] 자리로 남았다
#'   ★수치 판정과 독립 — 수치 가림(rx)을 한 번 더 씌운 사본 위에서 잰다(수치 잔존은 앞 게이트 몫 · 멱등).
.b5_label_residue <- function(sec, txt, order, xsecs, lb, rx, pol = character(0), root = ROOT) {
  n <- vapply(order, function(k) length(sec[[k]]) + 1L, integer(1)); hi <- cumsum(n); lo <- hi - n + 1L
  if (hi[length(hi)] != length(txt)) return("section_bounds")
  lines_of <- function(k) { j <- match(k, order); if (is.na(j)) character(0) else rx$redact(txt[lo[j]:hi[j]]) }
  bad <- character(0)
  for (k in xsecs) if (isTRUE(lb$has(lines_of(k)))) bad <- c(bad, paste0("vocab:", k))
  d2 <- lines_of("director")
  if (length(d2)) {
    dp <- file.path(root, ".cache/rf_director_context.json")
    d <- if (file.exists(dp)) tryCatch(fromJSON(dp, simplifyVector = FALSE), error = function(e) NULL) else NULL
    dv <- .b5_vocab_clean(c(.chr(d$binding), as.character(unlist(d$co_binding %||% list())), .chr((d$recurring_class %||% list())$shape),
                            .chr((d$overlay %||% list())$status)))
    body <- d2[!startsWith(d2, "## ") & nzchar(d2)]
    if ((length(dv) && any(vapply(dv, function(v) any(grepl(.b5_tok_rx(v, ci = FALSE), body, perl = TRUE)), logical(1)))) ||
        any(grepl("[0-9]", body))) bad <- c(bad, "director")
  }
  if (length(lb$tests)) {
    a4 <- lines_of("adv")
    trx <- paste(vapply(lb$tests, .b5_tok_rx, character(1), ci = FALSE, USE.NAMES = FALSE), collapse = "|")
    if (length(a4) && any(grepl(trx, a4, perl = TRUE))) bad <- c(bad, "adv_tests")
  }
  m6 <- lines_of("catalog")
  i3 <- which(startsWith(m6, "### ")); if (length(i3)) m6 <- m6[seq_len(i3[1] - 1L)]   # 지도 행만(뒤의 활성 카탈로그 basis 는 서술 — 대상 밖)
  if (length(m6) && any(grepl("(판정|미검증)\\s*\\d", m6, perl = TRUE))) bad <- c(bad, "map_counts")   # 판정 · 미검증
  if (length(pol)) {
    p5 <- lines_of("distilled")
    prx <- sprintf("\\[\\s*(?:%s)\\s*\\]", paste(.b5_rx_esc(pol), collapse = "|"))
    if (length(p5) && any(grepl(prx, p5, perl = TRUE))) bad <- c(bad, "polarity")
  }
  unique(bad)
}

# ── 검증 + 최종 설계 쓰기 ────────────────────────────────────────────────────
.b5_grid_b5_cells <- function(root) {   # 설계 파일이 없던 entry 의 재설계 — 격자 칸을 picks 로 옮겨 자리를 지킨다(코드 충돌 방지)
  g <- .b5_prog(root)
  for (b in g$blocks %||% list()) if (identical(as.character(b$id), "B5"))
    return(lapply(b$cells %||% list(), function(cl) { pk <- .chr((cl$overlay %||% list())$arm_id %||% (cl$overlay %||% list())$kind)
      list(picks = if (nzchar(pk)) list(pk) else list(), label = .chr(cl$label), why = "격자 규칙 칸(자리 보존)") }))
  list()
}
#' @return list(ok, fallback, n_new, n_total, why, path)
b5_verify_and_write <- function(base_id, root = ROOT, cfg = b5_cfg(root), lane_out, admitted_ids = character(0),
                                rejected_ids = character(0), round = 1L, compose_only = FALSE) {
  round <- as.integer(round); fp <- b5_final_path(root, base_id)
  admitted_ids <- unique(admitted_ids[nzchar(admitted_ids)]); rejected_ids <- unique(rejected_ids[nzchar(rejected_ids)])
  n_adm <- length(admitted_ids); n_rej <- length(rejected_ids)
  .fallback <- function(why) {
    .b5_log("design_fallback", base_id = base_id, round = round, why = why, note = "기존 설계(기전/규칙/이전 라운드) 보존 — 러너는 그것으로 돈다")
    tryCatch(rf_record_b5_design(1L, base_id, list(round = round, n_cells = 0L, new_arms_admitted = n_adm, new_arms_rejected = n_rej,
                                                    compose_only = isTRUE(compose_only), fallback = TRUE, fallback_reason = why,
                                                    new_arm_ids = as.list(admitted_ids)), root = root),
             error = function(e) .b5_log("ledger_record_failed", base_id = base_id, err = conditionMessage(e)))
    list(ok = FALSE, fallback = TRUE, n_new = 0L, n_total = NA_integer_, why = why, path = fp)
  }
  E <- .b5_entry(root, base_id); if (is.null(E)) return(list(ok = FALSE, fallback = TRUE, n_new = 0L, n_total = NA_integer_, why = "entry 부재", path = fp))
  if (!file.exists(lane_out) || file.size(lane_out) == 0L) return(.fallback("설계 파일 부재"))
  D <- tryCatch(fromJSON(lane_out, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(D)) return(.fallback("설계 JSON 파싱 실패"))
  cells <- Filter(is.list, D$cells %||% list())
  if (!length(cells)) return(.fallback("cells 0건"))
  cat_map <- rfbd_catalog("B5", root); cat_ids <- vapply(cat_map, function(x) .chr(x$id), character(1))
  .kind_of <- function(id) { k <- which(cat_ids == id); if (length(k)) .chr(cat_map[[k[1]]]$kind) else "" }
  st <- .b5_standing(root)
  max_layers <- min(cfg$max_layers, rfbd_max_layers(root))
  measured_keys <- .b5_measured_b5_keys(E, root)
  # 바닥 칸(재설계) — 기존 설계 파일 > 격자 B5 칸 · 측정된 칸의 자리를 지킨다(코드 = 위치)
  base <- list()
  if (round >= 2L) {
    D0 <- if (file.exists(fp)) tryCatch(fromJSON(fp, simplifyVector = FALSE), error = function(e) NULL) else NULL
    base <- Filter(is.list, D0$cells %||% list())
    if (!length(base)) base <- .b5_grid_b5_cells(root)
    # ★이미 차지된 B5 코드보다 바닥이 짧으면 자리표시 칸으로 채운다 — 새 칸 코드가 측정된 코드와 겹치면 러너가 '이미 자리 있음' 으로
    #   조용히 건너뛴다(구 entry 의 기전 설계가 규칙 측정 **뒤에** 쓰인 경우). 상주 코드는 설계 코드 공간 밖이다.
    tk <- setdiff(.rf_taken_codes(E$attempts %||% list()), st$codes)
    ix <- suppressWarnings(as.integer(sub("^B5_", "", tk[grepl("^B5_[0-9]+$", tk)]))) - B5_CODE_BASE + 1L
    ix <- ix[is.finite(ix) & ix >= 1L & ix <= B5_TOTAL_CELLS]
    if (length(ix) && max(ix) > length(base))
      for (k in seq(length(base) + 1L, max(ix)))
        base[[k]] <- list(picks = list(), label = sprintf("(자리 보존 B5_%d)", B5_CODE_BASE + k - 1L), why = "측정된 코드 자리 — 설계 칸 아님")
  }
  base_keys <- vapply(base, function(ce) { ids <- rfbd_cell_picks(ce); if (length(ids)) rfbd_stack_key(ids) else "" }, character(1))
  keep <- list(); seen <- character(0); n_drop <- c(size = 0L, integrity = 0L)
  for (i in seq_along(cells)) {
    ce <- cells[[i]]; ids <- rfbd_cell_picks(ce)
    drop <- function(why, axis) { n_drop[[axis]] <<- n_drop[[axis]] + 1L
      .b5_log("design_cell_dropped", base_id = base_id, round = round, cell = i, picks = paste(ids, collapse = "×"), guard = axis, why = why) }
    if (!length(ids)) { drop("picks 없음", "integrity"); next }
    if (length(ids) > max_layers) { drop(sprintf("층 %d > 상한 %d", length(ids), max_layers), "size"); next }
    if (anyDuplicated(ids)) { drop("같은 id 두 번", "integrity"); next }
    if (any(ids %in% st$picks)) { drop("상주 arm 포함 — 상주 칸이 따로 잰다", "integrity"); next }
    if (any(ids %in% rejected_ids)) { drop(sprintf("등재 거부·무시된 새 arm 참조: %s", paste(intersect(ids, rejected_ids), collapse = ",")), "integrity"); next }
    miss <- setdiff(ids, cat_ids); if (length(miss)) { drop(sprintf("active 카탈로그에 없음: %s", paste(miss, collapse = ",")), "integrity"); next }
    kd <- vapply(ids, .kind_of, character(1)); if (anyDuplicated(kd)) { drop(sprintf("같은 kind 두 층(%s)", kd[duplicated(kd)][1]), "integrity"); next }
    key <- rfbd_stack_key(ids)
    if (key %in% seen) { drop("앞 칸과 같은 스택", "integrity"); next }
    if (key %in% base_keys) { drop("기존 설계 칸과 같은 스택(이미 자리가 있다)", "integrity"); next }
    if (key %in% measured_keys) { drop("이 entry 가 이미 잰 스택", "integrity"); next }
    if (!nzchar(.chr(ce$label))) ce$label <- paste(ids, collapse = "×")
    if (length(keep) >= cfg$max_cells) { drop(sprintf("라운드 상한 %d칸 초과", cfg$max_cells), "size"); next }
    if (length(base) + length(keep) >= B5_TOTAL_CELLS) { drop(sprintf("entry 총 %d칸(B5_%d..B5_%d) 초과", B5_TOTAL_CELLS, B5_CODE_BASE, B5_CODE_BASE + B5_TOTAL_CELLS - 1L), "size"); next }
    seen <- c(seen, key); keep[[length(keep) + 1L]] <- list(picks = as.list(ids), label = .cap(ce$label, 60), why = .cap(ce$why %||% "", 400))
  }
  .b5_log("overlay_guard_h5_design_size", base_id = base_id, round = round, proposed = length(cells), kept = length(keep),
          dropped_size = n_drop[["size"]], base_cells = length(base), max_cells = cfg$max_cells, min_cells = cfg$min_cells, max_layers = max_layers,
          decision = if (length(keep) >= cfg$min_cells) "pass" else "fallback")
  .b5_log("overlay_guard_h6_cell_integrity", base_id = base_id, round = round, dropped_integrity = n_drop[["integrity"]],
          measured_stacks = length(measured_keys), standing = paste(st$picks, collapse = ","))
  if (length(keep) < cfg$min_cells) return(.fallback(sprintf("유효 칸 %d < 최소 %d", length(keep), cfg$min_cells)))
  # 최종 관문 — 새 칸은 정본 검증기가 재도출한다(실재·active·kind·중복·상주·층). 진술은 근거가 아니다.
  v <- rfbd_verify(list(cells = keep), "B5", root, max_cells = cfg$max_cells)
  if (!isTRUE(v)) return(.fallback(paste("rfbd_verify:", as.character(v))))
  mech_bk <- ""
  if (round == 1L && file.exists(fp)) {
    mech_bk <- b5_mech_backup(root, base_id); dir.create(dirname(mech_bk), recursive = TRUE, showWarnings = FALSE)
    file.copy(fp, mech_bk, overwrite = TRUE)
    .b5_log("design_backed_up", base_id = base_id, from = fp, to = mech_bk,
            note = "백업은 .cache/rf_block_design 밖 — 그 디렉터리의 최신 파일 이름이 블록 순서 규칙의 입력이다")
  }
  final <- list(block = "B5", base_id = base_id, source = "b5_design_lane", round = round,
                written_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                rationale = .cap(D$rationale %||% "", 600), base_design_cells = length(base),
                mechanism_backup = if (nzchar(mech_bk)) mech_bk else NULL, new_arm_ids = as.list(admitted_ids),
                cells = c(base, keep))
  .b5_atomic_write(toJSON(final, auto_unbox = TRUE, pretty = TRUE, null = "null"), fp)
  fields <- list(round = round, n_cells = length(keep), new_arms_admitted = n_adm, new_arms_rejected = n_rej,
                 compose_only = isTRUE(compose_only), fallback = FALSE, new_arm_ids = as.list(admitted_ids),
                 n_total_cells = length(base) + length(keep), design_path = fp)
  if (nzchar(mech_bk)) fields$mechanism_backup <- mech_bk
  if (round >= 2L) fields$redesign <- list(cells_added = length(keep), base_design_cells = length(base))
  tryCatch(rf_record_b5_design(1L, base_id, fields, root = root),
           error = function(e) .b5_log("ledger_record_failed", base_id = base_id, err = conditionMessage(e)))
  .b5_log("design_verified", base_id = base_id, round = round, cells = length(keep), total_cells = length(base) + length(keep),
          first_code = sprintf("B5_%d", B5_CODE_BASE + length(base)), new_arms_admitted = n_adm, new_arms_rejected = n_rej,
          compose_only = isTRUE(compose_only), path = fp)
  list(ok = TRUE, fallback = FALSE, n_new = length(keep), n_total = length(base) + length(keep), why = "", path = fp)
}

# ── claim (pid-aware · 소유자 = 호출 레인의 Windows pid) ─────────────────────
#'   rf_claim_acquire 는 R 자신의 pid 를 적어 자식 R 이 끝나면 곧 '사망 소유자' 가 된다 — 레인(bash)의 pid 를 받아 적는다.
#'   생존 판정은 rf_claim.R 정본(rf_claim_pid_alive · proc_start 대조 = pid 재사용 감지 2026-09-06 Widgets 사고)을 쓴다.
b5_claim_acquire <- function(claim, owner_pid, stale_hours = 6) {
  owner_pid <- suppressWarnings(as.integer(owner_pid))
  op <- file.path(claim, "owner.json")
  .take <- function(why) {
    dir.create(claim, recursive = TRUE, showWarnings = FALSE); unlink(file.path(claim, "released.json"))
    rec <- list(pid = owner_pid, started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), host = Sys.info()[["nodename"]], lane = "b5_design")
    ps <- tryCatch(rf_claim_proc_start(owner_pid), error = function(e) NA_real_)
    if (length(ps) == 1L && is.finite(ps)) rec$proc_start <- ps
    ok <- tryCatch({ writeLines(toJSON(rec, auto_unbox = TRUE), op); TRUE }, error = function(e) FALSE)
    if (!ok) return(list(ok = FALSE, reason = "owner_write_failed", note = why))
    o2 <- tryCatch(fromJSON(op, simplifyVector = TRUE), error = function(e) NULL)       # 경합 확인 — 되읽어 내 pid 인가
    if (is.null(o2) || !identical(suppressWarnings(as.integer(o2$pid)), owner_pid)) return(list(ok = FALSE, reason = "race", note = why))
    list(ok = TRUE, reason = "acquired", note = why)
  }
  if (!dir.exists(claim)) return(.take("신규"))
  o <- if (file.exists(op)) tryCatch(fromJSON(op, simplifyVector = TRUE), error = function(e) NULL) else NULL
  pid <- suppressWarnings(as.integer(o$pid %||% NA)); pst <- suppressWarnings(as.numeric(o$proc_start %||% NA))
  age_h <- suppressWarnings(as.numeric(difftime(Sys.time(), file.info(claim)$mtime, units = "hours")))
  if (file.exists(file.path(claim, "released.json"))) return(.take("해제 표식 — 제자리 인수"))
  if (is.na(pid) && is.finite(age_h) && age_h * 3600 > 60) return(.take("owner 부재 — 빈 고아 인수"))
  if (!is.na(pid) && !rf_claim_pid_alive(pid, proc_start = if (is.finite(pst)) pst else NULL))
    return(.take(sprintf("owner pid %d 사망 또는 pid 재사용 — 인수", pid)))
  if (is.finite(age_h) && age_h > stale_hours) return(.take(sprintf("나이 %.2fh > %.1fh — 시간 폴백 인수", age_h, stale_hours)))
  list(ok = FALSE, reason = "claimed", note = sprintf("owner pid %s · %.2fh", .chr(pid), age_h))
}

# ── CLI ───────────────────────────────────────────────────────────────────────
if (!interactive() && identical(sys.nframe(), 0L)) {
  a <- commandArgs(TRUE)
  cmd <- if (length(a)) a[1] else ""
  .cmds <- c("due", "active_entry", "next_is_b5", "guards", "materials", "probe", "record_emission", "verify", "claim", "release", "outcomes")
  .san  <- function(x) { x <- gsub("[^A-Za-z0-9_]", "_", .chr(x)); if (!nzchar(x)) "unnamed" else substr(x, 1L, 60L) }
  if (cmd %in% .cmds) {
    if (cmd == "due") {
      E <- b5_active_entry(ROOT)
      if (is.null(E)) cat("-\t0\t활성 entry 없음\n", sep = "") else {
        r <- b5_next_block_is_b5(E, ROOT)
        cat(sprintf("%s\t%s\t%s\n", .chr(E$base_id), if (isTRUE(r)) "1" else "0", gsub("[\t\r\n]+", " ", attr(r, "why") %||% "")))
      }
    } else if (cmd == "active_entry") { E <- b5_active_entry(ROOT); cat(if (is.null(E)) "-" else .chr(E$base_id), "\n", sep = "")
    } else if (cmd == "next_is_b5") { r <- b5_next_block_is_b5(.b5_entry(ROOT, a[2]), ROOT)
      cat(attr(r, "why") %||% "", "\n", if (isTRUE(r)) "1" else "0", "\n", sep = "")
    } else if (cmd == "guards") {
      E <- .b5_entry(ROOT, a[2]); if (is.null(E)) { cat("entry 부재\n"); quit(status = 2L) }
      g <- b5_guards(E, ROOT, b5_cfg(ROOT), mode = a[3]); write(toJSON(g, auto_unbox = TRUE, null = "null", na = "null"), a[4])
      quit(status = if (isTRUE(g$ok)) 0L else 3L)
    } else if (cmd == "materials") {
      b5_materials(a[2], ROOT, b5_cfg(ROOT), compose_only = identical(a[4], "1"), arm_quota = as.integer(a[5]), round = as.integer(a[6]), out_p = a[3])
    } else if (cmd == "probe") {
      invisible(capture.output(suppressMessages(source(.b5_lib("02_Infrastructure/reinforcement/overlay_probe.R")))))
      kind <- .san(a[2])
      pr <- tryCatch(overlay_probe_arm(kind, ROOT), error = function(e) list(ok = FALSE, reason = conditionMessage(e)))
      st <- if (length(a) >= 3L) .chr(a[3]) else ""; st_norm <- if (st %in% RFM_STATES) st else "multivar"   # 정본 = rf_mechanism_map.R::RFM_STATES
      cat(sprintf("probe: %s | %s | %s | %s | %s\n", kind, if (isTRUE(pr$ok)) "pass" else "fail", .chr(pr$axis %||% "NA"), st_norm,
                  gsub("[\r\n|]+", " ", .chr(pr$reason %||% ""))))
      quit(status = if (isTRUE(pr$ok)) 0L else 3L)
    } else if (cmd == "record_emission") {
      invisible(capture.output(suppressMessages(source(.b5_lib("02_Infrastructure/reinforcement/rf_overlay_admit.R")))))
      rf_overlay_record_emission(.san(a[2]), target = list(action = .chr(a[3]), state = .chr(a[4])), n_siblings = suppressWarnings(as.integer(a[6])),
                                 generator_model = .chr(a[5]), root = ROOT, source = "b5_design", stage = .chr(a[7]),
                                 reason = if (length(a) >= 8L) a[8] else "")
    } else if (cmd == "verify") {
      .csv <- function(x) { x <- .chr(x); if (!nzchar(x) || identical(x, "-")) return(character(0)); v <- strsplit(x, ",", fixed = TRUE)[[1]]; v[nzchar(v) & v != "-"] }
      r <- b5_verify_and_write(a[2], ROOT, b5_cfg(ROOT), lane_out = a[3], round = as.integer(a[4]), compose_only = identical(a[5], "1"),
                               admitted_ids = .csv(if (length(a) >= 6L) a[6] else ""), rejected_ids = .csv(if (length(a) >= 7L) a[7] else ""))
      cat(sprintf("verify: %s | %s | new %d | %s\n", a[2], if (isTRUE(r$ok)) "written" else "fallback", r$n_new, r$why))
      quit(status = if (isTRUE(r$ok)) 0L else 1L)
    } else if (cmd == "claim") {
      r <- b5_claim_acquire(a[2], a[3], as.numeric(if (length(a) >= 4L) a[4] else 6))
      cat(sprintf("claim: %s | %s\n", r$reason, r$note)); quit(status = if (isTRUE(r$ok)) 0L else 1L)
    } else if (cmd == "release") {   # 마지막 줄 "release: <reason>[ | <err>]" · rc 0 = 다음 실행이 즉시 인수 가능(marker_left 포함 · 레인이 사유로 정보 이벤트를 가른다)
      r <- rf_claim_release(a[2]); e <- gsub("[\r\n|]+", " ", .chr(r$err %||% ""))
      cat(sprintf("release: %s%s\n", r$reason, if (nzchar(e)) paste0(" | ", e) else "")); quit(status = if (isTRUE(r$ok)) 0L else 1L)
    } else if (cmd == "outcomes") { O <- rf_overlay_outcomes(ROOT); fwrite(O, a[2]); cat(sprintf("outcomes: %d arms -> %s\n", nrow(O), a[2])) }
  } else if (nzchar(cmd)) stop("[b5_design] 알 수 없는 명령: ", cmd)
}
