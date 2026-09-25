#!/usr/bin/env Rscript
#==============================================================================
# test_rf_selection_asof.R — 선정층 as-of (플랜 P0-08 · 감사 D4-02·D4-05·D10-05 · pit.md C1 D-E · 2026-09-24)
#
# 무엇을 지키나:
#   B1 규칙 선정기(rf_factor_arms.R) — 순위·tier·IC 상관이 IC[Usable_Date <= asof] 로만 계산된다.
#     tier 어휘는 factor_evidence 선언(S1/S2/S3)에서 재도출되고(구판 A..E 리터럴 → 전부 99), 저장 tier(전기간)를 쓰지 않는다.
#   ★as-of 상한 가드(2026-09-25 · P0-08 잔여 R3) — 인자·규칙 as-of 가 결정 시점(B1 = 격자 fixed_axes.start_date ·
#     B7 = 셀 스펙 > 격자 fixed_axes.start_date) 뒤·미래·NA·복수면 stop(A11·B10). 수리 전 판에서 A11·B10 은 빨갛다
#     (ASOF_SRC_FACTOR_ARMS·ASOF_SRC_SLEEVE 로 구판을 물려 실증). 구 'asof=NA 명시적 전표본' 대조는 절단 줄을 걷은
#     돌연변이 적재(FE_FULL)로 옮겼다(A5b·A5c — 검정력 대조는 그대로). C5 = 저수준 계산기 직접 호출 0(우회 경로 재도출).
#   B7 선정 통계(rf_sleeve.R::rf_sl_conditional_ic_asof) — 약세장 = 벤치 **실현** 보유월(확장창 분위), IC 는 형성일 t 를
#     보유월(t 다음 달)에 정렬, Usable_Date <= d, 벤치는 d 에서 절단 후 월 집계, Ret/100 없음, 날짜 일치 조인 없음.
#
# 방향(양방향 — '경고 0' 이 최고 위험이다):
#   PIT 섭동  — as-of 뒤 행을 교란하면 신판 선정은 불변, 구판(전표본)은 변한다(섭동에 검정력이 있음을 같이 보인다).
#   양성 대조 — 설계한 픽스처에서 기대 순위·tier·정렬이 나온다 · 저장 tier 재판정 규칙이 등록부 전 팩터와 일치한다.
#   위반 주입 — 소스 돌연변이(절단 삭제·정렬 어긋남·A..E 리터럴 복귀·벤치 절단 삭제)가 각각 빨개진다.
#   실데이터(읽기 전용) — 운영 IC·벤치에서 as-of 해석·섭동 불변(구조 단정만 — 값 고정 금지: 운영 상태를 빌리지 않는다).
#     RF_ASOF_REALDATA=1 이면 감사 수치(D35 .1595·D42 .1582·D34 .1534·D22 10위 / as-of 2008 D51_Ulcer .1005 /
#     IC 한 달 밀기 → D22 .0753 1위)를 **같은 함수**로 재현한다(STR_1469 보유 + RAWDATA 판독 — 무거워서 선택).
#
# 부작용: 픽스처는 전부 tempdir. 운영 파일은 읽기만(mmap=FALSE). 원장·설정·산출물 무접촉.
# 실행: cd <ROOT> && Rscript 08_Tests/reinforcement/test_rf_selection_asof.R
# ★R 문법: 최상위 if 다음 줄 else 금지 — 단정은 chk() 한 줄로.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC_ARMS  <- Sys.getenv("ASOF_SRC_FACTOR_ARMS", file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R"))
SRC_SLEEVE <- Sys.getenv("ASOF_SRC_SLEEVE", file.path(ROOT, "02_Infrastructure/reinforcement/rf_sleeve.R"))
SRC_READ  <- file.path(ROOT, "02_Infrastructure/validation/pit_quarantine.R")
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { d <- paste(as.character(unlist(d)), collapse = " ")   # (R3) 길이 0 상세(구판 필드 부재)에 죽지 않는다
  FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
SKIPS <- list()   # 배터리 요약 계약(run_all_hooks.sh:120) — skips[{axis, reason}] 로 미판정 사유를 드러낸다
sk <- function(m) { SKIP <<- SKIP + 1L; SKIPS[[length(SKIPS) + 1L]] <<- list(axis = sub(" .*$", "", m), reason = m)
  cat(sprintf("  SKIP %s\n", m)) }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
TMP0 <- file.path(tempdir(), sprintf("rf_asof_%d", Sys.getpid())); dir.create(TMP0, recursive = TRUE, showWarnings = FALSE)
EMPTY <- file.path(TMP0, "empty_code_root"); dir.create(EMPTY, showWarnings = FALSE)
wj <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)), p, useBytes = TRUE) }
Sys.unsetenv("RF_CELL_SPEC")

# 소스를 (선택적으로 돌연변이해) 격리 env 에 적재. 돌연변이 대상 문자열이 정확히 1회 없으면 NULL(검사 공허 — 호출부가 FAIL).
#   from/to 는 같은 길이의 문자 벡터(여러 곳을 한꺼번에 — 중복 방어선은 한 겹만 지우면 돌연변이가 살아남는다).
load_src <- function(path, from = NULL, to = NULL, code_root = EMPTY) {
  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  for (i in seq_along(from)) {
    n <- lengths(regmatches(txt, gregexpr(from[i], txt, fixed = TRUE)))
    if (n != 1L) return(NULL)
    txt <- sub(from[i], to[i], txt, fixed = TRUE)
  }
  f <- tempfile(fileext = ".R", tmpdir = TMP0); writeLines(txt, f, useBytes = TRUE)
  en <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(f, envir = en))))
  if (exists(".RFF_ROOT", envir = en, inherits = FALSE)) assign(".RFF_ROOT", code_root, envir = en)
  en
}

