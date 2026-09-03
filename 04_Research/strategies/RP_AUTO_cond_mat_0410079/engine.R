# =============================================================================
# engine.R — RP_AUTO_cond_mat_0410079
# "Experts' earning forecasts: bias, herding and gossamer information"
#  (O. Guedj, J.-P. Bouchaud — arXiv:cond-mat/0410079)
#  https://arxiv.org/abs/cond-mat/0410079
#
# ★fidelity = ADAPTED (기전 이식). 정본 = FIDELITY.json
#
# ===== 왜 faithful 이 불가능한가 (판정 순서 1 → 2) =====
# 이 논문은 **기술통계 논문**이다. 1987-2004 US/EU/UK/JP 애널리스트 이익전망치의
# 편의·군집·예측력을 재고 끝난다. 원문 대조 결과 포트폴리오·수익률·거래비용·
# 종목수·비중·리밸 주기가 **하나도 없다**(초록: "We study the statistics of earning
# forecasts ..."). 복제할 '논문 그대로의 신호·종목수·비중·리밸'이 존재하지 않는다.
#   → faithful 불가. 데이터는 있으므로(아래) ABORT 사유도 아니다 → 판정 순서 2.
#
# ===== 무엇을 남기는가 (kept — 논문의 기전) =====
# 논문의 stock-level 결과 두 줄이 그대로 이식된다. 둘 다 원문 정의다.
#
#  (K1) **컨센서스는 체계적으로 과낙관이다.** 편의 정의(원문 식):
#           b(α, t−θ) = f(α, t−θ) − ε(α, t)
#       f = 애널리스트 평균 전망, ε = 실제 발표 EPS. 부호가 **양(+)** 이고,
#       발표일에 가까워질수록 줄어든다 — 예측EPS 대비 **1년 전 ~60% → 1개월 전 ~10%**.
#       즉 발표에서 먼 시점의 컨센서스 **수준(level)** 이 가장 크게 부풀어 있다.
#
#  (K2) **그 전망의 정보량은 'no change' 순진예측을 못 넘는다.** 원문 Fig.5 —
#       순진예측(= **작년 실현 EPS 를 그대로 내년 추정치로 쓰는 것**)이 θ≈11개월
#       시계에서 애널리스트 전망과 **예측오차는 비슷하면서 편의는 유의하게 작다**.
#       ⇒ 컨센서스가 '이미 알려진 것(작년 실현치)'을 **넘어서서** 주장하는 부분은
#         정보가 아니라 논문이 말하는 **gossamer**(거미줄 같은, 실체 없는 정보)다.
#
#  이식(횡단면 1축): 종목 α 의 컨센서스가 no-change 앵커를 얼마나 위로 늘려 잡았나 =
#       GOSSAMER(α,t) = [ f(α,t) − ε_last(α,t) ] / P(α,t)
#                     = (1년 시계 컨센서스 이익수익률) − (직전 실현 이익수익률)
#       K1(체계적 과낙관) + K2(그 초과분은 정보 아님) ⇒ 이 초과분을 액면가로 사면
#       발표가 도착할 때 실망한다. 따라서 **Score = −GOSSAMER**(늘려 잡지 **않은**
#       종목을 롱). 부호는 성과를 보고 고른 것이 아니라 K1 의 부호(+ 편의)에서
#       사전(a priori)으로 나온다.
#
# ===== 무엇을 바꿨는가 (changed) — 전문은 FIDELITY.json =====
#  (1) 산출 형태: 기술통계 → 횡단면 팩터 점수. 논문에 포트폴리오가 없으므로
#      종목수·비중·리밸은 논문이 아니라 **우리 고정 축**을 쓴다(25종·EW·월간).
#  (2) ★**군집비율 φ = Σ/σ 는 구현하지 않았다.** 논문의 서명 통계지만(S&P ~10,
#      전체 US ~40, EU ~7 — "애널리스트들은 서로에게 실제 결과보다 5~10배 더
#      동의한다") 분모 σ = **애널리스트 간 전망 분산**이고, 우리 컨센서스 패널
#      12종(eps_1y·coverage·sue·esbr·escr·target_price·eps_chg_1m/3m 등)에 **분산
#      패널이 없다**. coverage(애널리스트 수)나 변동성으로 σ 를 대신하는 것은 이식이
#      아니라 지어내기이므로 하지 않는다. 군집 축은 미구현으로 남기고 신고한다.
#      (데이터 적재 항목 = data_pipeline_queue.json 의 본 논문 엔트리와 동일 사유.)
#      ★단 "애널리스트 이익 전망치 패널 부재"라는 그 큐 엔트리의 진술은 **틀렸다** —
#        eps_1y 는 2000-03-16~ 3,434,859행으로 실재한다. 부재한 것은 σ 하나다.
#  (3) 편의의 정규화: 논문은 b 를 **예측 EPS 대비 %** 로 보고한다(60%→10%).
#      그건 대표본 **평균** 보고용 척도이고, 횡단면 순위에 그대로 쓰면 f≈0 근방에서
#      분모가 폭발하고 f<0 에서 부호가 뒤집힌다(논문이 겪지 않은 병리). 그래서
#      **주가 P 로 정규화**한다 — 두 항이 모두 이익수익률이 되어 발산·부호병리가
#      없고, 차이의 의미(늘려 잡은 폭)는 보존된다.
#  (4) ε_last(no-change 앵커): 논문은 "작년 EPS". 우리 구현은 **직전 실현 순이익 /
#      시가총액**(= 인프라의 V02_EP 와 동일 구성). 주당으로 환산하지 않는 이유는
#      SharesOut = Size/Close 환산이 과거 실사고("Size 는 시총이지 주식수가 아니다"
#      — compute_value.R:186-188, eps_growth 를 ~1e5 배 부풀림)의 진원이기 때문이다.
#      f/P 와 ε/시총 은 둘 다 무차원 이익수익률이라 주식수 없이 바로 뺄 수 있다.
#  (5) 유니버스: K200∪KQ150 (PIT 시변). 기간 2005-01-01~.
#
# ===== 남는 한계 (숨기지 않는다) =====
#  ▸ **지배 vs 전체 순이익 불일치**: 벤더 컨센서스 EPS 는 통상 지배주주 기준인데
#    DART 순이익은 전체(비지배 포함)다. 비지배지분이 큰 기업에서 두 항의 기준이
#    어긋난다. 우리 패널에 지배주주 순이익 항목이 없어 보정 불가 — 신고만 한다.
#  ▸ **재무 정정공시 vintage 미보존**(인프라 전역 성질, ast_field_map_v0.json
#    FDB-B1 pit_hazards ①): 정정된 값이 최초 공시 시점에 알려졌던 것처럼 보인다.
#    본 엔진이 새로 들여온 결함이 아니라 원천 패널의 성질이다.
#
# ===== PIT (C1~C15) — 구조로 보장 (detect_lookahead 통과를 근거로 삼지 않는다) =====
#  ▸ 구조 경계: 미래 관측을 볼 수 있는 지점이 **코드에 존재하지 않는다**. 두 원천
#    패널(컨센서스·재무)은 오직 data.table **as-of 롤조인**으로만 소비되고, 롤조인은
#    정의상 `관측일 <= 시그널일` 인 마지막 행만 집는다(roll 방향 = 과거→현재 단방향).
#    전 표본을 한 번에 훑는 통계(cov/mean/sd/quantile 등)가 **0건**이다.
#  C1  : 전 표본 통계 0건. 횡단면 값은 각 시그널일 스냅샷, 시계열 값은 as-of 최신치뿐.
#  C2  : same-day 순환참조 없음. 시그널일 종가·시총까지만 쓰고 집행은 익월 첫 거래일.
#  C3  : 같은 기간 집계→적용 없음. 모든 창의 종점이 보유월 **시작 전**이다.
#  C4  : ★재무 lag — 원천의 Factor_Date(DART annual = bsns_year+1 의 3/31)를 쓰되,
#        그 위에 **자체 하한**을 덧씌운다: Avail = max(Factor_Date, Period_Date + 90d).
#        90일 = C4 연간 규약(12월말 → 익년 3/31)을 일수로 옮긴 값이다. 이 하한은
#        어떤 원천에 대해서도 C4 보다 **늦으면 늦었지 이르지 않다** — xlsx 경로의
#        Q4 일률 +45d(≈익년 2/14, CLAUDE.md 가 '3/31 대비 공격적'으로 명시한 수리
#        항목)가 본 엔진으로 새어들어올 수 없다. 인프라보다 보수적으로 간다.
#  C5  : 오버레이 없음(S0/S1 오버레이 금지 준수).
#  C6  : 유니버스 = 각 시그널일의 K200/KQ150 멤버십(PIT 시변). 최종 명부 주입 없음.
#  C7  : shift(-N)·미래 인덱싱 0건. 유일한 shift 는 +1(과거 방향, 유동성).
#  C8  : FM weight 미사용.  C9 : DD/VT 미사용.
#  C10 : 유동성 = 20일 평균 거래대금을 by-Ticker shift(1) 한 t-1 값 ≥ 2e8.
#  C11 : 매크로·외부 시계열 미사용.
#  C12 : 컨센서스 관측도 as-of(<= 시그널일) — 벤더 공표일 기준 단방향.
#  C13 : Factor DB 미소비 → 부호 정렬 대상 없음. 방향은 측정된 IC 가 아니라
#        논문 K1 의 편의 부호(+)에서 사전으로 나온다. 부호 수동 반전 0건.
#  C14 : IC 접근 없음.
#  C15 : Factor DB parquet 직접 load 0건(애초에 Factor DB 를 안 쓴다). 소비 패널은
#        원천 캐시(consensus/fundamental)이며 Factor DB 가 아니다.
#  ★rawdata 의 Market 열 미사용(KOSDAQ 0건 날조 — 메모리 카드). 시장구분 불필요.
#
# ===== 산출 =====
#   FACTORS(Date, Ticker, Score) — Score = ε_last/시총 − f/P  ( = −GOSSAMER )
#     높을수록 컨센서스가 no-change 앵커를 덜 늘려 잡았다 = 롱 후보.
#     적격 전 종목에 발행하므로 러너의 IC·FF3/FF5/Carhart·FMB 분석이 선다.
#   러너 호출: portfolio_spec = list(construction="top_n_long", weighting="ew",
#              rebalance="monthly", n_long=25) · commission_paper = NULL(논문 무명시).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))

