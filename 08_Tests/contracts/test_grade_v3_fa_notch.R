## test_grade_v3_fa_notch.R — 등급 v3.3 팩터 조정 알파 노치 검사기(양성 대조 + 위반 주입)
## 대상: 02_Infrastructure/contracts/grade_v3.R(gv3_decide ④ · gv3_fa_stats · .gv3_fa_monthly · gv3_fa_ctx · .gv3_fa_eval)
## 결정: decision_register GRADE-V33-FACTOR-ALPHA-NOTCH-20261109(도훈 11-09 '1안으로 가자')
##   A 결정 함수 경우표 · B 합성 요인 통계(정답을 아는 자료) · C 요인 묶음 fail-closed · D 자격 판정 · M 위반 주입 5종
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a)) b else a
ROOT <- gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "")))
if (!nzchar(ROOT)) stop("QM_ROOT 미설정")
setwd(ROOT)
GV3 <- file.path(ROOT, "02_Infrastructure/contracts/grade_v3.R")
load_gv3 <- function(text = NULL) {
  e <- new.env(parent = globalenv()); f <- GV3
  if (!is.null(text)) { f <- tempfile(fileext = ".R"); writeLines(text, f, useBytes = TRUE) }
  sys.source(f, envir = e, keep.source = FALSE)
  e
}
mutant <- function(from, to) {
  txt <- paste(readLines(GV3, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  n <- lengths(regmatches(txt, gregexpr(from, txt, fixed = TRUE)))
  if (n != 1L) stop("돌연변이 치환 대상이 정확히 1곳이 아니다(", n, "): ", from)
  load_gv3(sub(from, to, txt, fixed = TRUE))
}
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}

G <- load_gv3()
cfg <- G$gv3_cfg(ROOT)
FL <- c(port_t = TRUE, calmar = TRUE, cagr = TRUE, sharpe = TRUE); OO <- c(test_window_cr_not_weak = TRUE, rolling36_pass_oos = TRUE)
SB <- 0.40
fa <- function(t, el = TRUE) list(eligible = el, t_min = t, th_b = 2.0, th_a = 2.95)
dec <- function(env, S, cr = "normal", t = NULL, fl = FL, oo = OO, el = TRUE)
  env$gv3_decide(S, SB, fl, oo, cr, cfg, fa = if (is.null(t)) NULL else fa(t, el))

cat("=== A. 결정 함수(gv3_decide ④) ===\n")
d <- dec(G, 0.30, t = 2.1); chk("A1 C 띠 · CR 보통 · t_min 2.1 ≥ B 문턱 → B(fa_notch 1)", identical(d$grade, "B") && identical(d$fa_notch, 1L))
d <- dec(G, 0.30, t = 1.9); chk("A2 C 띠 · t_min 1.9 < B 문턱 → C", identical(d$grade, "C") && identical(d$fa_notch, 0L))
d <- dec(G, 0.60, t = 3.0); chk("A3 B 띠 · t_min 3.0 ≥ A 문턱 · 하한 · OOS 충족 → A(notch_a)", identical(d$grade, "A") && isTRUE(d$notch_a) && identical(d$fa_notch, 1L))
d <- dec(G, 0.60, t = 3.0, fl = replace(FL, "cagr", FALSE))
chk("A4 B 띠 · t_min 3.0 이나 CAGR 하한 미달 → B(하한은 그대로)", identical(d$grade, "B") && identical(d$fa_notch, 0L))
d <- dec(G, 0.60, t = 2.5); chk("A5 B 띠 · t_min 2.5 < A 문턱 → B", identical(d$grade, "B"))
d <- dec(G, 0, t = 5); chk("A6 F(S = 0) · t_min 5 → F(노치 없음)", identical(d$grade, "F") && identical(d$fa_notch, 0L))
d <- dec(G, 0.60, cr = "weak", t = 3.0)
chk("A7 B 띠 · CR 약함(→ C) · t_min 3.0 → C 그대로(약함 감점을 상쇄하지 않는다)", identical(d$grade, "C") && identical(d$fa_notch, 0L) && identical(d$notch, -1L))
d <- dec(G, 0.30, t = 5, el = FALSE); chk("A8 자격 없음(eligible = FALSE) · t_min 5 → C", identical(d$grade, "C") && identical(d$fa_notch, 0L))
same <- all(vapply(list(list(0.3, "normal"), list(0.6, "weak"), list(1.2, "normal"), list(0, "normal"), list(0.6, "strong")), function(a)
  identical(G$gv3_decide(a[[1]], SB, FL, OO, a[[2]], cfg)$grade, G$gv3_decide(a[[1]], SB, FL, OO, a[[2]], cfg, fa = NULL)$grade), logical(1)))
chk("A9 fa = NULL 이면 구 판과 같은 등급(뒤 호환)", same)
d <- dec(G, 0.30, cr = "strong", t = 3.0, fl = replace(FL, "port_t", FALSE))
chk("A10 C 띠 · CR 강함(→ B) · t_min 3.0 · 하한 미달 → B(겹쳐 A 로 가지 않는다)", identical(d$grade, "B") && identical(d$notch, 1L) && identical(d$fa_notch, 0L))
d <- dec(G, 1.20, t = 3.5, oo = replace(OO, "rolling36_pass_oos", FALSE))
chk("A11 A 띠가 OOS 로 막혀 B · t_min 3.5 → B(시험 창 관문은 그대로)", identical(d$grade, "B") && identical(d$fa_notch, 0L))

cat("=== B. 통계(합성 요인 · 정답을 아는 자료) ===\n")
set.seed(20261109)
cal <- seq(as.Date("2001-01-01"), as.Date("2026-09-30"), by = "day"); cal <- cal[as.integer(format(cal, "%u")) <= 5L]
CL <- data.table(date = cal)[, ym := as.integer(format(date, "%Y%m"))]
ME <- CL[, .(Date = max(date), n_td = .N), by = ym]
Fm <- ME[, .(ym, Date, RF = 0.002, MKT = rnorm(.N, 0.005, 0.06), SMB = rnorm(.N, 0, 0.04), HML = rnorm(.N, 0.005, 0.04),
             RMW = rnorm(.N, 0.002, 0.03), CMA = rnorm(.N, 0.002, 0.03), WML = rnorm(.N, 0.004, 0.05))]
Fm[, SMB5 := SMB + rnorm(.N, 0, 0.005)]
mk_pr <- function(alpha, b = c(MKT = 0.8, HML = 0.3), eps = 0.01, months = NULL, drop_first = 0L, drop_last = 0L) {
  R <- copy(Fm)
  if (!is.null(months)) R <- R[ym %in% months]
  a <- if (is.function(alpha)) alpha(R$Date) else rep(alpha, nrow(R))
  R[, Rm := RF + a + Reduce(`+`, lapply(names(b), function(k) b[[k]] * get(k))) + rnorm(.N, 0, eps)]
  D <- merge(CL, R[, .(ym, Rm)], by = "ym")
  D[, ret_net := (1 + Rm)^(1 / .N) - 1, by = ym]
  setorder(D, date)
  if (drop_first > 0L) D <- D[-seq_len(drop_first)]
  if (drop_last > 0L) D <- D[seq_len(nrow(D) - drop_last)]
  D[, .(date, ret_net, frequency = "daily")]
}
E <- G$.gv3_deps(ROOT)
st <- function(pr, env = G) env$gv3_fa_stats(env$.gv3_fa_monthly(pr, cal), Fm, cfg$fa_notch$models, 3L, 36L, 12L, as.Date("2022-12-31"), E$.nw_fit)
s1 <- st(mk_pr(0.01))
chk("B1 알파 1%/월 · 4개 모형 t 모두 계산 · 최소 t ≥ A 문턱", all(is.finite(s1$models$t)) && s1$t_min >= 2.95 && isTRUE(s1$test_all_pos),
    sprintf("(t_min %.2f · %s)", s1$t_min, s1$t_min_model))
s0 <- st(mk_pr(0)); chk("B2 알파 0 → 최소 t < B 문턱", is.finite(s0$t_min) && s0$t_min < 2.0, sprintf("(t_min %.2f)", s0$t_min))
nfull <- nrow(Fm)
s3 <- st(mk_pr(0.01, drop_first = 3L, drop_last = 3L))
chk("B3 첫 달 · 마지막 달이 부분 월이면 뺀다(요인 월간과 맞지 않는다)", identical(s3$n_months, nfull - 2L), sprintf("(%d vs 전체 %d)", s3$n_months, nfull))
s4 <- st(mk_pr(function(d) ifelse(d > as.Date("2022-12-31"), -0.01, 0.01)))
chk("B4 시험 창(τ_D 뒤) 알파가 음수면 test_all_pos = FALSE(전기간 t 는 양수여도)", s4$t_min > 2.0 && !isTRUE(s4$test_all_pos))
s5 <- st(mk_pr(0.01, months = head(Fm$ym, 24)))
chk("B5 관측 24개월 < 36 → t_min = NA(판정 불가 · 지어내지 않는다)", is.na(s5$t_min))
s6 <- st(mk_pr(0.004, b = c(MKT = 0.8, WML = 0.6)))
chk("B6 최소 t = 네 모형 t 의 최솟값(모형 고르기 차단 · 모형마다 t 가 다르다)",
    isTRUE(all.equal(s6$t_min, min(s6$models$t))) && length(unique(round(s6$models$t, 6))) == 4L,
    sprintf("(%s)", paste(sprintf("%s %.2f", s6$models$model, s6$models$t), collapse = " · ")))
pm <- data.table(date = Fm$Date, ret_net = Fm$RF + 0.01 + 0.8 * Fm$MKT + rnorm(nrow(Fm), 0, 0.01), frequency = "monthly")
chk("B7 월간 수익 입력도 같은 경로(행 = 달)", identical(nrow(G$.gv3_fa_monthly(pm, cal)), nrow(Fm)))

cat("=== C. 요인 묶음 fail-closed(gv3_fa_ctx) ===\n")
TR <- file.path(tempdir(), sprintf("gv3fa_%d", Sys.getpid()))
dir.create(file.path(TR, "02_Infrastructure/data"), recursive = TRUE, showWarnings = FALSE); dir.create(file.path(TR, ".cache"), showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/data/build_kr_factor_returns.R"), file.path(TR, "02_Infrastructure/data/build_kr_factor_returns.R"), overwrite = TRUE))
c1 <- G$gv3_fa_ctx(TR, cfg)
chk("C1 요인 파일 없음 → factor_unavailable", identical(c1$status, "factor_unavailable") && grepl("없음", c1$reason))
B <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/data/build_kr_factor_returns.R"), envir = B, keep.source = FALSE)
cols <- c("Date", "MKT", "SMB", "HML", "WML", "RMW", "CMA", "RF", "SMB5")
write_parquet(Fm, file.path(TR, ".cache/kr_factor_returns_v2.parquet"))
write_parquet(data.table(Date = cal), file.path(TR, ".cache/kr_factor_returns_daily.parquet"))
wmeta <- function(md5) writeLines(toJSON(list(schema = "kr_factor_returns_meta_v1", epoch = "EP_TEST", universe = "ALL_HYG",
                                               monthly = list(content_md5 = md5, content_cols = cols)), auto_unbox = TRUE),
                                  file.path(TR, ".cache/kr_factor_returns_meta.json"))
wmeta("0123456789abcdef0123456789abcdef")
c2 <- G$gv3_fa_ctx(TR, cfg)
chk("C2 [위반 주입] meta 내용 해시 불일치 → factor_unavailable", identical(c2$status, "factor_unavailable") && grepl("해시", c2$reason))
wmeta(B$.krf_content_md5(Fm, cols))
c3 <- G$gv3_fa_ctx(TR, cfg)
chk("C3 해시 일치 → ok · epoch · 달력 · 해시 기록", identical(c3$status, "ok") && identical(c3$epoch, "EP_TEST") && length(c3$cal) == length(cal))

cat("=== D. 자격 판정(.gv3_fa_eval) ===\n")
fx <- c3; fx$enabled <- TRUE
ctx <- list(fa = fx, rg = list(window_months = 36L), bc_cfg = list(tau_d = "2022-12-31"), th = list(port_t_b = 2.0, port_t_a = 2.95))
X <- list(pr = mk_pr(0.01), ar = list(measurement_axis = list(epoch = "EP_TEST")), spec = list())
ev <- function(env = G, x = X, cx = ctx, gates = NULL, cr = "normal") env$.gv3_fa_eval(x, cx, cfg, ROOT, gates, cr, E)
r <- ev(); chk("D1 조건 모두 충족 → eligible · decide 입력(t_min · 문턱)", isTRUE(r$decide$eligible) && !length(r$record$why_not) &&
                identical(r$decide$th_b, 2.0) && identical(r$decide$th_a, 2.95))
r <- ev(x = modifyList(X, list(ar = list(measurement_axis = list(epoch = "OTHER")))))
chk("D2 기록 epoch ≠ 요인 epoch → epoch_mismatch", !isTRUE(r$decide$eligible) && "epoch_mismatch" %in% r$record$why_not)
r <- ev(gates = c(dsr_sweep = FALSE)); chk("D3 스윕 DSR 관문 미달 → gate:dsr_sweep", !isTRUE(r$decide$eligible) && "gate:dsr_sweep" %in% r$record$why_not)
r <- ev(cr = "weak"); chk("D4 CR 약함 → cr_weak(기록)", !isTRUE(r$decide$eligible) && "cr_weak" %in% r$record$why_not)
XT <- modifyList(X, list(pr = mk_pr(function(d) ifelse(d > as.Date("2022-12-31"), -0.01, 0.01))))
r <- ev(x = XT); chk("D5 시험 창 알파 음수 → test_window_alpha_not_all_positive", !isTRUE(r$decide$eligible) && "test_window_alpha_not_all_positive" %in% r$record$why_not)
cx0 <- ctx; cx0$fa$enabled <- FALSE
r <- ev(cx = cx0); chk("D6 enabled = FALSE → 통계는 기록 · 자격 없음(disabled)", !isTRUE(r$decide$eligible) && "disabled" %in% r$record$why_not && is.finite(r$record$t_min))
Xb <- list(pr = mk_pr(0.01), ar = list(), spec = list(universe = "K200_KQ150"))
r <- ev(x = Xb); chk("D7 메모리판 · 유니버스가 활성 epoch 와 다르면 epoch 미상 → 자격 없음", !isTRUE(r$decide$eligible) && "epoch_mismatch" %in% r$record$why_not)

cat("=== M. 위반 주입(검사가 살아 있나) ===\n")
M1 <- mutant('g %in% c("C", "B") && !identical(cr, "weak")', 'g %in% c("C", "B")')
chk("M1 CR 약함 제외를 지우면 A7 이 B 로 뒤집힌다(A7 이 잡는다)", identical(dec(M1, 0.60, cr = "weak", t = 3.0)$grade, "B"))
M2 <- mutant("t_min <- if (all_t) min(tab$t) else NA_real_", "t_min <- if (all_t) max(tab$t) else NA_real_")
s6m <- M2$gv3_fa_stats(M2$.gv3_fa_monthly(mk_pr(0.004, b = c(MKT = 0.8, WML = 0.6)), cal), Fm, cfg$fa_notch$models, 3L, 36L, 12L, as.Date("2022-12-31"), E$.nw_fit)
chk("M2 최솟값을 최댓값으로 바꾸면 B6 의 등식이 깨진다(B6 이 잡는다)", !isTRUE(all.equal(s6m$t_min, min(s6m$models$t))))
M3 <- mutant('  if (!isTRUE(st$test_all_pos)) why <- c(why, "test_window_alpha_not_all_positive")\n', "")
chk("M3 시험 창 조건을 지우면 D5 가 자격을 얻는다(D5 가 잡는다)", isTRUE(ev(env = M3, x = XT)$decide$eligible))
M4 <- mutant('  if (length(g) && !all(g)) why <- c(why, paste0("gate:", names(g)[!g]))\n', "")
chk("M4 관문 조건을 지우면 D3 이 자격을 얻는다(D3 이 잡는다)", isTRUE(ev(env = M4, gates = c(dsr_sweep = FALSE))$decide$eligible))
M5 <- mutant("isTRUE(fa$t_min >= fa$th_a) && a_ok", "isTRUE(fa$t_min >= fa$th_a)")
chk("M5 B→A 의 하한 조건을 지우면 A4 가 A 로 뒤집힌다(A4 가 잡는다)", identical(dec(M5, 0.60, t = 3.0, fl = replace(FL, "cagr", FALSE))$grade, "A"))

unlink(TR, recursive = TRUE)
cat(sprintf("\n== grade_v3_fa_notch: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(toJSON(list(test = "grade_v3_fa_notch", pass = PASS, fail = FAIL, total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0L) quit(save = "no", status = 1L)
