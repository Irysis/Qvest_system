#!/usr/bin/env Rscript
#==============================================================================
# test_rf_a_gate_lineage_flags.R — P0-14(2026-09-25) A 자격 관문 **관문 시점 계보 표식 재도출** 양방향 검사
#
# 사고(구멍): rf_runner_gates.R::rf_a_eligibility ⑤ vintage_flag 는 원장 attempt$vintage_flags 만 봤다 — 표식은 사후에 붙는다.
#   최고 계보 RP_20260917_105807_22632_* 가 전부 selection_basis_full_sample_ic_inherited 표식으로 A 보류인데, 러너를 재개하면
#   이 계보의 새 칸(같은 팩터 집합 carry)은 표식 없이 A 관문을 통과한다. C11 격리(pit_quarantine.json)도 사후 표식(pit_c11)에만 의존했다.
# 수리: rf_lineage_flags.R(술어 정본 — P0-08 derive 와 같은 함수)을 관문 ⑤ 가 수집 시점에 부른다.
#
# 재는 것
#   A  합성 원장 — 선정 기저 승계: 표식 부모 + 같은 집합 carry 새 칸 → 보류 · 손자 → 보류 · as-of 재선정 새 칸 → 통과 ·
#      as-of 루트의 승격 자식(carry 증명 승계) → 통과 · 오염 carry + as-of 자기 선정 → 보류(carry 몫) · 무관 집합 → 통과 ·
#      spec full_sample_ic 규칙 칸 → 자기 표식 보류 · 원장 표식 있는 칸 → 중복 재도출 없음 · 오염 집합 판독 불가·격리 목록 파손 → fail-closed ·
#      선정 기저 필드 없는 규칙 칸 → as-of 미증명(보수 보류)
#   B  합성 — C11 격리: 격리 팩터 · carry 된 정지 arm(pg2) · 격리 원천을 읽는 기저 엔진 · 격리 원천을 읽는 생성 arm 코드 ·
#      기저 측정 표식(base_vintage_flags) → 보류 / 깨끗한 엔진·서술 속 'VIX' → 통과
#   R  실원장 **사본** — 재도출 parity(선정 기저: 재도출 = self∪inherited 표식 · C11: 재도출 = pit_c11 표식) · 22632 계보 새 칸 모사 → 보류 ·
#      표식 없는 계보 새 칸 모사 → 통과
#   X  러너 SPEC 선정 기저 부기(블록 추출 실행) · .spec_sig 서명 불변
#   Q  충실구현 어댑터(R1 · run_paper_replication.R) — 격리 원천을 읽는 엔진 A → 보류 · 깨끗한 엔진 → 발행
#   L  원장 기록 — 러너 claim 을 쥔 프로세스의 rf_mark_vintage_batch 는 거부된다(재진입 불가 실증 → tick 안 기록 불채택) ·
#      idle 계획(rflf_marks_plan) + writer → 신규 기록 · 재실행 멱등 · 보호 투영 불변 · policy/source 'P0-14 derived'
#   P  수리 2판(적대검증 BLOCKING) — P1 집합 단위 면제({FA} 만 as-of 증명 · carry·바닥 {FA,FB} → 보류 / 원소 전부 증명 → 통과) ·
#      P2~P4 검사 공백(as-of 칸의 carry 몫 · n 순서 · 부모 증명 ∩ carry) · P5 부모 증명은 carry 출처 칸까지(source_spec → source_cell · 못 찾으면 보수) ·
#      P6~P7 격자 스냅샷 폴백 칸(실격자 B1 cells) 자기 표식 보류 · 그 승격 자식 보류(S 의 표식 없는 규칙 라벨 칸) · P8 carry 출처 판독 불가(부모 칸·entry
#      원장 부재) = 보류 · X3 러너 폴백 분기 부기(소스 추출 실행) ·
#      Q3~Q7 재도출 입력 판독 불가(spec 부재·파손 · spec·engine_path 없음 · 엔진 부재) = 보류 · P9 L2 전용 오염 집합 · P10 tick 캐시 entries 갱신 ·
#      P11 격리 팩터 id 단독 경로(합성 격리 목록) · Q8 spec 부재 + engine_path 있음 → 보류
#   M  돌연변이 — 재도출 제거(A1·R2 새어 나감) · 술어 사본화(parity red) · as-of 면제 제거 · 계보 재귀 제거 · C11 재도출 제거 · 어댑터 engine_path 누락
#      (본문 텍스트 돌연변이 — 집합 단위 면제·판독 불가 보류·출처 경계·폴백 부기 제거 등 — 는 외부 실행기가 이 검사를 돌려 red 를 잰다)
# 부작용: 쓰기는 tempdir 샌드박스뿐(루트는 읽기 전용 원천 — 전후 md5 대조). 수리 전 코드(rf_lineage_flags.R 부재)에서는 A1·R2·Q2 가 red.
# 실행: QM_ROOT=<루트> Rscript --no-environ 08_Tests/reinforcement/test_rf_a_gate_lineage_flags.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)   # 백슬래시 루트(파이썬 미러 등) — 경로 문자열 속 \U 즉사 방지
cat(sprintf("ROOT(읽기 전용) = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (length(why) && any(nzchar(why))) paste0(" — ", paste(why, collapse = " ")) else "", "\n") }
sk <- function(m, why = "") { SKIP <<- SKIP + 1L; cat("  SKIP", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
emit <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d · 생략 %d\n", PASS, FAIL, SKIP))
  cat(sprintf('{"test":"rf_a_gate_lineage_flags","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', PASS, FAIL, PASS + FAIL, SKIP))
}
TMP <- normalizePath(tempdir(), winslash = "/")
inside <- function(p, q) startsWith(tolower(normalizePath(p, winslash = "/", mustWork = FALSE)),
                                    tolower(paste0(normalizePath(q, winslash = "/", mustWork = FALSE), "/")))
if (inside(TMP, ROOT)) { ng("tempdir 가 루트 안에 있다 — 쓰기 위험(중단)", TMP); emit(); quit(status = 1L) }
# 루트 지문(전후 대조) — 이 검사는 루트에 아무것도 쓰지 않는다
PROD <- file.path(ROOT, c("06_Registry/reinforce_ledger_l1.json", "06_Registry/reinforce_ledger_l2.json", "06_Registry/grade_a_queue.json",
                          "06_Registry/pit_quarantine.json", "06_Registry/a_eligibility_gate.json"))
md5_prod <- function() vapply(PROD, function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent", character(1))
PROD0 <- md5_prod()
LS0 <- sort(list.files(file.path(ROOT, "04_Research/strategies")))

invisible(capture.output(suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"))
  source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"))
  source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")) })))
HAS_LIB <- exists("rflf_gate_flags", mode = "function") && exists("rflf_fids", mode = "function")
cat("\n=== L0. 적재 ===\n")
chk(HAS_LIB, "L0 계보 표식 술어 정본(rf_lineage_flags.R) 적재 — 관문 정본이 source 한다", "수리 전 코드 — 이하 관문 판정은 구판으로 잰다(red 실증)")
lib_or <- function(f, alt = NULL) if (HAS_LIB) f() else alt

# ── 샌드박스 root (설정 사본 · 합성 산출물 · 합성 원장) ─────────────────────────────────────────
S <- file.path(TMP, sprintf("p14_lf_%d", Sys.getpid())); unlink(S, recursive = TRUE, force = TRUE)
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts", "02_Infrastructure/validation", "02_Infrastructure/ops",
            "02_Infrastructure/reinforcement/overlay_arms", "06_Registry", "04_Research/strategies", "stage_artifacts/replication",
            ".cache/rf_parallel", "eng"))
  dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
cp <- function(rel) isTRUE(file.copy(file.path(ROOT, rel), file.path(S, rel), overwrite = TRUE))
okc <- all(vapply(c("02_Infrastructure/worktask/constraint_defaults.json", "02_Infrastructure/contracts/essence_score.R",
                    "06_Registry/a_eligibility_gate.json", "06_Registry/pit_quarantine.json", "02_Infrastructure/validation/pit_quarantine.R",
                    "02_Infrastructure/ops/rf_claim.R", "02_Infrastructure/reinforcement/overlay_arms/pg2_risk_overlay.R",
                    "02_Infrastructure/reinforcement/overlay_arms/pg2_risk_overlay.arm.json"), cp, logical(1)))
if (!okc) { ng("샌드박스 설정 사본 실패"); emit(); quit(status = 1L) }
writeLines(toJSON(list(entries = list()), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_ledger_l2.json"))
CUR <- rf_current_regime(S)$regime
QEN <- new.env(); sys.source(file.path(S, "02_Infrastructure/validation/pit_quarantine.R"), envir = QEN)
QF <- QEN$pitq_factor_ids(S)

mk_art <- function(tag, regime = CUR, start = "2005-02-01") {
  d <- file.path(S, "stage_artifacts/replication", tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  dates <- seq(as.Date(start), as.Date("2026-08-01"), by = "month")
  saveRDS(list(holdings = data.frame(date = dates, ticker = "A005930", weight = 1),
               period_returns = data.frame(date = dates, ret_net = 0.01)), file.path(d, "bt_result.rds"))
  au <- list(status = "OK", essence_grade = "A", selection_type = "sweep", dsr = 0.9, essence = list(dsr = 0.9), n_trials_cumulative = 12L,
             measurement_regime = list(selection_type = "sweep", n_trials_basis = "base1+lineage_measured(excl_inherited)+batch_size",
                                       exec_price = regime, n_trials_cumulative = 12L))
  writeLines(toJSON(au, auto_unbox = TRUE, null = "null"), file.path(d, "authoritative_remeasure.json"))
  d
}
ART_OK <- mk_art("ok")
fz <- function(ids) lapply(ids, function(i) list(kind = "db", id = i))
mk_spec <- function(tag, code, factors, label = code, sb = NULL, overlay = NULL, overlay_cell = list(), extra = list()) {
  p <- file.path(S, ".cache/rf_parallel", sprintf("spec_%s__%s.json", code, tag))
  sp <- c(list(code = code, label = label, factors = fz(factors), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"),
               overlay_cell = overlay_cell), extra)
  if (!is.null(sb)) { sp$selection_basis <- sb; sp$selection_asof <- "2005-01-01" }
  if (!is.null(overlay)) sp$overlay <- overlay
  writeLines(toJSON(sp, auto_unbox = TRUE, null = "null"), p); p
}
mk_att <- function(n, code, spec, art = ART_OK, grade = "A", flags = NULL, idea = NULL, pt = 3.2) {
  a <- list(n = as.integer(n), cell_code = code, grade = grade, artifacts = art, opened_at = "2026-09-26T10:00:00+0900",
            essence = list(cell_code = code, port_t = pt, calmar = 0.7, spec = spec))
  if (!is.null(flags)) a$vintage_flags <- flags
  if (!is.null(idea)) a$idea <- idea
  a
}
SELF <- function(set) list(list(flag = "selection_basis_full_sample_ic", verdict = "consumed", evidence = "p0_08",
                                source = sprintf("p0_08 · B1_1 · 규칙 선정기 라벨 · factors=%s", paste(set, collapse = "+"))))
ent <- function(bid, attempts = list(), parent = NULL, carry = NULL, status = "active", base_flags = NULL) {
  e <- list(base_id = bid, status = status, attempts = attempts)
  if (!is.null(parent)) e$parent <- list(base_id = parent, cell = "B1_1", best_port_t = 3.0)
  if (!is.null(carry)) e$carry <- list(factors = fz(carry), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"), source_cell = "B1_1")
  if (!is.null(base_flags)) e$base_vintage_flags <- base_flags
  e
}
ctx_of <- function(entries, bid, root = S) rf_a_ctx(rf_runner_ctx(root), entries, bid)
elig <- function(entry, att, entries, root = S) rf_a_eligibility(entry, att, NULL, ctx_of(entries, entry$base_id, root))
codes <- function(el) paste(sort(el$codes), collapse = "+")
dflags <- function(el) as.character(unlist(el$facts$derived_flags %||% character(0)))
has_d <- function(el, flag) any(startsWith(dflags(el), paste0(flag, " ")))
held_by <- function(el, flag) !isTRUE(el$eligible) && "vintage_flag" %in% el$codes && has_d(el, flag)

# ── 합성 원장: 표식 부모(T_SRC) · 오염 carry 자식/손자 · as-of 루트/자식 · 무관 · 혼합 ─────────────────────
SRC <- ent("T_SRC", status = "exhausted", attempts = list(
  mk_att(1, "B1_1", mk_spec("SRC", "B1_1", c("FA", "FB"), label = "2팩터 직교(가치+모멘텀)"), grade = "B", flags = SELF(c("FA", "FB"))),
  mk_att(2, "B1_2", mk_spec("SRC", "B1_2", c("FS"), label = "1팩터 직교(품질)"), grade = "C", flags = SELF("FS"))))
CH  <- ent("T_CH", parent = "T_SRC", carry = c("FA", "FB"))
GC  <- ent("T_GC", parent = "T_CH", carry = c("FA", "FB", "FC"))
ASO <- ent("T_ASOF", attempts = list(
  mk_att(1, "B1_1", mk_spec("ASOF", "B1_1", c("FA", "FB"), label = "2팩터 직교(가치+모멘텀)", sb = "asof_ic"), grade = "B")))
ASC <- ent("T_ASOF_CH", parent = "T_ASOF", carry = c("FA", "FB"))
UNR <- ent("T_UNREL")
MIX <- ent("T_MIX", parent = "T_SRC", carry = c("FA", "FB"))
ENTS <- list(SRC, CH, GC, ASO, ASC, UNR, MIX)

cat("\n=== A. 선정 기저 승계 — 합성 원장 ===\n")
a1 <- mk_att(7, "B2_7", mk_spec("CH", "B2_7", c("FA", "FB")))
e1 <- elig(CH, a1, ENTS)
chk(held_by(e1, "selection_basis_full_sample_ic_inherited"),
    "A1 [주입] 표식 부모(자기 선정 {FA,FB}) → carry 로 같은 집합을 실은 새 칸(표식 없음) → 보류 · 재도출 inherited", c(codes(e1), dflags(e1)))
e5 <- elig(GC, mk_att(12, "B3_12", mk_spec("GC", "B3_12", c("FA", "FB", "FC"))), ENTS)
chk(held_by(e5, "selection_basis_full_sample_ic_inherited"), "A5 [주입] 표식 부모의 손자(carry {FA,FB,FC}) 새 칸 → 보류", c(codes(e5), dflags(e5)))
e2a <- elig(ASO, mk_att(2, "B1_2", mk_spec("ASOF", "B1_2", c("FS"), label = "1팩터 직교(품질)", sb = "asof_ic")), ENTS)
chk(isTRUE(e2a$eligible) && !length(dflags(e2a)),
    "A2a [양성] as-of 재선정 새 칸(규칙 선정기 · selection_basis=asof_ic · 오염 집합 {FS} 과 같은 팩터) → 통과", c(codes(e2a), dflags(e2a)))
e2b <- elig(ASO, mk_att(6, "B2_6", mk_spec("ASOF", "B2_6", c("FA", "FB"))), ENTS)
chk(isTRUE(e2b$eligible), "A2b [양성] as-of 루트의 바닥 구성({FA,FB} — 같은 entry 의 as-of 규칙 칸이 골랐다) 위 B2 새 칸 → 통과", c(codes(e2b), dflags(e2b)))
e6 <- elig(ASC, mk_att(6, "B2_6", mk_spec("ASC", "B2_6", c("FA", "FB"))), ENTS)
chk(isTRUE(e6$eligible), "A6 [양성] as-of 루트의 승격 자식(carry {FA,FB} = 부모 as-of 증명 ∩ carry) 새 칸 → 통과(계보 재귀)", c(codes(e6), dflags(e6)))
e7 <- elig(MIX, mk_att(3, "B1_3", mk_spec("MIX", "B1_3", c("FA", "FB", "FD"), label = "3팩터 직교(가치+모멘텀+규모)", sb = "asof_ic")), ENTS)
chk(held_by(e7, "selection_basis_full_sample_ic_inherited"),
    "A7 [주입] 오염 carry {FA,FB} + as-of 자기 선정 {FD} → 보류(as-of 면제는 자기 선정 몫에만 · carry 몫은 그대로 오염)", c(codes(e7), dflags(e7)))
e3 <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6", c("FZ", "FY"))), ENTS)
chk(isTRUE(e3$eligible) && !length(dflags(e3)), "A3 [양성] 무관 집합 {FZ,FY} → 통과 · 재도출 표식 0", c(codes(e3), dflags(e3)))
e8 <- elig(UNR, mk_att(1, "B1_1", mk_spec("UNR", "B1_1", c("FQ"), label = "1팩터 직교(규모)", sb = "full_sample_ic")), ENTS)
chk(held_by(e8, "selection_basis_full_sample_ic"), "A8 [주입] 규칙 선정 칸 spec selection_basis=full_sample_ic → 자기 표식 재도출 보류", c(codes(e8), dflags(e8)))
a9 <- mk_att(8, "B2_8", mk_spec("CH", "B2_8", c("FA", "FB")),
             flags = list(list(flag = "selection_basis_full_sample_ic_inherited", verdict = "consumed", evidence = "p0_08", source = "p0_08")))
e9 <- elig(CH, a9, ENTS)
chk(!isTRUE(e9$eligible) && "vintage_flag" %in% e9$codes && !length(dflags(e9)),
    "A9 원장 표식이 이미 있는 칸 → 보류(원장 표식) · 같은 flag 재도출 중복 0", c(codes(e9), dflags(e9)))
e12 <- elig(UNR, mk_att(2, "B1_2", mk_spec("UNR", "B1_2", c("FS", "FW"), label = "2팩터 직교(품질+x)")), ENTS)
chk(held_by(e12, "selection_basis_full_sample_ic"),
    "A12 선정 기저 필드 없는 규칙 칸(구 SPEC · 격자 스냅샷 폴백) → as-of 미증명 = 자기 표식 보류(수리 2판 ③ — 구판은 오염 포함일 때만 승계 보류)",
    c(codes(e12), dflags(e12)))
# A10 오염 집합 판독 불가 → fail-closed / source 폴백
BAD <- ent("T_BAD", status = "exhausted", attempts = list(
  mk_att(1, "B1_1", file.path(S, "nope_spec.json"), grade = "C",
         flags = list(list(flag = "selection_basis_full_sample_ic", verdict = "consumed", evidence = "p0_08", source = "p0_08 · 스펙 소실"))),
  mk_att(2, "B1_2", file.path(S, "nope_spec2.json"), grade = "C", flags = SELF(c("FP1", "FP2")))))
e10 <- elig(UNR, mk_att(5, "B2_5", mk_spec("UNR", "B2_5", c("FZ"))), c(ENTS, list(BAD)))
chk(!isTRUE(e10$eligible) && any(grepl("오염 집합 판독 불가", unlist(e10$detail))),
    "A10 [주입] 자기 표식 칸 스펙·source 모두 판독 불가 → 오염 집합 모름 → 보류(fail-closed)", c(codes(e10), unlist(e10$detail)))
BAD2 <- BAD; BAD2$attempts <- BAD2$attempts[2]
e10b <- elig(UNR, mk_att(5, "B2_5", mk_spec("UNR", "B2_5b", c("FP1", "FP2", "FX"))), c(ENTS, list(BAD2)))
chk(held_by(e10b, "selection_basis_full_sample_ic_inherited"), "A10b 스펙 소실 자기 표식 칸 → 표식 source 'factors=' 폴백으로 집합 복원 → 보류",
    c(codes(e10b), dflags(e10b)))
S3 <- file.path(TMP, sprintf("p14_lf_badq_%d", Sys.getpid())); unlink(S3, recursive = TRUE)
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts", "02_Infrastructure/validation", "06_Registry"))
  dir.create(file.path(S3, d), recursive = TRUE, showWarnings = FALSE)
for (r in c("02_Infrastructure/worktask/constraint_defaults.json", "02_Infrastructure/contracts/essence_score.R", "06_Registry/a_eligibility_gate.json",
            "02_Infrastructure/validation/pit_quarantine.R", "06_Registry/reinforce_ledger_l2.json"))
  file.copy(file.path(S, r), file.path(S3, r), overwrite = TRUE)
writeLines("{ broken", file.path(S3, "06_Registry/pit_quarantine.json"))
e11 <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6c", c("FZ"))), ENTS, root = S3)
chk(!isTRUE(e11$eligible) && "vintage_flag" %in% e11$codes && any(grepl("재도출 실패", unlist(e11$detail))),
    "A11 [주입] 격리 목록 파손 → 재도출 실패 → 보류(fail-closed · 조용한 해제 없음)", c(codes(e11), unlist(e11$detail)))

cat("\n=== B. C11 격리 — 합성 ===\n")
PG2 <- list(kind = "pg2_risk_overlay", arm_id = "pg2_risk_overlay_v1")
if (length(QF)) {
  eb5 <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6q", c("FZ", QF[1]))), ENTS)
  chk(held_by(eb5, "pit_c11"), sprintf("B5 [주입] 격리 팩터(%s — pit_quarantine.json 에서 재도출) carry/바닥 → 보류 pit_c11", QF[1]), c(codes(eb5), dflags(eb5)))
} else sk("B5 격리 팩터", "pit_quarantine.json 효력 팩터 0")
eb1 <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6p", c("FZ"), overlay = PG2, overlay_cell = list())), ENTS)
chk(held_by(eb1, "pit_c11"), "B1 [주입] carry/바닥으로 실린 정지 arm(pg2_risk_overlay_v1 · 등재 관문 밖 승계) → 보류 pit_c11", c(codes(eb1), dflags(eb1)))
writeLines(c("FACTORS <- function() {", "  m <- load_macro_regime()   # 격리 원천", "}"), file.path(S, "eng/eng_bad.R"))
writeLines(c("FACTORS <- function() NULL"), file.path(S, "eng/eng_ok.R"))
eb2 <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6e", c("FZ"), extra = list(base_signal = list(kind = "engine", path = file.path(S, "eng/eng_bad.R"))))), ENTS)
chk(held_by(eb2, "pit_c11") && any(grepl("engine:eng_bad.R", dflags(eb2), fixed = TRUE)),
    "B2 [주입] 격리 원천(macro_regime)을 읽는 기저 엔진 → 보류 pit_c11(engine 출처)", c(codes(eb2), dflags(eb2)))
eb2p <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6f", c("FZ"), extra = list(base_signal = list(kind = "engine", path = file.path(S, "eng/eng_ok.R"))))), ENTS)
chk(isTRUE(eb2p$eligible), "B2p [양성] 깨끗한 기저 엔진 → 통과", c(codes(eb2p), dflags(eb2p)))
writeLines(c("overlay_expo_gen_bad <- function(ctx) {", "  x <- arrow::read_parquet('.cache/unified_regime_signal_daily.parquet')", "}"),
           file.path(S, "02_Infrastructure/reinforcement/overlay_arms/gen_bad.R"))
eb3 <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6g", c("FZ"), overlay = list(kind = "gen_bad", arm_id = "gen_bad_v1"), overlay_cell = list())), ENTS)
chk(held_by(eb3, "pit_c11") && any(grepl("arm:gen_bad.R", dflags(eb3), fixed = TRUE)),
    "B3 [주입] 격리 원천을 읽는 생성 arm 코드(승계 층) → 보류 pit_c11(arm 출처)", c(codes(eb3), dflags(eb3)))
UNRB <- ent("T_UNREL", base_flags = list(list(flag = "pit_c11", verdict = "consumed", evidence = "x", source = "x")))
eb4 <- elig(UNRB, mk_att(6, "B2_6", mk_spec("UNRB", "B2_6h", c("FZ"))), list(UNRB))
chk(held_by(eb4, "pit_c11"), "B4 [주입] 기저 측정 격리 표식(entry base_vintage_flags pit_c11) → 새 칸 보류", c(codes(eb4), dflags(eb4)))
eb6 <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6i", c("FZ"), extra = list(basis = "VIX 기간구조 서술 · 공포지수"))), ENTS)
chk(isTRUE(eb6$eligible), "B6 [양성] 서술 속 'VIX'(격리 원천 이름 아님) → 통과", c(codes(eb6), dflags(eb6)))

cat("\n=== R. 실원장 사본 — 재도출 parity · 22632 새 칸 · 표식 없는 계보 ===\n")
LC <- file.path(TMP, sprintf("p14_lf_ledger_%d", Sys.getpid())); dir.create(file.path(LC, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(LC, "02_Infrastructure/validation"), recursive = TRUE, showWarnings = FALSE)
for (r in c("06_Registry/reinforce_ledger_l1.json", "06_Registry/reinforce_ledger_l2.json", "06_Registry/pit_quarantine.json",
            "02_Infrastructure/validation/pit_quarantine.R"))
  if (file.exists(file.path(ROOT, r))) file.copy(file.path(ROOT, r), file.path(LC, r), overwrite = TRUE)
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts")) dir.create(file.path(LC, d), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(S, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(LC, "02_Infrastructure/worktask"), overwrite = TRUE))
invisible(file.copy(file.path(S, "02_Infrastructure/contracts/essence_score.R"), file.path(LC, "02_Infrastructure/contracts"), overwrite = TRUE))
invisible(file.copy(file.path(S, "06_Registry/a_eligibility_gate.json"), file.path(LC, "06_Registry"), overwrite = TRUE))
if (!file.exists(file.path(LC, "06_Registry/reinforce_ledger_l1.json"))) {
  sk("R 절 전체", "원장 L1 부재(루트)"); RL <- NULL
} else RL <- fromJSON(file.path(LC, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
RL2 <- if (file.exists(file.path(LC, "06_Registry/reinforce_ledger_l2.json"))) fromJSON(file.path(LC, "06_Registry/reinforce_ledger_l2.json"), simplifyVector = FALSE) else list(entries = list())
# 검사 쪽 독립 재구현(판정 함수를 쓰지 않는다) — 표식·spec 판독만
t_fl <- function(a) vapply(a$vintage_flags %||% list(), function(z) as.character(z$flag %||% ""), "")
t_spec <- function(a) { p <- as.character(a[["essence"]]$spec %||% ""); if (length(p) == 1L && nzchar(p) && file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL }
t_meas <- function(a) { v <- suppressWarnings(as.numeric(a[["essence"]]$port_t %||% NA)); length(v) == 1L && is.finite(v) }
t_fids <- function(s) { if (is.null(s)) return(character(0))
  x <- c(s$factors %||% list(), if (is.list(s$factor2) && !identical(s$factor2$kind, "none")) list(s$factor2), if (is.list(s$factor3) && !identical(s$factor3$kind, "none")) list(s$factor3))
  sort(unique(unlist(lapply(x, function(f) if (is.list(f) && identical(as.character(f$kind %||% "db"), "db")) as.character(f$id) else NULL)))) }
parity <- function(inherits_fun = NULL) {
  ctxR <- list(root = LC, cache = new.env(parent = emptyenv()), entries = RL$entries)
  out <- list()
  for (ly in 1:2) for (e in (if (ly == 1L) RL else RL2)$entries %||% list()) for (a in e$attempts %||% list()) {
    if (!t_meas(a)) next
    m <- t_fl(a); a0 <- a; a0$vintage_flags <- NULL
    g <- rflf_gate_flags(e, a0, .rflf_spec_of(a, LC, ctxR$cache), ctxR)
    d <- vapply(g$flags, function(z) z$flag, "")
    out[[length(out) + 1L]] <- data.table(b = e$base_id, n = a$n, m_sel = any(m %in% c("selection_basis_full_sample_ic", "selection_basis_full_sample_ic_inherited")),
                                          m_b7 = "treatment_misspecified" %in% m, m_c11 = "pit_c11" %in% m,
                                          d_sel = any(startsWith(d, "selection_basis")), d_c11 = "pit_c11" %in% d)
  }
  rbindlist(out)
}
if (!is.null(RL) && HAS_LIB) {
  PR <- parity()
  sel_mark_only <- PR[m_sel & !d_sel, .N]; sel_d_only <- PR[!m_sel & d_sel]; c11_mis <- PR[m_c11 != d_c11, .N]
  cat(sprintf("       (측정 칸 %d · 선정 표식 %d · 재도출 %d · C11 표식 %d · 재도출 %d)\n", nrow(PR), PR[m_sel == TRUE, .N], PR[d_sel == TRUE, .N],
              PR[m_c11 == TRUE, .N], PR[d_c11 == TRUE, .N]))
  chk(nrow(PR) > 0L && PR[m_sel == TRUE, .N] > 0L && sel_mark_only == 0L && all(sel_d_only$m_b7),
      "R1 선정 기저 parity — 재도출(원장 표식 제거 후) ⊇ 원장 self∪inherited 표식 · 재도출만 = treatment_misspecified 표식 칸(derive 가 한 칸 한 표식)",
      sprintf("표식만 %d · 재도출만(비 B7) %d", sel_mark_only, sel_d_only[m_b7 == FALSE, .N]))
  chk(c11_mis == 0L && PR[m_c11 == TRUE, .N] > 0L, "R1b C11 parity — 재도출 pit_c11 = 원장 pit_c11 표식(양쪽 불일치 0)", sprintf("불일치 %d", c11_mis))
} else if (!HAS_LIB) ng("R1 parity", "수리 전 코드 — 재도출 술어 없음")
# R2 — 22632 계보 새 칸 모사
if (!is.null(RL)) {
  cand <- Filter(function(e) grepl("_22632_", e$base_id %||% "") && !is.null(e$carry) && length(e$carry$factors), RL$entries)
  depth <- function(e) { k <- 0L; p <- e$parent$base_id %||% ""; while (nzchar(p) && k < 20L) { k <- k + 1L
    pe <- Filter(function(x) identical(x$base_id, p), RL$entries); p <- if (length(pe)) pe[[1]]$parent$base_id %||% "" else "" }; k }
  if (!length(cand)) sk("R2 22632 새 칸", "원장에 22632 승격 계보 없음") else {
    E22 <- cand[[which.max(vapply(cand, depth, integer(1)))]]
    nmax <- max(vapply(E22$attempts %||% list(), function(a) as.integer(a$n %||% 0L), integer(1)), 0L)
    cf <- vapply(E22$carry$factors, function(f) as.character(f$id), "")
    a22 <- mk_att(nmax + 1L, "B2_99", mk_spec("R22632", "B2_99", cf))
    e22 <- rf_a_eligibility(E22, a22, NULL, rf_a_ctx(rf_runner_ctx(LC), RL$entries, E22$base_id))
    chk(!isTRUE(e22$eligible) && "vintage_flag" %in% e22$codes && has_d(e22, "selection_basis_full_sample_ic_inherited"),
        sprintf("R2 [실원장] %s 새 칸(carry %s · 표식 없음) → 보류 · 재도출 inherited", E22$base_id, paste(cf, collapse = "+")),
        c(codes(e22), dflags(e22)))
  }
  # R3 — 표식 없는 계보: 독립 재구현으로 오염 집합과 무관한 entry 를 고른다
  Sind <- list(); for (L in list(RL, RL2)) for (e in L$entries %||% list()) for (a in e$attempts %||% list())
    if ("selection_basis_full_sample_ic" %in% t_fl(a)) { f <- t_fids(t_spec(a)); if (length(f)) Sind[[length(Sind) + 1L]] <- f }
  clean_e <- NULL
  for (e in RL$entries) {
    if (any(vapply(e$attempts %||% list(), function(a) any(nzchar(t_fl(a))), logical(1)))) next
    if (length(e$base_vintage_flags %||% list())) next
    last <- Filter(function(a) t_meas(a) && !is.null(t_spec(a)), e$attempts %||% list())
    if (!length(last)) next
    sp0 <- t_spec(last[[length(last)]]); f0 <- t_fids(sp0)
    if (!length(f0) || any(vapply(Sind, function(s) all(s %in% f0), logical(1)))) next
    if (length(sp0[["overlay"]]) || !is.null(sp0[["base_signal"]]) && !identical(sp0$base_signal$kind, "mom_12_1") && !file.exists(as.character(sp0$base_signal$path %||% ""))) next
    clean_e <- e; break
  }
  if (is.null(clean_e)) sk("R3 표식 없는 계보", "조건 맞는 entry 없음") else {
    last <- Filter(function(a) t_meas(a) && !is.null(t_spec(a)), clean_e$attempts)
    sp0 <- t_spec(last[[length(last)]])
    nmax <- max(vapply(clean_e$attempts, function(a) as.integer(a$n %||% 0L), integer(1)))
    a3 <- mk_att(nmax + 1L, "B2_98", mk_spec("R3", "B2_98", t_fids(sp0), extra = list(base_signal = sp0$base_signal)))
    e3r <- rf_a_eligibility(clean_e, a3, NULL, rf_a_ctx(rf_runner_ctx(LC), RL$entries, clean_e$base_id))
    chk(!length(dflags(e3r)) && !("vintage_flag" %in% e3r$codes),
        sprintf("R3 [양성·실원장] 표식 없는 계보 %s 새 칸(%s) → 재도출 표식 0 · vintage_flag 보류 없음", clean_e$base_id, paste(t_fids(sp0), collapse = "+")),
        c(codes(e3r), dflags(e3r)))
  }
}

cat("\n=== X. 러너 SPEC 선정 기저 부기 · 서명 불변 ===\n")
RUN <- sub("\r$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE, encoding = "UTF-8"))
i0 <- grep("P0-14(2026-09-25) 선정 기저 부기", RUN, fixed = TRUE)
if (length(i0) != 1L) ng("X1 러너 SPEC 선정 기저 부기 블록(앵커 1개)", sprintf("앵커 %d개 — 수리 전 러너", length(i0))) else {
  j0 <- i0 + which(grepl("^  if \\(!is.null\\(CELL\\[\\[\"selection_basis\"\\]\\]\\)\\) \\{", RUN[(i0 + 1L):(i0 + 6L)]))[1]
  j1 <- j0 + which(RUN[(j0 + 1L):(j0 + 4L)] == "  }")[1]
  blk <- parse(text = paste(RUN[j0:j1], collapse = "\n"), keep.source = FALSE)
  xe <- new.env(); xe$SPEC <- list(code = "B1_1", factors = fz("FA")); xe$CELL <- list(code = "B1_1", selection_basis = "asof_ic", selection_asof = "2005-01-01")
  eval(blk, xe)
  ye <- new.env(); ye$SPEC <- list(code = "B1_2", factors = fz("FA")); ye$CELL <- list(code = "B1_2", label = "설계 칸")
  eval(blk, ye)
  chk(identical(xe$SPEC$selection_basis, "asof_ic") && identical(xe$SPEC$selection_asof, "2005-01-01") && !("selection_basis" %in% names(ye$SPEC)),
      "X1 러너 블록(소스 추출 실행) — 규칙 선정 칸만 selection_basis·selection_asof 를 싣고, 필드 없는 칸은 키를 만들지 않는다")
}
sp_real <- NULL
if (!is.null(RL)) for (e in rev(RL$entries)) { for (a in rev(e$attempts %||% list())) { s <- t_spec(a); if (!is.null(s) && length(s$factors)) { sp_real <- s; break } }
  if (!is.null(sp_real)) break }
if (is.null(sp_real)) sp_real <- list(factors = fz(c("FA", "FB")), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"))
sp_tag <- sp_real; sp_tag$selection_basis <- "asof_ic"; sp_tag$selection_asof <- "2005-01-01"
chk(identical(.spec_sig(sp_real), .spec_sig(sp_tag)), "X2 .spec_sig 불변 — 선정 기저 부기 필드는 서명에 안 들어간다(실원장 스펙 1칸)")

cat("\n=== Q. 충실구현 어댑터(R1) — 격리 원천을 읽는 엔진 ===\n")
RP_F <- file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")
RP_TXT <- paste(readLines(RP_F, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
WANT <- c(".RP_JR_LEGACY", ".RP_JR_ELIGIBLE", ".RP_JR_HELD", ".rp_is_cell_run", ".rp_gate_env", ".rp_a_gate_inputs", ".rp_gate_err_verdict", ".rp_a_route")
load_rp <- function(txt) { ex <- parse(text = txt, keep.source = FALSE, encoding = "UTF-8"); env <- new.env(parent = globalenv())
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) && as.character(e[[2]]) %in% WANT) eval(e, envir = env)
  env }
RPE <- tryCatch(load_rp(RP_TXT), error = function(e) NULL)
if (is.null(RPE) || length(setdiff(WANT, ls(RPE, all.names = TRUE)))) {
  sk("Q 절 전체", "run_paper_replication.R 에 P0-13 어댑터 정의 없음(R1 미배포 루트)")
} else {
  SQ <- file.path(TMP, sprintf("p14_lf_rq_%d", Sys.getpid())); unlink(SQ, recursive = TRUE)
  for (r in c("02_Infrastructure/reinforcement/rf_runner_gates.R", "02_Infrastructure/reinforcement/rf_spec_sig.R", "02_Infrastructure/reinforcement/rf_block_design.R",
              "02_Infrastructure/reinforcement/reinforce_ledger.R", "02_Infrastructure/reinforcement/rf_lineage_flags.R", "02_Infrastructure/contracts/essence_score.R",
              "02_Infrastructure/reinforcement/rf_spec_axes.R",   # ★B4-SIX-AXIS(2026-09-26) 관문 정본이 축 등록부를 적재한다
              "02_Infrastructure/worktask/constraint_defaults.json", "06_Registry/a_eligibility_gate.json", "06_Registry/pit_quarantine.json",
              "02_Infrastructure/validation/pit_quarantine.R")) {
    dir.create(dirname(file.path(SQ, r)), recursive = TRUE, showWarnings = FALSE)
    if (file.exists(file.path(ROOT, r))) file.copy(file.path(ROOT, r), file.path(SQ, r), overwrite = TRUE)
  }
  gj <- fromJSON(file.path(SQ, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)
  RQ <- as.character(gj$holds$accounting_fail[["replication_required_selection_type"]] %||% "")
  CFG <- fromJSON(file.path(SQ, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = TRUE)
  ANCHOR <- as.Date(CFG[["diagnostics"]][["window_anchor_date"]])
  mk_rart <- function(tag) {
    d <- file.path(SQ, "stage_artifacts", "replication", tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
    au <- list(status = "OK", strategy_id = paste0("RP_T_", tag), essence_grade = "A", metric_type = "backtested", selection_type = RQ,
               n_trials_cumulative = 1L, dsr = NULL, essence = list(dsr = NULL, cagr = 0.2, calmar = 0.9),
               measurement_regime = list(selection_type = RQ, n_trials_cumulative = 1L, exec_price = CUR, exec_price_basis = "argument", cost_model_version = "synthetic"))
    write(toJSON(au, auto_unbox = TRUE, null = "null", pretty = TRUE), file.path(d, "authoritative_remeasure.json"))
    dates <- seq(ANCHOR, by = "month", length.out = 24L)
    saveRDS(list(holdings = data.table(date = dates, ticker = "A000001", weight = 1), period_returns = data.table(date = dates, ret_net = rep(0.01, 24L))),
            file.path(d, "bt_result.rds"))
    d
  }
  dir.create(file.path(SQ, "paper"), showWarnings = FALSE)
  writeLines("FACTORS <- NULL  # 논문 신호", file.path(SQ, "paper/engine_ok.R"))
  writeLines(c("FACTORS <- function() {", "  r <- arrow::read_parquet(file.path(CACHE_DIR, 'unified_regime_signal_daily.parquet'))  # 격리 원천", "}"), file.path(SQ, "paper/engine_bad.R"))
  qroute <- function(R, d, eng) { gx <- R$.rp_gate_env(SQ)
    R$.rp_a_route(d, grade = "A", strategy_id = basename(d), engine_path = eng, cell = FALSE,
                  gate = if (is.environment(gx$env)) gx$env$rf_a_eligibility else NULL, gx = gx$env, root = SQ, gate_err = gx$err) }
  q1 <- qroute(RPE, mk_rart("q_ok"), file.path(SQ, "paper/engine_ok.R"))
  chk(identical(q1$action, "publish") && isTRUE(q1$eligible), "Q1 [양성] 깨끗한 논문 엔진 A → 관문 통과 → judge_request.eligible.json", paste(q1$codes, collapse = "+"))
  q2 <- qroute(RPE, mk_rart("q_bad"), file.path(SQ, "paper/engine_bad.R"))
  qd <- as.character(unlist(q2$verdict$facts$derived_flags %||% character(0)))
  chk(identical(q2$action, "hold") && "vintage_flag" %in% q2$codes && any(startsWith(qd, "pit_c11 ")) &&
        file.exists(file.path(SQ, "stage_artifacts/replication/q_bad", RPE$.RP_JR_HELD)),
      "Q2 [주입] 격리 원천(unified_regime_signal)을 읽는 논문 엔진 A → 보류 pit_c11(재도출) · judge_request.held.json · 발행 없음(R1 남은 위험 3)",
      c(q2$action, paste(q2$codes, collapse = "+"), qd))
  # 돌연변이 M6 — 어댑터가 engine_path 를 싣지 않는 구판(R1 스테이지 판)으로 되돌리면: 수리 1판에서는 격리 엔진 A 가 발행으로 샜다(Q2 가 잡았다).
  #   수리 2판 ④ 이후에는 관문이 'spec·engine_path 모두 없음 = 재도출 대상 불명' 으로 보류한다 — 새지 않고 닫힌다. 대신 깨끗한 엔진도 보류돼
  #   Q1(양성 대조)이 red 가 된다 = 돌연변이는 여전히 검출된다(Q1 이 잡는다 · 조용한 발행 없음).
  mtxt <- sub(", engine_path = engine_path)", ")", RP_TXT, fixed = TRUE)
  if (identical(mtxt, RP_TXT)) ng("M6 돌연변이 적용(어댑터 engine_path 인자 제거)", "치환 대상 없음 — 수리 전 어댑터") else {
    RPM <- load_rp(mtxt)
    q1m <- qroute(RPM, mk_rart("q_ok_m"), file.path(SQ, "paper/engine_ok.R"))
    q2m <- qroute(RPM, mk_rart("q_bad_m"), file.path(SQ, "paper/engine_bad.R"))
    um <- function(q) any(grepl("재도출 입력 판독 불가", unlist(q$verdict$detail), fixed = TRUE))
    chk(identical(q1m$action, "hold") && um(q1m) && identical(q2m$action, "hold"),
        "M6 [돌연변이] 어댑터 engine_path 누락 → 격리 엔진도 깨끗한 엔진도 보류(재도출 입력 판독 불가 · fail-closed) — 발행 누출 없음 · Q1 이 잡는다",
        c(q1m$action, q2m$action, paste(unlist(q1m$verdict$detail), collapse = " | ")))
  }
}

cat("\n=== L. 원장 기록 — tick 안 쓰기 불가 실증 · idle 계획 + writer 멱등 ===\n")
if (!HAS_LIB) ng("L 절", "수리 전 코드 — rflf_marks_plan 없음") else {
  SL <- file.path(TMP, sprintf("p14_lf_rec_%d", Sys.getpid())); unlink(SL, recursive = TRUE)
  for (d in c("06_Registry", ".cache", "02_Infrastructure/ops", "02_Infrastructure/validation")) dir.create(file.path(SL, d), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(S, "02_Infrastructure/ops/rf_claim.R"), file.path(SL, "02_Infrastructure/ops"), overwrite = TRUE)
  file.copy(file.path(S, "02_Infrastructure/validation/pit_quarantine.R"), file.path(SL, "02_Infrastructure/validation"), overwrite = TRUE)
  file.copy(file.path(S, "06_Registry/pit_quarantine.json"), file.path(SL, "06_Registry"), overwrite = TRUE)
  CHm <- CH; CHm$attempts <- list(mk_att(7, "B2_7", mk_spec("CH", "B2_7", c("FA", "FB")), grade = "B"))
  led <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 35L, entries = list(SRC, CHm, UNR), last_updated = "2026-09-26T00:00:00+0900")
  writeLines(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(SL, "06_Registry/reinforce_ledger_l1.json"))
  writeLines(toJSON(list(entries = list()), auto_unbox = TRUE), file.path(SL, "06_Registry/reinforce_ledger_l2.json"))
  LP <- file.path(SL, "06_Registry/reinforce_ledger_l1.json"); md0 <- unname(tools::md5sum(LP))
  CLM <- file.path(SL, ".cache/reinforce_auto.claim")
  plan <- rflf_marks_plan(1L, root = SL)
  chk(length(plan) == 1L && identical(plan[[1]]$flag, "selection_basis_full_sample_ic_inherited") && identical(plan[[1]]$attempt_key, "7") &&
        startsWith(plan[[1]]$source, "P0-14 derived"), "L0 idle 계획 — 표식 없는 새 칸(T_CH n=7) 1건 · source 'P0-14 derived'",
      paste(vapply(plan, function(m) paste(m$base_id, m$attempt_key, m$flag), ""), collapse = " ; "))
  CL <- new.env(); sys.source(file.path(SL, "02_Infrastructure/ops/rf_claim.R"), envir = CL)
  ac <- CL$rf_claim_acquire(CLM, stale_hours = 6)
  rj <- tryCatch({ rf_mark_vintage_batch(1L, plan, root = SL, claim = CLM, wait_s = 2, poll_s = 1, policy = RFLF_POLICY); "written" },
                 error = function(e) conditionMessage(e))
  CL$rf_claim_release(CLM)
  chk(isTRUE(ac$ok) && grepl("claim", rj) && !identical(rj, "written") && identical(unname(tools::md5sum(LP)), md0),
      "L1 러너 claim 을 쥔 같은 프로세스의 rf_mark_vintage_batch → 거부(재진입 없음 · 원장 무변경) — tick 안 기록은 불채택 근거", substr(rj, 1, 160))
  r1 <- rf_mark_vintage_batch(1L, plan, root = SL, claim = CLM, wait_s = 5, poll_s = 1, policy = RFLF_POLICY)
  LB <- fromJSON(LP, simplifyVector = FALSE)
  rec <- Filter(function(z) identical(z$flag, "selection_basis_full_sample_ic_inherited"), LB$entries[[2]]$attempts[[1]]$vintage_flags %||% list())
  chk(identical(r1$n_new, 1L) && length(rec) == 1L && identical(rec[[1]]$policy, RFLF_POLICY) && startsWith(rec[[1]]$source, "P0-14 derived") &&
        identical(.rf_vintage_protected(LB), .rf_vintage_protected(fromJSON(toJSON(led, auto_unbox = TRUE, null = "null", na = "null", digits = 6), simplifyVector = FALSE))),
      "L2 idle 기록(writer rf_mark_vintage_batch 단일) — 신규 1 · policy=P0-14 derived · 보호 투영(표식 밖) 불변", sprintf("n_new=%s", r1$n_new))
  r2 <- rf_mark_vintage_batch(1L, plan, root = SL, claim = CLM, wait_s = 5, poll_s = 1, policy = RFLF_POLICY)
  plan2 <- rflf_marks_plan(1L, root = SL)
  chk(identical(r2$n_new, 0L) && identical(r2$n_already, 1L) && !length(plan2) && !isTRUE(r2$written),
      "L3 멱등 — 같은 표식 재기록 0 · 재계획 0(원장 표식이 생기면 재도출은 빈 곳만)", sprintf("n_new=%s n_already=%s plan2=%d", r2$n_new, r2$n_already, length(plan2)))
}

cat("\n=== P. 수리 2판 — 적대검증 BLOCKING(PIT B1·B2 · 시스템 1·2) · 검사 공백(MU1·2·3·7·10) · C9 캐시 ===\n")
ent2 <- function(bid, attempts = list(), parent = NULL, carry = NULL, source_cell = "B1_1", source_spec = NULL, status = "active") {
  e <- ent(bid, attempts = attempts, parent = parent, carry = carry, status = status)
  if (!is.null(carry)) { e$carry$source_cell <- source_cell; if (!is.null(source_spec)) e$carry$source_spec <- source_spec }
  if (!is.null(parent)) e$parent$cell <- source_cell
  e
}
vfhold <- function(el) !isTRUE(el$eligible) && "vintage_flag" %in% el$codes
# ① 집합 단위 면제 — 오염 {FA,FB} 의 원소 하나({FA})만 as-of 로 증명돼도 구판은 집합 전체를 면제했다(적대검증 시스템 P2a/P2b)
PR0 <- ent2("P_R0", status = "exhausted", attempts = list(
  mk_att(1, "B1_1", mk_spec("PR0", "B1_1", c("FA"), label = "1팩터 직교(가치)", sb = "asof_ic"), grade = "C"),
  mk_att(2, "B1_2", mk_spec("PR0", "B1_2", c("FA", "FB"), label = "2팩터 직교(가치+모멘텀)"), grade = "B", flags = SELF(c("FA", "FB")))))
PC0 <- ent2("P_C0", parent = "P_R0", carry = c("FA", "FB"), source_cell = "B1_2")
p1a <- elig(PC0, mk_att(7, "B2_7", mk_spec("PC0", "B2_7", c("FA", "FB"))), c(ENTS, list(PR0, PC0)))
chk(held_by(p1a, "selection_basis_full_sample_ic_inherited"),
    "P1a [주입] 부모 계보가 {FA} 만 as-of 증명 · carry = 전표본 {FA,FB} → 자식 새 칸 보류(집합 단위 면제 — 구판 통과)", c(codes(p1a), dflags(p1a)))
PW <- ent2("P_W", attempts = PR0$attempts)
p1b <- elig(PW, mk_att(8, "B2_8", mk_spec("PW", "B2_8", c("FA", "FB"))), c(ENTS, list(PW)))
chk(held_by(p1b, "selection_basis_full_sample_ic_inherited"),
    "P1b [주입] 같은 entry — {FA} as-of 칸 + 전표본 {FA,FB} 바닥 위 B2 새 칸 → 보류(구판 통과)", c(codes(p1b), dflags(p1b)))
PW2 <- ent2("P_W2", attempts = list(mk_att(1, "B1_1", mk_spec("PW2", "B1_1", c("FA"), label = "1팩터 직교(가치)", sb = "asof_ic"), grade = "C"),
                                     mk_att(2, "B1_2", mk_spec("PW2", "B1_2", c("FB"), label = "1팩터 직교(모멘텀)", sb = "asof_ic"), grade = "C")))
p1c <- elig(PW2, mk_att(21, "B4_21", mk_spec("PW2", "B4_21", c("FA", "FB"))), c(ENTS, list(PW2)))
chk(isTRUE(p1c$eligible) && !length(dflags(p1c)),
    "P1c [양성] 원소 전부({FA}·{FB})가 각각 as-of 증명 → 결합 칸 {FA,FB} 는 오염 집합 {FA,FB} 면제(측정 결합은 전표본 IC 선정이 아니다)", c(codes(p1c), dflags(p1c)))
# MU1 — entry 안 as-of 칸의 carry 몫은 증명이 아니다
MX2 <- ent2("P_MX2", parent = "T_SRC", carry = c("FA", "FB"), attempts = list(
  mk_att(3, "B1_3", mk_spec("MX2", "B1_3", c("FA", "FB", "FD"), label = "3팩터 직교(가치+모멘텀+규모)", sb = "asof_ic"), grade = "B")))
p2 <- elig(MX2, mk_att(6, "B2_6", mk_spec("MX2", "B2_6", c("FA", "FB", "FD"))), c(ENTS, list(MX2)))
chk(held_by(p2, "selection_basis_full_sample_ic_inherited"),
    "P2 [주입·MU1] 오염 carry {FA,FB} 위 as-of 규칙 칸(n=3 · {FA,FB,FD})의 바닥 B2 새 칸 → 보류(as-of 칸의 carry 몫은 증명 아님)", c(codes(p2), dflags(p2)))
# MU2 — 뒤(n 큰) as-of 칸은 앞 칸의 증명이 아니다(재평가 경로: 보류 A 가 나중 칸 측정 뒤 다시 평가된다)
OD <- ent2("P_OD", attempts = list(mk_att(10, "B1_10", mk_spec("OD", "B1_10", c("FA", "FB"), label = "2팩터 직교(가치+모멘텀)", sb = "asof_ic"), grade = "B")))
p3 <- elig(OD, mk_att(7, "B2_7", mk_spec("OD", "B2_7", c("FA", "FB"))), c(ENTS, list(OD)))
p3p <- elig(OD, mk_att(11, "B2_11", mk_spec("OD", "B2_11", c("FA", "FB"))), c(ENTS, list(OD)))
chk(held_by(p3, "selection_basis_full_sample_ic_inherited") && isTRUE(p3p$eligible),
    "P3 [주입·MU2] n=7 칸은 n=10 as-of 칸의 증명을 못 받는다 → 보류 · 대조 n=11 칸 → 통과", c(codes(p3), codes(p3p)))
# MU3 — 부모 증명은 carry 와의 교집합만
PP <- ent2("P_PP", status = "exhausted", attempts = list(
  mk_att(1, "B1_1", mk_spec("PP", "B1_1", c("FA", "FB"), label = "2팩터 직교(가치+모멘텀)", sb = "asof_ic"), grade = "B"),
  mk_att(2, "B1_2", mk_spec("PP", "B1_2", c("FA"), label = "1팩터 직교(가치)", sb = "asof_ic"), grade = "B")))
PPC <- ent2("P_PPC", parent = "P_PP", carry = c("FA"), source_cell = "B1_2")
p4 <- elig(PPC, mk_att(3, "B1_3", mk_spec("PPC", "B1_3", c("FA", "FB"), label = "잔차+가치")), c(ENTS, list(PP, PPC)))
chk(held_by(p4, "selection_basis_full_sample_ic_inherited"),
    "P4 [주입·MU3] 부모 as-of {FA,FB} · carry {FA} · 자식 설계 칸 {FA,FB}(FB 증명 없음) → 보류(부모 증명 ∩ carry = {FA})", c(codes(p4), dflags(p4)))
# ② 부모 증명은 carry 출처 칸까지 — 승격 뒤 부모 칸(n=40)은 carry 의 선정 이력이 아니다(적대검증 시스템 P2c)
PQ <- ent2("P_PQ", status = "exhausted", attempts = list(
  mk_att(1, "B1_1", mk_spec("PQ", "B1_1", c("FA", "FB"), label = "2팩터 직교(가치+모멘텀)"), grade = "B", flags = SELF(c("FA", "FB"))),
  mk_att(40, "B1_40", mk_spec("PQ", "B1_40", c("FA", "FB"), label = "2팩터 직교(가치+모멘텀)", sb = "asof_ic"), grade = "B")))
PQC <- ent2("P_PQC", parent = "P_PQ", carry = c("FA", "FB"), source_cell = "B1_1")
p5 <- elig(PQC, mk_att(6, "B2_6", mk_spec("PQC", "B2_6", c("FA", "FB"))), c(ENTS, list(PQ, PQC)))
chk(held_by(p5, "selection_basis_full_sample_ic_inherited"),
    "P5 [주입] carry 출처 = 부모 n=1(전표본) · 부모 n=40 as-of 재선정 {FA,FB} → 자식 새 칸 보류(출처 뒤 칸은 증명 아님)", c(codes(p5), dflags(p5)))
sp_pa <- mk_spec("PA", "B1_1", c("FA", "FB"), label = "2팩터 직교(가치+모멘텀)", sb = "asof_ic")
PA <- ent2("P_PA", status = "exhausted", attempts = list(mk_att(1, "B1_1", sp_pa, grade = "B")))
PAC <- ent2("P_PAC", parent = "P_PA", carry = c("FA", "FB"), source_cell = "B9_9", source_spec = sp_pa)
p5b <- elig(PAC, mk_att(6, "B2_6", mk_spec("PAC", "B2_6", c("FA", "FB"))), c(ENTS, list(PA, PAC)))
PAX <- ent2("P_PAX", parent = "P_PA", carry = c("FA", "FB"), source_cell = "B9_9")
p5c <- elig(PAX, mk_att(6, "B2_6", mk_spec("PAX", "B2_6", c("FA", "FB"))), c(ENTS, list(PA, PAX)))
chk(isTRUE(p5b$eligible) && held_by(p5c, "selection_basis_full_sample_ic_inherited"),
    "P5b [양성] carry 출처를 source_spec 으로 찾으면(코드 불일치여도) 부모 as-of 증명 승계 → 통과 · P5c 출처 못 찾음 → 증명 없음 = 보류(보수)",
    c(codes(p5b), codes(p5c)))
# ③ 격자 스냅샷 폴백 칸(적대검증 PIT B1 · C2/C3) — 실격자 B1 cells(루트 reinforce_program.json · 읽기만)
PGJ <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE), error = function(e) NULL)
G1 <- if (is.null(PGJ)) list() else (Filter(function(b) identical(b$id, "B1"), PGJ$blocks)[[1]] %||% list())$cells %||% list()
if (!length(G1)) sk("P6~P8 격자 스냅샷", "reinforce_program.json B1 cells 없음") else {
  gids <- function(c) vapply(c$factors, function(f) as.character(f$id), "")
  GF <- ent2("P_GF")
  p6 <- vapply(seq_along(G1), function(i) { c1 <- G1[[i]]
    held_by(elig(GF, mk_att(i, c1$code, mk_spec("GF", c1$code, gids(c1), label = c1$label),
                            idea = sprintf("[무인 병렬 %s] %s — B1/multifactor", c1$code, c1$label)), c(ENTS, list(GF))),
            "selection_basis_full_sample_ic") }, logical(1))
  chk(all(p6), sprintf("P6 [주입·PIT C2] 격자 스냅샷 폴백 칸 %d종(선정 기저 필드 없음 · 규칙 라벨) → 전부 자기 표식 보류(구판 B1_1~B1_4 통과)", length(G1)),
      paste(p6, collapse = ","))
  p6p <- elig(GF, mk_att(1, G1[[1]]$code, mk_spec("GFa", G1[[1]]$code, gids(G1[[1]]), label = G1[[1]]$label, sb = "asof_ic")), c(ENTS, list(GF)))
  chk(isTRUE(p6p$eligible), "P6p [양성] 같은 칸이 selection_basis=asof_ic(규칙 선정기 as-of) → 통과", c(codes(p6p), dflags(p6p)))
  # C3 — 폴백 칸이 원장에 측정·표식 없이 남은 뒤 그 승자를 승격한 자식(오염 집합 S 의 '표식 없는 규칙 라벨 칸' 경로 · MU10)
  for (stamp in c(FALSE, TRUE)) {
    GF0 <- ent2(if (stamp) "P_GF0s" else "P_GF0", status = "exhausted", attempts = lapply(1:2, function(i) { c1 <- G1[[i]]
      mk_att(i, c1$code, mk_spec(if (stamp) "GF0s" else "GF0", c1$code, gids(c1), label = c1$label, sb = if (stamp) "full_sample_ic" else NULL), grade = "B") }))
    GFC <- ent2(paste0(GF0$base_id, "_promo1"), parent = GF0$base_id, carry = gids(G1[[2]]), source_cell = G1[[2]]$code)
    p7 <- elig(GFC, mk_att(1, "B2_6", mk_spec(GFC$base_id, "B2_6", gids(G1[[2]]))), c(ENTS, list(GF0, GFC)))
    chk(held_by(p7, "selection_basis_full_sample_ic_inherited"),
        sprintf("P7%s [주입·PIT C3·MU10] 폴백 승자 승격 자식(carry {%s}) 새 칸 → 보류 — 부모 폴백 칸(측정 · 원장 표식 없음 · %s)이 오염 집합",
                if (stamp) "b" else "", paste(gids(G1[[2]]), collapse = ","), if (stamp) "spec full_sample_ic" else "선정 기저 필드 없음"),
        c(codes(p7), dflags(p7)))
  }
  # P8 — 적대검증 PIT C3 원형: 부모 entry 는 있는데 폴백 칸이 원장에 없다(또는 부모 entry 자체가 없다) → carry 출처 판독 불가 = 보류
  GFe <- ent2("P_GFE")                                                               # 칸 기록 없는 부모
  GFeC <- ent2("P_GFE_promo1", parent = "P_GFE", carry = gids(G1[[2]]), source_cell = G1[[2]]$code)
  p8a <- elig(GFeC, mk_att(1, "B2_6", mk_spec("GFeC", "B2_6", gids(G1[[2]]))), c(ENTS, list(GFe, GFeC)))
  GFo <- ent2("P_GFO_promo1", parent = "P_NO_SUCH_PARENT", carry = gids(G1[[2]]), source_cell = G1[[2]]$code)
  p8b <- elig(GFo, mk_att(1, "B2_6", mk_spec("GFo", "B2_6", gids(G1[[2]]))), c(ENTS, list(GFo)))
  cu <- function(el) any(grepl("carry 출처 판독 불가", unlist(el$detail), fixed = TRUE))
  chk(vfhold(p8a) && cu(p8a) && vfhold(p8b) && cu(p8b),
      "P8 [주입·PIT C3 원형] 폴백 승자 승격 자식인데 부모 칸이 원장에 없음 · 부모 entry 없음 → carry 출처 판독 불가 = 보류(구판 통과)",
      c(codes(p8a), codes(p8b), unlist(p8a$detail)[1]))
  # X3 — 러너 폴백 분기(소스 추출 실행): 격자 칸에 selection_basis=full_sample_ic · selection_asof=substrate 일자 → SPEC 부기 → 관문 자기 표식
  k0 <- grep("P0-14 수리 2판(2026-09-25 · 적대검증 PIT B1)", RUN, fixed = TRUE)
  if (length(k0) != 1L) ng("X3 러너 격자 스냅샷 폴백 부기 블록(앵커 1개)", sprintf("앵커 %d개 — 수리 2판 이전 러너", length(k0))) else {
    f0 <- k0 + which(grepl("^    for \\(\\.j in seq_along\\(batch\\)\\) \\{", RUN[(k0 + 1L):(k0 + 8L)]))[1]
    f1 <- f0 + which(RUN[(f0 + 1L):(f0 + 8L)] == "    }")[1]
    fb <- parse(text = paste(RUN[f0:f1], collapse = "\n"), keep.source = FALSE)
    fe <- new.env(); fe$`%||%` <- `%||%`; fe$batch <- G1; eval(fb, fe)
    sb_ok <- all(vapply(fe$batch, function(c) identical(c$selection_basis, "full_sample_ic") && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$|^grid_snapshot$", c$selection_asof %||% ""), logical(1)))
    i0x <- grep("P0-14(2026-09-25) 선정 기저 부기", RUN, fixed = TRUE)
    j0x <- i0x + which(grepl("^  if \\(!is.null\\(CELL\\[\\[\"selection_basis\"\\]\\]\\)\\) \\{", RUN[(i0x + 1L):(i0x + 6L)]))[1]
    j1x <- j0x + which(RUN[(j0x + 1L):(j0x + 4L)] == "  }")[1]
    ab <- parse(text = paste(RUN[j0x:j1x], collapse = "\n"), keep.source = FALSE)
    ae <- new.env(); ae$CELL <- fe$batch[[2]]; ae$SPEC <- list(code = ae$CELL$code, label = ae$CELL$label, factors = ae$CELL$factors,
                                                             weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"), overlay_cell = list())
    eval(ab, ae)
    sx <- file.path(S, ".cache/rf_parallel", sprintf("spec_%s__P_GFR.json", ae$SPEC$code)); writeLines(toJSON(ae$SPEC, auto_unbox = TRUE, null = "null"), sx)
    GFR <- ent2("P_GFR"); px <- elig(GFR, mk_att(2, ae$SPEC$code, sx), c(ENTS, list(GFR)))
    chk(sb_ok && identical(ae$SPEC$selection_basis, "full_sample_ic") && held_by(px, "selection_basis_full_sample_ic") &&
          any(grepl("selection_basis=full_sample_ic", dflags(px), fixed = TRUE)),
        sprintf("X3 러너 폴백 분기(소스 추출 실행) → 격자 %d칸 selection_basis=full_sample_ic · asof=%s → SPEC 부기 → 관문 자기 표식 보류",
                length(fe$batch), fe$batch[[1]]$selection_asof %||% "?"), c(codes(px), dflags(px)))
  }
}
# ④ 재도출 입력 판독 불가 = 보류(적대검증 PIT B2 · 시스템 2) — 재평가 경로(spec 인자 NULL → 원장 essence$spec 파일)
gone <- file.path(S, ".cache/rf_parallel/spec_gone_P.json"); badj <- file.path(S, ".cache/rf_parallel/spec_bad_P.json"); writeLines("{ corrupt", badj)
q3 <- elig(CH, mk_att(7, "B2_7", gone), ENTS); q4 <- elig(CH, mk_att(7, "B2_7", badj), ENTS)
q5 <- elig(UNR, mk_att(6, "B2_6", gone), ENTS)
a_ns <- list(n = 9L, cell_code = "B2_9", grade = "A", artifacts = ART_OK, opened_at = "2026-09-26T10:00:00+0900", essence = list(cell_code = "B2_9", port_t = 3.2))
q6 <- elig(UNR, a_ns, ENTS)
un <- function(el) any(grepl("재도출 입력 판독 불가", unlist(el$detail), fixed = TRUE))
sun <- function(el) any(grepl("칸 spec 판독 불가", unlist(el$detail), fixed = TRUE))
chk(vfhold(q3) && un(q3) && sun(q3) && vfhold(q4) && un(q4) && sun(q4),
    "Q3 [주입] 오염 carry 칸 재평가 — spec 파일 부재·파손 → 보류 유지(칸 spec 판독 불가 · 구판은 해제)", c(codes(q3), codes(q4)))
a_se <- mk_att(8, "B2_8", gone); a_se$engine_path <- file.path(S, "eng/eng_ok.R")
q8 <- elig(UNR, a_se, ENTS)
chk(vfhold(q8) && sun(q8),
    "Q8 [주입] spec 선언(부재) + 읽을 수 있는 engine_path → 엔진이 있어도 spec 판독 불가 보류(엔진 경로가 spec 부재를 가리지 않는다)", c(codes(q8), unlist(q8$detail)))
chk(vfhold(q5) && un(q5) && vfhold(q6) && un(q6),
    "Q5 [주입] 무관 계보라도 spec 판독 불가 · spec·engine_path 모두 없음 → 보류(판독 못 한 칸을 깨끗하다고 하지 않는다)", c(codes(q5), codes(q6)))
eb7 <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6m", c("FZ"), extra = list(base_signal = list(kind = "engine", path = file.path(S, "eng/does_not_exist.R"))))), ENTS)
chk(vfhold(eb7) && un(eb7) && any(grepl("엔진 판독 불가", unlist(eb7$detail), fixed = TRUE)),
    "Q7 [주입] 선언 기저 엔진 파일 부재 → C11 스캔 불가 → 보류(적대검증 P4e)", c(codes(eb7), unlist(eb7$detail)))
# ⑤ L2 원장 오염 집합(MU7) · tick 캐시(C9)
S4 <- file.path(TMP, sprintf("p14_lf_l2_%d", Sys.getpid())); unlink(S4, recursive = TRUE)
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts", "02_Infrastructure/validation", "06_Registry")) dir.create(file.path(S4, d), recursive = TRUE, showWarnings = FALSE)
for (r in c("02_Infrastructure/worktask/constraint_defaults.json", "02_Infrastructure/contracts/essence_score.R", "06_Registry/a_eligibility_gate.json",
            "02_Infrastructure/validation/pit_quarantine.R", "06_Registry/pit_quarantine.json"))
  file.copy(file.path(S, r), file.path(S4, r), overwrite = TRUE)
L2E <- ent2("P_L2SRC", status = "exhausted", attempts = list(
  mk_att(1, "B1_1", mk_spec("L2", "B1_1", c("FL1", "FL2"), label = "2팩터 직교(x+y)"), grade = "B", flags = SELF(c("FL1", "FL2")))))
writeLines(toJSON(list(entries = list(L2E)), auto_unbox = TRUE, null = "null"), file.path(S4, "06_Registry/reinforce_ledger_l2.json"))
UL <- ent2("P_UL")
p9 <- elig(UL, mk_att(3, "B2_3", mk_spec("UL", "B2_3", c("FL1", "FL2", "FX"))), list(UL), root = S4)
chk(held_by(p9, "selection_basis_full_sample_ic_inherited"), "P9 [주입·MU7] L2 원장에만 있는 자기 표식 집합 {FL1,FL2} 을 싣은 L1 새 칸 → 보류", c(codes(p9), dflags(p9)))
# MU9 — 격리 팩터 id 경로 단독(원천 정규식과 겹치지 않는 id · 합성 격리 목록) — 실목록은 격리 팩터 id 가 원천 정규식에도 있어 경로가 겹친다
S5 <- file.path(TMP, sprintf("p14_lf_q5_%d", Sys.getpid())); unlink(S5, recursive = TRUE)
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts", "02_Infrastructure/validation", "06_Registry")) dir.create(file.path(S5, d), recursive = TRUE, showWarnings = FALSE)
for (r in c("02_Infrastructure/worktask/constraint_defaults.json", "02_Infrastructure/contracts/essence_score.R", "06_Registry/a_eligibility_gate.json",
            "02_Infrastructure/validation/pit_quarantine.R"))
  file.copy(file.path(S, r), file.path(S5, r), overwrite = TRUE)
writeLines(toJSON(list(entries = list()), auto_unbox = TRUE), file.path(S5, "06_Registry/reinforce_ledger_l2.json"))
writeLines(toJSON(list(schema = "pit_quarantine_test", quarantines = list(list(id = "T_QZ", status = "active", flag = "pit_c11",
                                                                                 factors = list(list(id = "FQZ_Synthetic")), sources = list()))),
                  auto_unbox = TRUE), file.path(S5, "06_Registry/pit_quarantine.json"))
UQ <- ent2("P_UQ")
p11 <- elig(UQ, mk_att(3, "B2_3", mk_spec("UQ", "B2_3q", c("FZ", "FQZ_Synthetic"))), list(UQ), root = S5)
p11p <- elig(UQ, mk_att(4, "B2_4", mk_spec("UQ", "B2_4q", c("FZ"))), list(UQ), root = S5)
chk(held_by(p11, "pit_c11") && any(grepl("factors=FQZ_Synthetic", dflags(p11), fixed = TRUE)) && isTRUE(p11p$eligible),
    "P11 [주입·MU9] 원천 정규식에 없는 격리 팩터 id(합성 격리 목록) → 보류 pit_c11(factors=) · 대조(격리 팩터 없음) → 통과",
    c(codes(p11), dflags(p11), codes(p11p)))
RCc <- rf_runner_ctx(S)
U10 <- ent2("P_U10")   # carry 없는 entry(출처 판독 불가 보류와 섞이지 않게) — 설계 칸 {FA,FB}
ENTS_noSRC <- c(Filter(function(e) !identical(e$base_id, "T_SRC"), ENTS), list(U10))
c9a <- rf_a_eligibility(U10, mk_att(7, "B2_7", mk_spec("U10", "B2_7c9", c("FA", "FB"))), NULL, rf_a_ctx(RCc, ENTS_noSRC, "P_U10"))
c9b <- rf_a_eligibility(U10, mk_att(7, "B2_7", mk_spec("U10", "B2_7c9", c("FA", "FB"))), NULL, rf_a_ctx(RCc, c(ENTS, list(U10)), "P_U10"))
chk(isTRUE(c9a$eligible) && held_by(c9b, "selection_basis_full_sample_ic_inherited"),
    "P10 [주입·C9] 같은 tick 캐시 — 첫 호출(오염 원천 entry 없는 원장) 뒤 전체 원장 호출 → 다시 계산해 보류(구판 키 = root 만 · 첫 entries 고정)",
    c(codes(c9a), codes(c9b)))

cat("\n=== M. 돌연변이 ===\n")
if (HAS_LIB) {
  keep <- list(rflf_gate_flags = rflf_gate_flags, rflf_inherits = rflf_inherits, .rflf_sb = .rflf_sb, rflf_clean_ids = rflf_clean_ids, rflf_c11_derive = rflf_c11_derive)
  restore <- function() for (k in names(keep)) assign(k, keep[[k]], envir = globalenv())
  # M1 재도출 제거 → 구판 관문(원장 표식만)
  assign("rflf_gate_flags", function(...) list(flags = list(), selection = NULL, c11 = NULL, S_unknown = character(0)), envir = globalenv())
  m1a <- elig(CH, a1, ENTS)
  m1r <- if (exists("E22")) rf_a_eligibility(E22, a22, NULL, rf_a_ctx(rf_runner_ctx(LC), RL$entries, E22$base_id)) else list(eligible = TRUE)
  restore()
  chk(isTRUE(m1a$eligible) && isTRUE(m1r$eligible), "M1 [돌연변이] 재도출 제거 → A1 합성·R2 22632 새 칸이 통과로 샌다(= A1·R2 가 잡는다)", c(codes(m1a), codes(m1r)))
  # M2 술어 사본화(드리프트 사본: 포함 → 교집합) → parity red
  if (!is.null(RL)) {
    assign("rflf_inherits", function(f, sets) Filter(function(sx) any(sx %in% f), sets %||% list()), envir = globalenv())
    PRm <- parity(); restore()
    chk(PRm[!m_sel & d_sel & !m_b7, .N] > 0L, "M2 [돌연변이] 관문 쪽 술어를 사본(드리프트)으로 바꾸면 derive 표식과 parity 가 깨진다(= R1 이 잡는다)",
        sprintf("재도출만(비 B7) %d", PRm[!m_sel & d_sel & !m_b7, .N]))
  }
  DEF <- unlist(lapply(list.files(file.path(ROOT, "02_Infrastructure"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE), function(f) {
    x <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
    if (any(grepl("^(rflf_fids|rflf_inherits|rflf_is_rule_cell) <- function", x))) f else NULL }))
  chk(length(DEF) == 1L && grepl("rf_lineage_flags[.]R$", DEF), "M2b 술어 정의는 02_Infrastructure 전체에서 한 곳(rf_lineage_flags.R) — 사본 0", paste(basename(DEF), collapse = ","))
  # M3 as-of 면제 제거
  assign(".rflf_sb", function(s) "", envir = globalenv())
  m3 <- c(isTRUE(elig(ASO, mk_att(2, "B1_2", mk_spec("ASOF", "B1_2", c("FS"), label = "1팩터 직교(품질)", sb = "asof_ic")), ENTS)$eligible),
          isTRUE(elig(ASC, mk_att(6, "B2_6", mk_spec("ASC", "B2_6", c("FA", "FB"))), ENTS)$eligible))
  restore()
  chk(!any(m3), "M3 [돌연변이] as-of 면제 제거 → as-of 재선정 칸(A2a)·as-of 자식(A6)이 보류된다(= A2a·A6 이 잡는다)", paste(m3, collapse = ","))
  # M4 계보 재귀 제거(자기 entry 만)
  assign("rflf_clean_ids", function(entries, bid, root, before_n = Inf, cache = NULL, depth = 0L, seen = character(0), max_depth = 20L) {
    E <- Filter(function(x) identical(x$base_id, bid), entries); if (!length(E)) return(character(0))
    cf <- rflf_fids(E[[1]]$carry); own <- character(0)
    for (a in E[[1]]$attempts %||% list()) { s <- .rflf_spec_of(a, root, cache)
      if (identical(keep$.rflf_sb(s), "asof_ic") && rflf_is_rule_cell(a, s)) own <- union(own, setdiff(rflf_fids(s), cf)) }
    own }, envir = globalenv())
  m4 <- elig(ASC, mk_att(6, "B2_6", mk_spec("ASC", "B2_6", c("FA", "FB"))), ENTS)
  m4b <- elig(ASO, mk_att(6, "B2_6", mk_spec("ASOF", "B2_6", c("FA", "FB"))), ENTS)
  restore()
  chk(!isTRUE(m4$eligible) && isTRUE(m4b$eligible), "M4 [돌연변이] 계보 재귀 제거 → as-of 루트의 승격 자식(A6)이 보류(자기 entry 증명 A2b 는 통과) — 재귀가 하중을 진다",
      c(codes(m4), codes(m4b)))
  # M5 C11 재도출 제거
  assign("rflf_c11_derive", function(...) list(hit = FALSE, factors = character(0), sources = list(), base_flag = character(0), scanned = 0L), envir = globalenv())
  m5p <- elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6p", c("FZ"), overlay = PG2, overlay_cell = list())), ENTS)
  m5 <- c(pg2_leak = !("vintage_flag" %in% m5p$codes),   # 적대검증 승계 층 보류는 남지만 C11 보류가 사라진다
          engine_leak = isTRUE(elig(UNR, mk_att(6, "B2_6", mk_spec("UNR", "B2_6e", c("FZ"), extra = list(base_signal = list(kind = "engine", path = file.path(S, "eng/eng_bad.R"))))), ENTS)$eligible),
          base_leak = isTRUE(elig(UNRB, mk_att(6, "B2_6", mk_spec("UNRB", "B2_6h", c("FZ"))), list(UNRB))$eligible))
  restore()
  chk(all(m5), "M5 [돌연변이] C11 재도출 제거 → 정지 arm 승계(vintage_flag 사라짐)·격리 엔진·격리 기저가 새어 나간다(= B1·B2·B4 가 잡는다)", paste(m5, collapse = ","))
} else ng("M 절", "수리 전 코드 — 돌연변이 대상 술어 없음")

cat("\n=== Z. 루트 무접촉 ===\n")
chk(identical(md5_prod(), PROD0) && identical(sort(list.files(file.path(ROOT, "04_Research/strategies"))), LS0),
    "Z1 루트 원장·큐·격리 목록·관문 설정 md5 불변 · 04_Research/strategies 목록 불변(쓰기는 tempdir 만)")
unlink(c(S, S3, LC, if (exists("SQ")) SQ, if (exists("SL")) SL, if (exists("S4")) S4, if (exists("S5")) S5), recursive = TRUE, force = TRUE)
emit()
quit(status = if (FAIL > 0L) 1L else 0L)
