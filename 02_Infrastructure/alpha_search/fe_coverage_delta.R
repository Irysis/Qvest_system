# =============================================================================
# fe_coverage_delta.R — 애널리스트 커버리지 head-count *변화* 알파 (KR-native 가설)
# =============================================================================
# 가설: 커버리지 *수준*이 아니라 *변화*가 횡단면 수익을 예측한다.
#   - 커버리지 개시 급증(initiation burst, Δcoverage_3m 상위) = 정보환경 개선·기관 수요
#     선행 → long 신호.  커버리지 철수(abandonment, Δ 하위) = 음의 신호(레몬 회피).
#   문헌 맥락(복제 대상 아님 — KR-native 가설 lane):
#     Demiroglu-Ryngaert(2010) initiation drift / Kelly-Ljungqvist(2012) 철수 정보효과 /
#     McNichols-O'Brien selection. 327 census E-family(추정치 level/revision, eps_chg 등)와
#     fe_earnrev(earnings revision)와는 **별개 구성축** — head-count 변화 그 자체.
#
# 산출: FACTORS(Date, Ticker, Score, N, dcov_abs, dcov_rel, cov_now, aband, neglect)
#   - P1(primary, 러너 판정): Score = 같은 시그널일 횡단면 Δcoverage_3m 랭크, 상위 decile EW.
#       (절대 증분 dcov_abs vs 증가율 dcov_rel 중 IS에서 분포 보고 1회 선택 — 러너가 선택·기록.
#        본 fe는 두 변형을 모두 산출. Score 기본 = dcov_abs 랭크. 변경 시 러너에서 swap.)
#   - 진단(게이트 미사용, 러너가 IC 산출): aband(P2 철수=3m 감소), neglect(P3 저커버리지 조건).
#
# ===== PIT self-assert (외부 parquet 의존 — detect_lookahead 정적분석 사각 보강) =====
#   - coverage.parquet = (Date, Ticker, coverage) 일별 관측 시계열(벤더 관측일 = Date).
#     중복 (Date,Ticker) 0건·일변화율 4.8%(step 함수) 실측 → Date = 관측시점(restatement 아님).
#   - Usable_Date = 관측일 + 1 거래일 (당일 관측분은 익영업일부터 — C2 same-day 금지).
#   - 시그널일 t: Usable_Date <= t 인 ticker별 '가장 최근' 관측만 사용(cov_now).
#     3개월 전 시그널일 t-3m 에 대해서도 동일 규칙(cov_3m_ago) — 모두 과거/현재 관측치.
#     → fe 내부에 시그널일별 max(Usable_Date) <= 시그널일 어서션 내장(위반 시 stop).
#   - Δcoverage_3m = cov_now - cov_3m_ago (forward label 아님 — 둘 다 t 이전 관측).
#   - ★ NA-vs-0 함정: coverage.parquet은 coverage>=1 종목만 행 존재(min=1, 0/NaN 0건 실측).
#     유니버스 종목이 관측에 없으면 = 미커버 → cov := 0 으로 채움(명시 가정). 러너 유니버스
#     필터(K200∪KQ150) 후 left-join으로 0 채움. 신규 개시(0->k)가 initiation burst의 핵심.
#   - C6 생존편향: coverage 데이터에 상폐 종목 포함(last<2020 891/1939 실측) — 편향 없음.
#   - 횡단면 랭크 = 같은 시그널일 횡단면(C1 full-sample 아님). NEGATE/FLIP 없음.
#   - 데이터 floor: coverage 2001-06~ (2005 mandate 충족 — 가격 데이터와 교집합이 실질 floor).
# =============================================================================
suppressMessages({ library(data.table); library(arrow) })
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 0. 거래일 캘린더 (Usable_Date = 관측일 + 1 거래일) ------------------------
.TDAYS <- sort(unique(RAWDATA$Date))
.next_tday <- function(d) {                      # d 이후 첫 거래일(당일 관측 = 익일 사용, C2)
  i   <- findInterval(d, .TDAYS)                 # d 이하 마지막 거래일 인덱스
  idx <- pmin(pmax(i + 1L, 1L), length(.TDAYS))  # 항상 d '다음' 거래일
  .TDAYS[idx]
}

# ---- 1. 커버리지 메타데이터 로드 (원천 컨센서스 캐시 — factor DB 아님) ----------
.cvp <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                  Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
                  ".cache", "consensus", "coverage.parquet")
stopifnot(file.exists(.cvp))
.CV <- as.data.table(read_parquet(.cvp, col_select = c("Date","Ticker","coverage")))
if (!inherits(.CV$Date, "Date")) .CV[, Date := as.Date(Date)]
.CV <- .CV[is.finite(coverage) & coverage >= 0]
setkey(.CV, Ticker, Date)
.CV[, Usable_Date := .next_tday(Date)]           # 관측일 + 1 거래일

# ---- 2. 월말 시그널 날짜 그리드 (유니버스 canonical 월말 거래일) ---------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.MEND <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)

# ---- 3. 각 시그널일 t: Usable_Date <= t 인 ticker별 '가장 최근' 커버리지 -------
#   PIT 핵심: t 시점 가관측 관측만. 미래 관측 절대 차단.
.cov_asof <- function(t) {
  cand <- .CV[Usable_Date <= t]
  if (!nrow(cand)) return(NULL)
  setorder(cand, Ticker, Date)
  latest <- cand[, .(cov = coverage[.N], Usable_Date = Usable_Date[.N]), by = Ticker]
  latest[, Date := t]
  latest
}
COVASOF <- rbindlist(lapply(.MEND, .cov_asof), use.names = TRUE, fill = TRUE)
COVASOF <- COVASOF[is.finite(cov)]

