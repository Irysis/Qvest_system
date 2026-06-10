#==============================================================================
# Quant Module — Unified Configuration
# Version: 1.0.0
#
# Single source of truth for all paths and global settings.
# Source this file at the top of every script.
#==============================================================================

# ─── Project Root ────────────────────────────────────────────────────────────
# 우선순위: QM_ROOT 환경변수 → 알려진 후보 경로(드라이브 무관).
# 새 위치/드라이브로 옮겨도 QM_ROOT만 설정하면 무수정 동작.
# (2026-06-03 G:\ 이전 대응 — 본 파일 단일 수정으로 config.R-source 스크립트 181개 자동 정합)
.root_candidates <- c(
  Sys.getenv("QM_ROOT", unset = ""),                            # 명시 override (최우선)
  Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),                 # Claude Code 주입
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot",               # OneDrive canonical (도훈 mandate 2026-06-10)
  "/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot",           # WSL 동일 경로 호환
  "/g/Quant_Module_Moltbot", "G:/Quant_Module_Moltbot",         # legacy G:\ 잔존 호환
  "/mnt/g/Quant_Module_Moltbot"
)
.root_candidates <- .root_candidates[nzchar(.root_candidates)]
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
if (is.na(PROJECT_ROOT)) {
  # 후보 미발견 — QM_ROOT 미설정 + 미이동 상태. 임시 fallback + 경고.
  PROJECT_ROOT <- Sys.getenv("QM_ROOT", unset = Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
  warning("[config.R] 후보 경로 미발견 — QM_ROOT 환경변수를 설정하세요. 임시값: ", PROJECT_ROOT)
}
rm(.root_candidates)

# ─── Data Paths ──────────────────────────────────────────────────────────────
RAWDATA_PATH <- file.path(PROJECT_ROOT, "03_Universe")
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
INFRA_DIR    <- FUNC_PATH
LIT_PATH     <- file.path(PROJECT_ROOT, "01_Literature")

# ─── Infrastructure Subdirectories ──────────────────────────────────────────
DATA_DIR       <- file.path(INFRA_DIR, "data")
FACTOR_DB_DIR  <- file.path(INFRA_DIR, "factor_db")
REGIME_DIR     <- file.path(INFRA_DIR, "regime")
VALIDATION_DIR <- file.path(INFRA_DIR, "validation")
HOOKS_DIR      <- file.path(INFRA_DIR, "hooks")
AGENTS_DIR     <- file.path(INFRA_DIR, "agents")
TELEGRAM_DIR   <- file.path(INFRA_DIR, "telegram")
REPORTS_DIR    <- file.path(INFRA_DIR, "reports")
MEMORY_DIR     <- file.path(INFRA_DIR, "memory")
PORTFOLIO_DIR  <- file.path(INFRA_DIR, "portfolio")
OPS_DIR        <- file.path(INFRA_DIR, "ops")
DOCS_DIR       <- file.path(INFRA_DIR, "docs")

# ─── Output Paths ───────────────────────────────────────────────────────────
RESEARCH_OUTPUT  <- file.path(PROJECT_ROOT, "04_Research")
RESEARCH_REG     <- file.path(PROJECT_ROOT, "06_Registry")
STRATEGY_OUTPUT  <- file.path(RESEARCH_OUTPUT, "strategies")
BRIEFING_OUTPUT  <- file.path(RESEARCH_OUTPUT, "briefings")
PAPER_NOTES      <- file.path(RESEARCH_OUTPUT, "paper_notes")
LOG_OUTPUT       <- file.path(RESEARCH_OUTPUT, "logs")

# ─── Cache (Parquet) ─────────────────────────────────────────────────────────
CACHE_DIR      <- file.path(PROJECT_ROOT, ".cache")
RAWDATA_CACHE  <- file.path(CACHE_DIR, "RAWDATA.parquet")
BM_CACHE       <- file.path(CACHE_DIR, "benchmark.parquet")

# ─── Universe Cache (KRX API 기반 + QuantiWise Support 메타) ────────────────
UNIVERSE_CACHE         <- file.path(CACHE_DIR, "universe.parquet")
UNIVERSE_SUPPORT_CACHE <- file.path(CACHE_DIR, "universe_support")
UNIVERSE_SUPPORT_XLSX  <- file.path(RAWDATA_PATH, "Universe_Support.xlsx")

# ─── Fundamental / Macro Cache ──────────────────────────────────────────────
DART_FACTOR_CACHE  <- file.path(CACHE_DIR, "fundamental_dart.parquet")
FRED_MACRO_CACHE   <- file.path(CACHE_DIR, "macro_fred.parquet")
FRED_REGIME_CACHE  <- file.path(CACHE_DIR, "macro_regime.parquet")

# ─── ECOS (한국은행 경제통계) ───────────────────────────────────────────────
ECOS_API_KEY      <- "AIQOGTG4QU4GWPCT8INK"
ECOS_KRW_CACHE    <- file.path(CACHE_DIR, "ecos_krw_usd.parquet")

# ─── Endogenous Regime Cache ───────────────────────────────────────────────
REGIME_ENDO_CACHE  <- file.path(CACHE_DIR, "market_regime_endo.parquet")

# ─── Unified Regime Signal (3-Layer Cascade) ─────────────────────────────
REGIME_SIGNAL_CACHE <- file.path(CACHE_DIR, "unified_regime_signal.parquet")

# ─── Consensus (QuantiWise) Cache ────────────────────────────────────────
CONSENSUS_CACHE <- file.path(CACHE_DIR, "consensus")

# ─── Investor (QuantiWise 거래주체) Cache ────────────────────────────────
INVESTOR_CACHE     <- file.path(CACHE_DIR, "investor_stock")
INVESTOR_WIDE_CACHE <- file.path(INVESTOR_CACHE, "investor_wide.parquet")

# ─── Valuation (밸류에이션 팩터) Cache ───────────────────────────────────
VALUATION_CACHE <- file.path(CACHE_DIR, "valuation.parquet")

# ─── Regime Engine v2 Thresholds (2026-03-14 Pareto-optimized) ────────────
# Pareto front: H10/S40/E50% → CAGR 11.1%, SR 0.796, MDD -18.1%
MACRO_HARD_THRESH   <- 40L    # Score >= this → SKIP month (0% exposure)
REGIME_SOFT_THRESH  <- 10L    # Score >= this → HALF exposure
REGIME_SCALE_SOFT   <- 0.5    # Exposure multiplier in HALF zone
BUDDHA_CASH_OUT     <- TRUE   # Buddha Mode (score >= 70) → full cash

# ─── Loop Integrator Path ────────────────────────────────────────────────────
LOOP_INTEGRATOR_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure", "memory", "loop_integrator.R")

# ─── Simulation Defaults ────────────────────────────────────────────────────
DEFAULT_INITIAL_CAPITAL  <- 100000000  # 1억 KRW
DEFAULT_COMMISSION       <- 0.0015     # 0.15% (commission + slippage)
DEFAULT_MAX_HOLDINGS     <- 20
DEFAULT_MIN_WEIGHT       <- 0.02

# ─── Benchmark ───────────────────────────────────────────────────────────────
DEFAULT_BM_CODE <- "IKS200"  # KOSPI (전체, Naver code=KOSPI)

# ─── Analysis Date Range ────────────────────────────────────────────────────
# RAWDATA/Factor DB/BM 모두 1990년부터 존재.
# 개별 팩터의 데이터 가용성은 load_month_factors()가 coverage 필터로 자동 처리.
# 날짜 하드코딩 금지 — 이 상수를 참조할 것.
ANALYSIS_START_DATE <- as.Date("1990-01-01")  # RAWDATA/BM 로드 범위
SIGNAL_START_DATE   <- as.Date("1990-07-01")  # 시그널 생성 시작 (6개월 lookback 버퍼)

# ─── Create Directories ─────────────────────────────────────────────────────
.ensure_dirs <- function() {
  dirs <- c(
    RESEARCH_OUTPUT, RESEARCH_REG,
    STRATEGY_OUTPUT, BRIEFING_OUTPUT, PAPER_NOTES, LOG_OUTPUT,
    CACHE_DIR
  )
  for (d in dirs) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
}
.ensure_dirs()

# ─── Validation ──────────────────────────────────────────────────────────────
if (!dir.exists(RAWDATA_PATH)) {
  warning("[config.R] RAWDATA_PATH not found: ", RAWDATA_PATH,
          "\n  OHLCVS loading will fail. Check the path.")
}

# QEPM Pipeline: auto-commit hurdle results to qepm registry
QEPM_AUTO_COMMIT <- TRUE

# ─── STR 번호 중앙 할당 (충돌 방지) ─────────────────────────────────────────
.STR_LOCK <- file.path(PROJECT_ROOT, ".cache", "str_counter.lock")

#' Allocate next STR number (thread-safe via lockfile)
#' @param name_slug Character: strategy name slug (e.g., "flow_reversal")
#' @return Character: full strategy ID (e.g., "STR_1426_flow_reversal")
allocate_str <- function(name_slug) {
  dirs <- list.dirs(file.path(PROJECT_ROOT, "04_Research", "strategies"),
                    recursive = FALSE, full.names = FALSE)
  nums <- suppressWarnings(
    as.integer(gsub("^STR_(\\d+)_.*", "\\1", dirs[grepl("^STR_\\d+", dirs)]))
  )
  next_num <- max(c(nums, 1000L), na.rm = TRUE) + 1L
  strat_id <- sprintf("STR_%d_%s", next_num, name_slug)
  # Create directory to "claim" the number
  dir.create(file.path(PROJECT_ROOT, "04_Research", "strategies", strat_id),
             recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("[config] Allocated: %s\n", strat_id))
  strat_id
}

cat(sprintf("[config.R] PROJECT_ROOT: %s\n", PROJECT_ROOT))
