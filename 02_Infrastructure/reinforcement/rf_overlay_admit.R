#==============================================================================
# rf_overlay_admit.R — 생성된 오버레이 arm 의 등재 판정 (v10.2 2026-09-03 · Phase 1+5)
#
# ★등재는 R 이 한다. LLM 은 overlay_arms/<kind>.R 와 <kind>.arm.json 을 낼 뿐
#   카탈로그를 직접 쓰지 않는다 — 봉쇄 경계는 출력 디렉터리가 아니라 **등록 호출**이다
#   (reinforce_ladder 실사고: out_root 를 분리했는데 register_module 이 풀을 오염시켰다).
#
# ★원장은 probe 통과 여부와 무관하게 **항상** 쓴다. 실패한 방출을 지우면
#   "패자를 숨길 수 없다" 는 성질이 죽는다(weight_variant_ledger 규율).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFA_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

RFA_LEDGER <- "06_Registry/overlay_arm_ledger.jsonl"

#' PIT 격리 원천 참조 검사 (2026-09-24 · C11 봉쇄) — 생성 arm(<kind>.R · <kind>.arm.json)이 참조하는 격리 원천 정규식.
#'   정본 = <root>/06_Registry/pit_quarantine.json sources[].regex · 판독기 = 02_Infrastructure/validation/pit_quarantine.R
#'   (데이터 루트 → 코드 루트 순). 목록 부재 = character(0). 목록은 있는데 판독기 부재·목록 파손 = 그 사실을 걸린 것으로
#'   돌려준다 — 등재 거부로 넘어진다(조용한 해제 금지).
.rfa_pitq_hits <- function(kind, root) {
  rel <- "02_Infrastructure/validation/pit_quarantine.R"
  lib <- c(file.path(root, rel), file.path(.RFA_ROOT(), rel)); lib <- lib[file.exists(lib)]
  if (!length(lib)) {
    if (file.exists(file.path(root, "06_Registry/pit_quarantine.json"))) return("판독기 부재(pit_quarantine.R)")
    return(character(0))
  }
  ad <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms")
  fs <- file.path(ad, paste0(kind, c(".R", ".arm.json"))); fs <- fs[file.exists(fs)]
  txt <- unlist(lapply(fs, function(f) readLines(f, warn = FALSE, encoding = "UTF-8")))
  tryCatch({ en <- new.env(parent = globalenv()); sys.source(lib[1], envir = en); en$pitq_source_hits(txt, root) },
           error = function(e) sprintf("격리 목록 판독 실패: %s", conditionMessage(e)))
}

rfa_append_ledger <- function(rec, root = .RFA_ROOT()) {
  p <- file.path(root, RFA_LEDGER)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = p, append = TRUE)
  invisible(p)
}

