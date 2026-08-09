#==============================================================================
# s2_fq_register.R — FQ-218 큐 등재 (번호는 **쓰기 직전** 해석)
#
# ★번호 하드코딩 금지 (도훈 지시): 오늘 착수~완료 사이에 번호가 두 번 이동했다.
#   read -> 기존 항목 탐색 -> 없으면 max+1 -> 쓰기 -> **재읽기 확인**.
# 정본 writer 경유 (02_Infrastructure/ops/frontier_queue_io.R) — 직접 toJSON 금지
#   (digits 반올림 + pretty 불일치로 남의 측정값을 훼손한 전례).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
source(file.path(ROOT, "02_Infrastructure/ops/frontier_queue_io.R"))

Q <- read_frontier_queue()
cat(sprintf("[read] entries=%d\n", length(Q$entries)))

ids <- vapply(Q$entries, function(e) if (is.null(e$id)) NA_character_ else as.character(e$id)[1],
              character(1))
nums <- suppressWarnings(as.integer(sub("^FQ-0*", "", ids[grepl("^FQ-[0-9]+$", ids)])))
nums <- nums[!is.na(nums)]
cat(sprintf("[read] FQ 번호 범위 %d .. %d (n=%d)\n", min(nums), max(nums), length(nums)))

# 이 라운드가 이미 등재돼 있는가 (제목/키워드로 탐색 — 번호를 가정하지 않는다)
hit <- which(vapply(Q$entries, function(e) {
  s <- paste(unlist(e[intersect(names(e), c("id", "title", "hypothesis", "note",
                                            "mechanism", "ev_rationale"))]),
             collapse = " ")
  grepl("cons_history", s, fixed = TRUE) || grepl("무력 창", s, fixed = TRUE) ||
  grepl("inert_rolling_window", s, fixed = TRUE)
}, logical(1)))
cat(sprintf("[scan] 기존 관련 항목 %d건: %s\n", length(hit),
            paste(ids[hit], collapse = ", ")))

FQ_ID <- if (length(hit) == 1L) ids[hit] else sprintf("FQ-%03d", max(nums) + 1L)
cat(sprintf("[id] 사용할 id = %s (%s)\n", FQ_ID,
            if (length(hit) == 1L) "기존 항목 갱신" else "신규 max+1"))