#==============================================================================
cat("=== A. B1 규칙 선정기 — as-of 순위·tier·상관 ===\n")
#==============================================================================
ASOF <- as.Date("2005-01-01")
me <- seq(as.Date("2000-02-01"), by = "month", length.out = 132L) - 1L            # 형성일 2000-01..2010-12 월말
ue <- seq(as.Date("2000-03-01"), by = "month", length.out = 132L) - 1L            # 가용일 = 다음 월말
pre <- ue <= ASOF
FIDS <- c("F_V1", "F_V2", "F_Q1", "F_M1", "F_D1", "F_T", "F_S")
FCAT <- c(F_V1 = "value", F_V2 = "value", F_Q1 = "quality", F_M1 = "momentum", F_D1 = "defense", F_T = "technical", F_S = "liquidity")
mk_ic <- function(seed = 11L) {
  set.seed(seed)
  rc_cut <- as.Date("2001-12-01")            # as-of 표본 마지막 형성일(2004-11-30) - 1095일 근방 — F_T 의 최근 부호를 뒤집는다
  mu <- list(
    F_V1 = ifelse(pre, 0.06, 0.00),            # as-of S1 1위(가치) · 전기간이면 F_V2 에 밀린다
    F_V2 = ifelse(pre, 0.015, 0.10),
    F_Q1 = rep(0.03, 132L),
    F_M1 = ifelse(pre, 0.01, 0.08),
    F_D1 = rep(-0.045, 132L),                  # 음수 IC — |IC| 로 정렬 · 최근 부호도 음수라 S1
    F_T  = ifelse(pre, ifelse(me < rc_cut, 0.24, -0.03), 0.00),   # |평균| 최대(.075)지만 최근 3년 부호가 반대 → S1 탈락(S2)
    F_S  = rep(0.30, 132L))
  rbindlist(lapply(FIDS, function(f) {
    keep <- if (f == "F_S") (ue > as.Date("2004-09-01")) else rep(TRUE, 132L)   # F_S = as-of 이력 4개월뿐
    data.table(Factor_Name = f, IC = mu[[f]][keep] + rnorm(sum(keep), 0, 0.02), N_Stocks = 300L,
               Date = me[keep], Usable_Date = ue[keep])
  }))
}
mk_b1_root <- function(tag, IC, with_grid = TRUE, b1cfg = TRUE, thresholds = TRUE) {
  R <- file.path(TMP0, paste0("b1_", tag)); unlink(R, recursive = TRUE)
  ev <- list(factors = setNames(lapply(FIDS, function(f) list(category = FCAT[[f]], ic_all = 0.99, ic_screen_tier = "S3",
                                                             lifecycle_status = "active")), FIDS))
  if (thresholds) { ev$thresholds_declared <- list(S1_abs_ic = 0.04, S2_abs_ic = 0.02, S1_min_months = 24L, S1_require_sign_agree = TRUE)
                    ev$counts <- list(S1 = 0L, S2 = 0L, S3 = 7L, unmeasured = 0L) }
  wj(ev, file.path(R, "06_Registry/factor_evidence.json"))
  wj(list(factors = setNames(lapply(FIDS, function(i) list(panel_axis = "cross_sectional")), FIDS)),
     file.path(R, "06_Registry/factor_panel_axis.json"))
  wj(setNames(lapply(FIDS, function(i) list(lifecycle = list(status = "active"), category = FCAT[[i]])), FIDS),
     file.path(R, ".cache/factor_db/factor_registry.json"))
  arrow::write_parquet(IC, file.path(R, ".cache/factor_db/factor_ic_monthly.parquet"))
  if (with_grid) {
    b1 <- list(id = "B1")
    if (b1cfg) b1$selection_asof <- list(min_ic_months = 6L, recent_icir_days = 1095L, recent_icir_min_n = 6L)
    wj(list(fixed_axes = list(start_date = format(ASOF)), blocks = list(b1)), file.path(R, "06_Registry/reinforce_program.json"))
  }
  R
}
suppressMessages(library(arrow))
FE <- load_src(SRC_ARMS)
IC0 <- mk_ic()
R0 <- mk_b1_root("base", IC0)
P0 <- tryCatch(FE$rf_factor_pool(R0), error = function(e) e)
chk(!inherits(P0, "error") && identical(P0$asof, format(ASOF)) && identical(P0$selection_basis, "asof_ic") &&
      grepl("fixed_axes.start_date", P0$asof_source),
    sprintf("A1 as-of 기본값 = 격자 fixed_axes.start_date(%s) · basis asof_ic", format(ASOF)),
    if (inherits(P0, "error")) conditionMessage(P0) else paste(P0$asof, P0$selection_basis))
chk(!inherits(P0, "error") && nrow(P0$IC) > 0L && max(as.Date(P0$IC$Usable_Date)) <= ASOF,
    "A1b 반환 IC 는 Usable_Date <= as-of 행만(C14 — 소비자가 P$IC 를 써도 미래가 없다)")
picks <- function(en, R, asof = NULL, offs = 0:5)
  vapply(offs, function(o) paste((en$rf_pick_factor_sets(5L, seed_offset = o, depths = 1:5, root = R, asof = asof) %||%
                                  list(picked_ids = "NULL"))$picked_ids, collapse = ","), character(1))
pk0 <- tryCatch(picks(FE, R0), error = function(e) paste("ERR", conditionMessage(e)))
chk(startsWith(pk0[1], "F_V1"), sprintf("A2 [양성] as-of 시드(오프셋 0) = F_V1 (as-of |IC| 최대 S1) — %s", pk0[1]), pk0[1])
chk(!any(grepl("F_S", pk0)), "A3 as-of 표본 min_ic_months 미만(F_S · 4개월 · IC 0.30)은 어떤 오프셋에서도 사슬에 안 든다",
    paste(pk0, collapse = " / "))
chk(!inherits(P0, "error") && !P0$pool[id == "F_S"]$rankable && "F_S" %in% P0$pool$id,
    "A3b 풀 자격은 그대로(F_S 는 풀에 있다) — 순위 표본만 부족(설계 재료 풀 불변)")
tt <- if (inherits(P0, "error")) NULL else setNames(P0$pool$tier, P0$pool$id)
chk(!is.null(tt) && identical(unname(tt[c("F_V1", "F_D1", "F_T", "F_Q1")]), c("S1", "S1", "S2", "S2")) &&
      identical(P0$tier_levels, c("S1", "S2", "S3")),
    sprintf("A4 tier 어휘 재도출(S1<S2<S3) · as-of 재판정 — F_T 는 |IC| 최대지만 최근 부호 반대로 S2 (%s)",
            paste(names(tt), tt, sep = "=", collapse = " ")), paste(tt, collapse = ","))
chk(!is.null(tt) && !any(tt %in% c("A", "B", "C", "D", "E")) && all(P0$pool$tier != "S3" | P0$pool$id != "F_V1"),
    "A4b 저장 tier(픽스처는 전부 S3 · ic_all 0.99)를 읽지 않는다 — 재판정 값이 쓰인다")

# A5 PIT 섭동 — as-of 뒤 IC 를 교란: 신판 불변 · 구판(asof=NA 전표본) 변함
IC1 <- copy(IC0); set.seed(99); IC1[Usable_Date > ASOF, IC := rnorm(.N, 0, 0.5)]
R1 <- mk_b1_root("perturb", IC1)
pk1 <- tryCatch(picks(FE, R1), error = function(e) paste("ERR", conditionMessage(e)))
P1 <- tryCatch(FE$rf_factor_pool(R1), error = function(e) NULL)
chk(identical(pk0, pk1) && !is.null(P1) && isTRUE(all.equal(as.data.frame(P0$pool), as.data.frame(P1$pool), check.attributes = FALSE)),
    "A5 [PIT 섭동] Usable_Date > as-of 행 교란 → 신판 사슬(오프셋 0..5)·풀 통계·tier 전부 불변",
    paste(c(pk0[pk0 != pk1][1], "->", pk1[pk0 != pk1][1], if (is.null(P1)) "P1=NULL" else paste(all.equal(P0$pool, P1$pool), collapse = ";")), collapse = " "))
# ★전표본 대조 = as-of 절단 줄을 걷은 적재(구판 등가). 구 경로(asof=NA 명시적 전표본)는 R3 상한 가드로 폐지됐다(A11b).
CUT_LINE <- "    IC <- IC[!is.na(Usable_Date) & Usable_Date <= A$date]\n"
FE_FULL <- tryCatch(load_src(SRC_ARMS, CUT_LINE, "\n"), error = function(e) NULL)
if (is.null(FE_FULL)) ng("A5b 전표본 대조 적재 — 절단 줄 부재(좌표 낡음)") else {
  pl0 <- tryCatch(picks(FE_FULL, R0), error = function(e) paste("ERR", conditionMessage(e)))
  pl1 <- tryCatch(picks(FE_FULL, R1), error = function(e) paste("ERR", conditionMessage(e)))
  chk(!identical(pl0, pl1) && !any(startsWith(c(pl0, pl1), "ERR")),
      "A5b [검정력] 같은 교란에 절단 없는 판(전표본 · 구판 등가)은 사슬이 바뀐다 — 섭동이 실제로 선정을 움직일 수 있다", pl0[1])
  chk(!startsWith(pl0[1], "F_V1"), sprintf("A5c [대조] 전표본이면 시드가 F_V1 이 아니다(%s) — as-of 가 결과를 가른다", substr(pl0[1], 1, 12)))
}
pkF <- tryCatch(FE$rf_pick_factor_sets(3L, seed_offset = 0L, depths = 1:3, root = R0), error = function(e) NULL)
chk(!is.null(pkF) && all(vapply(pkF$cells, function(c) identical(c$selection_basis, "asof_ic") && grepl("as-of 2005-01-01", c$basis), TRUE)) &&
      identical(pkF$substrate_asof, "2005-01-01"),
    "A6 셀·반환값에 selection_basis=asof_ic · basis 에 as-of 표기(러너 jlog asof = 선정 창 끝)")

