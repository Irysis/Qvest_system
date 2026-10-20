## test_round_core_v1_p2.R — 공통 판정 코어 v1 짝 판정 모듈(pair.R · p2.R · p3.R · rules_p2.R) 검사(WP1-b · 2026-10-20 · 가벼움 — 원자료 적재 없음)
##   A 끝난 라운드 픽스처(P2R04 · P2R03 · P3R03 evaluate_fixture.R)를 코어 심으로 다시 돌린다 — 그 라운드 도우미 · 판정 1칸 경로 = 코어(검사 수까지 고정)
##   B 코어 뮤테이션(소스 텍스트 치환 · 치환 성사 단정 · 사본 단독 적재 — deparse 금지) C 규칙 종류(위기 과반 · β 짝 승 · 비열등 알파 · 상승 포착 · 축 감사)
##   D 작업 사본 최소 파일(β 짝 · 공통 창) E 샤딩 · 엔진 알파 병합 순서 F 메모 래퍼(ta_load_market) G τ_D(보는 창 계산이 시험 창 변화에 불변)
##   I 사양 라운드 배선(p2_device 템플릿) J P2R05 범용분 = 원판 황금값(08_Tests/fixtures/round_core_p2r05_golden.json · 생성기 rejudge/p2r05_golden.R)
##   H 결과 동일 요약(무거운 재판정 heavy_round_core_v1_p2_rejudge.R 의 기록 RESULTS.json — 세 라운드 판정 · 칸 판정 · 핵심 수치)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
throws <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
source("04_Research/programs/_lib/round_core/v1/load.R")
TAU <- as.Date("2022-12-31")
TMP <- gsub("\\\\", "/", file.path(tempdir(), "rc_p2_test")); unlink(TMP, recursive = TRUE); dir.create(TMP, recursive = TRUE)

