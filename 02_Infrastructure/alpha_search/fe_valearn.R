# =============================================================================
# fe_valearn.R — value(BM) + earnings-revision 2-SLEEVE 위계 결합 (STR_1715식)
# =============================================================================
# 가설: STR_1715(KR 고SR 1.50)의 OOS-robustness(0.91)는 multi-sleeve 위계 구조가
#       단일 sleeve의 OOS decay를 차단하기 때문이다. 단독 long-short 진단에서
#         value(BM)         : Carhart4 t3.28 · OOS retention +0.41 (OOS-robust 직교원)
#         earnings-revision : Carhart4 t3.61 · OOS retention -0.10 (IS강 / OOS붕괴)
#       value는 OOS-robust인데 강도 보통, earnings-revision은 IS 고강도인데 OOS붕괴.
#       두 축을 **sleeve-level 위계**로 결합하면 value의 OOS-robustness가
#       earnings-revision의 OOS붕괴를 받쳐, valrev 단순 z-합(t1.76)보다 강하고
#       earnrev(OOS-0.10)보다 OOS-robust한 'OOS-robust 고강도' 결합이 되는가?
#
# ★★ sleeve-level 위계 (2단계 — STR_1715식, 개별팩터 1단계 z-합과 차별) ★★
#   본 fe의 핵심은 fe_valrev.R(1단계 flat z-combo: z(Val)+z(Rev))와의 **위계 차이**다.
#
#   Sleeve V (value):
#       V01_BM Z_Score_Aligned  ── universe 내 cross-sectional z화 ──>  Zv
#       (단일 팩터 → 1회 z화. sleeve V는 팩터 1개라 위계가 곧 단일 z.)
#
#   Sleeve E (earnings-revision) ── ★ 2단계 위계 ★ ──:
#       1단계: C01_SUE / C02_EPS_Chg_1m / C04_ESBR / C06_TP_Gap 각각
#              universe 내 cross-sectional z화  ──>  z1, z2, z4, z6
#       1.5단계: sleeve 내 EW 합  ──>  E_raw = z1 + z2 + z4 + z6  (가용 z만, 최소 2팩터)
#       2단계: ★ E_raw 자체를 다시 universe 내 cross-sectional z화 ──>  Ze ★
#       → 이 2단계(sleeve합을 재-z화)가 valrev의 1단계 개별-z-합과 다른 핵심.
#         재-z화로 sleeve E를 Zv(value)와 동일 스케일(평균0·표준편차1)에 맞춤 →
#         w_V*Zv + w_E*Ze 결합이 sleeve 단위(개별팩터 단위 아님)로 작동.
#
#   최종 Score = w_V*Zv + w_E*Ze  (둘 다 정의된 횡단면만, gross long-short는 driver).
#   가중치 w_V/w_E = 환경변수 W_V/W_E (기본 0.5/0.5). value-heavy(0.6/0.4)는
#     별 STRAT_NAME(valearn_vh)로 W_V=0.6 W_E=0.4 재실행하여 비교.
#
# ★ 계약: FACTORS(Date, Ticker, Score). universe = K200∪KQ150 + 유동성 2e8.
#   fe_earnrev.R(sleeve E 팩터·z화) + fe_value_bm.R(sleeve V·BM) 신호 로직 재사용.
#
# ===== PIT (C1~C15) =====
#   - value/earnings 각 팩터 load_month_factors(sig_date) Z_Score_Aligned =
#     Usable_Date<=sig_date IC 방향정렬(C14) + 재무/애널리스트 announcement lag는
#     factor DB 빌드 단계 반영(C4 — book 연간 5월 lag, earnings 분기 announce lag).
#     NEGATE/FLIP 없음(C13). Factor DB 직접 load 금지 → load_month_factors 경유(C15).
#   - 모든 z화(1단계·2단계)는 sig_date 시점 cross-section만(full-sample 통계 아님, C1).
#   - 동일시점 순환참조 없음(C2). sleeve 합·재-z화 전부 동일 sig_date 횡단면 내 연산.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

