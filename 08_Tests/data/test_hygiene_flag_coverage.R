#!/usr/bin/env Rscript
#==============================================================================
# test_hygiene_flag_coverage.R — 활성 종목의 위생 표식 NA 감시(경보만 · 판정 불변 · F7 · 2026-11-06 · 같은 날 2차 수리)
#
# 왜: 퀀티 Update_File 책마다 DATA_Key(질의 종목 목록)가 달라(OHLCVS 3,717 · 수급 · 컨센서스 · 유니버스 3,668)
#   신규 상장 53종이 위생 질의(Universe_Support)에서 빠졌다. RAWDATA 2026-11-05 에 그 53종의 위생 표식이 전부 NA 였고,
#   위생 판정식(factor_z_standard.R::corp_action_member)은 NA 를 '정상'으로 통과시킨다 → 측정 축 위생(MC1)이 그 종목을
#   판정하지 못한 채 멤버로 들인다(실측: 아이티켐 — 관리종목 지정 04-07 뒤 18거래일 · 거래량 0 날로는 20일 멤버).
#   아무도 이 결손을 보지 못했다. 보고서 = PLAN(04_Research/01_reports/quantiwise_data_expansion_20261106/PLAN.md) §3.0 F7.
#
# 무엇을 재나(소비면 = RAWDATA — 측정 계약이 실제로 읽는 패널):
#   기준일(as_of = RAWDATA 최신일)에 거래가 있는 종목 중 위생 표식이 NA 인 것을 셋으로 가른다.
#     item_uncovered — 기준일까지 그 항목 값이 한 번도 없다(항목 이력 시작 전 · 예 불성실공시 2009-03 이전) → 구조적 · 경보 아님
#     grace          — 상장 뒤 K 거래일 이내(첫 월말 스냅숏 전 · 구조적 지연) → 경보 아님
#     gap            — 그 밖 = 항목 이력은 이미 있는데 그 종목 값이 없다(DATA_Key 결손형) → ★경보
#   ★항목 이력이 시작된 뒤 기준일에 그 항목이 전 종목 NA 인 경우(전면 결손 — 적재 · 조인 실패로 위생이 전 유니버스에서 조용히
#     꺼진 상태)도 gap 이다(유예 안 종목만 빼고 전부 경보 · per_flag$whole_drop 로 따로 표시). 1차 판(같은 날)은 '기준일 커버리지 = 0'
#     을 항목 전으로 접어 이 경우 경보가 0 이었다 — 2026-11-06 독립 검증 실측: 53종 뺀 사본에 기준일 AdminStock 을 전 종목 NA 로
#     넣으면 pass 였고, 그 상태에서 실제 관리종목 20종이 그날 측정 축 멤버가 된다(NA = 정상 통과). 이 성질은 S11 · L0c 가 잰다.
#   K(구조적 유예 창) = 같은 달력에서 '한 달 거래일 수'의 최댓값(측정 축 시작일 이후 · 2026-11-06 실측 23) — 매번 달력에서 산출한다.
#     근거(기전): 위생 표식은 월간 스냅숏이다(Universe_Support 질의 B4 = M · 2026-11-06 사본 8시트 확인) → 책에 든 신규 상장은
#     늦어도 상장한 달의 월말 스냅숏에 첫 값이 생긴다 → 구조적 NA 는 길어야 '그 달 남은 거래일' ≤ 한 달 거래일 수의 최댓값.
#     관측 대조(2026-11-06 · 2000~ 상장 2,344종): 상장→첫 표식 간격 p50 2~8 · p90 16 · p99 20 — 상한 안쪽이다.
#     ★관측 분포의 분위(p99)를 K 로 쓰지 않는 이유: 그 분포 꼬리는 과거 DATA_Key 결손 사례(예 2009 상장 → 2018 첫 표식 2,184 거래일)
#     로 오염돼 있고 그 비율이 약 1% 라 p99 가 꼬리에 걸린다(불성실공시 p99 = 129 · 거래정지 · 관리종목 p99 = 20 — 2026-11-06 실측).
#     상한을 넘은 과거 상장 수(n_exceed)는 '이 결손이 전에도 있었다'는 기록으로 함께 보고한다.
#     경계(td ≤ K = grace · td = K+1 = gap)는 합성 경계 종목 2종(S13)과 뮤테이션 M9~M12 가 고정한다.
#   표식 목록 · 측정 축 시작일은 측정 축 계약(contracts/measurement_axis.R::ma_epoch)에서 읽는다(고정 목록 없음).
#   한계: RAWDATA 에 아예 없는 종목(OHLCVS DATA_Key 밖 신규 상장)은 이 감시가 못 본다 — 상장 원장 대조가 따로 필요하다.
#
# 판정 불변 — 이 시험은 위생 판정식을 고치거나 덮지 않는다. 실패할 수 있는 단언으로 잰다:
#   C1  전제 실측: 이 감시가 기대는 현행 판정 의미(표식 NA = 통과)를 계약 함수에서 직접 잰다 → 의미가 바뀌면 red
#       (도훈 결정 · 새 epoch 이면 이 감시의 경보 의미와 이 단언을 함께 고친다).
#   C1m 통제: 판정식 사본의 소스 텍스트를 'NA = 탈락'으로 치환하면 같은 잣대가 red 여야 한다(C1 이 실제로 실패할 수 있다).
#   C2  실행 전후 계약 파일(factor_z_standard.R · measurement_axis.R) 내용 지문(md5) 동일 — 이 실행이 판정 코드를 바꾸지 않았다.
#   C2c 통제: 같은 지문 비교가 1바이트 바뀐 임시 파일을 '다름'으로 잰다(비교기 생존).
#   멤버 수(gap 종목 중 지금 측정 축 멤버)는 계약 함수(ma_membership)로 잰다 — NA 처리 의미가 바뀌면 그 수가 따라 바뀐다.
#
# 구성:
#   S1~S13 합성 자기 시험(양성 대조 · 위반 주입 4종 · 구조적 NA 2종 · 비활성 · 순수성 · K 산출 2종 · as_of 절단 · 유예 경계)
#   C1 · C1m · C2 · C2c 계약 전제 · 판정 불변(위)
#   M0~M12 뮤테이션 테스트 — 이 파일의 SCAN 블록 소스 텍스트를 치환한 사본(치환 성사 단정)이 자기 시험에서 red 여야 한다
#        (M0 = 무치환 통제 · 사본이 오류로 죽으면 검거로 세지 않고 fail)
#   L0a~L0c live 경로 연기 시험 — 합성 parquet 을 실제 판독 경로(read → scan → 계약 멤버십)로 태운다(양방향 + 전면 결손)
#   L1   live — 운영 RAWDATA(읽기 전용 · mmap 끔)의 gap 종목 수. 0 이면 pass, 아니면 경보
#        QVEST_HYG_COVERAGE_LIVE = fail(기본 · 경보를 fail 로 계상) | warn(출력만 · 계상 안 함) | off(건너뜀 = skipped)
#        QVEST_HYG_RAWDATA = 판독 경로 덮어쓰기(모래상자 사본 검사용) · QVEST_HYG_US_ADMIN = us_admin_stock 사본(INFO 용)
#   INFO 지수 표식(K200 · KQ150) NA · 최신 스냅숏 결손(직전 값 이월 = 낡은 표식) 종목 수 — 계상 안 함
#
# 루트(r-portability.md 금칙 ④ · ④-b): 시험은 자기 위치 먼저(self-first), 환경변수는 CLAUDE_PROJECT_DIR → QM_ROOT 순.
#   후보마다 역슬래시를 / 로 바꾼 뒤 표지(02_Infrastructure/hooks/qvest_hook_router.py)로 검증하고, 자기 트리를 못 쓰면
#   stderr 로 ANCHOR OVERRIDE 를 알린다(어느 트리를 쟀는지 로그에 남긴다).
# 격리: 쓰기 0(운영 · 임시 모두 — L0 의 합성 parquet · C2c 의 1줄 파일만 tempdir). 운영 RAWDATA 는 읽기만(mmap = FALSE).
# 실행: Rscript 08_Tests/data/test_hygiene_flag_coverage.R   (마지막 줄 = JSON 요약 {"test":"hygiene_flag_coverage","pass":N,"fail":M,…})
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

