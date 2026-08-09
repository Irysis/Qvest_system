#==============================================================================
# test_liquidity_ruler.R — 유동성 자(ruler) 계약 검사기  [FQ-181, 2026-08-09]
#
# 계약: 헌법(CLAUDE.md Production Constraints · .claude/rules/pit.md C10)
#       유동성 = **20일 평균 거래대금 >= 2e8**, t-1 기준(당일 미포함).
#
# 배경 (확정 결함):
#   02_Infrastructure/ramp/factor_validation.R 의 build_monthly_forward_returns() 가
#   주석에 "20d ADV at t-1" 이라 써 놓고 `adv = Vol0 * Close0`(월말 당일 1일치)를 계산했다.
#   주석 자신이 "(사용은 단순 Vol0*Close0)" 라고 자백하고 있었다.
#   두 자 상관 0.929 · 판정 불일치 2.61% · 실선별 top-25 중 3.04%가 20일-자 미달.
#
# ★이 검사기는 정상경로만 재지 않는다. 축 B 가 **구판 1일치 산식을 실제로 주입**하고
#   교정 산식에 **돌연변이**(shift 제거 / 창폭 1)를 심어, 검사가 그때 정말 FAIL 하는지
#   본다. 오탐 제거와 검사 사망은 겉보기가 같으므로 이 축이 없으면 초록은 무의미하다.
#
# ★축 C2 가 이 파일의 존재 이유 절반이다: 호출부 149건 중 103건이 rawdata 를
#   월말 거래일만으로 slim 해 넘긴다. 그런 입력에 frollmean(.,20) 을 그냥 걸면
#   20 *개월* 평균이 나온다 — 오류가 아니라 **그럴듯한 쓰레기**. 함수가 입력 형태를
#   실측해 분기하고 라벨로 자백하는지가 계약이다.
#
# 실행: Rscript 08_Tests/ramp/test_liquidity_ruler.R
#       또는  Rscript -e 'source("08_Tests/ramp/test_liquidity_ruler.R")'
#       (★러너는 `--file=` 과 `source()` 양쪽에서 돌아야 한다 — 2026-08-08 수리 규약)
#==============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
data.table::setDTthreads(1)

## ── 자기 위치 해석 (r-portability 금칙④: CLAUDE_PROJECT_DIR 우선, 못 찾으면 크게 실패) ──
.resolve_proj <- function() {
  marker <- "02_Infrastructure/ramp/factor_validation.R"
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a) && nzchar(a[1])) {
    p <- normalizePath(file.path(dirname(sub("^--file=", "", a[1])), "..", ".."),
                       winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(p, marker))) return(p)
  }
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, marker))]
  if (!length(hit)) stop("test_liquidity_ruler: project root 미발견 — ",
                         "★러너 경로 실패이지 계약 실패가 아닙니다. ",
                         "CLAUDE_PROJECT_DIR/QM_ROOT 확인.")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
eqf <- function(a, b, tol = 1e-6) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = tol))

suppressMessages(source(file.path(PROJ, "02_Infrastructure/ramp/factor_validation.R")))