# 난수 미사용(결정론적 엔진)이지만 재현성 선언 고정.
set.seed(410079L)

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Date", "Ticker", "Close", "Vol", "K200", "KQ150") %in% names(RAWDATA)))

.TAG <- "RP_AUTO_cond_mat_0410079"

# =============================================================================
# 상수 — 논문에서 온 것 / 우리 고정 축에서 온 것 / PIT 경계
# =============================================================================
# ▸ 논문에서 온 것: 수치가 아니라 **정의**가 왔다 — b = f − ε 와 no-change 앵커.
#   자유 모수 0개(문턱·가중·윈저 상수 없음).
# ▸ 우리 고정 축: 25종·EW·월간(러너 spec) · adv20(t-1) ≥ 2e8 · 2005-01-01~.
# ▸ PIT 경계(논문 미명시 — 각 1값. 성과를 보고 고르지 않았다):
.LIQ          <- 2e8    # adv20(t-1) 하한 (KRW) — 고정 축 명시값
.NMIN         <- 25L    # 월 최소 횡단면 = 고정 축 top_n. 미만이면 포트폴리오가
                        #   못 차므로 그 달은 신호를 내지 않는다.
.CONS_STALE_D <- 31L    # 컨센서스 as-of 최대 소급(일). = **리밸 주기 그 자체**.
                        #   원천이 일간 캐리포워드 패널이라(compute_consensus.R
                        #   FQ-218 실측: 관측 간격 중앙 1일) 이 값은 신호 문턱이
                        #   아니라 "지금 애널리스트 커버리지가 살아있나" 라이브니스
                        #   검사다. 한 달간 관측이 없으면 커버리지가 끊긴 종목이다.
