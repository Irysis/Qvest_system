#==============================================================================
# build_contract_panel.R — FQ-002 계약수주 magnitude 패널 빌더
#
# 입력: .cache/dart/contract_backfill/<YYYYMM>.csv  (dart_contract_backfill.R 산출)
# 출력: .cache/dart/contract_panel.parquet
#         (ym, Ticker, n_contracts, amt_sum, ratio_rev_sum, is_amend_any, flags…)
#
# 2026-08-02 신설 (FQ-002). 게이트 실측 근거:
#   · 공시가 최근매출액을 동봉 → 시총 조인 없이 네이티브 분모(ratio_to_revenue) 사용 가능
#   · RAWDATA 에 Size(시총)도 있어 분모 A/B 양쪽 산출 가능
#   · 유니버스 348사에 체결 40건/월 → **월 커버리지 ~11%로 희소**.
#     1개월 윈도우는 대부분 종목이 0 → 신호가 아니라 이벤트 더미가 된다.
#     따라서 trailing 윈도우(기본 12개월) 누적이 기본형이고, 윈도우는 실측 대상이다.
#
# ★PIT (C5 정합):
#   신호월 M 의 값 = **rcept_dt 가 M 말일 이전인 공시만** 누적. 월말 시그널 날짜에
#   그 시점까지 공시된 정보만 들어가므로 홀딩월(M+1) 수익에 대해 look-ahead 없음.
#   기재정정(is_correction)은 **사후 수정본**이므로 신호에서 제외 — 포함하면
#   "나중에 고쳐진 금액"을 과거에 쓰는 것이 되어 동월 look-ahead 와 동형이다.
#   정정본은 누출검증 A/B 용으로 패널에 별도 컬럼으로만 보존한다.
#
# Usage:
#   Rscript 02_Infrastructure/alpha_search/build_contract_panel.R
#   [WINDOW_M=12 SCOPE=all|new_only]
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

.cp_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (!length(hit)) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
ROOT <- .cp_root()
# CKDIR/OUT 은 검사기가 합성 픽스처로 로직을 검증할 수 있도록 env 로 덮을 수 있다.
# (실운영은 기본값 사용 — 테스트가 실데이터 디렉토리를 건드리지 않게 하는 장치)
CKDIR <- Sys.getenv("CONTRACT_CKDIR", unset = file.path(ROOT, ".cache/dart/contract_backfill"))
OUT   <- Sys.getenv("CONTRACT_PANEL_OUT", unset = file.path(ROOT, ".cache/dart/contract_panel.parquet"))
WINDOW_M <- as.integer(Sys.getenv("WINDOW_M", "12"))
SCOPE    <- Sys.getenv("SCOPE", "all")   # all | new_only(변경계약 제외)

fs <- list.files(CKDIR, pattern = "^\\d{6}\\.csv$", full.names = TRUE)
if (!length(fs)) stop(sprintf("체크포인트 없음: %s — dart_contract_backfill.R 먼저 실행", CKDIR))
cat(sprintf("[panel] 체크포인트 %d개월\n", length(fs)))

raw <- rbindlist(lapply(fs, function(f) fread(f, colClasses = list(character = "corp_code"))),
                 fill = TRUE)
# note-only 월(공시 0건)은 데이터 행이 없다 — 커버리지 진단에만 쓰고 신호에선 제외
if (!"rcept_no" %in% names(raw)) stop("[panel] 체크포인트에 데이터 행 없음(전부 note 행)")
D <- raw[!is.na(rcept_no)]

cat(sprintf("[panel] 원시 %d행 / parse_status 분포:\n", nrow(D)))
print(D[, .N, by = parse_status][order(-N)])

# ★결손을 조용히 버리지 않는다 — 제외 건수를 명시 보고
# ★2026-08-03: **원문 부재를 파싱 실패와 분리**한다. DART 는 2019 이전 기재정정에
#   원문(document.xml)을 아예 주지 않는다(status 014) — 파서가 못 읽은 게 아니라
#   읽을 것이 없다. 둘을 한 숫자에 담으면 성공률이 왜곡되고("파싱이 나쁘다"로 오독),
#   반대로 파서 회귀가 원문부재 증가에 묻힌다.
NO_SOURCE <- c("NO_SOURCE_CORRECTION", "NO_SOURCE_014")
n_nosrc <- nrow(D[parse_status %in% NO_SOURCE])
n_bad   <- nrow(D[!parse_status %in% c("OK", NO_SOURCE)])
n_avail <- nrow(D) - n_nosrc
n_cor   <- nrow(D[is_correction == TRUE])
cat(sprintf("[panel] 원문제공 %d건 중 OK %d (%.1f%%) / 파싱실패 %d | 원문부재(DART 014) %d건\n",
            n_avail, nrow(D[parse_status == "OK"]),
            if (n_avail > 0) 100 * nrow(D[parse_status == "OK"]) / n_avail else NA_real_,
            n_bad, n_nosrc))
