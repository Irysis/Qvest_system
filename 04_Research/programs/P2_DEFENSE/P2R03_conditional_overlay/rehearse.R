## P2R03 등록 전 리허설 — 본 판정 함수(p2_eval_cell · p2_eval_pair)를 기존 산출(P0R01_E2_C2 = E2 EW × vol_scale 오버레이 vs P0R01_E2_C0 = 같은 엔진 · 같은 배치 기준)에
##   그대로 돌려 새 경로가 실제 산출물에서 무오류로 도는지 확인한다(P3R03 rehearse.R 과 같은 목적):
##   R0 = 칸 평가 분리 저장(보는 창 / 사람 쪽 · 열람 금지 표식) · R1 = 원 창 · 자연 β 비 · R2 = 공통 창 강제(RX0 첫 수익일 + 1개월) · β 짝 k = 0.9 강제 ·
##   R3 = lag 판 기대(overlay_shift=1 줄 없음) → 미시험(집행 증거 경로)
##   쓰기 = rehearsal/out(확인 뒤 삭제) · rehearsal/summary.json(구조 판독만 — 성과 수치 · 시험 창 값 없음). P0R01 결과 폴더는 읽기만 한다.
## 실행: Rscript rehearse.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay")
source(file.path(RD, "evaluate.R"))
source(file.path(RD, "round_rules.R"))
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
P0 <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map")
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json")
if (!file.exists(BCP)) file.copy(file.path(ROOT, "06_Registry/behavior_card.json"), BCP)
FS <- p2r03_final_selection_rule(ROOT, BCP); TAU <- as.Date("2022-12-31")
OUTD <- file.path(RD, "rehearsal", "out"); unlink(OUTD, recursive = TRUE); RES <- file.path(OUTD, "results"); dir.create(RES, recursive = TRUE)
cell <- function(code, comp) list(code = code, engine = "E2", component = comp, path = sprintf("04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs/%s.json", code))
cm <- cell("P0R01_E2_C2", "D_rehearsal"); cr <- cell("P0R01_E2_C0", "RX0")
for (cd in c(cm$code, cr$code)) file.copy(file.path(P0, "results", paste0(cd, ".json")), RES)
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCP); env$raw <- NULL
t0 <- Sys.time(); S <- list()
## R0 — 칸 평가 분리 저장
em <- tryCatch(p2_eval_cell(ROOT, RES, cm, env, TAU), error = function(e) list(error = conditionMessage(e)))
er <- tryCatch(p2_eval_cell(ROOT, RES, cr, env, TAU), error = function(e) list(error = conditionMessage(e)))
fv <- file.path(RES, cm$code, "visible", "eval_visible.json"); ff <- file.path(RES, cm$code, "full", "eval_full.json")
vj <- if (file.exists(fv)) fromJSON(fv, simplifyVector = FALSE) else list(); fj <- if (file.exists(ff)) fromJSON(ff, simplifyVector = FALSE) else list()
S$R0 <- list(error = c(em$error, er$error), status = c(em$status %||% NA, er$status %||% NA),
             visible_file = file.exists(fv), full_file = file.exists(ff), packet = file.exists(file.path(RES, cm$code, "visible", "diagnosis_packet.json")),
             card = file.exists(file.path(RES, cm$code, "full", "behavior_card.json")), marker = file.exists(file.path(RES, cm$code, "full", "NO_VISIBLE_REVIEW.txt")),
             visible_has_test_or_full = any(c("test", "full") %in% names(vj)), full_has_audience = identical(fj$audience, P2R03_FULL_AUDIENCE),
             effective_start_ok = identical(em$effective_start$status, "ok") && identical(er$effective_start$status, "ok"))