VAL_FACTOR <- "V01_BM"                                          # Sleeve V = value(BM)
EARN_4F    <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")  # Sleeve E

# 가중치 (환경변수 — 기본 0.5/0.5, value-heavy는 W_V=0.6 W_E=0.4)
.wv <- suppressWarnings(as.numeric(Sys.getenv("W_V", "0.5")))
.we <- suppressWarnings(as.numeric(Sys.getenv("W_E", "0.5")))
if (!is.finite(.wv)) .wv <- 0.5
if (!is.finite(.we)) .we <- 0.5

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

# ---- ★ OOM 근본 해결 (factor-db.md L-534: "루프 내 parquet 반복 로드 절대 금지") ----
#   기존: 월별 z-계산 루프 안에서 매월 load_month_factors(d) 호출(254회 × parquet read +
#         align_factor_direction 전체-dt merge·재z화) → run_monthly_simulation 무거운 컨텍스트와
#         겹쳐 peak 메모리 OOM. valearn long-short(driver_ls_generic)는 sim 파이프라인이 없어 완주.
#   해결: 월별 load_month_factors 호출을 **z-계산 루프 밖 사전 패스**로 분리하고, 호출 직후
#         5팩터(V01_BM + EARN_4F) × 유니버스 종목만 남겨 rbindlist → 단일 keyed cache(fdb_all).
#         z-계산 루프는 parquet read 없이 fdb_all[.(d)] 슬라이스만 참조.
#   ★ 결과 불변: load_month_factors(d, coverage_min=0.05) 반환값을 *호출 후* 5팩터로 subset할 뿐,
#     Z_Score_Aligned는 align_factor_direction이 factor별(by=Factor_Name) 방향정렬·재z화하므로
#     다른 팩터를 떨어뜨려도 5팩터 값은 bit-동일. 신호 로직(z화·sleeve 위계·Score) 미변경.
#   메모리: full 월별 dt(~288팩터)를 즉시 free하고 slim 5팩터만 누적 → peak 대폭 감소.
.want_factors <- c(VAL_FACTOR, EARN_4F)
.fdb_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next
  fdt0 <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt0) || nrow(fdt0) == 0) next
  # 호출 직후 5팩터 × 유니버스만 남기고 full dt 즉시 폐기(메모리 누적 차단)
  slim <- fdt0[Factor_Name %in% .want_factors & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
               .(Ticker, Factor_Name, Z_Score_Aligned)]
  if (nrow(slim) == 0) next
  slim[, Date := d]
  .fdb_list[[i]] <- slim
  rm(fdt0, slim)
}
fdb_all <- rbindlist(Filter(Negate(is.null), .fdb_list), use.names = TRUE)
rm(.fdb_list); gc(FALSE)
if (nrow(fdb_all) == 0) stop("[fe_valearn] factor DB 사전 로드 결과 없음 (5팩터 모두 부재)")
setkey(fdb_all, Date)
cat(sprintf("[fe_valearn] factor DB 사전 일괄 로드(L-534): %d months x 5팩터 -> fdb_all rows=%d (루프 내 parquet 반복 로드 제거)\n",
            uniqueN(fdb_all$Date), nrow(fdb_all)))

