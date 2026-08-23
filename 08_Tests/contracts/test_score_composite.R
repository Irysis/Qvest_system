# test_score_composite.R — score-level composite 계약의 **위반 주입** 검사 (v9.1 §7-S3a)
#
# 왜 있나: 이 계약의 실질 난점은 계산이 아니라 **멤버 support 불일치 규약**이다.
#   결측 멤버를 0 으로 채우면 "그 멤버가 이 종목을 중립으로 봤다"는 없는 진술이 생기고,
#   그 오류는 산출물 어디에도 흔적을 남기지 않는다(조용한 오염). 그래서 이 파일의 1급 축은
#   "z 가 계산되는가"가 아니라 **"결측을 0 으로 채우지 않는가"** 다.
#   [[feedback-verify-both-directions-always]] — 양성 대조 + 위반 주입 양방향으로 잰다.
#
# 실행: Rscript 08_Tests/contracts/test_score_composite.R
suppressWarnings(suppressMessages({
  library(data.table)
  # ★금칙 ④ 표준 계열: CLAUDE_PROJECT_DIR 먼저 (테스트와 피호출 모듈의 계열이 갈리면
  #   worktree 실행에서만 root 가 어긋나 잠복한다)
  ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
  src  <- file.path(ROOT, "02_Infrastructure", "contracts", "score_composite.R")
}))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d) { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", paste(d, collapse = " "), "\n") }

if (!file.exists(src)) {
  cat("  SKIP  계약 부재:", src, "\n== t_summary: PASS=0 FAIL=0 ==\n"); quit(save = "no", status = 0)
}
source(src)
set.seed(20260823)

# ── 합성 멤버 생성기 ─────────────────────────────────────────────────────────
DATES <- as.Date(c("2020-01-31", "2020-02-29", "2020-03-31"))
TK    <- sprintf("A%03d", 1:60)
mk <- function(tickers_by_date, sd_mult = 1) {
  rbindlist(lapply(seq_along(DATES), function(i) {
    tk <- tickers_by_date[[i]]
    if (!length(tk)) return(NULL)
    data.table(Date = DATES[i], Ticker = tk, Score = rnorm(length(tk)) * sd_mult)
  }))
}
all3 <- list(TK, TK, TK)

cat("== ① sc_zscore_by_date — 시점별 평균 0 · sd 1 ==\n")
m1 <- mk(all3, sd_mult = 3)
z1 <- sc_zscore_by_date(m1)
agg <- z1[, .(mu = mean(z), sdv = sd(z), sdx = sd(Score)), by = Date]
if (all(abs(agg$mu) < 1e-9)) ok("시점별 z 평균 = 0") else ng("z 평균", agg$mu)
if (all(abs(agg[sdx > 0]$sdv - 1) < 1e-9)) ok("시점별 z sd = 1 (sd>0 인 시점)") else ng("z sd", agg$sdv)
# 규약: sd==0 이면 0 벡터 (factor_engine_composite_mom.R:57 .zsc 자구동일)
flat <- data.table(Date = DATES[1], Ticker = TK, Score = 7)
zf <- sc_zscore_by_date(flat)
if (all(zf$z == 0)) ok("sd=0 시점 → z 전원 0 (NaN 아님)") else ng("sd=0 규약", unique(zf$z))
# 돌연변이 통제 — 검사가 실제로 무언가를 재는가
if (!all(abs(m1$Score) < 1e-9)) ok("돌연변이 통제: 원 Score 는 z 가 아니다(검사가 자명참 아님)") else
  ng("돌연변이 통제", "원 Score 가 이미 표준화돼 있음")

cat("== ② sc_combine_scores — min_members 미달 행 제외 ==\n")
# m_a: 전 종목 / m_b: 앞 30종만 / m_c: 뒤 30종만  → 겹치는 종목이 없다
a <- mk(all3); b <- mk(list(TK[1:30], TK[1:30], TK[1:30])); c3 <- mk(list(TK[31:60], TK[31:60], TK[31:60]))
cmb2 <- sc_combine_scores(list(a = a, b = b, c = c3), min_members = 2L)
if (all(cmb2$n_members >= 2L)) ok("출력 전 행 n_members >= 2") else ng("n_members", range(cmb2$n_members))
if (nrow(cmb2) == 3L * 60L) ok(sprintf("모든 (Date,Ticker) 가 정확히 2 멤버로 살아남음 (%d행)", nrow(cmb2))) else
  ng("행수", nrow(cmb2))
# b·c 는 서로소 support 라 3멤버가 동시에 관측되는 (Date,Ticker) 는 없다.
#   → 계약상 "빈 결과 = 합격 아님" 이므로 stop 이 정답이다(⑥에서 다시 잰다).
cmb3 <- tryCatch(sc_combine_scores(list(a = a, b = b, c = c3), min_members = 3L),
                 error = function(e) conditionMessage(e))
if (is.character(cmb3) && grepl("min_members=3", cmb3)) {
  ok("min_members=3 → 3멤버 동시관측 0 이므로 stop (조용한 빈 결과 아님)")
} else if (is.data.table(cmb3) && all(cmb3$n_members >= 3L)) {
  ok("min_members=3 → 3멤버 미만 전량 제외")
} else ng("min_members=3", cmb3)

cat("== ③ sc_cap_top_n — N 이 전 시점 <= 25 ==\n")
cap <- sc_cap_top_n(cmb2, top_n = 25L)
nn <- cap[, .(N = N[1], n_rows = .N), by = Date]
if (all(nn$N <= 25L)) ok(sprintf("N max = %d", max(nn$N))) else ng("N 상한", nn$N)
if (all(nn$n_rows > 25L)) ok("행은 자르지 않는다(buffer_zone 순위표 보존) — N 만 박는다") else
  ng("행 보존", nn$n_rows)
cap100 <- sc_cap_top_n(cmb2, top_n = 100L)   # ★E-5: 25 초과 요청도 클램프
if (max(cap100$N) <= 25L) ok("top_n=100 요청도 25 로 클램프 (SC_HOLDINGS_CAP)") else
  ng("클램프 실패", max(cap100$N))
small <- sc_cap_top_n(data.table(Date = DATES[1], Ticker = TK[1:10], Score = rnorm(10)))
if (unique(small$N) == 10L) ok("종목이 10개뿐인 시점 → N=10 (25 로 부풀리지 않음)") else
  ng("소규모 시점 N", unique(small$N))

cat("== ④ ★위반 주입 — 결측 멤버를 0 으로 채우지 않는가 ==\n")
# 멤버 2개, 두 번째 멤버를 첫 시점에서 통째로 비운다.
b_hole <- mk(list(character(0), TK, TK))
h2 <- sc_combine_scores(list(a = a, b = b_hole), min_members = 2L)
if (!any(h2$Date == DATES[1])) {
  ok("min_members=2 · 한 멤버 공백 시점 → 그 시점 행이 사라진다(0 채움 아님)")
} else ng("공백 시점 잔존", nrow(h2[Date == DATES[1]]))
# 양성 대조: min_members=1 이면 살아남되 **Score 가 반토막 나지 않아야** 한다.
#   0 으로 채웠다면 Score = (z_a + 0)/2 = z_a/2 가 된다 — 그것이 이 검사가 잡는 것이다.
h1 <- sc_combine_scores(list(a = a, b = b_hole), min_members = 1L)
za <- sc_zscore_by_date(a)[Date == DATES[1], .(Ticker, z)]
cmp <- merge(h1[Date == DATES[1], .(Ticker, Score, n_members)], za, by = "Ticker")
if (nrow(cmp) && all(abs(cmp$Score - cmp$z) < 1e-9)) {
  ok("min_members=1 · 공백 시점 Score == 단독 멤버 z (분모에서 결측 멤버 제외)")
} else ng("결측 0채움 의심", if (nrow(cmp)) max(abs(cmp$Score - cmp$z)) else "겹침 0")
if (nrow(cmp) && all(cmp$n_members == 1L)) ok("그 시점 n_members = 1 로 기록") else
  ng("n_members 기록", unique(cmp$n_members))
# 돌연변이 통제: 0 채움 판본을 손으로 만들어 검사가 그것을 **탈락시키는지** 확인
zero_filled <- copy(cmp)[, Score := z / 2]
if (!all(abs(zero_filled$Score - zero_filled$z) < 1e-9)) {
  ok("돌연변이 통제: 0 채움 판본이었다면 위 검사가 FAIL 했다")
} else ng("돌연변이 통제", "0 채움 판본을 구별하지 못한다")

cat("== ⑤ sc_weight_blend_top_n — 대조군 지표 범위 ==\n")
wl <- lapply(1:3, function(k) {
  rbindlist(lapply(DATES, function(d) {
    tk <- sample(TK, 25L)
    data.table(Date = d, Ticker = tk, w = rep(1 / 25, 25L))
  }))
})
names(wl) <- c("s1", "s2", "s3")
wb <- sc_weight_blend_top_n(wl, top_n = 25L)
if (is.finite(wb$weight_retained_mean) &&
    wb$weight_retained_mean >= 0 && wb$weight_retained_mean <= 1) {
  ok(sprintf("weight_retained_mean = %.4f ∈ [0,1]", wb$weight_retained_mean))
} else ng("weight_retained_mean 범위", wb$weight_retained_mean)
if (wb$n_union_pre_trunc > 25) {
  ok(sprintf("union 이 25 를 넘는다 (%.1f종 / 75 슬롯) — 절단이 실재", wb$n_union_pre_trunc))
} else ng("union", wb$n_union_pre_trunc)
if (wb$weight_retained_mean < 1) ok("절단 손실이 0 이 아니다(대조군의 존재이유)") else
  ng("절단 손실", wb$weight_retained_mean)
chk <- wb$weights[, .(sw = sum(w), n = .N), by = Date]
if (all(abs(chk$sw - 1) < 1e-9)) ok("절단 후 Date별 Σw = 1 재정규화") else ng("Σw", chk$sw)
if (all(chk$n <= 25L)) ok(sprintf("절단 후 보유 <= 25 (max %d)", max(chk$n))) else ng("보유 상한", chk$n)
if (identical(wb$n_trunc_months, 3L)) ok("n_trunc_months = 3 (전 시점 절단 발생)") else
  ng("n_trunc_months", wb$n_trunc_months)

cat("== ⑥ 계약 경계 — 잘못된 입력은 조용히 통과하지 않는다 ==\n")
e1 <- tryCatch({ sc_combine_scores(list(a = a), weights = c(1, 1)); "no-error" },
               error = function(e) "error")
if (identical(e1, "error")) ok("weights 길이 불일치 → stop") else ng("weights 검증", e1)
e2 <- tryCatch({ sc_cap_top_n(data.table(Date = DATES[1], x = 1)); "no-error" },
               error = function(e) "error")
if (identical(e2, "error")) ok("Date/Ticker/Score 부재 → stop") else ng("컬럼 검증", e2)
e3 <- tryCatch({ sc_combine_scores(list(a = a, b = b_hole), min_members = 9L); "no-error" },
               error = function(e) "error")
if (identical(e3, "error")) ok("만족 행 0 → stop (빈 결과를 합격으로 내려앉히지 않는다)") else
  ng("빈 결과 처리", e3)

cat("== ⑦ sc_harvest_member — 멤버 격리 + N 폐기 ==\n")
.td <- file.path(tempdir(), "sc_members"); dir.create(.td, showWarnings = FALSE, recursive = TRUE)
.e1 <- file.path(.td, "eng_a.R"); .e2 <- file.path(.td, "eng_b.R"); .e3 <- file.path(.td, "eng_bad.R")
writeLines(c('stopifnot(exists("RAWDATA"))',
             'FACTORS <- RAWDATA[, .(Score = mean(Px)), by = .(Date, Ticker)]',
             'FACTORS[, N := 999L]'), .e1)          # ★멤버가 N 을 들고 온다
writeLines(c('RAWDATA[, junk := 1L]',                # ★멤버가 RAWDATA 를 참조 수정한다
             'FACTORS <- RAWDATA[, .(Score = -mean(Px)), by = .(Date, Ticker)]'), .e2)
writeLines(c('x <- 1'), .e3)                          # FACTORS 를 안 만든다
RD <- data.table(Date = rep(DATES, each = 40), Ticker = rep(TK[1:40], times = 3),
                 Px = rnorm(120))
h <- sc_harvest_member(.e1, RD)
if (identical(sort(names(h)), c("Date", "Score", "Ticker"))) ok("멤버 N 컬럼 폐기 (Date/Ticker/Score 만)") else
  ng("N 폐기", names(h))
invisible(sc_harvest_member(.e2, RD))
if (!("junk" %in% names(RD))) ok("멤버의 RAWDATA 참조 수정이 호출자에게 새지 않는다(copy 격리)") else
  ng("copy 격리", names(RD))
e4 <- tryCatch({ sc_harvest_member(.e3, RD); "no-error" }, error = function(e) "error")
if (identical(e4, "error")) ok("FACTORS 미생성 멤버 → stop") else ng("FACTORS 검증", e4)

cat("== ⑧ sc_axes / sc_incremental_report — 실 bt_result 구조 소비 (있으면) ==\n")
bts <- Sys.glob(file.path(ROOT, "stage_artifacts", "alpha_search", "20260823_*", "bt_result.rds"))
if (length(bts) >= 2L) {
  r <- tryCatch(sc_incremental_report(bts[1], setNames(as.list(bts[2:min(3, length(bts))]),
                                                       basename(dirname(bts[2:min(3, length(bts))])))),
                error = function(e) conditionMessage(e))
  if (is.list(r) && all(c("axes", "verdict") %in% names(r))) {
    ok(sprintf("증분 보고 산출 — verdict=%s · 축 %d행", r$verdict, nrow(r$axes)))
    if (identical(sort(r$axes$axis), sort(names(SC_AXIS_HIGHER_BETTER))))
      ok("축 6종(SR/MDD/Calmar/IR/PORT_t_NW3/book_dIR) 전부 보고") else
      ng("축 목록", r$axes$axis)
    if (r$verdict %in% c("INCREMENTAL_GAIN", "NO_INCREMENTAL_GAIN"))
      ok("verdict 어휘 = HARD 판정 2값") else ng("verdict", r$verdict)
  } else ng("증분 보고", r)
} else {
  cat("  SKIP  bt_result.rds 2건 미만 — 실 소비 축 생략\n")
}

cat(sprintf("== t_summary: PASS=%d FAIL=%d ==\n", PASS, FAIL))
# ★러너(run_all_hooks.sh)는 **마지막 줄의 JSON**으로만 집계한다. t_summary 만 내면
#   UNREPORTED 로 계상돼 "돌았는데 안 센" 상태가 된다(2026-08-23 배터리에서 실측 —
#   미발행 27건이 fail 로 잡혔다). 요약 형식이 두 갈래로 갈려 있는 저장소이므로
#   신규 suite 는 JSON 을 **마지막 줄**에 낸다.
cat(sprintf('{"test":"score_composite","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(save = "no", status = 1)