# A7 rf_ic_cormat(asof) — 절단 멱등 · Usable_Date 없이 asof 주면 stop
CM0 <- FE$rf_ic_cormat(IC0, FIDS, asof = ASOF); CM1 <- FE$rf_ic_cormat(IC1, FIDS, asof = ASOF)
chk(isTRUE(all.equal(CM0, CM1)), "A7 rf_ic_cormat(asof): as-of 뒤 교란에 상관행렬 불변")
chk(!isTRUE(all.equal(FE$rf_ic_cormat(IC0, FIDS), FE$rf_ic_cormat(IC1, FIDS))), "A7b [검정력] 절단 없는 상관은 같은 교란에 변한다")
chk(grepl("Usable_Date", err_of(FE$rf_ic_cormat(IC0[, !"Usable_Date"], FIDS, asof = ASOF)) %||% ""),
    "A7c Usable_Date 없는 IC 에 as-of 를 주면 멈춘다(C14 — 절단을 추정하지 않는다)")

# A8 격자 부재 root → 전표본 + 라벨 / 격자 있는데 B1 설정 없음 → stop
Rn <- mk_b1_root("nogrid", IC0, with_grid = FALSE)
Pn <- tryCatch(suppressMessages(FE$rf_factor_pool(Rn)), error = function(e) e)
chk(!inherits(Pn, "error") && identical(Pn$selection_basis, "full_sample_ic") && identical(Pn$asof, "full_sample"),
    "A8 격자 없는 root(합성 픽스처) → 전표본 + selection_basis=full_sample_ic 라벨(조용한 as-of 주장 금지)")
Rc <- mk_b1_root("nocfg", IC0, b1cfg = FALSE)
chk(grepl("selection_asof", err_of(FE$rf_factor_pool(Rc)) %||% ""),
    "A8b 격자가 있는데 B1.selection_asof 가 없으면 멈춘다(최소 표본·창을 코드에 박지 않는다)")
Rt <- mk_b1_root("nothr", IC0, thresholds = FALSE)
Pt <- tryCatch(FE$rf_factor_pool(Rt), error = function(e) e)
chk(!inherits(Pt, "error") && all(is.na(Pt$pool$tier)) && !length(Pt$tier_levels),
    "A8c 등록부에 절단선 선언이 없으면 tier 없음(NA) — 어휘를 지어내지 않는다")

# A11 as-of 상한 가드 (R3 · 2026-09-25) — 결정 시점 = 격자 fixed_axes.start_date(= ASOF). 뒤·미래·NA·복수 = stop · 이하 = 통과
e_late <- err_of(FE$rf_factor_pool(R0, asof = ASOF + 1L))
chk(grepl("결정 시점", e_late %||% ""), sprintf("A11a as-of = 결정 시점+1일(%s) → stop(첫 시그널일 뒤 IC 로 사슬 선정 금지)", format(ASOF + 1L)), e_late %||% "통과")
e_pk <- err_of(FE$rf_pick_factor_sets(3L, seed_offset = 0L, depths = 1:3, root = R0, asof = "2008-06-30"))
chk(grepl("결정 시점", e_pk %||% ""), "A11a' rf_pick_factor_sets(asof = 2008-06-30) → stop(러너 경로 인자 관통)", e_pk %||% "통과")
e_na <- err_of(FE$rf_factor_pool(R0, asof = NA))
chk(grepl("NA", e_na %||% "") && grepl("전표본", e_na %||% ""), "A11b as-of = NA → stop(구 '명시적 전표본' 경로 폐지)", e_na %||% "통과")
e_fu <- err_of(FE$rf_factor_pool(R0, asof = Sys.Date() + 30L))
chk(grepl("미래", e_fu %||% ""), "A11c as-of = 미래(오늘+30) → stop", e_fu %||% "통과")
e_v2 <- err_of(FE$rf_factor_pool(R0, asof = c("2004-01-01", "2004-06-30")))
chk(!is.na(e_v2), "A11d as-of 복수 → stop", "통과")
Pb <- tryCatch(FE$rf_factor_pool(R0, asof = ASOF), error = function(e) e)
chk(!inherits(Pb, "error") && isTRUE(all.equal(as.data.frame(Pb$pool), as.data.frame(P0$pool), check.attributes = FALSE)) &&
      identical(Pb$asof_source, "arg"),
    "A11e [양성 경계] as-of = 결정 시점 → 통과 · 기본(NULL) 풀과 동일", if (inherits(Pb, "error")) conditionMessage(Pb) else "")
Pe <- tryCatch(FE$rf_factor_pool(R0, asof = "2004-06-30"), error = function(e) e)
chk(!inherits(Pe, "error") && as.Date(Pe$ic_max_usable) <= as.Date("2004-06-30") && identical(Pe$asof, "2004-06-30"),
    "A11f [양성] 결정 시점보다 이른 as-of(2004-06-30) → 통과(더 보수적인 창 · IC 가용 ≤ as-of)", if (inherits(Pe, "error")) conditionMessage(Pe) else "")
e_ng <- err_of(suppressMessages(FE$rf_factor_pool(Rn, asof = "2004-06-30")))
chk(grepl("상한", e_ng %||% ""), "A11g 격자 없는 root 에 인자 as-of → stop(결정 시점을 몰라 상한 대조 불가 · fail-closed)", e_ng %||% "통과")
Rf <- mk_b1_root("futgrid", IC0); wj(list(fixed_axes = list(start_date = format(Sys.Date() + 400L)),
  blocks = list(list(id = "B1", selection_asof = list(min_ic_months = 6L, recent_icir_days = 1095L, recent_icir_min_n = 6L)))),
  file.path(Rf, "06_Registry/reinforce_program.json"))
e_fg <- err_of(FE$rf_factor_pool(Rf))
chk(grepl("미래", e_fg %||% ""), "A11h 격자 fixed_axes.start_date 가 미래 → stop(결정 시점이 오늘 뒤 = 전표본과 같다)", e_fg %||% "통과")

# A9 저장 tier 재판정 규칙의 양성 대조 — 등록부 전 팩터의 (ic_all · recent_3y_icir · n_months) → 저장 ic_screen_tier
EVP <- file.path(ROOT, "06_Registry/factor_evidence.json")
if (file.exists(EVP)) {
  EVJ <- fromJSON(EVP, simplifyVector = FALSE); rule <- FE$.rff_tier_rule(EVJ); ids <- names(EVJ$factors)
  nn <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)
  got <- FE$.rff_tier_of(vapply(ids, function(i) nn(EVJ$factors[[i]]$ic_all), 0), vapply(ids, function(i) nn(EVJ$factors[[i]]$recent_3y_icir), 0),
                         vapply(ids, function(i) nn(EVJ$factors[[i]]$n_months), 0), rule)
  want <- vapply(ids, function(i) as.character(EVJ$factors[[i]]$ic_screen_tier %||% NA), ""); want[want == "unmeasured"] <- NA
  same <- (got == want) | (is.na(got) & is.na(want))
  chk(length(ids) > 100L && all(same), sprintf("A9 [양성] tier 규칙 R 이식 = build_factor_evidence.py::tier_of — 등록부 %d/%d 일치", sum(same), length(ids)),
      paste(head(ids[!same], 5), collapse = ","))
} else sk("A9 factor_evidence.json 부재 — tier 이식 대조 생략")