cat(sprintf("[리허설] R0 — 상태 %s · 보는 창 파일 %s · 사람 쪽 파일 %s · 표식 %s · 보는 창에 시험/전기간 %s · 실효 시작 ok %s\n", paste(S$R0$status, collapse = "/"),
            S$R0$visible_file, S$R0$full_file, S$R0$marker, S$R0$visible_has_test_or_full, S$R0$effective_start_ok))
X <- list(root = ROOT, res = RES, out = OUTD, env = env, fs = FS, tau = TAU, ea = new.env())
LOG <- file.path(P0, "results", paste0(cm$code, ".log"))
first_ret <- min(as.Date(fread(file.path(env$E$ta_resolve_artifact(er$artifacts)$dir, "03_period_returns.csv"))$date))
fs <- seq(first_ret, by = "month", length.out = 2L)[2]
runs <- list(R1 = list(log = LOG), R2 = list(log = LOG, force_start = fs, force_k = 0.9), R3 = list(log = LOG, expect_shift = TRUE))
shape <- function(o) {
  RL <- o$rules
  list(tested = isTRUE(o$tested), why = o$why %||% NA, window = o$window %||% NA, verdict_class = o$verdict %||% NA,
       overlay = list(found = isTRUE(o$overlay$found), kind = o$overlay$kind %||% NA, shift1 = isTRUE(o$overlay$shift1), cash_exec_na = is.na(o$overlay$cash_exec %||% NA)),
       same_selection = o$same_selection[c("status", "n_checked", "n_violate", "n_missing")],
       crisis_pairs = o$crisis_pairs[c("n_pair", "unpaired", "n_deep")],
       rule_fields = vapply(c("crisis", "deep", "beta_deep", "fast", "beta_asym", "bull", "cycle", "path", "construction"), function(k) !is.null(RL[[k]]), logical(1)),
       ok_flags_logical = all(vapply(list(RL$crisis$ok, RL$deep$ok, RL$beta_deep$ok, RL$fast$ok, RL$beta_asym$ok, RL$bull$ok, RL$cycle$ok, RL$path$ok,
                                          o$alpha_non_loss$ok, o$non_inferiority$ok), function(v) is.logical(v) && length(v) == 1L && !is.na(v), logical(1))),
       beta = list(comparator = RL$beta_deep$comparator %||% NA, k_forced = RL$beta_deep$k_forced %||% NA, status = RL$beta_deep$status %||% NA, n_pair = RL$beta_deep$n_pair %||% NA),
       fast = list(n_keys = length(RL$fast$keys %||% character(0)), n_unclassified = length(RL$fast$unclassified %||% character(0)), n_pair = RL$fast$n_pair %||% NA, status = RL$fast$status %||% NA),
       bull = list(n_pair = RL$bull$n_pair %||% NA, unpaired = RL$bull$unpaired %||% NA), cycle_pairs = RL$cycle$n_pair %||% NA,
       alpha_se_finite = is.finite(o$alpha_non_loss$se %||% NA_real_), engine_alpha_finite = is.finite(o$alpha_non_loss$engine_alpha$alpha_ann %||% NA_real_),
       concentration = o$concentration$status %||% NA, recovery = o$recovery$status %||% NA, test_window_present = !is.null(o$alpha_test_window),
       records = list(hm = o$record$hm_timing$status %||% NA, cash = o$record$cash_timing$status %||% NA, expo_months = NROW(o$record$expo_m),
                      slow_pairs = RL$slow$n_pair %||% NA, fast_excl_pairs = RL$fast$record_excluding_no_month_end$n_pair %||% NA,
                      beta_ratio_finite = is.finite(RL$beta_asym$ratio %||% NA_real_) && is.finite(RL$beta_asym$ratio_rx0 %||% NA_real_),
                      attribution_path_finite = is.finite(o$attribution$share_beats_size_exposure_path %||% NA_real_)),
       visible_only_drops_test = is.null(p2_visible_only(o)$alpha_test_window))
}
for (nm in names(runs)) {
  t1 <- Sys.time()
  o <- tryCatch(p2_eval_pair(X, "E2", "D_rehearsal", cm, cr, em, er, opts = runs[[nm]]), error = function(e) list(error = conditionMessage(e)))
  S[[nm]] <- if (!is.null(o$error)) list(error = o$error) else c(shape(o), list(seconds = round(as.numeric(difftime(Sys.time(), t1, units = "secs")))))
  cat(sprintf("[리허설] %s — %s\n", nm, if (!is.null(o$error)) paste("오류:", o$error) else sprintf("tested %s%s · 창 %s · β %s(%s) · 빠름 키 %d · 강세 짝 %s · 사이클 짝 %s · 선정 집합 위반 %s/%s · 집중 %s",
      isTRUE(o$tested), if (!isTRUE(o$tested)) paste0("(", o$why, ")") else "", o$window %||% "-", o$rules$beta_deep$status %||% "-", o$rules$beta_deep$comparator %||% "-",
      length(o$rules$fast$keys %||% character(0)), format(o$rules$bull$n_pair %||% NA), format(o$rules$cycle$n_pair %||% NA),
      format(o$same_selection$n_violate), format(o$same_selection$n_checked), o$concentration$status %||% "-")))
}
pkw <- function(sub) { p <- file.path(OUTD, cm$code, sub, "diagnosis_packet.json"); if (file.exists(p)) unlist(fromJSON(p, simplifyVector = FALSE)$window) else NULL }
S$R2$packet_window <- list(variant = pkw(file.path(paste0("common_", format(fs, "%Y%m%d")), "visible")),
                           rx0_beta = pkw(file.path(paste0("common_", format(fs, "%Y%m%d")), "visible_rx0_beta")))