entry <- list(
  id = FQ_ID,
  title = ".cons_history() 무력 창 수리 — C10/C13/C15 를 분기 릴리스 창으로",
  status = "code_repaired_awaiting_rebuild",
  owner = "architect",
  opened = "2026-08-10",
  category = "infra_measurement_integrity",
  mechanism = paste0(
    ".cons_history() 는 관측 **행**을 최신순으로 주는데 원천 sue/esbr 이 **일간 캐리포워드**다",
    "(관측 간격 중앙 1일, 값 변경 간격 중앙 91일). 그래서 mean(sue[1:4]) 가 4분기가 아니라 ",
    "3~5일을 평균했다 — 창 내 고유값 중앙 1.0, mean==latest 비율 1.0000 ⇒ 이동평균이 ",
    "**항등변환**. 결과: C10 ≡ C01 · C13 ≡ C04 비트동일, C15 전 종목 0 ⇒ 횡단면 sd 0 ⇒ ",
    "소비면 도달 0행(50/50월 죽은 배출)."),
  repair = list(
    where = "02_Infrastructure/factor_db/compute_consensus.R :: .cons_quarters()",
    window_definition = paste0(
      "연속-런(run) 붕괴 후 최신 N 분기 릴리스 + stale 소급 상한(n_take*130일) + 최소 2 릴리스. ",
      ".cons_history() 계약은 불변(C11/C14/C17/C18 보호)."),
    design_bakeoff = paste0(
      "W0 최신N행(현행) frac_eq 1.0000·고유값1 / W1 런dedup(채택) 0.124~0.154·고유값=n_take ",
      "/ W2 달력lag3M 0.610~0.633·고유값1·span중앙0 / W3 달력lag4M 0.584~0.601·고유값1. ",
      "달력 lag 는 커버리지 끊긴 종목에서 앵커가 전부 같은 관측에 붙어 결함이 재발한다."),
    pit = paste0(
      "런 경계 = 값이 패널에 처음 나타난 날 = 가용일. 실측: 값 변경 100%가 4/6/9/12월 ",
      "**첫 영업일**(월초 1~3일 100%, 월말 0%, 주말 0건) = 한국 분기 법정 제출기한 이후. ",
      "분기 종료일 스탬프가 아니므로 미래참조 아님. 런은 Date<=sig_d 조각 위에서만 계산."),
    bound_validation = paste0(
      "살아있는 정상격자 종목의 oldest-run age: sue p50=p95=p99=301.5일(최대 348) / ",
      "esbr 210.5일(최대 302). 상한 520/390일에 대해 frac_within_bound=1.000 — ",
      "상한이 legit 창을 하나도 자르지 않고 stale 소급만 막는다.")
  ),
  measured = list(
    frac_eq_latest = "C10 1.0000 -> 0.0000 · C13 1.0000 -> 0.0000 (8개월 전건)",
    identity = "C10~C01 rho 1.000->0.541 maxdiff 0->37837.5 · C13~C04 rho 1.000->0.570 maxdiff 0->1.736",
    c15_variance = "sd 0.0000 -> 426.91 · 0값 비율 1.0000 -> 0.0000 · 고유값 1 -> 239",
    window_distinct = "창 내 고유값 중앙 1 -> 4(C10)/3(C13)/2(C15) · span 3일 -> 301.5/210.5/90일",
    coverage = paste0(
      "C10 806->295 · C13 1230->416 · C15 806->239 (월 평균). 감소는 결손이 아니라 정직화 — ",
      "상한 안에 분기 릴리스가 2개 미만인 종목은 값을 만들지 않는다. 구 코드는 그들에게 ",
      "C01/C04 복제값(또는 0)을 주고 있었다."),
    positive_control = "C10/C13/C15 외 14종 컨센서스 팩터 112/112 조합 비트 불변(maxdiff 0.000e+00)"
  ),
  verification = list(
    test = "08_Tests/factor_db/test_cons_window_quarterly.R (15 PASS / 0 FAIL / 0 SKIP)",
    suite_registered = "08_Tests/hooks/run_all_hooks.sh SUITES",
    violation_injection = "최신 N행 창으로 회귀하는 돌연변이 12/12 검거 (mut frac_eq 1.0000)",
    regression = "test_factor_dedup_consumption 16/16 · test_emission_identity_axes 43/43 · test_emission_guard 26/26"
  ),
  blocked_by = paste0(
    "factor_db 재빌드 303개월(200106..202608) — 저장 parquet 는 아직 결함값. ",
    "월당 62.7초 실측 단가 기준 약 317분. **도훈 confirm 대기**(이 라운드에서 실행 안 함)."),
  next_probe = list(
    paste0("① C11_Earnings_Streak 의 같은-뿌리 점검: streak 이 연속 **양수 분기**가 아니라 ",
           "연속 양수 **영업일**을 세고 있을 가능성(원천이 일간이므로 구조적으로 동일 함정). ",
           "이번 라운드는 C11->M25 를 명시 제외했으므로 미측정 — 별도 라운드로 실측할 것. ",
           "M25 도 같은 원천·같은 식이라 함께 움직인다."),
    paste0("② 재빌드 후 C10/C13/C15 의 **선별 자격 재판정**: 이제 C01/C04 와 다른 신호이므로 ",
           "rank-IC·PORT_t 를 처음으로 의미 있게 잴 수 있다. 특히 C15 는 11년간 소비면 도달 0행이라 ",
           "한 번도 평가된 적이 없다. 자격 판정 전까지 alias 해제도 보류 상태로 둔다."),
    paste0("③ 같은 계통 전수: 원천이 일간 캐리포워드인데 하류가 x[1:n] 으로 '롤링'을 만드는 ",
           "다른 지점이 있는가. compute_crowding.R:450 이 consensus 테이블을 참조한다 — ",
           "행 기반 창을 쓰는지 확인. 판별 축은 'mean==latest 비율' 하나로 재사용 가능.")
  ),
  artifacts = list(
    "stage_artifacts/infra/cons_window_repair_20260810/p3_design_agg.csv",
    "stage_artifacts/infra/cons_window_repair_20260810/p6_bound_validate.csv",
    "stage_artifacts/infra/cons_window_repair_20260810/v1_pair_identity.csv",
    "stage_artifacts/infra/cons_window_repair_20260810/v1_c15_variance.csv",
    "stage_artifacts/infra/cons_window_repair_20260810/v1_positive_control.csv",
    "stage_artifacts/infra/cons_window_repair_20260810/s1_affected_months.csv"
  ),
  parent = "FQ-210 (배출 정체 감사 — 축3a 죽은 배출 C15 · 미선언 중복 C10/C13)"
)

if (length(hit) == 1L) Q$entries[[hit]] <- entry else Q$entries[[length(Q$entries) + 1L]] <- entry
res <- write_frontier_queue(Q)
cat(sprintf("[write] added=%s removed=%s n=%s\n",
            paste(res$added, collapse = ","), paste(res$removed, collapse = ","), res$n))

# ── 재읽기 확인 (번호가 실제로 그 값으로 들어갔는가) ────────────────────────
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
stopifnot(FQ_ID %in% ids2)
e2 <- Q2$entries[[which(ids2 == FQ_ID)[1]]]
cat(sprintf("[verify] %s 재읽기 OK · status=%s · next_probe=%d건 · entries=%d\n",
            FQ_ID, e2$status, length(e2$next_probe), length(Q2$entries)))
writeLines(FQ_ID, file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810/FQ_ID.txt"))