# A10 위반 주입(소스 돌연변이) — 각각 빨개져야 한다
mut_b1 <- list(
  list("M1 as-of 절단 줄 삭제(rf_factor_pool)", "    IC <- IC[!is.na(Usable_Date) & Usable_Date <= A$date]\n", "\n",
       function(en) identical(picks(en, R0), picks(en, R1))),
  list("M2 tier 어휘 A..E 리터럴 복귀", "pool[, .tk := if (length(.lv)) match(tier, .lv) else NA_integer_]",
       "pool[, .tk := match(tier, c(\"A\", \"B\", \"C\", \"D\", \"E\"))]",
       function(en) startsWith(picks(en, R0, offs = 0L), "F_V1")),
  list("M3 상관 입력을 절단 전 IC 로(as-of 인자 제거)", "  R <- rf_ic_cormat(P$IC, pool$id, asof = P$asof_date)",
       "  R <- rf_ic_cormat(arrow::read_parquet(file.path(root, \".cache/factor_db/factor_ic_monthly.parquet\"), mmap = FALSE) |> as.data.table(), pool$id)",
       function(en) identical(picks(en, R0), picks(en, R1))),
  list("M4 순위 표본 하한 해제(rankable 필터 삭제)", "  pool <- P$pool[rankable == TRUE]", "  pool <- P$pool",
       function(en) !any(grepl("F_S", picks(en, R0)))),
  # (R3) 상한 가드 — 결정 시점 비교 줄을 무력화하면 늦은 as-of 가 통과한다 · NA 를 전표본으로 되돌리면 NA 가 통과한다
  list("M9 as-of 상한(결정 시점) 비교 삭제", "    if (d > bound)\n", "    if (FALSE)\n",
       function(en) !is.na(err_of(en$rf_factor_pool(R0, asof = "2008-06-30")))),
  list("M9b NA → 전표본 복귀(구 explicit_full_sample)", "    if (length(asof) != 1L || is.na(asof))\n",
       "    if (length(asof) == 1L && is.na(asof)) return(list(date = as.Date(NA), basis = \"full_sample_ic\", source = \"explicit_full_sample\", bound = bound, cfg = cfg))\n    if (length(asof) != 1L)\n",
       function(en) !is.na(err_of(en$rf_factor_pool(R0, asof = NA)))))
for (m in mut_b1) {
  en <- tryCatch(load_src(SRC_ARMS, m[[2]], m[[3]]), error = function(e) NULL)
  if (is.null(en)) { ng(paste(m[[1]], "— 돌연변이 대상 문자열 부재(검사 공허 · 소스가 바뀌었다)")); next }
  still <- tryCatch(isTRUE(m[[4]](en)), error = function(e) FALSE)
  chk(!still, sprintf("A10 [돌연변이 red] %s → 검사가 잡는다", m[[1]]), "돌연변이가 살아남았다")
}

#==============================================================================
cat("\n=== B. B7 선정 통계 — rf_sl_conditional_ic_asof · rf_sl_resolve ===\n")
#==============================================================================
SL <- load_src(SRC_SLEEVE)
d0 <- as.Date("2003-12-31")
# 일간 벤치: 영업일(평일) · 지정 월 수익이 정확히 나오게 월 첫 영업일에 한 번 점프
days <- seq(as.Date("1999-11-01"), as.Date("2006-12-31"), by = "day"); days <- days[as.integer(format(days, "%u")) <= 5L]
mret <- function(hm) { k <- as.integer(substr(hm, 6, 7)); ifelse(k %% 3L == 0L, -0.06, ifelse(k %% 3L == 1L, 0.01, 0.03)) }
B <- data.table(Date = days, hm = format(days, "%Y-%m"))
B[, first := !duplicated(hm)]
B[, r := ifelse(first, mret(hm), 0)]
B[, BM_Close := 100 * cumprod(1 + r)]
B[1, r := NA_real_]
BMD <- B[, .(Date, BM_Close, BM_Ret = r)]
# IC: 보유월(= 형성 다음 달)이 약세(3·6·9·12월)면 형성일 t 에 X_A 값 — 같은 달(형성월)로 잘못 이으면 다른 값을 줍는다
me7 <- seq(as.Date("2000-01-01"), by = "month", length.out = 84L) - 1L       # 1999-12..2006-11 월말
ue7 <- seq(as.Date("2000-02-01"), by = "month", length.out = 84L) - 1L
hm7 <- format(ue7, "%Y-%m"); bear7 <- as.integer(substr(hm7, 6, 7)) %% 3L == 0L
formbear <- as.integer(format(me7, "%m")) %% 3L == 0L                            # 형성월 자체가 약세인 행(어긋난 정렬이 잡을 달)
IC7 <- rbindlist(list(
  data.table(Factor_Name = "D_A", Date = me7, Usable_Date = ue7, IC = ifelse(bear7, 0.20, ifelse(formbear, -0.30, 0.00))),
  data.table(Factor_Name = "D_B", Date = me7, Usable_Date = ue7, IC = ifelse(bear7, 0.05, ifelse(formbear, 0.40, 0.00))),
  data.table(Factor_Name = "R_C", Date = me7, Usable_Date = ue7, IC = ifelse(bear7, 0.10, 0.00))))
C0 <- tryCatch(SL$rf_sl_conditional_ic_asof(d0, IC7, BMD, 0.30, 4L), error = function(e) e)
chk(!inherits(C0, "error") && isTRUE(all.equal(C0[Factor_Name == "D_A"]$ic_bad, 0.20)) && isTRUE(all.equal(C0[Factor_Name == "D_B"]$ic_bad, 0.05)),
    "B1 [정렬] 약세 보유월의 IC = 형성일 t(보유월 직전 월말) 행 — D_A 0.20 · D_B 0.05 정확",
    if (inherits(C0, "error")) conditionMessage(C0) else paste(round(C0$ic_bad, 4), collapse = ","))
Mb <- SL$rf_sl_bench_months(BMD, d0)
thr_ref <- as.numeric(quantile(Mb$ret, 0.30, names = FALSE))
chk(!inherits(C0, "error") && isTRUE(all.equal(attr(C0, "meta")$threshold, thr_ref)) && max(Mb$hend) <= d0 &&
      !(format(min(BMD$Date), "%Y-%m") %in% Mb$hm),
    sprintf("B2 [확장창] 문턱 = d 까지 완결된 벤치 달 전부의 30%% 분위(%.4f) · 첫 달(전월 종가 없음) 제외", thr_ref))
Mb2 <- SL$rf_sl_bench_months(BMD, as.Date("2003-12-15"))
chk(!("2003-12" %in% Mb2$hm) && ("2003-11" %in% Mb2$hm), "B3 d 가 월 중간이면 그 달은 모집단에서 빠진다(부분 실현 달 금지)")
# B4 PIT 섭동 — d 뒤 IC 행·벤치 가격 교란 → 불변 / d 를 뒤로 밀면 변함
IC7p <- copy(IC7); set.seed(5); IC7p[Usable_Date > d0, IC := rnorm(.N, 0, 1)]
BMDp <- copy(BMD); BMDp[Date > d0, BM_Close := BM_Close * cumprod(rep(1.01, .N))]   # d 뒤 매일 +1% — 미래 달이 전부 강세
Cp <- tryCatch(SL$rf_sl_conditional_ic_asof(d0, IC7p, BMDp, 0.30, 4L), error = function(e) e)
chk(!inherits(Cp, "error") && isTRUE(all.equal(C0[order(Factor_Name)], Cp[order(Factor_Name)], check.attributes = FALSE)) &&
      isTRUE(all.equal(attr(C0, "meta")$threshold, attr(Cp, "meta")$threshold)),
    "B4 [PIT 섭동] d 뒤 IC 행·벤치 가격 교란 → ic_bad·ic_good·문턱 전부 불변")
