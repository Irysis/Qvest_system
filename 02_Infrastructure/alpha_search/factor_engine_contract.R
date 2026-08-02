# =============================================================================
# factor_engine_contract.R — FQ-002 계약수주 magnitude
#
# 가설: 공시 계약금액의 **상대 규모**가 long-side directional 알파.
#   occurrence-only(발생 여부)는 null(t=0.59)로 이미 소진 — EV-지도 D4 판정.
#   magnitude(금액 크기)는 genuinely 미검증(real prior).
#
# 분모 A/B (DENOM 환경변수):
#   revenue (기본) : 계약금액 / 최근매출액 — **공시가 동봉하는 네이티브 분모**.
#                    KRX 가 매출 대비 비율로 공시를 의무화하므로 구조적으로 함께 실린다.
#                    시총 조인 불요 → 조인 결손·vintage 문제 원천 회피.
#   size           : 계약금액 / 시총(RAWDATA Size) — 원 가설의 분모. 시장가치 기준.
#
# ===== PIT =====
#   패널의 (ym, Ticker) 값은 **rcept_dt 가 그 달 안**인 공시만 누적한 것이다.
#   월말 시그널 날짜 t 에서 t 이하 공시만 보이므로 홀딩월(t+1) 수익에 대해 look-ahead 없음.
#   기재정정(사후 수정본)은 패널 단계에서 이미 제외 — 포함하면 "나중에 고쳐진 금액"을
#   과거에 쓰는 것이라 2026-07-06 오버레이 동월 look-ahead 사건과 동형이 된다.
#   ★외부 패널 의존이므로 detect_lookahead 정적분석이 이 파일 텍스트만 봐서는
#    상류 PIT 를 검사하지 못한다(alpha-search SKILL 경고). 상류 보증 = build_contract_panel.R
#    의 rcept_dt 컷오프 + is_correction 제외이며, 아래 assert 로 재확인한다.
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressPackageStartupMessages({ library(arrow) })

.fe_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
# CONTRACT_PANEL env 는 검사기 fixture 주입용 (실운영 = 기본 경로. builder 의 CONTRACT_PANEL_OUT 과 동형 장치)
.PANEL <- Sys.getenv("CONTRACT_PANEL",
                     unset = file.path(.fe_root(), ".cache/dart/contract_panel.parquet"))
if (!file.exists(.PANEL))
  stop("[fe_contract] 패널 부재 — build_contract_panel.R 먼저 실행. ",
       "빈 신호를 0 으로 채워 '알파 없음'으로 판정하지 않는다(미측정 != 신호부재).")

.DENOM <- Sys.getenv("DENOM", "revenue")
.P <- as.data.table(read_parquet(.PANEL))
cat(sprintf("[fe_contract] 패널 %d행 / %d종목 / %s~%s / window=%s scope=%s / DENOM=%s\n",
            nrow(.P), uniqueN(.P$Ticker), min(.P$ym), max(.P$ym),
            .P$window_m[1], .P$scope[1], .DENOM))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ym := format(Date, "%Y%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]

# 월말 행에 패널 조인 (같은 달 = 그 달 말까지 공시된 정보)
.ME <- RAWDATA[Date %in% .month_ends$Date, .(Date, Ticker, .ym, Size, LiqPass)]
.J  <- merge(.ME, .P[, .(.ym = ym, Ticker, w_amt, w_ratio, w_n)],
             by = c(".ym", "Ticker"), all.x = TRUE)

# 신호 없음(그 창에 계약 공시 없음) = 결측이지 0 이 아니다.
#  0 으로 채우면 "계약 없는 종목"이 최하위 점수로 랭킹에 참여해 유니버스를 왜곡한다.
#  run_monthly_simulation 은 상위 n_holdings 를 고르므로 NA 는 자연 제외된다.
.J[, .Score := switch(.DENOM,
      revenue = w_ratio,
      size    = ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_),
      stop("DENOM 은 revenue 또는 size"))]

FACTORS <- .J[LiqPass == TRUE & is.finite(.Score) & .Score > 0, .(Date, Ticker, Score = .Score)]

# ── 조인 무결성 assert (2026-08-02 수리) ──
# 구판 `ym > sig_ym & ym == sig_ym` 은 모순 조건 = 항상 0행 = 절대 발화 불가 —
# "빈 결과 = 합격" 계통의 재발 형태였다. 미래월 조인은 equality-key merge 라 구조적으로
# 불가능하므로(패널 ym == 시그널 ym), 이 계층의 **실재하는** 위험 = 패널 (ym,Ticker) 중복이
# merge fan-out 으로 같은 시그널 날짜에 행을 복제해 랭킹을 왜곡하는 것. 그것을 검사한다.
# 상류 PIT(rcept 컷오프·정정 제외·롤링 미래누출)의 보증 = 08_Tests/data/test_contract_panel.R.
if (anyDuplicated(.P[, .(ym, Ticker)]) > 0)
  stop("[fe_contract] 패널 (ym,Ticker) 중복 — merge fan-out 으로 신호 행 복제 위험")
if (anyDuplicated(FACTORS[, .(Date, Ticker)]) > 0)
  stop("[fe_contract] FACTORS (Date,Ticker) 중복 — 조인 fan-out 발생")
cat(sprintf("[fe_contract] FACTORS rows=%d | signal dates=%d | 월평균 종목수=%.1f\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            nrow(FACTORS) / max(1L, uniqueN(FACTORS$Date))))
if (!nrow(FACTORS))
  stop("[fe_contract] FACTORS 0행 — 조인 실패 가능성. 빈 팩터를 '알파 없음'으로 흘려보내지 않는다.")

RAWDATA[, .ym := NULL]