#' @param kind   overlay_arms/<kind>.R 의 kind
#' @param target list(action, state) — 이 방출이 겨눈 칸
#' @param n_siblings 한 요청에서 방출된 arm 수. ★selection_type 은 여기서 **구조적으로** 나온다.
#'   LLM 이 선언하지 못한다 — k>1 이면 사후 argmax 가 sweep 이 되고 DSR 게이트에 누적된다.
#' @param source 방출 출처 (v10.4 2026-09-17). 기본 "overlay_propose"(일간 arm 레인). 세션 수동 등재·B5 설계 레인 등
#'   레인 밖 방출은 자기 이름을 단다 — 원장 기록과 카탈로그 항목 양쪽에 `source` 로 남는다.
#'   ★왜: 일간 상한(rf_overlay_propose.sh)이 원장에서 "오늘 방출 수" 를 세는데, 출처가 안 남으면
#'   남의 방출이 레인의 하루 예산을 먹는다(같은 날 세션 등재 1건 → 레인 halt_daily_cap). 구판 기록(필드 부재)은 레인 몫으로 센다.
rf_overlay_admit <- function(kind, target = NULL, n_siblings = 1L,
                             generator_model = NA_character_, root = .RFA_ROOT(),
                             source = "overlay_propose") {
  source <- as.character(source %||% "overlay_propose")[1]
  if (is.na(source) || !nzchar(source)) source <- "overlay_propose"
  suppressMessages(source(file.path(root, "02_Infrastructure/reinforcement/overlay_probe.R"),
                          local = TRUE))
  pr <- try(overlay_probe_arm(kind, root), silent = TRUE)
  if (inherits(pr, "try-error")) pr <- list(ok = FALSE, reason = as.character(pr))
  ## ★PIT 격리 원천 참조 거부 (2026-09-24 · C11 봉쇄 · 06_Registry/pit_quarantine.json) — probe 가 통과해도 등재하지 않는다.
  ##   pg2_risk_overlay 가 AE·m4 패널을 읽어 L1 15칸을 오염시켰고(판정서 V-02), 생성 레인 프롬프트가 그 파일을
  ##   외부 패널 본보기로 가리킨다 — 같은 원천을 읽는 새 arm 을 방출 단계에서 막는다. 사유는 방출 원장 probe.reason 에 남는다.
  .qh <- .rfa_pitq_hits(kind, root)
  if (length(.qh)) {
    pr$reason <- sprintf("pit_quarantine(C11) — 격리 원천 참조 %s%s", paste(.qh, collapse = " | "),
                         if (isTRUE(pr$ok)) "" else sprintf(" · probe: %s", as.character(pr$reason %||% "")))
    pr$ok <- FALSE
  }

  # arm 메타 — LLM 이 낸 <kind>.arm.json. 없으면 최소값으로 채운다(등재는 R 판단).
  mp <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".arm.json"))
  meta <- if (file.exists(mp)) tryCatch(fromJSON(mp, simplifyVector = FALSE), error = function(e) list()) else list()
  arm_id <- as.character(meta$id %||% paste0(kind, "_v1"))
  fam    <- as.character(meta$family %||% (if (identical(pr$axis, "cross_sectional")) "cross_sectional" else "multivar"))
  basis  <- as.character(meta$basis %||% "")

  rec <- .rfa_emission_record(kind, target, n_siblings, generator_model, source, meta, pr)
  rfa_append_ledger(rec, root)

  if (!isTRUE(pr$ok)) {
    cat(sprintf("[rf_overlay_admit] %s REJECT — %s\n", kind, as.character(pr$reason)))
    return(invisible(list(ok = FALSE, kind = kind, reason = pr$reason, ledger = TRUE)))
  }
  if (!nzchar(basis)) {
    cat(sprintf("[rf_overlay_admit] %s REJECT — basis 공백(검사가 요구한다)\n", kind))
    return(invisible(list(ok = FALSE, kind = kind, reason = "basis 공백", ledger = TRUE)))
  }

  cp <- file.path(root, "06_Registry/overlay_catalog.json")
  cd <- fromJSON(cp, simplifyVector = FALSE)
  if (any(vapply(cd$arms, function(a) identical(as.character(a$id), arm_id), logical(1)))) {
    cat(sprintf("[rf_overlay_admit] %s SKIP — 이미 등재됨 (%s)\n", kind, arm_id))
    return(invisible(list(ok = TRUE, kind = kind, reason = "already", ledger = TRUE)))
  }
  cd$arms[[length(cd$arms) + 1L]] <- list(
    id = arm_id, kind = kind, family = fam, basis = basis,
    status = "active", est_cost_min = as.numeric(meta$est_cost_min %||% 8),
    action = as.character(pr$axis %||% "scalar_exposure"),
    state = as.character(target$state %||% meta$state %||% "multivar"),
    source = source)
  if (is.null(cd$families[[fam]]))
    cd$families[[fam]] <- as.character(meta$family_doc %||% paste0(fam, " — 생성 arm 이 신설한 계열"))
  write(toJSON(cd, auto_unbox = TRUE, pretty = TRUE, null = "null"), cp)
  cat(sprintf("[rf_overlay_admit] %s ADMIT — %s (%s · %s · source=%s)\n", kind, arm_id, fam, pr$axis, source))
  invisible(list(ok = TRUE, kind = kind, arm_id = arm_id, ledger = TRUE, source = source))
}

