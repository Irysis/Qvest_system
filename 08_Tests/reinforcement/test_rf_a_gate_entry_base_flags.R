#!/usr/bin/env Rscript
#==============================================================================
# test_rf_a_gate_entry_base_flags.R — AUTOMEM 표식(AUTOMEM-EXPOSED-CELLS-DISPOSITION · B5FIX-CONSUME-HOLD · FA-CLEAN-BASE-PATH 조정 ·
#   PROMO1-CARRY-OMISSION-FLAG · 2026-09-26)의 관문 효과 **양방향 검사** — 판정 = rf_runner_gates.R 순수 함수 · 쓰기는 tempdir 만
#
#   G  A 관문(rf_a_eligibility ⑤)
#      G0 정상 A = 발행(대조) · G1 칸 설계 표식 = 보류 · G2 arm 승계 표식 = 보류 · G3 entry 기저 표식 = 그 entry 칸 보류(self)
#      G4 목록 밖 기저 표식(fdb_202608_v1) = 비전파 · G5 계보 = 보류 · G6 같은 엔진 경로(구분자 차이) = 보류 · G7 다른 엔진 = 발행
#      G8 설정 목록 부재 = 기저 표식 비전파(설정이 켠다) · G9 설정 목록 존재
#      G10 계보 자식 엔진이 **청정 판**(wdir_prefix 디렉터리 · lane_provenance clean · md5 · cutoff 뒤 · engine_rel 일치) = 발행
#      G10b 같은 청정 경로 entry 의 기저 표식 = 발행(이중 안전) · G10c 접두 없는 디렉터리의 청정 기록 = 보류 · G10d engine_rel 불일치 = 보류
#      (10-03: 청정 갈래 consumer_rule 갱신 — engine_rel == 그 엔진 ∧ 디렉터리 접두 = wdir_prefix · 06_Registry/replication_clean_lane.json)
#      G11 같은 경로 **비청정 재구현**(출처 기록 없음) = 보류 · G12 청정 기록 뒤 엔진 수정(md5 불일치) = 보류 · G13 청정 실행 시각 < cutoff = 보류
#      G14 다른 경로·비계보인데 노출 엔진과 **같은 내용**(md5) = 보류(same_content) · G15 청정 기록인데 내용 = 노출 md5 = 보류
#      G16 carry 누락 표식(treatment_misspecified_carry_omission · consumed) = 보류
#   C  소비 술어(rf_candidate_facts · B5FIX (c) consume_hold — 배포돼 있을 때만 · 없으면 SKIP)
#      C1 칸 설계 표식 = 소비 제외 + A 보류 · C2 설계 승계 표식 = 제외 + 보류 · C3 arm 표식 = 제외 + 보류
#      C4 entry 기저 표식 = **소비 유지** + A 보류 · C5 consume_hold "*" 여도 기저 표식 = 소비 유지(필드 분리)
#      C6 carry 누락 표식 = 소비 유지 + A 보류(소비 보류는 설계 노출 표식 전용) · C7 표식 없음 = 유지 + 발행
#   M  돌연변이 — M1 entry 기저 블록 무력화 → G3 발행 · M2 목록 필터 제거 → G4 보류 · M3 청정 제외 줄 무력화 → G10 보류 ·
#      M4 consume_hold 에서 AUTOMEM 이름 제거 → C1 소비 유지 · M5 기저 표식을 attempt 필드에 쓰면("*") → 소비 제외(필드가 판별자) ·
#      M6 청정 접두 검사 무력화 → G10c 발행 · M7 engine_rel 대조 무력화 → G10d 발행
# 실행: QM_ROOT=<저장소 또는 미러> Rscript --no-environ 08_Tests/reinforcement/test_rf_a_gate_entry_base_flags.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
cat(sprintf("ROOT = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
sk <- function(m, why = "") { SKIP <<- SKIP + 1L; cat("  SKIP", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
GATE_SRC <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")
load_gate <- function(path) {
  e <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages({
    sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = e)
    sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), envir = e)
    sys.source(path, envir = e) })))
  e
}
GE <- load_gate(GATE_SRC)
TMP <- gsub("\\", "/", tempdir(), fixed = TRUE)
S <- file.path(TMP, sprintf("rf_aebf_%d", Sys.getpid()))
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts", "06_Registry", "stage_artifacts/replication", ".cache/rf_parallel", "04_Research/strategies"))
  dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S, "02_Infrastructure/worktask"), overwrite = TRUE))
