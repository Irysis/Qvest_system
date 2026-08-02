#==============================================================================
# test_ev_term_not_inert.R — EV 항이 살아 있는지의 상설 검사
#
# 대상: 02_Infrastructure/factor_db/compute_value.R
#       (EV = MarketCap + TotalDebt - Cash 를 쓰는 V07/V13/V14/V22 + NetDebt 의 V15,
#        그리고 TotalLiab 을 더하는 V16)
#
# 왜 있나 (2026-08-02):
#   저장된 월간 factor DB 에서 V13_EV_Sales 의 Z_Score 가 V08_PSR 과 258/258 개월
#   cor = 1.000000 이었다. EV 항이 아무 일도 하지 않았다는 뜻이다.
#   기전은 `MarketCap := Close * Size` — RAWDATA$Size 는 **이미 시가총액**인데
#   (compute_size.R:38 이 명시, factor_db_builder.R:350 은 Size/Close 로 주식수를
#   역산한다) 거기에 주가를 한 번 더 곱해 시총이 종목별 ~5e3 배 부풀었다.
#   그 결과 더해지는 재무 항(TotalDebt/Cash/TotalLiab)이 수치적으로 소멸했다.
#   → EV ≡ MarketCap → V13 ≡ V08, V16 ≡ 1/V18.
#
#   ★ 이 결함은 **중복으로 위장**한다. 라벨(alias/dedup)로 접으면 결함이 라벨 뒤로
#     사라진다. 그래서 판정 기준을 "두 팩터가 순위-동일한가"로 상설화한다 —
#     그 동일성 자체가 결함의 지문이기 때문이다.
#
# 구조 5축:
#   A. 회귀       — 실데이터에서 EV 팩터가 non-EV 쌍둥이와 순위-동일하지 않은지
#   B. 위반 주입  — 구 `Close * Size` 를 되살리면 A 가 실제로 실패하는지
#                   (= 이 검사가 결함을 잡을 능력이 있는지 / 차단 실효)
#   C. 결손 경로  — 부채/현금 입력이 없는 종목이 NA(미커버)로 떨어지는지.
#                   구 coalesce(.,0) 를 되살리면 커버리지가 부풀어야 한다
#                   (= "결손을 정상값으로 내려앉힘" 계열의 재발 감지)
#   D. 척도 불변  — 모듈이 쓰는 시총이 RAWDATA$Size 와 같은 척도인지.
#                   A 는 지문이고 D 는 원인이다 — 원인을 직접 잰다.
#   E. 음성 대조  — 시총을 안 쓰는 팩터(V17/V23)는 그대로여야 한다.
#                   (무차별 변경을 '수리'로 오인하지 않게 하는 대조군)
#
#   ★ 주입이 실제로 적용됐는지를 매번 단언한다. 리팩터로 needle 이 어긋나면
#     주입이 무해해져 B/C 가 **공허하게 통과**한다 — 그건 초록이 아니라 검사 사망이다.
#
# 단독 실행: Rscript 08_Tests/factor_db/test_ev_term_not_inert.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================

suppressPackageStartupMessages({ library(data.table); library(arrow) })

# ─── 앵커 = self-first ──────────────────────────────────────────────────────
# 환경변수(CLAUDE_PROJECT_DIR/QM_ROOT)를 먼저 보면 worktree 에서 돌린 검사가
# main 의 소스를 검사한다(2026-08-02 실측: 러너 4종이 이 함정을 밟고 있었다).
# 자기 자신의 위치에서 위로 올라가 트리를 고르고, 표지 파일로 정체성을 확인한다.
.resolve_proj <- function() {
  MARKER <- "02_Infrastructure/factor_db/compute_value.R"
  a <- commandArgs(trailingOnly = FALSE)
  fa <- a[grepl("^--file=", a)]
  self <- if (length(fa)) normalizePath(sub("^--file=", "", fa[1]), winslash = "/", mustWork = FALSE) else ""
  cands <- character(0)
  if (nzchar(self)) cands <- c(cands, dirname(dirname(dirname(self))))   # 08_Tests/factor_db/x.R -> root
  cands <- c(cands, Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                    Sys.getenv("QM_ROOT", unset = ""), getwd())
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, MARKER))]
  if (!length(hit)) stop("project root 미발견 — 표지 없음: ", MARKER)
  normalizePath(hit[1], winslash = "/")
}
PROJ <- .resolve_proj()
MOD  <- file.path(PROJ, "02_Infrastructure/factor_db/compute_value.R")

