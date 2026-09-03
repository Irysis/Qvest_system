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
rf_overlay_admit <- function(kind, target = NULL, n_siblings = 1L,
                             generator_model = NA_character_, root = .RFA_ROOT()) {
  suppressMessages(source(file.path(root, "02_Infrastructure/reinforcement/overlay_probe.R"),
                          local = TRUE))
  pr <- try(overlay_probe_arm(kind, root), silent = TRUE)
  if (inherits(pr, "try-error")) pr <- list(ok = FALSE, reason = as.character(pr))

  # arm 메타 — LLM 이 낸 <kind>.arm.json. 없으면 최소값으로 채운다(등재는 R 판단).
  mp <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".arm.json"))
  meta <- if (file.exists(mp)) tryCatch(fromJSON(mp, simplifyVector = FALSE), error = function(e) list()) else list()
  arm_id <- as.character(meta$id %||% paste0(kind, "_v1"))
  fam    <- as.character(meta$family %||% (if (identical(pr$axis, "cross_sectional")) "cross_sectional" else "multivar"))
  basis  <- as.character(meta$basis %||% "")

  tfid <- sprintf("OAF_%s_%s", format(Sys.time(), "%Y%m%d%H%M%S"), kind)
  rec <- list(record_type = "arm_emission", arm_id = arm_id, kind = kind,
              emitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
              target_cell = list(action = as.character(target$action %||% NA),
                                 state  = as.character(target$state  %||% NA)),
              generator_model = generator_model,
              family = fam, est_cost_min = as.numeric(meta$est_cost_min %||% 8),
              probe = list(ok = isTRUE(pr$ok), reason = as.character(pr$reason %||% NA),
                           axis = as.character(pr$axis %||% NA),
                           x_var = suppressWarnings(as.numeric(pr$x_var %||% NA))),
              emission_is_pre_measurement = TRUE,
              trial_family_id = tfid, n_siblings = as.integer(n_siblings),
              selection_type = if (n_siblings > 1L) "sweep_candidate_family" else "chain")
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
    state = as.character(target$state %||% meta$state %||% "multivar"))
  if (is.null(cd$families[[fam]]))
    cd$families[[fam]] <- as.character(meta$family_doc %||% paste0(fam, " — 생성 arm 이 신설한 계열"))
  write(toJSON(cd, auto_unbox = TRUE, pretty = TRUE, null = "null"), cp)
  cat(sprintf("[rf_overlay_admit] %s ADMIT — %s (%s · %s)\n", kind, arm_id, fam, pr$axis))
  invisible(list(ok = TRUE, kind = kind, arm_id = arm_id, ledger = TRUE))
}

cat("[rf_overlay_admit.R] Loaded — rf_overlay_admit(kind, target, n_siblings)\n")
