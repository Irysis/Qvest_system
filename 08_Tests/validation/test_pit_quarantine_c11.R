#!/usr/bin/env Rscript
#==============================================================================
# test_pit_quarantine_c11.R — PIT C11 봉쇄(안 A 0단계 · 2026-09-24) 양방향 검사
#
# 대상: 02_Infrastructure/validation/pit_quarantine.R (격리 목록 판독기)
#       02_Infrastructure/ops/rf_factor_arms.R::rf_factor_pool / rf_pick_factor_sets (B1 후보 풀 격리)
#       02_Infrastructure/reinforcement/rf_overlay_admit.R::rf_overlay_admit (생성 arm 격리 원천 참조 거부)
#       + 운영 봉쇄 상태(격리 목록이 active 일 때만): pg2 arm suspended · 카탈로그 15모듈 fr_eligible 해제 ·
#         l2_auto 정지 · 원장 pit_c11 표식 · b1_verify 가 격리 팩터 설계를 기각
# 왜: pit.md '위반 시 처리' 1·2단계(즉시 중단·결과 무효)를 코드 수리 전에 목록 파일로 집행한다. 목록을 아무도
#   안 읽으면 봉쇄는 선언뿐이다 — 소비자가 실제로 빼는지(양성 대조)와, 빼는 줄을 지우면 이 검사가 죽는지
#   (돌연변이 red)를 같이 잰다.
# 구성:
#   F  팩터 풀(합성 픽스처 root) — 목록 부재=포함(대조) · active=제외 · released=복귀 · 파손=stop · 판독기 부재=stop ·
#      시드 회전 전 구간에서 격리 팩터가 사슬에 안 들어온다
#   A  등재 관문(합성 샌드박스) — 청정 arm 등재(대조) · 격리 패널 참조 arm 거부(원장 사유 기록·카탈로그 무변경) ·
#      같은 arm 이 목록 released 면 등재(거부 원인이 격리임을 증명) · 대소문자 무시 · 단어 경계(compare_mrs 오탐 0) ·
#      참조가 .arm.json(external_data)에만 있어도 거부(A9) · 목록 파손=거부
#   L  운영 상태(격리 항목 status=active 일 때만 · 해제 후엔 SKIP — 해제 절차가 이 검사를 깨지 않게)
#      L11~L13 = C11-F1 수리 재현(적대 검증 F1): 운영 목록이 우회 변형 21종(fred_macro*·pg2 파일·M4gAE·AE/m4 디렉터리·
#      JM_State·regime_current·regime_forecast·FRED_MRS·RCMA · 엔진 globalenv 의 load_macro_regime/FRED_*_CACHE/
#      REGIME_SIGNAL_CACHE · regime_signal.R · ctx macro provider)을 잡고 국내 패널·등재 arm 은 0 적중 · E2E REJECT 3 + 청정 ADMIT ·
#      수리 정규식(amend C11-F1)을 뺀 목록 사본이면 red(데이터 돌연변이)
#   M  돌연변이(자식 Rscript · PITQ_SRC_* = 변형 사본 · PITQ_CORE_ONLY=1 로 F/A 만) — 필터 줄 삭제 · 판독기 부재 fail-open ·
#      파손 fail-open · status 필터 제거 · 대소문자 구분 · 등재 관문 제거 · 관문이 .arm.json 을 안 읽음(M7) → red. 원본 사본(대조) → green.
# 격리: F/A 는 tempdir 픽스처만 쓴다. L 은 운영 파일을 **읽기만** 한다(b1_verify 자식의 jlog 는 임시 파일).
# env: PITQ_SRC_FACTOR_ARMS · PITQ_SRC_READER · PITQ_SRC_ADMIT (검사 대상 소스 · 기본 운영 파일) · PITQ_CORE_ONLY=1
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC_ARMS  <- Sys.getenv("PITQ_SRC_FACTOR_ARMS", file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R"))
SRC_READ  <- Sys.getenv("PITQ_SRC_READER",      file.path(ROOT, "02_Infrastructure/validation/pit_quarantine.R"))
SRC_ADMIT <- Sys.getenv("PITQ_SRC_ADMIT",       file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_admit.R"))
CORE <- identical(Sys.getenv("PITQ_CORE_ONLY"), "1")
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
sk <- function(m) { SKIP <<- SKIP + 1L; cat("  SKIP", m, "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
TMP0 <- file.path(tempdir(), sprintf("pitq_c11_%d", Sys.getpid())); dir.create(TMP0, recursive = TRUE, showWarnings = FALSE)
wj <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null")), p, useBytes = TRUE) }
qdoc <- function(status = "active", factors = list(), sources = list())
  list(schema = "pit_quarantine_v1", quarantines = list(list(id = "PITQ-FIX", code = "C11", flag = "pit_c11",
       status = status, factors = factors, sources = sources)))

# ── F. 팩터 풀 (합성 픽스처 root) ────────────────────────────────────────────
cat("=== F. B1 후보 풀 격리 (rf_factor_pool · rf_pick_factor_sets) ===\n")
mk_froot <- function(tag, with_reader = TRUE) {
  R <- file.path(TMP0, paste0("f_", tag)); unlink(R, recursive = TRUE)
  ids <- c("F_A", "F_B", "F_C", "F_Q"); cats <- c("value", "quality", "momentum", "regime")
  wj(list(factors = setNames(lapply(seq_along(ids), function(i) list(category = cats[i], ic_all = 0.01 * i,
       ic_screen_tier = "S1", lifecycle_status = "active")), ids)), file.path(R, "06_Registry/factor_evidence.json"))
  wj(list(factors = setNames(lapply(ids, function(i) list(panel_axis = "cross_sectional")), ids)),
     file.path(R, "06_Registry/factor_panel_axis.json"))
  wj(setNames(lapply(ids, function(i) list(lifecycle = list(status = "active"))), ids),
     file.path(R, ".cache/factor_db/factor_registry.json"))
  set.seed(7); d <- seq(as.Date("2020-01-31"), by = "month", length.out = 36)
  IC <- rbindlist(lapply(ids, function(f) data.table(Factor_Name = f, Date = d, IC = rnorm(length(d), 0.01, 0.05))))
  arrow::write_parquet(IC, file.path(R, ".cache/factor_db/factor_ic_monthly.parquet"))
  if (with_reader) { dir.create(file.path(R, "02_Infrastructure/validation"), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(SRC_READ, file.path(R, "02_Infrastructure/validation/pit_quarantine.R"), overwrite = TRUE)) }
  R
}
FE <- new.env(parent = globalenv())
invisible(capture.output(suppressMessages(sys.source(SRC_ARMS, envir = FE))))
NOREADER <- file.path(TMP0, "no_reader_code_root"); dir.create(NOREADER, showWarnings = FALSE)
FE$.RFF_ROOT <- NOREADER            # 코드 루트 폴백을 막는다 — 판독기는 픽스처 root 의 사본(검사 대상 SRC_READ)만
pool_ids <- function(R) FE$rf_factor_pool(R)$pool$id
QP <- function(R) file.path(R, "06_Registry/pit_quarantine.json")

R1 <- mk_froot("base")
p0 <- tryCatch(pool_ids(R1), error = function(e) paste("ERR", conditionMessage(e)))
chk(setequal(p0, c("F_A", "F_B", "F_C", "F_Q")), "F1 대조 — 목록 부재면 F_Q 포함(4종)", paste(p0, collapse = ","))
wj(qdoc(factors = list(list(id = "F_Q"))), QP(R1))
P1 <- tryCatch(FE$rf_factor_pool(R1), error = function(e) NULL)
chk(!is.null(P1) && setequal(P1$pool$id, c("F_A", "F_B", "F_C")) && identical(P1$excluded_pit, "F_Q"),
    "F2 active 격리 → F_Q 제외 · 나머지 3종 유지 · excluded_pit 기록", paste(P1$pool$id, collapse = ","))
wj(qdoc(status = "released", factors = list(list(id = "F_Q"))), QP(R1))
chk(setequal(tryCatch(pool_ids(R1), error = function(e) ""), c("F_A", "F_B", "F_C", "F_Q")),
    "F3 status=released → F_Q 복귀(해제는 status 로)")
writeLines("{ broken json", QP(R1))
e4 <- err_of(pool_ids(R1))
chk(!is.na(e4) && grepl("pit_quarantine", e4), "F4 목록 파손 → stop(조용한 해제 금지)", e4)
R5 <- mk_froot("noreader", with_reader = FALSE)
wj(qdoc(factors = list(list(id = "F_Q"))), QP(R5))
e5 <- err_of(pool_ids(R5))
chk(!is.na(e5) && grepl("판독기", e5), "F5 목록은 있는데 판독기 부재 → stop", e5)
unlink(QP(R5)); chk("F_Q" %in% tryCatch(pool_ids(R5), error = function(e) ""), "F5b 판독기·목록 둘 다 부재 → 격리 0(F_Q 포함)")
seen <- function(R) unique(unlist(lapply(0:3, function(o) tryCatch(
  FE$rf_pick_factor_sets(4L, seed_offset = o, depths = 1:4, root = R)$picked_ids, error = function(e) "ERR"))))
unlink(QP(R1)); s0 <- seen(R1)
chk("F_Q" %in% s0 && !("ERR" %in% s0), "F6 대조 — 목록 없으면 시드 회전 중 F_Q 가 사슬에 든다", paste(s0, collapse = ","))
wj(qdoc(factors = list(list(id = "F_Q"))), QP(R1)); s1 <- seen(R1)
chk(!("F_Q" %in% s1) && length(s1) >= 3L && !("ERR" %in% s1), "F6 격리 → 전 시드 오프셋(0..3)에서 F_Q 미선정", paste(s1, collapse = ","))

# ── A. 등재 관문 (합성 샌드박스) ─────────────────────────────────────────────
cat("=== A. 생성 arm 등재 관문 (rf_overlay_admit · 격리 원천 참조 거부) ===\n")
SB <- file.path(TMP0, "admit_sb"); unlink(SB, recursive = TRUE)
for (d in c("02_Infrastructure/reinforcement/overlay_arms", "02_Infrastructure/portfolio", "02_Infrastructure/validation", "06_Registry"))
  dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
stopifnot(file.copy(file.path(ROOT, "02_Infrastructure/reinforcement/overlay_probe.R"), file.path(SB, "02_Infrastructure/reinforcement/overlay_probe.R")),
          file.copy(SRC_ADMIT, file.path(SB, "02_Infrastructure/reinforcement/rf_overlay_admit.R")),
          file.copy(file.path(ROOT, "02_Infrastructure/portfolio/weight_catalog.R"), file.path(SB, "02_Infrastructure/portfolio/weight_catalog.R")),
          file.copy(SRC_READ, file.path(SB, "02_Infrastructure/validation/pit_quarantine.R")))
CAT <- file.path(SB, "06_Registry/overlay_catalog.json"); LEDP <- file.path(SB, "06_Registry/overlay_arm_ledger.jsonl")
wj(list(schema = "overlay_catalog_v1", note = "fixture", families = list(vol_target = "fixture"), arms = list()), CAT)
QS <- list(list(regex = "\\bm4_published\\b"), list(regex = "\\bbear_?prob"), list(regex = "\\bRE_MRS\\b"))
wj(qdoc(sources = QS), QP(SB))
ADIR <- file.path(SB, "02_Infrastructure/reinforcement/overlay_arms")
mk_arm <- function(kind, extra = character(0)) {
  writeLines(c(extra, sprintf("overlay_expo_%s <- function(H, t, ctx) {", kind),
               "  h <- H$rv60[is.finite(H$rv60)]", "  if (length(h) < 24L) return(1)",
               "  v <- H$rv60[t]", "  if (!is.finite(v) || v <= 0) return(1)",
               "  max(0, min(1, stats::median(h) / v))", "}"), file.path(ADIR, paste0(kind, ".R")))
  wj(list(id = paste0(kind, "_v1"), family = "vol_target", state = "vol", basis = "fixture — 확장창 중앙 변동성 대비", est_cost_min = 1),
     file.path(ADIR, paste0(kind, ".arm.json")))
}
in_cat <- function(id) any(vapply(fromJSON(CAT, simplifyVector = FALSE)$arms, function(a) identical(as.character(a$id), id), logical(1)))
last_rec <- function() { ln <- readLines(LEDP, warn = FALSE); ln <- ln[nzchar(ln)]; fromJSON(ln[length(ln)], simplifyVector = FALSE) }
AE <- new.env(parent = globalenv())
invisible(capture.output(suppressMessages(sys.source(file.path(SB, "02_Infrastructure/reinforcement/rf_overlay_admit.R"), envir = AE))))
adm <- function(kind) { r <- NULL; invisible(capture.output(r <- AE$rf_overlay_admit(kind, target = list(action = "scalar_exposure", state = "vol"),
                                                                                      root = SB, source = "test_pitq"))); r }
mk_arm("zzq_clean"); r <- adm("zzq_clean")
chk(isTRUE(r$ok) && in_cat("zzq_clean_v1"), "A1 대조 — 청정 arm 은 등재된다(probe 통과 · 격리 원천 0)", as.character(r$reason %||% ""))
# ★R3R(2026-09-25): 구판은 file.path(Sys.getenv("QM_ROOT"), …) — Sys.getenv 는 probe ③d 허용 목록 밖(능력 계열)이라 A4(released 면 등재)가
#   격리 목록이 아닌 ③d 에서 거부됐다. 이 절은 격리 목록의 원천 참조 판정만 재므로 허용 목록 안 형태(file.path 문자열)로 참조한다.
TAINT <- '.PANEL <- file.path("06_Registry", "m4_published/m4_panel_published.parquet")'
mk_arm("zzq_m4", TAINT); r <- adm("zzq_m4"); lr <- last_rec()
chk(!isTRUE(r$ok) && grepl("pit_quarantine", as.character(r$reason)) && !in_cat("zzq_m4_v1"),
    "A2 m4 발행 패널 참조 arm → 등재 거부 · 카탈로그 무변경", as.character(r$reason %||% ""))
chk(identical(lr$kind, "zzq_m4") && isFALSE(lr$probe$ok) && grepl("m4_published", lr$probe$reason, fixed = TRUE),
    "A3 거부 사유가 방출 원장에 남는다(probe.ok=false · 걸린 원천)", as.character(lr$probe$reason %||% ""))
wj(qdoc(status = "released", sources = QS), QP(SB)); mk_arm("zzq_m4b", TAINT); r <- adm("zzq_m4b")
chk(isTRUE(r$ok) && in_cat("zzq_m4b_v1"), "A4 같은 참조 arm 이 목록 released 면 등재 — 거부 원인은 격리 목록이다(probe 아님)",
    as.character(r$reason %||% ""))
wj(qdoc(sources = QS), QP(SB))
mk_arm("zzq_bear", '# Bear_Prob 게이트를 곱한다 (JM 국면 확률)'); r <- adm("zzq_bear")
chk(!isTRUE(r$ok) && !in_cat("zzq_bear_v1"), "A5 대소문자 무시 — 'Bear_Prob' 가 \\bbear_?prob 에 걸린다", as.character(r$reason %||% ""))
mk_arm("zzq_word", 'compare_mrs <- function(x) x  # RE_MRS 가 아니라 compare_mrs'); r <- adm("zzq_word")
chk(!isTRUE(r$ok), "A6 주석 속 격리 열 이름(RE_MRS)도 참조로 센다(보수적)", as.character(r$reason %||% ""))
mk_arm("zzq_word2", 'compare_mrs <- function(x) x'); r <- adm("zzq_word2")
chk(isTRUE(r$ok) && in_cat("zzq_word2_v1"), "A7 단어 경계 — compare_mrs 는 \\bRE_MRS\\b 오탐 아님(등재)", as.character(r$reason %||% ""))
## A9 (2026-09-24 C11-F1 수리) — 참조가 <kind>.arm.json 에만 있어도 거부. B5 설계 레인은 외부 패널을 arm.json 의
##   external_data 로 신고한다 — 관문이 .R 만 읽으면 그 신고가 통과한다(적대 검증 2 X4 생존 돌연변이 · M7 이 잡는다).
mk_arm("zzq_json")
wj(list(id = "zzq_json_v1", family = "vol_target", state = "vol", basis = "fixture — 확장창 중앙 변동성 대비", est_cost_min = 1,
        external_data = "06_Registry/m4_published/m4_panel_published.parquet (홀딩월 시작 전 컷오프)"),
   file.path(ADIR, "zzq_json.arm.json")); r <- adm("zzq_json")
chk(!isTRUE(r$ok) && grepl("m4_published", as.character(r$reason), fixed = TRUE) && !in_cat("zzq_json_v1"),
    "A9 참조가 .arm.json(external_data)에만 있어도 거부 — 관문은 두 파일을 다 읽는다", as.character(r$reason %||% ""))
writeLines("{ broken", QP(SB)); mk_arm("zzq_broken"); r <- adm("zzq_broken")
chk(!isTRUE(r$ok) && grepl("판독 실패", as.character(r$reason)) && !in_cat("zzq_broken_v1"),
    "A8 목록 파손 → 청정 arm 도 거부(조용한 해제 금지)", as.character(r$reason %||% ""))

# ── L. 운영 봉쇄 상태 (격리 항목 active 일 때만 · 읽기 전용) ─────────────────
if (!CORE) {
  cat("=== L. 운영 봉쇄 상태 (PITQ-C11-20260924) ===\n")
  QL <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/pit_quarantine.json"), simplifyVector = FALSE), error = function(e) NULL)
  q <- if (is.null(QL)) NULL else Filter(function(x) identical(x$id, "PITQ-C11-20260924"), QL$quarantines)
  q <- if (length(q)) q[[1]] else NULL
  if (is.null(q)) ng("L0 운영 격리 목록에 PITQ-C11-20260924 없음")
  else if (!identical(q$status, "active")) sk(sprintf("L 운영 상태 — PITQ-C11-20260924 status=%s (해제됨 · 검사 생략)", q$status))
  else {
    QF <- vapply(q$factors, function(f) f$id, character(1))
    chk(setequal(QF, c("D32_Beta_VIX", "MA01_GDP_Sensitivity", "MA02_CPI_Sensitivity")), "L1 격리 팩터 3종(D32·MA01·MA02)")
    LE <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(SRC_ARMS, envir = LE))))
    PL <- tryCatch(LE$rf_factor_pool(ROOT), error = function(e) NULL)
    chk(!is.null(PL) && !any(QF %in% PL$pool$id) && setequal(PL$excluded_pit, QF) && nrow(PL$pool) >= 100L,
        sprintf("L2 운영 B1 풀에서 3종 제외(풀 %s종)", if (is.null(PL)) "NA" else nrow(PL$pool)))
    # 오버레이 arm
    OC <- fromJSON(file.path(ROOT, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)$arms
    pg <- Filter(function(a) identical(a$id, "pg2_risk_overlay_v1"), OC)
    chk(length(pg) == 1L && !identical(pg[[1]]$status, "active") && identical(pg[[1]]$status_before, "active"),
        "L3 pg2_risk_overlay_v1 status≠active · 원값 status_before=active 보존")
    OE <- new.env(parent = globalenv())
    invisible(capture.output(suppressMessages({
      sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), envir = OE)
      sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), envir = OE)
      sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R"), envir = OE)
      sys.source(file.path(ROOT, "02_Infrastructure/ops/rf_overlay_arms.R"), envir = OE) })))
    pk <- tryCatch(OE$rf_pick_overlay_arms(60L, root = ROOT)$picked_ids, error = function(e) "ERR")
    cb5 <- vapply(OE$rfbd_catalog("B5", ROOT), function(x) x$id, character(1))
    sc <- Filter(function(x) identical(x$overlay_pick, "pg2_risk_overlay_v1"), OE$rfbd_standing_cells(ROOT))
    dd <- if (length(sc)) OE$rf_standing_decision(sc[[1]], list(), NULL, OE$.rfbd_b5_raw(ROOT), TRUE) else list(insert = NA)
    chk(!("pg2_risk_overlay_v1" %in% pk) && !("ERR" %in% pk) && !("pg2_risk_overlay_v1" %in% cb5) &&
          isFALSE(dd$insert) && identical(dd$reason, "arm_not_active"),
        "L4 규칙 픽커·설계 카탈로그 제외 · 상주 칸 B5_31 새 entry 삽입 안 함(재설계 라운드 포함)", as.character(dd$reason %||% ""))
    # 모듈 카탈로그
    MC <- fromJSON(file.path(ROOT, "06_Registry/module_catalog.json"), simplifyVector = FALSE)$modules
    gl <- function(x, k) if (is.list(x)) x[[k]] else NULL          # 레코드마다 필드 형태가 다르다(문자열 contamination 등)
    tagged <- names(Filter(function(m) identical(gl(gl(m, "contamination"), "flag"), "pit_c11"), MC))
    QM <- vapply(q$modules, function(m) m$strategy_id, character(1))
    elig <- function(m) isTRUE(gl(m, "fr_eligible")) && identical(gl(m, "metric_type"), "backtested") && isTRUE(gl(gl(m, "contract"), "contract_pass"))
    chk(setequal(tagged, QM) && length(QM) == 15L && !any(vapply(MC[QM], elig, logical(1))) &&
          all(vapply(MC[QM], function(m) isTRUE(gl(m$contamination, "fr_eligible_before")) && identical(gl(m$contamination, "reason"), "pit_invalid:C11"), logical(1))),
        sprintf("L5 카탈로그 pit_c11 모듈 = 격리 목록 15개 · FR 계약 floor 탈락 · 원값 fr_eligible_before 보존(표식 %d)", length(tagged)))
    PGM <- names(Filter(function(m) grepl("pg2_risk_overlay_v1", as.character(gl(gl(m, "meta"), "strategy_idea") %||% "")[1], fixed = TRUE), MC))
    chk(!any(vapply(MC[PGM], elig, logical(1))), sprintf("L6 카탈로그에 FR 적격 pg2 모듈 0(전체 pg2 %d개 · 봉쇄 뒤 신규 등재 감시)", length(PGM)))
    # 2계층 레인
    LL <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/ops/rf_l2_lib.R"), envir = LL))))
    lc <- LL$l2_cfg(ROOT)
    chk(isFALSE(lc$enabled), "L7 l2_auto 레인 정지(l2_cfg()$enabled FALSE) — 격리 active 동안")
    # 원장 표식
    L1 <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
    f1 <- unlist(lapply(L1$entries, function(e) vapply(Filter(function(a)
      any(vapply(a$vintage_flags %||% list(), function(z) identical(z$flag, "pit_c11"), logical(1))), e$attempts %||% list()),
      function(a) paste(e$base_id, a$n), character(1))))
    exp1 <- c(vapply(q$ledger_marks$l1$ma01, function(x) paste(x[[1]], x[[2]]), character(1)),
              vapply(q$ledger_marks$l1$pg2, function(x) paste(x[[1]], x[[2]]), character(1)))
    chk(length(f1) == 35L && setequal(f1, exp1), sprintf("L8 L1 원장 pit_c11 표식 %d칸 = 격리 목록 35칸", length(f1)))
    L2 <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l2.json"), simplifyVector = FALSE)
    fr <- Filter(function(e) identical(e$base_id, "FR_003"), L2$entries)
    hasf <- function(fl) any(vapply(fl %||% list(), function(z) identical(z$flag, "pit_c11"), logical(1)))
    chk(length(fr) == 1L && hasf(fr[[1]]$base_vintage_flags) &&
          hasf((Filter(function(a) identical(as.integer(a$n), 1L), fr[[1]]$attempts)[[1]])$vintage_flags),
        "L9 L2 FR_003 n=1·base pit_c11 표식")
    # b1_verify 자식 — 격리 팩터 설계는 기각, 풀 팩터 설계는 통과(대조)
    ren <- file.path(TMP0, "empty.Renviron"); writeLines(character(0), ren)
    JL <- file.path(TMP0, "b1_jlog.jsonl")
    old <- Sys.getenv(c("R_ENVIRON_USER", "QVEST_RP_JLOG", "QVEST_RF_ROOT"), unset = NA)
    Sys.setenv(R_ENVIRON_USER = ren, QVEST_RP_JLOG = JL, QVEST_RF_ROOT = ROOT)     # Windows system2(env=) 는 무시된다
    vdes <- function(f) { p <- file.path(TMP0, sprintf("b1_%s.json", f))
      wj(list(cells = list(list(label = "fixture", factors = list(f)))), p)
      system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R")), "verify", "PITQ_TEST_BID", shQuote(p)),
              stdout = FALSE, stderr = FALSE) }
    rc_bad <- vdes("D32_Beta_VIX")
    ctl <- setdiff(PL$pool$id, QF)[1]
    rc_ok <- vdes(ctl)
    for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k))
    jl <- if (file.exists(JL)) readLines(JL, warn = FALSE) else character(0)
    chk(!identical(as.integer(rc_bad), 0L) && any(grepl("design_rejected", jl) & grepl("D32_Beta_VIX", jl, fixed = TRUE)),
        "L10 b1_verify — D32_Beta_VIX 설계 기각(등록부에 없는 팩터)", sprintf("rc=%s", rc_bad))
    chk(identical(as.integer(rc_ok), 0L), sprintf("L10b 대조 — 풀 팩터(%s) 설계는 통과", ctl), sprintf("rc=%s", rc_ok))
    # ── C11-F1 수리 재현 (적대 검증 1 F1 BLOCKING · 2026-09-24) ──────────────────
    #   구 목록은 실제 FRED 저장소(fred_macro*)·pg2 arm 파일 자체·파생 국면 패널(regime_jump_daily 등)을 못 잡아
    #   샌드박스 E2E 에서 우회 arm 3종이 ADMIT 됐다(scratchpad/c11_contain_verify_coverage/t_gate.R). 운영 목록으로 다시 잰다.
    RE <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(SRC_READ, envir = RE))))
    BYP <- c(
      fredwide_vix  = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/fred_macro_wide.parquet"); .COL <- "VIX"',
      fredwide_stl  = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/fred_macro_wide.parquet"); .COL <- c("StL_Fin_Stress","Chi_Fin_Cond","Init_Claims")',
      fredlong_nfci = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/fred_macro.parquet"); .ID <- c("NFCI","STLFSI4","ICSA")',
      fred_pin      = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/fred_macro_wide_pin20260718wt006.parquet")',
      jump_state    = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/regime_jump_daily.parquet"); .COL <- "JM_State"',
      regime_cur    = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/regime_current.json")',
      fcst_vix      = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/regime_forecast_series_v1vix.parquet")',
      src_pg2       = '.DEP <- file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/reinforcement/overlay_arms/pg2_risk_overlay.R")',
      call_pg2      = 'e <- overlay_expo_pg2_risk_overlay(H, t, ctx)',
      src_gen_m4gae = '.DEP <- file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R")',
      ae_monthly    = 'system2("python", "02_Infrastructure/regime/ae_regime_monthly.py")',
      m4_engine     = 'source("qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R")',
      fred_mrs      = 'x <- u$FRED_MRS',
      modperf       = 'mp <- jsonlite::fromJSON("06_Registry/module_performance.json")',
      rcma          = 'source("02_Infrastructure/portfolio/regime_module_admission.R")',
      # 같은 계열 — 엔진 globalenv 에 이미 있는 이름(run_paper_replication.R:57-61 이 config.R·backtest_harness.R 전역 source ·
      #   arm env 부모 = globalenv, rf_cell_engine.R:565)과 밑줄 결합 식별자: 파일명 없이 오염 패널에 닿는다
      g_load_macro  = 'm <- load_macro_regime()',
      g_fred_regime = 'm <- arrow::read_parquet(FRED_REGIME_CACHE)',
      g_regime_sig  = 'u <- arrow::read_parquet(REGIME_SIGNAL_CACHE)',
      src_regsig    = 'source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/regime/regime_signal.R")); u <- load_daily_regime_signal()',
      ctx_macro     = 'source("02_Infrastructure/methods/ctx_providers.R"); x <- build_ctx_extras(ctx$date, NULL)$macro',
      load_fred_d   = 'w <- load_fred_daily_wide()')
    CLN <- c(msm   = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/msm_daily_latest.parquet")',
             bench = '.P <- file.path(Sys.getenv("QM_ROOT"), ".cache/benchmark.parquet")',
             raw   = '.P <- ".cache/rawdata.parquet"; v <- H$rv60[t]')
    caught <- function(root) vapply(BYP, function(x) length(RE$pitq_source_hits(x, root)) > 0L, logical(1))
    c_live <- tryCatch(caught(ROOT), error = function(e) setNames(rep(NA, length(BYP)), names(BYP)))
    chk(all(c_live %in% TRUE),
        sprintf("L11 재현 — 운영 목록이 우회 변형 %d종 전부를 잡는다(fred_macro*·pg2 파일·M4gAE·AE/m4 디렉터리·JM_State·regime_current·regime_forecast·FRED_MRS·RCMA·전역 load_macro_regime/FRED_*_CACHE/REGIME_SIGNAL_CACHE·ctx macro)", length(BYP)),
        paste(names(BYP)[!(c_live %in% TRUE)], collapse = ","))
    # 대조: 국내 패널 + 등재된 운영 arm(pg2 제외 — 카탈로그 등재 kind 만 · 거부돼 남은 파일은 세지 않는다)은 0 적중
    reg_kinds <- setdiff(unique(vapply(OC, function(a) as.character(a$kind %||% "")[1], character(1))), c("", "pg2_risk_overlay"))
    armf <- file.path(ROOT, "02_Infrastructure/reinforcement/overlay_arms", c(paste0(reg_kinds, ".R"), paste0(reg_kinds, ".arm.json")))
    armf <- armf[file.exists(armf)]
    fp_cln <- names(CLN)[vapply(CLN, function(x) length(RE$pitq_source_hits(x, ROOT)) > 0L, logical(1))]
    fp_arm <- basename(armf)[vapply(armf, function(f) length(RE$pitq_source_hits(readLines(f, warn = FALSE, encoding = "UTF-8"), ROOT)) > 0L, logical(1))]
    chk(!length(fp_cln) && !length(fp_arm) && length(armf) >= 2L,
        sprintf("L11b 대조 — 국내 패널(msm·benchmark·rawdata)과 등재 arm %d파일(pg2 제외)은 0 적중(과잉 봉쇄 없음)", length(armf)),
        paste(c(fp_cln, fp_arm), collapse = ","))
    # L12 E2E — 운영 목록 사본을 A 샌드박스에 깔고 검증자가 ADMIT 시킨 3변형을 다시 등재 시도
    stopifnot(file.copy(file.path(ROOT, "06_Registry/pit_quarantine.json"), QP(SB), overwrite = TRUE))
    e2e <- vapply(c("fredwide_vix", "src_pg2", "jump_state"), function(k) {
      kd <- paste0("zzl_", k); mk_arm(kd, BYP[[k]]); r <- adm(kd)
      !isTRUE(r$ok) && grepl("pit_quarantine", as.character(r$reason %||% "")) && !in_cat(paste0(kd, "_v1")) }, logical(1))
    mk_arm("zzl_clean"); rcl <- adm("zzl_clean")
    chk(all(e2e) && isTRUE(rcl$ok) && in_cat("zzl_clean_v1"),
        "L12 E2E 재현 — 운영 목록으로 fred_macro_wide(VIX)·pg2 source·JM_State 변형 REJECT · 청정 대조 ADMIT",
        paste(c(names(e2e)[!e2e], if (!isTRUE(rcl$ok)) paste("clean:", as.character(rcl$reason %||% ""))), collapse = ","))
    # L13 돌연변이(데이터) — 수리 정규식(amend C11-F1)을 뺀 목록 사본이면 L11 이 red 여야 한다(검사가 수리를 실제로 잰다)
    MR <- file.path(TMP0, "mut_list_root")
    QM0 <- fromJSON(file.path(ROOT, "06_Registry/pit_quarantine.json"), simplifyVector = FALSE)
    QM0$quarantines <- lapply(QM0$quarantines, function(x) {
      x$sources <- Filter(function(s) !identical(s$amend, "C11-F1"), x$sources %||% list()); x })
    wj(QM0, QP(MR))
    c_mut <- tryCatch(caught(MR), error = function(e) setNames(rep(NA, length(BYP)), names(BYP)))
    n_amend <- sum(vapply(q$sources, function(s) identical(s$amend, "C11-F1"), logical(1)))
    chk(n_amend >= 1L && !all(c_mut %in% TRUE) && !any(c_mut[c("fredwide_vix", "src_pg2", "jump_state")] %in% TRUE),
        sprintf("L13 돌연변이 — 수리 정규식(amend C11-F1 %d개)을 뺀 목록이면 우회 %d종이 다시 통과 → L11 red",
                n_amend, sum(!(c_mut %in% TRUE))))
  }
}