.MARK <- "02_Infrastructure/hooks/qvest_hook_router.py"
## 절대 경로 — 경로 정규화 함수를 쓰지 않는다(프로젝트 R 규칙 · 한글 경로). 드라이브 문자 · UNC · ~ 는 그대로, 상대 경로만 작업 폴더에 붙인다.
.abs <- function(p) if (grepl("^([A-Za-z]:)?[/\\\\]", p) || grepl("^~", p)) p else file.path(getwd(), p)
.self_path <- function() {
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (!length(a)) return(NA_character_)
  f <- gsub("~+~", " ", sub("^--file=", "", a[1]), fixed = TRUE)      # Windows Rscript 는 경로의 공백을 ~+~ 로 넘긴다
  gsub("\\\\", "/", .abs(f))
}
SELF <- .self_path()
SELF_ROOT <- if (!is.na(SELF)) dirname(dirname(dirname(SELF))) else ""
## 앵커 순서(감사 가능한 한 줄): 자기 위치 → CLAUDE_PROJECT_DIR → QM_ROOT. 정규화(역슬래시 → /) 뒤 표지로 검증한다.
.qv_order <- c(SELF_ROOT, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))
ROOT <- NA_character_
for (.c in gsub("\\\\", "/", .qv_order)) if (nzchar(.c) && file.exists(file.path(.c, .MARK))) { ROOT <- .c; break }
if (!is.na(ROOT) && nzchar(SELF_ROOT) && !identical(ROOT, SELF_ROOT))
  message(sprintf("⚠ ANCHOR OVERRIDE — 자기 트리(%s)에 표지가 없어 %s 를 쓴다", SELF_ROOT, ROOT))