# 데이터 앵커는 코드 앵커와 **다르다**. 코드 정체성은 self-first 여야 하지만
# .cache/ 는 추적되지 않는 단일 산출물이라 worktree 에는 없다(정본 루트에만 존재).
# 두 앵커를 하나로 묶으면 worktree 검사가 통째로 SKIP 되어 상시 무해해진다.
.resolve_data <- function() {
  cands <- c(PROJ, Sys.getenv("QM_ROOT", unset = ""),
             Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, ".cache/RAWDATA.parquet"))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[1], winslash = "/")
}
DATA_ROOT <- .resolve_data()
cat(sprintf("[anchor] PROJ(code) = %s\n", PROJ))
cat(sprintf("[anchor] MOD        = %s\n", MOD))
cat(sprintf("[anchor] DATA_ROOT  = %s\n", DATA_ROOT))

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok   <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad  <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
skip <- function(n, m = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s — %s\n", n, m)) }

# ─── 전제(데이터) 부재는 FAIL 이 아니라 제3상태 ────────────────────────────
RAW_P  <- if (is.na(DATA_ROOT)) "" else file.path(DATA_ROOT, ".cache/RAWDATA.parquet")
FUND_P <- if (is.na(DATA_ROOT)) "" else file.path(DATA_ROOT, ".cache/fundamental_merged.parquet")
if (!nzchar(RAW_P) || !file.exists(RAW_P) || !file.exists(FUND_P)) {
  skip("전제 데이터", "RAWDATA/fundamental_merged parquet 부재 — 판정 불가")
  cat(sprintf("\n[test_ev_term_not_inert] PASS=%d FAIL=%d SKIP=%d\n", PASS, FAIL, SKIP))
  quit(status = 0)
}

SIG      <- as.Date("2026-06-30")
RHO_MAX  <- 0.999   # |Spearman| 이 이 값 이상이면 "순위-동일" = 결함 지문
# EV 팩터 -> 같은 분자/분모를 공유하는 non-EV 쌍둥이
PAIRS <- list(c("V13_EV_Sales", "V08_PSR"),
              c("V22_FCFF_EV",  "V10_FCF_Yield"),
              c("V16_Tobins_Q", "V18_AM"))

# ─── 입력 준비 (필요 컬럼만) ────────────────────────────────────────────────
RAW <- as.data.table(read_parquet(RAW_P, col_select = c("Date", "Ticker", "Close", "Size")))
RAW[, Date := as.Date(Date)]
RS <- RAW[Date <= SIG & Date >= (SIG - 1400L)]
setkey(RS, Date, Ticker)
FUND <- as.data.table(read_parquet(FUND_P))
FUND[, Factor_Date := as.Date(Factor_Date)]
FP <- FUND[Factor_Date <= SIG]
if (nrow(RS) == 0L || nrow(FP) == 0L) {
  skip("전제 데이터", sprintf("SIG=%s 시점 입력 없음 (RAW=%d, FUND=%d)", SIG, nrow(RS), nrow(FP)))
  cat(sprintf("\n[test_ev_term_not_inert] PASS=%d FAIL=%d SKIP=%d\n", PASS, FAIL, SKIP))
  quit(status = 0)
}

SRC <- readLines(MOD, warn = FALSE)

# 소스에 치환을 적용해 compute_value 를 하나 만든다.
# subs = list(list(pattern=, replacement=, min_hits=)) — 치환이 실제로 먹었는지 단언한다.
build_fn <- function(subs = list(), label = "as-is") {
  txt <- SRC
  for (s in subs) {
    hits <- sum(grepl(s$pattern, txt))
    if (hits < s$min_hits)
      stop(sprintf("[주입 실패] label=%s pattern='%s' 이 %d 곳에서만 매치(요구 %d). ",
                   label, s$pattern, hits, s$min_hits),
           "소스가 리팩터돼 needle 이 어긋났다 — 주입이 무해해져 검사가 공허해진다. needle 갱신 필요.")
    txt <- sub(s$pattern, s$replacement, txt)
  }
  tf <- tempfile(fileext = ".R")
  writeLines(txt, tf)
  e <- new.env(parent = globalenv())
  source(tf, local = e)
  unlink(tf)
  get("compute_value", envir = e)
}

run_wide <- function(fn) {
  r <- fn(RAWDATA = RS, sig_date = SIG, FUND = FP, CONSENSUS = NULL)
  if (is.null(r) || nrow(r) == 0L) return(NULL)
  dcast(r, Ticker ~ Factor_Name, value.var = "Raw_Value")
}

sp <- function(w, f1, f2) {
  if (is.null(w) || !all(c(f1, f2) %in% names(w))) return(NA_real_)
  a <- w[[f1]]; b <- w[[f2]]
  keep <- is.finite(a) & is.finite(b)
  if (sum(keep) < 30L) return(NA_real_)
  suppressWarnings(cor(a[keep], b[keep], method = "spearman"))
}

# ── 현행 소스 실행 ──────────────────────────────────────────────────────────
W <- tryCatch(run_wide(build_fn()), error = function(e) { bad("현행 소스 실행", conditionMessage(e)); NULL })

#=============================================================================
# A. 회귀 — EV 팩터가 non-EV 쌍둥이와 순위-동일하면 안 된다
#=============================================================================
cat("\n[A] 회귀 — EV 항이 순위에 실제로 기여하는가\n")
if (is.null(W)) {
  bad("A", "현행 소스가 결과를 내지 못함")
} else for (p in PAIRS) {
  rho <- sp(W, p[1], p[2])
  nm <- sprintf("A/%s ~ %s", p[1], p[2])
  if (is.na(rho)) { bad(nm, "두 팩터 공통 관측 30 미만 — 판정 불가(커버리지 붕괴 의심)"); next }
  if (abs(rho) >= RHO_MAX)
    bad(nm, sprintf("|rho|=%.6f >= %.4f — 순위-동일. EV 항이 무력하다(결함 재발).", abs(rho), RHO_MAX))
  else
    ok(nm, sprintf("|rho|=%.6f (여유 %.4f)", abs(rho), RHO_MAX - abs(rho)))
}

#=============================================================================
# D. 척도 불변 — 모듈이 쓰는 시총이 RAWDATA$Size 척도인가 (지문 아닌 원인)
#    TotalLiab/MarketCap 은 경제적으로 O(0.1~2). Close 를 한 번 더 곱하면 ~1e-4 가 된다.
#=============================================================================
cat("\n[D] 척도 불변 — 시총이 Size 척도인가\n")
if (is.null(W) || !all(c("V16_Tobins_Q", "V18_AM") %in% names(W))) {
  bad("D", "V16/V18 부재 — 척도 역산 불가")
} else {
  # V16*V18 = (MC + TotalLiab)/TA * TA/MC = 1 + TotalLiab/MC
  ratio <- (W$V16_Tobins_Q * W$V18_AM) - 1
  ratio <- ratio[is.finite(ratio) & ratio > 0]
  med <- if (length(ratio) >= 30L) median(ratio) else NA_real_
  if (is.na(med)) bad("D/TotalLiab_over_MarketCap", "관측 부족")
  else if (med < 0.05 || med > 5)
    bad("D/TotalLiab_over_MarketCap",
        sprintf("median=%.6g — 경제적 범위 [0.05, 5] 밖. 시총 척도가 어긋났다(Close 중복 곱 의심).", med))
  else ok("D/TotalLiab_over_MarketCap", sprintf("median=%.4f", med))
}

#=============================================================================
# B. 위반 주입 — 구 `Close * Size` 를 되살리면 A 가 실패해야 한다
#=============================================================================
cat("\n[B] 위반 주입 — 구 시총 정의를 되살리면 잡히는가\n")
inj_ok <- TRUE
W_inj <- tryCatch(
  run_wide(build_fn(list(list(pattern = "snap\\[, MarketCap := Size\\]",
                              replacement = "snap[, MarketCap := Close * Size]",
                              min_hits = 1L)), label = "MarketCap=Close*Size")),
  error = function(e) { inj_ok <<- FALSE; bad("B/주입 적용", conditionMessage(e)); NULL })
if (inj_ok && !is.null(W_inj)) {
  caught <- 0L; total <- 0L
  for (p in PAIRS) {
    rho <- sp(W_inj, p[1], p[2])
    if (is.na(rho)) next
    total <- total + 1L
    if (abs(rho) >= RHO_MAX) caught <- caught + 1L
  }
  if (total == 0L) bad("B/차단 실효", "주입판에서 어떤 쌍도 판정되지 않음 — 케이스가 공허하다")
  else if (caught == total) ok("B/차단 실효", sprintf("주입 시 %d/%d 쌍 전부 순위-동일로 검거", caught, total))
  else bad("B/차단 실효",
           sprintf("주입했는데 %d/%d 쌍만 검거 — 문턱 %.4f 가 결함을 통과시킨다", caught, total, RHO_MAX))
} else if (inj_ok) bad("B", "주입판이 결과를 내지 못함")

#=============================================================================
# C. 결손 경로 — 부채/현금 결손이 NA 로 떨어지는가
#    구 coalesce(.,0) 를 되살리면 EV 팩터 커버리지가 부풀어야 한다.
#=============================================================================
cat("\n[C] 결손 경로 — 입력 결손이 NA(미커버)로 떨어지는가\n")
cov_ok <- TRUE
W_coal <- tryCatch(
  run_wide(build_fn(list(
    list(pattern = "debt_reported > 0L", replacement = "rep(TRUE, nrow(dt))", min_hits = 1L),
    list(pattern = "dt\\[, Cash := CashAndEquiv\\]",
         replacement = "dt[, Cash := fifelse(!is.na(CashAndEquiv), CashAndEquiv, 0)]", min_hits = 1L)
  ), label = "NA->0 coalesce")),
  error = function(e) { cov_ok <<- FALSE; bad("C/주입 적용", conditionMessage(e)); NULL })
if (cov_ok && !is.null(W_coal) && !is.null(W)) {
  infl <- 0L; tot <- 0L
  for (f in c("V13_EV_Sales", "V07_EV_EBITDA", "V14_EBIT_EV", "V22_FCFF_EV", "V15_NetDebt_Adj_EP")) {
    if (!(f %in% names(W)) || !(f %in% names(W_coal))) next
    tot <- tot + 1L
    n_now <- sum(is.finite(W[[f]])); n_coal <- sum(is.finite(W_coal[[f]]))
    if (n_coal > n_now) infl <- infl + 1L
  }
  if (tot == 0L) bad("C/차단 실효", "EV 팩터가 하나도 없음 — 케이스가 공허하다")
  else if (infl == tot)
    ok("C/차단 실효", sprintf("coalesce 복원 시 %d/%d 팩터 커버리지가 부풀음 = 결손이 값으로 위장됨을 검사가 구분", infl, tot))
  else bad("C/차단 실효",
           sprintf("coalesce 를 되살렸는데 %d/%d 만 커버리지가 늘었다 — 결손 경로 판정이 무력하다", infl, tot))
} else if (cov_ok) bad("C", "주입판이 결과를 내지 못함")

#=============================================================================
# E. 음성 대조 — 시총을 안 쓰는 팩터는 주입에 흔들리지 않아야 한다
#=============================================================================
cat("\n[E] 음성 대조 — 시총 무관 팩터는 불변인가\n")
if (!is.null(W) && !is.null(W_inj)) {
  for (f in c("V17_Payout_Ratio", "V23_RAFI_Weight")) {
    if (!(f %in% names(W)) || !(f %in% names(W_inj))) { skip(sprintf("E/%s", f), "팩터 부재"); next }
    m <- merge(W[, c("Ticker", f), with = FALSE], W_inj[, c("Ticker", f), with = FALSE],
               by = "Ticker", suffixes = c(".a", ".b"))
    a <- m[[paste0(f, ".a")]]; b <- m[[paste0(f, ".b")]]
    keep <- is.finite(a) & is.finite(b)
    if (sum(keep) < 30L) { skip(sprintf("E/%s", f), "관측 부족"); next }
    rho <- suppressWarnings(cor(a[keep], b[keep], method = "spearman"))
    if (isTRUE(all.equal(rho, 1))) ok(sprintf("E/%s", f), "시총 정의에 불변 (rho=1)")
    else bad(sprintf("E/%s", f),
             sprintf("rho=%.6f — 시총을 쓰지 않는 팩터가 시총 정의에 반응한다(수리 범위 누출)", rho))
  }
} else skip("E", "대조 불가 (현행 또는 주입판 결과 없음)")

cat(sprintf("\n[test_ev_term_not_inert] PASS=%d FAIL=%d SKIP=%d\n", PASS, FAIL, SKIP))
quit(status = if (FAIL > 0L) 1L else 0L)
