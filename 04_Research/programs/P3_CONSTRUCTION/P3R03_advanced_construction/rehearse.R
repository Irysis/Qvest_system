## P3R03 등록 전 리허설(격리 교차 점검 필수 4) — 본 판정 함수 p3_eval_pair 를 기존 산출(P3R02_E2_M5 vs P3R02_E2_RX0 · 같은 엔진 · 같은 배치)에
##   그대로 돌려 새 경로가 실제 산출물에서 무오류로 도는지 확인한다: R1 = 원 창(실효 시작 같음) · 자연 β 비 / R2 = 공통 창 강제(RX0 첫 수익일 + 1개월) · β 짝 k = 0.9 강제.
##   쓰기 = rehearsal/out(확인 뒤 삭제) · rehearsal/summary.json(구조 판독만 — 성과 수치 · 시험 창 값 없음). P3R02 결과 폴더는 읽기만 한다.
## 실행: Rscript rehearse.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
RD <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction")
source(file.path(RD, "evaluate.R"))
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
P2 <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz")
DR <- fromJSON(file.path(RD, "prereg_draft.json"), simplifyVector = FALSE)
OUTD <- file.path(RD, "rehearsal", "out"); unlink(OUTD, recursive = TRUE); dir.create(OUTD, recursive = TRUE)
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = file.path(RD, "behavior_card_cfg_at_prereg.json")); env$raw <- NULL
X <- list(root = ROOT, res = file.path(P2, "results"), out = OUTD, env = env, fs = DR$final_selection_rule, tau = as.Date(DR$tau_d), ea = new.env())
cell <- function(code) list(code = code, path = sprintf("04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz/specs/%s.json", code))
ev <- function(code) fromJSON(file.path(P2, "results", code, "eval.json"), simplifyVector = FALSE)
cm <- cell("P3R02_E2_M5"); cr <- cell("P3R02_E2_RX0"); em <- ev(cm$code); er <- ev(cr$code)
first_ret <- min(as.Date(fread(file.path(er$artifacts, "03_period_returns.csv"))$date))
fs <- seq(first_ret, by = "month", length.out = 2L)[2]
runs <- list(R1 = list(tag = "ecm"), R2 = list(tag = "ecm", force_start = fs, force_k = 0.9))
shape <- function(o, opts) {
  pk <- function(sub) { p <- file.path(OUTD, cm$code, sub, "diagnosis_packet.json"); if (file.exists(p)) unlist(fromJSON(p, simplifyVector = FALSE)$window) else NULL }
  sub <- if (identical(o$window, "original")) "original" else sub("^common_from_", "common_", gsub("-", "", o$window %||% ""))
  list(tested = isTRUE(o$tested), why = o$why %||% NA, window = o$window %||% NA,
       packet_window = if (!identical(sub, "original")) list(variant = pk(file.path(sub, "visible")), rx0 = pk(file.path(sub, "visible_rx0")),
                                                            rx0_beta = pk(file.path(sub, "visible_rx0_beta"))) else NULL,
       same_selection = o$same_selection[c("status", "n_checked", "n_violate", "n_missing")],
       crisis_pairs = o$crisis_pairs[c("n_pair", "unpaired", "n_deep")],
       cycle = list(n_pair = o$decisive$c_participation$cycle$n_pair, unpaired = o$decisive$c_participation$cycle$unpaired_crises,
                    pair_mismatch = o$decisive$c_participation$cycle$pair_mismatch),
       fields = vapply(c("decisive", "non_inferiority", "alpha_non_loss", "beta_matched", "attribution", "concentration", "record"), function(k) !is.null(o[[k]]), logical(1)),
       ok_flags_are_logical = all(vapply(list(o$decisive$ok, o$non_inferiority$ok, o$alpha_non_loss$ok), function(v) is.logical(v) && length(v) == 1L && !is.na(v), logical(1))),
       alpha_se_finite = is.finite(o$alpha_non_loss$se %||% NA_real_),
       beta = list(status = o$beta_matched$status %||% NA, k_forced = o$beta_matched$k_forced %||% NA, k_up_finite = is.finite(o$beta_matched$k_up %||% NA_real_),
                   scaled_present = !is.null(o$beta_matched$scaled)),
       concentration = list(status = o$concentration$status %||% NA, missing_deep = o$concentration$top_loss$missing_deep %||% character(0)),
       history_drop_status = o$history_drop_status %||% NA, verdict_class = o$verdict %||% NA)
}
S <- list(); t0 <- Sys.time()
for (nm in names(runs)) {
  t1 <- Sys.time()
  o <- tryCatch(p3_eval_pair(X, "E2", "M5", cm, cr, em, er, opts = runs[[nm]]), error = function(e) list(error = conditionMessage(e)))
  S[[nm]] <- if (!is.null(o$error)) list(error = o$error) else c(shape(o, runs[[nm]]), list(seconds = round(as.numeric(difftime(Sys.time(), t1, units = "secs")))))
  cat(sprintf("[리허설] %s — %s\n", nm, if (!is.null(o$error)) paste("오류:", o$error) else sprintf("tested %s · 창 %s · β %s · 집중 %s · 선정 집합 위반 %s/%s · 사이클 짝 %s",
      isTRUE(o$tested), o$window %||% "-", o$beta_matched$status %||% "-", o$concentration$status %||% "-",
      format(o$same_selection$n_violate), format(o$same_selection$n_checked), format(o$decisive$c_participation$cycle$n_pair %||% NA))))
}
pass <- all(vapply(S, function(s) is.null(s$error) && isTRUE(s$tested) && all(s$fields) && isTRUE(s$ok_flags_are_logical), logical(1))) &&
  identical(S$R2$beta$status, "ok") && isTRUE(S$R2$beta$scaled_present) && identical(S$R2$window, paste0("common_from_", format(fs))) &&
  length(S$R2$packet_window$variant) && as.Date(S$R2$packet_window$variant[1]) >= fs
res <- list(schema = "p3r03_rehearsal_v1", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")),
            inputs = list(variant = cm$code, rx0 = cr$code, tag = "ecm", forced_start = format(fs), forced_k = 0.9,
                          note = "P3R02 의 같은 엔진 · 같은 배치 두 칸 — 새 경로(공통 창 사본 · β 짝 사본 · 패킷 · 위기 짝 · 사이클 짝 · 선정 집합 · 집중 상태)의 무오류 실행 확인용"),
            runs = S, pass = pass, seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))))
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RD, "rehearsal", "summary.json"), useBytes = TRUE)
cat(sprintf("[리허설] %s — %d초 · 요약 rehearsal/summary.json\n", if (pass) "통과" else "실패", res$seconds))
quit(status = if (pass) 0L else 1L)