LIVE_MODE <- tolower(Sys.getenv("QVEST_HYG_COVERAGE_LIVE", "fail"))
if (!LIVE_MODE %in% c("fail", "warn", "off")) LIVE_MODE <- "fail"

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- character(0); WARN <- 0L
ok   <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng   <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (length(why) && nzchar(why[1])) paste0(" — ", why[1]) else "", "\n") }
chk  <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
skip <- function(axis, reason, missing = "") {
  SKIP <<- SKIP + 1L
  SKIPS <<- c(SKIPS, sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', axis, gsub('"', "'", reason), gsub("\\\\", "/", missing)))
  cat("  SKIP", axis, "—", reason, "\n")
}
## 소스 텍스트 치환(뮤테이션 · C1m 공용) — 대상 줄이 정확히 1개여야 하고 치환이 실제로 들어가야 한다(성사 단정)
mutate_once <- function(lines, pat, repl) {
  hit <- which(grepl(pat, lines, fixed = TRUE))
  if (length(hit) != 1L) stop(sprintf("치환 대상 줄 %d개(1개여야): %s", length(hit), pat))
  out <- lines; out[hit] <- sub(pat, repl, lines[hit], fixed = TRUE)
  if (identical(out, lines)) stop("치환이 적용되지 않았다: ", pat)
  out
}
load_scan <- function(lines) {
  env <- new.env(parent = globalenv())
  eval(parse(text = lines, keep.source = FALSE, encoding = "UTF-8"), envir = env)
  get("hyg_cov_scan", envir = env)
}

## <<SCAN-BEGIN>>
## hyg_cov_scan — 순수 함수(입력 표를 바꾸지 않는다). DT: Date · Ticker · Close + flags 열.
##   as_of 이후 행은 보지 않는다(항목 시작 · K · 첫 표식 · 상장일 모두 그날까지 알려진 이력만 — S12 가 잰다).
hyg_cov_scan <- function(DT, flags, as_of = NULL, since = NULL) {
  need <- c("Date", "Ticker", "Close", flags)
  miss <- setdiff(need, names(DT))
  if (length(miss)) stop("[hyg_cov_scan] missing columns: ", paste(miss, collapse = ","))
  X <- as.data.table(DT)[, need, with = FALSE]
  X[, Date := as.Date(Date)]
  X <- X[!is.na(Close)]
  if (!nrow(X)) stop("[hyg_cov_scan] no active rows")
  if (is.null(as_of)) as_of <- max(X$Date)
  as_of <- as.Date(as_of)
  X <- X[Date <= as_of]
  cal <- sort(unique(X$Date))
  calK <- if (is.null(since)) cal else cal[cal >= as.Date(since)]
  if (!length(calK)) calK <- cal
  ft <- X[, list(first_trade = min(Date)), by = Ticker]
  now <- X[Date == as_of]
  per_flag <- list(); det <- list()
  for (f in flags) {
    v <- X[[f]]
    ## 항목 시작 = 기준일까지 그 항목 값이 처음 나온 날(한 번도 없으면 NA = 항목 이력 전 · 구조적)
    item_start <- if (any(!is.na(v))) min(X$Date[!is.na(v)]) else as.Date(NA)
    cover_now <- if (nrow(now)) mean(!is.na(now[[f]])) else 0
    ff <- if (any(!is.na(v))) X[!is.na(X[[f]]), list(first_flag = min(Date)), by = Ticker] else data.table(Ticker = character(0), first_flag = as.Date(character(0)))
    g <- merge(ft, ff, by = "Ticker")
    lo <- if (is.na(item_start)) as.Date(NA) else if (is.null(since)) item_start else max(item_start, as.Date(since))
    g <- if (is.na(lo)) g[0] else g[first_trade >= lo & first_flag >= first_trade]
    g[, gap := findInterval(first_flag, cal) - findInterval(first_trade, cal)]
    ## 구조적 유예 창 = 한 달 거래일 수의 최댓값(월간 스냅숏 — 상장한 달 월말까지) · 관측 분위를 쓰지 않는다(과거 결손 꼬리 오염)
    K <- max(table(format(calK, "%Y-%m")))
    n <- now[is.na(now[[f]]), list(Ticker)]
    n <- merge(n, ft, by = "Ticker")
    n[, td := findInterval(as_of, cal) - findInterval(first_trade, cal)]
    ## 항목 전 ⇔ 기준일까지 그 항목 값이 한 번도 없음. ★기준일 커버리지 0(이력 뒤 전면 결손)은 항목 전이 아니라 gap 이다(S11).
    n[, kind := fifelse(rep(is.na(item_start), .N), "item_uncovered", fifelse(td <= K, "grace", "gap"))]
    n[, flag := f]
    det[[f]] <- n
    per_flag[[f]] <- list(item_start = item_start, cover_now = cover_now, K = K,
                          whole_drop = !is.na(item_start) && nrow(now) > 0L && cover_now == 0,
                          gap_max = if (nrow(g)) max(g$gap) else NA_real_,
                          n_listings = nrow(g), n_exceed = sum(g$gap > K),
                          exceed_top = if (nrow(g)) head(g[gap > K][order(-gap)], 3L) else g,
                          n_na = nrow(n), n_gap = sum(n$kind == "gap"),
                          n_grace = sum(n$kind == "grace"), n_item = sum(n$kind == "item_uncovered"))
  }
  D <- rbindlist(det, use.names = TRUE, fill = TRUE)
  gt <- if (nrow(D)) sort(unique(D[kind == "gap"]$Ticker)) else character(0)
  list(as_of = as_of, n_active = nrow(now), flags = per_flag, detail = D, gap_tickers = gt, n_gap = length(gt))
}
## <<SCAN-END>>

#------------------------------------------------------------------------------
# 합성 자료 — 300 거래일(주말 제외). 상장 이력 241종(간격 1~15 + 바깥값 200) + 시험 대상 7종.
#   UnfaithfulDisc 항목은 100번째 거래일부터 존재(그 전 = 항목 이력 전 · 전 종목 NA) · 도입기 지연:
#   100~129번째 날 상장분은 160번째 날에야 첫 값(항목 도입기 — K 를 부풀리면 안 된다).
#   유예 경계 종목: T_EDGE_K = 상장 정확히 K 거래일(경계 안쪽 · 양성 대조에도 든다) · T_EDGE_K1 = K+1 거래일(경계 바깥 한 칸).
#------------------------------------------------------------------------------
FL <- c("AdminStock", "TradingHalt", "UnfaithfulDisc")
mk_cal <- function(n) { d <- seq(as.Date("2021-01-04"), by = "day", length.out = n * 2); d <- d[!(as.POSIXlt(d)$wday %in% c(0L, 6L))]; d[seq_len(n)] }
N_DAYS <- 300L; UNF_START <- 100L; RAMP_FROM <- 100L; RAMP_TO <- 130L; RAMP_FIRST <- 160L
## 합성 달력의 구조적 유예 창(기대값 — S8 · S10 잣대와 같은 정의) · 경계 종목 상장일을 이 값으로 놓는다
K_SYN <- max(table(format(mk_cal(N_DAYS), "%Y-%m")))
EXPECT_GAP <- c("T_EDGE_K1", "T_GAP", "T_HALT")    # 위반 주입(전 자료) 경보 대상 — S9 · L0b
mk_syn <- function(with_gap = TRUE, with_halt = TRUE, with_edge = TRUE) {
  cal <- mk_cal(N_DAYS)
  one <- function(tk, L, g, close_na_from = NA_integer_, halt_na_last = 0L, never = FALSE) {
    idx <- L:N_DAYS
    fl_on <- if (never) rep(FALSE, length(idx)) else idx >= L + g
    unf_from <- if (L >= RAMP_FROM && L < RAMP_TO) RAMP_FIRST else UNF_START
    x <- data.table(Date = cal[idx], Ticker = tk, Close = 1000, Vol = 1e6,
                    AdminStock = fifelse(fl_on, 0, NA_real_), TradingHalt = fifelse(fl_on, 0, NA_real_),
                    UnfaithfulDisc = fifelse(fl_on & idx >= unf_from, 0, NA_real_))
    if (!is.na(close_na_from)) x[idx >= close_na_from, `:=`(Close = NA_real_, AdminStock = NA_real_, TradingHalt = NA_real_, UnfaithfulDisc = NA_real_)]
    if (halt_na_last > 0L) x[idx > N_DAYS - halt_na_last, TradingHalt := NA_real_]
    x
  }
  L <- list()
  for (k in 1:240) L[[length(L) + 1L]] <- one(sprintf("H%03d", k), k + 1L, 1L + (k %% 15L))
  L[[length(L) + 1L]] <- one("H241", 5L, 200L)                       # 과거 결손형 바깥값(200 거래일) — K 를 부풀리면 안 된다
  L[[length(L) + 1L]] <- one("T_OLD", 1L, 0L)
  L[[length(L) + 1L]] <- one("T_GRACE", N_DAYS - 5L, 0L, never = TRUE)   # 상장 5 거래일 · 표식 아직 없음 = 구조적
  L[[length(L) + 1L]] <- one("T_EDGE_K", N_DAYS - K_SYN, 0L, never = TRUE)   # 상장 정확히 K 거래일(td = K) · 표식 없음 = grace
  L[[length(L) + 1L]] <- one("T_DEAD", 1L, 0L, close_na_from = 201L)      # 201일째부터 거래 없음(행은 남음) = 비활성
  if (with_gap)  L[[length(L) + 1L]] <- one("T_GAP", 50L, 0L, never = TRUE)  # 250 거래일째 표식 없음 = DATA_Key 결손형
  if (with_halt) L[[length(L) + 1L]] <- one("T_HALT", 1L, 0L, halt_na_last = 3L)  # 거래정지 표식만 최근 3일 결손
  if (with_edge) L[[length(L) + 1L]] <- one("T_EDGE_K1", N_DAYS - K_SYN - 1L, 0L, never = TRUE)  # 상장 K+1 거래일(td = K+1) = gap
  rbindlist(L)
}

## 자기 시험 — scan 함수를 받아 S1~S13 을 논리 벡터로 돌려준다(뮤테이션 사본에도 같은 잣대). 오류는 attr(, "error") 로 싣는다.
selftests <- function(scan) {
  r <- setNames(rep(FALSE, 13L), paste0("S", 1:13))
  tryCatch({
    clean <- mk_syn(with_gap = FALSE, with_halt = FALSE, with_edge = FALSE)
    s1 <- scan(clean, FL)
    r["S1"] <- identical(s1$n_gap, 0L)                                              # 양성 대조: 결손 없음(경계 안쪽 T_EDGE_K 포함) → 경보 0
    full <- mk_syn()
    snap <- copy(full)
    s2 <- scan(full, FL)
    r["S2"] <- "T_GAP" %in% s2$gap_tickers && all(c("AdminStock", "TradingHalt", "UnfaithfulDisc") %in% s2$detail[Ticker == "T_GAP" & kind == "gap"]$flag)
    r["S3"] <- "T_HALT" %in% s2$gap_tickers && identical(sort(unique(s2$detail[Ticker == "T_HALT"]$flag)), "TradingHalt")
    r["S4"] <- !("T_GRACE" %in% s2$gap_tickers) && nrow(s2$detail[Ticker == "T_GRACE"]) == 3L && all(s2$detail[Ticker == "T_GRACE"]$kind == "grace")
    r["S5"] <- !("T_DEAD" %in% s2$detail$Ticker)                                    # 비활성(거래 없음) 종목은 보지 않는다
    s6 <- scan(full, FL, as_of = mk_cal(N_DAYS)[80L])                               # 불성실공시 항목 이력 전(기준일까지 값 0개)
    u6 <- s6$detail[flag == "UnfaithfulDisc"]
    r["S6"] <- nrow(u6) > 0L && all(u6$kind == "item_uncovered") && !any(s6$detail[kind == "gap"]$flag == "UnfaithfulDisc")
    r["S7"] <- identical(full, snap)                                                # 순수성: 입력 표 불변
    k_cal <- max(table(format(mk_cal(N_DAYS), "%Y-%m")))                         # 기대 K = 합성 달력의 한 달 거래일 수 최대
    pa <- s2$flags$AdminStock
    r["S8"] <- isTRUE(all.equal(pa$K, k_cal)) && isTRUE(all.equal(pa$gap_max, 200)) && identical(pa$n_exceed, 1L)   # 바깥값(H241)은 K 를 못 바꾸고 n_exceed 로만 보고
    r["S9"] <- identical(s2$n_gap, length(EXPECT_GAP)) && setequal(s2$gap_tickers, EXPECT_GAP)   # 경보 대상 정확히 셋
    pu <- s2$flags$UnfaithfulDisc
    r["S10"] <- isTRUE(all.equal(pu$K, k_cal)) && identical(pu$n_exceed, as.integer(RAMP_TO - RAMP_FROM))   # 도입기 지연(31~60일) 30종도 K 를 못 바꾼다
    ## S11 — 항목 이력 뒤 기준일 전면 결손: 관리종목 표식을 그날 전 종목 NA 로(적재 · 조인 실패 흉내) → 유예 안 2종만 빼고 전부 gap
    drop <- copy(clean); drop[Date == max(Date), AdminStock := NA_real_]
    s11 <- scan(drop, FL); p11 <- s11$flags$AdminStock
    exp11 <- setdiff(unique(clean[Date == max(Date) & !is.na(Close)]$Ticker), c("T_GRACE", "T_EDGE_K"))
    r["S11"] <- identical(p11$n_item, 0L) && isTRUE(p11$whole_drop) && setequal(s11$gap_tickers, exp11) &&
                all(s11$detail[kind == "gap"]$flag == "AdminStock")
    ## S12 — as_of 이후 행을 보지 않는다: '전 자료 + as_of' 와 '그날까지 자른 자료' 의 결과가 같아야 한다(항목 이력 전 · 도입기 두 날)
    cal0 <- mk_cal(N_DAYS)
    keyed <- function(s) list(n_gap = s$n_gap, gap = s$gap_tickers, n_active = s$n_active,
                              detail = if (nrow(s$detail)) s$detail[order(flag, Ticker)] else s$detail,
                              flags = lapply(s$flags, function(p) p[setdiff(names(p), "exceed_top")]))
    r["S12"] <- all(vapply(c(80L, 150L), function(i) {
      d <- cal0[i]
      isTRUE(all.equal(keyed(scan(full, FL, as_of = d)), keyed(scan(full[Date <= d], FL, as_of = d)), check.attributes = FALSE))
    }, logical(1)))
    ## S13 — 유예 경계: 상장 K 거래일 = grace · K+1 = gap(표식 셋 모두) + td 값 자체
    e <- s2$detail[Ticker %in% c("T_EDGE_K", "T_EDGE_K1")]
    r["S13"] <- nrow(e) == 6L && all(e[Ticker == "T_EDGE_K"]$kind == "grace") && all(e[Ticker == "T_EDGE_K1"]$kind == "gap") &&
                all(e[Ticker == "T_EDGE_K"]$td == K_SYN) && all(e[Ticker == "T_EDGE_K1"]$td == K_SYN + 1L)
    r
  }, error = function(e) { attr(r, "error") <- conditionMessage(e); r })
}

cat("[test_hygiene_flag_coverage] ROOT =", ROOT, "· SELF =", SELF, "· live mode =", LIVE_MODE, "\n")

#------------------------------------------------------------------------------
# S — 자기 시험(원본 함수)
#------------------------------------------------------------------------------
cat("\n[S] 자기 시험(합성)\n")
DESC <- c(S1 = "S1 양성 대조 — 결손 없는 자료(유예 경계 안쪽 T_EDGE_K 포함) → 경보 0",
          S2 = "S2 위반 주입 — 표식 셋 다 없는 활성 종목(상장 250 거래일) → 경보",
          S3 = "S3 위반 주입 — 거래정지 표식 하나만 결손 → 그 표식만 경보",
          S4 = "S4 구조적 — 상장 5 거래일(K 이내) → grace · 경보 아님",
          S5 = "S5 비활성 — 거래 없는 날의 NA 는 보지 않는다",
          S6 = "S6 구조적 — 기준일까지 항목 값이 한 번도 없음(불성실공시 이력 전) → item_uncovered · 경보 아님",
          S7 = "S7 순수성 — 입력 표 불변(판정 입력을 건드리지 않는다)",
          S8 = "S8 K = 달력의 한 달 거래일 수 최대 — 과거 결손형 바깥값(200 거래일)은 K 를 못 바꾸고 n_exceed=1 로만 보고",
          S9 = "S9 경보 대상 정확히 셋(T_GAP · T_HALT · T_EDGE_K1)",
          S10 = "S10 K = 달력 상한 — 항목 도입기 지연 30종(31~60 거래일)도 K 를 못 바꾸고 n_exceed=30 으로 보고",
          S11 = "S11 위반 주입 — 항목 이력 뒤 기준일 전면 결손(관리종목 표식 전 종목 NA) → 유예 안 2종 빼고 전부 gap · item_uncovered 0",
          S12 = "S12 as_of 이후 행을 보지 않는다 — 80 · 150 거래일 기준 '전 자료 + as_of' = '그날까지 자른 자료'",
          S13 = sprintf("S13 유예 경계 — 상장 K(=%d) 거래일 = grace · K+1 = gap(td 값까지 단언)", K_SYN))
st <- selftests(hyg_cov_scan)
if (!is.null(attr(st, "error"))) cat("  (자기 시험 오류:", attr(st, "error"), ")\n")
for (k in names(DESC)) chk(isTRUE(st[[k]]), DESC[[k]])

#------------------------------------------------------------------------------
# C — 계약 전제 · 판정 불변(실측 — 실패할 수 있는 단언 + 그 실패 가능성의 통제)
#------------------------------------------------------------------------------
cat("\n[C] 계약 전제 · 판정 불변\n")
FZ <- if (!is.na(ROOT)) file.path(ROOT, "02_Infrastructure", "factor_db", "factor_z_standard.R") else NA_character_
MA <- if (!is.na(ROOT)) file.path(ROOT, "02_Infrastructure", "contracts", "measurement_axis.R") else NA_character_
fp_of <- function(p) if (!is.na(p) && file.exists(p)) unname(tools::md5sum(p)) else NA_character_
FP0 <- c(FZ = fp_of(FZ), MA = fp_of(MA))                        # 시작 지문 — 끝(C2)에서 다시 잰다
CE <- new.env(parent = globalenv())
contract_ok <- FALSE
if (!is.na(FZ) && file.exists(FZ) && file.exists(MA)) {
  contract_ok <- tryCatch({
    invisible(capture.output(sys.source(FZ, envir = CE, keep.source = FALSE)))
    invisible(capture.output(sys.source(MA, envir = CE, keep.source = FALSE)))
    TRUE
  }, error = function(e) { cat("  (계약 판독 오류:", conditionMessage(e), ")\n"); FALSE })
}
## 전제 탐침 — 행: 표식 전부 NA · 전부 0 · 관리 1 · 정지 1 · 유동성 결측 · 유동성 미달(하한 2e8 은 탐침 인자일 뿐 — 운영 하한은 epoch 설정)
premise_probe <- function(fun) tryCatch(fun(c(3e8, 3e8, 3e8, 3e8, NA, 1e8), c(NA, 0, 1, NA, 0, 0), c(NA, 0, 0, 1, 0, 0), c(NA, 0, 0, 0, 0, 0), 2e8),
                                        error = function(e) NULL)
PREMISE <- c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE)   # 표식 NA = 통과(이 감시가 경보하는 이유) · 0 통과 · ≠0 탈락 · 유동성 결측 · 미달 탈락
if (contract_ok) {
  v0 <- premise_probe(CE$corp_action_member)
  chk(identical(v0, PREMISE), "C1 전제 실측 — 현행 판정식: 표식 NA = 통과 · 0 = 통과 · ≠0 = 탈락 · 유동성 결측 · 미달 = 탈락",
      sprintf("판정 결과 %s — 판정 의미가 바뀌었다(도훈 결정 · 새 epoch 이면 이 감시의 경보 의미와 이 단언을 함께 고친다)",
              if (is.null(v0)) "판독 불가" else paste(v0, collapse = ",")))
  fz_l <- sub("\r$", "", readLines(FZ, warn = FALSE, encoding = "UTF-8"))
  mz <- tryCatch(mutate_once(fz_l, "(is.na(AdminStock) | AdminStock == 0) &", "(!is.na(AdminStock) & AdminStock == 0) &"), error = function(e) e)
  if (inherits(mz, "error")) {
    ng("C1m 통제 — 판정식 사본 치환", conditionMessage(mz))
  } else {
    ME <- new.env(parent = globalenv())
    vm <- tryCatch({
      invisible(capture.output(eval(parse(text = mz, keep.source = FALSE, encoding = "UTF-8"), envir = ME)))
      premise_probe(ME$corp_action_member)
    }, error = function(e) NULL)
    chk(!is.null(vm) && !identical(vm, PREMISE) && identical(vm[1], FALSE),
        "C1m 통제 — 'NA = 탈락'으로 치환한 판정식 사본(소스 텍스트)에서 C1 잣대가 red(C1 은 실패할 수 있다)",
        if (is.null(vm)) "사본 실행 오류 — 통제로 세지 않는다" else sprintf("사본 결과 %s", paste(vm, collapse = ",")))
  }
  cat(sprintf("  INFO 현행 판정 의미 — 표식 NA 행: %s (TRUE = 정상 통과 · 판정 의미 변경은 도훈 결정 사항)\n",
              if (is.null(v0)) "판독 불가" else v0[1]))
} else skip("C1_contract", "위생 판정식 · 측정 축 계약 파일 부재/판독 실패 — 전제 실측 불가", if (is.na(FZ)) "ROOT" else FZ)

