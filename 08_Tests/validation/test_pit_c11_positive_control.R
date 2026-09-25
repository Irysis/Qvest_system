# test_pit_c11_positive_control.R — PIT C11 방어선(S6_defense) 양방향 검사 (2026-09-24 신설)
#
# 지키는 것: 판정서 ⑤-8 "방어선" — ① lookahead_detector.R 의 C3 macro/regime 단어 면제 삭제 + C11 계보 분석기
#   ② pit_verify_fred_lag 실구현(무조건 TRUE → 규칙 파일 대조) ③ ast_verify.py 선언 맹신(:360-361) → 규칙 파일·격리 대조
#   ④ ast_field_map E4 선언 정정. 근거 = 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md ③·⑤-8,
#   decision_register PIT-C11-CONVENTIONS ④. 규칙 정본 = 06_Registry/fred_availability_rules.json(S0).
#
# ★양방향(pit.md: 양성 대조 없는 계기는 방어선으로 세지 않는다):
#   - 위반 주입 → red 19종: 같은 날짜 결합·판정서 돌연변이 2종(flagword·paste0 간접 경로)·그 밖 변형·가용일 열 이름 흉내·파이썬
#   - 올바른 lag → 오탐 0(14종): 판정서 음성 픽스처·일간 계열 임시 lag·가용시점 층·어댑터·가용일 열·메시지 문자열
#     + 레거시 '안전' 분류 + 1계층 엔진 전수
#   - 판정서가 지목한 거짓 양성 2파일(compute_regime·regime_engine_daily): git 고정 원판에서 종전 발화 줄(읽기 줄)
#     무발화 · 발화는 판정서가 확정한 결함 줄(V-01 :77 · V-11 :419)에만 · 결함 줄을 가용시점 층으로 바꾼 판 = 무발화
#   - 계기 돌연변이 → red: 검출기 9종 · pit_verify_fred_lag 구판 · ast_verify 4종
#
# 축: A 위반 주입 · B 음성 대조 · C 고정 원판(git 7ea5d8377) · D 레거시·엔진 회귀(읽기 전용) · E C3 면제 삭제
#     · F 검출기 돌연변이 · G pit_verify_fred_lag · H ast_verify(파이썬 하위 프로세스)
# 쓰기: tempdir() 만. 운영 .cache·원장·로그·레지스트리에 쓰지 않는다.
# 실행: Rscript 08_Tests/validation/test_pit_c11_positive_control.R   (R_ENVIRON_USER=<빈 파일> 권장)

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.self <- tryCatch({
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) gsub("\\\\", "/", f[1]) else NA_character_
}, error = function(e) NA_character_)
ROOT <- if (!is.na(.self) && file.exists(.self)) dirname(dirname(dirname(.self))) else
  gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DETECTOR <- file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")
PITE     <- file.path(ROOT, "02_Infrastructure/validation/pit_enforcement.R")
HELPER   <- file.path(ROOT, "02_Infrastructure/data/fred_availability.R")
RULES    <- file.path(ROOT, "06_Registry/fred_availability_rules.json")
AST      <- file.path(ROOT, "02_Infrastructure/ast/ast_verify.py")
FMAP     <- file.path(ROOT, "06_Registry/ast_field_map_v0.json")
REG      <- file.path(ROOT, "02_Infrastructure/factor_db/factor_registry.json")
QUAR     <- file.path(ROOT, "06_Registry/pit_quarantine.json")
DATA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ROOT))   # 코드 사본(워크트리·스테이징)이면 레거시·git 은 운영 루트에서 읽는다
STRAT    <- if (dir.exists(file.path(ROOT, "04_Research/strategies"))) file.path(ROOT, "04_Research/strategies") else
              file.path(DATA_ROOT, "04_Research/strategies")
GITROOT  <- if (file.exists(file.path(ROOT, ".git"))) ROOT else DATA_ROOT
PIN      <- "7ea5d8377"   # 판정서 작성 시점(2026-09-24 10:45) 커밋 — 수리 전 원판

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
skip <- function(axis, reason, missing) {
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat(sprintf("  SKIP  %s — %s [%s]\n", axis, reason, missing))
}
raises <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")

TD <- file.path(tempdir(), paste0("c11pc_", as.integer(runif(1, 1e6, 9e6))))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
options(lookahead.c11_rules = RULES)

cat("=== 전제 ===\n")
for (p in c(DETECTOR, PITE, HELPER, RULES, AST, FMAP, REG)) chk(paste("존재", basename(p)), file.exists(p), p)

# 검출기를 독립 환경에 싣는다(돌연변이 판과 섞이지 않게)
load_det <- function(path) { e <- new.env(parent = globalenv()); capture.output(sys.source(path, envir = e)); e }
DET <- load_det(DETECTOR)
wfix <- function(name, lines, dir = TD) { f <- file.path(dir, name); writeLines(lines, f, useBytes = TRUE); invisible(f) }
scan <- function(det, f) det$detect_lookahead(f, verbose = FALSE)
codes <- function(r) vapply(r$violations, function(v) v$check, "")
c11_of <- function(r) Filter(function(v) grepl("C11", v$check), r$violations)
has <- function(r, code, line = NULL) any(vapply(r$violations, function(v)
  identical(v$check, code) && (is.null(line) || v$line %in% line), logical(1)))
no_c11 <- function(r) length(c11_of(r)) == 0L

