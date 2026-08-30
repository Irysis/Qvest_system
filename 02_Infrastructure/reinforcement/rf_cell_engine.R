#==============================================================================
# rf_cell_engine.R — 규칙기반 고속강화 **단일 파라미터 엔진** (무인화 정본, 2026-08-30)
#
# 왜 이 파일이 하나인가:
#   무인 러너가 셀마다 엔진 **코드를 생성**하면, 생성이 조용히 틀렸을 때 아무도 안 본다.
#   그래서 엔진은 하나이고 셀 스펙(JSON)만 바뀐다 — 검사 대상이 20개가 아니라 1개다.
#   셀 스펙 = 06_Registry/reinforce_program.json 의 한 칸 + 러너가 채운 런타임 필드.
#
# 계약:
#   입력  = 환경변수 RF_CELL_SPEC (셀 스펙 JSON 경로) + 호출자 env 의 RAWDATA / BM_DT
#           (run_paper_replication.R 이 source(local=fe_env) 로 주입한다)
#   출력  = FACTORS(Date,Ticker,Score)  또는  PORTFOLIO(Date,Ticker,Weight,Leg)
#           weighting 이 EW 면 FACTORS(선정은 러너가), 그 외면 PORTFOLIO(비중을 직접 산출)
#
# PIT (C1~C15 — 이 파일이 지키는 지점):
#   C1  전 표본 통계 없음. rank-Z 는 **그 시그널일 횡단면 안에서만**. sigma/공분산은 후행 창.
#   C2  모멘텀 = shift(Close,21)/shift(Close,252)-1  → 시그널일 당일 종가 미사용(12-1 skip 구조).
#   C10 유동성 = shift(frollmean(Close*Vol,20),1)    → 시그널일 당일 거래대금 미사용.
#   C13 부호 조작 없음. 팩터 DB 는 Z_Score_Aligned 만 소비(방향은 커넥터의 expanding IC 소관).
#   C15 팩터 DB parquet 직접 load 금지 — load_month_factors() 단일 경유.
#   C6  멤버십·시총·섹터 전부 그 시그널일 행에서 읽는다(생존 명부 사용 없음).
#
# ★sigma 계산 주의(2026-08-30 실측): 모멘트 항등식 (E[x^2]-E[x]^2) 은 분산이 진짜 0 인 종목
#   (60일 연속 동일수익 = 거래정지·상하한 고착)에서 소거오차로 sigma~1e-10 허수를 만들고,
#   w ~ 1/sigma 아래서 그 한 종목이 비중 100% 를 가져간다. **직접 sd() 만 쓴다.**
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.RF_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
.rf_spec_path <- Sys.getenv("RF_CELL_SPEC", "")
if (!nzchar(.rf_spec_path) || !file.exists(.rf_spec_path))
  stop("[rf_cell_engine] RF_CELL_SPEC 환경변수가 셀 스펙 JSON 을 가리켜야 합니다")
SPEC <- jsonlite::fromJSON(.rf_spec_path, simplifyVector = FALSE)

.AX <- SPEC$fixed_axes
.N_MAX   <- as.integer(.AX$n_max      %||% 25L)
.LIQ_MIN <- as.numeric(.AX$liq_adv20_min %||% 2e8)
.START   <- as.Date(.AX$start_date    %||% "2005-01-01")

stopifnot(is.data.table(RAWDATA))
DT <- RAWDATA
if (!inherits(DT$Date, "Date")) DT[, Date := as.Date(Date)]
setorder(DT, Ticker, Date)

# ── 1. 기저 신호 + 유동성 (일별 패널에서 과거 창만) ────────────────────────────
DT[, .TV := as.numeric(Close) * as.numeric(Vol)]
DT[, .adv20_l1 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]   # C10
DT[, .mom_12_1 := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]         # C2