#------------------------------------------------------------------------------
# M — 뮤테이션 테스트(이 파일 SCAN 블록 소스 텍스트 치환 · 치환 성사 단정 · 각 사본이 기대 판정에서 red)
#------------------------------------------------------------------------------
cat("\n[M] 뮤테이션 테스트\n")
scan_block <- NULL
if (!is.na(SELF) && file.exists(SELF)) {
  L <- sub("\r$", "", readLines(SELF, warn = FALSE, encoding = "UTF-8"))
  b <- which(L == "## <<SCAN-BEGIN>>"); e <- which(L == "## <<SCAN-END>>")
  if (length(b) == 1L && length(e) == 1L && e > b) scan_block <- L[(b + 1L):(e - 1L)]
}
if (is.null(scan_block)) {
  skip("M_mutation", "자기 소스(--file=) 판독 불가 — 뮤테이션 테스트 미실행", if (is.na(SELF)) "--file" else SELF)
} else {
  ctl <- tryCatch(selftests(load_scan(scan_block)), error = function(e) e)
  ctl_err <- if (inherits(ctl, "error")) conditionMessage(ctl) else attr(ctl, "error")
  chk(is.null(ctl_err) && all(ctl), "M0 통제 — 추출한 원본 SCAN 블록 사본은 자기 시험 전부 green(추출 · 평가 기계 생존)",
      if (!is.null(ctl_err)) ctl_err else paste(names(ctl)[!ctl], collapse = ","))
  TD_LINE <- "n[, td := findInterval(as_of, cal) - findInterval(first_trade, cal)]"
  MUT <- list(
    list(id = "M1 구조적 유예 삭제(td <= K → td < 0)", red = c("S1", "S4", "S13"), pat = "fifelse(td <= K,", repl = "fifelse(td < 0,"),
    list(id = "M2 항목 이력 판정 삭제", red = c("S6"), pat = "rep(is.na(item_start), .N)", repl = "rep(FALSE, .N)"),
    list(id = "M3 활성 필터 삭제", red = c("S5"), pat = "X <- X[!is.na(Close)]", repl = "X <- X[TRUE]"),
    list(id = "M4 NA 검출 무력화", red = c("S2", "S3"), pat = "n <- now[is.na(now[[f]]), list(Ticker)]", repl = "n <- now[FALSE, list(Ticker)]"),
    list(id = "M5 유예 무한(K = Inf)", red = c("S2", "S3", "S13"), pat = "K <- max(table(format(calK, \"%Y-%m\")))", repl = "K <- Inf"),
    list(id = "M6 K = 관측 p99(결손 꼬리 오염 — 2026-11-06 실측 불성실공시 129 의 재현)", red = c("S8", "S10"),
         pat = "K <- max(table(format(calK, \"%Y-%m\")))", repl = "K <- as.numeric(quantile(g$gap, 0.99, type = 1, names = FALSE))"),
    list(id = "M7 1차 판 판정 복원(기준일 커버리지 0 = 항목 전 — 전면 결손 은폐 · 2차 검증 지적)", red = c("S11"),
         pat = "rep(is.na(item_start), .N)", repl = "rep(cover_now == 0, .N)"),
    list(id = "M8 as_of 절단 삭제(검증 지적 ⓑ 그대로)", red = c("S6", "S12"), pat = "X <- X[Date <= as_of]", repl = "X <- X[Date <= max(Date)]"),
    list(id = "M9 유예 창 약 3배(td %/% 3 — 검증 지적 ⓐ)", red = c("S9", "S13"), pat = TD_LINE,
         repl = "n[, td := (findInterval(as_of, cal) - findInterval(first_trade, cal)) %/% 3L]"),
    list(id = "M10 유예 창 약 10배(td %/% 10 — 검증 지적 ⓐ)", red = c("S9", "S13"), pat = TD_LINE,
         repl = "n[, td := (findInterval(as_of, cal) - findInterval(first_trade, cal)) %/% 10L]"),
    list(id = "M11 경계 안쪽 한 칸(td <= K → td < K)", red = c("S1", "S13"), pat = "fifelse(td <= K,", repl = "fifelse(td < K,"),
    list(id = "M12 경계 바깥 한 칸(td <= K → td <= K + 1)", red = c("S9", "S13"), pat = "fifelse(td <= K,", repl = "fifelse(td <= K + 1L,")
  )
  for (m in MUT) {
    ml <- tryCatch(mutate_once(scan_block, m$pat, m$repl), error = function(e) e)
    if (inherits(ml, "error")) { ng(m$id, paste("치환 실패:", conditionMessage(ml))); next }
    mr <- tryCatch(selftests(load_scan(ml)), error = function(e) e)
    if (inherits(mr, "error")) { ng(m$id, paste("사본 실행 오류:", conditionMessage(mr))); next }
    if (!is.null(attr(mr, "error"))) { ng(m$id, paste("사본이 자기 시험 도중 오류로 죽었다(검거로 세지 않는다):", attr(mr, "error"))); next }
    still_green <- m$red[mr[m$red]]
    chk(!length(still_green), sprintf("%s → red: %s", m$id, paste(m$red, collapse = ",")),
        sprintf("green 으로 남은 판정: %s", paste(still_green, collapse = ",")))
  }
}

