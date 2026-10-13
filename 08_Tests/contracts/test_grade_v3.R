## test_grade_v3.R — 등급 v3 진단 계약 검사기 (양방향: 양성 대조 + 위반 주입)
## 규약: "경고 0" 만으로는 검사기가 살아있는지 알 수 없다 — 일부러 틀린 입력을 넣어 발화를 확인한다.
## 대상: 02_Infrastructure/contracts/grade_v3.R (MC7 · S0 진단 모드 · v10.01 2026-10-13)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else dirname(sys.frame(1)$ofile %||% ".")
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- normalizePath(file.path(.qv_self_dir(), "..", ".."), mustWork = FALSE)
if (dir.exists(file.path(SELF, "02_Infrastructure/contracts"))) ROOT <- gsub("\\\\", "/", SELF)
setwd(ROOT)
source("02_Infrastructure/contracts/grade_v3.R")

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- list()
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
throws <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")

cfg <- gv3_cfg(ROOT); th <- gv3_thresholds(ROOT); w <- cfg$weights

cat("=== A. 종합점수 S ===\n")
chk("A1 S(Calmar_A, PORT_t_A) = 1 (정의 고정점)", isTRUE(all.equal(gv3_S(th$calmar_a, th$port_t_a, th, w), 1)))
chk("A2 교환 관계(README §2.2) ĉ 1.2 · p̂ 1.2^-1.5 → S = 1",
    isTRUE(all.equal(gv3_S(th$calmar_a * 1.2, th$port_t_a * 1.2^(-w$calmar / w$port_t), th, w), 1)))
s_c <- gv3_S(th$calmar_a * 1.1, th$port_t_a, th, w); s_p <- gv3_S(th$calmar_a, th$port_t_a * 1.1, th, w)
chk("A3 6:4 — Calmar 10% 개선이 PORT_t 10% 개선보다 S 를 더 올린다", s_c > s_p && isTRUE(all.equal(s_c, 1.1^w$calmar)) &&
      isTRUE(all.equal(s_p, 1.1^w$port_t)), sprintf("(%.4f vs %.4f)", s_c, s_p))
chk("A4 정의역 밖 → 0 (Calmar 0 · PORT_t 음수 · Calmar 음수)",
    identical(gv3_S(c(0, 1, -0.1), c(3, -0.5, 3), th, w), c(0, 0, 0)))
chk("A5 결측 → NA (0 으로 위장하지 않는다)", is.na(gv3_S(NA, 3, th, w)) && is.na(gv3_S(0.7, Inf, th, w)))
chk("A6 벡터화", isTRUE(all.equal(gv3_S(c(th$calmar_a, 0), c(th$port_t_a, 3), th, w), c(1, 0))))
w_sw <- list(calmar = w$port_t, port_t = w$calmar)
s64 <- gv3_S(th$calmar_a * 1.5, th$port_t_a * 0.8, th, w); s46 <- gv3_S(th$calmar_a * 1.5, th$port_t_a * 0.8, th, w_sw)
chk("A7 [위반 주입] 가중을 뒤집으면 S 가 바뀐다 — Calmar 우위 칸은 6:4 에서 더 높다(가중 방향 확인)", s64 > s46,
    sprintf("(6:4 %.4f · 4:6 %.4f)", s64, s46))

cat("=== B. 설정 · 문턱 정본 ===\n")
chk("B1 설정 — mode authoritative(MC7) · 가중 0.6/0.4 · B 경계 = 벤치 Calmar·B PORT_t 모서리의 S · C = S > 0 · 롤링 문턱 확정 · 구제 미탑재",
    identical(cfg$mode, "authoritative") && isTRUE(all.equal(c(w$calmar, w$port_t), c(0.6, 0.4))) &&
      identical(cfg$b_boundary$rule, "S_at_corner") && identical(cfg$c_boundary$rule, "S_gt_zero") &&
      identical(cfg$oos$rolling_pass_min_status, "confirmed") && identical(cfg$rescue$rolling_rescue_f_to_c, FALSE))
chk("B2 문턱 = tier_graduation 정본(폴백 아님)", grepl("constraint_defaults.json$", th$source %||% "") &&
      isTRUE(all.equal(c(th$calmar_a, th$port_t_a, th$port_t_b), c(0.64, 2.95, 2.0))),
    sprintf("(source=%s)", th$source))
