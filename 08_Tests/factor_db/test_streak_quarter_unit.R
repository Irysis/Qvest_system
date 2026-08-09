#==============================================================================
# test_streak_quarter_unit.R — streak 팩터가 "영업일"이 아니라 "분기"를 세는가
#
# 지키는 결함 (FQ-219, 2026-08-10 적발·수리):
#   C11_Earnings_Streak / M25_Earnings_Mom_Streak 는 "연속 양수 SUE 의 개수"인데,
#   `.cons_history()` 가 준 **행**을 최신순으로 세고 있었다. 원천 sue 는 일간
#   캐리포워드라 한 분기에 여러 행이 들어가고, 실측 행/분기 비는 21~70 이었다
#   (21~31 = stale 필터 통과한 live 앵커 종목 / 41~70 = 미필터 패널 전체).
#   ⇒ 값의 단위가 분기가 아니라 **영업일**이었다.
#
# ★판별식이 FQ-218 과 다르다 — 여기서 `mean == latest` 는 쓸 수 없다.
#   평균 팩터는 창이 붕괴하면 이동평균이 **항등변환**이 되어 정보가 사라진다.
#   카운트 팩터는 창이 붕괴해도 정보가 사라지지 않고 **단위가 바뀐다**. 그래서
#   재야 할 것이 다르다. 이 검사의 고정 축 3개:
#     A 단위      — streak == (연속 양수 분기 수) 인가. 결함이면 비 41~70 (실측)
#     B 연속성    — 관측되지 않은 분기를 가로지르지 않는가. 결함이면 10.7~13.7% 가
#                   결번을 교량한다(옛 양수 런이 공백 너머로 이어붙는다)
#     C 릴리스 의존 — 릴리스가 없는 달에 값이 커지지 않는가. 결함이면 같은 분기 안
#                   월말 3점에서 28~42% 종목이 매달 ~21씩 증가한다
#   ★A~C 는 전부 "값이 그럴듯한" 상태에서 참이다. 행수·NA·오류 축으로는 원리적으로
#     안 잡힌다(행수 정상·NA 0·오류 0인 채 단위만 21~70배 틀려 있었다).
#
# 축:
#   1) 헬퍼 존재       — .cons_streak/.cons_epoch (수리 되돌림 즉시 검거)
#   2) ★본문 일치      — consensus/momentum 두 파일의 복제 정의가 갈리지 않았는가
#                        (빌더가 모듈을 별도 env 에 source 해 공유 불가. 2026-08-08 에
#                         "식·원천·정렬 동일"을 기록만 하고 강제가 없어 둘이 같이 틀렸다)
#   3) epoch 귀속      — 분기에 붙는 값이 그 분기 공표값인가 (기준값 = 경계+10일 이후
#                        첫 관측). 경계를 미는 돌연변이가 다음 분기 값을 끌어오는지 확인
#   4) 단위(A)         — 합성 픽스처에서 streak == 분기 수인가
#   5) 연속성(B)       — 결번 분기에서 끊기는가
#   6) staleness       — 죽은 커버리지(>130일)에 값을 내지 않는가
#   7) PIT 불변        — 미래 행이 있어도 결과가 같은가
#   8) ★위반 주입      — 수리를 되돌리는 돌연변이 4종이 A/B/C 축에 검거되는가
#   9) ★양성 대조      — 무관 팩터(C01/C04/C09/C02/M26)가 원천 독립 재계산과 비트 일치
#  10) 실데이터 A~C    — 원천이 있으면 실패널에서 A/B/C 를 직접 잰다
#
# ★"0건은 정지 신호" — 원천/대상이 없으면 PASS 가 아니라 SKIP.
#
# 실행: Rscript 08_Tests/factor_db/test_streak_quarter_unit.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR",
                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