#------------------------------------------------------------------------------
# live — 판독 경로(read → scan → 계약 멤버십)
#------------------------------------------------------------------------------
live_scan <- function(raw_path, ep) {
  flags <- as.character(ep$excluded_flags)
  sch <- names(arrow::open_dataset(raw_path)$schema)
  idx <- intersect(c("K200", "KQ150"), sch)
  cols <- unique(c("Date", "Ticker", "Close", "Vol", flags, idx))
  if (length(setdiff(cols, sch))) stop("RAWDATA 열 부족: ", paste(setdiff(cols, sch), collapse = ","))
  DT <- as.data.table(arrow::read_parquet(raw_path, col_select = tidyselect::all_of(cols), mmap = FALSE))
  DT[, Date := as.Date(Date)]
  sc <- hyg_cov_scan(DT, flags, since = ep$start_date)
  adm <- 0L
  if (sc$n_gap) {
    X <- DT[Ticker %in% sc$gap_tickers]; setorder(X, Ticker, Date)
    X[, .mem := CE$ma_membership(X, ep)]
    adm <- X[Date == sc$as_of & .mem == TRUE, uniqueN(Ticker)]
  }
  si <- if (length(idx)) hyg_cov_scan(DT, idx, since = ep$start_date) else NULL
  rm(DT); invisible(gc())
  list(sc = sc, admitted = adm, idx = si)
}
whole_drop_flags <- function(sc) names(Filter(function(p) isTRUE(p$whole_drop), sc$flags))