.FUND_STALE_D <- 730L   # 재무 as-of 최대 소급(일) = **연간 보고 주기 2회분**.
                        #   3/31 가용 규약 탓에 정상 종목도 연초에는 직전연도가
                        #   아니라 전전연도가 최신일 수 있어(예: 2월 시그널 → FY(t-2))
                        #   1주기로는 정상 종목을 자른다. 2주기 = 보고를 멈춘
                        #   종목만 배제하는 하한.
.C4_ANNUAL_D  <- 90L    # C4 연간 규약(12월말 → 익년 3/31)의 일수 표현. 재무 가용일
                        #   자체 하한에 쓴다(위 C4 항목 참조).
.SIG_FROM     <- as.Date("2005-01-01")   # 고정 축 시작
.PANEL_FROM   <- as.Date("2004-01-01")   # 일별 패널 하한(메모리 경계). adv20 20일창
                                         #   +여유. 신호 산출 범위에 무영향.

# ── 경로: 호출자가 config.R 을 이미 source 했으면 그 값을 쓰고, 아니면 env 로 복원 ──
#    ("코드 루트는 데이터 루트가 아니다" — 자기 경로가 아니라 데이터 루트를 앵커로.)
.cache_dir <- if (exists("CACHE_DIR", inherits = TRUE) && nzchar(CACHE_DIR)) {
  CACHE_DIR
} else {
  .r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(.r)) .r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(.r)) stop(sprintf("[%s] CACHE_DIR/QM_ROOT 미해결 — 캐시 경로를 못 찾는다", .TAG))
  file.path(.r, ".cache")
}
if (!dir.exists(.cache_dir))
  stop(sprintf("[%s] 캐시 디렉터리 부재: %s", .TAG, .cache_dir))

