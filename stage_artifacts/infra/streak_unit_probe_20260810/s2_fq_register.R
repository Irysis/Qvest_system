#==============================================================================
# s2_fq_register.R — FQ-219(streak 단위) 등재 + SE02 후보 등재
#
# ★번호 하드코딩 금지 (도훈 지시): read -> 기존 항목 탐색 -> 없으면 max+1 -> 쓰기
#   -> **재읽기 확인**. 정본 writer 경유 (frontier_queue_io.R) — 직접 toJSON 금지.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
source(file.path(ROOT, "02_Infrastructure/ops/frontier_queue_io.R"))

Q <- read_frontier_queue()
n0 <- length(Q$entries)
cat(sprintf("[read] entries=%d\n", n0))
getid <- function(Q) vapply(Q$entries, function(e)
  if (is.null(e$id)) NA_character_ else as.character(e$id)[1], character(1))
ids <- getid(Q)
nums <- suppressWarnings(as.integer(sub("^FQ-0*", "", ids[grepl("^FQ-[0-9]+$", ids)])))
nums <- nums[!is.na(nums)]
cat(sprintf("[read] FQ 번호 %d .. %d\n", min(nums), max(nums)))

find_entry <- function(Q, kw) {
  which(vapply(Q$entries, function(e) {
    s <- paste(unlist(e[intersect(names(e), c("id","title","hypothesis","note",
                                              "mechanism","ev_rationale"))]), collapse = " ")
    any(vapply(kw, function(k) grepl(k, s, fixed = TRUE), logical(1)))
  }, logical(1)))
}

add_or_update <- function(Q, kw, build) {
  ids <- getid(Q)
  nums <- suppressWarnings(as.integer(sub("^FQ-0*", "", ids[grepl("^FQ-[0-9]+$", ids)])))
  nums <- nums[!is.na(nums)]
  hit <- find_entry(Q, kw)
  if (length(hit) == 1L) {
    id <- ids[hit]; cat(sprintf("[id] 기존 항목 갱신 %s\n", id))
    Q$entries[[hit]] <- build(id)
  } else {
    id <- sprintf("FQ-%03d", max(nums) + 1L)
    cat(sprintf("[id] 신규 max+1 = %s (기존 관련 %d건)\n", id, length(hit)))
    Q$entries[[length(Q$entries) + 1L]] <- build(id)
  }
  Q
}