cat("\n[L0] live 경로 연기 시험(합성 parquet · 양방향 + 전면 결손)\n")
EP <- NULL
if (contract_ok) EP <- tryCatch(CE$ma_epoch(NULL, ROOT), error = function(e) { cat("  (epoch 판독 오류:", conditionMessage(e), ")\n"); NULL })
if (is.null(EP) || !isTRUE(EP$hygiene)) {
  skip("L0_live_path", "측정 축 계약(위생 epoch) 판독 불가 — live 경로 미검증", if (is.na(MA)) "ROOT" else MA)
} else {
  tdir <- tempfile("hygcov_"); dir.create(tdir)
  p_clean <- file.path(tdir, "clean.parquet"); p_bad <- file.path(tdir, "bad.parquet"); p_drop <- file.path(tdir, "drop.parquet")
  syn <- function(...) { x <- mk_syn(...); x[, `:=`(K200 = 0, KQ150 = 0)]; x }
  arrow::write_parquet(syn(with_gap = FALSE, with_halt = FALSE, with_edge = FALSE), p_clean)
  arrow::write_parquet(syn(), p_bad)
  dr <- syn(with_gap = FALSE, with_halt = FALSE, with_edge = FALSE); dr[Date == max(Date), AdminStock := NA_real_]
  arrow::write_parquet(dr, p_drop)
  ep0 <- EP; ep0$start_date <- min(mk_cal(N_DAYS))
  a  <- tryCatch(live_scan(p_clean, ep0), error = function(e) e)
  b  <- tryCatch(live_scan(p_bad, ep0), error = function(e) e)
  cc <- tryCatch(live_scan(p_drop, ep0), error = function(e) e)
  chk(!inherits(a, "error") && identical(a$sc$n_gap, 0L), "L0a live 경로 양성 대조 — 결손 없는 parquet → 경보 0",
      if (inherits(a, "error")) conditionMessage(a) else sprintf("n_gap=%s", a$sc$n_gap))
  chk(!inherits(b, "error") && setequal(b$sc$gap_tickers, EXPECT_GAP) && b$admitted >= 1L,
      "L0b live 경로 위반 주입 — 결손 3종 경보 + 계약 멤버십이 그중 멤버를 센다(NA = 정상 통과의 실측)",
      if (inherits(b, "error")) conditionMessage(b) else sprintf("gap=%s admitted=%s", paste(b$sc$gap_tickers, collapse = ","), b$admitted))
  chk(!inherits(cc, "error") && "T_OLD" %in% cc$sc$gap_tickers && identical(whole_drop_flags(cc$sc), "AdminStock") && cc$admitted >= 1L,
      "L0c live 경로 위반 주입 — 이력 뒤 기준일 전면 결손(관리종목 표식 전 종목 NA) → 경보 + 전면 결손 표시 + 그중 멤버를 센다",
      if (inherits(cc, "error")) conditionMessage(cc) else sprintf("gap=%d whole_drop=%s admitted=%s", cc$sc$n_gap,
                                                                  paste(whole_drop_flags(cc$sc), collapse = ","), cc$admitted))
  unlink(tdir, recursive = TRUE)
}