# ── 날짜 정규화 헬퍼 ──
# ★파케이 패널마다 Date dtype 이 다르다(date32 vs timestamp[ns] — benchmark.parquet
#   실사고: date32 와 조인 시 **조용히 전량 NA**). 롤조인 키가 어긋나면 에러 없이
#   신호가 통째로 비므로, 조인 전 반드시 한 타입(Date)으로 내린다.
#   POSIXct 는 KST 로 내린다(러너의 RAWDATA 변환 규약 tz="Asia/Seoul" 과 동일 —
#   UTC 로 내리면 자정 근방에서 하루가 밀린다).
.as_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXct")) return(as.Date(x, tz = "Asia/Seoul"))
  as.Date(x)
}

# ── 조인 수율 계기 ──
# ★티커 포맷 불일치(RAWDATA/컨센서스 = QuantiWise "A005930" 접두 · 일부 DART 계열은
#   맨 6자리)는 에러 없이 **0행**으로만 나타난다. 그러면 뒤에서 "FACTORS 0행"이라는
#   엉뚱한 진단이 뜨고 진짜 원인이 묻힌다. 조인 직후 수율을 재고, 0이면 양쪽 티커
#   표본을 찍어 원인을 지목한 뒤 멈춘다("재기 쉬운 것 말고 잴 것을 잰다").
.assert_join <- function(nm, got, src_tk, elig_tk) {
  if (nrow(got) == 0L)
    stop(sprintf(paste0("[%s] %s 조인 0행 — 티커 포맷/기간 불일치 의심.\n",
                        "  적격측 티커 표본: %s\n  원천측 티커 표본: %s"),
                 .TAG, nm,
                 paste(head(sort(unique(as.character(elig_tk))), 5), collapse = ", "),
                 paste(head(sort(unique(as.character(src_tk))), 5), collapse = ", ")))
  cat(sprintf("[%s] %s 매칭 %s쌍 (적격 %s쌍 대비 %.1f%%)\n", .TAG, nm,
              format(nrow(got), big.mark = ","), format(nrow(.ELIG), big.mark = ","),
              100 * nrow(got) / nrow(.ELIG)))
}