# ---- 3b. ★ PIT self-assert: 시그널일별 사용 관측의 Usable_Date <= 시그널일 ------
.maxuse <- COVASOF[, .(mx = max(Usable_Date)), by = Date]
if (nrow(.maxuse[mx > Date]) > 0L)
  stop(sprintf("[fe_coverage_delta][PIT-FAIL] 미래 커버리지 누설: %d 시그널일에서 Usable_Date > 시그널일",
               nrow(.maxuse[mx > Date])))
cat("[fe_coverage_delta][PIT-OK] 시그널일별 max(Usable_Date) <= 시그널일 — 미래참조 없음 검증 통과\n")

# ---- 4. 유니버스 그리드(시그널일 × K200∪KQ150 종목) + NA->0 채움 ----------------
#   ★ NA-vs-0: 커버리지 미관측 = 미커버 → 0. 유니버스 멤버 전체 그리드에 left-join.
stopifnot(all(c("K200","KQ150") %in% names(RAWDATA)))
.UNI <- unique(RAWDATA[Date %in% .MEND & (K200 == 1 | KQ150 == 1), .(Date, Ticker)])
G <- merge(.UNI, COVASOF[, .(Date, Ticker, cov)], by = c("Date","Ticker"), all.x = TRUE)
G[is.na(cov), cov := 0]                          # 미커버 = 0 (명시 가정)

# ---- 5. 3개월 전(=3 시그널월 전) 커버리지 align → Δcoverage_3m ------------------
#   같은 ticker 시그널월 시계열에서 3-lag shift (전부 과거 관측, forward 없음).
.MIDX <- data.table(Date = .MEND, midx = seq_along(.MEND))
G <- merge(G, .MIDX, by = "Date")
setorder(G, Ticker, midx)
G[, cov_l3 := shift(cov, 3L), by = Ticker]       # 3 시그널월 전 (PIT: 과거)
G[, midx_l3 := shift(midx, 3L), by = Ticker]
G <- G[is.finite(cov_l3) & (midx - midx_l3) == 3L]  # 정확히 3개월 간격(결측월 배제)
G[, dcov_abs := cov - cov_l3]                     # 절대 증분 (initiation burst 핵심)
G[, dcov_rel := fifelse(cov_l3 > 0, (cov - cov_l3) / cov_l3,
                        fifelse(cov > 0, 1.0, 0.0))]  # 증가율(0->k는 +100% 처리)
setnames(G, "cov", "cov_now")

# 진단 지표
G[, aband   := as.integer(dcov_abs < 0)]          # P2: 철수(3m 순감소)
G[, neglect := as.integer(cov_l3 <= 2)]           # P3: 저커버리지(3m전 <=2명) 조건

# ---- 6. 유동성 통과 결합 (시그널일 t-1 PIT는 LiqPass 산출 시 이미 right-aligned) -
.LP <- RAWDATA[Date %in% .MEND, .(Date, Ticker, LiqPass)]
SIG <- merge(G, .LP, by = c("Date","Ticker"))
SIG <- SIG[LiqPass == TRUE & is.finite(dcov_abs)]

# ---- 7. P1 Score = 같은 시그널일 횡단면 Δcoverage_3m 랭크 (rank-invariant) ------
#   기본 = dcov_abs(절대 증분). 러너가 IS 분포 보고 dcov_rel 로 swap 가능(변경사유 기록).
SIG[, Score := frank(dcov_abs, ties.method = "average") / .N, by = Date]

# ---- 8. decile N (각 시그널일 상위 10%, EW) — 종목수 임의 제한 안 함 ------------
.NDT <- SIG[, .(N = as.integer(pmax(1L, round(.N / 10)))), by = Date]
FACTORS <- merge(SIG[, .(Date, Ticker, Score, dcov_abs, dcov_rel, cov_now, aband, neglect)],
                 .NDT, by = "Date")
setorder(FACTORS, Date, -Score)

# ---- 9. 진단 분포 출력 (절대 증분 vs 증가율 선택 근거) --------------------------
.qa <- function(x) sprintf("[%.1f, %.1f, %.1f, %.1f, %.1f]",
                           quantile(x, c(.05,.25,.5,.75,.95), na.rm = TRUE)[1],
                           quantile(x, c(.05,.25,.5,.75,.95), na.rm = TRUE)[2],
                           quantile(x, c(.05,.25,.5,.75,.95), na.rm = TRUE)[3],
                           quantile(x, c(.05,.25,.5,.75,.95), na.rm = TRUE)[4],
                           quantile(x, c(.05,.25,.5,.75,.95), na.rm = TRUE)[5])
cat(sprintf("[fe_coverage_delta] FACTORS rows=%d | dates=%d | tickers=%d | decile N med=%d | cand/mo med=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker),
            as.integer(median(.NDT$N)), as.integer(median(SIG[, .N, by = Date]$N))))
cat(sprintf("[fe_coverage_delta] dcov_abs 분위 p05/25/50/75/95 = %s | 철수비율=%.1f%% | 저커버리지비율=%.1f%%\n",
            .qa(FACTORS$dcov_abs), 100*mean(FACTORS$aband), 100*mean(FACTORS$neglect)))
cat(sprintf("[fe_coverage_delta] cov_now 분위 = %s\n", .qa(FACTORS$cov_now)))
cat(sprintf("[fe_coverage_delta] 데이터 floor: 시그널 최초 %s (coverage 2001-06~, 가격 교집합이 실질 floor)\n",
            as.character(min(FACTORS$Date))))

# 정리 (RAWDATA 임시컬럼 제거)
RAWDATA[, c(".ym") := NULL]
rm(.CV, COVASOF, .maxuse, .UNI, G, .MIDX, SIG, .LP, .NDT, .MEND); gc(verbose = FALSE)
