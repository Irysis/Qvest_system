## overlay_precheck.R — 선별 오버레이 제안의 착수 전 판정 (2026-08-10 신설)
##
## 왜 있나: 2026-08-10 에 **세 경로가 독립적으로 같은 원리에 도달**했고 실제 PORT_t 로 확인됐다.
##   **선별 오버레이는 base 의 선호를 되돌리는 연산이다** — base 가 이미 선호하는 것을 자르면 손해다.
##   실측(4 base · 2-arm canonical_screen_bt · 커버리지 전건 1.0):
##     FAM_L q1 0.148 → Δ **+0.736** · FAM_CR 0.150 → +0.210 · FAM_S 0.195 → +0.116
##     **PG2 q1 0.308 → Δ −0.846**
##   ⇒ **q1 순서와 Δ 부호가 정확히 갈린다**(q1 = base 의 top-25 중 오버레이가 자를 분위의 비중).
##   경로: ①FQ-170 순열 통제 4/4(core4 Δ −0.293) ②FQ-168 P14(PG2 가 q1 을 19% 초과 보유)
##         ③P15(위 4점).
##
## 무엇을 하나: 오버레이를 제안하기 **전에** base 의 q1 비중으로 GO/CAUTION/NO_GO 를 낸다.
##   판정은 **경고이지 차단이 아니다** — 근거가 4점이고 문턱은 잠정이다(아래 CAVEAT).
##
## ⚠CAVEAT (인용 시 함께 옮길 것):
##   ①**자본 후보 아님** — 개선된 base 들은 t_base −2.4/−1.1/+0.4 이고 오버레이 후 **최고 +0.538**.
##     이 레버는 **약한 재료를 덜 나쁘게** 만들 뿐이다. "오버레이가 알파를 만든다" 는 오독.
##   ②문턱(0.25)은 **균등 분위 비중**이라는 자연 기준일 뿐 최적화된 값이 아니다.
##   ③★★**이 계약은 reversal 계열 처리 전용이다** (2026-08-10 P20 실측):
##     D03 밴드로 일반화를 시험했더니 **Q2_PARTIAL** — 방향은 맞으나(상위3 Δ +0.712 vs 하위3 +0.922)
##     차이가 0.21 로 미미하고, **강한 검정점이 빗나갔다**: 유일한 음수 Δ(−0.381)를 낸 CORE4_EW 의
##     band_share 가 **20 중 10위(0.2194, 중앙 근처)** 였다.
##     ⇒ **공통 원리는 유지되나 예측자가 처리마다 다르다**:
##       · **reversal** = base 가 **선호하는 종목**을 자름 ⇒ 예측자 = `q1 비중`(이 계약)
##       · **D03 밴드** = base 의 **순위 구간(14~25)** 을 버림 ⇒ 예측자 = 그 구간의 base-내 가치
##         (FQ-170 P8a: core4 는 14~25 가 **자기 최고 구간** 8.875 > top-13 의 5.323이라 버리는 게 비쌌다)
##     ⇒ **다른 처리에 이 q1 문턱을 적용하지 말 것.** 표의 `treatment` 필드를 확인하고,
##       새 처리는 **그 처리의 예측자를 따로 세워** 등재한다.
##
## 자매 계약: cluster_power.R(상관·군집 검정력) · required_effect_size.R(평균·DiD)

## 이 문턱이 검증된 처리 계열. P20(2026-08-10)이 **범위 밖 처리에는 서지 않음**을 실측했으므로
## 계약이 스스로 거부한다 — 주석 경고는 dead 가 되지만 거부는 배선이다.
CP_OVERLAY_Q1_SCOPE <- c("within_sector_reversal", "reversal")