# =============================================================================
# 1. 일별 패널 → 시그널일(월말) · 적격 유니버스 (C6 · C10)
# =============================================================================
.mcap_col <- if ("MarketCap" %in% names(RAWDATA)) {
  "MarketCap"
} else if ("Size" %in% names(RAWDATA)) {
  "Size"
} else {
  stop(sprintf("[%s] RAWDATA 에 MarketCap/Size 가 없다 — 실현 이익수익률 불가", .TAG))
}

.rd <- RAWDATA[Date >= .PANEL_FROM,
               c("Date", "Ticker", "Close", "Vol", "K200", "KQ150", .mcap_col), with = FALSE]
setnames(.rd, .mcap_col, "MCap")
.rd <- .rd[is.finite(Close) & Close > 0]
setorder(.rd, Ticker, Date)

# (Date,Ticker) 중복 방어. 중복이 남으면 by-Ticker shift 가 전제를 잃고 ADV20 이
#   조용히 어긋난다 — 에러 없이 유동성 필터만 바뀌는 침묵 실패다. 없으면 무연산.
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[%s] (Date,Ticker) 중복 %d행 — 첫 행만 남긴다\n", .TAG, .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}

.rd[, TV := Close * Vol]
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]  # C10 t-1
.rd[, TV := NULL]

.rd[, MI := year(Date) * 12L + month(Date)]
.mend <- .rd[, .(SigDate = max(Date)), by = MI]
setorder(.mend, MI)
.SIGD <- .mend[SigDate >= .SIG_FROM, SigDate]
if (length(.SIGD) == 0L)
  stop(sprintf("[%s] 시그널일 0건 — RAWDATA 날짜 범위 확인", .TAG))

# 적격: 시그널일의 K200/KQ150 멤버십(PIT 시변) + adv20(t-1) 하한 + 가격/시총 유효
.ELIG <- .rd[Date %in% .SIGD][
             (K200 | KQ150) & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ &
             is.finite(MCap) & MCap > 0,
             .(SigDate = Date, Ticker, Close, MCap)]
if (nrow(.ELIG) == 0L)
  stop(sprintf("[%s] 적격 종목 0건 — 멤버십/유동성 필터 확인", .TAG))

cat(sprintf("[%s] 시그널일 %d개 (%s ~ %s) | 적격 (시그널일,종목) %s쌍\n",
            .TAG, uniqueN(.ELIG$SigDate),
            as.character(min(.ELIG$SigDate)), as.character(max(.ELIG$SigDate)),
            format(nrow(.ELIG), big.mark = ",")))

# =============================================================================
# 2. f — 1년 시계 컨센서스 EPS (as-of, C12)
# =============================================================================
.p_eps <- file.path(.cache_dir, "consensus", "eps_1y.parquet")
if (!file.exists(.p_eps))
  stop(sprintf(paste0("[%s] 컨센서스 EPS 패널 부재: %s\n",
                      "  → 이 논문의 기전(f vs ε)은 컨센서스 없이는 성립하지 않는다.\n",
                      "  → consensus_build_cache() (02_Infrastructure/data/consensus_parser.R) 선행 필요."),
              .TAG, .p_eps))

.CONS <- as.data.table(read_parquet(.p_eps))
if (!all(c("Date", "Ticker", "eps_1y") %in% names(.CONS)))
  stop(sprintf("[%s] eps_1y 패널 스키마 불일치: %s", .TAG, paste(names(.CONS), collapse = ",")))
.CONS <- .CONS[, .(Date, Ticker, eps_1y)]
# ★타입 정규화: arrow 는 dictionary 인코딩 문자열을 **factor** 로, int64 를
#   **integer64** 로 돌려줄 수 있다. factor Ticker 는 character 키와 조인이 깨지고,
#   integer64 는 뒤의 fifelse(..., NA_real_) 에서 타입 불일치로 죽는다. 조인·산술
#   전에 한 번 내려둔다(이미 맞는 타입이면 무연산에 가깝다).
.CONS[, `:=`(Date = .as_date(Date), Ticker = as.character(Ticker),
             eps_1y = as.numeric(eps_1y))]
.CONS <- .CONS[!is.na(Date) & is.finite(eps_1y)]
.CONS <- unique(.CONS, by = c("Ticker", "Date"))          # 롤조인 전제
setkey(.CONS, Ticker, Date)

