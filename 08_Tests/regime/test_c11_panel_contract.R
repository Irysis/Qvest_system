#!/usr/bin/env Rscript
# =============================================================================
# test_c11_panel_contract.R — PIT C11 r1: 국면 패널 '표식 계약' 통일 · POSIXct 가용일 · epoch · 빈티지 라벨 (양방향)
# =============================================================================
# 막는 결함(통합 검증·V4·V5 BLOCKING):
#   G  overlay_pit_guard C11 층 — (a) POSIXct avail_date 를 가용일로 받아 as.Date(UTC)에서 하루 앞당겨진 날로 결합하고
#      HARD 검사도 통과했다(V4 B2). (b) 표식 epoch(규칙 키)를 보지 않아 규칙이 바뀐 뒤의 옛 판을 수리판으로 받았다.
#      (c) 창 시작이 주말 행이면 토요일 가용 행이 월요일 수익 창에 들어갈 수 있다(통합 (2)-3).
#   L  regime_label_gate — 월말 라벨 구성(monthly_prev/same)을 가용일 열만 보고 avail_annotated 로 표식(V4 잠재).
#   M  m4 엔진(factor_engine.R) — 생산자 regime_signal 이 싣는 avail_date + c11_regime_key 를 행 컷오프로 받지 못해
#      수리 뒤에도 m4 가 영구 '미해소'(통합 (2)-1 표식 계약 넷).
#   A  AE 표식(ae_pit_features.stamp) — STLFSI4·NFCI 의 vintage_resolved=FALSE 를 버렸다(V5 B2) → 빈티지 라벨 3열.
# 방법: 합성 픽스처(손 유도 기대값) + 대상 파일 사본에 돌연변이를 넣어 같은 픽스처에서 빨개지는지 잰다.
# 쓰기: tempdir() 만. 운영 파일은 읽기만(대상 소스·규칙 파일).
# 실행: Rscript 08_Tests/regime/test_c11_panel_contract.R   (R_ENVIRON_USER=<빈 파일> 권장)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) normalizePath(f[1], winslash = "/", mustWork = TRUE) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
GUARD <- file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R")
RLG   <- file.path(ROOT, "02_Infrastructure/contracts/regime_label_gate.R")
FE    <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R")
AEPF  <- file.path(ROOT, "02_Infrastructure/regime/ae_pit_features.py")
HELP  <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
RULES <- file.path(ROOT, "06_Registry/fred_availability_rules.json")