TD <- file.path(tempdir(), sprintf("gv3_%d", Sys.getpid())); dir.create(TD, recursive = TRUE, showWarnings = FALSE)
j <- fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
jb <- j; jb$weights$calmar <- 0.7
pb <- file.path(TD, "bad_weights.json"); writeLines(toJSON(jb, auto_unbox = TRUE, null = "null"), pb)
chk("B3 [위반 주입] 가중 합 ≠ 1 → 멈춘다", throws(gv3_cfg(ROOT, path = pb)))
jm <- j; jm$cr_notch <- NULL
pm <- file.path(TD, "missing_key.json"); writeLines(toJSON(jm, auto_unbox = TRUE, null = "null"), pm)
chk("B4 [위반 주입] 필수 키 누락 → 멈춘다", throws(gv3_cfg(ROOT, path = pm)))
jr <- j; jr$b_boundary$rule <- "S_fixed_0.5"
pr_ <- file.path(TD, "bad_brule.json"); writeLines(toJSON(jr, auto_unbox = TRUE, null = "null"), pr_)
chk("B4b [위반 주입] B 경계 규칙 어휘 밖(고정 숫자) → 멈춘다(경계를 지어내지 않는다)", throws(gv3_cfg(ROOT, path = pr_)))
# 샌드박스 루트 — tier_graduation 키 하나가 빠진 정본 → 리터럴 폴백을 거부하고 멈춰야 한다
SB <- file.path(TD, "sb"); for (d in c("06_Registry", "02_Infrastructure/contracts", "02_Infrastructure/worktask"))
  dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
writeLines("sandbox", file.path(SB, "CLAUDE.md"))
for (f in c("backtest_result_contract.R", "essence_score.R", "rolling_grade.R", "behavior_card.R"))
  file.copy(file.path(ROOT, "02_Infrastructure/contracts", f), file.path(SB, "02_Infrastructure/contracts", f))
cd <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
cd$tier_graduation$min_calmar <- NULL
writeLines(toJSON(cd, auto_unbox = TRUE, null = "null", digits = NA), file.path(SB, "02_Infrastructure/worktask/constraint_defaults.json"))
chk("B5 [위반 주입] tier_graduation 키 결측 → 폴백 거부(멈춤)", suppressWarnings(throws(gv3_thresholds(SB))))
invisible(.gv3_deps(ROOT))   # 사적 환경을 정본 루트로 되돌린다

cat("=== C. 등급 결정표 (gv3_decide · GRADE-V3-S0-BANDS) ===\n")
F_ok <- c(port_t = TRUE, calmar = TRUE, cagr = TRUE, sharpe = TRUE)
O_ok <- c(test_window_cr_not_weak = TRUE, rolling36_pass_oos = TRUE)
SB <- 0.435                                                     # 그 전략의 B 경계(벤치 Calmar · B PORT_t 모서리의 S)
g <- function(S, cr = "normal", fl = F_ok, oo = O_ok, sb = SB, cf = cfg) gv3_decide(S, sb, fl, oo, cr, cf)
d1 <- g(1.2)
chk("C1 S ≥ 1 · 하한 · OOS 충족 · CR 보통 → A", identical(d1$grade, "A") && identical(d1$band, "A") && !length(d1$blocked_by))
f2 <- F_ok; f2["calmar"] <- FALSE; d2 <- g(1.2, fl = f2)
chk("C2 S ≥ 1 이나 Calmar 하한(벤치) 미달 → A 띠 차단 = B · 사유 floor:calmar",
    identical(d2$grade, "B") && identical(d2$band, "A") && "floor:calmar" %in% d2$blocked_by)
d3 <- g(1.2, "weak")
chk("C3 S ≥ 1 이나 CR 약함 → A 불가 · 한 단계 하향 = B(cr:weak · notch −1)",
    identical(d3$grade, "B") && "cr:weak" %in% d3$blocked_by && identical(d3$notch, -1L))
o4 <- O_ok; o4["rolling36_pass_oos"] <- FALSE; d4 <- g(1.2, "strong", oo = o4)
chk("C4 S ≥ 1 이나 OOS 롤링 미달 → B · CR 강함이어도 OOS 없이는 A 로 못 올린다",
    identical(d4$grade, "B") && "oos:rolling36_pass_oos" %in% d4$blocked_by && !isTRUE(d4$notch_a))
