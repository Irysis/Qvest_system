#!/usr/bin/env Rscript
#==============================================================================
# test_rf_a_eligibility.R — 러너 관문 P0-10 · P0-11 · P0-12 · 규약 혼합 가드 **양방향 검사** (2026-09-24)
#
# 재는 것 (판정 = rf_runner_gates.R 순수 함수 · 부작용 = 없음):
#   A  A 자격 관문 rf_a_eligibility — 합성 A 5종(legacy regime / 2012 시작 / 미검증 승계 층 / C11 표식 / n_trials 결측)이 각각
#      보류 + 사유 코드 · 정상 픽스처는 발행 · 결정상 꺼진 코드(sigma_w_lt_1·dossier·rule)는 inactive 로만 · 설정 fail-closed ·
#      [돌연변이] 구 관문(rf_grade_a_hold 단독)은 5종을 전부 발행한다
#   B  P0-11 rf_adversary_ok — 자기 층 B5 verdict 부재 = unverified(FALSE) · B1~B4 는 현행 · 원장 **사본** 전수:
#      보류 수 = 독립 재도출(층 평탄화를 검사가 따로 구현) · 알려진 칸(14760 promo3 B5_16~20) 개별 · [돌연변이] 구 술어 red
#   D  규약 혼합 가드 — rf_candidates_keep(현행 규약 칸만 · rebase 표식 인정) · [대조] 현행 규약을 legacy 로 주입하면 반대 · 규약 판독 불가 = 후보 0
#   E  carry 기준선 rf_carry_base_info(부모 승자 칸 기록값 · 처치 유니버스 출처·규약 혼합 → NA) · 바닥 carry 게이트 rf_floor_carry_gate 판정
#   F  바닥·carry 기준선 유니버스·창 한정 — 바닥 후보 술어(F1) · carry 기준선 spec 판독(F3) · [돌연변이 M11·M12] 역할 검사 축소 red(F4)
# (v10.01 2026-10-13) 고정 격자 러너 퇴역으로 C0~C3b(러너 바닥 carry 게이트 블록 추출 · 원장 리플레이) · D5·D6(러너 .winner_of 추출) ·
#   E1~E4(승격 best rf_promote_best — rf_promote.R) · F2(러너 바닥 블록 추출) 삭제 — 대상 코드가 없다(롤백 태그 pre-v10.01-prescription-20261013).
#   rf_candidates_keep·rf_floor_carry_gate·rf_carry_base_info 는 rf_runner_gates.R 에 남아 함수 단위로만 잰다(실소비자 없음 — 배선 재표적 대상 없음).
# 부작용 없음: 운영 원장은 **읽기 전용 사본**(tempdir)으로만 · 쓰기는 전부 tempdir 샌드박스 root.
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_a_eligibility.R
#   (QVEST_TEST_LEDGER_L1 = 원장 원본 경로 주입 — 기본 <ROOT>/06_Registry/reinforce_ledger_l1.json · 사본을 떠서만 읽는다)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
cat(sprintf("ROOT = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
sk <- function(m, why = "") { SKIP <<- SKIP + 1L; cat("  SKIP", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
invisible(capture.output(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"))
  source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"))
  source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")) })))

# ── 샌드박스 root (설정 사본 · 합성 산출물) ─────────────────────────────────────────
S <- file.path(tempdir(), sprintf("rf_aelig_%d", Sys.getpid()))
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts", "06_Registry", "stage_artifacts/replication", ".cache/rf_parallel"))
  dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S, "02_Infrastructure/worktask"), overwrite = TRUE))
invisible(file.copy(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R"), file.path(S, "02_Infrastructure/contracts"), overwrite = TRUE))
invisible(file.copy(file.path(ROOT, "06_Registry/a_eligibility_gate.json"), file.path(S, "06_Registry"), overwrite = TRUE))
if (!all(file.exists(file.path(S, c("02_Infrastructure/worktask/constraint_defaults.json", "02_Infrastructure/contracts/essence_score.R",
                                    "06_Registry/a_eligibility_gate.json"))))) { cat("  FAIL 샌드박스 설정 사본 실패\n"); quit(status = 1) }
CUR <- rf_current_regime(S)$regime   # 현행 규약(설정 사본에서 — 하드코딩하지 않는다)

mk_art <- function(tag, regime = CUR, start = "2005-02-01", mr = TRUE, n_trials = 12L,
                   basis = "base1+lineage_measured(excl_inherited)+batch_size", sel = "sweep", dsr = 0.9) {
  d <- file.path(S, "stage_artifacts/replication", tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  dates <- seq(as.Date(start), as.Date("2026-08-01"), by = "month")
  saveRDS(list(holdings = data.frame(date = dates, ticker = "A005930", weight = 1),
               period_returns = data.frame(date = dates, ret_net = 0.01)), file.path(d, "bt_result.rds"))
  au <- list(status = "OK", essence_grade = "A", selection_type = sel, dsr = dsr, essence = list(dsr = dsr))
  if (!is.null(n_trials)) au$n_trials_cumulative <- n_trials
  if (isTRUE(mr)) {
    au$measurement_regime <- list(selection_type = sel, n_trials_basis = basis, exec_price = regime)
    if (!is.null(n_trials)) au$measurement_regime$n_trials_cumulative <- n_trials
  }
  writeLines(toJSON(au, auto_unbox = TRUE, null = "null"), file.path(d, "authoritative_remeasure.json"))
  d
}
mk_spec <- function(code, overlay = NULL, overlay_cell = NULL, universe = list(kind = "k200_kq150"), tag = code,
                    factors = list(list(kind = "db", id = "F1"))) {
  p <- file.path(S, ".cache/rf_parallel", sprintf("spec_%s__T.json", tag))
  sp <- list(code = code, factors = factors, weighting = list(kind = "ew"), universe = universe)
  if (!is.null(overlay)) sp$overlay <- overlay
  if (!is.null(overlay_cell)) sp$overlay_cell <- overlay_cell
  writeLines(toJSON(sp, auto_unbox = TRUE, null = "null"), p); p
}
mk_att <- function(n, code, art, spec, grade = "A", pt = 3.2, flags = NULL, adv = NULL, mr = NULL) {
  a <- list(n = as.integer(n), cell_code = code, grade = grade, artifacts = art,
            essence = list(cell_code = code, port_t = pt, calmar = 0.7, spec = spec))
  if (!is.null(flags)) a$vintage_flags <- flags
  if (!is.null(adv)) a$adversary <- adv
  if (!is.null(mr)) a$measurement_regime <- mr
  a
}
BID <- "T_AELIG"
elig_of <- function(att, entry = list(base_id = BID, status = "active", attempts = list(att)), extra = list(), axes = NULL, root = S) {
  ents <- c(list(entry), extra)
  rf_a_eligibility(entry, att, NULL, rf_a_ctx(rf_runner_ctx(root), ents, BID, axes = axes))
}
codes_of <- function(el) paste(sort(el$codes), collapse = "+")

cat("\n=== A. A 자격 관문 — 합성 A 5종 · 정상 · 비활성 · fail-closed ===\n")
chk(!is.na(CUR) && nzchar(CUR), sprintf("A0 현행 규약 판독(설정 사본) = %s", CUR), "constraint_defaults.json::execution.exec_price 판독 불가")
LEG <- setdiff(c("close_d_legacy", "close_t1", "open_t1"), CUR)[1]
art_ok <- mk_art("ok"); sp_ok <- mk_spec("B2_6", overlay_cell = list())
e0 <- elig_of(mk_att(6, "B2_6", art_ok, sp_ok))
chk(isTRUE(e0$eligible) && !length(e0$codes), "A1 [양성] 정상 픽스처(현행 규약·2005 시작·sweep N=12 DSR 0.9·오버레이 없음) → 발행",
    paste(codes_of(e0), paste(unlist(e0$detail), collapse = " | ")))
chk(all(c("dossier_pending", "rule_pending") %in% e0$inactive) && !any(c("dossier_pending", "rule_pending") %in% e0$codes),
    "A1b 결정상 꺼진 dossier_pending·rule_pending 은 inactive 로만 기록(D-B — 발행을 막지 않는다)", paste(e0$inactive, collapse = ","))
syn <- list(
  legacy = list(att = mk_att(7, "B2_7", mk_art("legacy", regime = LEG), mk_spec("B2_7", overlay_cell = list())), want = "legacy_regime"),
  y2012  = list(att = mk_att(8, "B2_8", mk_art("y2012", start = "2012-01-02"), mk_spec("B2_8", overlay_cell = list())), want = "window_deviation"),
  inherit = list(att = mk_att(9, "B2_9", mk_art("inherit"), mk_spec("B2_9", overlay = list(kind = "k_old", arm_id = "arm_old"),
                                                                     overlay_cell = list())), want = "adversary_unverified"),
  c11    = list(att = mk_att(10, "B2_10", mk_art("c11"), mk_spec("B2_10", overlay_cell = list()),
                             flags = list(list(flag = "pit_c11", verdict = "consumed"))), want = "vintage_flag"),
  ntrial = list(att = mk_att(11, "B3_11", mk_art("ntrial", n_trials = NULL), mk_spec("B3_11", overlay_cell = list())), want = "n_trials_missing"))
for (nm in names(syn)) {
  el <- elig_of(syn[[nm]]$att)
  chk(!isTRUE(el$eligible) && identical(el$codes, syn[[nm]]$want),
      sprintf("A2 [주입] 합성 A '%s' → 보류 · 사유 코드 = %s (단독)", nm, syn[[nm]]$want),
      sprintf("codes=%s detail=%s", codes_of(el), paste(unlist(el$detail), collapse = " | ")))
}
el <- elig_of(mk_att(12, "B2_6", mk_art("pre_p0", mr = FALSE, n_trials = NULL, sel = "chain"), mk_spec("B2_6x", overlay_cell = list())))
chk(!isTRUE(el$eligible) && all(c("legacy_regime", "accounting_fail", "n_trials_missing") %in% el$codes),
    "A3 P0-01 이전 산출물(measurement_regime·n_trials 부재 · chain) → legacy_regime + accounting_fail + n_trials_missing", codes_of(el))
el <- elig_of(mk_att(13, "B2_6", mk_art("unk_basis", n_trials = 1L, basis = "unknown_legacy_spec_no_accounting"), mk_spec("B2_6u", overlay_cell = list())))
chk("n_trials_missing" %in% el$codes, "A3b n_trials_basis=unknown_*(회계 없는 구 spec 재개 · N 추정 금지) → n_trials_missing", codes_of(el))
el <- elig_of(mk_att(14, "B2_6", mk_art("nodsr", dsr = NA), mk_spec("B2_6d", overlay_cell = list())))
chk(identical(el$codes, "accounting_fail"), "A3c sweep·N≥2 인데 DSR 부재 → accounting_fail", codes_of(el))
# 승계 층 — 계보에 pass 기록이 있으면 발행(양성 대조: 같은 픽스처가 기록 하나로 갈린다)
parent <- list(base_id = "T_PARENT", status = "exhausted", attempts = list(
  list(n = 3L, cell_code = "B5_18", grade = "B", essence = list(port_t = 2, spec = ""),
       adversary = list(verdict = "pass", own_layers = list(list(kind = "k_old", arm_id = "arm_old"))))))
ent_child <- list(base_id = BID, status = "active", parent = list(base_id = "T_PARENT"), attempts = list(syn$inherit$att))
el <- elig_of(syn$inherit$att, entry = ent_child, extra = list(parent))
chk(isTRUE(el$eligible), "A4 [양성] 같은 승계 층이 부모 계보의 적대검증 pass 기록에 있으면 발행", codes_of(el))
# (modifyList 는 이름 없는 리스트 원소를 바꾸지 않는다 — 부모를 명시적으로 다시 만든다)
parent_fail <- parent; parent_fail$attempts[[1]]$adversary$verdict <- "fail"
el <- elig_of(syn$inherit$att, entry = ent_child, extra = list(parent_fail))
chk("adversary_unverified" %in% el$codes && identical(parent_fail$attempts[[1]]$adversary$verdict, "fail"),
    "A4b 부모 기록이 fail 이면 승계 층은 여전히 미검증 → 보류", codes_of(el))
# 자기 층 B5 (구 rf_grade_a_hold 흡수)
OWN <- list(kind = "k_new", arm_id = "arm_new")
a5 <- mk_att(16, "B5_16", mk_art("b5"), mk_spec("B5_16", overlay = OWN, overlay_cell = OWN))
el <- elig_of(a5)
chk(identical(el$codes, "adversary_unverified") && isTRUE(el$self_unverified), "A5 자기 층 B5 · verdict 없음 → adversary_unverified(self)", codes_of(el))
el <- elig_of(modifyList(a5, list(adversary = list(verdict = "pass", own_layers = list(OWN)))))
chk(isTRUE(el$eligible), "A5b 같은 칸 verdict pass → 발행(자기 층 검증 · 승계 층 없음)", codes_of(el))
el <- elig_of(modifyList(a5, list(adversary = list(verdict = "deferred_refresh_lock"))))
chk("adversary_unverified" %in% el$codes, "A5c deferred_refresh_lock 은 pass 가 아니다 → 보류", codes_of(el))
# 비활성 코드 — 라벨이 있어도 발행 · 설정에서 켜면 보류(설정이 실제로 가른다)
el <- elig_of(mk_att(17, "B2_6", art_ok, sp_ok), axes = list(labels = "sigma_w_lt_1"))
chk(isTRUE(el$eligible) && "sigma_w_lt_1" %in% el$inactive, "A6 Σw<1 라벨 → inactive 기록만(D-D · 발행)", paste(el$inactive, collapse = ","))
S2 <- file.path(tempdir(), sprintf("rf_aelig2_%d", Sys.getpid())); dir.create(file.path(S2, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts")) {
  dir.create(file.path(S2, d), recursive = TRUE, showWarnings = FALSE)
  invisible(file.copy(list.files(file.path(S, d), full.names = TRUE), file.path(S2, d), overwrite = TRUE)) }
G <- fromJSON(file.path(S, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)
G2 <- G; G2$holds$sigma_w_lt_1$active <- TRUE
writeLines(toJSON(G2, auto_unbox = TRUE, null = "null"), file.path(S2, "06_Registry/a_eligibility_gate.json"))
el <- elig_of(mk_att(17, "B2_6", art_ok, sp_ok), axes = list(labels = "sigma_w_lt_1"), root = S2)
chk(identical(el$codes, "sigma_w_lt_1"), "A6b [대조] 설정에서 sigma_w_lt_1 를 켜면 같은 칸이 보류된다 — on/off 가 설정에서 온다", codes_of(el))
for (case in c("absent", "unknown_code", "string_active")) {
  if (case == "absent") unlink(file.path(S2, "06_Registry/a_eligibility_gate.json"))
  if (case == "unknown_code") { G3 <- G; G3$holds$typo_code <- list(active = FALSE)
    writeLines(toJSON(G3, auto_unbox = TRUE, null = "null"), file.path(S2, "06_Registry/a_eligibility_gate.json")) }
  if (case == "string_active") { G3 <- G; G3$holds$legacy_regime$active <- "false"
    writeLines(toJSON(G3, auto_unbox = TRUE, null = "null"), file.path(S2, "06_Registry/a_eligibility_gate.json")) }
  el <- elig_of(mk_att(18, "B2_6", art_ok, sp_ok), root = S2)
  chk(!isTRUE(el$eligible) && "gate_config" %in% el$codes, sprintf("A7 설정 불량(%s) → gate_config 보류(fail-closed · 오타가 보류를 끄지 못한다)", case), codes_of(el))
}
unlink(file.path(S2, "02_Infrastructure/worktask/constraint_defaults.json"))
invisible(file.copy(file.path(S, "06_Registry/a_eligibility_gate.json"), file.path(S2, "06_Registry"), overwrite = TRUE))
el <- elig_of(mk_att(19, "B2_6", art_ok, sp_ok), root = S2)
chk("legacy_regime" %in% el$codes, "A8 현행 규약 판독 불가(constraint_defaults 부재) → legacy_regime 보류(fail-closed)", codes_of(el))
# rebase 된 칸(P0-06) — 원 산출물은 P0-01 이전 판(회계 없음 · legacy)이고 원장 표식이 형제 재측정 판을 가리킨다
art_pre <- mk_art("rebased_pre", mr = FALSE, n_trials = NULL, sel = "chain")
sib_dir <- file.path(art_pre, sprintf("remeasure_%s_ab12cd34", CUR)); dir.create(sib_dir, showWarnings = FALSE)
writeLines(toJSON(list(essence_grade = "A", selection_type = "sweep", n_trials_cumulative = 40L, dsr = 0.8,
                       measurement_regime = list(key = sprintf("%s_ab12cd34", CUR), exec_price = CUR, selection_type = "sweep",
                                                 n_trials_cumulative = 40L, n_trials_basis = "argument")), auto_unbox = TRUE),
           file.path(sib_dir, "authoritative_remeasure.json"))
mr_reb <- list(key = sprintf("%s_ab12cd34", CUR), exec_price = CUR, selection_type = "sweep", n_trials_cumulative = 40L,
               regime = sprintf("%s_ab12cd34", CUR), basis = "rebase", remeasure_path = file.path(sib_dir, "authoritative_remeasure.json"))
a_reb <- mk_att(20, "B2_6", art_pre, mk_spec("B2_6r", overlay_cell = list()), mr = mr_reb)
el <- elig_of(a_reb)
chk(isTRUE(el$eligible) && identical(el$facts$regime, CUR) && identical(el$facts$accounting_source, "rebase_sibling"),
    "A11 rebase 칸 — 원장 표식 exec_price 로 규약 판정 · 회계는 형제 재측정 판(원 산출물은 P0-01 이전) → 발행",
    sprintf("%s · regime=%s · src=%s", codes_of(el), el$facts$regime %||% "?", el$facts$accounting_source %||% "?"))
a_key <- a_reb; a_key$measurement_regime <- list(regime = sprintf("%s_ab12cd34", CUR), remeasure_path = mr_reb$remeasure_path)  # (modifyList 는 병합 — 교체로)
el <- elig_of(a_key)
chk(isTRUE(el$eligible) && identical(el$facts$regime, CUR) && is.null(a_key$measurement_regime$exec_price),
    "A11b 표식이 키 라벨(<규약>_<md5 8>)만 가져도 체결 규약으로 정규화(허용 규약명 접두) → 현행 규약", el$facts$regime %||% "?")
a_reb2 <- a_reb; a_reb2$measurement_regime$remeasure_path <- NULL
el <- elig_of(a_reb2)
chk(all(c("accounting_fail", "n_trials_missing") %in% el$codes) && !("legacy_regime" %in% el$codes),
    "A11c [대조] 형제 경로가 없으면 회계를 원 산출물(P0-01 이전)에서 읽어 보류 — 회계 원천이 실제로 가른다", codes_of(el))
# 돌연변이 — 구 관문(적대검증 자기 층만 · rf_grade_a_hold)은 합성 5종을 전부 **발행**한다 = 이 검사가 그 결함을 잡는다
old_pub <- vapply(syn, function(x) !rf_grade_a_hold(x$att$cell_code, fromJSON(x$att$essence$spec, simplifyVector = FALSE), NULL, x$att), logical(1))
chk(all(old_pub), sprintf("A9 [돌연변이] 구 관문이면 합성 5종 전부 발행(%d/5) — 새 관문만 막는다", sum(old_pub)), paste(names(syn)[!old_pub], collapse = ","))
chk(identical(rf_grade_a_hold("B5_16", fromJSON(a5$essence$spec, simplifyVector = FALSE), NULL, a5), TRUE) &&
      identical(rf_grade_a_hold("B1_1", list(overlay = OWN, overlay_cell = list()), NULL, NULL), FALSE),
    "A10 rf_grade_a_hold 호환(흡수된 자기 층 성분 — 기존 검사·수동 호출 계약 불변)")

cat("\n=== B. P0-11 적대검증 소비 술어 ===\n")
chk(rf_adversary_ok(list(n = 1L)) && rf_adversary_ok(mk_att(1, "B1_1", art_ok, sp_ok)) &&
      rf_adversary_ok(mk_att(2, "B4_21", art_ok, mk_spec("B4_21", overlay = OWN))),
    "B1 verdict 없는 B1~B4 칸·코드 없는 구 attempt → TRUE(현행 유지 — B4 의 오버레이는 승계분)")
chk(!rf_adversary_ok(a5) && identical(rf_adversary_status(a5)$status, "unverified"),
    "B2 자기 층 B5 · verdict 없음 → FALSE(unverified) ★P0-11")
chk(rf_adversary_ok(mk_att(3, "B5_17", art_ok, mk_spec("B5_17", overlay = OWN, overlay_cell = list()))),
    "B3 B5 인데 자기 층 없음(overlay_cell=[] · 승계분만) → TRUE")
chk(!rf_adversary_ok(mk_att(4, "B5_18", art_ok, file.path(S, "no_such_spec.json"))), "B4 B5 spec 판독 불가 → FALSE(정직 결측)")
chk(rf_adversary_ok(modifyList(a5, list(adversary = list(verdict = "pass")))) &&
      all(!vapply(c("fail", "error", "not_candidate", "deferred_refresh_lock"), function(v) rf_adversary_ok(modifyList(a5, list(adversary = list(verdict = v)))), logical(1))),
    "B5 verdict 있으면 pass 만 TRUE(fail·error·not_candidate·deferred_refresh_lock FALSE — 구판과 같다)")
old_ok <- function(a) { v <- as.character((a$adversary %||% list())$verdict %||% "")[1]; is.na(v) || !nzchar(v) || identical(v, "pass") }
chk(old_ok(a5) && !rf_adversary_ok(a5), "B6 [돌연변이] 구 술어(verdict 부재 = 통과)는 미검증 B5 를 소비한다 — 새 술어만 막는다")
# 원장 사본 전수 — 보류 수 = 독립 재도출
LSRC <- Sys.getenv("QVEST_TEST_LEDGER_L1", file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"))
LCOPY <- file.path(tempdir(), sprintf("ledger_l1_copy_%d.json", Sys.getpid()))
LED <- NULL
if (file.exists(LSRC) && isTRUE(file.copy(LSRC, LCOPY, overwrite = TRUE))) LED <- tryCatch(fromJSON(LCOPY, simplifyVector = FALSE), error = function(e) NULL)
if (is.null(LED)) sk("B7~B9 원장 사본", "원장 원본 부재·파손") else {
  md5_src0 <- unname(tools::md5sum(LSRC))
  # 독립 층 평탄화(검사 전용 구현 — .ov_layers/.ov_own_layers 를 쓰지 않는다): kind 가 있는 객체 = 층 · 리스트 = 재귀
  flat <- function(x) { if (!is.list(x) || !length(x)) return(0L); if (!is.null(x[["kind"]])) return(1L); sum(vapply(x, flat, integer(1))) }
  n_b5_nov <- 0L; n_hold_ind <- 0L; n_hold_pred <- 0L; n_nonb5_nov <- 0L; n_nonb5_ok <- 0L; mism <- character(0)
  for (e in LED$entries) for (a in e$attempts %||% list()) {
    if (is.null(a[["essence"]]) || !is.numeric(a$essence$port_t %||% NULL)) next
    v <- as.character((a$adversary %||% list())$verdict %||% "")
    cd <- as.character(a$cell_code %||% a$essence$cell_code %||% "")
    if (nzchar(v)) next
    if (startsWith(cd, "B5_")) {
      n_b5_nov <- n_b5_nov + 1L
      sp <- tryCatch(fromJSON(as.character(a$essence$spec %||% ""), simplifyVector = FALSE), error = function(z) NULL)
      ind <- if (is.null(sp)) TRUE else if (!is.null(sp[["overlay_cell"]])) flat(sp[["overlay_cell"]]) > 0L else flat(sp[["overlay"]]) > 0L
      pred <- !rf_adversary_ok(a)
      n_hold_ind <- n_hold_ind + ind; n_hold_pred <- n_hold_pred + pred
      if (!identical(ind, pred)) mism <- c(mism, sprintf("%s/%s", e$base_id, cd))
    } else { n_nonb5_nov <- n_nonb5_nov + 1L; n_nonb5_ok <- n_nonb5_ok + rf_adversary_ok(a) }
  }
  chk(n_hold_pred == n_hold_ind && !length(mism) && n_hold_pred > 0L,
      sprintf("B7 원장 사본: verdict 없는 측정 B5 %d칸 중 보류 %d = 독립 재도출 %d(칸 단위 불일치 %d)", n_b5_nov, n_hold_pred, n_hold_ind, length(mism)),
      paste(utils::head(mism, 5), collapse = ","))
  chk(n_nonb5_ok == n_nonb5_nov, sprintf("B8 원장 사본: verdict 없는 B5 밖 측정 칸 %d 전부 소비 가능(현행 유지)", n_nonb5_nov), sprintf("%d/%d", n_nonb5_ok, n_nonb5_nov))
  E3 <- Filter(function(e) identical(e$base_id, "RP_20260913_090549_14760_adapted_rulefast_promo3"), LED$entries)
  if (!length(E3)) sk("B9 알려진 칸", "14760 promo3 entry 부재") else {
    b5 <- Filter(function(a) startsWith(as.character(a$cell_code %||% ""), "B5_"), E3[[1]]$attempts)
    st <- vapply(b5, function(a) rf_adversary_status(a)$status, character(1))
    chk(length(b5) == 5L && all(st == "unverified"),
        sprintf("B9 알려진 칸 14760 promo3 B5_16~20(B5_19 = 프로그램 최고 Calmar 0.609) → 전부 unverified(%s)", paste(st, collapse = ",")))
  }
  chk(identical(unname(tools::md5sum(LSRC)), md5_src0), "B10 원장 원본 md5 불변(사본만 읽었다)")
}

cat("\n=== D. 규약 혼합 가드 ===\n")
art_leg <- mk_art("mix_leg", regime = LEG); art_cur <- mk_art("mix_cur")
aL <- mk_att(1, "B1_1", art_leg, mk_spec("B1_1", factors = list(list(kind = "db", id = "LEGACY"))), grade = "B", pt = 3.0)
aC <- mk_att(2, "B1_2", art_cur, mk_spec("B1_2", factors = list(list(kind = "db", id = "CURRENT"))), grade = "B", pt = 2.0)
aR <- mk_att(3, "B1_3", art_leg, mk_spec("B1_3", factors = list(list(kind = "db", id = "REBASED"))), grade = "B", pt = 1.5,
             mr = list(regime = CUR, basis = "rebase"))
EVD <- list(); lg <- function(event, ...) EVD[[length(EVD) + 1L]] <<- c(list(event = event), list(...))
kept <- rf_candidates_keep(list(aL, aC, aR), rf_runner_ctx(S), role = "floor", log = lg, base_id = BID)
chk(identical(vapply(kept, function(a) a$cell_code, ""), c("B1_2", "B1_3")),
    "D1 rf_candidates_keep — 현행 규약 칸(산출물 판 · rebase 표식 판)만 남고 legacy 칸 제외", paste(vapply(kept, function(a) a$cell_code, ""), collapse = ","))
chk(length(EVD) == 1L && identical(EVD[[1]]$event, "candidates_excluded") && grepl("regime_mismatch=1", EVD[[1]]$by_reason),
    "D2 제외는 역할당 로그 1줄(candidates_excluded · 사유 집계)", toJSON(EVD, auto_unbox = TRUE))
aK <- mk_att(4, "B1_4", art_leg, mk_spec("B1_4", factors = list(list(kind = "db", id = "KEYLABEL"))), grade = "B", pt = 1.2,
             mr = list(regime = sprintf("%s_ab12cd34", CUR), basis = "rebase"))
chk(length(rf_candidates_keep(list(aK), rf_runner_ctx(S), role = "floor")) == 1L,
    "D2b rebase 표식이 P0-05 키 라벨(<규약>_<md5 8>)이어도 현행 규약 칸으로 인정(체결 규약 정규화)")
kc <- rf_candidates_keep(list(aL, aC), rf_runner_ctx(S, regime = LEG), role = "winner_B1")
chk(identical(vapply(kc, function(a) a$cell_code, ""), "B1_1"), "D3 [대조] 현행 규약을 legacy 로 주입하면 반대로 legacy 칸만 남는다(가드가 규약 값으로 가른다)")
S3 <- file.path(tempdir(), sprintf("rf_aelig3_%d", Sys.getpid())); dir.create(S3, showWarnings = FALSE)
kc <- rf_candidates_keep(list(aL, aC), rf_runner_ctx(S3), role = "floor")
chk(!length(kc), "D4 현행 규약 판독 불가 → 후보 0(fail-closed · 섞지 않는다)")

cat("\n=== E. carry 기준선 · 바닥 carry 게이트 (승격 best E1~E4 는 v10.01 삭제) ===\n")
par_e <-list(base_id = "T_P", status = "exhausted", attempts = list(mk_att(7, "B2_7", mk_art("cb_ok"), mk_spec("B2_7cb"), grade = "B", pt = 2.5)))
kid <- list(base_id = "T_P_promo1", carry = list(factors = list(), universe = list(kind = "k200_kq150"), universe_reset_from = list(kind = "k200_kq150")),
            parent = list(base_id = "T_P", cell = "B2_7", best_port_t = 2.5))
cb <- rf_carry_base_info(kid, list(par_e, kid), rf_runner_ctx(S))
chk(identical(cb$why, "ok") && isTRUE(abs(cb$value - 2.5) < 1e-9), "E5 carry 기준선 — 부모 승자 칸이 현행 규약·k200·창 안이면 기록값", cb$why)
kid_u <- kid; kid_u$carry$universe_reset_from <- list(kind = "index", flag = "KQ150")
cb <- rf_carry_base_info(kid_u, list(par_e, kid_u), rf_runner_ctx(S))
chk(is.na(cb$value) && startsWith(cb$why, "carry_source_universe"), "E6 carry 출처가 처치 유니버스(D2-08) → 기준선 NA(비교 불가 · 게이트 무발화)", cb$why)
cb <- rf_carry_base_info(kid, list(par_e, kid), rf_runner_ctx(S, regime = LEG))
chk(is.na(cb$value) && grepl("regime_mismatch", cb$why), "E7 부모 승자 칸 규약 ≠ 현행 → 기준선 NA(규약 혼합 비교 금지)", cb$why)
g1 <- rf_floor_carry_gate(list(factors = list()), 2.4, kid$carry, 2.5); g2 <- rf_floor_carry_gate(list(factors = list()), 2.6, kid$carry, 2.5)
g3 <- rf_floor_carry_gate(NULL, NA, kid$carry, 2.5); g4 <- rf_floor_carry_gate(list(factors = list()), 1.0, kid$carry, NA)
chk(isTRUE(g1$use_carry) && !isTRUE(g2$use_carry) && isTRUE(g3$use_carry) && !isTRUE(g4$use_carry) && identical(g1$spec$floor_source, "carry"),
    "E8 rf_floor_carry_gate — 미달·바닥 없음 → carry · 초과 → 바닥 유지 · 기준선 NA → 무발화")

cat("\n=== F. ★바닥·carry 기준선 유니버스·창 한정 (2026-09-24 수리 · 적대검증 G-F2 — M11·M12 돌연변이 생존) ===\n")
# 픽스처: PORT_t 최고 = B3 KQ150 처치 유니버스 칸(4.2) · 차순위 = 2012 시작 창 이탈 칸(4.0) · 자격 칸 = k200·2005 시작(3.0)
fu <- mk_att(1, "B3_11", mk_art("f_kq"), mk_spec("B3_11f", universe = list(kind = "index", flag = "KQ150"),
                                                factors = list(list(kind = "db", id = "KQ"))), grade = "B", pt = 4.2)
fw <- mk_att(2, "B2_6", mk_art("f_2012", start = "2012-01-02"), mk_spec("B2_6f", factors = list(list(kind = "db", id = "Y2012"))), grade = "B", pt = 4.0)
fk <- mk_att(3, "B2_7", mk_art("f_ok"), mk_spec("B2_7f", factors = list(list(kind = "db", id = "OK"))), grade = "B", pt = 3.0)
kf <- rf_candidates_keep(list(fu, fw, fk), rf_runner_ctx(S), role = "floor")
chk(identical(vapply(kf, function(a) a$cell_code, ""), "B2_7"),
    "F1 바닥 후보 — KQ150 처치 유니버스(4.2)·2012 시작 창 이탈(4.0) 칸 제외 · k200·창 안 칸(3.0)만", paste(vapply(kf, function(a) a$cell_code, ""), collapse = ","))
# carry 기준선 — 부모 승자 칸이 처치 유니버스(spec 판독) / 창 이탈이면 기준선 NA(비교 불가 · 게이트 무발화)
par_u <- list(base_id = "T_PU", status = "exhausted", attempts = list(fu)); par_w <- list(base_id = "T_PW", status = "exhausted", attempts = list(fw))
kid_of <- function(pid, cell, pt) list(base_id = paste0(pid, "_promo1"), carry = list(factors = list(), universe = list(kind = "k200_kq150"),
                                                                                      universe_reset_from = list(kind = "k200_kq150")),
                                        parent = list(base_id = pid, cell = cell, best_port_t = pt))
ku <- kid_of("T_PU", "B3_11", 4.2); kw <- kid_of("T_PW", "B2_6", 4.0)
cbu <- rf_carry_base_info(ku, list(par_u, ku), rf_runner_ctx(S)); cbw <- rf_carry_base_info(kw, list(par_w, kw), rf_runner_ctx(S))
chk(is.na(cbu$value) && grepl("^parent_best_universe", cbu$why) && is.na(cbw$value) && grepl("^parent_best_window_deviation", cbw$why),
    "F3 carry 기준선 — 부모 승자 칸이 처치 유니버스(carry 리셋 표기와 무관하게 spec 판독)·창 이탈이면 NA(섞인 기준선으로 막지 않는다)",
    sprintf("u=%s w=%s", cbu$why, cbw$why))
# 돌연변이 M11·M12 — 역할 검사를 규약만으로 줄이면(적대검증이 살려 낸 두 돌연변이) F1·F3 가 red 가 된다(자기 실증)
.rc0 <- RF_ROLE_CHECKS
RF_ROLE_CHECKS$floor <- "regime"
m11 <- vapply(rf_candidates_keep(list(fu, fw, fk), rf_runner_ctx(S), role = "floor"), function(a) a$cell_code, "")
RF_ROLE_CHECKS <- .rc0; RF_ROLE_CHECKS$carry_base <- "regime"
m12 <- rf_carry_base_info(ku, list(par_u, ku), rf_runner_ctx(S))
RF_ROLE_CHECKS <- .rc0
chk(length(m11) == 3L && identical(m12$why, "ok") && isTRUE(abs(m12$value - 4.2) < 1e-12),
    "F4 [돌연변이 M11·M12] floor/carry_base 검사를 규약만으로 줄이면 처치·창 이탈 칸이 바닥(3칸 생존)·기준선(4.2)으로 샌다 — F1·F3 가 잡는다",
    sprintf("m11=%s m12=%s", paste(m11, collapse = ","), m12$why))

unlink(c(S, S2, S3, LCOPY), recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d · 생략 %d\n", PASS, FAIL, SKIP))
cat(sprintf('{"test":"rf_a_eligibility","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', PASS, FAIL, PASS + FAIL, SKIP))
quit(status = if (FAIL > 0L) 1L else 0L)
