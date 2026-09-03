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
#   기저를 모멘텀에 못 박아 둔 셈이라, 새 논문의 강화 25칸이 전부 **그 논문 신호가 아니라**
#   모멘텀 위에서 돌 뻔했다(무인 루프라 조용히 반복됐을 것 — 아직 미발화 상태에서 적발).
#   현행: 충실구현 엔진을 그대로 물려받는다. 그 엔진이 논문의 신호를 이미 구현해 뒀다.
.base <- SPEC$base_signal %||% list(kind = "mom_12_1")
if (identical(.base$kind, "mom_12_1")) {
  DT[, .base_sig := .mom_12_1]
} else if (identical(.base$kind, "engine") || identical(.base$kind, "engine_blend")) {
  # ★engine_blend — 논문 **간** 결합. 두 충실구현 엔진의 신호를 각각 만들고 월별 rank-Z 로
  #   정규화해 평균한다. 척도가 다른 두 신호를 그대로 더하면 분산 큰 쪽이 결합을 지배하므로
  #   순위 정규화가 필수다(격자 B4 는 같은 논문 **안**의 축 결합이라 이것과 다른 층이다).
  #   PIT: 각 엔진이 자기 시점 규약을 지키고, 평균은 같은 시그널일 횡단면 안에서만 일어난다.
  .load_one <- function(.be) {
    if (is.null(.be) || !file.exists(.be))
      stop("[rf_cell_engine] base_signal path 부재: ", .be %||% "(NULL)")
    .cdir <- file.path(.RF_ROOT, ".cache", "rf_base_signal")
    dir.create(.cdir, recursive = TRUE, showWarnings = FALSE)
    .rawp <- file.path(.RF_ROOT, ".cache", "rawdata.parquet")
    .key <- paste(tryCatch(unname(tools::md5sum(.be)), error = function(e) "nohash"),
                  tryCatch(as.character(file.info(.rawp)$mtime), error = function(e) "nomtime"),
                  nrow(DT), as.character(.START), sep = "_")
    .key <- gsub("[^A-Za-z0-9]", "", .key)
    .cpath <- file.path(.cdir, paste0("base_", substr(.key, 1, 40), ".rds"))
    .b <- NULL
    if (file.exists(.cpath)) {
      .b <- tryCatch(readRDS(.cpath), error = function(e) NULL)
      if (!is.null(.b)) cat(sprintf("[rf_cell_engine] 기저 캐시 적중 — %s (%d행)
",
                                    basename(.cpath), nrow(.b)))
    }
    if (is.null(.b)) {
      cat("[rf_cell_engine] 기저 캐시 미스 — 엔진 실행:", basename(.be), "
")
      .env <- new.env(parent = globalenv())
      .env$RAWDATA <- DT; .env$BM_DT <- if (exists("BM_DT")) BM_DT else NULL
      sys.source(.be, envir = .env)
      .b <- if (exists("FACTORS", envir = .env, inherits = FALSE)) {
              x <- as.data.table(get("FACTORS", envir = .env)); setnames(x, "Score", ".base_sig"); x
            } else if (exists("PORTFOLIO", envir = .env, inherits = FALSE)) {
              x <- as.data.table(get("PORTFOLIO", envir = .env))
              x[, .(Date, Ticker, .base_sig = as.numeric(Weight))]
            } else stop("[rf_cell_engine] 기저 엔진이 FACTORS/PORTFOLIO 를 만들지 않았다: ", .be)
      .b <- .b[, .(Date, Ticker, .base_sig)]
      if (!nrow(.b)) stop("[rf_cell_engine] 기저 엔진 산출이 비었다: ", .be)
      tryCatch(saveRDS(.b, .cpath), error = function(e)
        cat("[rf_cell_engine] 캐시 저장 실패(비치명):", conditionMessage(e), "
"))
      rm(.env); gc(verbose = FALSE)
    }
    .b
  }
  if (identical(.base$kind, "engine_blend")) {
    .paths <- unlist(.base$paths %||% list())
    if (length(.paths) < 2L)
      stop("[rf_cell_engine] engine_blend 는 엔진 2개 이상 필요 — 받은 수: ", length(.paths))
    .rz1 <- function(v) { r <- frank(v, ties.method = "average"); (r - mean(r)) / stats::sd(r) }
    .parts <- lapply(seq_along(.paths), function(k) {
      b <- copy(.load_one(.paths[k]))
      b <- b[is.finite(.base_sig)]
      b[, z := .rz1(.base_sig), by = Date]          # 월별 횡단면 rank-Z (C1: 그 날 안에서만)
      b[, .(Date, Ticker, z)]
    })
    .M <- Reduce(function(a, b) merge(a, b, by = c("Date", "Ticker"), all = FALSE), .parts)
    if (!nrow(.M))
      stop("[rf_cell_engine] engine_blend — 두 엔진의 공통 (Date,Ticker) 가 없다")
    .zc <- setdiff(names(.M), c("Date", "Ticker"))
    .M[, .base_sig := rowMeans(as.matrix(.SD)), .SDcols = .zc]
    .bs <- .M[, .(Date, Ticker, .base_sig)]
    cat(sprintf("[rf_cell_engine] engine_blend %d개 — 공통 %d행 (%s)
",
                length(.paths), nrow(.bs), paste(basename(.paths), collapse = " + ")))
  } else {
  # 논문 충실구현 엔진 재사용 — 같은 계약(FACTORS/PORTFOLIO)이라 그대로 붙는다.
  #
  # ★기저 캐시 (도훈 지시 2026-08-30) — 강화 25칸은 **전부 같은 기저 신호**를 쓴다.
  #   셀마다 기저를 재계산하면 무거운 논문에서 20배를 버린다(실측: Lead-Lag 착안 엔진은
  #   월당 거리행렬 + KMeans K=2~10 silhouette + DTW 를 260개월 반복한다).
  #   ★PIT 를 깨지 않는다: 같은 시점 규약으로 한 번 만든 패널을 나눠 쓰는 것뿐이고,
  #     각 셀은 그 위에서 자기 유니버스·팩터·비중을 따로 적용한다. 창을 넓히거나
  #     미래 정보를 끌어오는 것이 아니다.
  #   ★캐시 키에 **엔진 내용 해시 + 데이터 판본**을 넣는다 — 둘 중 하나만 바뀌어도
  #     다른 키가 되어 자동 무효화된다. 이게 없으면 엔진을 고쳐도 옛 신호를 계속 쓴다.
    .bs <- .load_one(.base$path)
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
    # 지수 멤버십 무제약 — 유동성 하한만.
    # ★처치 확인(2026-08-30 실측): 기저 신호가 지수 멤버 위에서만 정의돼 있으면 '멤버십 해제' 는
    #   넓힐 대상이 없다. B3_11 이 B1_5 와 보유 777/777 **완전 동일**한 포트폴리오를 내고도
    #   등급 B 를 받았다 — 처치 미전달인데 수치가 나온다. 그러면 블록 승자를 가짜가 가져갈 수 있다.
    #   (이 논문의 기저 엔진은 engine.R 에서 (K200|KQ150) 로 자기 유니버스를 이미 자른다)
    if (all(c("K200", "KQ150") %in% names(x))) {
      .n_idx <- nrow(x[K200 == TRUE | KQ150 == TRUE])
      if (identical(.n_idx, nrow(x)))
        stop("[rf_cell_engine] all_listed 후보가 지수 멤버와 동일 — 유니버스 처치 미전달",
             "(기저 신호 지지집합이 지수로 한정). 측정 무효 — 같은 포트폴리오에 다른 이름을 붙이지 않는다.")
    }
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
# ★기저 가중 w0 (2026-09-01 도훈 결정) — 등가중이면 팩터를 n개 얹을 때 논문 신호 가중이
#   1/(1+n) 로 떨어져(50/33/25/20/17%) **결합 깊이와 기저 희석이 교락된다**. 5팩터 칸이 져도
#   깊이가 나쁜 건지 논문 신호를 17%로 깎은 탓인지 분리할 수 없다. 실측 전례: 2026-08-31
#   승계에서 1/2 -> 1/3 희석만으로 B1 다섯 칸이 전부 부모 기준선(2.63)을 못 넘었다(최고 0.814).
#   w0 를 고정하면 깊이가 순수 축이 된다.
# ★기본값을 여기 박지 않는다 — 격자 fixed_axes 에서만 온다. 값 없는 구 스펙은 등가중 그대로
#   재현된다(사후 재현성 보존). 1팩터일 때 w0=0.5 는 rowMeans(2열)과 수치적으로 동일하다.
.w0 <- suppressWarnings(as.numeric(SPEC$base_weight %||% NA))
if (is.finite(.w0) && length(.zt)) {
  if (.w0 < 0 || .w0 > 1) stop("[rf_cell_engine] base_weight 는 [0,1]: ", .w0)
  PANEL[, .zfac := rowMeans(as.matrix(.SD), na.rm = TRUE), .SDcols = .zt]
  PANEL[, Score := .w0 * .zb + (1 - .w0) * .zfac]
} else {
  PANEL[, Score := rowMeans(as.matrix(.SD), na.rm = TRUE), .SDcols = .zcols]
}
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

# ── 5.5 리스크 오버레이 (도훈 지시 2026-08-30) ────────────────────────────────
#   "오버레이 계층은 없나? PG2의 성공도 오버레이인데" + "논문이 없어도 진행되게.
#    통계/수학/머신러닝 방법론 적극 활용으로 리스크 컨트롤 목적의 오버레이 설계"
#
#   왜 여기가 자리인가: B1~B3 15칸이 MDD 61.6~77.2% 대역에 갇혀 Calmar 0.34/0.64 로
#   A 를 못 연다. 신호를 더 깎아도 안 열린다 — 구속 축이 낙폭이기 때문이다.
#
#   ★구현 = 노출 스케일(Sigma w <= 1, 나머지 현금). 하네스가 gross exposure 를 그대로
#     반영하므로(replication_harness.R 의 Rg = GL*Lr) 비중 축소가 곧 현금 보유다.
#   ★PIT(C5): 신호는 BM/시장 시계열이고 창 종점 = 시그널일 d(월말). 홀딩은 익월부터라
#     교집합이 없다. assert_overlay_pit 로 하드 통과. 적합·분위·임계는 전부 확장창이다.
#   ★임의 상수 금지: 목표변동성·게이트 문턱·EWMA lambda 를 숫자로 박지 않는다. 전부 그
#     시점까지의 데이터에서 추정한다. 상수를 박으면 그게 곧 사후 선택이다.
.ov      <- SPEC$overlay
.ov_kind <- if (is.null(.ov)) "none" else as.character(.ov$kind %||% "none")
if (!identical(.ov_kind, "none")) {
  if (!exists("BM_DT")) stop("[rf_cell_engine] overlay 는 BM_DT 를 요구한다(호출자 env)")
  suppressMessages(source(file.path(.RF_ROOT, "02_Infrastructure/validation/overlay_pit_guard.R")))
  .sdna <- function(v) if (anyNA(v)) NA_real_ else stats::sd(v)
  .B <- as.data.table(BM_DT)[is.finite(BM_Ret), .(Date = as.Date(Date), BM_Ret = as.numeric(BM_Ret))]
  setorder(.B, Date)
  .B[, nav := cumprod(1 + BM_Ret)]
  .B[, dd  := 1 - nav / cummax(nav)]
  .B[, rv20  := frollapply(BM_Ret,  20L, .sdna, align = "right") * sqrt(252)]
  .B[, rv60  := frollapply(BM_Ret,  60L, .sdna, align = "right") * sqrt(252)]
  .B[, rv120 := frollapply(BM_Ret, 120L, .sdna, align = "right") * sqrt(252)]
  .B[, r252 := nav / shift(nav, 252L) - 1]

  # EWMA(lambda) 변동성 — lambda 를 상수로 박지 않고 격자에서 데이터가 고르게 한다
  .lams <- seq(0.90, 0.99, by = 0.01)
  .ew <- lapply(.lams, function(lam) {
    x <- .B$BM_Ret; n <- length(x); s <- numeric(n); s[1] <- x[1]^2
    for (i in 2:n) s[i] <- lam * s[i - 1] + (1 - lam) * x[i - 1]^2
    sqrt(s) * sqrt(252)
  })

  # 횡단면 분산(난기류 특징) — 그날 종목 수익의 표준편차.
  # ★RAWDATA 의 Ret 열에 의존하지 않는다 — 엔진이 스스로 만드는 .ret 을 쓴다(픽스처·패널 무관 동작).
  if (!".ret" %in% names(DT)) DT[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
  .XS <- DT[is.finite(.ret), .(xs = stats::sd(.ret, na.rm = TRUE)), by = Date]

  # 월별 특징표(시그널일 기준). 학습·분위는 여기서 확장창으로만 쓴다.
  .M <- data.table(Date = .sig_dates)
  .M <- .M[Date >= min(.B$Date) & Date <= max(.B$Date)]
  .M[, i := findInterval(Date, .B$Date)]
  .M <- .M[i > 0]
  .M[, rv20  := .B$rv20[i]]
  .M[, rv60  := .B$rv60[i]]
  .M[, rv120 := .B$rv120[i]]
  .M[, dd    := .B$dd[i]]
  .M[, r252  := .B$r252[i]]
  .M[, nav   := .B$nav[i]]
  for (k in seq_along(.lams)) .M[, (paste0("ew", k)) := .ew[[k]][i]]
  .M <- merge(.M, .XS, by = "Date", all.x = TRUE)
  setorder(.M, Date)
  .M[, fwd := shift(nav, 1L, type = "lead") / nav - 1]   # 익월 BM 수익 — 학습에만, 과거쌍만 사용

  .N <- nrow(.M)
  .clip <- function(x) max(0, min(1, x))
  .expo   <- rep(1, .N)
  .expo_x <- vector("list", .N)   # 월별 종목 노출(횡단면 비대칭 arm 전용). NULL = 그 달은 스칼라

  # ★절벽형 워밍업 금지 (2026-08-30 실측): 첫 판은 60개월 미만을 통째로 무개입으로 뒀는데,
  #   그 창(2005-02~2010-05)에 **최대낙폭 에피소드(2008-05~2008-10)가 통째로 들어간다**.
  #   그러면 낙폭을 만든 구간에서는 안 걸고 수익을 만든 구간에서만 조이게 되어, 다섯 팔의 MDD 가
  #   56.3% 로 완전히 동일해지고 CAGR 만 20.8%→4.5~7.9% 로 무너졌다. 오버레이의 결과가 아니라
  #   계기의 결함이다.
  #   수리 = 절벽 대신 **축소(shrinkage)**. 표본이 적으면 개입을 부분만 반영하고 표본이 쌓일수록
  #   완전 반영한다: e = 1 - w * (1 - e_raw), w = min(1, n / n_min). 통계적으로도 이게 옳다 —
  #   추정 불확실성이 큰 구간에서 무개입(사전평균)으로 끌어당기는 것이 축소 추정의 정의다.
  # ── ★파일 기반 arm 디스패치 (v10.2 2026-09-03) ──────────────────────────────
  #   왜: 구판은 kind 를 추가하려면 이 파일의 if/else 사슬을 편집해야 했다. 그러면 생성기(LLM)가
  #   **측정 경로 자체**를 편집하게 된다. arm 을 파일 하나로 격리하면 생성 세션의 쓰기 범위를
  #   overlay_arms/ 한 디렉터리로 묶을 수 있다(--add-dir 하나).
  #   ★기존 10 kind 는 위 사슬이 먼저 처리하므로 여기 오지 않는다 — 구 경로 무변경.
  .OV_BUILTIN <- c("vol_scale", "ewma_vol", "har_vol", "turbulence", "ml_tail_gate",
                   "ts_mom_gate", "dd_recovery", "vol_x_turb", "dd_brake", "vol_x_dd")
  .OV_FN <- NULL
  if (!.ov_kind %in% .OV_BUILTIN) {
    .ov_file <- file.path(.RF_ROOT, "02_Infrastructure/reinforcement/overlay_arms",
                          paste0(.ov_kind, ".R"))
    if (!file.exists(.ov_file))
      stop("[rf_cell_engine] overlay.kind 미지원: ", .ov_kind,
           " — overlay_arms/", .ov_kind, ".R 도 없다")
    .ov_env <- new.env(parent = globalenv())
    source(.ov_file, local = .ov_env)          # ★sys.source 는 ofile 이 없다 — source(local=) 사용
    .fn_name <- paste0("overlay_expo_", .ov_kind)
    if (!exists(.fn_name, envir = .ov_env, inherits = FALSE))
      stop(sprintf("[rf_cell_engine] %s 에 %s() 가 없다 — arm 계약 위반", basename(.ov_file), .fn_name))
    .OV_FN <- get(.fn_name, envir = .ov_env)
    if (!is.function(.OV_FN)) stop("[rf_cell_engine] ", .fn_name, " 가 함수가 아니다")
  }

  .n_min <- switch(.ov_kind,
    "har_vol" = 48L, "ml_tail_gate" = 48L, "turbulence" = 36L, "ewma_vol" = 36L, 24L)
  # ── ★종목 수준 상태 (v10.2 2026-09-03 · Phase 0-c) ──────────────────────────
  #   누적합 기반 확장창 통계. 각 신호일 d 에서 d 까지의 모든 관측만 쓴다(홀딩월은 익월이라 교집합 0).
  #   beta/dbeta 는 (n·Sxy − Sx·Sy)/(n·Syy − Sy²) 형태로 O(n) 에 나온다.
  .HOLD <- NULL
  if (!is.null(.OV_FN)) {
    if (!exists("PORTFOLIO")) {              # EW 셀은 FACTORS 만 있다 — 보유를 여기서 확정한다
      PORTFOLIO <- SEL[, .(Ticker, Weight = 1 / .N), by = Date][, .(Date, Ticker, Weight, Leg = "LONG")]
    }
    .HB <- merge(DT[is.finite(.ret), .(Date, Ticker, x = .ret)],
                 .B[, .(Date, y = BM_Ret)], by = "Date")
    setorder(.HB, Ticker, Date)
    .HB[, `:=`(
      n_   = seq_len(.N),
      Sx   = cumsum(x),      Sy   = cumsum(y),
      Sxx  = cumsum(x * x),  Syy  = cumsum(y * y),  Sxy = cumsum(x * y),
      dn_  = cumsum(y < 0),
      dSx  = cumsum(fifelse(y < 0, x,     0)),
      dSy  = cumsum(fifelse(y < 0, y,     0)),
      dSyy = cumsum(fifelse(y < 0, y * y, 0)),
      dSxy = cumsum(fifelse(y < 0, x * y, 0))
    ), by = Ticker]
    .HF <- .HB[PORTFOLIO[, .(Date, Ticker)], on = .(Ticker, Date), roll = TRUE]  # d 이하 최종 관측
    .MINOBS <- 250L                          # 1년 미만 표본으로는 베타를 말하지 않는다
    .HF[, `:=`(
      beta  = fifelse(n_  >= .MINOBS & (n_  * Syy  - Sy^2)  > 0,
                      (n_  * Sxy  - Sx  * Sy)  / (n_  * Syy  - Sy^2),  NA_real_),
      dbeta = fifelse(dn_ >= 60L      & (dn_ * dSyy - dSy^2) > 0,
                      (dn_ * dSxy - dSx * dSy) / (dn_ * dSyy - dSy^2), NA_real_),
      ovol  = fifelse(n_  >= .MINOBS & n_ > 1L,
                      sqrt(pmax(0, (Sxx - Sx^2 / n_) / (n_ - 1))) * sqrt(252), NA_real_)
    )]
    .HF[, bcorr := fifelse(n_ >= .MINOBS & (Sxx - Sx^2 / n_) > 0 & (Syy - Sy^2 / n_) > 0,
                           (Sxy - Sx * Sy / n_) /
                             sqrt((Sxx - Sx^2 / n_) * (Syy - Sy^2 / n_)), NA_real_)]
    .HOLD <- .HF[, .(Date, Ticker, beta, dbeta, ovol, bcorr, n_obs = n_)]
    setkey(.HOLD, Date)
    cat(sprintf("[rf_cell_engine] .HOLD %d행 · 종목상태 4축(beta·dbeta·ovol·bcorr) · 최소관측 %d",
                nrow(.HOLD), .MINOBS), fill = TRUE)
  }

  .n_floor <- 12L                              # 이 아래로는 표본이라 부르지 않는다
  for (t in seq_len(.N)) {
    if (t < .n_floor) next
    H <- .M[seq_len(t)]                        # ★확장창 = d 까지. 미래 행 접근 없음
    v_now <- H$rv60[t]
    tgt   <- stats::median(H$rv60, na.rm = TRUE)          # 목표 = 자기 이력 중앙 변동성
    e <- 1
    .ov_ctx <- if (is.null(.OV_FN)) NULL else list(
      t = t, date = .M$Date[t], v_now = v_now, tgt = tgt, n_min = .n_min,
      hold = if (!is.null(.HOLD)) .HOLD[J(.M$Date[t]), nomatch = 0L] else NULL)
    if (identical(.ov_kind, "vol_scale")) {
      e <- if (is.finite(v_now) && v_now > 0 && is.finite(tgt)) min(1, tgt / v_now) else 1

    } else if (identical(.ov_kind, "ewma_vol")) {
      best <- NA_integer_; bmse <- Inf         # lambda 선택 = 1개월 앞 예측 MSE 최소(과거쌍만)
      for (k in seq_along(.lams)) {
        pr <- H[[paste0("ew", k)]][-t]; ac <- H$rv20[-1]
        m <- suppressWarnings(mean((pr - ac)^2, na.rm = TRUE))
        if (is.finite(m) && m < bmse) { bmse <- m; best <- k }
      }
      s_hat <- if (is.na(best)) v_now else H[[paste0("ew", best)]][t]
      e <- if (is.finite(s_hat) && s_hat > 0 && is.finite(tgt)) min(1, tgt / s_hat) else 1

    } else if (identical(.ov_kind, "har_vol")) {
      tr <- H[is.finite(rv20) & is.finite(rv60) & is.finite(rv120)]
      tr[, y := shift(log(rv20), 1L, type = "lead")]
      tr <- tr[is.finite(y)]
      if (nrow(tr) >= 40L) {
        fit <- tryCatch(stats::lm(y ~ log(rv20) + log(rv60) + log(rv120), data = tr),
                        error = function(z) NULL)
        if (!is.null(fit)) {
          nd <- H[t, .(rv20, rv60, rv120)]
          if (all(is.finite(unlist(nd))) && all(unlist(nd) > 0)) {
            s_hat <- tryCatch(exp(as.numeric(stats::predict(fit, nd))), error = function(z) NA_real_)
            if (is.finite(s_hat) && s_hat > 0 && is.finite(tgt)) e <- min(1, tgt / s_hat)
          }
        }
      }

    } else if (identical(.ov_kind, "turbulence")) {
      FM <- as.matrix(H[, .(rv60, xs, dd)])
      FM <- FM[stats::complete.cases(FM), , drop = FALSE]
      if (nrow(FM) >= 60L) {
        mu <- colMeans(FM); S <- stats::cov(FM) + diag(1e-12, ncol(FM))
        Si <- tryCatch(solve(S), error = function(z) NULL)
        if (!is.null(Si)) {
          d2 <- apply(FM, 1L, function(r) as.numeric(t(r - mu) %*% Si %*% (r - mu)))
          q <- stats::quantile(d2, c(0.5, 0.9), na.rm = TRUE, names = FALSE)
          now <- d2[length(d2)]
          e <- if (!is.finite(now) || now <= q[1]) 1 else
               if (now >= q[2]) 0 else 1 - (now - q[1]) / max(1e-9, q[2] - q[1])
        }
      }

    } else if (identical(.ov_kind, "ml_tail_gate")) {
      tr <- H[seq_len(t - 1L)]                 # 결과가 실현된 과거쌍만
      tr <- tr[is.finite(fwd) & is.finite(rv60) & is.finite(dd) & is.finite(r252) & is.finite(xs)]
      if (nrow(tr) >= 60L) {
        thr <- stats::quantile(tr$fwd, 0.10, na.rm = TRUE, names = FALSE)
        tr[, bad := as.integer(fwd <= thr)]
        if (sum(tr$bad) >= 5L && sum(tr$bad) < nrow(tr)) {
          fit <- tryCatch(suppressWarnings(stats::glm(bad ~ rv60 + dd + r252 + xs,
                            data = tr, family = stats::binomial())), error = function(z) NULL)
          if (!is.null(fit)) {
            nd <- H[t, .(rv60, dd, r252, xs)]
            if (all(is.finite(unlist(nd)))) {
              pp <- tryCatch(as.numeric(stats::predict(fit, nd, type = "response")),
                             error = function(z) NA_real_)
              if (is.finite(pp)) e <- .clip(1 - pp)
            }
          }
        }
      }

    } else if (identical(.ov_kind, "ts_mom_gate")) {
      e <- if (is.finite(H$r252[t]) && H$r252[t] < 0) 0 else 1        # 12개월 부호(롱온리 → 현금)

    } else if (identical(.ov_kind, "dd_recovery")) {
      dq <- stats::quantile(H$dd, c(0.5), na.rm = TRUE, names = FALSE)
      dn <- H$dd[t]
      rr <- if (t >= 2L) H$nav[t] / H$nav[t - 1L] - 1 else NA_real_   # 직전 1개월 BM 수익
      e <- if (!is.finite(dn) || dn <= dq[1]) 1 else if (is.finite(rr) && rr > 0) 1 else 0

    } else if (identical(.ov_kind, "vol_x_turb")) {
      ev <- if (is.finite(v_now) && v_now > 0 && is.finite(tgt)) min(1, tgt / v_now) else 1
      et <- 1
      FM <- as.matrix(H[, .(rv60, xs, dd)])
      FM <- FM[stats::complete.cases(FM), , drop = FALSE]
      if (nrow(FM) >= 60L) {
        mu <- colMeans(FM); S <- stats::cov(FM) + diag(1e-12, ncol(FM))
        Si <- tryCatch(solve(S), error = function(z) NULL)
        if (!is.null(Si)) {
          d2 <- apply(FM, 1L, function(r) as.numeric(t(r - mu) %*% Si %*% (r - mu)))
          q <- stats::quantile(d2, c(0.5, 0.9), na.rm = TRUE, names = FALSE)
          nw <- d2[length(d2)]
          et <- if (!is.finite(nw) || nw <= q[1]) 1 else
                if (nw >= q[2]) 0 else 1 - (nw - q[1]) / max(1e-9, q[2] - q[1])
        }
      }
      e <- ev * et

    } else if (identical(.ov_kind, "dd_brake")) {
      dq <- stats::quantile(H$dd, c(0.5, 0.9), na.rm = TRUE, names = FALSE)
      dn <- H$dd[t]
      e <- if (!is.finite(dn) || dn <= dq[1]) 1 else
           if (dn >= dq[2]) 0 else 1 - (dn - dq[1]) / max(1e-9, dq[2] - dq[1])

    } else if (identical(.ov_kind, "vol_x_dd")) {
      ev <- if (is.finite(v_now) && v_now > 0 && is.finite(tgt)) min(1, tgt / v_now) else 1
      dq <- stats::quantile(H$dd, c(0.5, 0.9), na.rm = TRUE, names = FALSE)
      dn <- H$dd[t]
      ed <- if (!is.finite(dn) || dn <= dq[1]) 1 else
            if (dn >= dq[2]) 0 else 1 - (dn - dq[1]) / max(1e-9, dq[2] - dq[1])
      e <- ev * ed

    } else if (!is.null(.OV_FN)) {
      # 파일 기반 arm — 스칼라 e 또는 data.table(Ticker, e) 를 돌려줄 수 있다.
      e <- .OV_FN(H, t, .ov_ctx)
    } else stop("[rf_cell_engine] overlay.kind 미지원: ", .ov_kind)
    .w <- min(1, t / .n_min)                   # 표본 축소 가중 — 절벽 없음
    if (is.data.frame(e)) {
      # ★횡단면 비대칭 arm — 종목별 노출. 축소 가중은 종목마다 동일하게 적용한다.
      .ex <- as.data.table(e)
      if (!all(c("Ticker", "e") %in% names(.ex)))
        stop("[rf_cell_engine] arm 반환표에 Ticker/e 열이 없다: ", .ov_kind)
      .ex[, oe := vapply(1 - .w * (1 - vapply(e, .clip, numeric(1))), .clip, numeric(1))]
      .ex <- .ex[is.finite(oe), .(Ticker = as.character(Ticker), oe)]
      if (nrow(.ex)) {
        .expo_x[[t]] <- .ex
        .expo[t] <- mean(.ex$oe)               # 요약·로그용 대표값(판정은 아래 두 축을 함께 본다)
      }
    } else {
      .expo[t] <- .clip(1 - .w * (1 - .clip(e)))
    }
  }

  if (!exists("PORTFOLIO")) {                  # EW 셀은 FACTORS 만 있으므로 여기서 비중을 만든다
    PORTFOLIO <- SEL[, .(Ticker, Weight = 1 / .N), by = Date][, .(Date, Ticker, Weight, Leg = "LONG")]
  }
  # ★벡터 여부는 arm 이 실제로 종목표를 냈는가로 정한다(선언이 아니라 산출로).
  .VEC <- any(!vapply(.expo_x, is.null, logical(1)))
  if (.VEC) {
    # 스칼라만 낸 달은 그 달 보유 전 종목으로 펼쳐 하나의 (Date,Ticker,oe) 표로 만든다.
    .EX <- rbindlist(lapply(seq_len(.N), function(k) {
      if (!is.null(.expo_x[[k]]))
        data.table(Date = .M$Date[k], Ticker = .expo_x[[k]]$Ticker, oe = .expo_x[[k]]$oe)
      else {
        .tk <- PORTFOLIO[Date == .M$Date[k], unique(as.character(Ticker))]
        if (!length(.tk)) NULL else data.table(Date = .M$Date[k], Ticker = .tk, oe = .expo[k])
      }
    }), use.names = TRUE)
  } else {
    .EX <- data.table(Date = .M$Date, oe = .expo)
  }
  # 홀딩월 시작 = 익월 1일(캘린더). ★d+1 을 month 로 자르면 월말이 거래일 기준일 때 같은 달이 나온다
  #   ★신호일 집합(.M$Date)으로 판정한다 — 벡터판은 .EX$Date 가 종목 수만큼 반복되므로.
  .hs <- as.Date(vapply(.M$Date, function(x)
           as.character(seq(as.Date(format(x, "%Y-%m-01")), by = "month", length.out = 2L)[2L]),
           character(1)))
  assert_overlay_pit(.M$Date, .hs, label = paste0("rf_cell:", .ov_kind))

  # ★처치 확인 — 2축이다. 시간축 변동이 없어도 **횡단면 변동**이 있으면 처치는 전달된 것이다.
  #   스칼라 arm 은 .x_var == 0 이라 구판 조건(sd<1e-12 || mean>=1-1e-12)과 정확히 동치로 떨어진다.
  .t_var <- stats::sd(.expo, na.rm = TRUE)
  .x_var <- if (.VEC) max(vapply(.expo_x, function(z)
                if (is.null(z) || nrow(z) < 2L) 0 else stats::sd(z$oe), numeric(1)), na.rm = TRUE) else 0
  if ((!is.finite(.t_var) || .t_var < 1e-12) && .x_var < 1e-12)
    stop(sprintf("[rf_cell_engine] overlay %s 노출이 상수 — 처치 미전달. 측정 무효.", .ov_kind))
  if (mean(.expo, na.rm = TRUE) >= 1 - 1e-12 && .x_var < 1e-12)
    stop(sprintf("[rf_cell_engine] overlay %s 노출이 상시 1 — 처치 미전달. 측정 무효.", .ov_kind))
  if (.VEC && .x_var < 1e-12)
    cat("[rf_cell_engine] ★경고 — 벡터 arm 인데 횡단면 분산 0: 스칼라와 동치다(비대칭 미전달)", fill = TRUE)

  if (.VEC) {
    PORTFOLIO <- merge(PORTFOLIO, .EX, by = c("Date", "Ticker"), all.x = TRUE)
    .cov <- mean(!is.na(PORTFOLIO$oe))
    if (!is.finite(.cov) || .cov < 0.8)
      stop(sprintf("[rf_cell_engine] overlay %s 종목 커버리지 %.2f < 0.80 — arm 이 보유를 못 덮었다.",
                   .ov_kind, .cov))
    PORTFOLIO[is.na(oe), oe := 1]              # arm 이 지목하지 않은 종목 = 무개입
  } else {
    PORTFOLIO <- merge(PORTFOLIO, .EX, by = "Date")
  }
  PORTFOLIO[, Weight := Weight * oe]
  PORTFOLIO[, oe := NULL]
  PORTFOLIO <- PORTFOLIO[is.finite(Weight) & Weight > 0]
  if (!nrow(PORTFOLIO)) stop("[rf_cell_engine] overlay 적용 후 보유가 비었다: ", .ov_kind)
  stopifnot(all(PORTFOLIO$Weight >= 0))
  stopifnot(max(PORTFOLIO[, .(s = sum(Weight)), by = Date]$s) <= 1 + 1e-8)   # Sigma w <= 1
  if (exists("FACTORS")) rm(FACTORS)
  cat(sprintf("[rf_cell_engine] overlay %s | 축 %s | 평균노출 %.3f · 최소 %.3f · 완전현금 %d/%d개월%s",
              .ov_kind, if (.VEC) "종목별" else "스칼라",
              mean(.expo, na.rm = TRUE), min(.expo, na.rm = TRUE),
              sum(.expo <= 1e-12, na.rm = TRUE), .N,
              if (.VEC) sprintf(" · 횡단면 sd 최대 %.3f", .x_var) else ""), fill = TRUE)
}

# ★N-ary 리팩터(2026-08-30) 후 이 줄만 구 변수(.f2/.f3)를 참조해 전 셀이
#   마지막 문장에서 죽었다(B1_1~5). 로그 한 줄이라 계산을 다 마친 뒤에 터진다 — .flist 로 정정.
cat(sprintf("[rf_cell_engine] cell=%s | univ=%s | factors=%s | wt=%s | months=%d | rows=%d\n",
            SPEC$code %||% "?", .univ$kind,
            if (.base_only) "none" else paste(vapply(.flist, function(f) f$id %||% "?", character(1)), collapse = "+"),
            .wt$kind,
            length(.sig_dates), if (exists("PORTFOLIO")) nrow(PORTFOLIO) else nrow(FACTORS)))