d5 <- g(0.9, "strong")
chk("C5 B 띠(S_B ≤ S < 1) · CR 강함 · 하한 · OOS 충족 → 노치로 A", identical(d5$band, "B") && identical(d5$grade, "A") && isTRUE(d5$notch_a))
f6 <- F_ok; f6["cagr"] <- FALSE; d6 <- g(0.9, "strong", fl = f6)
chk("C6 B 띠 · CR 강함이어도 하한 미달이면 B 에 머문다", identical(d6$grade, "B") && !isTRUE(d6$notch_a))
d7 <- g(0.3, "strong")
chk("C7 C 띠 · CR 강함 → B(+1 · 무조건)", identical(d7$band, "C") && identical(d7$grade, "B") && identical(d7$notch, 1L))
d8 <- g(0.3, "weak")
chk("C8 C 띠 · CR 약함 → F(한 단계 하향)", identical(d8$grade, "F") && identical(d8$notch, -1L))
d9 <- g(0, "strong")
chk("C9 S = 0 → F · CR 강함이어도 노치 없음(F 는 노치 밖)", identical(d9$grade, "F") && identical(d9$notch, 0L))
chk("C10 결측은 지어내지 않는다 — S = NA → NA · B 경계 결측(S 0.5) → NA · A 띠는 B 경계와 무관",
    is.na(g(NA_real_)$grade) && is.na(g(0.5, sb = NA_real_)$grade) && identical(g(1.2, sb = NA_real_)$grade, "A"))
chk("C11 B 경계는 전략마다 — 같은 S 0.5 라도 S_B 0.45 면 B · 0.55 면 C",
    identical(g(0.5, sb = 0.45)$grade, "B") && identical(g(0.5, sb = 0.55)$grade, "C"))
cfg_m <- cfg; cfg_m$cr_notch$applies_to <- "none"
chk("C12 [돌연변이] 노치 적용 범위를 끄면 C7 이 C 에 머문다 — 설정이 실제로 판정을 움직인다", identical(g(0.3, "strong", cf = cfg_m)$grade, "C"))
cfg_b <- cfg; cfg_b$cr_notch$a_blocked_to <- "C"
chk("C13 [돌연변이] A 띠 차단 행선을 C 로 바꾸면 C2 가 C — 차단 규칙이 설정에서 온다", identical(g(1.2, fl = f2, cf = cfg_b)$grade, "C"))
chk("C14 산출 어휘 ⊂ {A, B, C, F}", all(vapply(list(d1, d2, d3, d4, d5, d6, d7, d8, d9), function(d) d$grade, "") %in% c("A", "B", "C", "F")))
## '강함' 상향 노치 = MC8 선택(기전) 방어 동반 시만(GRADE-V3-CR-STRONG-SELECTION · 도훈 10-13 · MC8 보고서 §7)
cfg_s <- cfg; cfg_s$cr_notch$strong_requires <- "mc8_selection_defense"
crn <- function(cr, lab, cf = cfg_s) gv3_cr_for_notch(cr, lab, cf)
chk("C15 강함 + 선택 방어 → 강함 유지 · 크기 방어 · 노출 방어 · 방어 없음 · 판정 불가 · 대조 불가(NA) → 보통",
    identical(crn("strong", "selection_defense"), "strong") &&
      all(vapply(c("size_defense", "exposure_defense", "no_defense", "insufficient", NA_character_),
                 function(l) identical(crn("strong", l), "normal"), logical(1))))
chk("C16 약함 · 보통 · 판정 불가는 대조와 무관하게 그대로(하향 노치는 MC8 을 보지 않는다)",
    identical(crn("weak", "selection_defense"), "weak") && identical(crn("weak", NA_character_), "weak") &&
      identical(crn("normal", "size_defense"), "normal") && identical(crn("insufficient", NA_character_), "insufficient"))
chk("C17 [하위 호환] 요구 키가 없으면(구 설정) 강함이 그대로 통과", identical(gv3_cr_for_notch("strong", "size_defense", cfg), if (is.null(cfg$cr_notch$strong_requires) || identical(cfg$cr_notch$strong_requires, "none")) "strong" else "normal"))
gs <- function(S, lab) g(S, crn("strong", lab), cf = cfg_s)
chk("C18 C 띠 · CR 강함: 선택 방어면 B(+1) · 크기 방어면 C 에 머문다 — 크기 방어 착시로 오르지 않는다",
    identical(gs(0.3, "selection_defense")$grade, "B") && identical(gs(0.3, "size_defense")$grade, "C") && identical(gs(0.3, "size_defense")$notch, 0L))
