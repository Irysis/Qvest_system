## P2R04 등록 전 리허설 — 본 판정 함수(p2_eval_cell · p2_eval_pair · 진단 읽기 · 라운드 도우미)를 실제 산출물에 그대로 돌려 새 경로가 끝까지 무오류로 도는지
##   증명한다(판정용 아님 · 코드 경로 증명). 재료 = P0R01 의 같은 엔진 · 같은 배치 두 칸(구 축 all_hyg_2000_v1 이지만 팩터 틸트 셀 로그 · 보유가 있다):
##   P0R01_E2_C0(기준 → 가짜 코드 RX0) · P0R01_E2_C4(D03 저변동 틸트 · w0 0.5 → 가짜 코드 H2). 결과 json 의 artifacts 경로로 산출물을 찾는다(읽기만).
##   단계: R0 칸 평가 분리 저장 · R1 원 창 판정(⑩ · ⑭ 분해 · 크기 × β · 유동성 · 국면 월 · 기준점 · 기록) · R2 공통 창 강제 + β 짝 k 0.9 강제 ·
##   R3a 장치 불일치 → 미시험(구성 증거) · R3b 변형 = RX0 산출물 → 미시험(무처치) · R4a 진단 역할(가중 일치 → 판정됨) · R4b 진단 가중 불일치 → 미시험 ·
##   R5 진단 역할 + 보유 같음 → 무처치여도 계속(판정됨 · β 짝 = RX0) · R6 진단 읽기 묶음 · R7 RX0 동일성(P2R03 RX0 · 자기 자신 양성 대조) ·
##   R8 라운드 도우미(판정 · 선택 · R7 판독 · A 거리) + 보는 창 파일 직렬화 · τ_D 이후 날짜 전수 검사.
##   쓰기 = rehearsal/out(끝나면 삭제) · rehearsal/summary.json(단계별 통과 · 판정 어휘 · 걸린 시간만 — 성과 수치 · 시험 창 · 전기간 값 없음).
## 실행: Rscript rehearse.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings")
## 리허설이 실제로 적재한 판본의 md5 — 적재 전에 잰다(끝에서 재면 실행 중 편집이 기록을 속인다) · 끝에서 다시 재어 바뀌었으면 실패
MD5_AT_LOAD <- vapply(c("evaluate.R", "round_rules.R", "rehearse.R"), function(f) unname(as.character(tools::md5sum(file.path(RD, f)))), character(1))
source(file.path(RD, "evaluate.R"))
source(file.path(RD, "round_rules.R"))
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
P0 <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map")
## 행동 카드 설정 — 사전등록 사본(register 가 만든다)이 있으면 그것 · 없으면 정본을 읽기만(이 리허설은 사본을 만들지 않는다)
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json"); if (!file.exists(BCP)) BCP <- file.path(ROOT, "06_Registry/behavior_card.json")
FS <- p2r04_final_selection_rule(ROOT, BCP); TAU <- as.Date(fromJSON(BCP)$tau_d)
OUTD <- file.path(RD, "rehearsal", "out"); unlink(OUTD, recursive = TRUE); RES <- file.path(OUTD, "results"); dir.create(RES, recursive = TRUE)
SRC <- c(RX0 = "P0R01_E2_C0", H2 = "P0R01_E2_C4")
CODE <- c(RX0 = "P2R04_REH_E2_RX0", H2 = "P2R04_REH_E2_H2", NULLC = "P2R04_REH_E2_NULL")
spec <- function(s) sprintf("04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs/%s.json", s)
for (k in names(SRC)) { file.copy(file.path(P0, "results", paste0(SRC[[k]], ".json")), file.path(RES, paste0(CODE[[k]], ".json")))
                        file.copy(file.path(P0, "results", paste0(SRC[[k]], ".log")), file.path(RES, paste0(CODE[[k]], ".log"))) }