# ── 1) FQ-219 streak 단위 (코드 수리 완료, 재빌드 대기) ─────────────────────
Q <- add_or_update(Q, c("streak 단위", "cons_streak", "C11_Earnings_Streak"), function(id) list(
  id = id,
  title = "streak 팩터 단위 수리 — C11/M25 를 영업일이 아니라 분기 릴리스로",
  status = "code_repaired_awaiting_rebuild",
  owner = "architect",
  opened = "2026-08-10",
  category = "infra_measurement_integrity",
  parent = "FQ-218 (.cons_history 무력 창) 의 같은 뿌리, 다른 증상",
  mechanism = paste0(
    "C11_Earnings_Streak / M25_Earnings_Mom_Streak 는 '연속 양수 SUE 의 개수'인데 ",
    ".cons_history() 가 준 **행**을 최신순으로 셌다. 원천 sue 는 일간 캐리포워드라 ",
    "한 분기 ≈ 60행 ⇒ 값의 단위가 분기가 아니라 **영업일**. 실측: 행/분기 비 41~70 ",
    "(unit_match 0.0000, 8 sig_date 전건), 저장값 raw_max 408~510(분기 카운트면 6~10). ",
    "부수 결함 2종 — (a) 결번 분기 교량: 양수 streak 종목의 10.7~13.7% 가 관측되지 않은 ",
    "분기를 가로질러 옛 양수 런을 이어붙였다 (b) stale 배출: sig 2026-06 기준 배출 1125행 중 ",
    "69.6% 가 최신 관측 400일 초과(커버리지가 죽은 종목에 옛 streak 을 현재 신호로 배출)."),
  discriminant = paste0(
    "★FQ-218 의 mean==latest 를 쓸 수 없다 — 그건 **평균** 팩터의 사망 서명이다(창이 ",
    "붕괴하면 항등변환). 카운트는 정보가 남고 **단위만 바뀐다**. 그래서 축이 다르다: ",
    "①단위(streak == 분기 수인가) ②연속성(결번 분기를 가로지르지 않는가) ",
    "③릴리스 의존(릴리스 없는 달에 값이 커지지 않는가 — 구 구현은 28~42% 종목이 매달 ~21씩 증가). ",
    "셋 다 행수 정상·NA 0·오류 0 상태에서 참이라 기존 n_rows/NA 축으로는 원리적으로 안 잡힌다."),
  repair = list(
    where = paste0("02_Infrastructure/factor_db/compute_consensus.R :: .cons_streak()/.cons_epoch() ",
                   "+ compute_momentum.R 동일 정의(빌더가 모듈을 별도 env 에 source 해 공유 불가)"),
    window_definition = paste0(
      "릴리스 epoch 리샘플(경계 4/1·6/1·9/1·12/1, epoch 당 마지막 관측) + 인접성 요구(결번 = 연속 아님) ",
      "+ 앵커 stale 상한 130일. ★.cons_quarters() 재사용 불가 — (a) 동률 병합이 카운트를 과소하고 ",
      "(b) 런 기반은 결번을 안 끊는다(epoch 결번률 0.1306)."),
    boundary_evidence = paste0(
      "달력 경계의 근거 = sue 값 변경이 100% 월초(dom<=5)이고 4/6/9/12월에 각 ~25%. ",
      "시대 안정성 4구간(2001-06/2007-12/2013-18/2019-26) 전부 경계 적중률 0.999+. ",
      "★초기 설계의 '릴리스 가드 5일'은 기준값 대조로 **반증**했다 — 경계를 밀면 분기의 ",
      "마지막 관측이 다음 분기 릴리스 직후 관측이 되어 다음 분기 값이 끌려온다 ",
      "(기준값 일치 guard0 0.9998 vs guard5 0.1652, 다음-분기 귀속 0.000 vs 0.835)."),
    twin_enforcement = paste0(
      "2026-08-08 에 'C11 과 M25 는 식·원천·정렬 동일'을 **기록만** 하고 강제가 없어 두 곳이 ",
      "같이 틀린 채 남았다. 이제 08_Tests 가 두 파일 함수 본문(deparse)·상수 일치를 매 실행 강제한다.")),
  validation = list(
    ab_test = paste0("OLD/NEW 별도 env 실행 대조 4 sig_date. raw_max 432/453/408/510 → 8/7/5/6, ",
                     "고유값 36~89 → 6~8, 커버리지 528/757/992/1125 → 310/300/280/294. ",
                     "C11 ≡ M25 최대절대차 0.0000000000 전건일치."),
    positive_control = "C11/M25/M32 외 consensus+momentum 전 팩터 180 팩터-월 조합 값 비트 불변(변경 0건)",
    propagation = paste0("M32_Composite_Mom_v2 = mean(z(M01,M10,M13,M24,M25)) 라 M25 를 소비 ⇒ 변경 예상. ",
                         "변경된 M32 티커의 100% 가 M25-touched 집합 안(4/4 sig_date) — 전파가 M25 로 전부 설명된다."),
    test = "08_Tests/factor_db/test_streak_quarter_unit.R (17/17 PASS, 위반 주입 4/4 검거) — run_all_hooks.sh 등재"),
  rebuild_scope = list(
    affected_months = 300, span = "200109..202608",
    integration = paste0("★FQ-218 의 303개월(200106..202608)의 **진부분집합**(B\\A = 0개월). ",
                         "통합 재빌드 = 303개월 317분으로 FQ-218 단독과 **동일 비용**. ",
                         "따로 하면 630분 ⇒ 통합 절감 314분."),
    note = "저장 단위가 월별 parquet 1개라 팩터 선택 재빌드 경로는 없다 — 영향월은 전 모듈이 함께 재계산된다."),
  next_probe = c(
    "재빌드 후 C11 의 rank-IC / PORT_t 재측정 — 단위 교정 + 커버리지 74% 축소가 신호력을 어떻게 바꾸는가 (구 값은 커버리지 밀도와 혼입돼 있었다: 잔차 rho 0.54~0.90)",
    "M25 배출 폐지 제안 — registry dedup DUPC-046 이 이미 C11 canonical / M25 alias(deprecated_for_selection) 로 판정. C14/C17 의 .CONSENSUS_DEPRECATED 선례와 대칭",
    "streak 계열 일반화 — 다른 '연속/누적 카운트' 팩터가 캐리포워드 원천 위에 있는지 (현 전수에서는 sue 계열 2종뿈)"),
  artifacts = "stage_artifacts/infra/streak_unit_probe_20260810/"
))