## 처리별로 **이미 시험해 실패한 예측자**. 같은 곳을 다시 파지 않도록 계약이 들고 있는다.
## (오늘 P17a 와 P23/P23b 가 rel14 를 두 설계로 각각 시험했고 둘 다 미달했다.)
CP_OVERLAY_KNOWN_DEAD_PREDICTORS <- list(
  d03_band = paste0(
    "rel14(base 의 랭크 14~25 가 자기 구간들 중 어디쯤인가) = **2회 실패**. ",
    "P17a 계열-간 상관 rho 0.162/-0.070(임계 0.273) · P23b 동점군 대조 +1.961/-0.061(둘 다 해상도 아래). ",
    "★기각 사유가 검정력이 아니다 — **rel14 자체가 지속적 base 성질이 아니다**: ",
    "홀수달로 정의한 rel14==1 군과 짝수달로 정의한 군의 **Jaccard 0.182**(22 중 4 겹침). ",
    "⇒ 기전 서술(core4 의 14~25 가 자기 최고 구간이라 버리면 비쌌다)은 **실현 표본의 참인 서술**이지 ",
    "사전 예측자가 아니다. ⚠공유항 오염판은 rho -0.632·순열 p 0.000 으로 **확증처럼 보인다** — ",
    "홀/짝 교차 없이 이 수치를 인용하면 없는 기전을 확립하게 된다. ",
    "FQ-170 이 같은 결론에 독립 도달(그 가치는 지속적이지 않아 사전 판단 불가 ⇒ 밴드는 기본 ON)."
  )
)

## q1 이 **지속적 base 성질인가** — 자기 명제를 rel14 와 같은 칼로 잰 결과 (P24, 2026-08-10).
## 이 계약을 쓰기 전에 이 필드를 읽을 것: 문턱이 실현-표본 서술이면 판정은 사후 라벨일 뿐이다.
CP_OVERLAY_Q1_PERSISTENCE <- list(
  verdict = "J1_PERSISTENT",
  spearman_odd_even = 0.981,
  group_jaccard = 0.800,            # 문턱(>=0.25) '높음' 군의 홀/짝 겹침
  rel14_jaccard_reference = 0.182,  # 같은 척도로 죽은 예측자 (P23b)
  verdict_flips = "3/22 — 전부 0.243~0.259 (CAUTION 밴드), GO<->NO_GO 횡단 0건",
  key4_stable = "근거 4점 전부 홀/짝 판정 불변 (PG2 NO_GO 양쪽, FAM_L/CR/S GO 양쪽)",
  ## ⚠한정 — 인용 시 함께 옮길 것
  caveat = paste0(
    "홀/짝 교대는 **약한 지속성 시험**이다 — 인접 월이 같은 국면을 공유하므로 시대-분할보다 관대하다. ",
    "요점은 **rel14 가 이 약한 시험조차 통과 못 했다**는 것이고, q1 의 통과는 '**rel14 와 다르다**' 까지다. ",
    "'시대를 넘어 안정하다' 는 **미검** — 시대-분할 재측정이 다음 관문."
  ),
  lesson = paste0(
    "**평균-비중 통계는 지속적이고 argmax/위치 통계는 아니다.** ",
    "rel14 는 4구간 중 최대 위치라 구조적으로 불안정했다(Jaccard 0.182). ",
    "새 예측자를 설계할 때 **먼저** 물을 것 — 이 양은 평균인가 위치인가."
  )
)

#' 이 처리에 대해 이미 죽은 예측자가 있는가 (라운드 착수 전 조회)
#' @return 설명 문자열 또는 NA (기록 없음 — '없음'이 아니라 '미기록')
overlay_dead_predictor <- function(treatment) {
  if (!length(treatment)) return(NA_character_)
  tr <- as.character(treatment)[1]
  hit <- names(CP_OVERLAY_KNOWN_DEAD_PREDICTORS)[
    vapply(names(CP_OVERLAY_KNOWN_DEAD_PREDICTORS),
           function(k) grepl(k, tr, fixed = TRUE), TRUE)]
  if (!length(hit)) return(NA_character_)
  CP_OVERLAY_KNOWN_DEAD_PREDICTORS[[hit[1]]]
}

