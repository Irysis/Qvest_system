# =============================================================================
# fe_str1715v2.R — STR_1715 v2: Core(consensus) + Defense + Value 3-SLEEVE 위계 결합
# =============================================================================
# 가설: STR_1715(KR 고SR 1.50 · OOS retention 0.91)은 Core(earnings-rev consensus 4F, w0.65)
#       + Defense(Q07/M08/Q25, w0.35) 2-sleeve 위계로 normal 국면 지속력을 얻었으나
#       value 축이 0%다. value(V01_BM)는 단독 long-short 진단에서 Carhart4 t3.28 ·
#       OOS retention +0.41로 BM-직교 OOS-robust 축임이 입증됐다(measurement-graduation §6
#       의 "수익률직교 불가"는 single-factor long-only 한정 — multi-sleeve 내 보조축으로는 별개).
#       valearn(value+earnings-rev 2축)은 normal decay로 long-only OOS −0.517로 부족했으나,
#       이는 Defense sleeve(crisis_alpha + 안정성)가 빠진 2축뿐이라 normal 지속력이 없었기 때문이다.
#       STR_1715 v2 = Core(consensus) + Defense + Value 3-sleeve로 결합하면,
#       Defense가 normal 지속을 받치고 Value가 BM-직교 OOS-robustness를 더해
#       SR1.50(STR_1715) 위 + OOS retention 0.5+ 회복이 가능한가?
#
# ★★ 3-SLEEVE score-level 위계 (sleeve별 z화 후 결합 — STR_1715/valearn식 2단계) ★★
#   각 sleeve는 (1) 구성팩터 cross-sectional z화 → (1.5) sleeve 내 EW 합 →
#   (2) ★sleeve 합 자체를 다시 universe 내 cross-sectional 재z화★ 로 동일 스케일(평균0·σ1)에 정렬.
#   그래야 W_C·Zc + W_D·Zd + W_V·Zv 결합이 개별팩터 단위가 아닌 sleeve 단위로 작동한다.
#
#   Sleeve Core (earnings-rev consensus) ── 2단계 위계 ──:
#       1단계: C01_SUE / C02_EPS_Chg_1m / C04_ESBR / C06_TP_Gap 각각 cross-sectional z화 → z1,z2,z4,z6
#       1.5단계: sleeve 내 EW 합 → C_raw = z1+z2+z4+z6  (가용 z만, 최소 2팩터)
#       2단계: ★ C_raw 재-z화 → Zc ★
#
#   Sleeve Defense ── 2단계 위계 ──:
#       1단계: Q07_Earnings_Stability / M08_Residual_Mom / Q25_Ohlson_O 각각 z화 → zq,zm,zo
#       1.5단계: sleeve 내 EW 합 → D_raw = zq+zm+zo  (가용 z만, 최소 2팩터)
#       2단계: ★ D_raw 재-z화 → Zd ★
#
#   Sleeve Value:
#       V01_BM Z_Score_Aligned → 1회 cross-sectional z화 = Zv  (단일 팩터 → 위계가 곧 단일 z)
#
#   최종 Score = W_C·Zc + W_D·Zd + W_V·Zv  (세 sleeve 모두 정의된 횡단면만).
#   W_C/W_D/W_V = 환경변수 (기본 Core0.45 / Defense0.25 / Value0.30 —
#     STR_1715 원전 0.65/0.35 비율을 유지하며 value 30%를 삽입: 0.45:0.25 ≈ 0.643:0.357).
#
# ★ 계약: FACTORS(Date, Ticker, Score, N). universe = K200∪KQ150 + 유동성 2e8(PIT 시변).
#   STR_1715 신호코드(WT-D20260425_010 factor_engine_proposal.R)의 sleeve 팩터 구성 재현.
#   fe_valearn.R의 L-534 일괄로딩 패턴(루프 밖 단일 사전 패스) 복제 — OOM 회피.
#
# ===== PIT (C1~C15) =====
#   - 8팩터 load_month_factors(sig_date) Z_Score_Aligned = Usable_Date<=sig_date IC 방향정렬(C14)
#     + 재무/애널리스트 announcement lag는 factor DB 빌드 단계 반영(C4). NEGATE/FLIP 없음(C13).
#     Factor DB 직접 load 금지 → load_month_factors 경유(C15).
#   - 모든 z화(1·1.5·2단계)는 sig_date 시점 cross-section만(full-sample 통계 아님, C1).
#   - 동일시점 순환참조 없음(C2). sleeve 합·재z화 전부 동일 sig_date 횡단면 내 연산.
#   - forward return·실행 시차는 driver(driver_str1715v2_lo.R)가 forward 1M hold로 처리.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