good <- function(s) is.null(s$error) && isTRUE(s$tested) && all(s$rule_fields) && isTRUE(s$ok_flags_logical) && isTRUE(s$visible_only_drops_test)
pass <- is.null(S$R0$error) && identical(S$R0$status, c("evaluated", "evaluated")) && S$R0$visible_file && S$R0$full_file && S$R0$marker &&
  !S$R0$visible_has_test_or_full && S$R0$full_has_audience && S$R0$effective_start_ok &&
  good(S$R1) && good(S$R2) && identical(S$R2$window, paste0("common_from_", format(fs))) && identical(S$R2$beta$comparator, "RX0 × k") && isTRUE(S$R2$beta$k_forced) &&
  length(S$R2$packet_window$variant) && as.Date(S$R2$packet_window$variant[1]) >= fs && length(S$R2$packet_window$rx0_beta) &&
  S$R1$fast$n_keys >= 2L && is.null(S$R3$error) && !isTRUE(S$R3$tested) && grepl("집행 증거", S$R3$why) &&
  identical(S$R1$records$hm, "ok") && identical(S$R1$records$cash, "ok") && S$R1$records$expo_months > 100L && isTRUE(S$R1$records$beta_ratio_finite) &&
  isTRUE(S$R1$records$attribution_path_finite)
res <- list(schema = "p2r03_rehearsal_v1", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")),
            inputs = list(variant = cm$code, rx0 = cr$code, forced_start = format(fs), forced_k = 0.9,
                          note = "P0R01 의 같은 엔진 · 같은 배치 두 칸(E2 EW × vol_scale 오버레이 vs 기준) — 새 경로(분리 저장 · 집행 줄 · 같은 선정 집합 · 공통 창 · β 짝 사본 · 빠른 급락 · 강세 구간별 · 사이클 · 집중 · 회복)의 무오류 실행 확인용"),
            runs = S, pass = pass, seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))))
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RD, "rehearsal", "summary.json"), useBytes = TRUE)
unlink(OUTD, recursive = TRUE)
cat(sprintf("[리허설] %s — %d초 · 요약 rehearsal/summary.json\n", if (pass) "통과" else "실패", res$seconds))
quit(status = if (pass) 0L else 1L)