cat("\n[L1] live — 운영 RAWDATA(읽기 전용)\n")
LIVE <- list(gap = NA_integer_, admitted = NA_integer_, idx_gap = NA_integer_, stale = NA_integer_, as_of = NA_character_, whole_drop = NA_integer_)
RAW <- Sys.getenv("QVEST_HYG_RAWDATA", if (!is.na(ROOT)) file.path(ROOT, ".cache", "RAWDATA.parquet") else "")
if (LIVE_MODE == "off") {
  skip("L1_live", "QVEST_HYG_COVERAGE_LIVE=off", "")
} else if (!nzchar(RAW) || !file.exists(RAW)) {
  skip("L1_live", "RAWDATA 부재(클론 · 데이터 없는 환경) — 판정 없음", RAW)
} else if (is.null(EP) || !isTRUE(EP$hygiene)) {
  skip("L1_live", "측정 축 계약 판독 불가 — 위생 표식 목록을 지어내지 않는다", if (is.na(MA)) "ROOT" else MA)
} else {
  lv <- tryCatch(live_scan(RAW, EP), error = function(e) e)
  if (inherits(lv, "error")) {
    ng("L1 live 판독", conditionMessage(lv))
  } else {
    sc <- lv$sc
    wd <- whole_drop_flags(sc)
    LIVE$gap <- sc$n_gap; LIVE$admitted <- lv$admitted; LIVE$as_of <- format(sc$as_of); LIVE$whole_drop <- length(wd)
    for (f in names(sc$flags)) {
      pf <- sc$flags[[f]]
      cat(sprintf("  %s: 커버리지 %.4f · 항목 시작 %s · K(달력 상한)=%g · 과거 상장 %d 중 K 초과 %d(최대 %g — 지난 결손 흔적: %s) · NA %d = gap %d + grace %d + 항목전 %d%s\n",
                  f, pf$cover_now, format(pf$item_start), pf$K, pf$n_listings, pf$n_exceed, pf$gap_max,
                  if (nrow(pf$exceed_top)) paste(sprintf("%s %s→%s", pf$exceed_top$Ticker, format(pf$exceed_top$first_trade), format(pf$exceed_top$first_flag)), collapse = ", ") else "-",
                  pf$n_na, pf$n_gap, pf$n_grace, pf$n_item,
                  if (isTRUE(pf$whole_drop)) " · ★전면 결손(항목 이력 뒤 기준일 커버리지 0 — 위생이 전 종목에서 꺼졌다 · 적재 · 조인 실패 의심)" else ""))
    }
    if (sc$n_gap) {
      gd <- unique(sc$detail[kind == "gap", list(Ticker, first_trade, td)])[order(first_trade)]
      cat(sprintf("  gap 종목 %d (그중 지금 측정 축 멤버 %d) — 앞 10: %s\n", sc$n_gap, lv$admitted,
                  paste(sprintf("%s(%s·%d거래일)", gd$Ticker, format(gd$first_trade), gd$td)[seq_len(min(10L, nrow(gd)))], collapse = " ")))
    }
    if (!is.null(lv$idx)) {
      LIVE$idx_gap <- lv$idx$n_gap
      cat(sprintf("  INFO 지수 표식(K200 · KQ150) gap %d — BOOK_0001(K200∪KQ150) 후보에서 빠진다(계상 안 함)\n", lv$idx$n_gap))
    }
    UA <- Sys.getenv("QVEST_HYG_US_ADMIN", if (!is.na(ROOT)) file.path(ROOT, ".cache", "universe_support", "us_admin_stock.parquet") else "")
    if (nzchar(UA) && file.exists(UA)) {
      ua <- as.data.table(arrow::read_parquet(UA, mmap = FALSE)); ua[, Date := as.Date(Date)]
      dlast <- max(ua$Date)
      act <- unique(as.data.table(arrow::read_parquet(RAW, col_select = tidyselect::all_of(c("Date", "Ticker", "Close")), mmap = FALSE))[as.Date(Date) == dlast & !is.na(Close)]$Ticker)
      stl <- setdiff(setdiff(act, ua[Date == dlast]$Ticker), sc$gap_tickers)
      LIVE$stale <- length(stl)
      cat(sprintf("  INFO 최신 스냅숏(%s)에 없는 활성 종목 중 gap 밖 %d — 표식이 이전 스냅숏 값으로 이월된다(낡은 표식 · 계상 안 함)%s\n",
                  dlast, length(stl), if (length(stl)) paste0(": ", paste(head(stl, 10), collapse = " ")) else ""))
    }
    msg <- sprintf("L1 live — 활성 종목 위생 표식 gap 0 (as_of %s · 활성 %d)", sc$as_of, sc$n_active)
    why <- sprintf("gap %d종(지금 측정 축 멤버 %d)%s — 위생 판정이 NA 를 정상으로 통과시킨다 · %s", sc$n_gap, lv$admitted,
                   if (length(wd)) paste0(" · ★전면 결손 표식 ", paste(wd, collapse = ",")) else "",
                   if (length(wd)) "표식 적재 · RAWDATA 조인([0b] · [3] apply_universe_mapping)부터 확인" else
                     "DATA_Key 동기화 + 이력 보충 필요(PLAN §3.0 F7 · §5.2 ⑦)")
    if (LIVE_MODE == "fail") chk(sc$n_gap == 0L, msg, why)
    else if (sc$n_gap > 0L) { WARN <- WARN + 1L; cat("  [ALARM]", why, "\n") } else cat("  OK  ", msg, "(warn 모드 · 계상 안 함)\n")
  }
}