# ── 2) SE02 후보 (측정 완료, 수리 미착수 — 도훈 결정 대기) ──────────────────
Q <- add_or_update(Q, c("SE02_Consensus_Revision", "SE02 인접 행"), function(id) list(
  id = id,
  title = "SE02_Consensus_Revision — 인접 **행** 차분이 93~99% 정확히 0",
  status = "measured_awaiting_decision",
  owner = "dohoon_decision",
  opened = "2026-08-10",
  category = "infra_measurement_integrity",
  parent = "FQ-218/FQ-219 와 같은 계통 (캐리포워드 원천 위 위치-기반 창)",
  mechanism = paste0(
    "compute_crowding.R:422-428 이 date_rank==1 vs ==2, 즉 **인접 두 행**의 차로 개정률을 만든다. ",
    "원천 eps_1y / target_price 는 일간 캐리포워드이고 인접 행이 안 바뀌는 비율이 0.901 / 0.954 ",
    "⇒ SE02 가 정확히 0인 종목 비율 0.934~0.993(4 sig_date). 저장값 실측: modal_frac 0.914~0.959, ",
    "201403 월은 Coverage 0.000 / Z 전건 NA / 고유값 2 = 소비면 도달 0행. ",
    "달력 lag 판본(sig_d-63)과의 rank 상관은 -0.03~0.22 — 사실상 다른 것을 재고 있다."),
  discriminant = paste0(
    "★이 계통의 판별축은 '원천이 분기 계단인가'가 **아니다** — 12개 컨센서스 지표 전부 ",
    "인접-행 불변 비율이 0.88~0.985 다(상시 개정되는 revenue_fy1 도 0.895). ",
    "판별축은 **창이 위치-기반인가 달력-기반인가**. 같은 파일의 M26/M28/C14/C17 은 ",
    "`sig_date - 63L` 달력 lag 라 같은 원천에서도 멀쩡하다."),
  proposed_repair = paste0(
    "in-repo 선례 그대로: compute_consensus.R 의 `.revision_63d()` 와 동형 — 최신값 vs ",
    "`Date <= sig_d - 63L` 의 최신값. eps_1y 는 변경 간격 중앙 6일(상시 개정)이라 분기 epoch 이 ",
    "아니라 **달력 lag** 가 맞는 창이다(sue/esbr 과 다르다). 착수 전 창 길이 bakeoff 필요."),
  rebuild_scope = list(
    affected_months = 318, span = "200003..202608",
    integration = paste0("★FQ-218/219 통합(303개월)에 얹으면 합집합 318개월 = 332분. ",
                         "한계비용 **+15개월 / +16분**. 따로 하면 별도 332분 재빌드가 한 번 더 필요하다. ",
                         "⇒ 재빌드 착수 **전에** 수리 여부를 결정하는 것이 유리하다.")),
  next_probe = c(
    "lag 길이 bakeoff — 21/63/126일 중 무엇이 SE01/SE02 원 의도(센티먼트 개정 속도)에 맞는가",
    "SE01_Volatility_Uncertainty fallback 경로 점검 — 같은 블록의 dispersion 컬럼 부재 우회가 지금도 유효한가"),
  artifacts = "stage_artifacts/infra/streak_unit_probe_20260810/a6_se02_reproduce.csv"
))

write_frontier_queue(Q)

# ── 재읽기 확인 ─────────────────────────────────────────────────────────────
Q2 <- read_frontier_queue()
ids2 <- getid(Q2)
cat(sprintf("\n[verify] 재읽기 entries=%d (전 %d, 증분 %d)\n",
            length(Q2$entries), n0, length(Q2$entries) - n0))
for (kw in list(c("streak 단위","cons_streak"), c("SE02_Consensus_Revision"))) {
  h <- find_entry(Q2, kw)
  cat(sprintf("[verify] %-28s -> %s (status=%s)\n", kw[1],
              paste(ids2[h], collapse = ","),
              paste(vapply(h, function(i) as.character(Q2$entries[[i]]$status), character(1)),
                    collapse = ",")))
}
