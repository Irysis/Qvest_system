#==============================================================================
# forge_diag_pit.R — WT-R20260829_004 forge 층 PIT 진단
#   ① assert_overlay_pit HARD  ② lag1 스트레스  ③ strict-PIT A/B 인플레
#   ④ 컷오프 = first-day-of-holding-month (anchor_date/realized_ym 금지) 재도출
#   ⑤ detect_lookahead 양방향 대조(선언 idiom 주입 + 비선언 idiom 주입)
#   ⑥ 벤치 basis 귀속 (상류 weighted_screen PORT_t vs forge 권위 PORT_t)
#
# ②③ 의 대체 비중 패널은 optimizer 가 o3_objects.rds 에 발행한 build_scores()/make_W()
#   를 **그대로 호출**해 만든다(내가 새 비중 규칙을 쓰지 않는다). 전부 진단 전용이며
#   authoritative = W2_IV 단 하나다.
#==============================================================================
source("run_all.R")   # 캐시 경유

source(file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"))
source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R"))

PIT <- list()

#---------------------------------------------------------------- ① HARD gate
# 결정경로가 실제로 소비한 컷오프 = as_of_date(신호월말).
# 홀딩월 시작 = holding_ym 의 1일(캘린더). 집행은 그 이후 첫 거래일(get_execution_date).
WR <- fread(file.path(STAGE_DIR, "weights.csv"))
CUT <- unique(WR[, .(used_cutoff = as.Date(as_of_date),
                     holding_start = as.Date(paste0(holding_ym, "-01")))])
setorder(CUT, used_cutoff)
assert_overlay_pit(CUT$used_cutoff, CUT$holding_start, label = "forge/JT1993_crash_overlay")
# 집행일도 홀딩월 시작 이후인지 재도출(신호가 아니라 체결 시점의 정합)
CUT[, exec_date := as.Date(vapply(used_cutoff, function(d) as.character(get_execution_date(d, all_dates)), ""))]
PIT$item1_assert_overlay_pit <- list(
  status = "PASS", n_rows = nrow(CUT),
  rule = "used_cutoff(as_of_date) <= holding_month_start (first-day-of-holding-month)",
  max_used_cutoff = as.character(max(CUT$used_cutoff)),
  max_gap_days = as.integer(max(as.numeric(CUT$holding_start - CUT$used_cutoff))),
  min_gap_days = as.integer(min(as.numeric(CUT$holding_start - CUT$used_cutoff))),
  exec_after_holding_start_all = all(CUT$exec_date >= CUT$holding_start, na.rm = TRUE),
  n_exec_na = sum(is.na(CUT$exec_date)),
  note = "forge 는 오버레이를 새로 적용하지 않는다 — 상류가 확정한 패널의 소비 시점 정합만 검사."
)
cat("[PIT-1] assert_overlay_pit PASS | gap ", PIT$item1_assert_overlay_pit$min_gap_days, "~",
    PIT$item1_assert_overlay_pit$max_gap_days, "d | exec>=holding_start:",
    PIT$item1_assert_overlay_pit$exec_after_holding_start_all, "\n")

#-------------------------------------------- ②③ 패널 구성 (optimizer 함수 verbatim)
o3 <- readRDS(file.path(STAGE_DIR, "o3_objects.rds"))
E0 <- as.data.table(o3$E_now)
## build_scores(panic_map) 계약: panic_map = (signal_ym, panic_use)
## o3_overlay_pit.R:37~39 의 panic_now / panic_lag1 / panic_viol 구성과 동일 (NA 행 탈락 포함)
PM      <- unique(E0[, .(signal_ym, panic_use = panic)])[order(signal_ym)][is.finite(panic_use)]
PM_lag1 <- unique(E0[, .(signal_ym, panic)])[order(signal_ym)][, panic_use := shift(panic, 1L)][is.finite(panic_use), .(signal_ym, panic_use)]
PM_viol <- unique(E0[, .(signal_ym, panic)])[order(signal_ym)][, panic_use := shift(panic, -1L)][is.finite(panic_use), .(signal_ym, panic_use)]

# optimizer 클로저가 참조하는 상류 객체(AS2 = alpha score 패널)를 그 클로저 환경에 주입.
#   rds 직렬화로 enclosing env 가 끊긴 것을 복원하는 것이며, 함수 본문은 손대지 않는다.
.o2x <- readRDS(file.path(STAGE_DIR, "o2_objects.rds"))
.e <- environment(o3$build_scores)
if (!exists("AS2", envir = .e, inherits = FALSE)) assign("AS2", .o2x$AS2, envir = .e)
# o3_overlay_pit.R:11/27/50/53 리터럴 그대로 (재정의 아님 — 직렬화로 끊긴 참조 복원)
if (!exists("TOPN",        envir = .e, inherits = FALSE)) assign("TOPN", 25L, envir = .e)
if (!exists("POOL_OFFSET", envir = .e, inherits = FALSE)) assign("POOL_OFFSET", 100, envir = .e)
if (!exists("zsc", envir = .e, inherits = FALSE))
  assign("zsc", function(x) { m <- mean(x, na.rm = TRUE); s <- stats::sd(x, na.rm = TRUE)
                              if (!is.finite(s) || s == 0) rep(0, length(x)) else (x - m) / s }, envir = .e)
if (!exists("w_iv", envir = .e, inherits = FALSE)) assign("w_iv", o3$w_iv, envir = .e)
if (!exists(".norm", envir = .e, inherits = FALSE))
  assign(".norm", function(w) { w[!is.finite(w) | w < 0] <- 0
                                if (sum(w) <= 0) return(rep(1 / length(w), length(w))); w / sum(w) }, envir = .e)
environment(o3$make_W) <- .e
environment(o3$w_iv)   <- .e
.panel <- function(pm) {
  E <- o3$build_scores(pm)
  as.data.table(o3$make_W(E))[, .(Date, Ticker, w)]
}
W_now  <- .panel(PM)
W_lag1 <- .panel(PM_lag1)
W_viol <- .panel(PM_viol)
cat(sprintf("[PIT-2] panels rebuilt via optimizer make_W(): now/lag1/viol rows %d/%d/%d\n",
            nrow(W_now), nrow(W_lag1), nrow(W_viol)))
# 재구성판이 채택 패널과 동일한지(구성 함수 verbatim 확인)
.chk <- merge(W, W_now[, .(Date, Ticker, w_r = w)], by = c("Date", "Ticker"), all = TRUE)
PIT$panel_rebuild_identity <- list(
  unmatched = .chk[is.na(w) | is.na(w_r), .N],
  max_abs_diff = .chk[!is.na(w) & !is.na(w_r), max(abs(w - w_r))])
cat(sprintf("        rebuild identity vs weights.csv: unmatched=%d max|dw|=%.2e\n",
            PIT$panel_rebuild_identity$unmatched, PIT$panel_rebuild_identity$max_abs_diff))

#-------------------------------------- forge basis(share-based NAV, net) 측정기
.metrics_net <- function(WP) {
  NET <- .replay(WP, COMMISSION)
  dn <- NET$nav; setorder(dn, Date)
  dn[, r := NAV / shift(NAV) - 1]; dn <- dn[!is.na(r)]
  yrs <- as.numeric(max(dn$Date) - min(dn$Date)) / 365.25
  cagr <- (last(dn$NAV) / first(dn$NAV))^(1 / yrs) - 1
  sr   <- mean(dn$r) / sd(dn$r) * sqrt(252)
  peak <- cummax(dn$NAV); mdd <- min(dn$NAV / peak - 1)
  bm <- BM_DT[Date %in% dn$Date][order(Date)]
  ar <- dn$r - bm$BM_Ret
  list(cagr = cagr, sr = sr, mdd = mdd, calmar = cagr / abs(mdd),
       net_ir = mean(ar) / sd(ar) * sqrt(252), n_days = nrow(dn))
}
PROBE_PATH <- file.path(STAGE_DIR, "forge_pit_probes.rds")
if (file.exists(PROBE_PATH) && !identical(Sys.getenv("FORGE_FORCE_PROBE"), "1")) {
  PR <- readRDS(PROBE_PATH)
} else {
  PR <- list(base = .metrics_net(W_now), lag1 = .metrics_net(W_lag1), viol = .metrics_net(W_viol))
  saveRDS(PR, PROBE_PATH)
}

PIT$item2_lag1_stress <- list(
  calmar_base = PR$base$calmar, calmar_lag1 = PR$lag1$calmar,
  rel_change_calmar = PR$lag1$calmar / PR$base$calmar - 1,
  sr_base = PR$base$sr, sr_lag1 = PR$lag1$sr,
  rel_change_sr = PR$lag1$sr / PR$base$sr - 1,
  rule = "lag1 판이 base 대비 -25% 초과 붕괴하면 동월 누출 의심",
  status = if (PR$lag1$calmar / PR$base$calmar - 1 < -0.25) "COLLAPSE_LEAK_SUSPECT" else "NO_COLLAPSE",
  basis = "forge share-based daily NAV, 15bps delta")
cat(sprintf("[PIT-2] lag1: Calmar %.4f -> %.4f (%+.2f%%) | SR %.4f -> %.4f (%+.2f%%) => %s\n",
            PR$base$calmar, PR$lag1$calmar, 100 * PIT$item2_lag1_stress$rel_change_calmar,
            PR$base$sr, PR$lag1$sr, 100 * PIT$item2_lag1_stress$rel_change_sr,
            PIT$item2_lag1_stress$status))

ab_c <- overlay_lookahead_ab(PR$base$calmar, PR$base$calmar, "Calmar(current vs strict)")
ab_v <- overlay_lookahead_ab(PR$viol$calmar, PR$base$calmar, "Calmar(violation vs strict)")
ab_vs <- overlay_lookahead_ab(PR$viol$sr, PR$base$sr, "SR(violation vs strict)")
PIT$item3_strict_ab <- list(
  current_equals_strict = TRUE,
  strict_definition = paste("현행 컷오프 = as_of_date(신호월말) = holding_month_start - 1d.",
                            "strict 정의(홀딩월 시작 전 데이터만)와 동일 집합이므로 두 판이 같다."),
  inflation_calmar = ab_c$inflation, lookahead_suspected = ab_c$lookahead_suspected,
  message = ab_c$message,
  positive_control_violation_probe = list(
    description = "국면 신호를 1개월 앞당김(shift -1) = 홀딩월 자신의 국면으로 구성 교체 (BearProb 실사고 동형)",
    calmar = PR$viol$calmar, sr = PR$viol$sr, cagr = PR$viol$cagr, mdd = PR$viol$mdd,
    inflation_calmar = ab_v$inflation, lookahead_flag_calmar = ab_v$lookahead_suspected,
    inflation_sr = ab_vs$inflation, lookahead_flag_sr = ab_vs$lookahead_suspected,
    interpretation = paste("계기가 살아있다는 양성 대조 — 위반을 주입하면 성과가 뛴다.",
                           "현행 판이 그 값을 내지 않는다는 것이 clean 의 내용이다.")))
cat(sprintf("[PIT-3] strict A/B 인플레 = %.4f (clean) | 위반주입 Calmar %.4f (인플레 %+.2f%%, flag=%s) SR %.4f (인플레 %+.2f%%)\n",
            ab_c$inflation, PR$viol$calmar, 100 * ab_v$inflation, ab_v$lookahead_suspected,
            PR$viol$sr, 100 * ab_vs$inflation))

#---------------------------------------------------------------- ④ 컷오프 규약
src <- readLines(file.path(STAGE_DIR, "run_all.R"), warn = FALSE)
## ★자기참조 오탐 회피: 파일 전문을 grep 하면 spec$lookahead_prevention 안의
##   "anchor_date/realized_ym 결정경로 미참조" 라는 **선언 문장 자체**가 히트한다.
##   (초판이 정확히 그렇게 TRUE 를 냈다 — optimizer 층이 남긴 self_reference_note 와 동형.)
##   결정경로 = ①.replay() 함수 본문 ②weights.csv 소비 블록 [2] 로 한정해 재도출한다.
code_replay <- deparse(.replay)
i2 <- grep("^W <- fread", src); i3 <- grep("^n_by_date", src)
code_consume <- src[i2[1]:(i3[1] - 1)]
code_consume <- code_consume[!grepl("^\\s*#", code_consume)]
code <- c(code_replay, code_consume)
src_all_nc <- src[!grepl("^\\s*#", src)]
PIT$item4_cutoff_rule <- list(
  rule = "first-day-of-holding-month",
  used = "as_of_date(신호월말) 비중 -> get_execution_date() = 홀딩월 첫 거래일 종가 집행",
  consumed_columns = names(WR),
  consumed_columns_have_anchor_date = "anchor_date" %in% names(WR),
  consumed_columns_have_realized_ym = "realized_ym" %in% names(WR),
  anchor_date_in_decision_path = any(grepl("anchor_date", code)),
  realized_ym_in_decision_path = any(grepl("realized_ym", code)),
  holding_ym_in_decision_path  = any(grepl("holding_ym", code)),
  join_key = "as_of_date (신호월말) — holding_ym 으로 조인하지 않는다",
  decision_path_code_lines = length(code),
  decision_path_definition = ".replay() 함수 본문(deparse) + weights.csv 소비 블록 [2]",
  whole_file_scan_anchor_date = any(grepl("anchor_date", src_all_nc)),
  whole_file_scan_realized_ym = any(grepl("realized_ym", src_all_nc)),
  self_reference_note = paste("파일 전문 grep 은 TRUE 를 낸다 — 그 히트는 spec$lookahead_prevention 의",
                              "선언 문장('anchor_date/realized_ym 결정경로 미참조') 자기 자신이다.",
                              "초판 검사기가 그 오탐에 걸렸고, 결정경로를 함수 본문으로 한정해 재도출했다.",
                              "소비 컬럼 존재검사(weights.csv 헤더 = FALSE/FALSE)를 독립 증거로 병기한다."),
  note = "holding_ym 은 결정경로에서 쓰이지 않고 본 진단(사후)에서만 컷오프 검증에 쓰인다.")
cat(sprintf("[PIT-4] cutoff=first-day-of-holding-month | anchor_date in decision path=%s | realized_ym=%s | 소비컬럼 anchor/realized=%s/%s\n",
            PIT$item4_cutoff_rule$anchor_date_in_decision_path,
            PIT$item4_cutoff_rule$realized_ym_in_decision_path,
            PIT$item4_cutoff_rule$consumed_columns_have_anchor_date,
            PIT$item4_cutoff_rule$consumed_columns_have_realized_ym))

#---------------------------------------- ⑤ detect_lookahead 양방향 대조
tmpd <- file.path(STAGE_DIR, "pit_probe"); dir.create(tmpd, showWarnings = FALSE)
base_clean <- detect_lookahead(file.path(STAGE_DIR, "run_all.R"), verbose = FALSE)

# (a) 선언 idiom 주입 — 검출기가 명시적으로 찾는 패턴
inj_a <- c(src, "", "## PROBE-A declared idioms (DO NOT RUN)",
           "PROBE <- RAWDATA[, .(mu = mean(Close)), by = Ticker]  # full-sample mean",
           "PROBE2 <- W[, fwd := shift(w, -1)]",
           "NEGATE_FACTORS <- c('mom')")
writeLines(inj_a, file.path(tmpd, "probe_declared.R"))

# (b) 비선언 idiom 주입 — 상류 3층에서 0/3 미발화했던 계통
inj_b <- c(src, "", "## PROBE-B non-declared idioms (DO NOT RUN)",
           "SIG <- cov(matrix(rnorm(100), 10))",
           "MU  <- mean(DAILY_NAV_DT$Strategy_Ret)",
           "W[, w := w / sum(w)]",
           "LEAD <- shift(DAILY_NAV_DT$Strategy_Ret, -1)")
writeLines(inj_b, file.path(tmpd, "probe_nondeclared.R"))

# (c) 음성 대조 — 무해한 주석만 추가
writeLines(c(src, "## PROBE-C harmless comment"), file.path(tmpd, "probe_null.R"))

r_a <- detect_lookahead(file.path(tmpd, "probe_declared.R"),    verbose = FALSE)
r_b <- detect_lookahead(file.path(tmpd, "probe_nondeclared.R"), verbose = FALSE)
r_c <- detect_lookahead(file.path(tmpd, "probe_null.R"),        verbose = FALSE)
.nv <- function(r) if (is.null(r$violations)) NA_integer_ else
  (if (is.data.frame(r$violations)) nrow(r$violations) else length(r$violations))
PIT$item5_detect_lookahead_two_way <- list(
  base_run_all = list(clean = base_clean$clean, scanned = base_clean$scanned %||% NA, n_violations = .nv(base_clean)),
  probe_declared_idioms    = list(clean = r_a$clean, n_violations = .nv(r_a),
                                  fired = isTRUE(!isTRUE(r_a$clean))),
  probe_nondeclared_idioms = list(clean = r_b$clean, n_violations = .nv(r_b),
                                  fired = isTRUE(!isTRUE(r_b$clean))),
  negative_control_comment_only = list(clean = r_c$clean, n_violations = .nv(r_c)),
  interpretation = paste("양성 대조(선언 idiom)가 발화하고 음성 대조가 조용해야 계기가 살아있다.",
                         "비선언 idiom 이 미발화하면 그 계통은 **미측정**이며 CLEAN 은",
                         "선언 idiom 부재의 증거일 뿐 PIT 증명이 아니다."))
cat(sprintf("[PIT-5] detect_lookahead: base clean=%s | declared-inj fired=%s (%s) | nondeclared-inj fired=%s (%s) | null-ctrl clean=%s\n",
            base_clean$clean, PIT$item5_detect_lookahead_two_way$probe_declared_idioms$fired, .nv(r_a),
            PIT$item5_detect_lookahead_two_way$probe_nondeclared_idioms$fired, .nv(r_b), r_c$clean))

#---------------------------------------------- ⑥ 벤치 basis 귀속
o2 <- readRDS(file.path(STAGE_DIR, "o2_objects.rds"))
prm <- as.data.table(o2$RES$W2_IV$M$m$period_returns)   # 상류 weighted_screen 월별
dn  <- copy(DAILY_NAV_DT)[order(Date)]
bmf <- BM_DT[Date %in% dn$Date][order(Date)]
cum <- function(x) prod(1 + x)
ann <- function(x, per) cum(x)^(1 / (length(x) / per)) - 1
PIT$item6_benchmark_basis <- list(
  upstream_basis  = "weighted_screen_bt — 월별 가중수익 집계(259 months), benchmark_ret 월별",
  forge_basis     = "share-based daily NAV(정수주 + 잔여현금) + BM_DT 일별 BM_Ret",
  upstream = list(n_months = nrow(prm),
                  strat_cum = cum(prm$ret_net), bench_cum = cum(prm$benchmark_ret),
                  strat_cagr = ann(prm$ret_net, 12), bench_cagr = ann(prm$benchmark_ret, 12),
                  port_t = as.numeric(o2$RES$W2_IV$M$m$portfolio_alpha_t_nw_lag3),
                  net_ir = as.numeric(o2$RES$W2_IV$M$m$information_ratio)),
  forge = list(n_days = nrow(dn),
               strat_cum = cum(dn$Strategy_Ret), bench_cum = cum(bmf$BM_Ret),
               strat_cagr = ann(dn$Strategy_Ret, 252), bench_cagr = ann(bmf$BM_Ret, 252),
               port_t = as.numeric(as.data.table(bt$benchmark_compare)[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value][1]),
               net_ir = as.numeric(as.data.table(bt$benchmark_compare)[metric_name == "Information_Ratio", active_value][1]))
)
PIT$item6_benchmark_basis$attribution <- list(
  d_port_t_total = PIT$item6_benchmark_basis$forge$port_t - PIT$item6_benchmark_basis$upstream$port_t,
  bench_cum_ratio_forge_over_upstream = PIT$item6_benchmark_basis$forge$bench_cum / PIT$item6_benchmark_basis$upstream$bench_cum,
  strat_cum_ratio_forge_over_upstream = PIT$item6_benchmark_basis$forge$strat_cum / PIT$item6_benchmark_basis$upstream$strat_cum,
  note = paste("상류 PORT_t 와 forge 권위 PORT_t 는 **다른 양**이다(월별 weighted_screen vs 일별",
               "share-based + 다른 BM 계열). 어느 쪽이 높다고 상대를 반증하지 않으며,",
               "판정에 쓰는 값은 forge 권위값 하나다."))
cat(sprintf("[PIT-6] PORT_t 상류 %.4f -> forge %.4f (Δ %+.4f) | BM 누적 forge/상류 = %.4f | 전략 누적 forge/상류 = %.4f\n",
            PIT$item6_benchmark_basis$upstream$port_t, PIT$item6_benchmark_basis$forge$port_t,
            PIT$item6_benchmark_basis$attribution$d_port_t_total,
            PIT$item6_benchmark_basis$attribution$bench_cum_ratio_forge_over_upstream,
            PIT$item6_benchmark_basis$attribution$strat_cum_ratio_forge_over_upstream))
cat(sprintf("        BM CAGR: 상류(월) %.4f vs forge(일) %.4f | 전략 CAGR: 상류 %.4f vs forge %.4f\n",
            PIT$item6_benchmark_basis$upstream$bench_cagr, PIT$item6_benchmark_basis$forge$bench_cagr,
            PIT$item6_benchmark_basis$upstream$strat_cagr, PIT$item6_benchmark_basis$forge$strat_cagr))

PIT$verdict <- if (isTRUE(base_clean$clean) && identical(PIT$item2_lag1_stress$status, "NO_COLLAPSE") &&
                   !isTRUE(PIT$item3_strict_ab$lookahead_suspected)) "PASS" else "REVIEW"
write_json(PIT, file.path(STAGE_DIR, "forge_overlay_pit.json"), auto_unbox = TRUE,
           pretty = TRUE, digits = 8, null = "null")
saveRDS(PIT, file.path(STAGE_DIR, "forge_pit.rds"))
cat(sprintf("=== forge_diag_pit.R done | verdict=%s ===\n", PIT$verdict))
