# =============================================================================
# fe_str1715v3.R — STR_1715 v3: Core(consensus) + Defense + IN04(issuance) 3-SLEEVE 위계 결합
# =============================================================================
# 가설: STR_1715 v2(Core consensus 0.45 + Defense 0.25 + Value 0.30)는 OOS retention −0.445로
#       실패했다(value 축이 OOS robust가 아니었음 — IS 강세 풀샘플 착시 + 잔차모멘텀 비직교 0.911).
#       v3는 value sleeve를 IN04(Net Equity Issuance, 순주식발행 anomaly)로 교체한다.
#       IN04는 LS 진짜 직교축: value/momentum/STR_1715/풀 max상관 0.21(value 0.41보다 직교),
#       특히 ★STR_1715와 −0.027 무관★. value(v2 −0.445)와 달리 IN04가 Core+Defense에 비직교/중복이
#       아니라면, consensus 결합 시 value보다 OOS retention 유의 개선이 기대된다.
#       단, IN04 long-only 단일은 OOS −0.983 붕괴(엣지가 short leg) — 결합 시 Core/Defense의
#       normal 지속력이 IN04의 long-leg 약점을 받칠 수 있는가가 검증 핵심.
#
# ★★ 3-SLEEVE score-level 위계 (sleeve별 z화 후 결합 — STR_1715/valearn/v2식 2단계) ★★
#   각 sleeve는 (1) 구성팩터 cross-sectional z화 → (1.5) sleeve 내 EW 합 →
#   (2) ★sleeve 합 자체를 다시 universe 내 cross-sectional 재z화★ 로 동일 스케일(평균0·σ1)에 정렬.
#   그래야 W_C·Zc + W_D·Zd + W_I·Zi 결합이 개별팩터 단위가 아닌 sleeve 단위로 작동한다.
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
#   Sleeve Issuance:
#       IN04_Net_Equity_Issuance Z_Score_Aligned → 1회 cross-sectional z화 = Zi  (단일 팩터 → 위계가 곧 단일 z)
#
#   최종 Score = W_C·Zc + W_D·Zd + W_I·Zi  (세 sleeve 모두 정의된 횡단면만).
#   W_C/W_D/W_I = 환경변수 (기본 Core0.45 / Defense0.25 / Issuance0.30 — v2의 value 30%를 그대로 IN04로 교체).
#
# ★ 계약: FACTORS(Date, Ticker, Score, N). universe = K200∪KQ150 + 유동성 2e8(PIT 시변).
#   fe_str1715v2.R의 sleeve 구성·2단계 위계·L-534 일괄로딩 패턴 복제 (value sleeve만 IN04로 교체).
#   ★ OOM fix: fe_single.R 패턴 — universe(.mem) 산출 직후 RAWDATA(fe_env 바인딩) 즉시 해제 →
#     8팩터 일괄로딩 동안 RAWDATA 378MB peak 제거(driver의 별도 RAWDATA env는 무영향).
#
# ===== PIT (C1~C15) =====
#   - 8팩터 load_month_factors(sig_date) Z_Score_Aligned = Usable_Date<=sig_date IC 방향정렬(C14)
#     + 재무/애널리스트/발행 announcement lag는 factor DB 빌드 단계 반영(C4 — IN04 issuance 재무 lag 포함).
#     NEGATE/FLIP 없음(C13). Factor DB 직접 load 금지 → load_month_factors 경유(C15).
#   - 모든 z화(1·1.5·2단계)는 sig_date 시점 cross-section만(full-sample 통계 아님, C1).
#   - 동일시점 순환참조 없음(C2). sleeve 합·재z화 전부 동일 sig_date 횡단면 내 연산.
#   - forward return·실행 시차는 driver(driver_str1715v3_lo.R)가 forward 1M hold로 처리.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

CORE_4F    <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")       # Sleeve Core (consensus)
DEF_3F     <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")  # Sleeve Defense
ISS_FACTOR <- "IN04_Net_Equity_Issuance"                                      # Sleeve Issuance (value 교체)

# 가중치 (환경변수 — 기본 Core0.45 / Defense0.25 / Issuance0.30)
.wc <- suppressWarnings(as.numeric(Sys.getenv("W_C", "0.45")))
.wd <- suppressWarnings(as.numeric(Sys.getenv("W_D", "0.25")))
.wi <- suppressWarnings(as.numeric(Sys.getenv("W_I", "0.30")))
if (!is.finite(.wc)) .wc <- 0.45
if (!is.finite(.wd)) .wd <- 0.25
if (!is.finite(.wi)) .wi <- 0.30

# ---- (1)(2) OOM fix: universe 산출 = slim 6열 로컬 추출, full RAWDATA 무수정 ----
#   fe_str1715v2와 달리 공유 RAWDATA를 reorder/컬럼추가하지 않고 slim 사본만 사용 →
#   universe(.mem) 산출 직후 .rd_slim + 공유 RAWDATA(fe_env 바인딩) 즉시 해제.
#   가드: v3는 .mem 산출 이후 RAWDATA를 일절 참조하지 않음(8팩터 전부 factor DB 기반,
#   가격/momentum driver 아님 — fe_single과 동일 조건). driver의 자체 RAWDATA env는 무영향.
.rd_slim <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]   # shallow 추출(새 data.table)
setorder(.rd_slim, Ticker, Date)