cat(sprintf("[%s] 컨센서스 eps_1y: %s행 · %d종 · %s ~ %s\n", .TAG,
            format(nrow(.CONS), big.mark = ","), uniqueN(.CONS$Ticker),
            as.character(min(.CONS$Date)), as.character(max(.CONS$Date))))

# ★as-of 롤조인 = PIT 그 자체. roll = .CONS_STALE_D 는 "관측일 <= 시그널일 이면서
#   시그널일로부터 31일 이내" 인 **마지막** 행만 집는다. 미래 행은 구조적으로 도달 불가.
.q <- .ELIG[, .(Ticker, Date = SigDate, SigDate)]
setkey(.q, Ticker, Date)
.F <- .CONS[.q, on = .(Ticker, Date), roll = .CONS_STALE_D]
.F <- .F[is.finite(eps_1y), .(SigDate, Ticker, eps_1y)]
.assert_join("컨센서스 eps_1y", .F, .CONS$Ticker, .ELIG$Ticker)

# =============================================================================
# 3. ε_last — 직전 실현 순이익 (as-of, C4 자체 하한)
# =============================================================================
# 원천 우선순위: fundamental_merged(장기 커버리지, 인프라 정본) → fundamental_dart(연간).
# 어느 쪽이든 최종 산출은 data.table(Ticker, Avail, NI) 하나로 정규화한다.
.load_realized_ni <- function() {
  # ---- (A) fundamental_merged.parquet — long: Ticker/Item/Value[/TTM_Value]/Factor_Date[/Period_Date]
  p_m <- file.path(.cache_dir, "fundamental_merged.parquet")
  if (file.exists(p_m)) {
    m <- tryCatch(as.data.table(read_parquet(p_m)), error = function(e) NULL)
    if (!is.null(m) && nrow(m) > 0L &&
        all(c("Ticker", "Item", "Value", "Factor_Date") %in% names(m))) {
      want <- c("NetIncome", "PretaxIncome", "TaxExpense")
      # 타입 정규화(위 컨센서스와 같은 이유 — arrow factor/integer64 방어).
      #   Item 이 factor 면 %chin% 이 곧바로 죽으므로 필터 **전에** 내린다.
      m[, `:=`(Ticker = as.character(Ticker), Item = as.character(Item))]
      m <- m[Item %chin% want]
      if (nrow(m) > 0L) {
        m[, Factor_Date := .as_date(Factor_Date)]
        # P/L 항목은 TTM 우선(인프라 정본 = compute_value.R 의 use_val 규약)
        if ("TTM_Value" %in% names(m)) {
          m[, use_val := fifelse(!is.na(as.numeric(TTM_Value)),
                                 as.numeric(TTM_Value), as.numeric(Value))]
        } else {
          m[, use_val := as.numeric(Value)]
        }
        m <- m[is.finite(use_val) & !is.na(Factor_Date)]

        # ★C4 자체 하한: Avail = max(Factor_Date, Period_Date + 90d).
        #   Period_Date 가 없거나 NA 면 원천 Factor_Date 를 그대로 쓴다(더 이르게
        #   만들지 않는다). pmax 라서 Period_Date 의 의미를 잘못 짚어도 원천보다
        #   **이른** 가용일이 나올 수 없다 — 실패 모드가 한쪽(보수적)으로만 열린다.
        if ("Period_Date" %in% names(m)) {
          m[, PD := .as_date(Period_Date)]
        } else {
          m[, PD := as.Date(NA_character_)]
        }
        m[, Avail := Factor_Date]
        # pmax 는 Date 속성 보존이 R 버전마다 미묘하다 — 수치로 내려 비교하고 되올린다.
        m[!is.na(PD), Avail := as.Date(pmax(as.numeric(Factor_Date),
                                            as.numeric(PD) + .C4_ANNUAL_D),
                                       origin = "1970-01-01")]

        # 같은 회계기간의 항목들을 한 행으로 묶는 키. Period_Date 가 있으면 그것으로,
        #   없는 행은 Avail 로 대체한다(부분 결측도 안전하게 처리).
        m[, GKEY := fifelse(is.na(PD), as.character(Avail), as.character(PD))]
        # 항목별 Avail 이 갈리면 **가장 늦은 쪽**으로 통일(보수적).
        m[, AvailG := max(Avail), by = .(Ticker, GKEY)]
        # 같은 (Ticker,기간,Item) 에 복수 행(정정·원천 중복)이 있으면 가용일이 가장
        #   늦은 = 가장 최신 판을 집도록 정렬해 둔다(아래 fun.aggregate 가 마지막을 집는다).
        setorderv(m, c("Ticker", "GKEY", "Item", "Avail"))

        w <- dcast(m, Ticker + GKEY + AvailG ~ Item,
                   value.var = "use_val",
                   fun.aggregate = function(x) if (length(x)) x[length(x)] else NA_real_)
        for (cc in want) if (!cc %in% names(w)) w[, (cc) := NA_real_]
        # NetIncome 항목이 있으면 그대로, 없으면 세전이익 − 법인세(= compute_value.R 구성)
        w[, NI := fifelse(is.finite(NetIncome), NetIncome,
                          fifelse(is.finite(PretaxIncome) & is.finite(TaxExpense),
                                  PretaxIncome - TaxExpense, NA_real_))]
        # 서로 다른 회계기간이 같은 가용일로 떨어질 수 있다(정정·TTM/연간 중첩).
        #   그럴 땐 **더 최근 기간**을 남긴다 — GKEY 오름차순 정렬 후 아래 dedup 이
        #   fromLast 로 마지막(=최신 기간)을 집는다. 정렬 없이 dedup 하면 임의의
        #   (사실상 가장 오래된) 기간이 남는다.
        setorderv(w, c("Ticker", "AvailG", "GKEY"))
        out <- w[is.finite(NI), .(Ticker, Avail = AvailG, NI)]
        if (nrow(out) > 0L) {
          cat(sprintf("[%s] 실현 순이익 원천 = fundamental_merged (%s행 · %d종 · Avail %s ~ %s)\n",
                      .TAG, format(nrow(out), big.mark = ","), uniqueN(out$Ticker),
                      as.character(min(out$Avail)), as.character(max(out$Avail))))
          return(out)
        }
      }
    }
  }
  # ---- (B) fundamental_dart.parquet — wide 연간: Ticker/bsns_year/Factor_Date/NetIncome
  p_d <- file.path(.cache_dir, "fundamental_dart.parquet")
  if (file.exists(p_d)) {
    d <- tryCatch(as.data.table(read_parquet(p_d)), error = function(e) NULL)
    if (!is.null(d) && nrow(d) > 0L &&
        all(c("Ticker", "Factor_Date", "NetIncome") %in% names(d))) {
      d[, `:=`(Factor_Date = .as_date(Factor_Date), Ticker = as.character(Ticker),
               NetIncome = as.numeric(NetIncome))]
      out <- d[is.finite(NetIncome) & !is.na(Factor_Date),
               .(Ticker, Avail = Factor_Date, NI = NetIncome)]
      # DART annual 의 Factor_Date 는 이미 bsns_year+1 의 3/31 = 12월말 + 90d → 하한 자동 충족.
      if (nrow(out) > 0L) {
        cat(sprintf("[%s] 실현 순이익 원천 = fundamental_dart (%s행 · %d종 · Avail %s ~ %s)\n",
                    .TAG, format(nrow(out), big.mark = ","), uniqueN(out$Ticker),
                    as.character(min(out$Avail)), as.character(max(out$Avail))))
        return(out)
      }
    }
  }
  stop(sprintf(paste0("[%s] 실현 순이익 패널을 못 찾았다 (fundamental_merged / fundamental_dart 모두 실패).\n",
                      "  → no-change 앵커 ε_last 없이는 이 논문의 기전(K2)이 성립하지 않는다."), .TAG))
}