Cq <- tryCatch(SL$rf_sl_conditional_ic_asof(as.Date("2006-12-31"), IC7p, BMDp, 0.30, 4L), error = function(e) e)
chk(!inherits(Cq, "error") && !isTRUE(all.equal(C0$ic_bad, Cq$ic_bad)), "B4b [검정력] as-of 를 뒤로 밀면 같은 교란이 결과를 바꾼다")
# B5 단위 — 공표 지수 포인트가 있으면 BM_Ret(퍼센트여도) 무시 · 없고 퍼센트면 stop
BMpct <- copy(BMD)[, BM_Ret := BM_Ret * 100]
Cu <- tryCatch(SL$rf_sl_conditional_ic_asof(d0, IC7, BMpct, 0.30, 4L), error = function(e) e)
chk(!inherits(Cu, "error") && isTRUE(all.equal(C0$ic_bad, Cu$ic_bad)), "B5 BM_Close 가 있으면 수익은 지수 포인트 비율 — 퍼센트 BM_Ret 에 영향 없음")
chk(grepl("퍼센트", err_of(SL$rf_sl_conditional_ic_asof(d0, IC7, BMpct[, .(Date, BM_Ret)], 0.30, 4L)) %||% ""),
    "B5b BM_Close 없이 BM_Ret 이 퍼센트 단위면 멈춘다(Ret/100 로 고치지 않는다)")
Cr <- tryCatch(SL$rf_sl_conditional_ic_asof(d0, IC7, BMD[, .(Date, BM_Ret)], 0.30, 4L), error = function(e) e)
chk(!inherits(Cr, "error") && isTRUE(all.equal(C0$ic_bad, Cr$ic_bad)), "B5c 소수 BM_Ret 만 있어도 같은 결과(가격·수익 두 경로 일치)")
# B6 계약 위반 입력
chk(grepl("Usable_Date", err_of(SL$rf_sl_conditional_ic_asof(d0, IC7[, !"Usable_Date"], BMD, 0.30, 4L)) %||% ""),
    "B6 Usable_Date 없는 IC → stop(C14)")
IC7m <- copy(IC7)[, Usable_Date := Usable_Date + 31L]
chk(grepl("한 달이 아닌", err_of(SL$rf_sl_conditional_ic_asof(as.Date("2006-12-31"), IC7m, BMD, 0.30, 4L)) %||% ""),
    "B6b 형성일→가용일이 한 달이 아닌 IC → stop(보유월 정렬을 추정하지 않는다)")
Cn <- SL$rf_sl_conditional_ic_asof(as.Date("2000-06-30"), IC7, BMD, 0.30, 4L)
chk(all(is.na(Cn$ic_bad)) && all(Cn$n_bad < 4L), "B6c 약세 표본 < min_bear_months 면 ic_bad = NA(순위에서 빠진다)")

# B7 rf_sl_resolve — as-of 해석 순서 · 격리 · 퇴역 규칙
R7 <- file.path(TMP0, "b7root"); unlink(R7, recursive = TRUE)
wj(list(factors = list(D_A = list(category = "defense", lifecycle_status = "active", ic_bad = 0.0),
                       D_B = list(category = "defense", lifecycle_status = "active", ic_bad = 0.9),
                       R_C = list(category = "risk", lifecycle_status = "active", ic_bad = 0.5))),
   file.path(R7, "06_Registry/factor_evidence.json"))
cfg7 <- list(bear_quantile = 0.3, min_bear_months = 4L, candidate_categories = c("defense", "risk"), rank_key = "ic_bad",
             ic_path = "x.parquet", bench_path = "y.parquet", bench_price_col = "BM_Close")
wj(list(fixed_axes = list(start_date = "2003-12-31"), blocks = list(list(id = "B7", selection_asof = cfg7))),
   file.path(R7, "06_Registry/reinforce_program.json"))
RL <- SL$rf_sl_parse(list(kind = "factor_topk", k = 5, select = "ic_bad_rank_asof", rank = 1))
x0 <- tryCatch(SL$rf_sl_resolve(RL, R7, IC = IC7, BM = BMD), error = function(e) e)
chk(!inherits(x0, "error") && identical(x0$id, "D_A") && identical(x0$asof, "2003-12-31") && grepl("program fixed_axes", x0$asof_source),
    "B7 rf_sl_resolve: 격자 시작일 as-of · 1위 D_A(저장 ic_bad 는 D_B 가 최대 — 읽지 않는다)",
    if (inherits(x0, "error")) conditionMessage(x0) else paste(x0$id, x0$asof))
spec <- file.path(TMP0, "cell_spec.json"); wj(list(fixed_axes = list(start_date = "2006-12-31")), spec)
Sys.setenv(RF_CELL_SPEC = spec)
x1 <- tryCatch(SL$rf_sl_resolve(RL, R7, IC = IC7p, BM = BMDp), error = function(e) e)
Sys.unsetenv("RF_CELL_SPEC")
chk(!inherits(x1, "error") && identical(x1$asof, "2006-12-31") && identical(x1$asof_source, "cell fixed_axes.start_date"),
    "B7b 셀 스펙(RF_CELL_SPEC) 시작일이 격자보다 우선 — 엔진 경로(rf_sl_resolve(.SL, root))가 그 셀의 워밍업 창을 쓴다")
RLa <- SL$rf_sl_parse(list(kind = "factor_topk", k = 5, rank = 1, asof = "2003-12-31"))
Sys.setenv(RF_CELL_SPEC = spec)
x2 <- tryCatch(SL$rf_sl_resolve(RLa, R7, IC = IC7p, BM = BMDp), error = function(e) e)
Sys.unsetenv("RF_CELL_SPEC")
chk(!inherits(x2, "error") && identical(x2$asof, "2003-12-31") && identical(x2$id, "D_A"),
    "B7c 규칙 asof 가 셀 스펙보다 우선 · d 뒤 교란 입력에서도 같은 id")
dir.create(file.path(R7, "02_Infrastructure/validation"), recursive = TRUE, showWarnings = FALSE)
file.copy(SRC_READ, file.path(R7, "02_Infrastructure/validation/pit_quarantine.R"), overwrite = TRUE)
wj(list(schema = "pit_quarantine_v1", quarantines = list(list(id = "PITQ-FIX", code = "C11", flag = "pit_c11", status = "active",
     factors = list(list(id = "D_A")), sources = list()))), file.path(R7, "06_Registry/pit_quarantine.json"))
x3 <- tryCatch(SL$rf_sl_resolve(RL, R7, IC = IC7, BM = BMD), error = function(e) e)
chk(!inherits(x3, "error") && !identical(x3$id, "D_A") && grepl("격리 제외 1", x3$basis),
    "B7d PIT 격리 팩터는 1위여도 후보에서 빠진다(pit_quarantine.json · B1 과 같은 규약)",
    if (inherits(x3, "error")) conditionMessage(x3) else x3$id)