.rd_slim[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(.rd_slim[, .(Date = max(Date)), by = .ym]$Date)
.rd_slim[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")          # factor DB 재무/애널리스트/발행 가용 시작
.month_ends <- .month_ends[.month_ends >= .fdb_min]

# K200∪KQ150 멤버십 + 유동성(20일 평균 거래대금 2e8) 유니버스 (PIT 시변, 과거 윈도우)
.rd_slim[, .TV := Close * Vol]
.rd_slim[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- .rd_slim[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                   !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                 .(Date, Ticker)]
setkey(.mem, Date, Ticker)
# ★ (2) universe-pass transient(.rd_slim 13.9M frollmean) + 공유 RAWDATA(fe_env, 378MB) 둘 다
#   즉시 해제 → 이후 8팩터 일괄로딩이 RAWDATA-free로 돌아 peak 평탄(8팩터라 OOM 주의 — fe_single 패턴).
rm(.rd_slim)
if (exists("RAWDATA", inherits = FALSE)) rm(RAWDATA)   # fe_env 바인딩만 해제(driver env 무영향)
gc(verbose = FALSE)

# ---- cross-sectional z-score (universe 내) ----
.zsc <- function(x) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

# ---- ★ L-534 일괄 사전 로드 (루프 내 parquet 반복 로드 금지; fe_str1715v2 패턴 복제) ----
#   월별 load_month_factors 호출을 z-계산 루프 밖 단일 사전 패스로 분리. 호출 직후 8팩터 ×
#   유니버스 종목만 남겨 rbindlist → 단일 keyed cache(fdb_all). 호출 직후 full 288팩터 dt 즉시 폐기.
.want_factors <- c(CORE_4F, DEF_3F, ISS_FACTOR)
.fdb_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next
  fdt0 <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt0) || nrow(fdt0) == 0) { if (!is.null(fdt0)) rm(fdt0); next }
  slim <- fdt0[Factor_Name %in% .want_factors & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
               .(Ticker, Factor_Name, Z_Score_Aligned)]
  rm(fdt0)                                  # ★ full 288팩터 dt를 다음 iteration 전 즉시 free(OOM)
  if (nrow(slim) == 0) next
  slim[, Date := d]
  .fdb_list[[i]] <- slim
  rm(slim)
  if (i %% 24L == 0L) gc(verbose = FALSE)   # 주기적 gc — align merge 잔여 해제(peak 평탄화)
}
fdb_all <- rbindlist(Filter(Negate(is.null), .fdb_list), use.names = TRUE)
rm(.fdb_list); gc(FALSE)
if (nrow(fdb_all) == 0) stop("[fe_str1715v3] factor DB 사전 로드 결과 없음 (8팩터 모두 부재)")
setkey(fdb_all, Date)
cat(sprintf("[fe_str1715v3] factor DB 사전 일괄 로드(L-534): %d months x 8팩터 -> fdb_all rows=%d (루프 내 parquet 반복 로드 제거 + RAWDATA 조기해제 OOM fix)\n",
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

# ---- 월별: 3 sleeve z(Zc/Zd/Zi) → Score = wc*Zc + wd*Zd + wi*Zi ----
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

  # ===== Sleeve Issuance (IN04) : 1회 z화 → Zi =====
  iss <- fdt[Factor_Name == ISS_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, IN = Z_Score_Aligned)]
  iss <- iss[Ticker %in% uni_tk]
  if (nrow(iss) == 0) next
  iss[, Zi := .zsc(IN)]
  iss <- iss[is.finite(Zi), .(Ticker, Zi)]
  if (nrow(iss) == 0) next

  # ===== 결합: 세 sleeve 모두 정의된 종목만, Score = wc*Zc + wd*Zd + wi*Zi =====
  cmb <- merge(cs, ds, by = "Ticker")
  cmb <- merge(cmb, iss, by = "Ticker")
  if (nrow(cmb) < 10L) next
  cmb[, Score := .wc * Zc + .wd * Zd + .wi * Zi]
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

cat(sprintf("[fe_str1715v3] 3-SLEEVE 위계: Core(C01+C02+C04+C06)=Zc + Defense(Q07+M08+Q25)=Zd + Issuance(IN04)=Zi | w_C=%.2f w_D=%.2f w_I=%.2f | N_CAP=%s(%s) | FACTORS rows=%d | signal months=%d | N range=%d~%d\n",
            .wc, .wd, .wi,
            if (.n_cap > 0L) as.character(.n_cap) else "0",
            if (.n_cap > 0L) sprintf("top%d cap(운용)", .n_cap) else "decile(검증)",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N, na.rm = TRUE) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N, na.rm = TRUE) else 0L))