cat(sprintf("[panel] 제외: 기재정정 %d건(신호 제외·누출검증용 보존)\n", n_cor))
# 무결성 교차검사(파서 v3 이후 열): 금액/매출 추출이 공시 동봉 `매출액대비(%)` 와 어긋난 행.
if ("ratio_check" %in% names(D)) {
  mm <- D[parse_status == "OK" & ratio_check == "MISMATCH"]
  cat(sprintf("[panel] ratio_check MISMATCH %d건 (비정정 %d건) — 추출 신뢰 저하 표시\n",
              nrow(mm), nrow(mm[is_correction == FALSE])))
}

S <- D[parse_status == "OK" & is_correction == FALSE]
if (identical(SCOPE, "new_only")) {
  n_am <- nrow(S[is_amendment == TRUE])
  S <- S[is_amendment == FALSE]
  cat(sprintf("[panel] SCOPE=new_only → 변경계약 %d건 추가 제외\n", n_am))
}
if (!nrow(S)) stop("[panel] 유효 행 0 — 신호 생성 불가(빈 패널을 정상으로 취급하지 않는다)")

# corp_code → Ticker
map <- unique(fread(file.path(ROOT, ".cache/dart/universe_corpcodes.csv"),
                    colClasses = "character")[, .(corp_code, Ticker = ticker)])
S <- merge(S, map, by = "corp_code", all.x = TRUE)
n_unmapped <- nrow(S[is.na(Ticker)])
if (n_unmapped) cat(sprintf("[panel] ⚠ ticker 미매핑 %d건 — 제외(유니버스 이탈 종목)\n", n_unmapped))
S <- S[!is.na(Ticker)]

S[, ym := substr(as.character(rcept_dt), 1, 6)]

# 월별 종목 집계 (해당 월 공시분)
M <- S[, .(n_contracts = .N,
           amt_sum       = sum(contract_amount, na.rm = TRUE),
           ratio_rev_sum = sum(ratio_to_revenue, na.rm = TRUE),
           amend_n       = sum(is_amendment %in% TRUE),
           round_n       = sum(rounding_flag %in% TRUE),
           fx_n          = sum(fx_flag %in% TRUE)),
       by = .(ym, Ticker)]

# trailing WINDOW_M 누적 — 희소성 대응. 각 (Ticker, ym) 에 대해 과거 W개월 합.
all_ym <- sort(unique(M$ym))
grid <- CJ(ym = all_ym, Ticker = unique(M$Ticker), unique = TRUE)
P <- merge(grid, M, by = c("ym", "Ticker"), all.x = TRUE)
for (cl in c("n_contracts", "amt_sum", "ratio_rev_sum", "amend_n", "round_n", "fx_n"))
  set(P, which(is.na(P[[cl]])), cl, 0)
setorder(P, Ticker, ym)
roll <- function(x) frollsum(x, WINDOW_M, align = "right", na.rm = TRUE)
P[, `:=`(w_n     = roll(n_contracts),
         w_amt   = roll(amt_sum),
         w_ratio = roll(ratio_rev_sum),
         w_amend = roll(amend_n)), by = Ticker]
P <- P[!is.na(w_n) & w_n > 0]

cat(sprintf("[panel] 출력 %d행 / %d종목 / %s~%s / WINDOW_M=%d SCOPE=%s\n",
            nrow(P), uniqueN(P$Ticker), min(P$ym), max(P$ym), WINDOW_M, SCOPE))
cat(sprintf("[panel] 월평균 신호보유 종목수 = %.1f (유니버스 348 대비 %.1f%%)\n",
            nrow(P) / uniqueN(P$ym), 100 * (nrow(P) / uniqueN(P$ym)) / 348))

P[, `:=`(window_m = WINDOW_M, scope = SCOPE,
         metric_type = "raw_disclosure", built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))]
write_parquet(P, OUT)
cat(sprintf("[panel] → %s\n", OUT))