file.copy(file.path(P0, "results", paste0(SRC[["H2"]], ".log")), file.path(RES, paste0(CODE[["NULLC"]], ".log")))      # 무처치 대조: 장치 로그 + RX0 산출물
cr <- list(code = CODE[["RX0"]], engine = "E2", component = "RX0", reference = TRUE, path = spec(SRC[["RX0"]]))
cm <- list(code = CODE[["H2"]], engine = "E2", component = "H2", reference = FALSE, path = spec(SRC[["H2"]]))
cn <- list(code = CODE[["NULLC"]], engine = "E2", component = "H2", reference = FALSE, path = spec(SRC[["H2"]]))
EXPECT <- list(expect_cell = SRC[["H2"]], expect_cell_rx0 = SRC[["RX0"]])                 # 가짜 코드 — 셀 로그의 cell= 은 원 코드
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCP); env$raw <- NULL; env$liq <- NULL
X <- list(root = ROOT, res = RES, out = OUTD, env = env, fs = FS, tau = TAU, ea = new.env())
t0 <- Sys.time(); S <- list(); OBJ <- list()
lg <- function(nm, s) cat(sprintf("[리허설] %s — %s · %s초\n", nm, if (isTRUE(s$pass)) "통과" else "실패", format(s$seconds)))
why_class <- function(w) { if (is.null(w) || is.na(w)) return(NA_character_)
  pats <- c(construction_evidence = "구성 증거", no_treatment = "무처치", diag_weight = "혼합 가중", no_packet = "패킷 없음", effective_start = "실효 시작",
            eval_status = "평가 상태", eval_error = "평가 오류", inputs_na = "판정 입력 NA")
  h <- names(pats)[vapply(pats, function(p) grepl(p, w, fixed = TRUE), logical(1))]; if (length(h)) h[1] else "other" }
lgl1 <- function(v) is.logical(v) && length(v) == 1L && !is.na(v)
stage <- function(nm, fn) { t1 <- Sys.time()
  r <- tryCatch(fn(), error = function(e) list(pass = FALSE, error_class = "stage_error", error = conditionMessage(e)))
  r$seconds <- round(as.numeric(difftime(Sys.time(), t1, units = "secs"))); S[[nm]] <<- r[setdiff(names(r), "error")]
  if (!is.null(r$error)) cat(sprintf("[리허설] %s — 단계 오류: %s\n", nm, .p2_redact_chr(r$error, TAU)))
  lg(nm, r); invisible(r) }
shape <- function(o, extra = list()) {
  RL <- o$rules
  chk <- c(tested = isTRUE(o$tested),
           rule_fields = all(vapply(c("crisis", "deep", "beta_deep", "fast", "slow", "beta_asym", "bull", "cycle", "path", "construction", "selection"), function(k) !is.null(RL[[k]]), logical(1))),
           ok_flags_logical = all(vapply(list(RL$crisis$ok, RL$deep$ok, RL$beta_deep$ok, RL$fast$ok, RL$beta_asym$ok, RL$bull$ok, RL$cycle$ok, RL$path$ok,
                                             RL$selection$ok, o$alpha_non_loss$ok, o$non_inferiority$ok), lgl1, logical(1))),
           verdict_in_vocab = isTRUE(o$verdict %in% P2R04_VERDICTS), verdict_name = !is.null(o$verdict_name),
           construction_ok = isTRUE(o$construction$ok), treatment_record = lgl1(o$treatment_delivered),
           selection_label_recorded = !is.null(RL$selection$label), selection_decomp_recorded = !is.null(RL$selection$decomposition$status),
           reference_points = !is.null(o$reference_points$market$all$share), state_unturned_record = is.data.frame(o$record$state_unturned_max_drop),
           conclusion_name = is.character(o$conclusion_name), test_window_split = !is.null(o$alpha_test_window) && is.null(p2_visible_only(o, TAU)$alpha_test_window))
  c(list(pass = all(chk) && all(unlist(extra)), checks = as.list(c(chk, unlist(extra))), verdict = o$verdict %||% NA_character_,
         verdict_name = o$verdict_name %||% NA_character_, why_class = why_class(o$why %||% NA_character_)))
}

