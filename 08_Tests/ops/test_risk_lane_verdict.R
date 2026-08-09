#!/usr/bin/env Rscript
# test_risk_lane_verdict.R — risk 레인 판정 블록 위반 주입 테스트 (2026-08-09 신설).
#
# 원 결함 (2026-08-09 실측):
#   Σ-A/B 배터리가 risk 레인 method 2건을 **실제로 쟀는데**
#     h1b_sigma_ab_overlay.csv :: minvar@ProperScoreGASFilter IR 0.920 · PreferenceRobustDistortion 0.658
#   research_status_20260809.json 의 risk 블록은
#     harness_status = "risk 레인 Σ-교체 A/B 하네스 미배선 …"   (하드코딩)
#     action         = "레지스트리 등재 2건 … 자동 측정 아직 없음" (하드코딩)
#   으로 **자기 실측을 부정**했다. 텔레그램도 같은 문자열이 나갔다.
#   ★등재≠처분 계통의 **반대 방향** 판본이다 — 여태 본 건 과대보고(등재를 처분으로 읽음)였는데
#     이건 과소보고(측정을 안 한 것으로 씀)다. 공통 뿌리 = **상태를 선언으로 적었다**.
#   ★게다가 판정 축이 없었다: Σ 추정기 교체의 옳은 대조는 비중 규칙을 고정한
#     `minvar@<est>` vs `minvar_lw` 인데, 그 대조가 CSV 안에 있는데도 계산되지 않아
#     optimizer 의 "최고 비중법" 경쟁에 흡수돼 조용히 졌다.
#
# ★검사 설계 — 양성 + 위반 주입 + 돌연변이:
#   (A) 양성 대조: 두 arm 다 CSV 에 있으면 2/2 측정 · Δ 부호 정확
#   (B) 위반 주입: arm 행 제거 → measured=FALSE + note 발화 (조용히 넘기지 않는가)
#   (C) 위반 주입: **대조군** 행 제거 → Δ = NA + 대조군 부재 호명 (Δ 를 지어내지 않는가)
#   (D) 배터리 미실행(battery_fresh=FALSE) → verdict NULL + 사유 명시
#   (E) 결과 CSV 부재 / (F) IR 컬럼 결손 → 부재를 정상값으로 내려앉히지 않는가
#   (G) implemented arm 0건 → 명시 상태
#   (H) ★역방향 양성: Δ>0 인 arm 을 주입하면 n_improved 가 는다
#       — "개선 0건"만 뱉는 검사면 아무것도 재지 않는 것이다.
#   (I) 실물 레지스트리 회귀: risk_lane_arms() 가 현 저장소에서 arm 을 실제로 만들어내는가
#   돌연변이: 수리 전 하드코딩 문자열 판을 동반 실행 — **모든 픽스처에서 같은 값**이어야 한다.
#     (그게 원 결함의 정의다: 실측이 무엇이든 보고가 안 변한다.)
#
# ★검사 대상 = 사본이 아니라 원본 .R 의 마커 구간 추출.
#   >>> RISK_LANE_VERDICT … <<< RISK_LANE_VERDICT

suppressMessages(library(data.table))