# ── M. 돌연변이 (자식 Rscript · F/A 만) ──────────────────────────────────────
if (!CORE) {
  cat("=== M. 돌연변이 — 봉쇄 줄을 지우면 이 검사가 red 여야 한다 ===\n")
  self <- local({ a <- grep("^--file=", commandArgs(FALSE), value = TRUE); if (length(a)) sub("^--file=", "", a[1]) else
                   file.path(ROOT, "08_Tests/validation/test_pit_quarantine_c11.R") })
  ren <- file.path(TMP0, "empty.Renviron"); writeLines(character(0), ren)
  mut <- function(src, old, new, tag) {
    t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    if (!grepl(old, t, fixed = TRUE)) return(NA_character_)
    p <- file.path(TMP0, sprintf("mut_%s_%s", tag, basename(src))); writeLines(enc2utf8(sub(old, new, t, fixed = TRUE)), p, useBytes = TRUE); p }
  run_child <- function(arms = SRC_ARMS, reader = SRC_READ, admit = SRC_ADMIT) {
    old <- Sys.getenv(c("PITQ_SRC_FACTOR_ARMS", "PITQ_SRC_READER", "PITQ_SRC_ADMIT", "PITQ_CORE_ONLY", "R_ENVIRON_USER"), unset = NA)
    Sys.setenv(PITQ_SRC_FACTOR_ARMS = arms, PITQ_SRC_READER = reader, PITQ_SRC_ADMIT = admit, PITQ_CORE_ONLY = "1", R_ENVIRON_USER = ren)
    rc <- system2("Rscript", shQuote(self), stdout = FALSE, stderr = FALSE)
    for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k))
    as.integer(rc) }
  rc0 <- run_child()
  chk(identical(rc0, 0L), "M0 대조 — 원본 사본으로 자식 F/A 가 green", sprintf("rc=%s", rc0))
  MUTS <- list(
    list("M1 풀 필터 줄 삭제(rf_factor_arms)", "arms", SRC_ARMS, "  keep <- keep & !(ids %in% pitq)\n", "\n"),
    list("M2 판독기 부재 fail-open(rf_factor_arms)", "arms", SRC_ARMS,
         "      stop(\"[rf_factor_arms] pit_quarantine.json 은 있는데 판독기(pit_quarantine.R)가 없다 — 격리를 건너뛰지 않는다\")",
         "      return(character(0))"),
    list("M3 목록 파손 fail-open(판독기)", "reader", SRC_READ, "  if (inherits(d, \"error\"))\n    stop(", "  if (inherits(d, \"error\")) return(list())\n  if (FALSE)\n    stop("),
    list("M4 status 필터 제거(판독기)", "reader", SRC_READ, "identical(as.character(.pitq_or(x$status, \"active\"))[1], \"active\")", "TRUE"),
    list("M5 대소문자 구분(판독기)", "reader", SRC_READ, "perl = TRUE, ignore.case = TRUE", "perl = TRUE, ignore.case = FALSE"),
    list("M6 등재 관문 제거(rf_overlay_admit)", "admit", SRC_ADMIT, "  .qh <- .rfa_pitq_hits(kind, root)\n", "  .qh <- character(0)\n"),
    list("M7 관문이 .arm.json 을 안 읽음(rf_overlay_admit)", "admit", SRC_ADMIT, "paste0(kind, c(\".R\", \".arm.json\"))", "paste0(kind, c(\".R\"))"))
  for (m in MUTS) {
    p <- mut(m[[3]], m[[4]], m[[5]], sub(" .*", "", m[[1]]))
    if (is.na(p)) { ng(m[[1]], "돌연변이 앵커 부재 — 검사가 소스를 못 따라간다"); next }
    rc <- switch(m[[2]], arms = run_child(arms = p), reader = run_child(reader = p), admit = run_child(admit = p))
    chk(!identical(rc, 0L), paste0(m[[1]], " → red"), sprintf("rc=%s (0 이면 검사가 이 돌연변이를 못 잡는다)", rc))
  }
}

unlink(TMP0, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d · 생략 %d\n", PASS, FAIL, SKIP))
cat(sprintf('{"test":"pit_quarantine_c11","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', PASS, FAIL, PASS + FAIL, SKIP))
quit(status = if (FAIL == 0L) 0L else 1L)
