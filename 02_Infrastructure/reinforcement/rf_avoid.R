#==============================================================================
# rf_avoid.R — 기전 회피 목록의 **표적 판정** (2026-09-05)
#
# 왜 생겼나 (실사고 2026-09-05 09:14 · promo2 B2 첫 칸):
#   러너는 부모 사슬 L-code 의 avoid 문장에 셀 코드가 나오고 측정 무효 키워드가 있으면
#   그 칸을 건너뛴다. 판정이 "코드가 문장 **어디에든** 있는가" 였다. 조부모 B4 회피문
#     "소형 유니버스 위에서 결합 칸 추가 — 세 칸이 전부 B2_6 아래이고 … 생존편향과 분리되지 않는다"
#   는 B2_6 을 **비교 기준**으로 언급했을 뿐인데 손자 B2_6(CDaR_LP · B2 설계의 머리 칸)이
#   표적으로 잡혔다. 같은 규칙으로 B3_11 회피문의 "소형 축은 B3_13 이 대체한다" 는
#   **권고 칸** B3_13 을 건너뛰게 만든다. 셀 코드는 entry 를 넘으면 같은 스펙을 가리키지도
#   않는다(조부모 B2_6 = 규칙 선정 비중 칸 · 손자 B2_6 = LLM 설계 CDaR_LP).
#   집행부가 att$n 을 등록 **전에** 읽어 R 오류로 죽는 바람에 이 오판이 드러났다 —
#   안 죽었으면 머리 칸이 "미결 — 기전 회피" 로 조용히 비었다(미측정 칸 = reinforce §0.3 위반).
#
# 규칙: 문장이 그 셀 코드로 **시작**할 때만 표적이다. 중간 언급은 표적도 기록도 아니다.
#   오판의 방향을 고른 것이다 — 놓치면 그 칸을 잰다(AX-000 기본값), 잘못 잡으면 칸이 빈다.
#   양방향 검사 = 08_Tests/reinforcement/test_rf_avoid_target.R (실사고 문장이 픽스처).
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## 측정 무효 사유 어휘 — 이것만 집행한다. 성과 사유는 사실 기록이다(AX-000).
RF_AVOID_INVALID_RE <- "측정 무효|편의|편향|누출|look-?ahead|미래참조|PIT"

## 문장이 그 셀 코드로 시작하는가 (앞 공백·여는 괄호 허용). "B2_6" 이 "B2_60" 과 섞이지 않게
## 뒤에 숫자가 오면 불일치.
rf_avoid_targets_cell <- function(x, cell_code) {
  grepl(sprintf("^[[:space:]]*[([]?%s([^0-9]|$)", cell_code), x)
}

#' @param avoid  L-code 의 avoid 벡터/리스트
#' @param cell_code  판정할 셀 코드 (예 "B2_6")
#' @return list(hit = 측정 무효 표적 문장(첫 건) 또는 NULL, noted = 성과 사유 표적 문장들)
rf_avoid_target <- function(avoid, cell_code) {
  avoid <- as.character(unlist(avoid %||% list()))
  avoid <- avoid[!is.na(avoid) & nzchar(avoid)]
  hit <- NULL; noted <- character(0)
  for (x in avoid) {
    if (!rf_avoid_targets_cell(x, cell_code)) next
    if (grepl(RF_AVOID_INVALID_RE, x)) { if (is.null(hit)) hit <- x }
    else noted <- c(noted, x)
  }
  list(hit = hit, noted = noted)
}
cat("[rf_avoid.R] Loaded — rf_avoid_target(avoid, cell_code) / rf_avoid_targets_cell()\n")
