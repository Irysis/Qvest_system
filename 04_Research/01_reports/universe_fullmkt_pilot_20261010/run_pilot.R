## =============================================================================
## 전 시장 유니버스 파일럿 (2026-10-10)
##   계기: 도훈 "유니버스를 코스피+코스닥 전체로 넓혀보자" → "내게 묻지말고 자체판단으로 진행".
##   Q 판단: 고정 축(K200∪KQ150) 교체는 헌법 수준이라 위임 밖 — 먼저 **병행 실험**으로 잰다.
##
##   설계: 같은 충실구현 엔진을 두 판으로 측정하고 권위 등급(essence)을 맞댄다.
##     F (고정 축) = K200∪KQ150 멤버(PIT 시변) ∧ ADV20(t-1) ≥ 유동성 하한
##     W (전 시장) = RAWDATA 전 상장 종목      ∧ ADV20(t-1) ≥ 유동성 하한
##   두 판의 차이는 유니버스 하나뿐이다(같은 하네스·같은 데이터 판본·같은 유동성 정의·같은 비용).
##
##   처치 전달: 충실구현 엔진 32/32 가 유니버스를 RAWDATA 의 K200/KQ150 플래그로만 거른다
##     (B3 all_listed 칸이 2026-08-31 '영구 미전달'로 빠진 이유 — 기저 패널이 이미 잘려 있었다).
##     그래서 러너가 부르는 load_rawdata() 를 감싸, 적재 직후 두 플래그를 실험 멤버십으로 바꿔 끼운다.
##     엔진·러너 코드는 수정하지 않는다.
##   유동성: rf_cell_engine.R 과 같은 정의 — .TV = Close×Vol · shift(frollmean(.TV,20),1) (C10 t-1).
##     하한 = constraint_defaults.json::tier_soft_deployment.liquidity_min_won_20d_avg (하드코딩 없음).
##   PIT: 멤버십은 그날 행 존재 ∧ 전일까지의 20일 거래대금 — 미래 정보 없음. 상장폐지 종목 포함(C6).
##   운영 무오염: QVEST_RP_REGISTER=0(2계층 풀 등재 끔) · QVEST_RP_NO_LCODE=1 · QVEST_NO_LEDGER_OPEN=1 ·
##     send_telegram=FALSE · 산출 = 이 폴더 runs/ · A 등급이 나와도 judge_request.eligible.json 은
##     *.EXPERIMENT_HOLD.json 으로 이름을 바꿔 Judge 트리거가 되지 않게 한다(고정 축 밖 = A/BOOK 비적격).
##   호출: Rscript run_pilot.R [엔진ID ...]   (인자 없으면 아래 PILOT 전부)
## =============================================================================
suppressMessages(library(data.table))
suppressMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
EXP  <- file.path(ROOT, "04_Research/01_reports/universe_fullmkt_pilot_20261010")
RUNS <- file.path(EXP, "runs")
dir.create(RUNS, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(QVEST_RP_REGISTER = "0", QVEST_RP_NO_LCODE = "1", QVEST_NO_LEDGER_OPEN = "1")

DATA_CUTOFF <- "2026-09-30"   # 두 판 공통 데이터 판본(직전 완결 월말) — 판 사이 데이터 차이 제거
START_DATE  <- "2005-01-01"   # 고정 축 기간 그대로(기존 등급과 같은 창)

cd <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
LIQ_MIN <- as.numeric(cd$tier_soft_deployment$liquidity_min_won_20d_avg)
if (length(LIQ_MIN) != 1L || !is.finite(LIQ_MIN) || LIQ_MIN <= 0)
  stop("[univ-pilot] constraint_defaults.json::tier_soft_deployment.liquidity_min_won_20d_avg 판독 실패")

# 파일럿 엔진 8 — 유니버스를 K200|KQ150 합집합(또는 러너 필터)으로만 쓰는 엔진 중 계열이 다른 것들
PILOT <- list(
  list(id = "RP_AUTO_1505_00328",       url = "https://arxiv.org/abs/1505.00328"),
  list(id = "RP_AUTO_2404_08129",       url = "https://arxiv.org/abs/2404.08129"),
  list(id = "RP_AUTO_1707_05552",       url = "https://arxiv.org/abs/1707.05552"),
  list(id = "RP_AUTO_2302_10175",       url = "https://arxiv.org/abs/2302.10175"),
  list(id = "RP_AUTO_2505_20608",       url = "https://arxiv.org/abs/2505.20608"),
  list(id = "RP_AUTO_cond_mat_0410079", url = "https://arxiv.org/abs/cond-mat/0410079"),
  list(id = "RP_AUTO_2608_14014",       url = "https://arxiv.org/abs/2608.14014"),
  list(id = "RP_AUTO_CLEAN_2508_18592", url = "https://arxiv.org/abs/2508.18592")
)
args <- commandArgs(trailingOnly = TRUE)
if (length(args)) PILOT <- Filter(function(p) p$id %in% args, PILOT)

source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"))

# ── load_rawdata 감싸기: 적재 직후 K200/KQ150 플래그를 실험 멤버십으로 교체 ──────────────
.UNIV_ARM <- NA_character_
.orig_load_rawdata <- load_rawdata
load_rawdata <- function(...) {
  res <- .orig_load_rawdata(...)
  DT <- res$RAWDATA
  if (!inherits(DT$Date, "Date")) DT[, Date := as.Date(Date)]
  setorder(DT, Ticker, Date)
  DT[, .TV := as.numeric(Close) * as.numeric(Vol)]
  DT[, .adv20_l1 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]   # C10 t-1
  liq <- !is.na(DT$.adv20_l1) & DT$.adv20_l1 >= LIQ_MIN
  k <- !is.na(DT$K200)  & DT$K200  == 1
  q <- !is.na(DT$KQ150) & DT$KQ150 == 1
  n_before <- sum(k | q)
  if (identical(.UNIV_ARM, "W")) {
    DT[, K200 := as.numeric(liq)]; DT[, KQ150 := 0]
  } else if (identical(.UNIV_ARM, "F")) {
    DT[, K200 := as.numeric(k & liq)]; DT[, KQ150 := as.numeric(q & liq)]
  } else stop("[univ-pilot] .UNIV_ARM 미설정")
  DT[, c(".TV", ".adv20_l1") := NULL]
  n_after <- sum(DT$K200 == 1 | DT$KQ150 == 1)
  per_day <- DT[K200 == 1 | KQ150 == 1, .N, by = Date][, median(N)]
  cat(sprintf("[univ-pilot] arm=%s · 멤버 행 %d → %d · 하루 중앙 %d종 · 유동성 하한 %.0f원\n",
              .UNIV_ARM, n_before, n_after, as.integer(per_day), LIQ_MIN))
  res$RAWDATA <- DT
  res
}

.metrics <- function(out_dir) {
  f <- file.path(out_dir, "authoritative_remeasure.json")
  if (!file.exists(f)) return(list(grade = NA_character_))
  a <- fromJSON(f, simplifyVector = FALSE)
  e <- a$essence %||% list()
  list(grade = a$essence_grade %||% NA_character_,
       port_t = e$portfolio_alpha_t_nw_lag3 %||% NA, sharpe = e$net_sharpe %||% NA,
       cagr = e$cagr %||% NA, mdd = e$mdd %||% NA, calmar = e$calmar %||% NA,
       oos_retention = e$oos_retention %||% NA,
       n_max = a$replication$n_max %||% NA, has_short = a$replication$has_short %||% NA,
       defensive = a$defensive_score$defensive %||% NA)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

results_p <- file.path(EXP, "pilot_results.jsonl")
for (p in PILOT) {
  sdir <- file.path(ROOT, "04_Research/strategies", p$id)
  eng  <- file.path(sdir, "engine.R")
  fid  <- tryCatch(fromJSON(file.path(sdir, "FIDELITY.json"), simplifyVector = FALSE), error = function(e) list())
  pspec <- fid$portfolio_spec
  if (!is.null(pspec) && is.null(pspec$construction)) pspec <- NULL
  for (arm in c("F", "W")) {
    .UNIV_ARM <- arm   # 최상위 루프 = 전역 대입 — load_rawdata 감싸개가 전역에서 읽는다
    out_root <- file.path(RUNS, paste0(p$id, "_", arm))
    t0 <- Sys.time()
    cat(sprintf("\n##### [univ-pilot] %s arm=%s 시작 %s\n", p$id, arm, format(t0, "%H:%M:%S")))
    r <- tryCatch({
      run_paper_replication(
        strategy_name = sprintf("UNIV_%s_%s", sub("^RP_AUTO_", "", p$id), arm),
        strategy_idea = sprintf("[유니버스 파일럿 arm=%s] %s", arm, as.character(fid$kept %||% p$id)),
        factor_engine_path = eng, portfolio_spec = pspec, universe = "K200_KQ150",
        source_paper = list(url = p$url, paper_key = sub("^.*abs/", "", p$url)),
        commission_paper = fid$commission_paper, start_date = START_DATE,
        out_root = out_root, send_telegram = FALSE, data_cutoff = DATA_CUTOFF)
      "ok"
    }, error = function(e) paste("ERROR:", conditionMessage(e)))
    od <- list.dirs(out_root, recursive = FALSE)
    od <- if (length(od)) od[which.max(file.mtime(od))] else NA_character_
    # 고정 축 밖 판은 A/BOOK 비적격 — Judge 트리거가 되지 않게 이름을 바꾼다
    if (!is.na(od)) for (jr in c("judge_request.eligible.json", "judge_request.json")) {
      fj <- file.path(od, jr)
      if (file.exists(fj)) file.rename(fj, file.path(od, sub("\\.json$", ".EXPERIMENT_HOLD.json", jr)))
    }
    m <- if (!is.na(od)) .metrics(od) else list(grade = NA_character_)
    rec <- c(list(engine = p$id, arm = arm, status = r, out_dir = od,
                  minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1),
                  data_cutoff = DATA_CUTOFF, liq_min = LIQ_MIN), m)
    cat(toJSON(rec, auto_unbox = TRUE, na = "null"), "\n", file = results_p, append = TRUE)
    cat(sprintf("##### [univ-pilot] DONE %s arm=%s grade=%s (%s) %.1f분\n", p$id, arm,
                as.character(m$grade), r, rec$minutes))
    gc(verbose = FALSE)
  }
}
cat("\n##### [univ-pilot] ALL DONE\n")