# ════════════════════════════════════════════════════════════════════════════════
# 픽스처 — 위반(P) · 적합(N) · C3(D)
# ════════════════════════════════════════════════════════════════════════════════
FX <- list(
  P01_samedate = c(   # 판정서 d_knowledge/fx_pos_samedate.R (V-08 형태)
    'build_vix <- function(RAWDATA, CACHE_DIR) {',
    '  macro <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    '  vix <- macro[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    '  out <- merge(RAWDATA, vix, by = "Date", all.x = TRUE)',
    '  out', '}'),
  P02_flagword = c(   # 판정서 돌연변이 ①: 근처 단어 verbose_flag(부분문자열 lag)로 구판이 통과
    'build_vix <- function(RAWDATA, CACHE_DIR, verbose_flag = TRUE) {',
    '  macro <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    '  vix <- macro[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    '  out <- merge(RAWDATA, vix, by = "Date", all.x = TRUE)',
    '  out', '}'),
  P03_indirect = c(   # 판정서 돌연변이 ②: paste0 간접 경로로 구판이 통과
    'build_vix <- function(RAWDATA, CACHE_DIR) {',
    '  fn <- paste0("macro_", "fred.parquet")',
    '  macro <- as.data.table(read_parquet(file.path(CACHE_DIR, fn)))',
    '  vix <- macro[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    '  merge(RAWDATA, vix, by = "Date", all.x = TRUE)', '}'),
  P04_splitlit = c(
    'fn <- paste0("macro_f", "red", ".parquet")',
    'm <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, fn)))',
    'v <- m[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    'RW <- v[RW, on = "Date", roll = TRUE]'),
  P05_pathsym = c(
    'm <- as.data.table(read_parquet(FRED_MACRO_CACHE))',
    'v <- m[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    'RW <- merge(RW, v, by = "Date")'),
  P06_loader = c(
    'm <- fred_load_cache()',
    'v <- m[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    'RW <- merge(RW, v, by = "Date")'),
  P07_param_subset = c(   # 경로 없이 인자로 받은 표에서 계열을 뽑아 같은 날짜 결합
    'build <- function(RAWDATA, macro) {',
    '  vix <- macro[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    '  merge(RAWDATA, vix, by = "Date", all.x = TRUE)', '}'),
  P08_weekly_shift = c(   # 주간 NFCI 에 1행 lag — 공표(라벨+6일) 전 사용(V-11 형태)
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "fred_macro.parquet")))',
    'nf <- m[Series_ID == "NFCI", .(Date, NFCI = Value)]',
    'nf[, NFCI := shift(NFCI, 1L)]',
    'RW <- merge(RW, nf, by = "Date", all.x = TRUE)'),
  P09_monthly_cut = c(    # compute_regime 구판 형태: 전 계열 1일 컷 뒤 월간 CPI 사용(V-01)
    'dt <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'dt <- dt[Date <= (sig_d - 1L) & !is.na(Value)]',
    'cpi <- dt[Series == "CPIAUCSL"]',
    'last_cpi <- cpi[Date == max(Date)]$Value'),
  P10_dexkous = c(
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'fx <- m[Series_ID == "DEXKOUS", .(Date, FX = Value)]',
    'fx[, FX := shift(FX, 1L)]',
    'RW <- merge(RW, fx, by = "Date")'),
  P11_asof_nolag = c(
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'v <- m[Series_ID == "VIXCLS"]',
    'last_v <- v[Date <= sig_d][Date == max(Date)]$Value'),
  P12_comment_bypass = c(  # 문장 안 주석의 fred_asof_join( · shift( 는 가용시점 층·lag 가 아니다
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'v <- m[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    'RW <- merge(RW,        # fred_asof_join(kr, v, "VIXCLS") 로 바꿀 예정',
    '            v,         # v[, VIX := shift(VIX, 1L)] 적용됨',
    '            by = "Date")'),
  P13_string_bypass = c(   # 문자열 안의 shift( 는 lag 가 아니다
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'v <- m[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    'msg <- "v[, VIX := shift(VIX, 1L)] 적용"',
    'RW <- merge(RW, v, by = "Date")'),
  P14_lead = c(
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'v <- m[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    'v[, VIX := shift(VIX, 1L, type = "lead")]',
    'RW <- merge(RW, v, by = "Date")'),
  P15_ice_d2 = c(          # ICE OAS 1일 lag — 채택 규약 한국 d+2(CONVENTIONS ②)
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'hy <- m[Series_ID == "BAMLH0A0HYM2", .(Date, HY = Value)]',
    'hy[, HY := shift(HY, 1L)]',
    'RW <- merge(RW, hy, by = "Date")'),
  P16_samemonth_period = c(  # macro_regime 같은 달 조회(V-14 · 레거시 STR_944 형태)
    'macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))',
    'macro_regime_dt[, YM := substr(Date, 1, 7)]',
    'for (dd in dates) {',
    '  ym <- format(as.Date(dd), "%Y-%m")',
    '  mrs <- macro_regime_dt[YM == ym, Macro_Risk_Score]',
    '}'),
  P18_spoof_availkey = c(  # 가용일 열 이름만 흉내(가용시점 층 미사용) — 이름으로는 통과시키지 않는다
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'v <- m[Series_ID == "VIXCLS", .(Asof_Date = Date, VIX = Value)]',
    'setnames(v, "Asof_Date", "Date")',
    'RW <- merge(RW, v, by = "Date")'),
  N11_availkey = c(        # 가용시점 층이 붙인 가용일 열로 결합(국면 생산자 수리판 형태)
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'nf <- fred_avail_annotate(m[Series_ID == "NFCI"], "NFCI")',
    'reg <- nf[!is.na(avail_date), .(Asof_Date = avail_date, NFCI = Value)]',
    'sub <- reg[!is.na(Asof_Date)]',
    'setnames(sub, "Asof_Date", "Date")',
    'out <- sub[data.table(Date = sig_dates), on = "Date", roll = TRUE]'),
  N12_message_only = c(    # 메시지·함수 이름 문자열의 'FRED'·'fred_asof_join' 은 원천이 아니다(국내 표 결합)
    '.load_other <- function() {',
    '  if (!exists("fred_asof_join", mode = "function")) stop("FRED 가용시점 층 없음. 먼저 source 하라")',
    '  as.data.table(read_parquet(file.path(CACHE_DIR, "kr_breadth.parquet"))) }',
    'x <- merge(RW, .load_other(), by = "Date")'),
  N01_lagged = c(          # 판정서 d_knowledge/fx_neg_lagged.R
    'build_vix <- function(RAWDATA, CACHE_DIR) {',
    '  macro <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    '  vix <- macro[Series_ID == "VIXCLS", .(Date, VIX = Value)]',
    '  vix[, VIX := shift(VIX, 1L)]',
    '  out <- merge(RAWDATA, vix, by = "Date", all.x = TRUE)',
    '  out', '}'),
  N02_daily_cut = c(       # compute_regime 형태이되 일간 시장 계열만(VIX: 미국 날짜 < 한국 날짜 = 1일 컷 충분)
    'dt <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'dt <- dt[Date <= (sig_d - 1L) & !is.na(Value)]',
    'vix_dt <- dt[Series == "VIXCLS"]',
    'last_vix <- vix_dt[Date == max(Date)]$Value'),
  N03_engine_daily = c(    # regime_engine_daily 형태이되 일간 계열만: 미국 격자 LOCF + 1행 shift + 패널 저장
    '.load_grid <- function() {',
    '  raw <- as.data.table(read_parquet(FRED_MACRO_CACHE))',
    '  wide <- dcast(raw[, .(Date, Series, Value)], Date ~ Series, value.var = "Value")',
    '  needed <- c("VIX", "Term_Spread")',
    '  for (col in needed) wide[, (col) := nafill(get(col), type = "locf")]',
    '  list(data = wide, series = needed)', '}',
    'build <- function() {',
    '  g <- .load_grid()',
    '  dt <- g$data',
    '  dt[, score := VIX + Term_Spread]',
    '  dt[, score := shift(score, n = 1L, type = "lag")]',
    '  out <- dt[, .(Date, score)]',
    '  write_parquet(out, REGIME_OUT)', '}'),
  N04_avail = c(
    'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
    'nf <- m[Series_ID == "NFCI"]',
    'j <- fred_asof_join(kr_dates, nf, "NFCI", mode = "decision_close")',
    'RW <- merge(RW, j[, .(Date = kr_date, NFCI = value)], by = "Date")'),
  N06_prevmonth = c(       # 레거시 c11fix 형태: 전월 키(함수 안 −32일) — 판정서 1-6 '안전'
    'macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))',
    'macro_regime_dt[, YM := substr(Date, 1, 7)]',
    '.prev_ym <- function(ym) { d <- as.Date(paste0(ym, "-01")); format(d - 32, "%Y-%m") }',
    'for (i in seq_along(days)) {',
    '  prev_ym <- .prev_ym(daily_ym[i])',
    '  mrs_val <- macro_regime_dt[YM == prev_ym, Macro_Risk_Score]',
    '}'),
  N07_period_join_shift = c(  # 레거시 run_all 형태: 월 표 1행(=1개월) shift 뒤 YM 결합 — 판정서 1-6 '안전'
    'mrs_raw <- as.data.table(read_parquet(FRED_REGIME_CACHE))',
    'mrs_raw[, YM := substr(Date, 1, 7)]',
    'mrs_monthly <- mrs_raw[!duplicated(YM), .(YM, Macro_Risk_Score)]',
    'mrs_monthly[, Macro_Risk_Score := shift(Macro_Risk_Score, n = 1L, type = "lag")]',
    'mrs_vals <- mrs_monthly[.(daily_ym_f), on = "YM", Macro_Risk_Score]'),
  N08_ecos_rf = c(         # 1계층 RP_AUTO 형태: ECOS CD91 무위험금리(국내 계열 — 이 검출기 범위 밖) + 월 이동
    '.ec <- as.data.table(read_parquet(file.path(CACHE_DIR, "ecos_bond_rates.parquet")))',
    '.ec <- .ec[Series == "KR_CD91" & is.finite(Value)]',
    '.ec[, MIq := year(Date) * 12L + month(Date)]',
    '.rfm <- .ec[, .(RF = Value[.N] / 1200), by = MIq]',
    '.rfm[, MI := MIq + 1L]',
    '.mp <- merge(.mp, .rfm, by = "MI")'),
  N09_engine = c(          # 해외 원천 없는 일반 엔진
    'FACTORS <- load_month_factors(sig_date = sig_d)',
    'x <- merge(FACTORS, RAWDATA[Date == sig_d, .(Ticker, Sector)], by = "Ticker")',
    'x[, Score := frank(Z_Score_Aligned) / .N]'),
  N10_ticker_merge = c(    # 해외 계보 점수를 전월 키로 고른 뒤 종목 키 결합(레거시 consgate 형태 — 날짜 결합 아님)
    'macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))',
    'macro_regime_dt[, YM := substr(Date, 1, 7)]',
    'prev_ym <- format(as.Date(paste0(sig_ym, "-01")) - 32, "%Y-%m")',
    'macro_row <- macro_regime_dt[YM == prev_ym]',
    'regime_scale <- if (nrow(macro_row) > 0) 1 - macro_row$Macro_Risk_Score[1] / 100 else 1',
    'lv[, Score := rank_x * regime_scale]',
    'lv <- merge(lv, sector_info, by = "Ticker", all.x = TRUE)'),
  D01_c3_nonfred = c(      # 해외 계보 아닌 월 표의 같은 달 조회 — 종전엔 문맥 단어(mrs)로 면제됐다
    'mrs_breadth <- readRDS(file.path(CACHE_DIR, "kr_breadth_monthly.rds"))  # mrs macro regime 참고',
    'val <- mrs_breadth[YM == current_ym, Breadth]'),
  D02_c3_fred_lagged = c(  # 해외 계보이되 열 단위 1개월 shift(레거시 1563 형태) — C11 분석기가 판정(무발화)
    'macro_regime_dt <- as.data.table(arrow::read_parquet(FRED_REGIME_CACHE))',
    'macro_regime_dt[, YM := substr(Date, 1, 7)]',
    'mrs_unique <- macro_regime_dt[, .(YM, Macro_Risk_Score)][!duplicated(YM)]',
    'mrs_unique[, prev_MRS := shift(Macro_Risk_Score, 1, type = "lag")]',
    'for (i in seq_len(n)) {',
    '  mrs_row_i <- mrs_unique[YM == daily_ym[i]]',
    '}'),
  D03_c3_fred_same = c(    # 해외 계보 같은 달 조회 — C11 이 동월로 잡는다
    'macro_regime_dt <- as.data.table(arrow::read_parquet(FRED_REGIME_CACHE))',
    'macro_regime_dt[, YM := substr(Date, 1, 7)]',
    'for (i in seq_len(n)) {',
    '  row_i <- macro_regime_dt[YM == daily_ym[i]]',
    '}')
)
F <- lapply(names(FX), function(nm) wfix(paste0(nm, ".R"), FX[[nm]])); names(F) <- names(FX)
# 어댑터 픽스처: source() 대상 파일을 실제로 읽어 인정 — 진짜 어댑터(N05) vs 이름만 어댑터(P17)
ad_dir <- file.path(TD, "adapter"); dir.create(ad_dir, showWarnings = FALSE)
wfix("real_adapter.R", c('my_on_kr <- function(kr, obs, sid) {',
  '  j <- fred_asof_join(kr, obs, sid, mode = "decision_close")',
  '  data.table(Date = j$kr_date, value = j$value) }'), ad_dir)
wfix("fake_adapter.R", c('my_on_kr <- function(kr, obs, sid) {',
  '  obs[data.table(Date = kr), on = "Date", roll = TRUE] }'), ad_dir)
consumer <- function(helper) c(sprintf('source(file.path(.SELF_DIR, "%s"))', helper),
  'm <- as.data.table(read_parquet(file.path(CACHE_DIR, "macro_fred.parquet")))',
  'v <- m[Series_ID == "VIXCLS", .(Date, Value)]',
  'v2 <- my_on_kr(sort(unique(RW$Date)), v, "VIXCLS")',
  'RW <- merge(RW, v2[, .(Date, VIX = value)], by = "Date")')
F$N05_adapter <- wfix("N05_adapter.R", consumer("real_adapter.R"), ad_dir)
F$P17_fake_adapter <- wfix("P17_fake_adapter.R", consumer("fake_adapter.R"), ad_dir)
# 파이썬
py_dir <- file.path(TD, "py"); dir.create(py_dir, showWarnings = FALSE)
wfix("good_pit.py", c('import fred_availability as fa', 'def build(kr, df):',
  '    return fa.fred_asof_join(kr, df, "NFCI", mode="decision_close")'), py_dir)
F$PY1_merge_asof <- wfix("PY1_merge_asof.py", c('import pandas as pd', 'FRED = "fred_macro_wide.parquet"',
  'f = pd.read_parquet(FRED)', 'out = pd.merge_asof(kr, f[["Date", "NFCI"]], on="Date")'), py_dir)
F$PY2_imported <- wfix("PY2_imported.py", c('import pandas as pd', 'import good_pit as gp',
  'FRED = "fred_macro_wide.parquet"', 'f = pd.read_parquet(FRED)', 'out = gp.build(kr, f).merge(x, on="Date")'), py_dir)
F$PY3_pathjoin <- wfix("PY3_pathjoin.py", c('import os', 'FRED = os.path.join(PIN, "fred_macro_wide.parquet")',
  'print(FRED)'), py_dir)

expect_red <- list(
  P01_samedate = "C11_FRED_SAMEDATE", P02_flagword = "C11_FRED_SAMEDATE", P03_indirect = "C11_FRED_SAMEDATE",
  P04_splitlit = "C11_FRED_SAMEDATE", P05_pathsym = "C11_FRED_SAMEDATE", P06_loader = "C11_FRED_SAMEDATE",
  P07_param_subset = "C11_FRED_SAMEDATE", P08_weekly_shift = "C11_PUB_LAG", P09_monthly_cut = "C11_PUB_LAG",
  P10_dexkous = "C11_PROHIBITED_SERIES", P11_asof_nolag = "C11_FRED_SAMEDATE", P12_comment_bypass = "C11_FRED_SAMEDATE",
  P13_string_bypass = "C11_FRED_SAMEDATE", P14_lead = "C11_FRED_SAMEDATE", P15_ice_d2 = "C11_PUB_LAG",
  P16_samemonth_period = "C11_FRED_SAMEDATE", P17_fake_adapter = "C11_FRED_SAMEDATE",
  P18_spoof_availkey = "C11_FRED_SAMEDATE", PY1_merge_asof = "PY_C11_FRED_SAMEDATE")
expect_clean <- c("N01_lagged", "N02_daily_cut", "N03_engine_daily", "N04_avail", "N05_adapter", "N06_prevmonth",
                  "N07_period_join_shift", "N08_ecos_rf", "N09_engine", "N10_ticker_merge", "N11_availkey", "N12_message_only",
                  "PY2_imported", "PY3_pathjoin")

cat("\n=== A 위반 주입 → red (", length(expect_red), "종) ===\n", sep = "")
RES <- lapply(F, function(f) scan(DET, f))
for (nm in names(expect_red)) chk(sprintf("A %s → %s", nm, expect_red[[nm]]), has(RES[[nm]], expect_red[[nm]]),
                                  paste(codes(RES[[nm]]), collapse = ","))
chk("A P09 발화 줄 = 1일 컷 줄(판정서 V-01 :75-77 형태 — 읽기 줄 아님)", has(RES$P09_monthly_cut, "C11_PUB_LAG", 2L))
chk("A P01 발화 줄 = 결합 줄(:4 — 읽기 줄 :2 아님)", has(RES$P01_samedate, "C11_FRED_SAMEDATE", 4L) &&
      !has(RES$P01_samedate, "C11_FRED_SAMEDATE", 2L))

cat("\n=== B 올바른 lag → 오탐 0 (", length(expect_clean), "종) ===\n", sep = "")
for (nm in expect_clean) chk(sprintf("B %s → C11 무발화·clean", nm), no_c11(RES[[nm]]) && isTRUE(RES[[nm]]$clean),
                             paste(codes(RES[[nm]]), collapse = ","))

cat("\n=== E C3 면제 삭제 ===\n")
chk("E D01 비해외 월 표 같은 달 조회 = C3 (종전: 문맥 단어 mrs 로 면제)", has(RES$D01_c3_nonfred, "C3"))
chk("E D02 해외 계보 열 단위 1개월 shift = C3 없음(C11 분석기가 판정) · C11 무발화",
    !has(RES$D02_c3_fred_lagged, "C3") && no_c11(RES$D02_c3_fred_lagged), paste(codes(RES$D02_c3_fred_lagged), collapse = ","))
chk("E D03 해외 계보 같은 달 조회 = C11_FRED_SAMEDATE(동월) · 파일 not clean",
    has(RES$D03_c3_fred_same, "C11_FRED_SAMEDATE") && !isTRUE(RES$D03_c3_fred_same$clean))
# 구판 대비(양성 대조): 구판은 D01 을 면제했고 P02·P03 을 통과시켰다 — 이 차이가 없으면 검사가 아무것도 안 잰 것이다
OLD_TXT <- tryCatch(system2("git", c("-C", shQuote(GITROOT), "show", paste0(PIN, ":02_Infrastructure/validation/lookahead_detector.R")),
                            stdout = TRUE, stderr = FALSE), error = function(e) character(0))
if (length(OLD_TXT) > 100L) {
  OLD <- load_det(wfix("old_detector.R", OLD_TXT))
  chk("E 구판(면제 있음)은 D01 에서 C3 무발화 — 면제 삭제의 양성 대조", !has(scan(OLD, F$D01_c3_nonfred), "C3"))
  chk("E 구판은 판정서 돌연변이 P02·P03 을 통과시켰다(거짓 음성 재현)",
      !any(grepl("C11", codes(scan(OLD, F$P02_flagword)))) && !any(grepl("C11", codes(scan(OLD, F$P03_indirect)))))
} else skip("E_old_detector", "git 구판 추출 실패 — 구판 대비 양성 대조 미측정", paste0(PIN, ":lookahead_detector.R"))

# ════════════════════════════════════════════════════════════════════════════════
cat("\n=== C 판정서 지목 파일 — git 고정 원판(", PIN, ") ===\n", sep = "")
gshow <- function(path) tryCatch(system2("git", c("-C", shQuote(GITROOT), "show", paste0(PIN, ":", path)), stdout = TRUE, stderr = FALSE),
                                 error = function(e) character(0), warning = function(w) character(0))
pin_dir <- file.path(TD, "pin"); dir.create(pin_dir, showWarnings = FALSE)
PINF <- c(compute_regime = "02_Infrastructure/factor_db/compute_regime.R",
          regime_engine = "02_Infrastructure/regime/regime_engine_daily.R",
          builder = "02_Infrastructure/factor_db/factor_db_builder.R",
          phase6 = "02_Infrastructure/factor_db/factor_db_daily_phase6.R",
          phase7 = "02_Infrastructure/factor_db/factor_db_daily_phase7.R",
          ae_py = "02_Infrastructure/regime/ae_regime_backfill.py")
PT <- lapply(PINF, gshow)
if (all(lengths(PT) > 50L)) {
  PP <- setNames(lapply(names(PT), function(k) wfix(paste0("pin_", basename(PINF[[k]])), PT[[k]], pin_dir)), names(PT))
  R0 <- lapply(PP, function(f) scan(DET, f))
  c11_lines <- function(r) sort(unique(vapply(c11_of(r), function(v) v$line, 0L)))
  # 판정서 ③: 구판은 compute_regime 읽기 줄 49·59·60, regime_engine_daily 읽기 줄 77·78·90·91·95 에서 거짓 양성
  chk("C compute_regime 원판: 종전 거짓 양성 줄(49·59·60) 무발화", !any(c11_lines(R0$compute_regime) %in% c(49L, 59L, 60L)),
      paste(c11_lines(R0$compute_regime), collapse = ","))
  chk("C compute_regime 원판: 발화 = V-01 결함 줄 77(월간 계열 1일 컷) 하나", identical(c11_lines(R0$compute_regime), 77L) &&
      has(R0$compute_regime, "C11_PUB_LAG", 77L), paste(c11_lines(R0$compute_regime), collapse = ","))
  chk("C regime_engine_daily 원판: 종전 거짓 양성 줄(77·78·90·91·95) 무발화",
      !any(c11_lines(R0$regime_engine) %in% c(77L, 78L, 90L, 91L, 95L)), paste(c11_lines(R0$regime_engine), collapse = ","))
  chk("C regime_engine_daily 원판: V-11 패널 저장 줄 419 = C11_PUB_LAG(주간·월간 축 1행 lag) + 금지 계열(KRW_USD=DEXKOUS)",
      has(R0$regime_engine, "C11_PUB_LAG", 419L) && has(R0$regime_engine, "C11_PROHIBITED_SERIES", 419L))
  chk("C 빌더 원판: V-08 결합 줄 311 = C11_FRED_SAMEDATE", has(R0$builder, "C11_FRED_SAMEDATE", 311L), paste(c11_lines(R0$builder), collapse = ","))
  chk("C phase6 원판: V-09 결합 = C11_FRED_SAMEDATE(:86-90)", any(c11_lines(R0$phase6) %in% 86:90), paste(c11_lines(R0$phase6), collapse = ","))
  chk("C phase7 원판: V-12 결합 = C11(:279-305)", any(c11_lines(R0$phase7) %in% 279:305), paste(c11_lines(R0$phase7), collapse = ","))
  chk("C AE backfill 원판(py): V-03 = PY_C11(같은 날짜/금지)", any(grepl("^PY_C11", codes(R0$ae_py))), paste(codes(R0$ae_py), collapse = ","))
  # 결함 줄만 가용시점 층으로 바꾼 compute_regime = 무발화(음성 대조 — 같은 파일의 나머지 코드는 그대로)
  cr <- PT$compute_regime
  i77 <- grep("dt <- dt\\[Date <= \\(sig_d - 1L\\) & !is.na\\(Value\\)\\]", cr)
  if (length(i77) == 1L) {
    cr[i77] <- paste0('        dt <- rbindlist(lapply(unique(dt$Series), function(s) { a <- fred_avail_annotate(dt[Series == s], s); ',
                      'a[!is.na(avail_date) & avail_date <= sig_d & !is.na(Value)] }))')
    R1 <- scan(DET, wfix("pin_compute_regime_availfix.R", cr, pin_dir))
    chk("C compute_regime 원판에서 결함 줄만 가용시점 층으로 바꾼 판 = C11 무발화", no_c11(R1), paste(codes(R1), collapse = ","))
  } else chk("C compute_regime 원판 결함 줄 위치 확인", FALSE, sprintf("(일치 %d줄)", length(i77)))
} else skip("C_pinned", "git 고정 원판 추출 실패 — 판정서 지목 파일 대조 미측정", paste(names(PT)[lengths(PT) <= 50L], collapse = ","))

# ════════════════════════════════════════════════════════════════════════════════
cat("\n=== D 레거시·1계층 엔진 회귀(읽기 전용 · 판정서 1-6 분류) ===\n")
leg <- function(d, f) file.path(STRAT, d, f)
LEG_BAD <- list(c("STR_944_oc_sue", "run_all.R", 46L), c("STR_791_orthogonal", "run_all.R", 60L),
                c("STR_1028_gerber_dcc_hrp", "consgate_pure_engine.R", NA), c("STR_824_rev_breadth_ivol", "factor_engine.R", NA),
                c("STR_943_oc_eps_chg", "run_all.R", NA))
LEG_OK <- list(c("STR_1562_gerber_dcc_hrp_c11fix", "consgate_pure_engine.R"), c("STR_1562_gerber_dcc_hrp_c11fix", "run_all.R"),
               c("STR_1571_bayesian_bl_c11fix", "consgate_pure_engine.R"), c("STR_1435_5sleeve_dd620_repair", "consgate_pure_engine.R"),
               c("STR_1028_gerber_dcc_hrp", "run_all.R"), c("STR_1033_nco", "run_all.R"))
miss <- c(vapply(LEG_BAD, function(x) leg(x[1], x[2]), ""), vapply(LEG_OK, function(x) leg(x[1], x[2]), ""))
miss <- miss[!file.exists(miss)]
if (!length(miss)) {
  for (x in LEG_BAD) { r <- scan(DET, leg(x[1], x[2]))
    ok <- length(c11_of(r)) > 0L && (is.na(x[3]) || any(vapply(c11_of(r), function(v) v$line == as.integer(x[3]), logical(1))))
    chk(sprintf("D 판정서 '동월 위반' %s/%s = C11 발화%s", x[1], x[2], if (is.na(x[3])) "" else paste0(" @", x[3])), ok,
        paste(codes(r), collapse = ",")) }
  for (x in LEG_OK) { r <- scan(DET, leg(x[1], x[2]))
    chk(sprintf("D 판정서 '안전' %s/%s = C11·C3 무발화", x[1], x[2]), no_c11(r) && !has(r, "C3"), paste(codes(r), collapse = ",")) }
} else skip("D_legacy", "레거시 STR 파일 부재 — 판정서 1-6 분류 대조 일부 미측정", paste(basename(dirname(miss)), collapse = ","))
eng <- Sys.glob(file.path(STRAT, "RP_AUTO_*", "engine.R"))
if (length(eng) >= 10L) {
  bad <- character(0)
  for (f in eng) { r <- scan(DET, f); if (!no_c11(r) || has(r, "C3")) bad <- c(bad, basename(dirname(f))) }
  chk(sprintf("D 1계층 RP_AUTO 엔진 %d종 = C11·C3 무발화(판정서 1-6: 충실구현 경로 해외 결합 0)", length(eng)), !length(bad),
      paste(bad, collapse = ","))
} else skip("D_engines", "RP_AUTO 엔진 10종 미만 — 1계층 회귀 미측정", STRAT)

# ════════════════════════════════════════════════════════════════════════════════
cat("\n=== F 검출기 돌연변이 → red ===\n")
DTXT <- readLines(DETECTOR, warn = FALSE, encoding = "UTF-8")
mutant <- function(tag, from, to, fixed = TRUE) {
  hit <- if (fixed) grepl(from, DTXT, fixed = TRUE) else grepl(from, DTXT, perl = TRUE)
  if (sum(hit) < 1L) return(NULL)
  t2 <- DTXT; t2[hit] <- if (fixed) gsub(from, to, t2[hit], fixed = TRUE) else gsub(from, to, t2[hit], perl = TRUE)
  load_det(wfix(paste0("mut_", tag, ".R"), t2))
}
kill <- function(tag, M, test) {
  if (is.null(M)) { chk(sprintf("F %s 돌연변이 적용", tag), FALSE, "(치환 대상 없음 — 검사 전제 붕괴)"); return(invisible()) }
  chk(sprintf("F %s → red(양성 대조가 돌연변이를 잡는다)", tag), !isTRUE(test(M)))
}
kill("M1 분석기 호출 제거", mutant("M1", ".r11 <- .la_c11_scan_r(run_all_path, lines, add_violation)", ".r11 <- NULL"),
     function(M) has(scan(M, F$P01_samedate), "C11_FRED_SAMEDATE"))
kill("M2 lag 판정 항상 참", mutant("M2", ".la_c11_has_lag <- function(code, nostr, names = NULL) {", ".la_c11_has_lag <- function(code, nostr, names = NULL) { return(TRUE)"),   # r1: 서명에 names(계열 묶음) 추가
     function(M) has(scan(M, F$P01_samedate), "C11_FRED_SAMEDATE") && has(scan(M, F$P14_lead), "C11_FRED_SAMEDATE"))
kill("M3 계열 분류 전부 class1", mutant("M3", 'if (!simple) "class2" else {', 'if (!simple) "class1" else {'),
     function(M) has(scan(M, F$P08_weekly_shift), "C11_PUB_LAG") && has(scan(M, F$P09_monthly_cut), "C11_PUB_LAG"))
kill("M4 주석 제거 끔", mutant("M4", 'if (startsWith(s, "#")) return(strrep(" ", nchar(s)))', 'if (startsWith(s, "#")) return(s)'),
     function(M) has(scan(M, F$P12_comment_bypass), "C11_FRED_SAMEDATE"))
kill("M5 C3 판정 줄 전부 면제", mutant("M5", "if (!(.cp$i %in% c11_judged))", "if (FALSE)"),
     function(M) has(scan(M, F$D01_c3_nonfred), "C3"))
kill("M6 규칙 파일 부재 fail-open", mutant("M6", 'add("C11_RULES_UNAVAILABLE", 1L, basename(path),', 'if (FALSE) add("C11_RULES_UNAVAILABLE", 1L, basename(path),'),
     function(M) { op <- options(lookahead.c11_rules = file.path(TD, "no_such_rules.json")); on.exit(options(op))
                   r <- scan(M, F$P01_samedate); has(r, "C11_RULES_UNAVAILABLE") })
kill("M7 어댑터를 본문 확인 없이 인정", mutant("M7", "w <- names(calls)[vapply(calls, function(a) any(a %in% .LA_C11_AVAIL_CORE), logical(1))]",
                                     "w <- names(calls)"),
     function(M) has(scan(M, F$P17_fake_adapter), "C11_FRED_SAMEDATE"))
kill("M8 메시지 문자열도 원천 경로로 셈", mutant("M8", 'pl <- lits[nzchar(lits) & !grepl("\\\\s", lits)]', "pl <- lits[nzchar(lits)]"),
     function(M) no_c11(scan(M, F$N12_message_only)))
kill("M9 가용일 열 이름만으로 인정", mutant("M9", "(file_uses_avail && grepl(P$avail_key, nostr, perl = TRUE))",
                                        "grepl(P$avail_key, nostr, perl = TRUE)"),
     function(M) has(scan(M, F$P18_spoof_availkey), "C11_FRED_SAMEDATE"))
# 규칙 파일이 없으면 판정 불가 = 통과 아님(정상판)
local({ op <- options(lookahead.c11_rules = file.path(TD, "no_such_rules.json")); on.exit(options(op))
  r <- scan(DET, F$P01_samedate)
  chk("F 규칙 파일 부재 → C11_RULES_UNAVAILABLE(fail-closed · 해외 원천 파일)", has(r, "C11_RULES_UNAVAILABLE") && !isTRUE(r$clean))
  chk("F 규칙 파일 부재여도 해외 원천 없는 파일은 영향 없음", no_c11(scan(DET, F$N09_engine))) })

# ════════════════════════════════════════════════════════════════════════════════
cat("\n=== G pit_verify_fred_lag (S0 도우미 경유 · 합성 달력) ===\n")
PE <- new.env(parent = globalenv()); invisible(capture.output(sys.source(HELPER, envir = PE))); invisible(capture.output(sys.source(PITE, envir = PE)))
PE$.pite_self_path <- PITE
cal <- local({ d <- seq(as.Date("2026-06-01"), as.Date("2026-09-30"), by = "day")
  d <- d[as.POSIXlt(d)$wday %in% 1:5]; d[!(d %in% as.Date(c("2026-08-17", "2026-09-24", "2026-09-25")))] })
obs <- data.table(Date = cal[cal <= as.Date("2026-09-11")], Value = seq_along(cal[cal <= as.Date("2026-09-11")]))
krd <- cal[cal >= as.Date("2026-07-01") & cal <= as.Date("2026-09-14")]
J <- PE$fred_asof_join(krd, obs, "VIXCLS", mode = "decision_close", kr_calendar = cal)
pv <- function(...) { capture.output(r <- tryCatch(PE$pit_verify_fred_lag(..., kr_calendar = cal), error = function(e) e)); r }
chk("G1 가용시점 층 결합 산출 = TRUE", isTRUE(pv(J)))
SAME <- data.table(kr_date = krd, obs_date = krd, series_id = "VIXCLS")
chk("G2 같은 날짜 결합 = stop(위반)", inherits(pv(SAME), "error"))
r3 <- pv(SAME, stop_on_violation = FALSE)
chk("G3 stop_on_violation=FALSE → FALSE + violations 행", identical(as.logical(r3), FALSE) && NROW(attr(r3, "violations")) > 0L)
chk("G4 관측일 열 없음 = 거부(fail-closed)", inherits(pv(data.table(Date = krd, Value = 1, Series_ID = "VIXCLS")), "error"))
chk("G5 금지 계열 DEXKOUS = 거부(도우미)", inherits(pv(data.table(kr_date = krd, obs_date = krd - 7L, series_id = "DEXKOUS")), "error"))
chk("G6 reference_dates 맞는 행 0 = 거부(빈 검증 ≠ 통과)", inherits(pv(J, reference_dates = as.Date("2030-01-02")), "error"))
chk("G7 decision_close 적합판을 exposure_return 으로 보면 위반(형태 b — 1행 lag 부족)",
    identical(as.logical(pv(J, mode = "exposure_return", stop_on_violation = FALSE)), FALSE))
NF <- data.table(kr_date = as.Date("2026-09-07"), obs_date = as.Date("2026-09-04"), series_id = "NFCI")   # 금요일 라벨 → 한국 목요일부터
chk("G8 주간 NFCI 라벨+3일 사용 = 위반(공표 라벨+6일)", inherits(pv(NF), "error"))
chk("G9 reference_dates 로 좁힌 적합 행 = TRUE", isTRUE(pv(J, reference_dates = krd[5:10])))
# 돌연변이: 구판(무조건 TRUE) — 같은 날짜 위반을 통과시킨다 → 이 검사가 잡는지
stub <- function(fred_dt, reference_dates, ...) invisible(TRUE)
chk("G10 돌연변이(구판 무조건 TRUE)는 G2 를 통과시킨다 — 검사가 그 차이를 잡는다", isTRUE(stub(SAME, NULL)) && inherits(pv(SAME), "error"))

# ════════════════════════════════════════════════════════════════════════════════
cat("\n=== H ast_verify (파이썬 하위 프로세스 · 합성 달력 주입) ===\n")
py <- gsub("\\\\", "/", Sys.getenv("QVEST_PY", ""))
if (!nzchar(py) || !file.exists(py)) {
  vp <- file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"); py <- if (file.exists(vp)) vp else ""
}
if (nzchar(py)) {
  calj <- file.path(TD, "kr_cal.json")
  writeLines(toJSON(as.character(cal)), calj)
  pkg <- function(name, ast, sig = "2026-09-04", td = "2026-09-07") {
    f <- file.path(TD, paste0("pkg_", name, ".json"))
    writeLines(toJSON(list(strategy_id = name, pit = list(sig_date = sig, decision_ts = td), ast = ast),
                      auto_unbox = TRUE, null = "null"), f); f }
  run_ast <- function(pf, ast_path = AST, fmap = FMAP, quar = QUAR) {
    out <- file.path(TD, paste0(basename(pf), ".", basename(dirname(ast_path)), ".verdict.json"))
    if (file.exists(out)) unlink(out)
    so <- suppressWarnings(system2(py, c(shQuote(ast_path), shQuote(pf), "--out", shQuote(out), "--registry", shQuote(REG),
                                         "--map", shQuote(fmap), "--fred-rules", shQuote(RULES), "--quarantine", shQuote(quar),
                                         "--kr-calendar", shQuote(calj)), stdout = TRUE, stderr = TRUE))
    if (!file.exists(out)) return(list(verdict = "NO_OUTPUT", tail = paste(tail(so, 3), collapse = " | ")))
    fromJSON(out, simplifyVector = FALSE)
  }
  REGL <- function(f) list(leaf = "REGISTRY", factor = f)
  E1 <- function(series = NULL, field = "Value") { l <- list(leaf = "FIELD", group_id = "E1_fred_macro_raw", field = field)
                                                  if (!is.null(series)) l$series <- series; l }
  P <- list(
    re_vix = pkg("re_vix", REGL("RE_VIX_z")),          # 격리(V-10) — 종전 '-1d' 선언 그대로 통과
    re_ts  = pkg("re_ts", REGL("RE_TS_z")),            # T10Y2Y · 저장 lag 1 · class1 → 적합
    re_hy  = pkg("re_hy", REGL("RE_HY_z")),            # ICE OAS · 저장 lag 1 · class2(한국 d+2) → 위반
    ma03   = pkg("ma03", REGL("MA03_Rate_Sensitivity")),  # DGS10 lag 1 — 판정서 1-6 적합(종전 +35d FAIL)
    ma07   = pkg("ma07", REGL("MA07_BusinessCycle_Composite")),  # INDPRO·CPI lag 1 → 위반(V-13)
    d32    = pkg("d32", REGL("D32_Beta_VIX")),         # 격리(V-08)
    e1_vix = pkg("e1_vix", E1("VIXCLS")),              # 미국 09-04(금) → 한국 09-07(월) 가용 = 결정 09-07 적합
    e1_nfci = pkg("e1_nfci", E1("NFCI")),              # 라벨 09-04 → 한국 09-10(목) > 09-07 → 위반
    e1_none = pkg("e1_none", E1(NULL)),                # series 미선언 → FAIL_CONTRACT
    e1_dex = pkg("e1_dex", E1("DEXKOUS")),             # 금지
    e4     = pkg("e4", list(leaf = "STORED_SCORE", group_id = "E4_regime_daily_v2_mrs",
                           provenance = list(store_build_hash = "x", generator_code_path = "02_Infrastructure/regime/regime_engine_daily.R",
                                             generated_at = "2026-09-01T00:00:00"), production_parity_verified = TRUE))
  )
  V <- lapply(P, run_ast)
  vd <- function(k) V[[k]]$verdict
  chk("H1 RE_VIX_z(격리 V-10) = FAIL_LOOKAHEAD — 종전 '-1d' 선언 통과 수리", identical(vd("re_vix"), "FAIL_LOOKAHEAD"), vd("re_vix"))
  chk("H2 RE_TS_z(class1 · lag 1) = 통과", vd("re_ts") %in% c("PASS", "WARN_RESTATEMENT"), vd("re_ts"))
  chk("H3 RE_HY_z(ICE d+2 · lag 1) = FAIL_LOOKAHEAD", identical(vd("re_hy"), "FAIL_LOOKAHEAD"), vd("re_hy"))
  chk("H4 MA03(DGS10 lag 1 — 판정서 1-6 적합) = 통과", vd("ma03") %in% c("PASS", "WARN_RESTATEMENT"), vd("ma03"))
  chk("H5 MA07(INDPRO·CPI lag 1) = FAIL_LOOKAHEAD", identical(vd("ma07"), "FAIL_LOOKAHEAD"), vd("ma07"))
  chk("H6 D32(격리 V-08) = FAIL_LOOKAHEAD", identical(vd("d32"), "FAIL_LOOKAHEAD"), vd("d32"))
  chk("H7 E1 VIXCLS 미국 금 → 한국 월 결정 = 통과", vd("e1_vix") %in% c("PASS", "WARN_RESTATEMENT"), vd("e1_vix"))
  chk("H8 E1 NFCI 라벨 금 → 한국 월 결정 = FAIL_LOOKAHEAD(라벨+6일)", identical(vd("e1_nfci"), "FAIL_LOOKAHEAD"), vd("e1_nfci"))
  chk("H9 E1 series 미선언 = FAIL_CONTRACT(선언 근사 폐지)", identical(vd("e1_none"), "FAIL_CONTRACT"), vd("e1_none"))
  chk("H10 E1 DEXKOUS = FAIL_LOOKAHEAD(금지)", identical(vd("e1_dex"), "FAIL_LOOKAHEAD"), vd("e1_dex"))
  chk("H11 E4 regime_daily_v2(선언 정정·격리) = FAIL_LOOKAHEAD", identical(vd("e4"), "FAIL_LOOKAHEAD"), vd("e4"))
  # 격리 해제판(사본)에서는 격리 사유가 사라진다 — 격리 판독이 실제로 판정을 움직인다(양성 대조)
  qx <- fromJSON(QUAR, simplifyVector = FALSE); for (k in seq_along(qx$quarantines)) qx$quarantines[[k]]$status <- "released"
  qrel <- file.path(TD, "quarantine_released.json"); writeLines(toJSON(qx, auto_unbox = TRUE, null = "null", pretty = TRUE), qrel)
  v_rel <- run_ast(P$e4, quar = qrel)
  chk("H12 격리 해제 사본 → E4 격리 사유 없음(판독이 판정을 움직인다)", !identical(v_rel$verdict, "FAIL_LOOKAHEAD"), v_rel$verdict)
  # c11_registry_series 미등재 = FAIL_CONTRACT(선언만으로 통과 없음)
  fm <- fromJSON(FMAP, simplifyVector = FALSE); fm$c11_registry_series$factors$RE_TS_z <- NULL
  fm2 <- file.path(TD, "fmap_no_rets.json"); writeLines(toJSON(fm, auto_unbox = TRUE, null = "null", pretty = TRUE), fm2)
  v_nm <- run_ast(P$re_ts, fmap = fm2)
  chk("H13 계열 등재 없는 '-1d' 팩터 = FAIL_CONTRACT", identical(v_nm$verdict, "FAIL_CONTRACT"), v_nm$verdict)
  # 기존 픽스처 배터리 5/5(회귀)
  bat <- file.path(ROOT, "02_Infrastructure/ast/tests/run_fixture_battery.py")
  if (file.exists(bat)) {
    so <- suppressWarnings(system2(py, shQuote(bat), stdout = TRUE, stderr = TRUE))
    chk("H14 ast 기존 픽스처 배터리 5/5", any(grepl("battery: 5/5", so, fixed = TRUE)), paste(tail(so, 2), collapse = " | "))
  } else skip("H14_battery", "ast 픽스처 배터리 부재", bat)
  # 돌연변이: ast_verify 사본 트리(코드 트리 구조 유지 — data/ 형제 도우미)
  mt_root <- file.path(TD, "astmut"); dir.create(file.path(mt_root, "ast"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(mt_root, "data"), showWarnings = FALSE)
  file.copy(file.path(ROOT, "02_Infrastructure/data/fred_availability.py"), file.path(mt_root, "data"), overwrite = TRUE)
  ATXT <- readLines(AST, warn = FALSE, encoding = "UTF-8")
  amut <- function(tag, from, to) {
    hit <- grepl(from, ATXT, fixed = TRUE)
    if (!any(hit)) return(NULL)
    d <- file.path(mt_root, paste0("ast_", tag)); dir.create(d, showWarnings = FALSE)
    t2 <- ATXT; t2[hit] <- gsub(from, to, t2[hit], fixed = TRUE)
    # 형제 data/ 를 찾도록 같은 깊이에 둔다: <mt_root>/ast_<tag>/ast_verify.py → dirname(dirname) = mt_root
    f <- file.path(d, "ast_verify.py"); writeLines(t2, f, useBytes = TRUE); f
  }
  akill <- function(tag, f, key, bad_verdicts) {
    if (is.null(f)) { chk(sprintf("H %s 돌연변이 적용", tag), FALSE, "(치환 대상 없음)"); return(invisible()) }
    v <- run_ast(P[[key]], ast_path = f)
    chk(sprintf("H %s → red(%s 판정이 뒤집힌다)", tag, key), v$verdict %in% bad_verdicts, v$verdict)
  }
  akill("AM1 '-1d' 선언 그대로 신뢰(구판 :360-361)", amut("AM1", "avail = self._resolve_c11_registry(name, rule, disc, t, path, desc)", "avail = t"),
        "re_hy", c("PASS", "WARN_RESTATEMENT"))
  akill("AM2 격리 판독 끔", amut("AM2", "if not hit:", "if True:"), "e4", c("PASS", "WARN_RESTATEMENT", "FAIL_CONTRACT"))
  akill("AM3 계열 분류 전부 class1", amut("AM3", '    if rule.get("status") != "active":', '    return "class1"  # MUT\n    if rule.get("status") != "active":'),
        "re_hy", c("PASS", "WARN_RESTATEMENT"))
  akill("AM4 E1 가용일 = 관측일(lag 없음)", amut("AM4", "avail = self._fa.fred_avail_date(r[\"id\"], t, kr_calendar=cal, rules=self._rules)", "avail = t"),
        "e1_nfci", c("PASS", "WARN_RESTATEMENT"))
} else skip("H_ast_verify", "파이썬 해석기(QVEST_PY·venv) 없음 — ast_verify 축 미측정", "QVEST_PY")

unlink(TD, recursive = TRUE)
cat(sprintf("\n=== 결과: PASS %d · FAIL %d · SKIP %d ===\n", PASS, FAIL, length(SKIPS)))
cat(toJSON(list(test = "pit_c11_positive_control", pass = PASS, fail = FAIL, skipped = length(SKIPS),
                total = PASS + FAIL, skips = SKIPS), auto_unbox = TRUE), "\n", sep = "")
quit(status = if (FAIL > 0L) 1L else 0L, save = "no")