unlink(file.path(R7, "06_Registry/pit_quarantine.json"))
chk(grepl("퇴역", err_of(SL$rf_sl_parse(list(kind = "factor_topk", k = 5, select = "ic_bad_rank"))) %||% "") &&
      grepl("퇴역", err_of(SL$rf_sl_resolve(list(select = "ic_bad_rank", factor_id = "", rank = 1L), R7)) %||% ""),
    "B8 퇴역 select(ic_bad_rank) — 파싱·해석 둘 다 멈춘다(구 칸과 새 칸이 같은 서명으로 섞이지 않게)")

# B10 as-of 상한 가드 (R3 · 2026-09-25) — 결정 시점 = 셀 스펙 > 격자 fixed_axes.start_date(R7 = 2003-12-31)
Sys.unsetenv("RF_CELL_SPEC")
e10a <- err_of(SL$rf_sl_resolve(RL, R7, asof = "2004-06-30", IC = IC7, BM = BMD))
chk(grepl("결정 시점", e10a %||% ""), "B10a 인자 as-of 2004-06-30 > 격자 시작일 2003-12-31 → stop", e10a %||% "통과")
RLf <- SL$rf_sl_parse(list(kind = "factor_topk", k = 5, rank = 1, asof = "2099-01-01"))
e10b <- err_of(SL$rf_sl_resolve(RLf, R7, IC = IC7, BM = BMD))
chk(grepl("미래", e10b %||% ""), "B10b 규칙 asof 2099(셀 스펙 경로) → stop(미래)", e10b %||% "통과")
spec_e <- file.path(TMP0, "cell_spec_early.json"); wj(list(fixed_axes = list(start_date = "2003-06-30")), spec_e)
RLm <- SL$rf_sl_parse(list(kind = "factor_topk", k = 5, rank = 1, asof = "2003-09-30"))
Sys.setenv(RF_CELL_SPEC = spec_e)
e10c <- err_of(SL$rf_sl_resolve(RLm, R7, IC = IC7, BM = BMD))
Sys.unsetenv("RF_CELL_SPEC")
chk(grepl("결정 시점 2003-06-30", e10c %||% "") && grepl("cell", e10c %||% ""),
    "B10c 엔진 경로 — 셀 시작일 2003-06-30 < 규칙 asof 2003-09-30(< 격자 2003-12-31) → stop(상한 = 그 칸의 셀 스펙)", e10c %||% "통과")
Sys.setenv(RF_CELL_SPEC = spec)
x10d <- tryCatch(SL$rf_sl_resolve(RL, R7, asof = "2006-12-31", IC = IC7p, BM = BMDp), error = function(e) e)
Sys.unsetenv("RF_CELL_SPEC")
chk(!inherits(x10d, "error") && identical(x10d$asof_bound, "2006-12-31") && identical(x10d$asof_bound_source, "cell fixed_axes.start_date"),
    "B10d [양성 경계] 셀 시작일 2006-12-31 = 인자 as-of → 통과(상한 = 셀 스펙 · 격자 2003-12-31 이 아니다)",
    if (inherits(x10d, "error")) conditionMessage(x10d) else paste(x10d$asof_bound, x10d$asof_bound_source))
e10e <- err_of(SL$rf_sl_resolve(RL, R7, asof = NA, IC = IC7, BM = BMD))
e10e2 <- err_of(SL$rf_sl_resolve(RL, R7, asof = c("2003-01-31", "2003-06-30"), IC = IC7, BM = BMD))
chk(grepl("NA/복수", e10e %||% "") && grepl("NA/복수", e10e2 %||% ""), "B10e 인자 as-of NA·복수 → stop('없음' 으로 읽어 기본값으로 가지 않는다)",
    paste(e10e %||% "통과", "|", e10e2 %||% "통과"))
x10f <- tryCatch(SL$rf_sl_resolve(RL, R7, asof = "2003-06-30", IC = IC7p, BM = BMDp), error = function(e) e)
chk(!inherits(x10f, "error") && identical(x10f$asof, "2003-06-30") && as.Date(x10f$meta$ic_max_usable) <= as.Date("2003-06-30") &&
      identical(x10f$asof_bound, "2003-12-31"),
    "B10f [양성] 결정 시점보다 이른 as-of → 통과(IC 가용 ≤ as-of · 상한 = 격자 2003-12-31)",
    if (inherits(x10f, "error")) conditionMessage(x10f) else paste(x10f$asof, x10f$asof_bound))
