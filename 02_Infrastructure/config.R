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
#'
#' 2026-07-25 수리: 주석은 "thread-safe via lockfile"인데 `.STR_LOCK`이 **정의만 되고
#'   어디서도 쓰이지 않았다**(전역 grep 1히트 = 정의부). 병렬 세션/에이전트가 동시에
#'   호출하면 같은 max+1을 계산해 **같은 번호를 서로 다른 전략이 점유**한다 — 실측 7건
#'   (STR_1435×3·STR_1622×4·STR_1570/1571/1332/1562/1563×2). CLAUDE.md가 병렬 spawn을
#'   의무화하므로 재발 조건이 상시 존재. → `dir.create()`의 원자성으로 실제 뮤텍스 구현.
#'   번호 파싱도 접미사 없는 `STR_1234` 형태를 포함하도록 교정(종전 gsub는 NA 반환).
allocate_str <- function(name_slug, lock_timeout_sec = 30, lock_stale_sec = 300) {
  lock_dir <- .STR_LOCK
  dir.create(dirname(lock_dir), recursive = TRUE, showWarnings = FALSE)

  # ── 잠금 획득 (dir.create = 원자적. 이미 있으면 FALSE) ──
  t0 <- Sys.time(); acquired <- FALSE
  repeat {
    if (isTRUE(suppressWarnings(dir.create(lock_dir, showWarnings = FALSE)))) {
      acquired <- TRUE; break
    }
    # 죽은 프로세스가 남긴 잠금 회수 (교착 방지)
    age <- tryCatch(as.numeric(difftime(Sys.time(), file.info(lock_dir)$mtime, units = "secs")),
                    error = function(e) NA_real_)
    if (!is.na(age) && age > lock_stale_sec) {
      warning(sprintf("[config] STR 잠금 %.0f초 경과 — stale 판정 후 회수", age), call. = FALSE)
      unlink(lock_dir, recursive = TRUE, force = TRUE)
      next
    }
    if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > lock_timeout_sec)
      stop(sprintf("[config] STR 번호 잠금 획득 실패(%ds 대기) — 다른 세션이 할당 중. 재시도하세요.",
                   lock_timeout_sec), call. = FALSE)
    Sys.sleep(0.2)
  }
  if (acquired) on.exit(unlink(lock_dir, recursive = TRUE, force = TRUE), add = TRUE)

  strat_base <- file.path(PROJECT_ROOT, "04_Research", "strategies")
  dirs <- list.dirs(strat_base, recursive = FALSE, full.names = FALSE)
  hits <- dirs[grepl("^STR_\\d+($|_)", dirs)]
  nums <- suppressWarnings(as.integer(sub("^STR_(\\d+).*$", "\\1", hits)))
  next_num <- max(c(nums, 1000L), na.rm = TRUE) + 1L

  # 방어: 계산된 번호가 이미 점유돼 있으면(경합·수동 생성) 빈 번호까지 전진
  while (any(grepl(sprintf("^STR_%d($|_)", next_num), dirs))) next_num <- next_num + 1L

  strat_id <- sprintf("STR_%d_%s", next_num, name_slug)
  # Create directory to "claim" the number (잠금 보유 중에 점유 확정)
  dir.create(file.path(strat_base, strat_id), recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("[config] Allocated: %s\n", strat_id))
  strat_id
}

cat(sprintf("[config.R] PROJECT_ROOT: %s\n", PROJECT_ROOT))