chk("C19 B 띠 · CR 강함 · 하한 · OOS 충족: 선택 방어면 A(노치) · 방어 없음이면 B",
    identical(gs(0.9, "selection_defense")$grade, "A") && isTRUE(gs(0.9, "selection_defense")$notch_a) &&
      identical(gs(0.9, "no_defense")$grade, "B") && !isTRUE(gs(0.9, "no_defense")$notch_a))
ps <- file.path(TD, "gv3_sr.json"); cj <- fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
cj$cr_notch$strong_requires <- "bogus"; writeLines(toJSON(cj, auto_unbox = TRUE, null = "null", digits = NA), ps)
chk("C20 [위반 주입] strong_requires 어휘 밖 → 멈춘다", throws(gv3_cfg(ROOT, path = ps)))

cat("=== D. 실측 산출물 (재사용 경로 양성 대조 · 위반 주입) ===\n")
DIR <- file.path(ROOT, "stage_artifacts/replication/20260905_095537_1276/remeasure_close_t1_5562284e")
need <- c("02_nav.csv", "03_period_returns.csv", "05_benchmark_returns.csv", "06_metrics.csv",
          "07_benchmark_compare.csv", "authoritative_remeasure.json")
if (!all(file.exists(file.path(DIR, need)))) {
  SKIP <- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <- list(axis = "D", reason = "실측 산출물 디렉터리 없음", missing = DIR)
  cat("  [skip] D 전체 — 산출물 없음:", DIR, "\n")
} else {
  e <- .gv3_deps(ROOT)
  ctx <- list(cfg = cfg, th = th, bc_cfg = e$bc_cfg(ROOT), rg = e$rg_params(ROOT), bm_hist = gv3_bench_history(ROOT))
  r <- gv3_score_dir(DIR, ROOT, ctx)
  chk("D1 같은 계약 함수로 다시 잰 전기간 지표 = 권위 표 값 (|Δ| < 1e-9)", isTRUE(r$parity_max_abs < 1e-9),
      sprintf("(%.3g)", r$parity_max_abs))
  chk("D2 권위 JSON(표시 반올림)과 표 원값의 차이 ≤ 반올림 폭 5e-4", isTRUE(r$json_gap_max_abs <= 5e-4),
      sprintf("(%.3g)", r$json_gap_max_abs))
  chk("D3 S = 표 원값으로 계산한 값", isTRUE(all.equal(r$S, gv3_S(r$essence$calmar, r$essence$port_t, th, w))))
  X <- .gv3_read_dir(DIR)
  Bq <- .gv3_bench_as_strategy(X$br)
  self <- gv3_window(Bq$pr, X$br, Bq$nv, root = ROOT)
  chk("D4 벤치 Calmar 하한 = 같은 함수로 잰 벤치 자신의 Calmar(항등 대조)", isTRUE(all.equal(self$calmar, r$bench$calmar)),
      sprintf("(%.4f vs %.4f)", self$calmar, r$bench$calmar))
  chk("D5 τ_D 분할 — IS 관측 + OOS 관측 = 전체 관측", r$oos$is$n_obs + r$oos$oos$n_obs == nrow(X$pr),
      sprintf("(%d + %d vs %d)", r$oos$is$n_obs, r$oos$oos$n_obs, nrow(X$pr)))
  chk("D6 산출 어휘 — 등급 A/B/C/F · CR", r$grade_v3 %in% c("A", "B", "C", "F") &&
        r$card$cr %in% c("strong", "normal", "weak", "insufficient"))
  chk("D6b B 경계 = 같은 창 벤치 Calmar · 현행 B PORT_t 모서리의 S(전략마다)", isTRUE(all.equal(r$S_B, gv3_S(r$bench$calmar, th$port_t_b, th, w))),
      sprintf("(S_B %.4f)", r$S_B))
  chk("D7 pass_oos 문턱 = rolling_grade.json 의 기존 값(확정 · GRADE-V3-S0-BANDS)", isTRUE(all.equal(r$oos$pass_min, ctx$rg$rescue_min_recent_pass)) &&
        identical(r$oos$pass_min_status, "confirmed"))
  # 위반 주입 — 수익 시계열 한 점을 바꾼 사본: 재현 대조가 발화해야 한다(대조가 장식이 아님)
  MD <- file.path(TD, "mut"); dir.create(MD, showWarnings = FALSE)
  for (f in need) file.copy(file.path(DIR, f), file.path(MD, f), overwrite = TRUE)
  P <- fread(file.path(MD, "03_period_returns.csv")); i <- which.max(abs(P$ret_net))
  P[i, ret_net := ret_net + 0.05]; fwrite(P, file.path(MD, "03_period_returns.csv"))
  rm_ <- gv3_score_dir(MD, ROOT, ctx)
  chk("D8 [위반 주입] 수익 한 점 +5%p → 재현 대조 발화(|Δ| > 1e-6)", isTRUE(rm_$parity_max_abs > 1e-6),
      sprintf("(%.3g)", rm_$parity_max_abs))
}
cat("=== E. essence_score 통합 (MC7 권위 승격 · GRADE-V3-PROMOTE) ===\n")
if (!all(file.exists(file.path(DIR, c(need, "bt_result.rds"))))) {
  SKIP <- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <- list(axis = "E", reason = "실측 bt_result 없음", missing = file.path(DIR, "bt_result.rds"))
  cat("  [skip] E 전체 — bt_result.rds 없음\n")
} else {
  EE <- new.env(parent = globalenv())
  for (f in c("backtest_result_contract.R", "essence_score.R"))
    invisible(capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/contracts", f), envir = EE))))
  bt <- readRDS(file.path(DIR, "bt_result.rds"))
  rE <- EE$essence_score(bt, sidecar_log = FALSE)
  v3d <- gv3_score_dir(DIR, ROOT, gv3_ctx(ROOT))
  chk("E1 권위 grade = v3(grade_basis grade_v3) — 디렉터리 채점과 같은 등급",
      identical(rE$grade_basis, "grade_v3") && identical(rE$grade, v3d$grade_v3) && identical(rE$grade_v3$status, "ok"),
      sprintf("(essence %s · dir %s · status %s)", rE$grade, v3d$grade_v3, rE$grade_v3$status %||% "?"))
  chk("E2 구 5조건 판정은 grade_v921 로 보존(진단)", rE$grade_v921 %in% c("A", "B", "C", "F") &&
        grepl("| v921 ", rE$reasons, fixed = TRUE), sprintf("(v921 %s)", rE$grade_v921))
  rH <- EE$essence_score(bt, hard_fail = TRUE, sidecar_log = FALSE)
  chk("E3 judge hard_fail 주입 → F · v3 는 적용 밖(not_applicable)", identical(rH$grade, "F") &&
        identical(rH$grade_v3$status, "not_applicable"))
  rS <- EE$essence_score(bt, n_trials_cumulative = 1e6, selection_type = "sweep", sidecar_log = FALSE)
  chk("E4 스윕형 선정 · DSR 미달 → v3 에 gate:dsr_sweep 사유(A 불가)", "gate:dsr_sweep" %in% unlist(rS$grade_v3$blocked_by),
      paste(unlist(rS$grade_v3$blocked_by), collapse = ","))
  # [위반 주입] 등급 v3 계약이 없는 루트 — 구 판정으로 조용히 떨어지면 안 된다(NA = 미측정)
  SB2 <- file.path(tempdir(), sprintf("gv3_ess_%d", Sys.getpid()))
  dir.create(file.path(SB2, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(SB2, "02_Infrastructure/contracts"), recursive = TRUE, showWarnings = FALSE)
  writeLines("sandbox", file.path(SB2, "CLAUDE.md"))
  old_cpd <- Sys.getenv("CLAUDE_PROJECT_DIR", NA_character_)
  Sys.setenv(CLAUDE_PROJECT_DIR = SB2); EE$.essence_v3_reset()
  rN <- suppressWarnings(EE$essence_score(bt, sidecar_log = FALSE))
  if (is.na(old_cpd)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = old_cpd)
  EE$.essence_v3_reset(); unlink(SB2, recursive = TRUE)
  chk("E5 [위반 주입] v3 계약 부재 → 등급 NA(미측정) · 사유 '등급 v3 산출 실패' — v921 로 폴백하지 않는다",
      is.na(rN$grade) && identical(rN$grade_v3$status, "error") && grepl("등급 v3 산출 실패", rN$reasons, fixed = TRUE),
      sprintf("(grade %s · status %s)", rN$grade, rN$grade_v3$status %||% "?"))
}

unlink(TD, recursive = TRUE)

cat(sprintf("\n== grade_v3: PASS %d · FAIL %d · SKIP %d ==\n", PASS, FAIL, SKIP))
cat(toJSON(list(test = "grade_v3", pass = PASS, fail = FAIL, total = PASS + FAIL, skipped = SKIP, skips = SKIPS),
           auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0L) quit(status = 1L)