CORE_4F    <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")     # Sleeve Core (consensus)
DEF_3F     <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")  # Sleeve Defense
VAL_FACTOR <- "V01_BM"                                                      # Sleeve Value

# 가중치 (환경변수 — 기본 Core0.45 / Defense0.25 / Value0.30)
.wc <- suppressWarnings(as.numeric(Sys.getenv("W_C", "0.45")))
.wd <- suppressWarnings(as.numeric(Sys.getenv("W_D", "0.25")))
.wv <- suppressWarnings(as.numeric(Sys.getenv("W_V", "0.30")))
if (!is.finite(.wc)) .wc <- 0.45
if (!is.finite(.wd)) .wd <- 0.25
if (!is.finite(.wv)) .wv <- 0.30

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")          # factor DB 재무/애널리스트 가용 시작
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# ---- K200∪KQ150 멤버십 + 유동성(20일 평균 거래대금 2e8) 유니버스 (PIT 시변) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                .(Date, Ticker)]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
setkey(.mem, Date, Ticker)

# ---- cross-sectional z-score (universe 내) ----
.zsc <- function(x) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

# ---- ★ L-534 일괄 사전 로드 (루프 내 parquet 반복 로드 금지; fe_valearn 패턴 복제) ----
#   월별 load_month_factors 호출을 z-계산 루프 밖 단일 사전 패스로 분리. 호출 직후 8팩터 ×
#   유니버스 종목만 남겨 rbindlist → 단일 keyed cache(fdb_all). z-계산 루프는 parquet read 없이
#   fdb_all[.(d)] 슬라이스만 참조. 결과 불변(align_factor_direction이 factor별 방향정렬·재z화하므로
#   다른 팩터를 떨궈도 8팩터 Z_Score_Aligned는 bit-동일).
.want_factors <- c(CORE_4F, DEF_3F, VAL_FACTOR)
.fdb_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next
  fdt0 <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt0) || nrow(fdt0) == 0) next
  slim <- fdt0[Factor_Name %in% .want_factors & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
               .(Ticker, Factor_Name, Z_Score_Aligned)]
  if (nrow(slim) == 0) next
  slim[, Date := d]
  .fdb_list[[i]] <- slim
  rm(fdt0, slim)
}
fdb_all <- rbindlist(Filter(Negate(is.null), .fdb_list), use.names = TRUE)
rm(.fdb_list); gc(FALSE)
if (nrow(fdb_all) == 0) stop("[fe_str1715v2] factor DB 사전 로드 결과 없음 (8팩터 모두 부재)")
setkey(fdb_all, Date)
cat(sprintf("[fe_str1715v2] factor DB 사전 일괄 로드(L-534): %d months x 8팩터 -> fdb_all rows=%d (루프 내 parquet 반복 로드 제거)\n",
            uniqueN(fdb_all$Date), nrow(fdb_all)))