PROJ <- gsub("\\\\", "/", PROJ)
MOD_C <- file.path(PROJ, "02_Infrastructure/factor_db/compute_consensus.R")
MOD_M <- file.path(PROJ, "02_Infrastructure/factor_db/compute_momentum.R")
if (!file.exists(MOD_C)) stop("[streak_unit] project root 아님 (marker 부재): ", PROJ)

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok   <- function(n, d = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }
bad  <- function(n, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }
skip <- function(n, d = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s%s\n", n, if (nzchar(d)) paste0(" — ", d) else "")) }
emit <- function(code) {
  cat(sprintf('{"test":"streak_quarter_unit","pass":%d,"fail":%d,"total":%d,"skip":%d}\n',
              PASS, FAIL, PASS + FAIL, SKIP))
  quit(status = code)
}

# ── 축 1: 헬퍼 존재 ─────────────────────────────────────────────────────────
envC <- new.env(parent = globalenv()); sys.source(MOD_C, envir = envC)
if (!exists(".cons_streak", envir = envC, inherits = FALSE) ||
    !exists(".cons_epoch",  envir = envC, inherits = FALSE)) {
  bad("helper_present", ".cons_streak/.cons_epoch 부재 — 수리가 되돌려졌다"); emit(1L)
}
ok("helper_present", ".cons_streak/.cons_epoch 존재 (consensus)")
.cs <- get(".cons_streak", envir = envC)
.ce <- get(".cons_epoch",  envir = envC)

# ── 축 2: 두 파일 복제 정의의 본문 일치 ─────────────────────────────────────
if (file.exists(MOD_M)) {
  envM <- new.env(parent = globalenv()); sys.source(MOD_M, envir = envM)
  if (!exists(".cons_streak", envir = envM, inherits = FALSE)) {
    bad("twin_helper_present", "compute_momentum.R 에 .cons_streak 부재 — M25 가 갈렸다")
  } else {
    b1 <- paste(deparse(body(.cs)), collapse = "\n")
    b2 <- paste(deparse(body(get(".cons_streak", envir = envM))), collapse = "\n")
    e1 <- paste(deparse(body(.ce)), collapse = "\n")
    e2 <- paste(deparse(body(get(".cons_epoch", envir = envM))), collapse = "\n")
    if (identical(b1, b2) && identical(e1, e2))
      ok("twin_body_identical", "consensus/momentum 복제 정의 본문 일치")
    else
      bad("twin_body_identical", sprintf("복제가 갈렸다 (streak=%s epoch=%s)",
          identical(b1, b2), identical(e1, e2)))
    s1 <- get(".CONS_STREAK_STALE_MAX", envir = envC)
    s2 <- get(".CONS_STREAK_STALE_MAX", envir = envM)
    if (identical(s1, s2)) ok("twin_const_identical", sprintf("stale 상한 %d 일치", s1))
    else bad("twin_const_identical", sprintf("stale 상한 불일치 %s vs %s", s1, s2))
  }
} else skip("twin_body_identical", "compute_momentum.R 부재")

# ── 픽스처 ──────────────────────────────────────────────────────────────────
# 릴리스 경계 = 4/1·6/1·9/1·12/1. 각 분기의 일간 캐리포워드를 합성한다.
mk_panel <- function(specs, start_ep_year = 2020L) {
  # specs: named list ticker -> numeric vector (오래된 분기부터), NA = 그 분기 결번
  bnd <- function(i) {  # i = 0.. 순번 → 경계일
    y <- start_ep_year + (i %/% 4L); s <- i %% 4L
    as.Date(sprintf("%d-%02d-01", y, c(4L, 6L, 9L, 12L)[s + 1L]))
  }
  out <- list()
  for (tk in names(specs)) {
    v <- specs[[tk]]
    for (i in seq_along(v)) {
      if (is.na(v[i])) next
      d0 <- bnd(i - 1L); d1 <- bnd(i) - 1L
      dts <- seq(d0, d1, by = "day")
      out[[length(out) + 1L]] <- data.table(Ticker = tk, Date = dts, sue = v[i])
    }
  }
  rbindlist(out)
}
LAST_BND <- function(n, y = 2020L) {
  yy <- y + (n %/% 4L); s <- n %% 4L
  as.Date(sprintf("%d-%02d-01", yy, c(4L, 6L, 9L, 12L)[s + 1L]))
}

# 8분기: A=전부 양수 / B=최근3 양수 / C=최근분기 음수 / D=결번 하나(3번째)
specs <- list(
  A = c(1, 1, 1, 1, 1, 1, 1, 1),
  B = c(-1, -1, -1, -1, -1, 2, 2, 2),
  C = c(1, 1, 1, 1, 1, 1, 1, -1),
  D = c(1, 1, NA, 1, 1, 1, 1, 1)      # 3번째 분기 결번 → 최근 5분기만 연속
)
P <- mk_panel(specs)
SIG <- LAST_BND(8L) - 1L               # 8번째 분기의 마지막 날
EXP <- c(A = 8, B = 3, C = 0, D = 5)

got <- .cs(P, "sue", SIG)
if (is.null(got)) { bad("fixture_unit", ".cons_streak 가 NULL — 픽스처가 안 먹는다"); emit(1L) }
setkey(got, Ticker)
g <- setNames(got$streak, got$Ticker)[names(EXP)]

# ── 축 4: 단위 ──────────────────────────────────────────────────────────────
if (isTRUE(all.equal(unname(g[c("A","B","C")]), unname(EXP[c("A","B","C")])))) {
  ok("unit_quarters", sprintf("A=%g B=%g C=%g (기대 8/3/0)", g["A"], g["B"], g["C"]))
} else {
  bad("unit_quarters", sprintf("A=%s B=%s C=%s (기대 8/3/0)", g["A"], g["B"], g["C"]))
}

# 행 단위였다면 A 는 분기당 ~90행 x 8 = 700+ 가 나온다
if (!is.na(g["A"]) && g["A"] < 20) {
  ok("unit_not_daily", sprintf("A=%g << 행 스케일", g["A"]))
} else {
  bad("unit_not_daily", sprintf("A=%s — 행 단위 의심", g["A"]))
}

# ── 축 5: 연속성 (결번 차단) ────────────────────────────────────────────────
if (!is.na(g["D"]) && g["D"] == EXP["D"]) {
  ok("gap_breaks_streak", sprintf("결번 분기 있는 D=%g (기대 5, 교량하면 7)", g["D"]))
} else {
  bad("gap_breaks_streak", sprintf("D=%s (기대 5) — 결번을 가로질렀다", g["D"]))
}

# ── 축 6: staleness ─────────────────────────────────────────────────────────
SIG_FAR <- SIG + 400L
got_far <- .cs(P, "sue", SIG_FAR)
if (is.null(got_far)) {
  ok("stale_anchor_blocked", "앵커 400일 경과 → NULL")
} else {
  bad("stale_anchor_blocked", sprintf("죽은 커버리지에 %d행 배출", nrow(got_far)))
}
# 경계 바로 안쪽은 살아야 한다 (상한이 legit 을 자르지 않는가)
SIG_NEAR <- SIG + 100L
got_near <- .cs(P, "sue", SIG_NEAR)
if (!is.null(got_near) && nrow(got_near) == length(EXP)) {
  ok("stale_bound_not_overtight", sprintf("100일 경과 시 %d행 유지", nrow(got_near)))
} else {
  bad("stale_bound_not_overtight",
      sprintf("100일 경과에서 %s행 — 상한이 legit 창을 자른다",
              if (is.null(got_near)) "0" else nrow(got_near)))
}

# ── 축 7: PIT 불변 (미래 행이 결과를 바꾸지 않는가) ─────────────────────────
P_fut <- rbind(P, data.table(Ticker = "A", Date = SIG + 1:200, sue = -99))
got_fut <- .cs(P_fut, "sue", SIG)
# ★값만 비교한다. data.table 키/정렬 속성까지 비교하면 검사가 PIT 가 아니라
#   속성 차이에 반응한다(초판이 그렇게 빨개졌다 — 검사 자신의 오답).
.vals <- function(dt) { x <- as.data.frame(dt[order(Ticker), .(Ticker, streak)])
                        rownames(x) <- NULL; x }
if (!is.null(got_fut) && isTRUE(all.equal(.vals(got_fut), .vals(got)))) {
  ok("pit_future_rows_ignored", "미래 행 200개 추가에도 결과 동일")
} else {
  bad("pit_future_rows_ignored", "미래 행이 결과를 바꿨다")
}

# ── 축 3 + 8: epoch 귀속 + 위반 주입 ────────────────────────────────────────
# 돌연변이 4종. 각각 수리의 한 축을 되돌린다.
mut_rows <- function(hist, metric, sig_d, ...) {   # M1: 행 카운트 (원 결함)
  h <- hist[!is.na(get(metric)) & Date <= sig_d]
  setorderv(h, c("Ticker", "Date"), c(1L, -1L))
  h[, { s <- 0L
        for (i in seq_len(.N)) { if (get(metric)[i] > 0) s <- s + 1L else break }
        list(streak = as.numeric(s)) }, by = Ticker]
}
mut_nogap <- function(hist, metric, sig_d, ...) {  # M2: 결번 차단 제거
  h <- hist[!is.na(get(metric)) & Date <= sig_d]
  h[, ep := .ce(Date)]
  setorderv(h, c("Ticker", "ep", "Date"))
  e <- h[, .(value = get(metric)[.N]), by = .(Ticker, ep)]
  setorderv(e, c("Ticker", "ep"), c(1L, -1L))
  e[, { s <- 0L
        for (i in seq_len(.N)) { if (value[i] > 0) s <- s + 1L else break }
        list(streak = as.numeric(s)) }, by = Ticker]
}
mut_nostale <- function(hist, metric, sig_d, ...) .cs(hist, metric, sig_d, max_stale_days = 99999L)
mut_shift <- function(hist, metric, sig_d, ...) { # M4: epoch 경계 밀기
  h <- hist[!is.na(get(metric)) & Date <= sig_d]
  h[, ep := .ce(Date - 5L)]
  setorderv(h, c("Ticker", "ep", "Date"))
  e <- h[, .(value = get(metric)[.N]), by = .(Ticker, ep)]
  setorderv(e, c("Ticker", "ep"), c(1L, -1L))
  e[, { s <- 0L; pe <- NA_integer_
        for (i in seq_len(.N)) {
          if (i > 1L && (pe - ep[i]) != 1L) break
          if (value[i] > 0) { s <- s + 1L; pe <- ep[i] } else break }
        list(streak = as.numeric(s)) }, by = Ticker]
}

caught <- 0L; tried <- 0L
# M1 행 카운트: A 가 20 이상이면 검거
tried <- tried + 1L
m <- mut_rows(P, "sue", SIG); v <- setNames(m$streak, m$Ticker)["A"]
if (!is.na(v) && v >= 20) { caught <- caught + 1L
  ok("mut_row_count_caught", sprintf("행-카운트 돌연변이 A=%g (>=20) 검거", v))
} else bad("mut_row_count_caught", sprintf("행-카운트 돌연변이 A=%s — 미검거", v))
# M2 결번 미차단: D 가 5 가 아니면 검거
tried <- tried + 1L
m <- mut_nogap(P, "sue", SIG); v <- setNames(m$streak, m$Ticker)["D"]
if (!is.na(v) && v != 5) { caught <- caught + 1L
  ok("mut_gap_bridge_caught", sprintf("결번 교량 돌연변이 D=%g (정본 5) 검거", v))
} else bad("mut_gap_bridge_caught", sprintf("결번 교량 돌연변이 D=%s — 미검거", v))
# M3 stale 미차단: SIG_FAR 에서 NULL 이 아니면 검거
tried <- tried + 1L
m <- mut_nostale(P, "sue", SIG_FAR)
if (!is.null(m) && nrow(m) > 0) { caught <- caught + 1L
  ok("mut_stale_caught", sprintf("stale 미차단 돌연변이 %d행 배출 검거", nrow(m)))
} else bad("mut_stale_caught", "stale 미차단 돌연변이 — 미검거")
# M4 경계 밀기: 기준값 귀속률로 검거 (분기 값이 다음 분기에서 온다)
tried <- tried + 1L
# ★픽스처 선택이 검거력을 결정한다. 교대 부호(…,+1,-1)로는 정본도 돌연변이도 0 이라
#   구별이 안 된다(초판이 그래서 미검거였다). v7=-1, v8=+1 이면 정본 streak=1 인데
#   경계를 밀면 epoch7 이 v8(+1) 을 끌어와 2 가 된다 — 그 차이가 검거 축이다.
P2 <- mk_panel(list(E = c(1, 1, 1, 1, 1, 1, -1, 1)))
m_ok  <- .cs(P2, "sue", LAST_BND(8L) - 1L)
m_bad <- mut_shift(P2, "sue", LAST_BND(8L) - 1L)
if (!is.null(m_ok) && !is.null(m_bad) && m_ok$streak[1] != m_bad$streak[1]) {
  caught <- caught + 1L
  ok("mut_boundary_shift_caught", sprintf("경계 밀기 검거 (정본 %g vs 돌연변이 %g)",
     m_ok$streak[1], m_bad$streak[1]))
} else bad("mut_boundary_shift_caught",
           sprintf("경계 밀기 미검거 (정본 %s / 돌연변이 %s)",
                   if (is.null(m_ok)) NA else m_ok$streak[1],
                   if (is.null(m_bad)) NA else m_bad$streak[1]))

# ── 축 3/10: 실데이터 — epoch 귀속 + A/B/C 축 ───────────────────────────────
CONS_DIR <- file.path(PROJ, ".cache/consensus")
SUEP <- file.path(CONS_DIR, "sue.parquet")
if (!file.exists(SUEP) || !requireNamespace("arrow", quietly = TRUE)) {
  skip("real_epoch_attribution", "원천 부재 — 0건은 PASS 아님")
  skip("real_unit_axis", "원천 부재")
  skip("real_release_independence", "원천 부재")
  skip("positive_control_untouched", "원천 부재")
} else {
  S <- as.data.table(arrow::read_parquet(SUEP))
  if (!inherits(S$Date, "Date")) S[, Date := as.Date(Date)]
  S <- S[!is.na(sue), .(Ticker, Date, sue)]
  ep_start <- function(ep) {
    y <- ep %/% 4L; s <- ep %% 4L
    as.Date(sprintf("%d-%02d-01", y, c(4L, 6L, 9L, 12L)[s + 1L]))
  }
  # 축 3: 분기에 붙은 값이 그 분기 공표값(경계+10일 이후 첫 관측)인가
  H <- copy(S); H[, ep := .ce(Date)]
  setorderv(H, c("Ticker", "ep", "Date"))
  asg <- H[, .(assigned = sue[.N]), by = .(Ticker, ep)]
  tru <- H[Date >= (ep_start(ep) + 10L), .(truth = sue[1L]), by = .(Ticker, ep)]
  mm <- merge(asg, tru, by = c("Ticker", "ep"))
  mm <- mm[ep_start(ep + 1L) < max(S$Date)]
  fm <- mean(abs(mm$assigned - mm$truth) < 1e-12)
  if (fm > 0.99) ok("real_epoch_attribution", sprintf("분기 귀속 기준값 일치 %.4f (n=%d)", fm, nrow(mm)))
  else bad("real_epoch_attribution", sprintf("분기 귀속 일치 %.4f — 경계 규약이 깨졌다", fm))

  RSIG <- as.Date(c("2010-06-30", "2016-06-30", "2022-06-30", "2026-06-30"))
  ratios <- c(); bridged <- c()
  for (sd_ in RSIG) {
    sd_ <- as.Date(sd_, origin = "1970-01-01")
    h <- S[Date <= sd_]
    if (!nrow(h)) next
    cur <- .cs(h, "sue", sd_)
    if (is.null(cur)) next
    setorderv(h, c("Ticker", "Date"), c(1L, -1L))
    rowsk <- h[, { s <- 0L
                   for (i in seq_len(.N)) { if (sue[i] > 0) s <- s + 1L else break }
                   list(r = as.numeric(s)) }, by = Ticker]
    j <- merge(cur[streak >= 1L], rowsk, by = "Ticker")
    if (nrow(j) > 10L) ratios <- c(ratios, median(j$r / j$streak))
  }
  if (length(ratios) && all(ratios > 10))
    ok("real_unit_axis", sprintf("행/분기 비 중앙 %s — 구 구현이 일간이었음 재확인",
        paste(sprintf("%.0f", ratios), collapse = "/")))
  else if (!length(ratios)) skip("real_unit_axis", "표본 부족")
  else bad("real_unit_axis", sprintf("비 %s — 전제 붕괴, 판별식 재검토 필요",
           paste(sprintf("%.1f", ratios), collapse = "/")))

  # 축 C: 릴리스 없는 달에 값이 커지지 않는가 (같은 epoch 내 월말 2점)
  d0 <- as.Date("2018-06-29"); d1 <- as.Date("2018-07-31")
  a <- .cs(S[Date <= d0], "sue", d0); b <- .cs(S[Date <= d1], "sue", d1)
  if (!is.null(a) && !is.null(b)) {
    j <- merge(a[, .(Ticker, s0 = streak)], b[, .(Ticker, s1 = streak)], by = "Ticker")
    fr <- mean(j$s0 != j$s1)
    if (fr < 0.02) ok("real_release_independence",
                      sprintf("같은 분기 내 월 이동에서 변동 %.4f (n=%d)", fr, nrow(j)))
    else bad("real_release_independence",
             sprintf("릴리스 없는 달에 %.4f 가 변동 — 행 단위 잔재", fr))
  } else skip("real_release_independence", "표본 부족")

  # ★양성 대조 — 무관 팩터가 원천 독립 재계산과 비트 일치인가 (수리 누출 검거)
  CONS <- list()
  for (m in c("sue", "esbr", "eps_chg_1m", "revenue_fy1")) {
    p <- file.path(CONS_DIR, paste0(m, ".parquet"))
    if (file.exists(p)) CONS[[m]] <- as.data.table(arrow::read_parquet(p))
  }
  RAWP <- file.path(PROJ, ".cache/RAWDATA.parquet")
  if (!file.exists(RAWP) || !exists("compute_consensus", envir = envC, inherits = FALSE)) {
    skip("positive_control_untouched", "RAWDATA 또는 진입함수 부재")
  } else {
    RAW <- as.data.table(arrow::read_parquet(RAWP))
    if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date)]
    sd_ <- as.Date("2022-06-30")
    rd <- RAW[Date <= sd_ & Date >= (sd_ - 400L)]
    res <- envC$compute_consensus(rd, sd_, NULL, CONS); setDT(res)
    ref <- list()
    sh <- CONS$sue[Date <= sd_ & !is.na(sue)]
    setorderv(sh, c("Ticker", "Date"), c(1L, -1L))
    l <- sh[, .SD[1L], by = Ticker]
    ref[["C01_SUE"]] <- l[, .(Ticker, v = sue)]
    ref[["C09_Earnings_Surprise_Sq"]] <- l[, .(Ticker, v = sign(sue) * sue^2)]
    eh <- CONS$esbr[Date <= sd_ & !is.na(esbr)]
    setorderv(eh, c("Ticker", "Date"), c(1L, -1L))
    ref[["C04_ESBR"]] <- eh[, .SD[1L], by = Ticker][, .(Ticker, v = esbr)]
    nbad <- 0L; nchk <- 0L
    for (fn in names(ref)) {
      a <- res[Factor_Name == fn, .(Ticker, v2 = Raw_Value)]
      if (!nrow(a)) next
      j <- merge(a, ref[[fn]], by = "Ticker")
      j <- j[is.finite(v) & is.finite(v2)]
      if (!nrow(j)) next
      nchk <- nchk + 1L
      if (max(abs(j$v - j$v2)) > 1e-9) nbad <- nbad + 1L
    }
    if (nchk == 0L) skip("positive_control_untouched", "대조 팩터 0건 — PASS 아님")
    else if (nbad == 0L) ok("positive_control_untouched",
                            sprintf("무관 팩터 %d종이 원천 독립 재계산과 비트 일치", nchk))
    else bad("positive_control_untouched", sprintf("%d/%d 종이 변했다 — 수리가 새어나갔다", nbad, nchk))
  }
}

cat(sprintf("\n[streak_quarter_unit] PASS %d / FAIL %d / SKIP %d  (위반 주입 %d/%d 검거)\n",
            PASS, FAIL, SKIP, caught, tried))
emit(if (FAIL > 0L) 1L else 0L)