# ---- 월별: Sleeve V 1회 z화(Zv) + Sleeve E 2단계 위계 z화(Ze) → Score = wv*Zv + we*Ze ----
.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next

  # 사전 로드된 cache 슬라이스 참조(parquet read 없음). 값은 load_month_factors와 bit-동일.
  fdt <- fdb_all[.(d), .(Ticker, Factor_Name, Z_Score_Aligned), nomatch = 0L]
  if (is.null(fdt) || nrow(fdt) == 0) next

  # ===== Sleeve V (value) : V01_BM → 1회 cross-sectional z화 = Zv =====
  val <- fdt[Factor_Name == VAL_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, BM = Z_Score_Aligned)]
  val <- val[Ticker %in% uni_tk]
  if (nrow(val) == 0) next
  val[, Zv := .zsc(BM)]

  # ===== Sleeve E (earnings-revision) : 2단계 위계 =====
  sub <- fdt[Factor_Name %in% EARN_4F & is.finite(Z_Score_Aligned),
             .(Ticker, Factor_Name, Z = Z_Score_Aligned)]
  sub <- sub[Ticker %in% uni_tk]
  if (nrow(sub) == 0) next
  w <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z")
  avail <- intersect(EARN_4F, names(w))
  if (length(avail) == 0) next

  # 1단계: 각 팩터 universe 내 cross-sectional z화 (z1,z2,z4,z6)
  z_cols <- character(0)
  for (fn in avail) {
    zc <- paste0(".z_", fn)
    w[, (zc) := .zsc(get(fn))]
    z_cols <- c(z_cols, zc)
  }
  # 1.5단계: sleeve 내 EW 합 (가용 z만, 최소 2팩터 요구 — fe_earnrev.R 규약)
  zmat <- as.matrix(w[, ..z_cols])
  n_valid <- rowSums(is.finite(zmat))
  w[, .E_raw := rowSums(zmat, na.rm = TRUE)]
  w[, .nvalid := n_valid]
  esl <- w[.nvalid >= 2L, .(Ticker, E_raw = .E_raw)]
  if (nrow(esl) < 10L) next
  # 2단계 ★위계 핵심★: sleeve 합(E_raw)을 다시 universe 내 cross-sectional z화 = Ze
  esl[, Ze := .zsc(E_raw)]
  esl <- esl[is.finite(Ze)]
  if (nrow(esl) < 10L) next

  # ===== 결합: 두 sleeve 모두 정의된 종목만, Score = wv*Zv + we*Ze =====
  cmb <- merge(val[is.finite(Zv), .(Ticker, Zv)], esl[, .(Ticker, Ze)], by = "Ticker")
  if (nrow(cmb) < 10L) next
  cmb[, Score := .wv * Zv + .we * Ze]
  cmb <- cmb[is.finite(Score)]
  if (nrow(cmb) < 10L) next
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

# decile (상위 10%) long-only EW marker (fe_valrev / fe_earnrev 동일 규약)
# ---- N_CAP (정책 B, 도훈 mandate 2026-06-05): 운용 편입만 max N cap ----
#   N_CAP 미설정/0 → decile 그대로(검증 직교 스크리닝 불변. driver_ls_generic은 N_CAP 미부여 → long-short 결과 보존).
#   N_CAP>0 (예 25) → 월별 decile N을 N_CAP로 상한(운용 max25 baseline).
.n_cap <- suppressWarnings(as.integer(Sys.getenv("N_CAP", "0")))
if (!is.finite(.n_cap)) .n_cap <- 0L
FACTORS[, N := {
  d <- pmax(5L, as.integer(ceiling(.N / 10)))
  if (.n_cap > 0L) pmin(.n_cap, d) else d
}, by = Date]

cat(sprintf("[fe_valearn] 2-SLEEVE 위계 value(BM)=Zv + earnings-rev(C01+C02+C04+C06 z화->EW합->재z화)=Ze | w_V=%.2f w_E=%.2f | N_CAP=%s(%s) | FACTORS rows=%d | signal months=%d | N range=%d~%d\n",
            .wv, .we,
            if (.n_cap > 0L) as.character(.n_cap) else "0",
            if (.n_cap > 0L) sprintf("top%d cap(운용)", .n_cap) else "decile(검증)",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            if (nrow(FACTORS)) min(FACTORS$N, na.rm = TRUE) else 0L,
            if (nrow(FACTORS)) max(FACTORS$N, na.rm = TRUE) else 0L))