.root <- local({
  # ★앵커 1순위 = 이 스크립트 자신의 위치 (self-first). env 를 먼저 믿으면 worktree 에서
  #   돌린 검사가 조용히 main 트리를 검사한다. [[project-test-runner-anchor-selffirst-20260802]]
  #   ★단 `--file=` 만으로 잡으면 헌법의 `source()` 호출에서 NA 가 돼 죽는다
  #     ([[project-power-label-tautology-and-runner-path-20260808]]) → env 폴백 필수.
  .marker <- file.path("02_Infrastructure", "ops", "paper_research_dispatch.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (dir.exists(cand)) cand else getwd()
})
TARGET <- Sys.getenv("QVEST_DISPATCH_R",
                     file.path(.root, "02_Infrastructure", "ops", "paper_research_dispatch.R"))

PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

# ── 원본에서 판정 블록 추출 ──────────────────────────────────────────────────
extract_block <- function(path) {
  if (!file.exists(path)) { cat("FATAL: 대상 부재:", path, "\n"); quit(status = 2) }
  ln <- readLines(path, warn = FALSE, encoding = "UTF-8")
  b <- grep(">>> RISK_LANE_VERDICT", ln, fixed = TRUE)
  e <- grep("<<< RISK_LANE_VERDICT", ln, fixed = TRUE)
  if (length(b) != 1L || length(e) != 1L || e <= b) {
    cat("FATAL: 마커를 찾지 못했다 (b=", length(b), " e=", length(e), ") — ",
        "마커가 바뀌었으면 이 추출기부터 고칠 것. 조용히 0건 검사하는 것을 막기 위해 중단.\n", sep = "")
    quit(status = 2)
  }
  blk <- paste(ln[(b + 1):(e - 1)], collapse = "\n")
  # ★추출 범위 오류를 초록으로 넘기지 않는다 — 핵심 심볼이 다 있어야 한다.
  for (sym in c("risk_verdict", "risk_state", "risk_lane_arms", "delta_ir", "n_measured")) {
    if (!grepl(sym, blk, fixed = TRUE)) {
      cat(sprintf("FATAL: 추출 구간에 `%s` 가 없다 — 추출 범위 오류.\n", sym)); quit(status = 2)
    }
  }
  blk
}
BLOCK <- extract_block(TARGET)

# 돌연변이(수리 전): 실측과 무관하게 같은 문자열만 낸다.
LEGACY <- 'risk_verdict <- NULL
           risk_state <- "risk 레인 Σ-교체 A/B 하네스 미배선 — optimizer 레인 검증 후 착수 예정"'

# ── 픽스처 ───────────────────────────────────────────────────────────────────
ARMS_STD <- list(
  list(method_id = "PreferenceRobustDistortion", paper_id = "arxiv:x", adapter_kind = "weight",
       arm = "PreferenceRobustDistortion", control = "strategy", control_basis = "book 대비"),
  list(method_id = "ProperScoreGASFilter", paper_id = "arxiv:y", adapter_kind = "sigma",
       arm = "minvar@ProperScoreGASFilter", control = "minvar_lw", control_basis = "Σ만 교체")
)
CSV_FULL <- data.table(
  method = c("EW", "strategy", "minvar_lw", "MVO_lw",
             "minvar@ProperScoreGASFilter", "PreferenceRobustDistortion"),
  IR     = c(1.269, 1.410, 1.142, 1.383, 0.920, 0.658),
  PORT_t = c(5.302, 6.182, 4.679, 5.654, 3.850, 2.789))

TMP <- file.path(tempdir(), "risk_lane_fx"); dir.create(TMP, showWarnings = FALSE, recursive = TRUE)

#' 블록을 픽스처 위에서 평가.
#' @param csv NULL 이면 파일을 만들지 않는다(부재 케이스).
run_block <- function(src, csv, arms, fresh = TRUE, drop_cols = character(0)) {
  p <- file.path(TMP, "ov.csv")
  unlink(p, force = TRUE)
  if (!is.null(csv)) {
    d <- copy(csv); if (length(drop_cols)) d[, (drop_cols) := NULL]
    fwrite(d, p)
  }
  env <- new.env(parent = globalenv())
  assign("ov_csv", p, envir = env)
  assign("battery_fresh", fresh, envir = env)
  assign("risk_lane_arms", function(...) arms, envir = env)
  out <- utils::capture.output(eval(parse(text = src), envir = env))
  list(v = get0("risk_verdict", envir = env, ifnotfound = NULL),
       s = as.character(get0("risk_state", envir = env, ifnotfound = "")),
       log = paste(out, collapse = " | "))
}
armof <- function(v, id) { if (is.null(v)) return(NULL)
  for (r in v$arms) if (identical(r$method_id, id)) return(r); NULL }

cat("== risk 레인 판정 위반 주입 테스트 ==\n")
cat(sprintf("   대상: %s\n\n", TARGET))

cat("[A] 양성 대조 — 두 arm 다 산출에 있음\n")
rA <- run_block(BLOCK, CSV_FULL, ARMS_STD)
# ★R 최상위에서 `if (..) x` 다음 줄 `else` 는 파스 에러 — 반드시 중괄호로(저장소 기왕의 사고 축).
if (!is.null(rA$v) && rA$v$n_measured == 2L && rA$v$n_arms == 2L) {
  ok("2/2 측정 인식")
} else {
  bad("A 측정 인식", sprintf("v=%s", if (is.null(rA$v)) "NULL" else paste(rA$v$n_measured, rA$v$n_arms)))
}
.gas <- armof(rA$v, "ProperScoreGASFilter")
if (!is.null(.gas) && isTRUE(all.equal(.gas$delta_ir, round(0.920 - 1.142, 3)))) {
  ok(sprintf("Σ-추정기 Δ 정확: %.3f (arm 0.920 − 대조 minvar_lw 1.142)", .gas$delta_ir))
} else bad("A Δ 산술", sprintf("delta=%s", if (is.null(.gas)) "NULL" else .gas$delta_ir))
.prd <- armof(rA$v, "PreferenceRobustDistortion")
if (!is.null(.prd) && identical(.prd$control, "strategy") &&
    isTRUE(all.equal(.prd$delta_ir, round(0.658 - 1.410, 3)))) {
  ok(sprintf("weight-kind 는 book 대조: Δ %.3f", .prd$delta_ir))
} else bad("A weight-kind 대조", "control/Δ 불일치")
if (identical(rA$v$n_improved, 0L)) ok("개선 0건 (실측 정합)") else bad("A n_improved", rA$v$n_improved)

cat("\n[B] ★위반 주입 — 등재 arm 이 산출에 없음 (어댑터 로드 실패 상황)\n")
rB <- run_block(BLOCK, CSV_FULL[method != "minvar@ProperScoreGASFilter"], ARMS_STD)
.g <- armof(rB$v, "ProperScoreGASFilter")
if (!is.null(.g) && identical(.g$measured, FALSE) && is.na(.g$delta_ir) && !is.na(.g$note)) {
  ok("measured=FALSE + Δ=NA + note 발화 (조용히 넘기지 않음)")
} else bad("B 결손 검출", sprintf("measured=%s note=%s",
                                  if (is.null(.g)) "NULL" else .g$measured,
                                  if (is.null(.g)) "-" else .g$note))
if (!is.null(rB$v) && rB$v$n_measured == 1L) ok("n_measured 1/2 로 감소") else bad("B n_measured", "감소 안 함")

cat("\n[C] ★위반 주입 — 대조군(minvar_lw) 이 산출에 없음\n")
rC <- run_block(BLOCK, CSV_FULL[method != "minvar_lw"], ARMS_STD)
.g <- armof(rC$v, "ProperScoreGASFilter")
if (!is.null(.g) && identical(.g$measured, TRUE) && is.na(.g$delta_ir) &&
    !is.na(.g$note) && grepl("대조군", .g$note)) {
  ok("arm 은 측정됐지만 Δ 는 NA + 대조군 부재 호명 (Δ 를 지어내지 않음)")
} else bad("C 대조군 결손", sprintf("delta=%s note=%s",
                                    if (is.null(.g)) "-" else .g$delta_ir,
                                    if (is.null(.g)) "-" else .g$note))

cat("\n[D~G] 부재·결손을 정상값으로 내려앉히지 않는가\n")
rD <- run_block(BLOCK, CSV_FULL, ARMS_STD, fresh = FALSE)
if (is.null(rD$v) && grepl("배터리", rD$s)) {
  ok(sprintf("D 배터리 미실행 → verdict NULL · 사유=%s", rD$s))
} else { bad("D 배터리 미실행", rD$s) }
rE <- run_block(BLOCK, NULL, ARMS_STD)
if (is.null(rE$v)) ok(sprintf("E CSV 부재 → verdict NULL · 사유=%s", rE$s)) else bad("E CSV 부재", rE$s)
rF <- run_block(BLOCK, CSV_FULL, ARMS_STD, drop_cols = "IR")
if (is.null(rF$v) && grepl("컬럼|판독", rF$s)) {
  ok(sprintf("F IR 컬럼 결손 → verdict NULL · 사유=%s", rF$s))
} else { bad("F 컬럼 결손", rF$s) }
rG <- run_block(BLOCK, CSV_FULL, list())
if (is.null(rG$v) && grepl("0건", rG$s)) ok(sprintf("G arm 0건 → 명시 상태=%s", rG$s)) else bad("G arm 0건", rG$s)

cat("\n[H] ★역방향 양성 — 대조군을 이기는 arm 을 주입하면 개선으로 세는가\n")
CSV_WIN <- copy(CSV_FULL)[method == "minvar@ProperScoreGASFilter", IR := 1.500]
rH <- run_block(BLOCK, CSV_WIN, ARMS_STD)
.g <- armof(rH$v, "ProperScoreGASFilter")
if (!is.null(rH$v) && rH$v$n_improved == 1L && .g$delta_ir > 0) {
  ok(sprintf("n_improved 0 → 1, Δ %+.3f — '개선 0'만 뱉는 검사가 아님", .g$delta_ir))
} else bad("H 역방향", sprintf("n_improved=%s", if (is.null(rH$v)) "NULL" else rH$v$n_improved))

cat("\n[I] 실물 레지스트리 회귀 — risk_lane_arms() 가 실제로 arm 을 만드는가\n")
.mrp <- file.path(.root, "02_Infrastructure", "methods", "method_registry.R")
if (file.exists(.mrp)) {
  # ★최상위 on.exit() 금지(r-portability 금칙② — 미발화 → cleanup dead code). 명시 복귀만 쓴다.
  .wd <- getwd(); setwd(.root)
  e2 <- new.env(parent = globalenv())
  okS <- tryCatch({ suppressMessages(sys.source(.mrp, envir = e2)); TRUE }, error = function(e) FALSE)
  if (okS && exists("risk_lane_arms", envir = e2)) {
    ra <- tryCatch(get("risk_lane_arms", envir = e2)(), error = function(e) NULL)
    if (!is.null(ra) && length(ra) > 0) {
      ok(sprintf("실물 arm %d건: %s", length(ra),
                 paste(vapply(ra, function(a) sprintf("%s→%s", a$arm, a$control), character(1)), collapse = ", ")))
      .sig <- Filter(function(a) identical(a$adapter_kind, "sigma"), ra)
      if (!length(.sig) || all(vapply(.sig, function(a) grepl("^minvar@", a$arm), logical(1)))) {
        ok("sigma-kind arm 명명 규약 `minvar@<id>` 준수 (배터리 규약과 일치)")
      } else bad("I 명명 규약", "minvar@ 접두 아님")
    } else {
      # ★0건이 정상일 수도 있다(레지스트리에 implemented risk method 가 없을 때).
      #   그래도 **0 은 결론이 아니라 정지 신호**다 — 이유를 출력하고 통과시킨다.
      ok("실물 arm 0건 — 레지스트리에 implemented risk method 부재(상태 보고, 결함 아님)")
    }
  } else bad("I 실물", "method_registry.R source 실패 또는 risk_lane_arms 부재")
  setwd(.wd)
} else bad("I 실물", "method_registry.R 부재")

cat("\n[J] 돌연변이(수리 전 하드코딩 판) — 실측이 바뀌어도 보고가 안 바뀌어야 검사가 유효\n")
LEG <- list(A = run_block(LEGACY, CSV_FULL, ARMS_STD),
            B = run_block(LEGACY, CSV_FULL[method != "minvar@ProperScoreGASFilter"], ARMS_STD),
            H = run_block(LEGACY, CSV_WIN, ARMS_STD),
            D = run_block(LEGACY, CSV_FULL, ARMS_STD, fresh = FALSE))
.uniq_leg <- length(unique(vapply(LEG, function(r) r$s, character(1))))
.uniq_new <- length(unique(c(rA$s, rB$s, rH$s, rD$s)))
if (.uniq_leg == 1L && .uniq_new >= 3L) {
  ok(sprintf("legacy 는 4 픽스처에서 상태 1종(불변) · 수리판은 %d종 — 판별력 실증", .uniq_new))
} else {
  bad("J 판별력", sprintf("legacy 상태 %d종(기대 1) · 수리판 %d종(기대 ≥3)", .uniq_leg, .uniq_new))
}
if (all(vapply(LEG, function(r) is.null(r$v), logical(1)))) {
  ok("legacy 는 어떤 픽스처에서도 verdict 를 내지 않음 (= 원 결함의 정의)")
} else bad("J legacy verdict", "legacy 가 verdict 를 냄 — 돌연변이 구성 오류")

unlink(TMP, recursive = TRUE, force = TRUE)
cat(sprintf("\nFINAL: passed=%d failed=%d\n", PASS, FAIL))
## ★러너 집계용 요약 JSON — 이 줄이 없으면 run_all_hooks.sh 가 이 suite 를
##   UNREPORTED(=1 fail)로 계상하고 **통과 건수는 통째로 사라진다**.
##   위 FINAL 줄은 사람용이라 유지한다(둘 다 남긴다). 2026-08-09 추가.
cat(sprintf("{\"test\":\"risk_lane_verdict\",\"pass\":%d,\"fail\":%d,\"total\":%d}\n",
            PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0) 1 else 0)
