#==============================================================================
# test_pg2_c11_consumers.R — PIT C11 수리 1단계 S5: 해외 정보를 먹는 두 소비자의 가용시점 검사 (2026-09-24 신설)
#
# 대상
#   02_Infrastructure/reinforcement/overlay_arms/pg2_risk_overlay.R          (판정서 V-02 — L1 arm)
#   qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R   (판정서 V-04 — m4 엔진 · c11_regime_check)
# 근거: 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md V-02·V-04 · ② 형태 (a)
#       결정 PIT-C11-REMEDIATION(안 B) · PIT-C11-BOOK0001('표기 → 수리 뒤 재산출')
#
# 무엇을 재는가 (양방향 — 양성 대조 + 위반 주입 + 돌연변이 red)
#   P. pg2 arm: 표식 패널에서 정상 산출(게이트 0.70 · 무발화 1.00 · no_regime 행 면제) · 규칙 epoch 는 S0 도우미에서 온다
#   N. pg2 arm: 수리 전 판(표식 없음)·unresolved·다른 epoch·컷오프 > 신호일 d 를 전부 거부(라벨 가드는 통과하는 경우 포함)
#   M. 돌연변이: require 제거 · d→홀딩월 시작 · epoch 검사 제거 — 각각 대응 위반을 통과시키는 것을 보인다(검사가 하중을 진다)
#   F. m4 c11_regime_check(소스 텍스트 추출 실행 — 재구현 아님): verified/unresolved/no_regime · 컷오프 > 결정일 stop · 돌연변이
#   E. m4 엔진 전 구간(sandbox · 실입력 사본 · 읽기 전용): 수리 전 상류 → 비중 불변(C11 이전 엔진 git blob 대비) + unresolved 표기 ·
#      표식 상류 → verified · 늦은 컷오프 상류 → 엔진 중단
# 쓰기: tempdir() 아래 sandbox 만. 운영 .cache·원장·로그 미접촉.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
if (identical(suppressWarnings(as.integer(Sys.getenv("ARROW_IO_THREADS", "0"))), 1L)) Sys.setenv(ARROW_IO_THREADS = "2")