.NIP <- .load_realized_ni()
gc(verbose = FALSE)   # 원천 재무 패널(수백만 행)은 로더 지역변수라 여기서 회수된다
# 롤조인 전제 = (Ticker,Avail) 유일. 동률이면 **뒤쪽**(= 위에서 정렬해 둔 최신 기간)을 남긴다.
#   setorder 는 안정 정렬이라 그 2차 순서가 보존된다.
setorder(.NIP, Ticker, Avail)
.NIP <- unique(.NIP, by = c("Ticker", "Avail"), fromLast = TRUE)
setkey(.NIP, Ticker, Avail)

.q2 <- .ELIG[, .(Ticker, Avail = SigDate, SigDate)]
setkey(.q2, Ticker, Avail)
.E <- .NIP[.q2, on = .(Ticker, Avail), roll = .FUND_STALE_D]
.E <- .E[is.finite(NI), .(SigDate, Ticker, NI)]
.assert_join("실현 순이익", .E, .NIP$Ticker, .ELIG$Ticker)

# =============================================================================
# 4. Score = ε_last/시총 − f/P   ( = −GOSSAMER )
# =============================================================================
.M <- merge(.ELIG, .F, by = c("SigDate", "Ticker"))
.M <- merge(.M,    .E, by = c("SigDate", "Ticker"))