#------------------------------------------------------------------------------
# C2 — 판정 불변 실측(이 실행 전후 계약 파일 지문) + 비교기 생존 통제
#------------------------------------------------------------------------------
cat("\n[C2] 판정 불변(이 실행 전후)\n")
if (contract_ok) {
  FP1 <- c(FZ = fp_of(FZ), MA = fp_of(MA))
  chk(!anyNA(FP0) && identical(FP0, FP1),
      "C2 판정 불변 실측 — 실행 전후 계약 파일(factor_z_standard.R · measurement_axis.R) 내용 지문(md5) 동일",
      sprintf("전 %s · 후 %s", paste(FP0, collapse = "/"), paste(FP1, collapse = "/")))
  tf <- tempfile("hygfp_"); writeLines("a", tf); h0 <- fp_of(tf); writeLines("b", tf); h1 <- fp_of(tf); unlink(tf)
  chk(!is.na(h0) && !is.na(h1) && !identical(h0, h1), "C2c 통제 — 같은 지문 비교가 1바이트 바뀐 임시 파일을 '다름'으로 잰다(비교기 생존)")
} else skip("C2_contract", "계약 파일 부재/판독 실패 — 지문 비교 불가", if (is.na(FZ)) "ROOT" else FZ)

cat(sprintf("\n[test_hygiene_flag_coverage] PASS: %d  FAIL: %d  SKIP: %d  WARN: %d\n", PASS, FAIL, SKIP, WARN))
js <- sprintf('{"test":"hygiene_flag_coverage","pass":%d,"fail":%d,"total":%d,"skipped":%d,"skips":[%s],"warn":%d,"live_mode":"%s","live_as_of":%s,"live_gap":%s,"live_admitted":%s,"live_whole_drop":%s,"live_index_gap":%s,"live_stale_carry":%s}',
              PASS, FAIL, PASS + FAIL, SKIP, paste(SKIPS, collapse = ","), WARN, LIVE_MODE,
              if (is.na(LIVE$as_of)) "null" else sprintf('"%s"', LIVE$as_of),
              if (is.na(LIVE$gap)) "null" else LIVE$gap, if (is.na(LIVE$admitted)) "null" else LIVE$admitted,
              if (is.na(LIVE$whole_drop)) "null" else LIVE$whole_drop,
              if (is.na(LIVE$idx_gap)) "null" else LIVE$idx_gap, if (is.na(LIVE$stale)) "null" else LIVE$stale)
cat(js, "\n", sep = "")
quit(status = if (FAIL == 0L) 0L else 1L)
