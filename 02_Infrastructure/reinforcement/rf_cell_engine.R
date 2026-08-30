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

.base <- SPEC$base_signal %||% list(kind = "mom_12_1")
if (!identical(.base$kind, "mom_12_1"))
  stop("[rf_cell_engine] base_signal.kind='", .base$kind, "' 미지원 — 현재 mom_12_1 만 (논문 교체 시 확장 지점)")
DT[, .base_sig := .mom_12_1]

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
.f2 <- SPEC$factor2
if (is.null(.f2)) stop("[rf_cell_engine] factor2 스펙 필수")
if (identical(.f2$kind, "none")) {
  # ★LOO(팩터 제외) 전용: 제2팩터 없이 **기저 신호 단독**. 컴포짓을 만들지 않는다.
  #   이게 없으면 "팩터 제외" 가 폴백 팩터로 대체돼 제외가 공허해진다(2026-08-30 적발).
  F2 <- PANEL[, .(Date, Ticker, .f2 = NA_real_)]
} else if (identical(.f2$kind, "db")) {
  suppressMessages(source(file.path(.RF_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R")))
  .f2_list <- lapply(.sig_dates, function(d) {
    f <- tryCatch(load_month_factors(d, factor_names = .f2$id), error = function(e) NULL)   # C15
    if (is.null(f) || !nrow(f)) return(NULL)
    f <- as.data.table(f)
    zc <- if ("Z_Score_Aligned" %in% names(f)) "Z_Score_Aligned" else NA_character_          # C13
    if (is.na(zc)) return(NULL)
    data.table(Date = as.Date(d), Ticker = f$Ticker, .f2 = as.numeric(f[[zc]]))
  })
  F2 <- rbindlist(Filter(Negate(is.null), .f2_list), use.names = TRUE)
} else if (identical(.f2$kind, "price")) {
  if (!identical(.f2$id, "lowvol60")) stop("[rf_cell_engine] price factor2 미지원: ", .f2$id)
  DT[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]
  # ★직접 sd(), 창 종점 t-1 (C2). 모멘트 항등식 금지 — 퇴화 종목에서 허수 sigma 발생.
  DT[, .sd60_l1 := shift(frollapply(.ret, 60L, function(v) if (anyNA(v)) NA_real_ else sd(v),
                                    align = "right"), 1L), by = Ticker]
  F2 <- DT[Date %in% .sig_dates & !is.na(.sd60_l1) & .sd60_l1 > 0,
           .(Date, Ticker, .f2 = -.sd60_l1)]          # 저변동 선호 = 역방향
} else stop("[rf_cell_engine] factor2.kind 미지원: ", .f2$kind)

PANEL <- merge(PANEL[, .(Date, Ticker, .base_sig, .SizeLag,
                         Sector = if ("Sector_Lv2" %in% names(PANEL)) Sector_Lv2 else NA_character_)],
               F2, by = c("Date","Ticker"))
if (!nrow(PANEL)) stop("[rf_cell_engine] 결합 후 패널이 비었습니다 — 팩터 커버리지 확인")

# ── 4. rank-Z 50/50 컴포짓 (C1: 그 날 횡단면 안에서만) ────────────────────────
.rz <- function(v) { r <- frank(v, ties.method = "average"); (r - mean(r)) / stats::sd(r) }
.f2_none <- identical(.f2$kind, "none")
PANEL[, .zb := .rz(.base_sig), by = Date]
if (!.f2_none) PANEL[, .zf := .rz(.f2), by = Date]
if (identical(.univ$kind, "sector_neutral")) {
  PANEL[!is.na(Sector), .zb := .rz(.base_sig), by = .(Date, Sector)]
  if (!.f2_none) PANEL[!is.na(Sector), .zf := .rz(.f2), by = .(Date, Sector)]
}
PANEL[, Score := if (.f2_none) .zb else 0.5 * .zb + 0.5 * .zf]
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
    stop("[rf_cell_engine] weighting.kind 미지원(러너가 공분산 셀을 별도 경로로 보냅니다): ", .wt$kind))
  PORTFOLIO <- merge(SEL[, .(Date, Ticker)], W, by = c("Date","Ticker"))[
    , .(Date, Ticker, Weight = w, Leg = "LONG")]
  stopifnot(all(PORTFOLIO$Weight >= 0))
  .chk <- PORTFOLIO[, .(s = sum(Weight)), by = Date]
  stopifnot(max(abs(.chk$s - 1)) < 1e-8)
}

cat(sprintf("[rf_cell_engine] cell=%s | univ=%s | f2=%s | wt=%s | months=%d | rows=%d\n",
            SPEC$code %||% "?", .univ$kind, .f2$id %||% "none", .wt$kind,
            length(.sig_dates), if (exists("PORTFOLIO")) nrow(PORTFOLIO) else nrow(FACTORS)))