.slash <- function(p) gsub("\\\\", "/", p)
.self <- .slash(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
if (!is.na(.self) && !grepl("^([A-Za-z]:)?/", .self)) .self <- file.path(.slash(getwd()), .self)
ROOT <- if (!is.na(.self) && file.exists(.self)) dirname(dirname(dirname(.self))) else .slash(Sys.getenv("QM_ROOT", getwd()))
ARM  <- file.path(ROOT, "02_Infrastructure/reinforcement/overlay_arms/pg2_risk_overlay.R")
FE   <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R")
FE_PRE_C11_COMMIT <- "7ea5d8377"   # C11 수리 직전 HEAD(2026-09-24 10:45) — 비중 불변 대조의 기준 엔진
for (f in c(ARM, FE)) if (!file.exists(f)) { cat("대상 부재:", f, "\n"); quit(status = 2L) }

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- character(0)
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
sk <- function(axis, why, miss) { SKIP <<- SKIP + 1L
  SKIPS <<- c(SKIPS, sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', axis, why, miss)); cat("  SKIP", axis, "—", why, "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
emit <- function() cat(sprintf('{"test":"test_pg2_c11_consumers","pass":%d,"fail":%d,"skipped":%d,"total":%d,"skips":[%s]}\n',
                               PASS, FAIL, SKIP, PASS + FAIL + SKIP, paste(SKIPS, collapse = ",")))

TMP0 <- .slash(file.path(tempdir(), sprintf("pg2c11_%d", Sys.getpid())))   # bash 격리 실행용 — 전 경로 슬래시
dir.create(TMP0, recursive = TRUE, showWarnings = FALSE)
QM0 <- Sys.getenv("QM_ROOT", NA)
on.exit_restore <- function() if (is.na(QM0)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = QM0)

# 현행 규칙 epoch — S0 도우미 정본에서 직접(arm 이 같은 값을 쓰는지 대조한다)
.fa <- new.env(); source(file.path(ROOT, "02_Infrastructure/data/fred_availability.R"), local = .fa)
KEY <- .fa$fred_avail_rules_meta()$regime_key

#------------------------------------------------------------------------------
# pg2 sandbox — arm 이 읽는 파일만 사본으로 세운다(국면·팩터 DB 원천 없음 → 중립 · breadth 캐시 쓰기 없음)
#------------------------------------------------------------------------------
mk_root <- function(tag, ae = NULL, m4 = NULL) {
  R <- file.path(TMP0, tag); unlink(R, recursive = TRUE)
  for (rel in c("02_Infrastructure/validation/overlay_pit_guard.R", "02_Infrastructure/data/fred_availability.R",
                "06_Registry/fred_availability_rules.json")) {
    dir.create(dirname(file.path(R, rel)), recursive = TRUE, showWarnings = FALSE)
    file.copy(file.path(ROOT, rel), file.path(R, rel))
  }
  if (!is.null(m4)) { p <- file.path(R, "06_Registry/m4_published/m4_panel_published.parquet")
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); write_parquet(m4, p) }
  if (!is.null(ae)) { p <- file.path(R, "stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet")
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); write_parquet(ae, p) }
  R
}
ae_fx <- function(key = KEY, cut = c("2020-02-28", "2020-03-31"), stamp = TRUE) {
  x <- data.table(decision_date = as.Date(c("2020-03-01", "2020-04-01")), fire_seq = c(0L, 1L),
                  last_feat_date = as.Date(c("2020-02-28", "2020-03-31")))
  if (stamp) x[, `:=`(c11_feat_join = "c11_avail_decision_close", c11_regime_key = key,
                      c11_fred_avail_max = last_feat_date - 1L, c11_info_cutoff = as.Date(cut))]
  x
}
m4_fx <- function(key = KEY, status = c("no_regime", "verified", "verified"),
                  cut = c(NA, "2020-02-28", "2020-03-31"), stamp = TRUE) {
  x <- data.table(Date = as.Date(c("2020-02-03", "2020-03-02", "2020-04-01")), YM = c("2020-02", "2020-03", "2020-04"),
                  weight_str1715 = c(1, 1, 0.8))
  if (stamp) x[, `:=`(c11_info_cutoff = as.Date(cut), c11_regime_key = fifelse(status == "no_regime", NA_character_, key),
                      c11_status = status)]
  x
}
load_arm <- function(R, arm_text = NULL) {
  e <- new.env(parent = globalenv())
  Sys.setenv(QM_ROOT = R)
  on.exit(on.exit_restore(), add = TRUE)
  f <- ARM
  if (!is.null(arm_text)) { f <- file.path(R, "arm_mut.R"); writeLines(arm_text, f, useBytes = TRUE) }
  msg <- err_of(utils::capture.output(source(f, local = e, encoding = "UTF-8")))
  list(env = e, err = msg)
}
call_arm <- function(a, d) tryCatch(
  a$env$overlay_expo_pg2_risk_overlay(NULL, 30L, list(date = as.Date(d), hold = data.table(Ticker = "X"))),
  error = function(e) paste("ERR:", conditionMessage(e)))
ARM_TXT <- readLines(ARM, encoding = "UTF-8", warn = FALSE)
mutate <- function(old, new) { i <- which(grepl(old, ARM_TXT, fixed = TRUE))
  if (length(i) != 1L) { ng(sprintf("돌연변이 앵커 %d개(1개여야) — 대상 줄 소실: %s", length(i), old)); return(NULL) }
  t <- ARM_TXT; t[i] <- sub(old, new, t[i], fixed = TRUE); t }
load_mut <- function(tag, mt, ae, m4) if (is.null(mt)) list(env = NULL, err = "앵커 소실") else load_arm(mk_root(tag, ae = ae, m4 = m4), mt)

cat("=== P. pg2 arm 양성 대조 (표식 패널) ===\n")
a <- load_arm(mk_root("p1", ae = ae_fx(), m4 = m4_fx()))
chk(is.na(a$err), "P1 표식 패널 적재 — no_regime 행(컷오프 NA)은 면제", a$err %||% "")
chk(identical(a$env$.PG2_C11_KEY, KEY), "P2 arm 의 규칙 epoch = S0 도우미 fred_avail_rules_meta()$regime_key", a$env$.PG2_C11_KEY %||% "NA")
v1 <- call_arm(a, "2020-03-31"); v2 <- call_arm(a, "2020-02-28")
chk(isTRUE(all.equal(v1, 0.70)), "P3 d=2020-03-31 → m4(0.8)∧AE 발화 → 게이트 0.70 (컷오프 03-31 ≤ d)", as.character(v1))
chk(isTRUE(all.equal(v2, 1.00)), "P4 d=2020-02-28 → m4 무발화 → 1.00", as.character(v2))

cat("=== N. pg2 arm 위반 주입 (거부해야 한다) ===\n")
a <- load_arm(mk_root("n1", ae = ae_fx(stamp = FALSE), m4 = m4_fx()))
chk(grepl("C11 미해소 패널\\(ae\\)", a$err %||% ""), "N1 ★AE 수리 전 판(표식 없음) → 적재 거부", a$err %||% "(통과)")
a <- load_arm(mk_root("n2", ae = ae_fx(), m4 = m4_fx(stamp = FALSE)))
chk(grepl("C11 미해소 패널\\(m4\\)", a$err %||% ""), "N2 ★m4 수리 전 판(표식 없음) → 적재 거부", a$err %||% "(통과)")
a <- load_arm(mk_root("n3", ae = ae_fx(), m4 = m4_fx(status = c("no_regime", "unresolved", "verified"))))
chk(grepl("미해소 행\\(m4\\)", a$err %||% ""), "N3 ★m4 unresolved 행 → 적재 거부", a$err %||% "(통과)")
a <- load_arm(mk_root("n4", ae = ae_fx(key = "c11_avail:old:00000000"), m4 = m4_fx()))
chk(grepl("epoch 불일치\\(ae\\)", a$err %||% ""), "N4 ★AE 규칙 epoch 불일치 → 적재 거부", a$err %||% "(통과)")
M4_EARLY <- m4_fx(cut = c(NA, "2020-02-28", "2020-03-27"))   # m4 는 적합(03-27 ≤ d) — AE 만 위반하도록
a <- load_arm(mk_root("n5", ae = ae_fx(), m4 = M4_EARLY))
v <- call_arm(a, "2020-03-30")
chk(grepl("pg2_risk_overlay:c11", v), "N5 ★AE 컷오프 03-31 > 신호일 03-30 → 호출 거부 (라벨 가드 last_feat<홀딩월 04-01 은 통과하는 경우)", v)
a <- load_arm(mk_root("n6", ae = ae_fx(), m4 = m4_fx(cut = c(NA, "2020-02-28", "2020-04-01"))))
v <- call_arm(a, "2020-03-31")
chk(grepl("pg2_risk_overlay:c11", v), "N6 ★m4 컷오프 04-01 > 신호일 03-31 → 호출 거부", v)

cat("=== M. 돌연변이 (검사를 지우면 위반이 통과한다 = 그 줄이 하중을 진다) ===\n")
mt <- mutate('x[, c11_cut := pmax(last_feat, .pg2_c11_require(x, "ae"))]', 'x[, c11_cut := as.Date(NA)]')
a <- load_mut("m1", mt, ae = ae_fx(stamp = FALSE), m4 = m4_fx())
v <- if (is.na(a$err)) call_arm(a, "2020-03-31") else paste("ERR:", a$err)
chk(is.numeric(v) && isTRUE(all.equal(v, 0.70)), "M1 AE require 제거판은 수리 전 AE 로 게이트 0.70 을 낸다(N1 과 대조 — 검출력)", as.character(v))
mt <- mutate('rep(d, length(.c11))', 'rep(.h, length(.c11))')
a <- load_mut("m2", mt, ae = ae_fx(), m4 = M4_EARLY)
v <- if (is.na(a$err)) call_arm(a, "2020-03-30") else paste("ERR:", a$err)
chk(is.numeric(v), "M2 컷오프 기준을 d→홀딩월 시작으로 바꾼 판은 N5 위반을 통과시킨다(라벨 가드의 맹점 재현)", as.character(v))
mt <- mutate('if (any(chk & (is.na(key) | key != .PG2_C11_KEY)))', 'if (FALSE)')
a <- load_mut("m3", mt, ae = ae_fx(key = "c11_avail:old:00000000"), m4 = m4_fx())
chk(is.na(a$err), "M3 epoch 검사 제거판은 N4(다른 epoch)를 적재한다", a$err %||% "")

#------------------------------------------------------------------------------
cat("=== F. m4 c11_regime_check (소스 텍스트 추출 실행) ===\n")
FE_TXT <- paste(readLines(FE, encoding = "UTF-8", warn = FALSE), collapse = "\n")
grab <- function(pat, txt = FE_TXT) { m <- regmatches(txt, regexpr(pat, txt, perl = TRUE)); if (length(m)) m else NULL }
DEF <- grab("(?s)c11_regime_check <- function\\(out\\) \\{.*?\\n\\}\\n")
if (is.null(DEF)) { ng("F0 소스에서 c11_regime_check 추출 실패 — 앵커 소실"); emit(); quit(status = 1L) }
ok("F0 소스에서 c11_regime_check 추출(테스트가 실코드를 실행)")
run_chk <- function(dt, def = DEF) { e <- new.env(parent = globalenv()); eval(parse(text = def, encoding = "UTF-8"), e)
  tryCatch({ capture.output(r <- e$c11_regime_check(copy(dt))); r }, error = function(z) paste("ERR:", conditionMessage(z))) }
fx <- data.table(Date = as.Date(c("2004-02-02", "2020-04-01", "2020-05-04", "2026-10-01")),
                 Regime_Score_lag = c(NA, 40, 50, 40),
                 c11_info_cutoff = as.Date(c(NA, "2020-03-31", NA, "2026-09-30")))
r <- run_chk(fx)
chk(is.data.table(r) && identical(r$c11_status, c("no_regime", "verified", "unresolved", "verified")),
    "F1 상태 — 국면 미사용 no_regime · 표식 있음 verified · 표식 없음 unresolved", paste(if (is.data.table(r)) r$c11_status else r, collapse = ","))
fx2 <- copy(fx); fx2[2, c11_info_cutoff := as.Date("2020-04-03")]
r2 <- run_chk(fx2)
chk(is.character(r2) && grepl("★C11 위반", r2), "F2 ★컷오프 04-03 > 결정일 04-01 → 중단", as.character(r2)[1])
fx3 <- copy(fx); fx3[2, c11_info_cutoff := as.Date("2020-04-01")]
chk(is.data.table(run_chk(fx3)), "F3 경계 — 컷오프 = 결정일(그 날 15:30 결정 기준 가용)은 통과")
mdef <- sub("if (nrow(bad)) {", "if (FALSE) {", DEF, fixed = TRUE)
chk(!identical(mdef, DEF) && is.data.table(run_chk(fx2, mdef)), "F4 돌연변이: stop 블록 제거판은 F2 위반을 통과시킨다(검출력)")
mdef2 <- sub('fifelse(is.na(c11_info_cutoff), "unresolved", "verified")', '"verified"', DEF, fixed = TRUE)
r4 <- run_chk(fx, mdef2)
chk(!identical(mdef2, DEF) && is.data.table(r4) && !"unresolved" %in% r4$c11_status,
    "F5 돌연변이: 표식 없음을 verified 로 접는 판은 미해소를 숨긴다(F1 과 대조)")
chk(grepl('c11_info_cutoff := shift(reg_c11_cutoff, 1L, type = "lag")', FE_TXT, fixed = TRUE) &&
    grepl('Regime_Score_lag := shift(Regime_Score, 1L, type = "lag")', FE_TXT, fixed = TRUE) &&
    regexpr("out <- c11_regime_check(out)", FE_TXT, fixed = TRUE) > regexpr("c11_info_cutoff := shift(reg_c11_cutoff", FE_TXT, fixed = TRUE),
    "F6 구조 — 표식과 국면 값이 같은 shift(1L)로 같은 행에서 오고, 대조가 그 뒤에 불린다")

#------------------------------------------------------------------------------
cat("=== E. m4 엔진 전 구간 (sandbox · 실입력 사본 · 읽기 전용) ===\n")
U_SRC <- file.path(ROOT, ".cache/unified_regime_signal.parquet")
P_SRC <- file.path(ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
if (!file.exists(U_SRC) || !file.exists(P_SRC) || !nzchar(Sys.which("bash"))) {
  sk("E", "실입력 또는 bash 부재 — worktree/격리 트리", if (!file.exists(U_SRC)) U_SRC else if (!file.exists(P_SRC)) P_SRC else "bash")
} else {
  env_empty <- file.path(TMP0, "empty.Renviron"); file.create(env_empty)
  rs <- .slash(file.path(R.home("bin"), "Rscript.exe"))
  if (!file.exists(rs)) rs <- "Rscript"
  run_fe <- function(tag, fe_file, unified) {
    SB <- file.path(TMP0, paste0("fe_", tag)); unlink(SB, recursive = TRUE)
    for (d in c(".cache", "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output",
                "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts", "stage_artifacts"))
      dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
    write_parquet(unified, file.path(SB, ".cache/unified_regime_signal.parquet"))
    file.copy(P_SRC, file.path(SB, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
    file.copy(fe_file, file.path(SB, "fe.R"))
    sh <- file.path(SB, "run.sh")
    # ★Windows system2(env=) 는 무시된다 — bash 스크립트로 격리(R_ENVIRON_USER 빈 파일 · 루트 = sandbox)
    writeLines(c(sprintf("cd '%s' || exit 9", SB),
                 sprintf("R_ENVIRON_USER='%s' CLAUDE_PROJECT_DIR='%s' QM_ROOT='%s' PG2_AS_OF=2026-10-01 ARROW_IO_THREADS=2 '%s' --no-save fe.R > run.log 2>&1",
                         env_empty, SB, SB, rs), "echo $? > rc.txt"), sh)
    system2("bash", sh, stdout = FALSE, stderr = FALSE)
    rc <- suppressWarnings(as.integer(readLines(file.path(SB, "rc.txt"), warn = FALSE)[1]))
    outp <- file.path(SB, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet")
    list(rc = rc, out = if (file.exists(outp)) as.data.table(read_parquet(outp, mmap = FALSE)) else NULL,
         log = paste(readLines(file.path(SB, "run.log"), warn = FALSE), collapse = "\n"))
  }
  U <- as.data.table(read_parquet(U_SRC, mmap = FALSE)); U[, Date := as.Date(Date)]
  # ★수리 전 상류 = 표식 형태 전부 제거(2026-09-25 C11 S9 — 운영 unified 가 S3 재발행으로 행 열 avail_date 와
  #   파일 스탬프 R 속성 c11_avail_regime_key 를 싣게 되자, 행 열 2개만 지우던 픽스처가 '수리된 상류'가 되어
  #   E2 가 거짓 red 를 냈다 — 운영 상태를 빌린 픽스처는 그 상태를 고치면 깨진다). 표식 형태는 이름 규약으로 전부 지운다.
  U_leg <- copy(U)
  .mk <- grep("^(c11_|avail_date$)", names(U_leg), value = TRUE)
  if (length(.mk)) U_leg[, (.mk) := NULL]
  for (.a in grep("^c11_", names(attributes(U_leg)), value = TRUE)) setattr(U_leg, .a, NULL)
  chk(!length(grep("^(c11_|avail_date$)", names(U_leg))) && !length(grep("^c11_", names(attributes(U_leg)))),
      "E0 픽스처 자기검사 — '수리 전 상류'에 C11 표식(행 열·파일 스탬프 속성)이 하나도 없다",
      paste(c(grep("^(c11_|avail_date$)", names(U_leg), value = TRUE), grep("^c11_", names(attributes(U_leg)), value = TRUE)), collapse = ","))
  r_new <- run_fe("new_legacy_up", FE, U_leg)
  chk(identical(r_new$rc, 0L) && !is.null(r_new$out), "E1 수리 전 상류(표식 없음)에서 엔진 완주(rc 0) — BOOK 트래킹 표기 경로", paste("rc", r_new$rc))
  if (!is.null(r_new$out)) {
    st <- r_new$out$c11_status
    chk(all(st %in% c("unresolved", "no_regime")) && sum(st == "unresolved") > 0 && grepl("C11 미해소", r_new$log),
        "E2 ★전 국면 사용 행 unresolved 표기 + 로그 경고(침묵하지 않는다)", paste(names(table(st)), table(st), collapse = " "))
  }
  old_fe <- file.path(TMP0, "fe_pre_c11.R")
  gs <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(ROOT), "show",
                   sprintf("%s:qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R", FE_PRE_C11_COMMIT)),
                   stdout = old_fe, stderr = FALSE)), error = function(e) 1L)
  if (!identical(as.integer(gs), 0L) || !file.exists(old_fe) || file.size(old_fe) < 1000) {
    sk("E3", "C11 이전 엔진 git blob 판독 불가(커밋 부재 트리)", FE_PRE_C11_COMMIT)
  } else {
    r_old <- run_fe("old_legacy_up", old_fe, U_leg)
    if (!is.null(r_old$out) && !is.null(r_new$out)) {
      cm <- setdiff(intersect(names(r_old$out), names(r_new$out)), character(0))
      chk(isTRUE(all.equal(r_old$out[, ..cm], r_new$out[, ..cm], check.attributes = FALSE)) &&
          identical(setdiff(names(r_new$out), names(r_old$out)), c("c11_info_cutoff", "c11_regime_key", "c11_status")),
          "E3 ★비중·전 열 불변(C11 이전 엔진 대비) — 추가된 것은 표식 3열뿐", sprintf("공통 %d열", length(cm)))
    } else ng("E3 비교 불가", paste("old rc", r_old$rc))
  }
  U_ok <- copy(U_leg)[, `:=`(c11_info_cutoff = Date, c11_regime_key = KEY)]
  r_ok <- run_fe("new_stamped_up", FE, U_ok)
  if (!is.null(r_ok$out)) {
    st <- r_ok$out$c11_status
    chk(identical(r_ok$rc, 0L) && all(st %in% c("verified", "no_regime")) && sum(st == "verified") > 0 &&
        isTRUE(all.equal(r_ok$out$weight_str1715, r_new$out$weight_str1715)),
        "E4 표식 상류(컷오프 = 월말 라벨 ≤ 다음 달 보유 시작) → 전 행 verified · 비중 동일", paste(names(table(st)), table(st), collapse = " "))
  } else ng("E4 표식 상류 실행 실패", paste("rc", r_ok$rc))
  # 생산자 파일 스탬프(S2·S3 규약: R 속성 c11_avail_regime_key = S0 regime_key) → 컷오프 = 행 Date → verified
  U_fs <- copy(U_leg); setattr(U_fs, "c11_avail_regime_key", KEY)
  r_fs <- run_fe("new_filestamp_up", FE, U_fs)
  if (!is.null(r_fs$out)) {
    st <- r_fs$out$c11_status
    chk(identical(r_fs$rc, 0L) && all(st %in% c("verified", "no_regime")) && sum(st == "verified") > 0 &&
        all(r_fs$out$c11_regime_key[st == "verified"] == KEY) && grepl("생산자 스탬프", r_fs$log),
        "E6 생산자 파일 스탬프(R 속성 c11_avail_regime_key)도 받는다 → verified · 키 = 스탬프 값", paste(names(table(st)), table(st), collapse = " "))
  } else ng("E6 파일 스탬프 상류 실행 실패", paste("rc", r_fs$rc))
  U_bad <- copy(U_leg); setattr(U_bad, "c11_avail_regime_key", "legacy:no-avail")
  r_bad <- run_fe("new_badstamp_up", FE, U_bad)
  chk(!is.null(r_bad$out) && all(r_bad$out$c11_status %in% c("unresolved", "no_regime")),
      "E7 ★형식이 다른 스탬프(접두 c11_avail: 아님)는 표식으로 치지 않는다 → unresolved")
  U_late <- copy(U_leg)[, `:=`(c11_info_cutoff = Date + 20L, c11_regime_key = KEY)]
  r_late <- run_fe("new_late_up", FE, U_late)
  chk(!identical(r_late$rc, 0L) && grepl("★C11 위반", r_late$log),
      "E5 ★상류 컷오프 = 라벨+20일(공표 지연 흉내) → 엔진 중단(PIT 위반)", paste("rc", r_late$rc))
}

cat(sprintf("\n-- test_pg2_c11_consumers: %d passed, %d failed, %d skipped --\n\n", PASS, FAIL, SKIP))
emit()
quit(status = if (FAIL > 0L) 1L else 0L)