R7n <- file.path(TMP0, "b7root_nostart"); unlink(R7n, recursive = TRUE)
dir.create(file.path(R7n, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(R7, "06_Registry/factor_evidence.json"), file.path(R7n, "06_Registry/factor_evidence.json"))
wj(list(fixed_axes = list(n_max = 25L), blocks = list(list(id = "B7", selection_asof = cfg7))), file.path(R7n, "06_Registry/reinforce_program.json"))
e10g <- err_of(SL$rf_sl_resolve(RL, R7n, asof = "2003-06-30", IC = IC7, BM = BMD))
chk(grepl("결정 시점", e10g %||% "") && grepl("부재", e10g %||% ""),
    "B10g 셀·격자 시작일 둘 다 없는데 인자 as-of → stop(상한 대조 불가 · fail-closed)", e10g %||% "통과")

# B9 위반 주입(소스 돌연변이)
mut_b7 <- list(
  # ★세 겹(IC 절단 · 벤치 절단 · 완결 달 필터)은 서로를 대신한다 — 한 겹만 지우면 살아남는 게 정상이다. 동시에 지운다.
  list("M5 as-of 세 겹 동시 삭제(IC 절단·벤치 절단·완결 필터)",
       c("  X <- X[!is.na(Usable_Date) & Usable_Date <= d & is.finite(IC)]", "  B <- B[!is.na(Date) & Date <= d]", "  M[is.finite(ret) & cal_end <= d][]"),
       c("  X <- X[!is.na(Usable_Date) & is.finite(IC)]", "  B <- B[!is.na(Date)]", "  M[is.finite(ret)][]"),
       function(en) { a <- en$rf_sl_conditional_ic_asof(d0, IC7, BMD, 0.3, 4L); b <- en$rf_sl_conditional_ic_asof(d0, IC7p, BMDp, 0.3, 4L)
                      isTRUE(all.equal(a[order(Factor_Name)], b[order(Factor_Name)], check.attributes = FALSE)) }),
  list("M6 정렬 어긋남(보유월 = 형성월 · 구 버그)", "  X[, hm := format(Usable_Date, \"%Y-%m\")]\n  nx <- format(as.Date(format(X$Date, \"%Y-%m-01\")) + 32L, \"%Y-%m\")",
       "  X[, hm := format(Date, \"%Y-%m\")]\n  nx <- X$hm",
       function(en) isTRUE(all.equal(en$rf_sl_conditional_ic_asof(d0, IC7, BMD, 0.3, 4L)[Factor_Name == "D_A"]$ic_bad, 0.20))),
  list("M7 벤치 절단 + 완결 필터 삭제(문턱 모집단에 미래 달)", c("  B <- B[!is.na(Date) & Date <= d]", "  M[is.finite(ret) & cal_end <= d][]"),
       c("  B <- B[!is.na(Date)]", "  M[is.finite(ret)][]"),
       function(en) isTRUE(all.equal(attr(en$rf_sl_conditional_ic_asof(d0, IC7, BMD, 0.3, 4L), "meta")$threshold,
                                     attr(en$rf_sl_conditional_ic_asof(d0, IC7p, BMDp, 0.3, 4L), "meta")$threshold))),
  list("M8 Ret/100 복귀(가격 경로)", "    B[, .r := px / shift(px) - 1]", "    B[, .r := (px / shift(px) - 1) / 100]",
       function(en) isTRUE(all.equal(attr(en$rf_sl_conditional_ic_asof(d0, IC7, BMD, 0.3, 4L), "meta")$threshold, thr_ref))),
  # (R3) 상한 가드 — 결정 시점 비교 무력화 · 셀 스펙을 상한에서 빼기 · NA 를 없음으로 — 각각 해당 사례가 샌다
  list("M10 as-of 상한(결정 시점) 비교 삭제", "  if (d > bound)\n", "  if (FALSE)\n",
       function(en) !is.na(err_of(en$rf_sl_resolve(RL, R7, asof = "2004-06-30", IC = IC7, BM = BMD)))),
  list("M11 상한을 격자 시작일로만(셀 스펙 무시)", "  bound <- suppressWarnings(as.Date(if (nzchar(cell_sd)) cell_sd else prog_sd))",
       "  bound <- suppressWarnings(as.Date(if (nzchar(prog_sd)) prog_sd else cell_sd))",
       function(en) { Sys.setenv(RF_CELL_SPEC = spec_e); on.exit(Sys.unsetenv("RF_CELL_SPEC"))
                      !is.na(err_of(en$rf_sl_resolve(RLm, R7, IC = IC7, BM = BMD))) }),
  list("M12 인자 NA 를 '없음' 으로(구판 거동)", "  if (.bad(asof))\n", "  if (FALSE)\n",
       function(en) !is.na(err_of(en$rf_sl_resolve(RL, R7, asof = NA, IC = IC7, BM = BMD)))))
for (m in mut_b7) {
  en <- tryCatch(load_src(SRC_SLEEVE, m[[2]], m[[3]]), error = function(e) NULL)
  if (is.null(en)) { ng(paste(m[[1]], "— 돌연변이 대상 문자열 부재(검사 공허 · 소스가 바뀌었다)")); next }
  still <- tryCatch(isTRUE(m[[4]](en)), error = function(e) FALSE)
  chk(!still, sprintf("B9 [돌연변이 red] %s → 검사가 잡는다", m[[1]]), "돌연변이가 살아남았다")
}

#==============================================================================
cat("\n=== C. 격자 배선 (재도출) ===\n")
#==============================================================================
PROG <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE), error = function(e) NULL)
if (is.null(PROG)) sk("C 격자 판독 불가") else {
  b7 <- Filter(function(b) identical(b$id, "B7"), PROG$blocks)
  sels <- if (length(b7)) vapply(b7[[1]]$cells, function(c) as.character(c$defense_sleeve$select %||% ""), "") else character(0)
  chk(length(sels) == 5L && all(sels == "ic_bad_rank_asof"), "C1 격자 B7 5칸 전부 select=ic_bad_rank_asof(퇴역 규칙 잔존 0)", paste(sels, collapse = ","))
  cf <- tryCatch(SL$rf_sl_select_config(ROOT), error = function(e) e)
  chk(!inherits(cf, "error") && isTRUE(cf$q > 0 && cf$q < 1) && cf$min_n >= 1L && length(cf$cats) > 0L,
      "C2 격자 B7.selection_asof 판독 가능(분위·최소 표본·후보 계열)", if (inherits(cf, "error")) conditionMessage(cf) else "")
  b1 <- Filter(function(b) identical(b$id, "B1"), PROG$blocks)
  chk(length(b1) == 1L && is.list(b1[[1]]$selection_asof) && nzchar(as.character(PROG$fixed_axes$start_date %||% "")),
      "C3 격자 B1.selection_asof + fixed_axes.start_date 존재(규칙 선정기 as-of 기본값의 원천)")
  for (c in (if (length(b7)) b7[[1]]$cells else list()))
    if (is.na(err_of(SL$rf_sl_parse(c$defense_sleeve)))) NULL else ng(sprintf("C4 %s 슬리브 파싱 실패", c$code))
  ok("C4 격자 B7 5칸 슬리브 규칙이 파싱된다(엔진 47행 경로)")
}
# C5 (R3) 상한 가드 우회 경로 재도출 — 결정 시점을 모르는 저수준 계산기(rf_sl_conditional_ic_asof · rf_ic_cormat)를
#   정의 파일 밖에서 직접 부르는 운영 코드가 없어야 한다(있으면 as-of 상한을 돌아간다). 파서로 호출 토큰만 센다(주석·문자열 제외).
LOWLV <- c(rf_sl_conditional_ic_asof = "02_Infrastructure/reinforcement/rf_sleeve.R", rf_ic_cormat = "02_Infrastructure/ops/rf_factor_arms.R")
infra <- list.files(file.path(ROOT, "02_Infrastructure"), pattern = "[.][Rr]$", recursive = TRUE, full.names = FALSE)
hits5 <- character(0)
for (rel0 in infra) {
  rel <- file.path("02_Infrastructure", rel0)
  tx <- tryCatch(readLines(file.path(ROOT, rel), warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
  if (!any(grepl(paste(names(LOWLV), collapse = "|"), tx))) next
  pd <- tryCatch(utils::getParseData(parse(text = tx, keep.source = TRUE)), error = function(e) NULL)
  if (is.null(pd)) { hits5 <- c(hits5, paste(rel, "(파싱 불가)")); next }
  cl <- pd[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text %in% names(LOWLV), ]
  for (i in seq_len(nrow(cl))) if (!identical(rel, unname(LOWLV[cl$text[i]]))) hits5 <- c(hits5, sprintf("%s:%d %s", rel, cl$line1[i], cl$text[i]))
}
chk(length(infra) > 0L && !length(hits5), sprintf("C5 저수준 as-of 계산기의 정의 파일 밖 운영 호출 0건(02_Infrastructure .R %d개) — 운영 as-of 는 전부 상한 가드 경유", length(infra)),
    paste(head(hits5, 5), collapse = " | "))

#==============================================================================
cat("\n=== D. 실데이터 (읽기 전용 · 구조 단정) ===\n")
#==============================================================================
cf <- tryCatch(SL$rf_sl_select_config(ROOT), error = function(e) NULL)
icp <- if (is.null(cf)) "" else file.path(ROOT, cf$ic_path); bmp <- if (is.null(cf)) "" else file.path(ROOT, cf$bench_path)
if (is.null(cf) || !file.exists(icp) || !file.exists(bmp)) sk("D 운영 IC·벤치 부재 — 생략") else {
  ICr <- as.data.table(arrow::read_parquet(icp, mmap = FALSE)); BMr <- as.data.table(arrow::read_parquet(bmp, mmap = FALSE))
  RLr <- SL$rf_sl_parse(list(kind = "factor_topk", k = 5, select = "ic_bad_rank_asof", rank = 1))
  xr <- tryCatch(SL$rf_sl_resolve(RLr, ROOT, IC = ICr, BM = BMr), error = function(e) e)
  ok_r <- !inherits(xr, "error")
  chk(ok_r && identical(xr$asof, as.character(PROG$fixed_axes$start_date)) && as.Date(xr$meta$ic_max_usable) <= as.Date(xr$asof) &&
        xr$meta$n_bear_months >= cf$min_n,
      sprintf("D1 운영 데이터 B7 해석 — as-of %s · 1위 %s · 약세 %s개월 · IC 가용 ~%s", if (ok_r) xr$asof else "?", if (ok_r) xr$id else "?",
              if (ok_r) xr$meta$n_bear_months else "?", if (ok_r) xr$meta$ic_max_usable else "?"),
      if (ok_r) "" else conditionMessage(xr))
  ICrp <- copy(ICr); set.seed(3); ICrp[as.Date(Usable_Date) > as.Date(PROG$fixed_axes$start_date), IC := rnorm(.N, 0, 0.5)]
  BMrp <- copy(BMr); BMrp[as.Date(Date) > as.Date(PROG$fixed_axes$start_date), BM_Close := BM_Close * exp(rnorm(.N, 0, 0.1))]
  xp <- tryCatch(SL$rf_sl_resolve(RLr, ROOT, IC = ICrp, BM = BMrp), error = function(e) e)
  chk(ok_r && !inherits(xp, "error") && identical(xp$id, xr$id) && isTRUE(all.equal(xp$table, xr$table, check.attributes = FALSE)),
      "D2 [PIT 섭동 · 운영 데이터] as-of 뒤 IC·벤치 교란 → B7 순위표 전체 불변")
  P_r <- tryCatch(FE2 <- load_src(SRC_ARMS, code_root = ROOT), error = function(e) NULL)
  Pr <- tryCatch(FE2$rf_factor_pool(ROOT), error = function(e) e)
  chk(!inherits(Pr, "error") && identical(Pr$selection_basis, "asof_ic") && identical(Pr$asof, as.character(PROG$fixed_axes$start_date)) &&
        as.Date(Pr$ic_max_usable) <= as.Date(Pr$asof) && sum(Pr$pool$rankable) >= 100L,
      sprintf("D3 운영 B1 풀 as-of %s · 풀 %s · 순위 가능 %s · IC 가용 ~%s", if (inherits(Pr, "error")) "?" else Pr$asof,
              if (inherits(Pr, "error")) "?" else nrow(Pr$pool), if (inherits(Pr, "error")) "?" else sum(Pr$pool$rankable),
              if (inherits(Pr, "error")) "?" else Pr$ic_max_usable), if (inherits(Pr, "error")) conditionMessage(Pr) else "")
}

#==============================================================================
cat("\n=== E. 감사 수치 재현 (선택 · RF_ASOF_REALDATA=1 · STR_1469 보유 + RAWDATA) ===\n")
#==============================================================================
HD <- file.path(ROOT, "04_Research/strategies/STR_1469_cons4f_5sleeve/output/holdings_detail.csv")
RAWP <- file.path(ROOT, ".cache/RAWDATA.parquet")
if (!identical(Sys.getenv("RF_ASOF_REALDATA"), "1")) sk("E 선택 절 — RF_ASOF_REALDATA=1 일 때만(무거움)") else
if (!file.exists(HD) || !file.exists(RAWP) || !file.exists(icp)) sk("E STR_1469 보유·RAWDATA·IC 부재") else {
  hd <- fread(HD)[, .(Signal_Date = as.Date(Signal_Date), Ticker = as.character(Ticker), Weight = as.numeric(Weight))]
  tk <- unique(hd$Ticker)
  ds <- arrow::open_dataset(RAWP)
  rw <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(ds, Ticker %in% tk), Date, Ticker, Ret)))
  rw[, `:=`(Date = as.Date(Date), Ticker = as.character(Ticker))]
  mo <- sort(unique(hd$Signal_Date))
  PM <- rbindlist(lapply(seq_len(length(mo) - 1L), function(i) {
    h <- hd[Signal_Date == mo[i], .(w = sum(Weight)), by = Ticker]
    s <- rw[Ticker %in% h$Ticker & Date > mo[i] & Date <= mo[i + 1L]]
    r1 <- s[, .(r = prod(1 + Ret / 100) - 1), by = Ticker]; r2 <- s[, .(r = prod(1 + Ret) - 1), by = Ticker]
    f <- function(rr) { m <- merge(h, rr, by = "Ticker", all.x = TRUE); m[is.na(r), r := 0]; sum(m$w * m$r) }
    data.table(start = mo[i], end = mo[i + 1L], ret100 = f(r1), rtrue = f(r2))
  }))
  EVr <- fromJSON(file.path(ROOT, "06_Registry/factor_evidence.json"), simplifyVector = FALSE)$factors
  pool77 <- names(EVr)[vapply(EVr, function(e) (e$category %||% "") %in% c("defense", "risk") &&
                                 identical(e$lifecycle_status %||% "active", "active") && !is.null(e$ic_bad), TRUE)]
  ICa <- as.data.table(arrow::read_parquet(icp, mmap = FALSE))[Factor_Name %in% pool77]
  ICa[, `:=`(Date = as.Date(Date), Usable_Date = as.Date(Usable_Date))]
  nxm <- function(d) format(as.Date(format(d, "%Y-%m-01")) + 32L, "%Y-%m")
  top <- function(C) C[is.finite(ic_bad)][order(-ic_bad, Factor_Name)]
  FAR <- as.Date("2099-01-01")
  # (감사 icb.py 는 날짜 **일치** 조인이었다 — STR_1469 신호일 201개 중 82개만 IC 형성일과 일치. 같은 입력을 주려고 그 조인을 에뮬한다)
  T1 <- top(SL$rf_sl_conditional_ic_asof(FAR, ICa[Date %in% PM$start], PM[, .(hm = nxm(start), ret = ret100, hend = end)], 0.30, 1L))
  chk(identical(head(T1$Factor_Name, 3), c("D35_RealVol_63d", "D42_EWMA_Vol", "D34_RealVol_21d")) &&
        isTRUE(all.equal(round(head(T1$ic_bad, 3), 4), c(0.1595, 0.1582, 0.1534))) && which(T1$Factor_Name == "D22_Tracking_Error") == 10L,
      "E1 [양성] 정렬판 재현 — D35 .1595 · D42 .1582 · D34 .1534 · D22 10위(감사 D4-05)",
      paste(sprintf("%s %.4f", head(T1$Factor_Name, 3), head(T1$ic_bad, 3)), collapse = " | "))
  ICs <- copy(ICa)[, `:=`(Date0 = Date, U0 = Usable_Date)][, `:=`(Usable_Date = Date0, Date = as.Date(format(Date0, "%Y-%m-01")) - 1L)]
  T2 <- top(SL$rf_sl_conditional_ic_asof(FAR, ICs[Date0 %in% PM$end], PM[, .(hm = format(end, "%Y-%m"), ret = ret100, hend = end)], 0.30, 1L))
  chk(identical(T2$Factor_Name[1], "D22_Tracking_Error") && isTRUE(all.equal(round(T2$ic_bad[1], 4), 0.0753)),
      "E2 [위반 주입] IC 날짜 한 달 밀기 → 구 버그 재현(D22 .0753 1위 = 저장 ic_bad)", sprintf("%s %.4f", T2$Factor_Name[1], T2$ic_bad[1]))
  A8 <- as.Date("2008-01-01")
  T3 <- top(SL$rf_sl_conditional_ic_asof(A8, ICs[Date0 %in% PM$end & U0 <= A8], PM[, .(hm = format(end, "%Y-%m"), ret = ret100, hend = end)], 0.30, 4L))
  chk(identical(T3$Factor_Name[1], "D51_Ulcer_Index") && isTRUE(all.equal(round(T3$ic_bad[1], 4), 0.1005)),
      "E3 [양성] as-of 2008 구 정의 재현 — D51_Ulcer .1005 1위(D22 7위)", sprintf("%s %.4f", T3$Factor_Name[1], T3$ic_bad[1]))
}

cat(sprintf("\n합계: 통과 %d · 실패 %d · 생략 %d\n", PASS, FAIL, SKIP))
cat(as.character(toJSON(list(test = "rf_selection_asof", pass = PASS, fail = FAIL, total = PASS + FAIL, skipped = SKIP,
                             skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
unlink(TMP0, recursive = TRUE)
if (FAIL > 0L) quit(status = 1L)
