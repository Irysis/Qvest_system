# =============================================================================
# np157c2a1c_tailwind_era.R — NP-157c2a1c: 과거 순풍기의 정체 + 창별 핸디캡 조회표
#
# 오늘 아크는 **최근 창의 역풍(2025+ +0.3743)** 만 봤다. 그런데 확장 d 는 2010s 블록이
# **−0.1116** 로 강한 **순풍기**였음을 보였다. 순풍도 역풍과 같은 크기의 측정 오염이다 —
# 그 시기 창에서 측정된 cap-w 성과는 **반대 방향으로 부풀려졌다**.
#
# 산출 2종:
#   ① 순풍기 종목 귀속 — 2025+ 역풍이 삼성+하이닉스였듯, 순풍은 무엇이 만들었나 (대칭 분석)
#   ② **창별 핸디캡 조회표** — (종료연도 × 창길이) → d_ann. 과거 측정치를 사후 보정/라벨링하는 실무 도구
#
# ★시장 관측만. 포트폴리오·비중 산출물 없음.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
say <- function(fmt, ...) cat(sprintf(paste0("[c2a1c] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")

main <- function() {
  RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
          col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
  RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
  MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
  RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
  fwd <- build_monthly_forward_returns(RAWME, MEND)
  returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
  uni <- RAWME[(K200 == TRUE | KQ150 == TRUE) & !is.na(Size) & Size > 0, .(Date, Ticker, Size)]
  P <- merge(uni, returns_dt, by = c("Date","Ticker"))
  P[, `:=`(w_cap = Size / sum(Size), w_ew = 1 / .N), by = Date]
  P[, contrib := (w_cap - w_ew) * Ret_1m]
  D <- P[, .(d = sum(contrib)), by = Date][order(Date)]
  D[, year := as.integer(format(Date, "%Y"))]
  say("확장 패널 %d개월 (%s ~ %s)", nrow(D), min(D$Date), max(D$Date))

  ## ── ① 순풍기 종목 귀속 (2010-2014) vs 역풍기 (2025+) ────────────────────
  attribute <- function(P, y0, y1, label) {
    W <- P[format(Date, "%Y") >= as.character(y0) & format(Date, "%Y") <= as.character(y1)]
    A <- W[, .(total = sum(contrib)), by = Ticker][order(total)]   # 순풍 = 음수 기여 상위
    tot <- sum(A$total); L <- uniqueN(W$Date)
    say("--- %s (%d~%d) · %d개월 · d_ann %+.4f ---", label, y0, y1, L, tot / L * 12)
    say("   [음수 기여 상위 6 = 순풍 생성]")
    print(head(A[, .(Ticker, total = round(total, 4), share = round(total / tot, 3))], 6))
    say("   [양수 기여 상위 6 = 역풍 생성]")
    print(head(A[order(-total), .(Ticker, total = round(total, 4), share = round(total / tot, 3))], 6))
    A
  }
  A_tail <- attribute(P, 2010, 2014, "순풍기")
  A_head <- attribute(P, 2025, 2026, "역풍기")

  say("--- 대칭성 점검: 순풍기 상위-2 와 역풍기 상위-2 가 같은 종목인가 ---")
  t2_tail <- head(A_tail[order(total)]$Ticker, 2)
  t2_head <- head(A_head[order(-total)]$Ticker, 2)
  say("   순풍기 최대 음수기여 2 = %s", paste(t2_tail, collapse = ", "))
  say("   역풍기 최대 양수기여 2 = %s", paste(t2_head, collapse = ", "))
  say("   교집합: %s", paste(intersect(t2_tail, t2_head), collapse = ", "))

  ## ── ② 창별 핸디캡 조회표 (종료연도 × 창길이) ────────────────────────────
  lens <- c(12, 24, 36, 60, 120, 167, 220, 269)
  dts <- D$Date
  tab <- rbindlist(lapply(lens, function(L) {
    rbindlist(lapply(seq(L, length(dts)), function(i) {
      w <- D[(i - L + 1L):i]
      data.table(window_months = L, end_year = as.integer(format(max(w$Date), "%Y")),
                 end = max(w$Date), d_ann = mean(w$d) * 12)
    }))
  }))
  ## 연도별 대표값 = 그 해 종료 창들의 중앙값
  LK <- tab[, .(d_ann = median(d_ann), n_win = .N), by = .(window_months, end_year)]
  say("--- 창별 핸디캡 조회표 (일부: 종료연도 2010~2026, 창 36/120/269개월) ---")
  print(dcast(LK[window_months %in% c(36, 120, 269) & end_year >= 2010],
              end_year ~ window_months, value.var = "d_ann")[, lapply(.SD, function(x)
                if (is.numeric(x)) round(x, 4) else x)])

  fwrite(LK, file.path(OUT, "np157c2a1c_handicap_lookup.csv"))
  fwrite(A_tail, file.path(OUT, "np157c2a1c_tailwind_attrib.csv"))
  say("저장: np157c2a1c_handicap_lookup.csv · np157c2a1c_tailwind_attrib.csv")
  invisible(0L)
}

main()