cat("A 끝난 라운드 픽스처 — 코어 심\n")
source("04_Research/programs/_lib/round_core/rejudge/shims.R")
FX <- list(P2R04 = list(f = "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/evaluate_fixture.R", n = 52L),
           P2R03 = list(f = "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/evaluate_fixture.R", n = 33L),
           P3R03 = list(f = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/evaluate_fixture.R", n = 48L))
for (r in names(FX)) {
  p <- rc_fixture_sandbox(r, file.path(ROOT, FX[[r]]$f), ROOT, file.path(TMP, "fx"))
  o <- suppressWarnings(system2("Rscript", shQuote(p), stdout = TRUE, stderr = TRUE))
  j <- grep('^\\{"test"', o, value = TRUE); x <- if (length(j)) jsonlite::fromJSON(j[length(j)]) else list(pass = NA, fail = NA)
  chk(sprintf("A %s 픽스처 %d 검사 = 코어(실패 0 · 검사 수 고정)", r, FX[[r]]$n), identical(as.integer(x$fail), 0L) && identical(as.integer(x$pass), FX[[r]]$n),
      paste("pass", x$pass, "fail", x$fail, "|", paste(utils::tail(grep("FAIL|Error", o, value = TRUE), 3), collapse = " / ")))
}

cat("B 코어 뮤테이션\n")
mutant <- function(file, from, to) {
  src <- readLines(file.path(RC_DIR, file), encoding = "UTF-8", warn = FALSE)
  hit <- sum(grepl(from, src, fixed = TRUE)); if (hit != 1L) return(list(err = sprintf("치환 대상 %d줄(1줄이어야 함): %s", hit, from)))
  ms <- sub(from, to, src, fixed = TRUE); if (sum(ms != src) != 1L) return(list(err = paste("치환 불성사:", from)))
  p <- file.path(TMP, paste0("mut_", basename(tempfile()), ".R")); writeLines(ms, p, useBytes = TRUE)
  e <- new.env(parent = globalenv())
  ## rules_p2.R 사본은 적재 때 종류를 공용 등록부(RC_RULE_EXT)에 다시 등록한다 — 검사 뒤 원판을 다시 적재해 되돌린다(아래 루프)
  r0 <- tryCatch({ sys.source(p, envir = e, keep.source = FALSE); NULL }, error = function(z) conditionMessage(z))
  if (!is.null(r0)) return(list(err = paste("사본 적재 실패:", r0)))
  list(env = e)
}
cm_a <- list(list(peak_date = "2008-05-16", trough_date = "2008-10-24", dd_capture = 0.70), list(peak_date = "2011-04-22", trough_date = "2011-09-26", dd_capture = 0.50))
cm_b <- list(list(peak_date = "2008-05-16", trough_date = "2008-10-24", dd_capture = 0.73), list(peak_date = "2011-04-22", trough_date = "2011-09-26", dd_capture = 0.60))
TBv <- data.table(engine = c("E2", "E3"), device = "H1", tested = TRUE, pass = c(TRUE, FALSE), excluded = FALSE, verdict = c("pass", "not_decisive"))
FL <- list(crisis = TRUE, deep = TRUE, beta_deep = TRUE, fast = TRUE, beta_ratio = TRUE, bull = TRUE, alpha = TRUE, cycle = TRUE, construction = TRUE, S = TRUE, path = TRUE, selection = FALSE)
bsrc <- file.path(TMP, "bsrc"); dir.create(bsrc, recursive = TRUE)
dd <- seq(as.Date("2022-11-01"), by = "day", length.out = 120)
fwrite(data.table(date = dd, ret_net = 0.001, ret_gross = 0.0011), file.path(bsrc, "03_period_returns.csv"))
fwrite(data.table(date = dd, benchmark_ret = 0.0005, benchmark_nav = cumprod(rep(1.0005, 120))), file.path(bsrc, "05_benchmark_returns.csv"))
fwrite(data.table(date = dd, nav_gross = cumprod(rep(1.0011, 120)), nav_net = cumprod(rep(1.001, 120)), cum_cost = 0, drawdown_net = 0), file.path(bsrc, "02_nav.csv"))
fwrite(data.table(date = rep(dd[c(1, 60)], each = 2), ticker = rep(c("000660", "005930"), 2), target_weight = 0.5), file.path(bsrc, "04_holdings.csv"))
for (f in c(RC_ARTIFACT_MINIMAL, "06_metrics.csv", "bt_result.rds", "analysis_report.md")) writeLines("x", file.path(bsrc, f))
TS <- list(name = "t", cfg = list(), init = function(ctx, opts) list(a = 1), untested = function(out, why) { out$why <- why; out$tested <- FALSE; out },
           stages = list(function(S) "중단", function(S) { S$out$after <- TRUE; NULL }))
fake_E <- function() { E <- new.env(); E$n <- 0L; E$ta_root <- function(root = NULL) root
  E$ta_load_market <- function(root = NULL, cfg, from, to = NULL, raw_path = NULL, bm_path = NULL, extra_tickers = character(0)) { E$n <- E$n + 1L; list(id = E$n, tk = sort(extra_tickers)) }
  E }
rt <- rc_rules_resolve(list(list(id = "b", type = "beta_pair_win", label = "③", crises = "deep", majority = 0.5, basis = "검사")))
noc <- function(dv, eng, tested = TRUE) list(device = dv, engine = eng, tested = tested, rules = list(beta_deep = list(status = "ok", n_pair = 3L, share = 0.3)),
                                             non_inferiority = list(S = 1.01, S_rx0 = 1))
NO1 <- list(noc("H1", "E2"), noc("H1", "E3"), noc("H2", "E2", FALSE), noc("H2", "E3", FALSE))   # 판정된 장치 1 < 2 = 판독 불가(NA)
## P2R05 범용분 황금값(원판 P2R05 evaluate.R 정의로 만든 기록 — 생성기 rejudge/p2r05_golden.R) — J 와 뮤테이션이 같이 쓴다
GE <- new.env(); sys.source(file.path(dirname(RC_DIR), "rejudge", "p2r05_golden.R"), envir = GE)
GJ <- jsonlite::fromJSON("08_Tests/fixtures/round_core_p2r05_golden.json", simplifyVector = FALSE)
GC <- GE$rc_golden_cases(file.path(TMP, "golden"))
gdiff <- function(env) { got <- GE$rc_golden_run(GC, function(fn) get(GE$RC_GOLDEN_FNS[[fn]][2], envir = env))
  ks <- union(names(GJ$cases), names(got)); ks[!vapply(ks, function(k) identical(got[[k]], GJ$cases[[k]]), logical(1))] }
MU <- list(
  list(nm = "위기 개선 경계(< → <=)", f = "pair.R", from = "nb <- sum(J$m < J$r - tol)", to = "nb <- sum(J$m <= J$r - tol)",
       kill = function(e) !identical(e$rc_crisis_majority(cm_a, cm_b, 0.03)$n_better, 1L)),
  list(nm = "칸 통과 ⑭ 요구 제거", f = "p2.R", from = "isTRUE(f$path) && isTRUE(f$selection)", to = "isTRUE(f$path)",
       kill = function(e) isTRUE(e$rc_p2_cell_pass(FL))),
  list(nm = "β 짝 k ≥ 1 분기 제거", f = "pair.R", from = 'mode <- if (!is.finite(k) || k <= 0) "unmeasured" else if (k >= 1) "rx0" else "scaled"',
       to = 'mode <- if (!is.finite(k) || k <= 0) "unmeasured" else "scaled"', kill = function(e) !identical(e$rc_beta_plan(1.2, 1)$mode, "rx0")),
  list(nm = "두 엔진 조건 완화", f = "pair.R", from = "both <- agg[n_pass == 2L & !ex][[unit]]", to = "both <- agg[n_pass >= 1L & !ex][[unit]]",
       kill = function(e) identical(e$rc_round_verdict(copy(TBv), "device", RC_P2_VERDICTS, RC_P2_VERDICT_SHORT)$both, "H1")),
  list(nm = "최소 사본 필터 제거", f = "pair.R", from = 'keep <- function(b) !isTRUE(minimal) || b %in% RC_ARTIFACT_MINIMAL || grepl("^0[2-5]_.*[.]csv$", b)', to = "keep <- function(b) TRUE",
       kill = function(e) { od <- file.path(TMP, "mut_min"); unlink(od, recursive = TRUE); e$rc_beta_scaled_copy(bsrc, od, 0.8, mark = FALSE, minimal = TRUE)
                            file.exists(file.path(od, "bt_result.rds")) }),
  list(nm = "R7 판독 불가 규칙 제거", f = "p2.R", from = "readable <- nb >= 2L", to = "readable <- TRUE",
       kill = function(e) !is.na(e$rc_p2_noise_reading(NO1, character(0), 0.02, 0.5, c("H1", "H2"))$result)),
  list(nm = "단계 미시험 뒤 계속", f = "pair.R", from = "if (!is.null(why)) return(T$untested(S$out, why))", to = "if (!is.null(why)) NULL",
       kill = function(e) isTRUE(e$rc_pair_run(list(), TS, list())$after)),
  list(nm = "메모 키가 보유 종목을 무시", f = "pair.R", from = "sort(unique(as.character(extra_tickers)))))", to = "character(0)))",
       kill = function(e) { E <- fake_E(); e$rc_memo_install(E); a <- E$ta_load_market("r", list(), "2020-01-01", extra_tickers = "A"); b <- E$ta_load_market("r", list(), "2020-01-01", extra_tickers = "B")
                            identical(a, b) }),
  list(nm = "샤드 배정 한 칸 밀림", f = "pair.R", from = "which((seq_len(n) - 1L) %% v[2] == (v[1] - 1L))", to = "which(seq_len(n) %% v[2] == (v[1] - 1L))",
       kill = function(e) !identical(e$rc_shard_index(5L, "1/2"), c(1L, 3L, 5L))),
  list(nm = "보는 창 시험 창 알파 제거 누락", f = "p2.R", from = 'RC_P2_VISIBLE_DROP <- c("alpha_test_window", "tbl", "cell_log_full_period")',
       to = 'RC_P2_VISIBLE_DROP <- c("tbl", "cell_log_full_period")', kill = function(e) !is.null(e$rc_p2_visible_only(list(alpha_test_window = 1), TAU, e$RC_P2_VISIBLE_DROP)$alpha_test_window)),
  list(nm = "size_or_exposure_defense 분기 제거", f = "p2.R", from = 'if (isTRUE(r3) && isTRUE(r4) && !s14) "size_or_exposure_defense" else', to = 'if (FALSE) "size_or_exposure_defense" else',
       kill = function(e) !identical(e$rc_p2_cell_verdict(list(pass = FALSE, beta_unmeasured = FALSE, beta_deep = TRUE, fast = TRUE, crisis = FALSE, deep = FALSE, selection = FALSE,
                                                              selection_measured = TRUE)), "size_or_exposure_defense")),
  list(nm = "P3 β 짝 k ≥ 1 = 통과 뒤집기", f = "p3.R", from = 'if (k >= 1) return(list(status = "not_needed", beats = TRUE))', to = 'if (k >= 1) return(list(status = "not_needed", beats = FALSE))',
       kill = function(e) !isTRUE(e$rc_p3_beta_verdict(1.1, 0.5, NA, NA, 0.5)$beats)),
  list(nm = "규칙 위기 과반 짝 하한 무시", f = "rules_p2.R", from = "ifelse(is.finite(n) & n >= r[[\"min_pairs\"]] & is.finite(s), s > r[[\"value\"]], NA)",
       to = "ifelse(is.finite(s), s > r[[\"value\"]], NA)",
       kill = function(e) !is.na(rc_rules_apply(rt, data.table(beta_deep_n_pair = 1, beta_deep_share = 1))$b)),
  list(nm = "선언 · 단계 대조 결함 숨김", f = "rules_p2.R", from = "if (length(diff)) bad <- c(bad,", to = "if (FALSE) bad <- c(bad,",
       kill = function(e) isTRUE(e$rc_p2_rules_crosscheck(rt, list(list(cell = "x", tested = TRUE, rules = list(beta_deep = list(n_pair = 3, share = 1, status = "ok", ok = TRUE)))),
                                                           NULL, list(b = function(x) FALSE))$ok)),
  list(nm = "유동성 3분위 분위수 정의 바뀜(type 7 → 1)", f = "p2.R", from = "bp <- stats::quantile(u, probs = seq_len(k - 1L) / k, names = FALSE, type = 7)",
       to = "bp <- stats::quantile(u, probs = seq_len(k - 1L) / k, names = FALSE, type = 1)", kill = function(e) length(gdiff(e)) > 0L))
nk <- 0L
for (m in MU) {
  mt <- mutant(m$f, m$from, m$to)
  if (!is.null(mt$err)) { chk(paste("B 뮤테이션", m$nm), FALSE, mt$err); next }
  k <- tryCatch(isTRUE(m$kill(mt$env)), error = function(z) TRUE)                 # 사본이 멈추면 잡힌 것
  if (identical(m$f, "rules_p2.R")) source(file.path(RC_DIR, "rules_p2.R"))       # 등록 종류 원래대로
  if (k) nk <- nk + 1L else chk(paste("B 뮤테이션 생존", m$nm), FALSE)
}
chk(sprintf("B 뮤테이션 %d/%d 검출(치환 대상 1줄 · 치환 성사 · 사본 단독 적재)", nk, length(MU)), nk == length(MU))
## 원판은 같은 검사를 통과한다(뮤테이션 검사의 음성 대조)
chk("B 원판 음성 대조 — 같은 검사에서 원판은 살아남는다", identical(rc_crisis_majority(cm_a, cm_b, 0.03)$n_better, 1L) && !isTRUE(rc_p2_cell_pass(FL)) &&
      is.na(rc_p2_noise_reading(NO1, character(0), 0.02, 0.5, c("H1", "H2"))$result) && is.na(rc_rules_apply(rt, data.table(beta_deep_n_pair = 1, beta_deep_share = 1))$b) &&
      identical(rc_beta_plan(1.2, 1)$mode, "rx0") && !identical(rc_round_verdict(copy(TBv), "device", RC_P2_VERDICTS, RC_P2_VERDICT_SHORT)$both, "H1") &&
      identical(rc_shard_index(5L, "1/2"), c(1L, 3L, 5L)) && !isTRUE(rc_pair_run(list(), TS, list())$after) && isTRUE(rc_p3_beta_verdict(1.1, 0.5, NA, NA, 0.5)$beats))

cat("C 규칙 종류(rules_p2)\n")
BC <- "06_Registry/behavior_card.json"
RD <- list(list(id = "crisis", type = "crisis_majority", label = "① 위기 과반", vs = "rx0", crises = "all", majority_ref = paste0(BC, "::majority_share")),
           list(id = "beta_deep", type = "beta_pair_win", label = "③ β 짝 깊은 위기", majority_ref = paste0(BC, "::majority_share")),
           list(id = "bull", type = "up_capture", label = "⑥ 강세", segments = TRUE, floor_ref = paste0(BC, "::uc_floor"), majority_ref = paste0(BC, "::majority_share")),
           list(id = "alpha", type = "alpha_noninferior", label = "⑦ 알파", t_floor = -2, margin_frac = 0.2, basis = "헌장 빈칸 4(C)(2026-10-16 도훈 확정)"),
           list(id = "axis", type = "axis_audit", label = "축 감사"),
           list(id = "pass", type = "all_of", label = "통과", of = list(list(id = "p_b", type = "beta_pair_win", label = "③", majority_ref = paste0(BC, "::majority_share")),
                                                                      list(id = "p_a", type = "axis_audit", label = "축"))))
RR <- rc_rules_resolve(RD)
maj <- as.numeric(rc_ref_value(paste0(BC, "::majority_share")))
chk("C1 정본 참조 해석(행동 카드 majority_share · uc_floor) · 근거 · 미측정 의미가 문장에 실린다", identical(RR[[1]]$value, maj) && grepl(BC, rc_rules_sentences(RR)[["crisis"]], fixed = TRUE) &&
      grepl("미측정 = 미시험", rc_rules_sentences(RR)[["alpha"]]) && grepl("−2|-2", rc_rules_sentences(RR)[["alpha"]]))
chk("C2 수치 근거 없음 = 거부(하드코딩 금지)", throws(rc_rules_validate(list(list(id = "a", type = "alpha_noninferior", label = "a", t_floor = -2, margin_frac = 0.2)))))
chk("C3 모르는 위기 조합 = 거부", throws(rc_rules_validate(list(list(id = "c", type = "crisis_majority", label = "c", vs = "rx0", crises = "fast", majority = 0.5, basis = "b")))))
TT <- data.table(crisis_n_pair = c(6, 6, 1, 6), crisis_share = c(0.67, 0.5, 1, NA), beta_deep_n_pair = c(3, 1, 3, 0), beta_deep_share = c(1, 1, 0.34, NA),
                 uc_vis = c(0.9, 0.5, 0.9, NA), bull_share = c(0.75, 0.75, 0.25, 0.75), alpha_t_vis = c(1, -3, 1, NA), alpha_d_vis = c(-0.01, 0, -0.05, NA),
                 engine_alpha_vis = c(0.10, 0.10, 0.10, NA), axis_ok = c(TRUE, TRUE, FALSE, NA))
A <- rc_rules_apply(RR, TT)
chk("C4 위기 과반 — 엄격 >(0.5 = 미달) · 짝 < 2 = 미측정 · 비율 NA = 미측정", identical(A$crisis, c(maj < 0.67, FALSE, NA, NA)), paste(A$crisis))
chk("C5 β 짝 승 — 짝 < 2 · 사본 실패(짝 0) = 미측정(통과로 접지 않음)", identical(A$beta_deep, c(TRUE, NA, FALSE, NA)), paste(A$beta_deep))
chk("C6 상승 포착 — 하한 ∧ 강세 구간 과반 · 입력 NA = 미측정", identical(A$bull, c(TRUE, FALSE, FALSE, NA)), paste(A$bull))
chk("C7 비열등 알파 — t > −2 ∧ 증분 ≥ −0.2 × max(엔진 α, 0)(−0.01 통과 · −0.05 미달) · NA = 미측정", identical(A$alpha, c(TRUE, FALSE, FALSE, NA)), paste(A$alpha))
chk("C8 축 감사 · all_of Kleene(거짓 우선 · 미측정 보존)", identical(A$axis, c(TRUE, TRUE, FALSE, NA)) && identical(A$pass, c(TRUE, NA, FALSE, NA)), paste(A$pass))
chk("C9 τ_D — 판정 규칙이 시험 창 열을 쓰면 멈춘다 · 보는 창 열은 통과", !throws(rc_p2_rules_tau_check(RR)) &&
      throws(rc_p2_rules_tau_check(rc_rules_resolve(list(list(id = "x", type = "threshold", label = "x", metric = "alpha_ann_test", op = ">", value = 0, basis = "b"))))))
chk("C10 DESIGN 표 — 확장 종류도 한 줄(지표 · 비교 · 값 · 출처)", length(rc_rules_table_md(RR)) == 2L + 8L && any(grepl("beta_deep_share", rc_rules_table_md(RR), fixed = TRUE)))
OUTx <- list(list(cell = "c1", tested = TRUE, rules = list(crisis = list(n_pair = 6, share = 0.67, ok = TRUE), beta_deep = list(n_pair = 3, share = 1, status = "ok", ok = TRUE))),
             list(cell = "c2", tested = TRUE, rules = list(crisis = list(n_pair = 6, share = 0.5, ok = FALSE), beta_deep = list(n_pair = 1, share = 1, status = "unmeasured(짝 < 2)", ok = FALSE))))
RC2 <- rc_rules_resolve(list(list(id = "crisis", type = "crisis_majority", label = "①", vs = "rx0", crises = "all", majority = 0.5, basis = "검사"),
                             list(id = "beta_deep", type = "beta_pair_win", label = "③", majority = 0.5, basis = "검사")))
cc_ok <- rc_p2_rules_crosscheck(RC2, OUTx, NULL, RC_P2_RULES_MAP[c("crisis", "beta_deep")])
OUTy <- OUTx; OUTy[[1]]$rules$crisis$ok <- FALSE
cc_bad <- rc_p2_rules_crosscheck(RC2, OUTy, NULL, RC_P2_RULES_MAP[c("crisis", "beta_deep")])
chk("C11 선언 판정 = 단계 판정 대조 — 같으면 통과(③ 미측정 = 미측정) · 단계 판정이 어긋나면 그 칸 · 규칙을 짚는다", isTRUE(cc_ok$ok) && !isTRUE(cc_bad$ok) && grepl("c1", cc_bad$mismatches[1]))
chk("C12 사양 params — 정본 참조 · 근거 있는 값 · 근거 없는 값 거부", identical(rc_spec_params(list(params = list(m = list(value_ref = paste0(BC, "::majority_share")), t = list(value = 0.03, basis = "P2R01 승계"))), ROOT),
                                                                            list(m = maj, t = 0.03)) && throws(rc_spec_params(list(params = list(t = list(value = 0.03))), ROOT)))

## 실데이터 — P2R04 저장 판정(구 evaluate.R 산출 · git 추적 evaluation_visible.json)에 같은 판정의 선언판(rules_p2 6종 · 값 = 사전등록 final_selection_rule)을 적용
X4 <- new.env(); sys.source(file.path(dirname(RC_DIR), "rejudge", "P2R04_ext.R"), envir = X4)
V4 <- jsonlite::fromJSON("04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/results/evaluation_visible.json", simplifyVector = FALSE)
P4 <- jsonlite::fromJSON("stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/prereg.json", simplifyVector = FALSE)
R4 <- rc_rules_resolve(Filter(function(z) !identical(z$type, "axis_audit"), X4$p2r04_rules(P4[["final_selection_rule"]])))
cc4 <- rc_p2_rules_crosscheck(R4, V4$cells, NULL, X4$p2r04_rules_map[c("crisis", "deep", "beta_deep", "fast", "bull", "alpha")])
n4 <- sum(vapply(V4$cells, function(x) isTRUE(x$tested), logical(1)))
chk(sprintf("C13 P2R04 저장 판정(구 evaluate.R) = 선언 규칙 판정 — 판정된 짝 %d × 규칙 6(① ② ③ ④ ⑥ ⑦)", n4), isTRUE(cc4$ok) && n4 >= 2L, paste(cc4$mismatches, collapse = " / "))

cat("D 작업 사본 최소 파일\n")
fo <- file.path(TMP, "full_copy"); mo <- file.path(TMP, "min_copy")
rc_beta_scaled_copy(bsrc, fo, 0.7, mark = TRUE, minimal = FALSE); rc_beta_scaled_copy(bsrc, mo, 0.7, mark = TRUE, minimal = TRUE)
same <- function(f) identical(rc_md5(file.path(fo, f)), rc_md5(file.path(mo, f)))
chk("D1 β 짝 최소 사본 — 02~05 · 최소 파일 바이트 동일 · 그 밖 파일 없음 · 표식", all(vapply(c("02_nav.csv", "03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv", RC_ARTIFACT_MINIMAL), same, logical(1))) &&
      setequal(list.files(mo), c("02_nav.csv", "03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv", RC_ARTIFACT_MINIMAL, RC_FULL_MARK)) &&
      file.exists(file.path(fo, "bt_result.rds")))
ft <- file.path(TMP, "full_trim"); mt <- file.path(TMP, "min_trim")
rc_trim_artifacts(bsrc, ft, dd[30], mark = FALSE, minimal = FALSE); rc_trim_artifacts(bsrc, mt, dd[30], mark = FALSE, minimal = TRUE)
chk("D2 공통 창 최소 사본 — 02~05 · 최소 파일 바이트 동일 · 표식 없음(구판 P2R03 · P3R03 형)", all(vapply(c("02_nav.csv", "03_period_returns.csv", "04_holdings.csv", "05_benchmark_returns.csv", RC_ARTIFACT_MINIMAL),
                                                                                         function(f) identical(rc_md5(file.path(ft, f)), rc_md5(file.path(mt, f))), logical(1))) &&
      !file.exists(file.path(mt, RC_FULL_MARK)) && !file.exists(file.path(mt, "06_metrics.csv")))
chk("D3 β 짝 k 범위 — (0, 1] 밖 = 멈춤 · 머리말(errtag) 구판 문구", throws(rc_beta_scaled_copy(bsrc, file.path(TMP, "kx"), 1.2)) &&
      grepl("^\\[p3_beta\\]", tryCatch(rc_beta_scaled_copy(bsrc, file.path(TMP, "kx"), -1, errtag = "p3_beta"), error = function(e) conditionMessage(e))))

cat("E 샤딩 · 병합 순서\n")
ix <- lapply(1:3, function(i) rc_shard_index(10L, sprintf("%d/3", i)))
chk("E1 샤드 = 교차 배정(rk_shard 와 같은 규칙) · 겹침 없음 · 합 = 전부", identical(sort(unlist(ix)), 1:10) && identical(ix[[1]], c(1L, 4L, 7L, 10L)) && throws(rc_shard_index(3L, "4/3")))
codes <- c("p1", "p2", "p3", "p4"); metas <- list(p1 = "E2 original", p2 = "E2 common_20050301", p3 = "E2 original", p4 = "E3 original")
vals <- list(`E2 common_20050301` = list(a = 2), `E2 original` = list(a = 1), `E3 original` = list(a = 3))
single <- new.env(); for (cd in codes) if (is.null(single[[metas[[cd]]]])) assign(metas[[cd]], vals[[metas[[cd]]]], envir = single)
rep_ea <- rc_ea_replay(codes, metas, vals)
chk("E2 엔진 알파 병합 = 단일 프로세스 삽입 순서 · 값(as.list 바이트 동일)", identical(jsonlite::toJSON(as.list(single)), jsonlite::toJSON(as.list(rep_ea))))
rc_pair_save(file.path(TMP, "pairs"), "p1", list(out = list(x = data.table(a = 1:2), y = NULL), ek = "E2 original"))
pl1 <- rc_pair_load(file.path(TMP, "pairs"), "p1"); pl0 <- list(out = list(x = data.table(a = 1:2), y = NULL), ek = "E2 original")
chk("E3 짝 결과 저장 · 읽기 왕복 = 같은 값 · 같은 JSON(데이터 표 자기 참조 포인터만 다름)", isTRUE(all.equal(pl1, pl0)) &&
      identical(jsonlite::toJSON(pl1, auto_unbox = TRUE, null = "null", na = "null", digits = NA), jsonlite::toJSON(pl0, auto_unbox = TRUE, null = "null", na = "null", digits = NA)))

cat("F 메모 래퍼(ta_load_market)\n")
E <- fake_E(); rc_memo_install(E)
a1 <- E$ta_load_market("r", list(k = 1), "2020-01-01", "2022-12-31", extra_tickers = c("B", "A"))
a2 <- E$ta_load_market("r", list(k = 1), "2020-01-01", "2022-12-31", extra_tickers = c("A", "B", "A"))
a3 <- E$ta_load_market("r", list(k = 1), "2020-01-01", "2022-12-31", extra_tickers = "C")
a4 <- E$ta_load_market("r", list(k = 2), "2020-01-01", "2022-12-31", extra_tickers = c("A", "B"))
chk("F1 같은 입력(보유 종목 순서 · 중복 무관) = 같은 결과 · 원래 함수 1회 · 다른 종목 · 설정 = 새로 부른다", identical(a1, a2) && identical(E$n, 3L) && !identical(a1, a3) && !identical(a1, a4))
chk("F2 래퍼 이중 설치 없음(표식)", { rc_memo_install(E); isTRUE(attr(E$ta_load_market, "rc_memo")) })

cat("G τ_D — 보는 창 계산은 시험 창 변화에 불변\n")
E2 <- rc_deps(ROOT)
mk <- function(dir, tail_mult, seed = 7L) {
  d <- seq(as.Date("2018-01-02"), as.Date("2024-06-28"), by = "day"); d <- d[!weekdays(d) %in% c("토요일", "일요일", "Saturday", "Sunday")]
  set.seed(seed); r <- rnorm(length(d), 0.0004, 0.01); set.seed(99L); b <- rnorm(length(d), 0.0002, 0.009); k <- d > TAU; r[k] <- r[k] * tail_mult
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(data.table(date = d, ret_net = r, ret_gross = r), file.path(dir, "03_period_returns.csv"))
  fwrite(data.table(date = d, benchmark_ret = b), file.path(dir, "05_benchmark_returns.csv"))
  fwrite(data.table(date = d, nav_net = cumprod(1 + r)), file.path(dir, "02_nav.csv"))
  H <- data.table(date = d[c(1, 400, 1300)], ticker = c("000660", "005930", "005930"), target_weight = c(1, 0.5, 0.7))
  H <- rbind(H, if (tail_mult == 1) data.table(date = d[1500], ticker = "035420", target_weight = 0.3) else data.table(date = d[c(1500, 1600)], ticker = c("035420", "000660"), target_weight = c(0.6, 0.3)))
  fwrite(H, file.path(dir, "04_holdings.csv"))
  writeLines('{"measurement_regime":{"exec_price":"close_t1"}}', file.path(dir, "authoritative_remeasure.json"))
  dir
}
u1 <- mk(file.path(TMP, "tau_a"), 1); u2 <- mk(file.path(TMP, "tau_b"), 5); ub <- mk(file.path(TMP, "tau_base"), 1, seed = 8L)
pa1 <- rc_pair_alpha(E2, u1, ub, TAU); pa2 <- rc_pair_alpha(E2, u2, ub, TAU)
c1 <- rc_concentration(u1, TAU); c2 <- rc_concentration(u2, TAU)
chk("G1 증분 β-통제 알파 보는 창 · 보유 집중 보는 창 = 시험 창을 흔들어도 바이트 동일(시험 창 판은 달라진다)",
    identical(jsonlite::toJSON(pa1$visible, digits = NA), jsonlite::toJSON(pa2$visible, digits = NA)) && !identical(pa1$test$d_alpha, pa2$test$d_alpha) &&
      identical(c1$visible, c2$visible) && !identical(c1$full, c2$full))
XV <- list(alpha_test_window = list(t = 1), tbl = data.table(a = 1), cell_log_full_period = list(v = 1), why = "실패 2023-05-02", rules = list(ym = c("2022-12", "2024-01")))
VO <- rc_p2_visible_only(XV, TAU)
chk("G2 보는 창 칸 — 사람 쪽 항목 제거 · τ_D 이후 날짜 가림 · 누출 검사 0(계약 dp_scan_dates · 코어 rc_after_tau_leaks 둘 다)",
    is.null(VO$alpha_test_window) && is.null(VO$tbl) && !length(dp_scan_dates(VO, TAU)) && !length(rc_after_tau_leaks(VO, TAU)) && length(rc_after_tau_leaks(XV, TAU)) > 0L)

cat("I 사양 라운드 배선(template p2_device — 측정 없는 격리 라운드 · 계약 · 판정 단계 · 보는 창 파일까지)\n")
IR <- file.path(TMP, "P2R99_core_pair_selftest"); dir.create(file.path(IR, "results"), recursive = TRUE); dir.create(file.path(IR, "specs"))
for (cd in c("P2R99_E2_RX0", "P2R99_E2_H1", "P2R99_E3_RX0", "P2R99_E3_H1")) {
  writeLines('{"factors":[]}', file.path(IR, "specs", paste0(cd, ".json")))
  for (t in c("start", "end")) writeLines(".cache/RAWDATA.parquet 1 1", file.path(IR, "results", sprintf("%s.fp_%s", cd, t)))
}
ispec <- list(schema = "round_spec_v1", program = "P2_DEFENSE", round_id = "P2R99_core_pair_selftest", template = "p2_device", core_version = "v1", tau_d = "2022-12-31",
              cells = lapply(c("E2", "E3"), function(e) lapply(c("RX0", "H1"), function(cp) list(code = sprintf("P2R99_%s_%s", e, cp), engine = e, component = cp,
                                                                                                   role = if (cp == "RX0") "reference" else "variant", spec = rc_rel(file.path(IR, "specs", sprintf("P2R99_%s_%s.json", e, cp)))))),
              devices = list(H1 = list(kind = "db", id = "D03_RealVol", name = "저변동")),
              params = list(majority_share = list(value_ref = paste0(BC, "::majority_share")), crisis_improve_min = list(value = 0.03, basis = "P2R01 승계"),
                            uc_floor = list(value_ref = paste0(BC, "::uc_floor"))),
              rules = RD[1:2], selection = list(rule = "none"), exposures = list(), behavior_card_cfg = BC)
ispec$cells <- unlist(ispec$cells, recursive = FALSE)
IP <- list(prereg = file.path(IR, "prereg.json"), results = file.path(IR, "results"))
writeLines("{}", IP$prereg)
ipre <- list(behavior_card_cfg = list(path = BC, md5 = rc_md5(BC)), rules_resolved = rc_rules_resolve(ispec$rules), sentences = as.list(rc_rules_sentences(rc_rules_resolve(ispec$rules))))
iv <- tryCatch(rc_p2_evaluate(ispec, ipre, ROOT, IR, IP), error = function(e) list(error = conditionMessage(e)))
ivis <- if (file.exists(file.path(IR, "results", "evaluation_visible.json"))) jsonlite::fromJSON(file.path(IR, "results", "evaluation_visible.json"), simplifyVector = FALSE) else list()
chk("I1 사양 → 템플릿 → 칸 평가(측정 없음 = not_measured) → 짝 미시험 → 라운드 판정 'untested(판정 0/2)' · 선언 대조 ok · 보는 창 · 사람 쪽 파일",
    is.null(iv$error) && identical(iv$verdict, "untested") && grepl("판정 0/2", iv$verdict_label) && isTRUE(iv$rules_crosscheck$ok) &&
      identical(ivis$schema, "round_core_p2_evaluation_visible_v1") && file.exists(file.path(IR, "results", "evaluation_full.json")) &&
      grepl("평가 상태 not_measured", ivis$cells[["P2R99_E2_H1"]]$why %||% ""), iv$error %||% iv$verdict_label)
chk("I2 driver 요약 — 짝 판정 템플릿 라벨 = 라운드 판정 라벨", identical(rc_summary(ispec, iv)$label, iv$verdict_label))

cat("J P2R05 범용분 = 원판 황금값(시드 띠 · 판정 여유 · Dimson β · 위기 유형 · 시작 시점 · 유동성 3분위 귀속)\n")
gd <- gdiff(globalenv())
chk(sprintf("J1 코어 이관분 %d 사례 = P2R05 원판 출력(원판 md5 %s · 시드 띠 note 문구만 뺌 · JSON 유효 숫자 15)", length(GC), substr(GJ$source_md5, 1, 8)),
    length(GC) == as.integer(GJ$n_cases) && identical(as.integer(GJ$n_error_cases), 0L) && !length(gd), paste(gd, collapse = ","))

cat("H 결과 동일 요약(무거운 재판정 기록)\n")
RS <- file.path(ROOT, "04_Research/programs/_lib/round_core/rejudge/RESULTS.json")
if (!file.exists(RS)) chk("H 재판정 기록 있음", FALSE, RS) else {
  J <- jsonlite::fromJSON(RS, simplifyVector = FALSE)
  for (r in c("P2R04", "P2R03", "P3R03")) {
    x <- J$rounds[[r]]
    chk(sprintf("H %s 판정 · 칸 판정 · 핵심 수치 동일(저장본 대 코어 · 차이 분류 %s)", r, x$classification %||% "-"),
        isTRUE(x$verdict_same) && isTRUE(x$cell_verdicts_same) && isTRUE(x$key_numbers_same), paste(x$verdict_stored, "/", x$verdict_core))
  }
}
unlink(TMP, recursive = TRUE)
cat(sprintf("\n== round_core_v1_p2: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_core_v1_p2","pass":%d,"fail":%d,"total":%d,"mutants_killed":%d,"mutants_total":%d}\n', PASS, FAIL, PASS + FAIL, nk, length(MU)))
if (FAIL > 0L) quit(status = 1L)