invisible(file.copy(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R"), file.path(S, "02_Infrastructure/contracts"), overwrite = TRUE))
invisible(file.copy(file.path(ROOT, "06_Registry/a_eligibility_gate.json"), file.path(S, "06_Registry"), overwrite = TRUE))
if (!all(file.exists(file.path(S, c("02_Infrastructure/worktask/constraint_defaults.json", "02_Infrastructure/contracts/essence_score.R",
                                    "06_Registry/a_eligibility_gate.json"))))) { cat("  FAIL 샌드박스 설정 사본 실패\n"); quit(status = 1) }
CUR <- GE$rf_current_regime(S)$regime
EBF <- "base_automem_cross_entry_metrics"
gcfg <- fromJSON(file.path(S, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)
HAS_LIST <- EBF %in% as.character(unlist(gcfg$holds$vintage_flag$entry_base_flags %||% list()))
CUTOFF <- as.character(gcfg$holds$vintage_flag$entry_base_clean$produced_after %||% "2026-09-25T15:01:46+0900")
cat(sprintf("현행 규약 = %s · entry_base_flags 에 %s %s · 청정 규칙 %s\n", CUR, EBF, if (HAS_LIST) "있음" else "없음(패치 전 설정)",
            if (is.list(gcfg$holds$vintage_flag$entry_base_clean)) "있음" else "없음"))

mk_art <- function(tag) {
  d <- file.path(S, "stage_artifacts/replication", tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  dates <- seq(as.Date("2005-02-01"), as.Date("2026-08-01"), by = "month")
  saveRDS(list(holdings = data.frame(date = dates, ticker = "A005930", weight = 1),
               period_returns = data.frame(date = dates, ret_net = 0.01)), file.path(d, "bt_result.rds"))
  au <- list(status = "OK", essence_grade = "A", selection_type = "sweep", dsr = 0.9, essence = list(dsr = 0.9), n_trials_cumulative = 12L,
             measurement_regime = list(selection_type = "sweep", n_trials_basis = "base1+lineage_measured(excl_inherited)+batch_size",
                                       exec_price = CUR, n_trials_cumulative = 12L))
  writeLines(toJSON(au, auto_unbox = TRUE, null = "null"), file.path(d, "authoritative_remeasure.json"))
  d
}
SP <- file.path(S, ".cache/rf_parallel/spec_B2_6__T.json")
writeLines(toJSON(list(code = "B2_6", factors = list(list(kind = "db", id = "F1")), weighting = list(kind = "ew"),
                       universe = list(kind = "k200_kq150"), overlay_cell = list()), auto_unbox = TRUE, null = "null"), SP)
ART <- mk_art("ok")
mk_att <- function(flags = NULL) { a <- list(n = 6L, cell_code = "B2_6", grade = "A", artifacts = ART,
                                             measurement_regime = list(exec_price = CUR, regime = CUR),
                                             essence = list(cell_code = "B2_6", port_t = 3.2, calmar = 0.7, window_deviation_months = 0, spec = SP))
  if (!is.null(flags)) a$vintage_flags <- flags; a }
flag <- function(f, v = "possible", src = "test") list(flag = f, verdict = v, evidence = "합성 픽스처", source = src, policy = "test", marked_at = "2026-09-26T00:00:00+0900")
mk_eng <- function(dir, content, prov = NULL) {
  d <- file.path(S, "04_Research/strategies", dir); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  f <- file.path(d, "engine.R"); writeLines(content, f); unlink(file.path(d, "lane_provenance.json"))
  if (!is.null(prov)) {   # 청정 레인 출처 기록(rf_clean_lane.py prov-pre/post 모양) — engine_rel 미지정이면 이 엔진의 저장소 상대경로
    if (is.null(prov$engine_rel)) prov$engine_rel <- sprintf("04_Research/strategies/%s/engine.R", dir)
    writeLines(toJSON(prov, auto_unbox = TRUE, null = "null"), file.path(d, "lane_provenance.json")) }
  list(path = f, md5 = unname(as.character(tools::md5sum(f))))
}
prov_clean <- function(md5, at = "2026-09-26T10:00:00+0900", mode = "clean", engine_rel = NULL) {
  p <- list(schema = "lane_provenance_v1", mode = mode, clean = identical(mode, "clean"), pre = list(at = at), post = list(engine_md5 = md5))
  if (!is.null(engine_rel)) p$engine_rel <- engine_rel
  p }
CLP <- as.character(gcfg$holds$vintage_flag$entry_base_clean$wdir_prefix %||% "RP_AUTO_CLEAN_")   # 청정 작업 디렉터리 접두(설정 정본)
bsrc <- function(md5) sprintf("AUTOMEM-EXPOSED-CELLS-DISPOSITION · faithful · test · base:same_engine · engine_md5=%s", md5)
mk_entry <- function(bid, eng, base_flags = NULL, parent = NULL, att = mk_att()) {
  e <- list(base_id = bid, status = "active", engine_path = eng, attempts = list(att))
  if (!is.null(base_flags)) e$base_vintage_flags <- base_flags
  if (!is.null(parent)) e$parent <- list(base_id = parent)
  e
}
elig <- function(entry, extra = list(), G = GE, root = S) {
  ents <- c(list(entry), extra)
  G$rf_a_eligibility(entry, entry$attempts[[1]], NULL, G$rf_a_ctx(G$rf_runner_ctx(root), ents, entry$base_id))
}
vfd <- function(el) paste(el$detail[["vintage_flag"]] %||% "", collapse = " ")
held_vf <- function(el) "vintage_flag" %in% el$codes

cat("\n=== G. A 관문 ⑤ ===\n")
V1 <- mk_eng("RP_AUTO_A", "# exposed v1 — 노출 실행 산출")
EB <- mk_eng("RP_AUTO_B", "# other engine")
e0 <- elig(mk_entry("T_G0", V1$path))
chk(isTRUE(e0$eligible), sprintf("G0 정상 A(표식 없음) = 발행 (codes=%s)", paste(e0$codes, collapse = "+")), paste(e0$codes, collapse = "+"))
e1 <- elig(mk_entry("T_G1", EB$path, att = mk_att(list(flag("design_automem_cross_entry_metrics")))))
chk(held_vf(e1) && grepl("design_automem_cross_entry_metrics", vfd(e1)), "G1 칸 설계 표식(possible) = vintage_flag 보류", vfd(e1))
e2 <- elig(mk_entry("T_G2", EB$path, att = mk_att(list(flag("arm_automem_cross_entry_metrics_inherited")))))
chk(held_vf(e2), "G2 칸 arm 승계 표식(possible) = vintage_flag 보류", vfd(e2))
FB <- list(flag(EBF, src = bsrc(V1$md5)))
e3 <- elig(mk_entry("T_G3", V1$path, base_flags = FB))
chk(held_vf(e3) && grepl("entry 기저 T_G3(self)", vfd(e3), fixed = TRUE), "G3 entry 기저 표식 = 그 entry 칸 보류(self)", vfd(e3))
e4 <- elig(mk_entry("T_G4", V1$path, base_flags = list(flag("fdb_202608_v1", "consumed"))))
chk(isTRUE(e4$eligible), "G4 목록 밖 기저 표식(fdb_202608_v1) = 칸으로 번지지 않음(발행)", paste(e4$codes, collapse = "+"))
par <- mk_entry("T_P", V1$path, base_flags = FB)
e5 <- elig(mk_entry("T_C", V1$path, parent = "T_P"), extra = list(par))
chk(held_vf(e5) && grepl("entry 기저 T_P(lineage)", vfd(e5), fixed = TRUE), "G5 부모 entry 기저 표식 = 자식 칸 보류(lineage)", vfd(e5))
sib <- mk_entry("T_SIB", gsub("/", "\\\\", V1$path), base_flags = FB)
e6 <- elig(mk_entry("T_NEW", V1$path), extra = list(sib))
chk(held_vf(e6) && grepl("entry 기저 T_SIB(same_engine)", vfd(e6), fixed = TRUE), "G6 같은 엔진 경로(구분자 차이) 다른 entry 기저 표식 = 보류(same_engine)", vfd(e6))
e7 <- elig(mk_entry("T_OWN", EB$path), extra = list(sib))
chk(isTRUE(e7$eligible), "G7 다른 엔진·비계보·다른 내용 = 발행", paste(e7$codes, collapse = "+"))
S8 <- file.path(TMP, sprintf("rf_aebf8_%d", Sys.getpid())); dir.create(file.path(S8, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
for (d in c("02_Infrastructure/worktask", "02_Infrastructure/contracts")) { dir.create(file.path(S8, d), recursive = TRUE, showWarnings = FALSE)
  invisible(file.copy(list.files(file.path(S, d), full.names = TRUE), file.path(S8, d), overwrite = TRUE)) }
g8 <- gcfg; g8$holds$vintage_flag$entry_base_flags <- NULL
writeLines(toJSON(g8, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S8, "06_Registry/a_eligibility_gate.json"))
e8 <- elig(mk_entry("T_G8", V1$path, base_flags = FB), root = S8)
chk(isTRUE(e8$eligible) || !held_vf(e8), "G8 설정 목록 부재 = 기저 표식이 칸을 보류하지 않음(설정이 켠다)", paste(e8$codes, collapse = "+"))
chk(HAS_LIST, "G9 설정에 entry_base_flags 목록 존재", "패치 전 설정")
# 청정 재구현 — 청정 레인은 항상 새 작업 디렉터리(설정 wdir_prefix)에 쓴다(10-03 인터페이스: engine_rel == 이 엔진 · 디렉터리 접두).
#   G10 계보 자식(부모 = 노출 기저)이 청정 엔진 = 발행 · G10b 같은 청정 경로를 쓰는 entry 에 기저 표식(이중 안전 픽스처) = 발행
#   G10c 접두 없는 디렉터리(노출 엔진 자리)의 '청정' 기록 = 보류 · G10d 기록 engine_rel 이 다른 엔진(복사된 기록) = 보류
CD <- paste0(CLP, "A")
V2 <- mk_eng(CD, "# clean v2 — 청정 모드 재구현"); V2 <- mk_eng(CD, "# clean v2 — 청정 모드 재구현", prov_clean(V2$md5))
e10 <- elig(mk_entry("T_C2", V2$path, parent = "T_P"), extra = list(par))
chk(isTRUE(e10$eligible), sprintf("G10 계보 자식 엔진이 청정 판(%s* · 기록 clean · md5 · cutoff 뒤 · engine_rel 일치) = 발행(계보 전파 제외)", CLP),
    sprintf("codes=%s detail=%s clean=%s", paste(e10$codes, collapse = "+"), vfd(e10), e10$facts$engine_clean %||% ""))
sibC <- mk_entry("T_SIBC", V2$path, base_flags = FB)
e10b <- elig(mk_entry("T_CLEAN", V2$path), extra = list(sibC))
chk(isTRUE(e10b$eligible), "G10b 같은 청정 경로 entry 의 기저 표식 = 발행(같은 경로 전파 제외 — 이중 안전)", sprintf("%s · %s", vfd(e10b), e10b$facts$engine_clean %||% ""))
V2a <- mk_eng("RP_AUTO_A", "# clean 기록이 있으나 노출 엔진 자리"); V2a <- mk_eng("RP_AUTO_A", "# clean 기록이 있으나 노출 엔진 자리", prov_clean(V2a$md5))
e10c <- elig(mk_entry("T_NOPFX", V2a$path), extra = list(sib))
chk(held_vf(e10c) && grepl("청정 접두", e10c$facts$engine_clean %||% "", fixed = TRUE), "G10c 접두 없는 디렉터리(노출 엔진 자리)의 청정 기록 = 보류(same_engine 유지)", e10c$facts$engine_clean %||% "")
V2d <- mk_eng(CD, "# clean v2 — 청정 모드 재구현", prov_clean(V2$md5, engine_rel = sprintf("04_Research/strategies/%sOTHER/engine.R", CLP)))
e10d <- elig(mk_entry("T_C2d", V2d$path, parent = "T_P"), extra = list(par))
chk(held_vf(e10d) && grepl("engine_rel", e10d$facts$engine_clean %||% "", fixed = TRUE), "G10d 기록 engine_rel ≠ 이 엔진(다른 디렉터리에서 복사된 기록) = 보류", e10d$facts$engine_clean %||% "")
V3 <- mk_eng("RP_AUTO_A", "# non-clean v3 — 표준 레인 재구현(앞 판을 읽을 수 있다)")
e11 <- elig(mk_entry("T_NC", V3$path), extra = list(sib))
chk(held_vf(e11) && grepl("(same_engine)", vfd(e11), fixed = TRUE), "G11 같은 경로 비청정 재구현(출처 기록 없음) = 보류", vfd(e11))
V4 <- mk_eng(CD, "# clean v2 뒤 손댄 판", prov_clean(V2$md5))
e12 <- elig(mk_entry("T_TOUCH", V4$path, parent = "T_P"), extra = list(par))
chk(held_vf(e12) && grepl("post.engine_md5", e12$facts$engine_clean %||% "", fixed = TRUE), "G12 청정 기록 뒤 엔진 수정(post.engine_md5 ≠ 현재) = 보류", e12$facts$engine_clean %||% "")
V5 <- mk_eng(CD, "# clean 이지만 cutoff 전 실행"); V5 <- mk_eng(CD, "# clean 이지만 cutoff 전 실행", prov_clean(V5$md5, at = "2026-09-25T10:00:00+0900"))
e13 <- elig(mk_entry("T_EARLY", V5$path, parent = "T_P"), extra = list(par))
chk(held_vf(e13) && grepl("cutoff", e13$facts$engine_clean %||% "", fixed = TRUE), "G13 청정 실행 시각 < cutoff = 보류", e13$facts$engine_clean %||% "")
VC <- mk_eng("RP_AUTO_COPY", "# exposed v1 — 노출 실행 산출")
e14 <- elig(mk_entry("T_COPY", VC$path), extra = list(sib))
chk(identical(VC$md5, V1$md5) && held_vf(e14) && grepl("(same_content)", vfd(e14), fixed = TRUE), "G14 다른 경로·비계보인데 노출 엔진과 같은 내용 = 보류(same_content)", vfd(e14))
VD <- mk_eng("RP_AUTO_CLEAN_D", "# exposed v1 — 노출 실행 산출", prov_clean(V1$md5))
e15 <- elig(mk_entry("T_FAKECLEAN", VD$path), extra = list(sib))
chk(held_vf(e15) && grepl("노출 기저 엔진 내용", e15$facts$engine_clean %||% "", fixed = TRUE), "G15 청정 기록인데 내용 = 노출 md5 = 보류(모순 가드)", e15$facts$engine_clean %||% "")
e16 <- elig(mk_entry("T_CO", EB$path, att = mk_att(list(flag("treatment_misspecified_carry_omission", "consumed")))))
chk(held_vf(e16) && grepl("treatment_misspecified_carry_omission", vfd(e16)), "G16 carry 누락 표식(consumed) = vintage_flag 보류", vfd(e16))

cat("\n=== C. 소비 술어 — 칸 표식 = 소비 제외 · 기저 표식 = 소비 유지 (B5FIX-CONSUME-HOLD) ===\n")
if (!exists("rf_consume_hold_config", envir = GE, mode = "function")) {
  sk("C1~C7 · M4·M5", "소비 보류(B5FIX (c)) 미배포 관문 — 소비 술어가 표식을 읽지 않는다")
} else {
  ctx <- GE$rf_runner_ctx(S)
  keep <- function(a, cx = ctx) length(GE$rf_candidates_keep(list(a), cx, role = "floor")) == 1L
  aflag <- function(f, v = "possible") mk_att(list(flag(f, v)))
  cat(sprintf("  consume_hold.flags = %s\n", paste(ctx$consume_hold$flags, collapse = ",")))
  for (cs in list(list("C1", "design_automem_cross_entry_metrics"), list("C2", "design_automem_cross_entry_metrics_inherited"),
                  list("C3", "arm_automem_cross_entry_metrics"))) {
    a <- aflag(cs[[2]]); ea <- elig(mk_entry(paste0("T_", cs[[1]]), EB$path, att = a))
    chk(!keep(a) && held_vf(ea), sprintf("%s 칸 표식 %s = 소비 제외 + A 보류", cs[[1]], cs[[2]]), sprintf("keep=%s held=%s", keep(a), held_vf(ea)))
  }
  V1 <- mk_eng("RP_AUTO_A", "# exposed v1 — 노출 실행 산출")   # G10~G13 이 바꾼 파일을 노출 판으로 되돌린다
  a4 <- mk_att(); e4c <- elig(mk_entry("T_C4", V1$path, base_flags = FB, att = a4))
  chk(keep(a4) && held_vf(e4c), "C4 entry 기저 표식 = 소비 유지 + A 보류(self)", sprintf("keep=%s held=%s", keep(a4), held_vf(e4c)))
  ctx5 <- ctx; ctx5$consume_hold <- list(flags = "*", verdicts = character(0))
  chk(keep(a4, ctx5), "C5 consume_hold \"*\"(모든 표식)여도 기저 표식 = 소비 유지 — 소비 술어는 attempt 필드만 읽는다(필드 분리)")
  a6 <- aflag("treatment_misspecified_carry_omission", "consumed"); e6c <- elig(mk_entry("T_C6", EB$path, att = a6))
  chk(keep(a6) && held_vf(e6c), "C6 carry 누락 표식 = 소비 유지 + A 보류(소비 보류는 설계 노출 표식 전용)", sprintf("keep=%s held=%s", keep(a6), held_vf(e6c)))
  a7 <- mk_att(); e7c <- elig(mk_entry("T_C7", EB$path, att = a7))
  chk(keep(a7) && isTRUE(e7c$eligible), "C7 표식 없음 = 소비 유지 + 발행(대조)")
  ctxm4 <- ctx; ctxm4$consume_hold$flags <- setdiff(ctx$consume_hold$flags, c("design_automem_cross_entry_metrics", "arm_automem_cross_entry_metrics",
                                                                              "design_automem_cross_entry_metrics_inherited", "arm_automem_cross_entry_metrics_inherited"))
  chk(keep(aflag("design_automem_cross_entry_metrics"), ctxm4), "M4 [돌연변이] consume_hold 에서 AUTOMEM 이름 제거 → C1 칸이 소비 후보로 남는다(목록이 제외의 원인)")
  chk(!keep(aflag(EBF), ctx5), "M5 [돌연변이] 기저 표식을 attempt 필드에 쓰면(\"*\") → 소비 제외 — C5 의 유지는 필드가 가른다")
}

cat("\n=== M. 관문 돌연변이 ===\n")
src <- readLines(GATE_SRC, warn = FALSE, encoding = "UTF-8")
mut <- function(tag, from, to) {
  k <- grep(from, src, fixed = TRUE)
  if (length(k) != 1L) return(NULL)
  s2 <- src; s2[k] <- sub(from, to, s2[k], fixed = TRUE)
  p <- file.path(TMP, sprintf("gate_%s_%d.R", tag, Sys.getpid())); writeLines(s2, p, useBytes = TRUE)
  load_gate(p)
}
V1 <- mk_eng("RP_AUTO_A", "# exposed v1 — 노출 실행 산출")
m1 <- mut("m1", "if (length(.ebf)) {", "if (FALSE) {")
if (is.null(m1)) ng("M1 대상 줄(entry 기저 블록) 부재", "패치 전 관문이면 기대된 부재") else {
  x <- elig(mk_entry("T_M1", V1$path, base_flags = FB), G = m1)
  chk(isTRUE(x$eligible) || !held_vf(x), "M1 entry 기저 블록 무력화 → G3 픽스처 발행(블록이 보류의 원인)", paste(x$codes, collapse = "+")) }
m2 <- mut("m2", "Filter(function(z) .rfg_s1(z$flag) %in% .ebf,", "Filter(function(z) TRUE,")
if (is.null(m2)) ng("M2 대상 줄(목록 필터) 부재", "패치 전 관문이면 기대된 부재") else {
  x <- elig(mk_entry("T_M2", V1$path, base_flags = list(flag("fdb_202608_v1", "consumed"))), G = m2)
  chk(held_vf(x), "M2 목록 필터 제거 → G4 픽스처 보류(필터가 fdb_* 확산을 막는다)", paste(x$codes, collapse = "+")) }
m3 <- mut("m3", "if (.via %in% c(\"lineage\", \"same_engine\") && isTRUE(.cl0$ok)) next", "if (FALSE) next")
if (is.null(m3)) ng("M3 대상 줄(청정 제외) 부재", "패치 전 관문이면 기대된 부재") else {
  W2 <- mk_eng(CD, "# clean v2 — 청정 모드 재구현"); W2 <- mk_eng(CD, "# clean v2 — 청정 모드 재구현", prov_clean(W2$md5))
  x0 <- elig(mk_entry("T_M3", W2$path, parent = "T_P"), extra = list(par))
  x <- elig(mk_entry("T_M3", W2$path, parent = "T_P"), extra = list(par), G = m3)
  chk(isTRUE(x0$eligible) && held_vf(x), "M3 청정 제외 줄 무력화 → G10 픽스처(원판 발행) 보류(그 줄이 청정 재구현을 풀어 준다)", paste(x$codes, collapse = "+")) }
m6 <- mut("m6", "if (!startsWith(tolower(basename(dirname(f))), tolower(.rfg_s1(cfg$wdir_prefix))))", "if (FALSE)")
if (is.null(m6)) ng("M6 대상 줄(청정 접두 검사) 부재", "10-03 인터페이스 전 관문이면 기대된 부재") else {
  W6 <- mk_eng("RP_AUTO_A", "# clean 기록이 있으나 노출 엔진 자리"); W6 <- mk_eng("RP_AUTO_A", "# clean 기록이 있으나 노출 엔진 자리", prov_clean(W6$md5))
  x <- elig(mk_entry("T_M6", W6$path), extra = list(sib), G = m6)
  chk(!held_vf(x), "M6 청정 접두 검사 무력화 → G10c 픽스처 발행(그 줄이 노출 엔진 자리의 '청정' 기록을 막는다)", paste(x$codes, collapse = "+")) }
m7 <- mut("m7", "if (!nzchar(er) || !identical(er, .rfg_rel(f, root)))", "if (FALSE)")
if (is.null(m7)) ng("M7 대상 줄(engine_rel 대조) 부재", "10-03 인터페이스 전 관문이면 기대된 부재") else {
  W7 <- mk_eng(CD, "# clean v2 — 청정 모드 재구현"); W7 <- mk_eng(CD, "# clean v2 — 청정 모드 재구현", prov_clean(W7$md5, engine_rel = sprintf("04_Research/strategies/%sOTHER/engine.R", CLP)))
  x <- elig(mk_entry("T_M7", W7$path, parent = "T_P"), extra = list(par), G = m7)
  chk(!held_vf(x), "M7 engine_rel 대조 무력화 → G10d 픽스처 발행(그 줄이 복사된 기록을 막는다)", paste(x$codes, collapse = "+")) }

unlink(c(S, S8), recursive = TRUE)
cat(sprintf("\n결과: PASS %d · FAIL %d · SKIP %d\n", PASS, FAIL, SKIP))
cat(sprintf('{"test":"rf_a_gate_entry_base_flags","pass":%d,"fail":%d,"skipped":%d,"total":%d}\n', PASS, FAIL, SKIP, PASS + FAIL + SKIP))
quit(status = if (FAIL == 0L) 0L else 1L, save = "no")