.M[, fEP := eps_1y / Close]      # 1년 시계 컨센서스 이익수익률  (= f / P)
.M[, tEP := NI / MCap]           # 직전 실현 이익수익률           (= ε_last / P)
.M[, Score := tEP - fEP]         # = −[ (f − ε_last) / P ] = −GOSSAMER

.M <- .M[is.finite(Score)]

# 월 최소 횡단면(= 고정 축 top_n) 미만인 달은 신호를 내지 않는다.
.M[, n_x := .N, by = SigDate]
.thin <- .M[n_x < .NMIN, uniqueN(SigDate)]
.M <- .M[n_x >= .NMIN]
if (nrow(.M) == 0L)
  stop(sprintf(paste0("[%s] FACTORS 0행 — 어느 달도 횡단면 %d 종을 못 채웠다.\n",
                      "  컨센서스/재무 커버리지와 유니버스 교집합을 확인하라."), .TAG, .NMIN))

FACTORS <- .M[, .(Date = SigDate, Ticker, Score)]
setorder(FACTORS, Date, -Score)

# ── 연도별 커버리지 보고(진단 전용 — 신호로 되먹임되지 않는다) ──
#    초기 구간이 얇으면 로그에서 바로 드러나게 한다. 실행 불가를 침묵시키지 않는다.
.permonth <- FACTORS[, .N, by = Date]
.cov <- .permonth[, .(n_month = .N, n_med = as.integer(median(N))),
                  by = .(yr = year(Date))][order(yr)]
cat(sprintf("[%s] 연도별 커버리지 (월수 / 월중앙 종목수):\n  %s\n", .TAG,
            paste(sprintf("%d:%d/%d", .cov$yr, .cov$n_month, .cov$n_med), collapse = "  ")))

cat(sprintf(paste0("[%s] adapted: Score = ε_last/시총 − f/P = −GOSSAMER ",
                   "(논문 b = f − ε 의 사전판 · no-change 앵커 대비 초과분)\n",
                   "  월 %d개 (%s ~ %s) · FACTORS %s행 · 횡단면 %d 미만이라 버린 달 %d개\n",
                   "  fEP 중앙 %.4f · tEP 중앙 %.4f · GOSSAMER 중앙 %.4f (컨센서스가 no-change 앵커를 위로 잡은 평균 폭)\n",
                   "  ★군집비율 φ=Σ/σ 미구현(애널리스트 간 분산 패널 부재 — 대리변수 금지). FIDELITY.json 참조\n",
                   "  ★러너 호출: portfolio_spec=list(construction=\"top_n_long\", ",
                   "weighting=\"ew\", rebalance=\"monthly\", n_long=25) · commission_paper=NULL\n"),
            .TAG, uniqueN(FACTORS$Date),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
            format(nrow(FACTORS), big.mark = ","), .NMIN, .thin,
            median(.M$fEP), median(.M$tEP), median(.M$fEP - .M$tEP)))