# ---- sleeve 2단계 위계 헬퍼: 팩터들 z화 → EW 합 → 재z화 (min 2팩터). 반환 data.table(Ticker, Z) ----
.sleeve_hier <- function(fdt, factors, uni_tk, min_factors = 2L) {
  sub <- fdt[Factor_Name %in% factors & is.finite(Z_Score_Aligned),
             .(Ticker, Factor_Name, Z = Z_Score_Aligned)]
  sub <- sub[Ticker %in% uni_tk]
  if (nrow(sub) == 0) return(NULL)
  w <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z")
  avail <- intersect(factors, names(w))
  if (length(avail) == 0) return(NULL)
  # 1단계: 각 팩터 cross-sectional z화
  z_cols <- character(0)
  for (fn in avail) {
    zc <- paste0(".z_", fn)
    w[, (zc) := .zsc(get(fn))]
    z_cols <- c(z_cols, zc)
  }
  # 1.5단계: sleeve 내 EW 합 (가용 z만, 최소 min_factors)
  zmat   <- as.matrix(w[, ..z_cols])
  nvalid <- rowSums(is.finite(zmat))
  w[, .raw := rowSums(zmat, na.rm = TRUE)]
  w[, .nv  := nvalid]
  sl <- w[.nv >= min_factors, .(Ticker, raw = .raw)]
  if (nrow(sl) < 10L) return(NULL)
  # 2단계 ★위계 핵심★: sleeve 합을 재-z화
  sl[, Z := .zsc(raw)]
  sl <- sl[is.finite(Z), .(Ticker, Z)]
  if (nrow(sl) < 10L) return(NULL)
  sl
}

# ---- 월별: 3 sleeve z(Zc/Zd/Zv) → Score = wc*Zc + wd*Zd + wv*Zv ----
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next

  fdt <- fdb_all[.(d), .(Ticker, Factor_Name, Z_Score_Aligned), nomatch = 0L]
  if (is.null(fdt) || nrow(fdt) == 0) next

  # ===== Sleeve Core (consensus 4F) : 2단계 위계 → Zc =====
  cs <- .sleeve_hier(fdt, CORE_4F, uni_tk, min_factors = 2L)
  if (is.null(cs)) next
  setnames(cs, "Z", "Zc")

  # ===== Sleeve Defense (Q07/M08/Q25) : 2단계 위계 → Zd =====
  ds <- .sleeve_hier(fdt, DEF_3F, uni_tk, min_factors = 2L)
  if (is.null(ds)) next
  setnames(ds, "Z", "Zd")

  # ===== Sleeve Value (V01_BM) : 1회 z화 → Zv =====
  val <- fdt[Factor_Name == VAL_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, BM = Z_Score_Aligned)]
  val <- val[Ticker %in% uni_tk]
  if (nrow(val) == 0) next
  val[, Zv := .zsc(BM)]
  val <- val[is.finite(Zv), .(Ticker, Zv)]
  if (nrow(val) == 0) next

  # ===== 결합: 세 sleeve 모두 정의된 종목만, Score = wc*Zc + wd*Zd + wv*Zv =====
  cmb <- merge(cs, ds, by = "Ticker")
  cmb <- merge(cmb, val, by = "Ticker")
  if (nrow(cmb) < 10L) next
  cmb[, Score := .wc * Zc + .wd * Zd + .wv * Zv]
  cmb <- cmb[is.finite(Score)]
  if (nrow(cmb) < 10L) next
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# ---- N_CAP (운용 편입 max N cap, 도훈 mandate 2026-06-05): top-N 선정용 ----
#   N_CAP 미설정/0 → decile(상위 10%). N_CAP>0(예 25) → decile N을 N_CAP로 상한(운용 max25 baseline).
.n_cap <- suppressWarnings(as.integer(Sys.getenv("N_CAP", "0")))
if (!is.finite(.n_cap)) .n_cap <- 0L
FACTORS[, N := {
  dN <- pmax(5L, as.integer(ceiling(.N / 10)))
  if (.n_cap > 0L) pmin(.n_cap, dN) else dN
}, by = Date]

cat(sprintf("[fe_str1715v2] 3-SLEEVE 위계: Core(C01+C02+C04+C06)=Zc + Defense(Q07+M08+Q25)=Zd + Value(V01_BM)=Zv | w_C=%.2f w_D=%.2f w_V=%.2f | N_CAP=%s(%s) | FACTORS rows=%d | signal months=%d | N range=%d~%d\n",
            .wc, .wd, .wv,
            if (.n_cap > 0L) as.character(.n_cap) else "0",
            if (.n_cap > 0L) sprintf("top%d cap(운용)", .n_cap) else "decile(검증)",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N, na.rm = TRUE) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N, na.rm = TRUE) else 0L))