# ── 기저 신호 (★2026-08-30 수리: 논문 독립성 회복) ────────────────────────────
#   구판은 mom_12_1 을 하드코딩하고 다른 값이면 stop 했다. 격자를 "논문 독립" 이라 써 놓고
#   기저를 모멘텀에 못 박아 둔 셈이라, 새 논문의 강화 20칸이 전부 **그 논문 신호가 아니라**
#   모멘텀 위에서 돌 뻔했다(무인 루프라 조용히 반복됐을 것 — 아직 미발화 상태에서 적발).
#   현행: 충실구현 엔진을 그대로 물려받는다. 그 엔진이 논문의 신호를 이미 구현해 뒀다.
.base <- SPEC$base_signal %||% list(kind = "mom_12_1")
if (identical(.base$kind, "mom_12_1")) {
  DT[, .base_sig := .mom_12_1]
} else if (identical(.base$kind, "engine")) {
  # 논문 충실구현 엔진 재사용 — 같은 계약(FACTORS/PORTFOLIO)이라 그대로 붙는다.
  #
  # ★기저 캐시 (도훈 지시 2026-08-30) — 강화 20칸은 **전부 같은 기저 신호**를 쓴다.
  #   셀마다 기저를 재계산하면 무거운 논문에서 20배를 버린다(실측: Lead-Lag 착안 엔진은
  #   월당 거리행렬 + KMeans K=2~10 silhouette + DTW 를 260개월 반복한다).
  #   ★PIT 를 깨지 않는다: 같은 시점 규약으로 한 번 만든 패널을 나눠 쓰는 것뿐이고,
  #     각 셀은 그 위에서 자기 유니버스·팩터·비중을 따로 적용한다. 창을 넓히거나
  #     미래 정보를 끌어오는 것이 아니다.
  #   ★캐시 키에 **엔진 내용 해시 + 데이터 판본**을 넣는다 — 둘 중 하나만 바뀌어도
  #     다른 키가 되어 자동 무효화된다. 이게 없으면 엔진을 고쳐도 옛 신호를 계속 쓴다.
  .be <- .base$path
  if (is.null(.be) || !file.exists(.be))
    stop("[rf_cell_engine] base_signal.path 부재: ", .be %||% "(NULL)")
  .cdir <- file.path(.RF_ROOT, ".cache", "rf_base_signal")
  dir.create(.cdir, recursive = TRUE, showWarnings = FALSE)
  .rawp <- file.path(.RF_ROOT, ".cache", "rawdata.parquet")
  .key <- paste(
    tryCatch(unname(tools::md5sum(.be)), error = function(e) "nohash"),
    tryCatch(as.character(file.info(.rawp)$mtime), error = function(e) "nomtime"),
    nrow(DT), as.character(.START), sep = "_")
  .key <- gsub("[^A-Za-z0-9]", "", .key)
  .cpath <- file.path(.cdir, paste0("base_", substr(.key, 1, 40), ".rds"))
  .bs <- NULL
  if (file.exists(.cpath)) {
    .bs <- tryCatch(readRDS(.cpath), error = function(e) NULL)
    if (!is.null(.bs)) cat(sprintf("[rf_cell_engine] 기저 캐시 적중 — %s (%d행)
",
                                   basename(.cpath), nrow(.bs)))
  }
  if (is.null(.bs)) {
    cat("[rf_cell_engine] 기저 캐시 미스 — 엔진 실행:", basename(.be), "
")
    .env <- new.env(parent = globalenv())
    .env$RAWDATA <- DT; .env$BM_DT <- if (exists("BM_DT")) BM_DT else NULL
    sys.source(.be, envir = .env)
    .bs <- if (exists("FACTORS", envir = .env, inherits = FALSE)) {
             x <- as.data.table(get("FACTORS", envir = .env)); setnames(x, "Score", ".base_sig"); x
           } else if (exists("PORTFOLIO", envir = .env, inherits = FALSE)) {
             x <- as.data.table(get("PORTFOLIO", envir = .env))
             x[, .(Date, Ticker, .base_sig = as.numeric(Weight))]
           } else stop("[rf_cell_engine] 기저 엔진이 FACTORS/PORTFOLIO 를 만들지 않았다: ", .be)
    .bs <- .bs[, .(Date, Ticker, .base_sig)]
    if (!nrow(.bs)) stop("[rf_cell_engine] 기저 엔진 산출이 비었다")
    tryCatch(saveRDS(.bs, .cpath), error = function(e)
      cat("[rf_cell_engine] 캐시 저장 실패(비치명):", conditionMessage(e), "
"))
    rm(.env); gc(verbose = FALSE)
  }
  DT <- merge(DT, .bs, by = c("Date", "Ticker"), all.x = TRUE)

} else stop("[rf_cell_engine] base_signal.kind 미지원: ", .base$kind)

# 시그널일 = 월말 거래일
.sig_dates <- DT[Date >= .START, .(d = max(Date)), by = .(ym = format(Date, "%Y%m"))]$d
.sig_dates <- sort(unique(.sig_dates))

# ── 2. 셀별 유니버스 (엔진이 자른다 — 러너는 K200_KQ150/INDEX 외 라벨을 통과시킨다) ──
.univ <- SPEC$universe %||% list(kind = "k200_kq150")
.universe_filter <- function(x) {
  k <- .univ$kind
  if (identical(k, "k200_kq150")) {
    if (!all(c("K200","KQ150") %in% names(x))) stop("[rf_cell_engine] K200/KQ150 멤버십 부재")
    x <- x[K200 == TRUE | KQ150 == TRUE]
  } else if (identical(k, "index")) {
    fl <- .univ$flag; if (!fl %in% names(x)) stop("[rf_cell_engine] 멤버십 열 부재: ", fl)
    x <- x[get(fl) == TRUE]
  } else if (identical(k, "all_listed")) {
    # 지수 멤버십 무제약 — 유동성 하한만
  } else if (identical(k, "size_band")) {
    if (!"Size" %in% names(x)) stop("[rf_cell_engine] Size 열 부재")
    # ★C1: 임계는 그 시그널일 횡단면 분위 — 전 표본 분위 금지. Size 는 t-1 값 사용(C2).
    x <- x[!is.na(.SizeLag)]
    x[, .q := frank(.SizeLag, ties.method = "average") / .N, by = Date]
    x <- x[.q > as.numeric(.univ$q_lo) & .q <= as.numeric(.univ$q_hi)]
    x[, .q := NULL]
  } else if (identical(k, "sector_neutral")) {
    if (!all(c("K200","KQ150") %in% names(x))) stop("[rf_cell_engine] K200/KQ150 멤버십 부재")
    x <- x[K200 == TRUE | KQ150 == TRUE]     # 유니버스는 유지, 중립화는 선정 단계에서
  } else stop("[rf_cell_engine] universe.kind 미지원: ", k)
  x
}

DT[, .SizeLag := shift(Size, 1L), by = Ticker]
PANEL <- DT[Date %in% .sig_dates & !is.na(.base_sig) &
            !is.na(.adv20_l1) & .adv20_l1 >= .LIQ_MIN]
PANEL <- .universe_filter(PANEL)

# ── 3. 제2팩터 ────────────────────────────────────────────────────────────────
# ── 3. 제2팩터~제N팩터 (★N-ary — 2026-08-30 도훈 "3팩터 이상으로도 결합할 수 있잖아") ──
#   구판은 factor2/factor3 를 하드코딩해 3에서 막혔다. 3 은 자의적 상한이었다.
#   현행: SPEC$factors = [{kind,id}, ...] 임의 길이. 구 factor2/factor3 도 그대로 받는다(하위호환).
#   결합 = 기저 신호 + 각 팩터의 **rank-Z 등가중 평균** (1/(1+n)). 비율 탐색은 별도 축.
.flist <- SPEC$factors
if (is.null(.flist)) {
  .flist <- Filter(Negate(is.null), list(SPEC$factor2, SPEC$factor3))
}
.flist <- Filter(function(f) !is.null(f) && !identical(f$kind, "none"), .flist)
.base_only <- (length(.flist) == 0L)

.load_factor <- function(fs, tag) {
  if (identical(fs$kind, "db")) {
    suppressMessages(source(file.path(.RF_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R")))
    L <- lapply(.sig_dates, function(d) {
      f <- tryCatch(load_month_factors(d, factor_names = fs$id), error = function(e) NULL)   # C15
      if (is.null(f) || !nrow(f)) return(NULL)
      f <- as.data.table(f)
      if (!"Z_Score_Aligned" %in% names(f)) return(NULL)                                     # C13
      out <- data.table(Date = as.Date(d), Ticker = f$Ticker, v = as.numeric(f$Z_Score_Aligned))
      setnames(out, "v", tag); out
    })
    rbindlist(Filter(Negate(is.null), L), use.names = TRUE)
  } else if (identical(fs$kind, "price")) {
    if (!identical(fs$id, "lowvol60")) stop("[rf_cell_engine] price factor 미지원: ", fs$id)
    if (!".sd60_l1" %in% names(DT)) {
      DT[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
      # ★직접 sd(), 창 종점 t-1 (C2). 모멘트 항등식 금지 — 퇴화 종목에서 허수 sigma 발생.
      DT[, .sd60_l1 := shift(frollapply(.ret, 60L, function(v) if (anyNA(v)) NA_real_ else sd(v),
                                        align = "right"), 1L), by = Ticker]
    }
    out <- DT[Date %in% .sig_dates & !is.na(.sd60_l1) & .sd60_l1 > 0, .(Date, Ticker, v = -.sd60_l1)]
    setnames(out, "v", tag); out
  } else stop("[rf_cell_engine] factor kind 미지원: ", fs$kind)
}

PANEL <- PANEL[, .(Date, Ticker, .base_sig, .SizeLag,
                   Sector = if ("Sector_Lv2" %in% names(PANEL)) Sector_Lv2 else NA_character_)]
.tags <- character(0)
if (!.base_only) {
  for (k in seq_along(.flist)) {
    tg <- paste0(".fv", k)
    PANEL <- merge(PANEL, .load_factor(.flist[[k]], tg), by = c("Date", "Ticker"))
    if (!nrow(PANEL)) stop("[rf_cell_engine] 팩터 ", k, " 결합 후 패널이 비었습니다 — 커버리지 확인")
    .tags <- c(.tags, tg)
  }
}

# ── 4. rank-Z 등가중 컴포짓 (C1: 그 날 횡단면 안에서만) ──────────────────────
.rz <- function(v) { r <- frank(v, ties.method = "average"); (r - mean(r)) / stats::sd(r) }
.grp <- if (identical(.univ$kind, "sector_neutral")) c("Date", "Sector") else "Date"
PANEL[, .zb := .rz(.base_sig), by = .grp]
# ★정규식 없이 이름을 직접 만든다 — 이 파일을 스크립트로 고치는 왕복에서 역슬래시가
#   반복해 뭉개졌다(2026-08-30). 결정론적 이름 생성이 이 맥락에서 더 견고하다.
.zt <- character(0)
for (k in seq_along(.tags)) {
  tg <- .tags[k]; zc <- paste0(".z", k)
  PANEL[, (zc) := .rz(get(tg)), by = .grp]
  .zt <- c(.zt, zc)
}
.zcols <- c(".zb", .zt)
PANEL[, Score := rowMeans(as.matrix(.SD), na.rm = TRUE), .SDcols = .zcols]
PANEL <- PANEL[is.finite(Score)]

# ── 5. 선정 + 비중 ────────────────────────────────────────────────────────────
.wt <- SPEC$weighting %||% list(kind = "ew")
.sector_neutral_pick <- function(x, n) {
  x <- x[order(-Score)]
  x[, .r := seq_len(.N), by = .(Date, Sector)]
  x[order(Date, .r, -Score)][, head(.SD, n), by = Date][, .r := NULL][]
}
SEL <- if (identical(.univ$kind, "sector_neutral")) {
  .sector_neutral_pick(PANEL, .N_MAX)
} else {
  PANEL[order(Date, -Score)][, head(.SD, .N_MAX), by = Date]
}

if (identical(.wt$kind, "ew")) {
  FACTORS <- SEL[, .(Date, Ticker, Score)]
} else {
  W <- switch(.wt$kind,
    "score_tilt" = SEL[, .(Ticker, w = { s <- Score - min(Score) + as.numeric(.wt$eps %||% 0.05); s / sum(s) }), by = Date],
    "rank_weight" = SEL[, .(Ticker, w = { r <- frank(-Score, ties.method = "first"); v <- (.N + 1 - r); v / sum(v) }), by = Date],
    "rank_weight_sqrt" = SEL[, .(Ticker, w = { r <- frank(-Score, ties.method = "first"); v <- sqrt(.N + 1 - r); v / sum(v) }), by = Date],
    "inv_vol" = {
      DT[, .ret2 := Close / shift(Close, 1L) - 1, by = Ticker]
      DT[, .sdw_l1 := shift(frollapply(.ret2, as.integer(.wt$window %||% 60L),
             function(v) if (anyNA(v)) NA_real_ else sd(v), align = "right"), 1L), by = Ticker]
      S2 <- merge(SEL[, .(Date, Ticker)], DT[, .(Date, Ticker, .sdw_l1)], by = c("Date","Ticker"))
      S2 <- S2[!is.na(.sdw_l1) & .sdw_l1 > 0]        # 퇴화 제외 (허수 sigma 차단)
      S2[, .(Ticker, w = (1 / .sdw_l1) / sum(1 / .sdw_l1)), by = Date]
    },
    "catalog" = {
      # ★B2 격자는 비중 카탈로그(등록 29종)를 소비한다. 그런데 그 다리가 없어서 B2 전 칸이
      #   "weighting.kind 미지원: catalog" 로 죽었다(2026-08-30 실사고 · 5칸 전멸).
      #   ★다리만 놓으면 안 된다 — lean 빌트인 arm 은 calc_*_weights 가 안 보이면
      #     wrap_adapter 가 **조용히 EW 로 폴백**한다(실측: 5종 중 4종). 그러면 이름만 다른
      #     EW 5벌을 "비중 방법론을 쟀다" 고 보고하게 된다. 그래서 ①하네스를 먼저 로드하고
      #     ②산출이 EW 면 측정을 끊는다(조작확인).
      #   ★하네스는 ./config.R 을 상대경로로 읽는다 — 작업 디렉터리를 옮겨 로드하고 되돌린다.
      #     (최상위 on.exit 은 이 파일에서 no-op 이므로 명시 복원한다)
      .owd <- getwd()
      .hl <- tryCatch({ setwd(file.path(.RF_ROOT, "02_Infrastructure"))
                        suppressMessages(suppressWarnings(source("backtest_harness.R"))); TRUE },
                      error = function(e) FALSE)
      setwd(.owd)
      if (!isTRUE(.hl) || !exists("calc_ivol_weights", mode = "function"))
        stop("[rf_cell_engine] backtest_harness.R 로드 실패 — lean 빌트인 arm 이 조용히 EW 로 폴백한다")
      suppressMessages(source(file.path(.RF_ROOT, "02_Infrastructure/portfolio/weight_catalog.R")))
      .cid <- as.character(.wt$catalog_id %||% "")
      .AR  <- weight_catalog_arms(quiet = TRUE)
      .row <- .AR[catalog_id == .cid]
      if (!nrow(.row)) stop("[rf_cell_engine] 카탈로그 arm 부재: ", .cid)
      .afn <- .row$adapter_fn[[1]]
      .LB  <- as.integer(.wt$lookback_days %||% 252L)
      if (!".ret" %in% names(DT)) DT[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
      .nEW <- 0L; .nOK <- 0L
      W <- rbindlist(lapply(.sig_dates, function(d) {
        nm <- SEL[Date == d, Ticker]
        if (length(nm) < 2L) return(NULL)
        H <- DT[Ticker %in% nm & Date < d, .(Date, Ticker, .ret)]   # C2: 창 종점 t-1
        if (!nrow(H)) return(NULL)
        M <- utils::tail(dcast(H, Date ~ Ticker, value.var = ".ret"), .LB)
        R <- as.matrix(M[, -1L, with = FALSE])
        keep <- colnames(R)[colSums(!is.finite(R)) == 0L]
        if (length(keep) < 2L) return(NULL)
        R <- R[, keep, drop = FALSE]
        mu <- SEL[Date == d][match(keep, Ticker), Score]
        ctx <- list(assets = keep, R = R, mu = stats::setNames(as.numeric(mu), keep),
                    Sigma = stats::cov(R), ub = 1, lookback_days = nrow(R),
                    decision_date = d, eval_date = d)
        w <- tryCatch(as.numeric(.afn(ctx)), error = function(e) NULL)
        if (is.null(w) || length(w) != length(keep) || !all(is.finite(w)) || sum(w) <= 0) return(NULL)
        w <- w / sum(w)
        if (stats::sd(w) < 1e-10) .nEW <<- .nEW + 1L else .nOK <<- .nOK + 1L
        data.table(Date = d, Ticker = keep, w = w)
      }), use.names = TRUE)
      if (is.null(W) || !nrow(W)) stop("[rf_cell_engine] 카탈로그 arm 이 어떤 시점에도 비중을 못 냈다: ", .cid)
      # ★조작확인 — 폴백이 조용하니 우리가 시끄럽게 만든다. 미전달은 '효과 없음' 이 아니라 '미측정' 이다.
      if (.nOK == 0L)
        stop(sprintf("[rf_cell_engine] arm %s 산출이 전 시점 EW 와 동일 — 처치 미전달(조용한 폴백). 측정 무효.", .cid))
      if (.nEW > .nOK)
        stop(sprintf("[rf_cell_engine] arm %s: EW 폴백 %d / 차별화 %d — 과반 미전달. 측정 무효.", .cid, .nEW, .nOK))
      .cov <- length(unique(W$Date)) / max(1L, length(.sig_dates))
      if (.cov < 0.8)
        stop(sprintf("[rf_cell_engine] arm %s 커버리지 %.1f%% (<80%%) — 침묵 부분측정 금지", .cid, 100 * .cov))
      cat(sprintf("[rf_cell_engine] catalog %s | 차별화 %d · EW폴백 %d · 커버리지 %.1f%%
",
                  .cid, .nOK, .nEW, 100 * .cov))
      W
    },
    stop("[rf_cell_engine] weighting.kind 미지원: ", .wt$kind))
  PORTFOLIO <- merge(SEL[, .(Date, Ticker)], W, by = c("Date","Ticker"))[
    , .(Date, Ticker, Weight = w, Leg = "LONG")]
  stopifnot(all(PORTFOLIO$Weight >= 0))
  .chk <- PORTFOLIO[, .(s = sum(Weight)), by = Date]
  stopifnot(max(abs(.chk$s - 1)) < 1e-8)
}

# ★N-ary 리팩터(2026-08-30) 후 이 줄만 구 변수(.f2/.f3)를 참조해 전 셀이
#   마지막 문장에서 죽었다(B1_1~5). 로그 한 줄이라 계산을 다 마친 뒤에 터진다 — .flist 로 정정.
cat(sprintf("[rf_cell_engine] cell=%s | univ=%s | factors=%s | wt=%s | months=%d | rows=%d\n",
            SPEC$code %||% "?", .univ$kind,
            if (.base_only) "none" else paste(vapply(.flist, function(f) f$id %||% "?", character(1)), collapse = "+"),
            .wt$kind,
            length(.sig_dates), if (exists("PORTFOLIO")) nrow(PORTFOLIO) else nrow(FACTORS)))