## R0 — 칸 평가 분리 저장(보는 창 / 사람 쪽 · 열람 금지 표식 · 실효 시작)
stage("R0_cell_eval", function() {
  em <- p2_eval_cell(ROOT, RES, cm, env, TAU); er <- p2_eval_cell(ROOT, RES, cr, env, TAU); OBJ$em <<- em; OBJ$er <<- er
  fv <- file.path(RES, cm$code, "visible", "eval_visible.json"); ff <- file.path(RES, cm$code, "full", "eval_full.json")
  vj <- if (file.exists(fv)) fromJSON(fv, simplifyVector = FALSE) else list(); fj <- if (file.exists(ff)) fromJSON(ff, simplifyVector = FALSE) else list()
  chk <- c(status_evaluated = identical(c(em$status, er$status), c("evaluated", "evaluated")), visible_file = file.exists(fv), full_file = file.exists(ff),
           packet = file.exists(file.path(RES, cm$code, "visible", "diagnosis_packet.json")), card = file.exists(file.path(RES, cm$code, "full", "behavior_card.json")),
           marker = file.exists(file.path(RES, cm$code, "full", "NO_VISIBLE_REVIEW.txt")), visible_no_test_full = !any(c("test", "full") %in% names(vj)),
           full_audience = identical(fj$audience, P2R04_FULL_AUDIENCE), effective_start_ok = identical(em$effective_start$status, "ok") && identical(er$effective_start$status, "ok"),
           visible_packet_dates_le_tau = !length(dp_scan_dates(fromJSON(file.path(RES, cm$code, "visible", "diagnosis_packet.json"), simplifyVector = FALSE)[c("window", "behavior")], TAU)))
  list(pass = all(chk), checks = as.list(chk))
})
em <- OBJ$em; er <- OBJ$er
## R1 — 원 창 · 자연 β 비 · 판정 칸 전 경로(⑩ 구성 · ⑭ 라벨 ∧ 분해 · 크기 × β · 유동성 · 국면 월 · 기준점 · 기록)
stage("R1_original_window", function() {
  o <- p2_eval_pair(X, "E2", "H2", cm, cr, em, er, opts = EXPECT); OBJ$R1 <<- o
  shape(o, list(window_original = identical(o$window, "original"), blend_half = isTRUE(abs(o$construction$blend$device_weight - 0.5) < 1e-12),
                factor_direction_ok = identical(o$construction$factor_direction$status, "ok"), holdings_differ = isTRUE(o$holdings_overlap$n_differ > 0L),
                selection_decomp_ok = identical(o$rules$selection$decomposition$status, "ok"), size_beta_ok = identical(o$size_beta$status, "ok"),
                liquidity_ok = identical(o$liquidity$variant$status, "ok") && identical(o$liquidity$rx0$status, "ok"),
                regime_months_ok = is.numeric(o$regime_months$n_months) && o$regime_months$n_months > 0, beta_status_ok = identical(o$rules$beta_deep$status, "ok"),
                selection_status_recorded = is.character(o$rules$selection$status) && lgl1(o$rules$selection$measured),
                tbl_verdict = identical(o$tbl$verdict, o$verdict),
                marker_original = !identical(o$rules$beta_deep$comparator, "RX0 × k") ||
                  (file.exists(file.path(OUTD, cm$code, "original", "NO_VISIBLE_REVIEW.txt")) && file.exists(file.path(OUTD, cm$code, "original", "rx0_beta_scaled", "NO_VISIBLE_REVIEW.txt")))))
})
## R2 — 공통 창 강제(RX0 첫 수익일 + 1개월) · β 짝 k 0.9 강제 — 사본 · 패킷 · β 짝 사본 경로
stage("R2_common_window_forced_k", function() {
  first_ret <- min(as.Date(fread(file.path(env$E$ta_resolve_artifact(er$artifacts)$dir, "03_period_returns.csv"))$date))
  fs <- seq(first_ret, by = "month", length.out = 2L)[2]; OBJ$fs <<- fs
  o <- p2_eval_pair(X, "E2", "H2", cm, cr, em, er, opts = c(EXPECT, list(force_start = fs, force_k = 0.9))); OBJ$R2 <<- o
  pkw <- function(sub) { p <- file.path(OUTD, cm$code, paste0("common_", format(fs, "%Y%m%d")), sub, "diagnosis_packet.json")
                         if (file.exists(p)) as.Date(unlist(fromJSON(p, simplifyVector = FALSE)$window))[1] else as.Date(NA) }
  cbase <- file.path(OUTD, cm$code, paste0("common_", format(fs, "%Y%m%d")))
  shape(o, list(window_common = identical(o$window, paste0("common_from_", format(fs))), comparator_scaled = identical(o$rules$beta_deep$comparator, "RX0 × k"),
                k_forced = isTRUE(o$rules$beta_deep$k_forced), packet_starts_after_forced = isTRUE(pkw("visible") >= fs) && isTRUE(pkw("visible_rx0") >= fs),
                beta_copy_packet = file.exists(file.path(cbase, "visible_rx0_beta", "diagnosis_packet.json")),
                size_beta_ok = identical(o$size_beta$status, "ok"),
                markers_full_copies = all(file.exists(file.path(cbase, c(".", "artifacts", "rx0_artifacts", "rx0_beta_scaled"), "NO_VISIBLE_REVIEW.txt"))),
                no_marker_in_visible_packets = !any(file.exists(file.path(cbase, c("visible", "visible_rx0", "visible_rx0_beta"), "NO_VISIBLE_REVIEW.txt")))))
})
## R3a — 장치 불일치(H1 = D04 를 D03 틸트 칸에) → 미시험(구성 증거) · R3b — 변형 = RX0 산출물(장치 로그) → 미시험(무처치)
stage("R3a_device_mismatch", function() {
  o <- p2_eval_pair(X, "E2", "H1", cm, cr, em, er, opts = EXPECT)
  list(pass = !isTRUE(o$tested) && identical(why_class(o$why), "construction_evidence") && identical(o$verdict, "untested"), verdict = o$verdict, why_class = why_class(o$why))
})
em_null <- modifyList(er, list(code = CODE[["NULLC"]]))
stage("R3b_no_treatment", function() {
  o <- p2_eval_pair(X, "E2", "H2", cn, cr, em_null, er, opts = EXPECT)
  list(pass = !isTRUE(o$tested) && identical(why_class(o$why), "no_treatment") && identical(o$holdings_overlap$n_differ, 0L), verdict = o$verdict, why_class = why_class(o$why))
})
## R4a — 진단 역할(W2 = H2 짝 · 기대 가중을 이 칸의 0.5 로 맞춤) → 판정됨(크기 × β · 유동성 생략) · R4b — 진단 가중 불일치(C2 · 기대 0) → 미시험
stage("R4a_diagnostic_role", function() {
  o <- p2_eval_pair(X, "E2", "W2", cm, cr, em, er, opts = c(EXPECT, list(role = "diagnostic", expect_weight = 0.5))); OBJ$R4a <<- o
  shape(o, list(role_diag = identical(o$role, "diagnostic"), size_beta_skipped = is.null(o$size_beta), blend_ok = isTRUE(o$construction$blend$ok),
                conclusion_diag = grepl("보류|없음|방어", o$conclusion_name %||% "")))
})
stage("R4b_diagnostic_weight_mismatch", function() {
  o <- p2_eval_pair(X, "E2", "C2", cm, cr, em, er, opts = c(EXPECT, list(role = "diagnostic", expect_weight = p2_diag_expect_weight("C2", list(), ROOT))))
  list(pass = !isTRUE(o$tested) && identical(why_class(o$why), "diag_weight"), verdict = o$verdict, why_class = why_class(o$why))
})
## R5 — 진단 역할 + 보유 같음(RX0 산출물 · 칸 평가 패킷 = RX0 패킷 사본) → 무처치여도 계속 · β 짝 = RX0(k = 1) · 판정됨
stage("R5_diagnostic_identical_continues", function() {
  dir.create(file.path(RES, cn$code), showWarnings = FALSE)
  file.copy(file.path(RES, cr$code, "visible"), file.path(RES, cn$code), recursive = TRUE)
  o <- p2_eval_pair(X, "E2", "C2", cn, cr, em_null, er, opts = c(EXPECT, list(role = "diagnostic", expect_weight = 0.5))); OBJ$R5 <<- o
  ## C2 의 기대 가중(0)은 이 재료(w0 0.5)와 다르므로 여기서는 기대 가중을 재료에 맞춘다 — 검사 대상은 '보유 같음이어도 계속' 경로
  shape(o, list(continued_without_treatment = identical(o$treatment_delivered, FALSE) && isTRUE(o$tested), comparator_rx0 = identical(o$rules$beta_deep$comparator, "RX0(k ≥ 1)"),
                alpha_degenerate_tolerated = isTRUE(o$alpha_degenerate) && identical(o$alpha_non_loss$ok, FALSE), no_wins = identical(o$rules$beta_deep$share, 0)))
})
## R6 — 진단 읽기 묶음(실제 칸 결과로 · 다른 엔진 칸은 같은 결과의 엔진 표식만 바꾼 사본 — 경로 증명용)
stage("R6_readings", function() {
  relabel <- function(o, eng, dev) { o$engine <- eng; o$device <- dev; o }
  OUTr <- list(relabel(OBJ$R1, "E2", "H2"), relabel(OBJ$R1, "E3", "H2"))
  DOUTr <- list(relabel(OBJ$R5, "E2", "C2"), relabel(OBJ$R4a, "E2", "W2"), relabel(OBJ$R4a, "E3", "W2"), relabel(OBJ$R4a, "E2", "N0"))
  for (i in 2:3) DOUTr[[i]]$construction$blend$device_weight <- OBJ$R1$construction$blend$device_weight / 4   # 경로 증명용 표식 — 용량 짝 몫 < 장치 몫(가중 대조 통과판)
  RR <- p2_readings(OUTr, DOUTr, as.numeric(FS$crisis_improve_min), "H2"); OBJ$RR <<- RR
  chk <- c(missing_status = RR$missing$H2$status %in% c("ok", "b_unmeasured"), missing_counts = is.integer(RR$missing$H2$n_missing_pattern),
           capacity_label = is.character(RR$capacity$H2$label) && !grepl("미측정", RR$capacity$H2$label), dilution_status = RR$dilution$by_device$H2$status %in% c("ok", "b_unmeasured"),
           n0_summary = isTRUE(RR$dilution$n0$tested), other_engine = identical(RR$other_engine, "E3"))
  list(pass = all(chk), checks = as.list(chk), capacity_label = RR$capacity$H2$label)
})
## R7 — RX0 동일성(P2R03 E2 RX0 대비 · 판본이 달라 '다름'이 정상) · 자기 자신 대비 = 같음(양성 대조)
stage("R7_rx0_identity", function() {
  ri <- p2_rx0_identity(X, er$artifacts, file.path(ROOT, sprintf(P2R04_P2R03_RX0, "E2")))
  d <- env$E$ta_resolve_artifact(er$artifacts)$dir; rp <- function(x) { y <- fread(file.path(x, "03_period_returns.csv")); y[, date := as.Date(date)]; y }
  self <- p2_rx0_identity_core(.p2_read_holdings(d), .p2_read_holdings(d), rp(d), rp(d), TAU)
  chk <- c(status_ok = identical(ri$status, "ok"), fields = all(c("holdings_same", "returns_same", "months_differ") %in% names(ri)),
           self_same = isTRUE(self$holdings_same) && isTRUE(self$returns_same))
  list(pass = all(chk), checks = as.list(chk), p2r03_vs_p0r01 = list(holdings_same = ri$holdings_same, returns_same = ri$returns_same))
})
## R8 — 라운드 도우미(판정 표 · 선택 · R7 판독 · A 거리) + 보는 창 직렬화 · τ_D 이후 날짜 전수 검사(가림 뒤 0)
stage("R8_round_helpers_and_visible_file", function() {
  o1 <- OBJ$R1; o2 <- OBJ$R2; o2$engine <- "E3"; t2 <- copy(o2$tbl)[, engine := "E3"]
  TB <- rbindlist(list(o1$tbl, t2), use.names = TRUE)
  rv <- p2_round_verdict(TB)
  sel <- p2_select(setNames(lapply(rv$both, function(dv) list(o1, o2)), rv$both))
  nr <- p2_noise_reading(list(o1, o2), rv$both, FS$tie_eps, FS$majority_share, "H2")
  GV3 <- list(th = env$E$gv3_thresholds(ROOT), cfg = env$E$gv3_cfg(ROOT))
  ad <- lapply(c(cm$code, cr$code), function(cd) { pk <- p2_pk_read(X, cd)
    S0 <- env$E$gv3_S(rk_getf(pk, "performance.strategy.calmar"), rk_getf(pk, "performance.strategy.port_t"), GV3$th, GV3$cfg$weights)
    p2_a_distance(pk$performance$strategy, rk_getf(pk, "performance.benchmark.calmar"), GV3$th, S0, GV3$cfg$a_boundary) })
  VIS <- list(cells = lapply(list(o1, o2, OBJ$R4a, OBJ$R5), p2_visible_only, tau = TAU), readings = p2_visible_only(OBJ$RR, TAU), table = TB, noise = nr, a_distance = ad)
  tf <- file.path(OUTD, "vis_test.json"); writeLines(toJSON(VIS, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), tf, useBytes = TRUE)
  back <- fromJSON(tf, simplifyVector = FALSE)
  chk <- c(verdict_vocab = rv$verdict %in% c("supported", "partial", "falsified", "untested"), label = grepl("판정 2/2 · ", rv$label, fixed = TRUE), select_shape = is.list(sel),
           noise_logical = is.logical(nr$result) && length(nr$result) == 1L, noise_unreadable_one_device = is.na(nr$result) && grepl("판독 불가", nr$label),
           a_distance_fields = all(vapply(ad, function(z) all(c("cagr", "sharpe", "calmar", "port_t", "S") %in% names(z)) &&
                                                                                  lgl1(z$cagr$meets) && is.finite(z$cagr$threshold), logical(1))),
           json_roundtrip = length(back$cells) == 4L, no_test_window_in_visible = !any(vapply(back$cells, function(z) !is.null(z$alpha_test_window), logical(1))),
           no_cell_log_full_period = !any(vapply(back$cells, function(z) !is.null(z$cell_log_full_period), logical(1))),
           no_dates_after_tau = !length(dp_scan_dates(back, TAU)))
  list(pass = all(chk), checks = as.list(chk), round_verdict = rv$verdict, noise_reading = nr$result)
})
MD5_AT_END <- vapply(names(MD5_AT_LOAD), function(f) rk_md5(file.path(RD, f)), character(1))
unchanged <- identical(unname(MD5_AT_LOAD), unname(MD5_AT_END))
if (!unchanged) cat("[리허설] 실행 중 evaluate.R · round_rules.R · rehearse.R 가 바뀌었다 — 이 리허설은 무효(다시 돌린다)\n")
pass <- all(vapply(S, function(s) isTRUE(s$pass), logical(1))) && unchanged
res <- list(schema = "p2r04_rehearsal_v1", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), evaluate_md5 = MD5_AT_LOAD[["evaluate.R"]],
            round_rules_md5 = MD5_AT_LOAD[["round_rules.R"]], rehearse_md5 = MD5_AT_LOAD[["rehearse.R"]], files_unchanged_during_run = unchanged,
            behavior_card_cfg = sub(paste0("^", ROOT, "/"), "", BCP),
            inputs = list(variant = SRC[["H2"]], rx0 = SRC[["RX0"]], fake_codes = unname(CODE), forced_start = format(OBJ$fs %||% as.Date(NA)), forced_k = 0.9,
                          note = paste0("P0R01 같은 엔진 · 같은 배치 두 칸(E2 기준 · E2 D03 저변동 틸트 w0 0.5 · 구 축 all_hyg_2000_v1)을 가짜 코드로 묶은 코드 경로 증명 — ",
                                        "판정용 아님 · 성과 수치 · 시험 창 · 전기간 값은 이 요약에 싣지 않는다")),
            stages = S, pass = pass, seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs"))))
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RD, "rehearsal", "summary.json"), useBytes = TRUE)
unlink(OUTD, recursive = TRUE)
cat(sprintf("[리허설] %s — %d초 · 요약 rehearsal/summary.json\n", if (pass) "통과" else "실패", res$seconds))
quit(status = if (pass) 0L else 1L)