## ★본문 전체를 하나의 중괄호 블록으로 감싼다 — R 은 **최상위**에서 `if` 다음 줄의
##   `else` 를 새 표현식으로 읽어 구문오류를 낸다(블록 안에서는 정상). 이 파일은
##   if/else 판정이 축마다 반복되므로 블록으로 감싸는 편이 축마다 중괄호를 다는 것보다
##   안전하다. PASS/FAIL 은 `<<-` 로 전역에 누적된다.
{
#==============================================================================
# 합성 일간 패널 — 손계산 정답이 있는 입력
#==============================================================================
mk_daily <- function(n_days = 260L, tickers = c("A", "B", "C")) {
  d0 <- as.Date("2020-01-01")
  dates <- seq(d0, by = "day", length.out = n_days * 2L)
  dates <- dates[format(dates, "%u") %in% c("1", "2", "3", "4", "5")][seq_len(n_days)]
  dt <- CJ(Ticker = tickers, Date = dates)
  setorder(dt, Ticker, Date)
  # dval = Vol*Close 를 종목별로 결정적으로 만든다 (A: 1e6*i, B: 상수, C: 월말만 폭증)
  dt[, i := seq_len(.N), by = Ticker]
  dt[, Close := 1000]
  dt[Ticker == "A", Vol := i * 1e3]                 # dval = i*1e6
  dt[Ticker == "B", Vol := 5e5]                     # dval = 5e8 (문턱 상회)
  dt[, ym := format(Date, "%Y-%m")]
  dt[, is_me := Date == max(Date), by = .(Ticker, ym)]
  dt[Ticker == "C", Vol := fifelse(is_me, 1e6, 1e3)] # 월말만 1e9, 평소 1e6
  dt[, `:=`(K200 = 1, KQ150 = 0, Size = 1e12)]
  dt[, dval := Vol * Close]
  dt[]
}
DAILY <- mk_daily()
ME <- DAILY[is_me == TRUE & Ticker == "A", Date]

## 손계산 참조: 창 = [i-20, i-1] (당일 미포함)
ref_adv20 <- function(dvals, i) {
  if (i <= 1L) return(NA_real_)
  lo <- max(1L, i - 20L); hi <- i - 1L
  mean(dvals[lo:hi])
}

#==============================================================================
# 축 A — 교정판 자기일치 (양성 대조)
#==============================================================================
cat("=== A. 교정판 자기일치 ===\n")
ADV <- build_adv20_t1(DAILY)
setkey(ADV, Ticker, Date)
A <- DAILY[Ticker == "A"][order(Date)]
a_adv <- ADV[Ticker == "A"][order(Date)]$adv

# A1: 20일 평균(t-1) 손계산 일치 (워밍업 이후 전 구간)
chk <- vapply(30:nrow(A), function(i) eqf(a_adv[i], ref_adv20(A$dval, i)), logical(1))
if (all(chk)) ok("A1_20d_mean_t1_matches_hand_calc", sprintf("%d 지점 전건 일치", length(chk)))
else bad("A1_20d_mean_t1_matches_hand_calc",
         sprintf("%d/%d 불일치 (예: i=%d 실측 %.4g vs 참조 %.4g)",
                 sum(!chk), length(chk), (30:nrow(A))[which(!chk)[1]],
                 a_adv[(30:nrow(A))[which(!chk)[1]]],
                 ref_adv20(A$dval, (30:nrow(A))[which(!chk)[1]])))

# A2: 창이 **당일을 포함하지 않는다** — 당일 dv 를 극단값으로 바꿔도 adv 불변
D2 <- copy(DAILY); tgt <- ME[6]
D2[Ticker == "A" & Date == tgt, Vol := 1e12]        # dval 1e15
a2 <- build_adv20_t1(D2)[Ticker == "A" & Date == tgt, adv]
a1 <- ADV[Ticker == "A" & Date == tgt, adv]
if (eqf(a1, a2)) ok("A2_same_day_excluded", sprintf("당일 dv 1e15 주입에도 adv 불변 (%.4g)", a1))
else bad("A2_same_day_excluded", sprintf("당일 값이 창에 샜다: %.6g -> %.6g", a1, a2))

# A3: i>=21 구간에서 adaptive == 저장소 관용구 frollmean(.,20) + shift(1)
std <- shift(frollmean(A$dval, n = 20L, align = "right"), 1L)
idx <- 22:nrow(A)
if (all(eqf(a_adv[idx], std[idx]))) ok("A3_matches_repo_idiom", "frollmean(.,20)+shift(1) 과 동일")
else bad("A3_matches_repo_idiom", "adaptive 판본이 표준 관용구와 갈림")

# A4: 워밍업이 NA 가 아니다 (NA 는 하류에서 필터를 '통과'한다 = 완화 방향)
n_na <- sum(is.na(a_adv))
if (n_na == 1L && is.na(a_adv[1])) ok("A4_warmup_not_na", "NA 는 종목 첫 관측 1건뿐(확장평균 채움)")
else bad("A4_warmup_not_na", sprintf("NA %d 건 — NA 는 canonical_screen_bt 에서 통과한다", n_na))

#==============================================================================
# 축 B — 위반 주입 / 돌연변이 (검사가 정말 발화하는가)
#==============================================================================
cat("=== B. 위반 주입 · 돌연변이 ===\n")

# B1: 구판 1일치 산식을 주입 → 검사가 두 자를 **구별**해야 한다
legacy_adv <- function(daily) {           # ★구판 산식 그대로 (adv = Vol0*Close0)
  d <- as.data.table(daily)[, .(Date, Ticker, adv = Vol * Close)]
  d[]
}
LEG <- legacy_adv(DAILY[is_me == TRUE])
NEW <- ADV[Date %in% ME]
cmp <- merge(LEG[Date %in% ME], NEW, by = c("Date", "Ticker"), suffixes = c("_leg", "_new"))
n_diff <- cmp[!eqf(adv_leg, adv_new), .N]
if (n_diff > 0) ok("B1_injection_detected",
                   sprintf("구판 1일치 주입 시 %d/%d 지점에서 20일-자와 갈림 (검출력 있음)",
                           n_diff, nrow(cmp)))
else bad("B1_injection_detected",
         "구판 산식을 주입했는데 차이를 못 잡았다 — 검사가 두 자를 구별하지 못함(검사 사망)")

# B2: 돌연변이 — shift(1) 제거(당일 포함) 판본을 만들면 A2 가 FAIL 해야 한다
mut_noshift <- function(daily) {
  DV <- as.data.table(daily)[, .(Ticker, Date = as.Date(Date), dval = Vol * Close)]
  setorder(DV, Ticker, Date)
  DV[, adv := frollmean(dval, n = pmin(seq_len(.N), 20L), adaptive = TRUE, na.rm = TRUE), by = Ticker]
  DV[, .(Date, Ticker, adv)]
}
m1 <- mut_noshift(DAILY)[Ticker == "A" & Date == tgt, adv]
m2 <- mut_noshift(D2)[Ticker == "A" & Date == tgt, adv]
if (!eqf(m1, m2)) ok("B2_mutation_noshift_caught", "shift 제거판은 A2 축에서 잡힌다(당일 누출 검출)")
else bad("B2_mutation_noshift_caught",
         "★돌연변이(당일 포함)를 A2 축이 못 잡는다 — A2 는 무력한 검사")

# B3: 돌연변이 — 창폭 20 → 1 이면 A1 이 FAIL 해야 한다
mut_win1 <- function(daily) {
  DV <- as.data.table(daily)[, .(Ticker, Date = as.Date(Date), dval = Vol * Close)]
  setorder(DV, Ticker, Date)
  DV[, adv := shift(dval, 1L), by = Ticker]
  DV[, .(Date, Ticker, adv)]
}
w1 <- mut_win1(DAILY)[Ticker == "A"][order(Date)]$adv
chk1 <- vapply(30:nrow(A), function(i) eqf(w1[i], ref_adv20(A$dval, i)), logical(1))
if (!all(chk1)) ok("B3_mutation_window1_caught", sprintf("창폭1 판본은 A1 축에서 %d 지점 불일치", sum(!chk1)))
else bad("B3_mutation_window1_caught", "★창폭 1 돌연변이를 A1 축이 못 잡는다")

# B4: 돌연변이 — 월말-slim 입력에 20일 창을 그대로 걸면 20*개월* 평균이 된다.
#     이 '그럴듯한 쓰레기'를 함수가 만들어내지 않는지가 계약(축 C2 와 짝).
SLIM <- DAILY[is_me == TRUE]
slim_naive <- build_adv20_t1(SLIM)          # 헬퍼를 slim 에 직접 걸면(=금지된 사용법)
sn <- slim_naive[Ticker == "B"][order(Date)]$adv
# B 는 dval 상수 5e8 이라 값이 같아 구별 불가 → A(단조증가)로 본다
sa <- slim_naive[Ticker == "A"][order(Date)]$adv
saw <- ADV[Ticker == "A" & Date %in% ME][order(Date)]$adv
if (!eqf(sa[length(sa)], saw[length(saw)]))
  ok("B4_slim_naive_is_wrong", "slim 에 20창을 걸면 20개월 평균이 되어 일간-자와 갈린다(그래서 함수가 분기해야 함)")
else bad("B4_slim_naive_is_wrong", "합성 데이터가 이 축을 구별하지 못함 — 픽스처 재설계 필요")

#==============================================================================
# 축 C — build_monthly_forward_returns 통합 계약
#==============================================================================
cat("=== C. 함수 통합 계약 ===\n")

# C5: 시그니처 불변 (하위호환 — FQ-173 등 병행 소비자 보호)
fm <- names(formals(build_monthly_forward_returns))
if (identical(fm, c("rawdata", "sig_dates"))) ok("C5_signature_unchanged", paste(fm, collapse = ", "))
else bad("C5_signature_unchanged", sprintf("시그니처가 바뀌었다: %s", paste(fm, collapse = ", ")))

RD <- DAILY[, .(Date, Ticker, Close, Vol, Size, K200, KQ150)]
fwd_daily <- suppressWarnings(build_monthly_forward_returns(RD, ME))

# C1: 일간 입력 → 헌법 자
if (identical(fwd_daily$liq_ruler, "adv20_t1")) ok("C1_daily_ruler_label", "liq_ruler='adv20_t1'")
else bad("C1_daily_ruler_label", sprintf("일간 입력인데 라벨이 %s", fwd_daily$liq_ruler))

# C1b: liq_dt 의 adv 가 실제로 20일 평균(t-1) 인가
lq <- fwd_daily$liq_dt[Ticker == "A"][order(Date)]
ref <- ADV[Ticker == "A" & Date %in% ME][order(Date)]
# liq_dt 의 Date 는 sig_date(=월말) 이고 ADV 도 같은 월말 → 마지막 sig 제외하고 대조
k <- min(nrow(lq), nrow(ref))
if (k > 3 && all(eqf(lq$adv[seq_len(k - 1L)], ref$adv[seq_len(k - 1L)])))
  ok("C1b_liq_dt_is_adv20", sprintf("%d 월 전건 20일-자와 일치", k - 1L))
else bad("C1b_liq_dt_is_adv20", "liq_dt 의 adv 가 20일-자와 다르다")

# C2: 월말-slim 입력 → 저하 라벨 (조용히 20개월 평균을 내지 않는다)
RS <- SLIM[, .(Date, Ticker, Close, Vol, Size, K200, KQ150)]
fwd_slim <- suppressWarnings(build_monthly_forward_returns(RS, ME))
if (identical(fwd_slim$liq_ruler, "adv1_sameday_DEGRADED"))
  ok("C2_slim_degraded_label", "월말-slim 입력을 실측 탐지 → 라벨로 자백")
else bad("C2_slim_degraded_label",
         sprintf("slim 입력인데 라벨이 %s — 20개월 평균을 20일 평균이라 주장할 위험", fwd_slim$liq_ruler))

# C2b: 저하 경로가 warning 을 실제로 발행하는가 (침묵 저하 금지)
wmsg <- tryCatch({ withCallingHandlers(
    { build_monthly_forward_returns(RS, ME); character(0) },
    warning = function(w) { assign(".w", conditionMessage(w), envir = globalenv()); invokeRestart("muffleWarning") }) },
  error = function(e) character(0))
if (exists(".w", envir = globalenv()) && grepl("FQ-181", get(".w", envir = globalenv())))
  ok("C2b_degraded_warns", "저하 시 warning 발행")
else bad("C2b_degraded_warns", "저하가 침묵으로 지나간다")

# C3: 저하 경로도 adv 가 NA 가 아니다 (NA 는 필터를 통과 = 완화 방향)
if (fwd_slim$liq_dt[, sum(is.na(adv))] == 0L) ok("C3_degraded_not_na", "저하 경로 adv NA 0건")
else bad("C3_degraded_not_na", sprintf("adv NA %d 건 — NA 는 하류에서 통과한다",
                                       fwd_slim$liq_dt[, sum(is.na(adv))]))

# C4: 하위호환 — 자 교정이 returns_dt / bench_dt 를 건드리지 않는다
if (nrow(fwd_daily$returns_dt) == nrow(fwd_slim$returns_dt) &&
    eqf(sum(fwd_daily$returns_dt$Ret_1m), sum(fwd_slim$returns_dt$Ret_1m)))
  ok("C4_returns_untouched", "일간/slim 입력의 returns_dt 동일 (자는 수익을 건드리지 않음)")
else bad("C4_returns_untouched", "자 교정이 forward return 을 바꿨다 — 범위 침범")

# C6: 라벨이 liq_dt attr 로도 도달 (list 를 풀어 넘기는 소비자 보호)
if (identical(attr(fwd_daily$liq_dt, "liq_ruler"), "adv20_t1"))
  ok("C6_label_on_liq_dt_attr", "attr(liq_dt,'liq_ruler') 도달")
else bad("C6_label_on_liq_dt_attr", "liq_dt 에 자 라벨이 안 붙었다")

#==============================================================================
# 축 D — 방향성: 교정은 자를 **조인다** (완화 금지)
#==============================================================================
cat("=== D. 방향성(조임) ===\n")
# 종목 C = 월말에만 거래량 폭증(dval 1e9), 평소 1e6.
#   구판(월말 1일치) → 1e9 >= 2e8 통과 / 20일-자 → ~1e6+ 로 탈락. 교정이 조인다.
c_leg <- DAILY[Ticker == "C" & is_me == TRUE][order(Date)]$dval
c_new <- ADV[Ticker == "C" & Date %in% ME][order(Date)]$adv
i_last <- length(c_new)
if (c_leg[i_last] >= 2e8 && !is.na(c_new[i_last]) && c_new[i_last] < 2e8)
  ok("D1_correction_tightens", sprintf("월말펌프 종목: 구판 %.3g(통과) → 교정 %.3g(탈락)",
                                       c_leg[i_last], c_new[i_last]))
else bad("D1_correction_tightens",
         sprintf("조임 방향 미실증 (leg=%.3g new=%.3g)", c_leg[i_last], c_new[i_last]))

}   # ── 본문 블록 끝 ──

#==============================================================================
# 요약
#==============================================================================
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "liquidity_ruler", pass = PASS, fail = FAIL,
                total = PASS + FAIL, skipped = 0L), auto_unbox = TRUE), "\n", sep = "")
# ★ source() 경로에서 세션을 죽이지 않는다. Rscript(--file= / -e source) 는 비대화형이라 종료코드가 산다.
if (FAIL > 0 && !interactive()) quit(status = 1)