#' 방출 원장 레코드 — 등재 경로(rf_overlay_admit)와 기록 전용 경로(rf_overlay_record_emission)가 **같은 형태**를 쓴다 (WP-C 2026-09-17).
#'   두 벌이면 한쪽만 고쳐지고 집계기(rf_overlay_ledger_count.py)가 한쪽을 못 센다.
.rfa_emission_record <- function(kind, target, n_siblings, generator_model, source, meta, pr) {
  arm_id <- as.character(meta$id %||% paste0(kind, "_v1"))
  fam    <- as.character(meta$family %||% (if (identical(pr$axis, "cross_sectional")) "cross_sectional" else "multivar"))
  tfid <- sprintf("OAF_%s_%s", format(Sys.time(), "%Y%m%d%H%M%S"), kind)
  list(record_type = "arm_emission", arm_id = arm_id, kind = kind,
       emitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
       target_cell = list(action = as.character(target$action %||% NA),
                          state  = as.character(target$state  %||% NA)),
       generator_model = generator_model, source = source,
       family = fam, est_cost_min = as.numeric(meta$est_cost_min %||% 8),
       probe = list(ok = isTRUE(pr$ok), reason = as.character(pr$reason %||% NA),
                    axis = as.character(pr$axis %||% NA),
                    x_var = suppressWarnings(as.numeric(pr$x_var %||% NA))),
       emission_is_pre_measurement = TRUE,
       trial_family_id = tfid, n_siblings = as.integer(n_siblings),
       selection_type = if (n_siblings > 1L) "sweep_candidate_family" else "chain")
}

#' 방출 **기록 전용** — 등재 전(probe 실패·G1 감사 거부·할당 초과·compose_only·미신고 파일) 에 버려지는 arm 도 원장에 남긴다.
#'   (WP-C 2026-09-17 · B5 설계 레인의 방출 정직성 H7). 카탈로그는 건드리지 않는다. 등재 경로가 이미 기록한 arm 에는 부르지 않는다
#'   (등재 CLI 는 probe 를 스스로 돌리고 기록한다 — 두 번 적으면 일간 상한이 그 arm 을 두 번 센다).
#' @param stage 어디서 버려졌나: probe / audit / audit_unavailable / quota / compose_only / undeclared / duplicate_id / missing_file
#' @param probe overlay_probe_arm 결과(있으면 그대로 싣는다). NULL 이면 ok=FALSE · reason 만.
rf_overlay_record_emission <- function(kind, target = NULL, n_siblings = 1L, generator_model = NA_character_,
                                       root = .RFA_ROOT(), source = "b5_design", stage = "probe", reason = "", probe = NULL) {
  source <- as.character(source %||% "b5_design")[1]; if (is.na(source) || !nzchar(source)) source <- "b5_design"
  mp <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".arm.json"))
  meta <- if (file.exists(mp)) tryCatch(fromJSON(mp, simplifyVector = FALSE), error = function(e) list()) else list()
  pr <- if (is.list(probe)) probe else list(ok = FALSE, reason = as.character(reason), axis = NA, x_var = NA)
  rec <- .rfa_emission_record(kind, target %||% list(), max(1L, as.integer(n_siblings %||% 1L)), generator_model, source, meta, pr)
  rec$admitted <- FALSE
  rec$rejected_stage <- as.character(stage)
  rec$reject_reason <- as.character(reason %||% "")
  rfa_append_ledger(rec, root)
  cat(sprintf("[rf_overlay_admit] %s RECORDED(admitted=false · %s) — %s\n", kind, stage, substr(as.character(reason %||% ""), 1, 120)))
  invisible(rec)
}

cat("[rf_overlay_admit.R] Loaded — rf_overlay_admit(kind, target, n_siblings, generator_model, root, source) / rf_overlay_record_emission(기록 전용 · admitted=false)\n")