P <- 0L; FL <- 0L; SKIPS <- list()
ok <- function(c, m) { if (isTRUE(c)) { P <<- P + 1L; cat("  PASS ", m, "\n") } else { FL <<- FL + 1L; cat("  FAIL ", m, "\n") } }
skip <- function(axis, reason) { SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason); cat("  SKIP ", axis, "—", reason, "\n") }
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
TD <- normalizePath(file.path(tempdir(), paste0("c11pc_", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
mutant <- function(src, old, new, tag) {
  t <- paste(readLines(src, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (lengths(regmatches(t, gregexpr(old, t, fixed = TRUE))) != 1L) return(NA_character_)
  f <- file.path(TD, paste0(tag, "_", basename(src))); writeLines(sub(old, new, t, fixed = TRUE), f, useBytes = TRUE); f
}
load_guard <- function(f) { e <- new.env(parent = globalenv()); suppressMessages(sys.source(f, envir = e)); e }
for (p in c(GUARD, RLG, FE, AEPF, HELP, RULES)) ok(file.exists(p), paste("존재", basename(p)))

Sys.setenv(QM_ROOT = ROOT)                                   # c11_rules_key() 가 이 트리의 규칙 파일을 읽게
source(HELP); options(fred_avail.root = ROOT)
CUR <- fred_avail_rules_meta(RULES)$regime_key
OLD <- "c11_avail:2026-09-24.b1:78c87534"

# ── G. 가드 ─────────────────────────────────────────────────────────────────
cat("\n── G. overlay_pit_guard C11 층 ──\n")
d0 <- as.Date("2020-03-13") + 0:4
mk <- function(avail) data.table(Date = d0, v = 1:5, avail_date = avail)
PX <- mk(as.POSIXct(format(d0 + 1L), tz = "Asia/Seoul"))            # 한국 자정 POSIXct → UTC as.Date 는 하루 이르다
PD <- mk(d0 + 1L)
checks_G <- function(G) {
  r <- list()
  r$G1a <- is.na(G$c11_panel_avail_col(PX, "v"))
  r$G1b <- grepl("C11", err_of(G$c11_legacy_gate(PX, "v", "t", policy = "stop")))
  r$G1c <- grepl("Date 형", err_of(G$c11_asof_align(as.Date("2020-03-16"), PX, "v", avail_col = "avail_date")), fixed = TRUE)
  r$G2a <- identical(G$c11_panel_status(PD, "v"), "avail_annotated")
  p <- copy(PD); p[, c11_regime_key := CUR]; r$G2b <- identical(G$c11_panel_status(p, "v"), "avail_annotated")
  p <- copy(PD); setattr(p, "c11_avail_regime_key", CUR); r$G2c <- identical(G$c11_panel_status(p, "v"), "avail_annotated")
  p <- copy(PD); p[, c11_regime_key := OLD]
  r$G2d <- identical(G$c11_panel_status(p, "v"), "stale_epoch") && grepl("epoch", err_of(G$c11_legacy_gate(p, "v", "t", policy = "stop")))
  p <- copy(PD); setattr(p, "c11_avail_regime_key", OLD); r$G2e <- identical(G$c11_panel_status(p, "v"), "stale_epoch")
  p <- copy(PD); p[, c11_regime_key := NA_character_]; r$G2f <- identical(G$c11_panel_status(p, "v"), "stale_epoch")
  a <- G$c11_asof_align(as.Date("2020-03-16"), PD, "v")                # 가용일 ≤ 03-16 중 최신 = 03-13 행(가용 03-14)… 03-15 행(가용 03-16)
  r$G3a <- identical(as.character(a$src_date), "2020-03-15")
  ws <- G$c11_window_start(as.Date(c("2020-03-13", "2020-03-15", "2020-03-16")),
                           kr_calendar = as.Date(c("2020-03-12", "2020-03-13", "2020-03-16")))
  r$G4a <- identical(as.character(ws), c(NA, "2020-03-13", "2020-03-13"))  # 일요일 03-15 → 금 03-13
  r$G4b <- identical(as.character(G$c11_window_start(as.Date(c("2020-03-13", "2020-03-16")))), c(NA, "2020-03-13"))  # 달력 없으면 구판 동작
  r
}
G <- load_guard(GUARD); rG <- checks_G(G)
lab <- c(G1a = "POSIXct avail_date → 가용일 열로 인정하지 않음(NA)", G1b = "POSIXct 패널 → legacy 관문 중단(stop 정책)",
         G1c = "c11_asof_align 에 POSIXct 가용일 열을 명시해도 거부", G2a = "Date 가용일 · 키 없음(메모리 패널) → annotated",
         G2b = "행 키 = 현행 → annotated", G2c = "속성 키 = 현행 → annotated", G2d = "행 키 = 옛 epoch → stale_epoch · 관문 중단",
         G2e = "속성 키 = 옛 epoch → stale_epoch", G2f = "행 키 NA → stale(미해석 = 통과 아님)", G3a = "Date 가용일 결합 손 유도(03-16 결정 → 03-15 행)",
         G4a = "창 시작 한국 거래일 내림(일요일 → 금요일)", G4b = "kr_calendar 없으면 구판 창 시작 그대로")
for (k in names(lab)) ok(isTRUE(rG[[k]]), paste(k, lab[[k]]))
mutG <- list(
  list(tag = "gm_posix", old = "return(if (inherits(panel[[cand]], \"Date\")) cand else NA_character_)", new = "return(cand)", want = c("G1a", "G1b")),
  list(tag = "gm_epoch", old = "if (is.na(cur) || anyNA(k) || !all(k == cur)) \"stale\" else \"current\"", new = "\"current\"", want = c("G2d", "G2e", "G2f")),
  list(tag = "gm_snap", old = "    out <- .c11_date(snap)\n", new = "\n", want = c("G4a")),
  list(tag = "gm_align", old = "  if (!is.na(ac) && ac %in% names(panel) && !inherits(panel[[ac]], \"Date\"))", new = "  if (FALSE)", want = c("G1c")))
for (mu in mutG) {
  f <- mutant(GUARD, mu$old, mu$new, mu$tag)
  if (is.na(f)) { ok(FALSE, sprintf("G-mut %s 대상 줄 부재", mu$tag)); next }
  rm_ <- tryCatch(checks_G(load_guard(f)), error = function(e) list())
  red <- mu$want[!vapply(mu$want, function(k) isTRUE(rm_[[k]]), logical(1))]
  ok(length(red) == length(mu$want), sprintf("G-mut %s ★red: %s (빨강 %s)", mu$tag, paste(mu$want, collapse = ","), paste(red, collapse = ",")))
}

# ── L. regime_label_gate 월말 라벨 구성의 표식 ────────────────────────────────
cat("\n── L. regime_label_gate ──\n")
PL <- file.path(TD, "projL"); dir.create(file.path(PL, ".cache"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(PL, "02_Infrastructure/validation"), recursive = TRUE, showWarnings = FALSE)
file.copy(GUARD, file.path(PL, "02_Infrastructure/validation/overlay_pit_guard.R"), overwrite = TRUE)
me <- seq(as.Date("2019-02-01"), by = "month", length.out = 24) - 1L
UM <- data.table(Date = me, YM = format(me, "%Y-%m"), Category = rep(c("RISK_ON", "RISK_OFF"), 12),
                 avail_date = me - 1L, c11_regime_key = CUR)
write_parquet(UM, file.path(PL, ".cache/unified_regime_signal.parquet"))
bd <- seq(as.Date("2019-01-01"), as.Date("2020-12-31"), by = "day"); bd <- bd[as.POSIXlt(bd)$wday %in% 1:5]
write_parquet(data.table(Date = bd, BM_Ret = 0.001), file.path(PL, ".cache/benchmark.parquet"))
rlg_status <- function(src, basis) {
  e <- new.env(parent = globalenv()); suppressMessages(sys.source(src, envir = e))
  pn <- tryCatch(e$regime_label_monthly_panel(PL, refresh = TRUE, label_basis = basis), error = function(err) NULL)
  if (is.null(pn)) NA_character_ else as.character(attr(pn, "pit_c11"))
}
s_prev <- rlg_status(RLG, "monthly_prev"); s_same <- rlg_status(RLG, "monthly_same")
ok(!identical(s_prev, "avail_annotated") && grepl("unresolved", s_prev), sprintf("L1 monthly_prev(월말 라벨 구성) 표식 ≠ avail_annotated — %s", s_prev))
ok(!identical(s_same, "avail_annotated") && grepl("unresolved", s_same), sprintf("L2 monthly_same 표식 ≠ avail_annotated — %s", s_same))
fL <- mutant(RLG, "    if (label_basis %in% c(\"monthly_prev\", \"monthly_same\")) \"unresolved_label_basis(월말 라벨 구성 — 가용일 미사용 · V4 소견)\" else\n", "", "lm_basis")
if (is.na(fL)) ok(FALSE, "L-mut 대상 줄 부재") else
  ok(identical(rlg_status(fL, "monthly_prev"), "avail_annotated"), "L-mut ★red: 구성 분기 삭제 → monthly_prev 가 avail_annotated 로 오표식")

# ── M. m4 엔진 load_macro_regime — 생산자 avail_date + c11_regime_key 를 행 컷오프로 ────────────
cat("\n── M. m4 엔진(factor_engine.R) 표식 판독 ──\n")
PM <- file.path(TD, "projM"); dir.create(file.path(PM, ".cache"), recursive = TRUE, showWarnings = FALSE)
UM2 <- data.table(Date = me, YM = format(me, "%Y-%m"), Regime_Score = 40, Category = "NEUTRAL", Cash_Pct = 0,
                  MSM_Crisis_Prob = 0.1, FRED_MRS = 20, KTRI_Score = 50, VEA_Score = 50,
                  avail_date = me - 2L, c11_regime_key = CUR)
write_parquet(UM2, file.path(PM, ".cache/unified_regime_signal.parquet"))
fe_env <- function(src) {
  ex <- parse(src, keep.source = FALSE, encoding = "UTF-8")
  e <- new.env(parent = globalenv()); assign("PROJECT_ROOT", PM, envir = e)
  for (x in ex) if (is.call(x) && as.character(x[[1]]) %in% c("<-", "=") && is.name(x[[2]]) &&
                    as.character(x[[2]]) %in% c("C11_CUTOFF_COL", "C11_KEY_COL", "C11_FILE_STAMP_KEY", "C11_FILE_STAMP_PREFIX",
                                               "c11_file_stamp", "load_macro_regime")) eval(x, e)
  e
}
m_cut <- function(src) { e <- fe_env(src); x <- NULL
  invisible(capture.output(x <- tryCatch(suppressMessages(e$load_macro_regime()), error = function(err) NULL))); x }
X <- m_cut(FE)
ok(!is.null(X) && identical(as.integer(X$reg_c11_cutoff), as.integer(me - 2L)) && all(X$reg_c11_key == CUR),
   "M1 unified 월간 avail_date(+c11_regime_key) → 행 컷오프 = avail_date(말일 −2) · 키 = 현행")
fM <- mutant(FE, "  has_avail <- !has_c11 && all(c(\"avail_date\", C11_KEY_COL) %in% names(dt)) && inherits(dt[[\"avail_date\"]], \"Date\")",
             "  has_avail <- FALSE", "fm_alias")
if (is.na(fM)) ok(FALSE, "M-mut 대상 줄 부재") else {
  XM <- m_cut(fM)
  ok(is.null(XM) || !identical(as.integer(XM$reg_c11_cutoff), as.integer(me - 2L)), "M-mut ★red: 계약 열 판독 삭제 → 컷오프가 avail_date 가 아니다")
}
fe_txt <- paste(readLines(FE, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
ok(grepl("PASS_AVAIL · VINTAGE_UNRESOLVED", fe_txt, fixed = TRUE) && !grepl("sprintf(\"PASS — 국면 사용", fe_txt, fixed = TRUE),
   "M2 C11_overseas_availability 가 빈티지 미해소를 함께 싣는다(맨 'PASS' 아님 · V5)")

# ── A. AE 표식 빈티지 라벨(파이썬) ───────────────────────────────────────────
cat("\n── A. AE stamp 빈티지 라벨 ──\n")
PY <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")          # pandas·pyarrow 가 있는 venv 우선(QVEST_PY 는 pandas 없을 수 있음)
if (!file.exists(PY)) PY <- Sys.getenv("QVEST_PY", "")
if (!file.exists(PY)) skip("A", "파이썬(venv) 부재") else {
  run_py <- function(aepf_path) {
    code <- c("import sys, importlib.util, json", "import pandas as pd",
              sprintf("sys.path.insert(0, r'%s')", file.path(ROOT, "02_Infrastructure/data")),
              sprintf("spec = importlib.util.spec_from_file_location('aepf_t', r'%s')", aepf_path),
              "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)",
              "panel = pd.DataFrame({'Date': pd.to_datetime(['2020-01-02','2020-01-03','2020-01-06']),",
              "                      'c11_row_avail_max': pd.to_datetime(['2020-01-02','2020-01-03','2020-01-06']),",
              "                      'c11_vintage_unresolved': 'NFCI,STLFSI4'})",
              "df = pd.DataFrame({'decision_date': pd.to_datetime(['2020-01-07']), 'last_feat_date': pd.to_datetime(['2020-01-06'])})",
              "out = {}",
              "try:",
              "    s = m.stamp(df, panel, 'KEY'); r = s.iloc[0]",
              "    out['v'] = str(r.get('c11_vintage')); out['res'] = bool(r.get('c11_vintage_resolved')) if 'c11_vintage_resolved' in s.columns else None",
              "    out['un'] = str(r.get('c11_vintage_unresolved')); out['stamped'] = bool(m.is_c11_stamped(s))",
              "    out['stamped_drop'] = bool(m.is_c11_stamped(s.drop(columns=['c11_vintage_unresolved']) if 'c11_vintage_unresolved' in s.columns else s))",
              "    s2 = m.stamp(df, panel.drop(columns=['c11_vintage_unresolved']), 'KEY'); out['un2'] = str(s2.iloc[0].get('c11_vintage_unresolved')); out['res2'] = bool(s2.iloc[0].get('c11_vintage_resolved'))",
              "except Exception as e:",
              "    out['err'] = repr(e)",
              "print('JSON:' + json.dumps(out))")
    pf <- file.path(TD, paste0("ae_", as.integer(runif(1, 1e6, 9e6)), ".py")); writeLines(code, pf, useBytes = TRUE)
    Sys.setenv(PYTHONDONTWRITEBYTECODE = "1")                     # 저장소에 __pycache__ 를 쓰지 않는다
    o <- suppressWarnings(system2(PY, shQuote(pf), stdout = TRUE, stderr = TRUE))
    j <- grep("^JSON:", o, value = TRUE)
    if (!length(j)) { cat(tail(o, 8), sep = "\n"); return(list(err = "no output")) }
    fromJSON(sub("^JSON:", "", j[length(j)]))
  }
  A <- run_py(AEPF)
  ok(is.null(A$err) && identical(A$v, "latest") && identical(A$res, FALSE) && identical(A$un, "NFCI,STLFSI4"),
     sprintf("A1 stamp 산출에 빈티지 라벨(latest · resolved=FALSE · 미해소 NFCI,STLFSI4) %s", if (is.null(A$err)) "" else A$err))
  ok(isTRUE(A$stamped) && identical(A$stamped_drop, FALSE), "A2 빈티지 열은 표식 계약(is_c11_stamped) — 빠지면 미표식")
  ok(identical(A$un2, "unknown") && identical(A$res2, FALSE), "A3 패널에 라벨이 없으면 'unknown' = 미해소(fail-closed)")
  fA <- mutant(AEPF, "    out[\"c11_vintage_resolved\"] = (vu == \"\")\n", "", "am_label")
  if (is.na(fA)) ok(FALSE, "A-mut 대상 줄 부재") else {
    Am <- run_py(fA)
    ok(!is.null(Am$err) || !identical(Am$res, FALSE) || !isTRUE(Am$stamped), "A-mut ★red: resolved 라벨 삭제 → A1/A2 가 깨진다")
  }
}

cat(sprintf("\n=== 최종: %d PASS / %d FAIL / %d SKIP ===\n", P, FL, length(SKIPS)))
cat(as.character(toJSON(list(test = "test_c11_panel_contract", pass = P, fail = FL, total = P + FL,
                             skipped = length(SKIPS), skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
quit(status = if (FL > 0L || length(SKIPS) > 0L) 1L else 0L, save = "no")