#' 오버레이 착수 전 판정
#' @param q1_share base 의 top-25 중 **오버레이가 자를 분위**의 평균 비중 (0~1)
#' @param base_label 보고용 이름
#' @param treatment 오버레이 처리 계열. 기본 "within_sector_reversal".
#'   **범위 밖이면 OUT_OF_SCOPE** — P20 에서 D03 밴드 일반화가 Q2_PARTIAL 로 미달했다.
#' @return list(verdict, message, ...) — verdict ∈ GO / CAUTION / NO_GO / INVALID / OUT_OF_SCOPE
overlay_q1_precheck <- function(q1_share, base_label = NA_character_,
                                treatment = "within_sector_reversal") {
  tr <- if (length(treatment)) as.character(treatment)[1] else NA_character_
  if (is.na(tr) || !any(vapply(CP_OVERLAY_Q1_SCOPE, function(s) grepl(s, tr, fixed = TRUE), TRUE)))
    return(list(verdict = "OUT_OF_SCOPE", q1_share = suppressWarnings(as.numeric(q1_share)),
                base_label = base_label, treatment = tr,
                dead_predictor = overlay_dead_predictor(tr),
                message = sprintf(paste0(
                  "처리 '%s' 는 이 문턱의 검증 범위 밖이다(검증 = %s). ",
                  "P20 실측: D03 밴드에서 상위3 Δ +0.712 vs 하위3 +0.922 로 분리 미미하고 ",
                  "**유일 음수 Δ 를 낸 CORE4_EW 가 band_share 20 중 10위**. ",
                  "원리(오버레이는 base 의 판단을 되돌린다)는 유지되나 **예측자가 처리마다 다르다** — ",
                  "이 처리의 예측자를 따로 세워 등재할 것. q1 문턱을 전용하지 말 것."),
                  tr, paste(CP_OVERLAY_Q1_SCOPE, collapse = "/"))))
  q <- suppressWarnings(as.numeric(q1_share))
  if (!length(q) || !is.finite(q) || q < 0 || q > 1)
    return(list(verdict = "INVALID", q1_share = q1_share, treatment = tr,
                message = "q1_share 는 0~1 의 유한값이어야 한다 — 미측정을 0 으로 대체하지 말 것"))
  ## ★CAUTION 밴드의 근거는 잠정 완충이 아니라 **실측**이다 (P24, 2026-08-10):
  ##   홀/짝 분할서 판정이 바뀐 base 3/22 가 **전부 0.243~0.259** — 즉 이 밴드 안팎.
  ##   GO↔NO_GO 를 건너뛴 base 는 **0건**. 밴드가 정확히 흔들림이 사는 구간을 덮는다.
  v <- if (q >= 0.28) "NO_GO" else if (q >= 0.25) "CAUTION" else "GO"
  msg <- switch(v,
    NO_GO = sprintf(paste0("q1 %.3f >= 0.28 — base 가 자를 대상을 **과대 보유**한다. ",
      "오버레이는 base 의 선호를 되돌린다(실측 PG2 0.308 → Δ -0.846). **얹지 말 것**."), q),
    CAUTION = sprintf(paste0("q1 %.3f — 균등(0.250) 근방. 부호가 갈리는 구간이라 ",
      "**소규모 A/B 로 부호부터 확인**하고 진행할 것."), q),
    GO = sprintf(paste0("q1 %.3f < 0.250 — base 가 자를 대상을 덜 담는다. 오버레이가 이득일 여지 ",
      "(실측 0.148~0.195 에서 Δ +0.116~+0.736). ⚠단 그 base 자체가 약해 **자본까지는 안 간다**."), q))
  list(verdict = v, q1_share = q, base_label = base_label, treatment = tr, message = msg,
       thresholds = c(caution = 0.25, no_go = 0.28),
       evidence = "P15 4점(FAM_L/CR/S vs PG2) · FQ-170 순열 4/4 · FQ-168 P14",
       scope_note = "reversal 계열 전용 — P20 에서 D03 밴드 일반화 Q2_PARTIAL(미달)",
       persistence = CP_OVERLAY_Q1_PERSISTENCE)
}

#' 실측 q1 표에서 조회 (2026-08-10 · 22 base)
#' @return q1_share 또는 **NA**(미측정 — 0 으로 위장하지 않는다)
overlay_q1_lookup <- function(base_label, table_path = NULL) {
  if (is.null(table_path)) {
    root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
    cand <- c(file.path(root, "06_Registry/overlay_base_q1_share_20260810.json"),
              "06_Registry/overlay_base_q1_share_20260810.json")
    table_path <- cand[file.exists(cand)][1]
  }
  if (is.na(table_path[1]) || !file.exists(table_path[1])) return(NA_real_)
  tb <- tryCatch(jsonlite::fromJSON(table_path[1]), error = function(e) NULL)
  if (is.null(tb) || is.null(tb$bases)) return(NA_real_)
  b <- tb$bases
  i <- match(base_label, b$base)
  if (is.na(i)) return(NA_real_)
  as.numeric(b$q1[i])
}

if (identical(environment(), globalenv()) && !interactive())
  cat("[overlay_precheck.R] Loaded — overlay_q1_precheck() / overlay_q1_lookup()\n")
