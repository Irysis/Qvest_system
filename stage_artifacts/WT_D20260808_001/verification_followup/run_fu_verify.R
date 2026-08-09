# =============================================================================
# run_fu_verify.R — 자기 적대검증에서 나온 항목을 정본에 등재 + 최종 무결성 검사
#   ★challenge_note 에만 적고 정본에 안 옮기면 '조용한 단순화' 다.
# =============================================================================
suppressPackageStartupMessages({library(jsonlite); library(arrow); library(data.table)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); FU <- file.path(OUT,"verification_followup")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260808_001")
say <- function(f,...) cat(sprintf(paste0("[verify] ",f,"\n"),...))

SA <- list(
  "[자기적대검증 C-1 2026-08-09] F3 는 D03 에 대해 거의 동어반복이다 — D03_EWMA 는 EWMA 실현변동성이라 그 최상위 분위는 정의상 최저변동 집합이고 저변동↔저β 는 산술적 귀결에 가깝다. 기전이 거짓이어도 관측되는 양이라 반증력이 낮다. HAC 교정은 추론을 고칠 뿐 관측의 반증력을 회복시키지 않는다. ★반면 Q01_EB 는 이익안정성 축이라 저β 와 정의상 연결이 없는데도 gap 이 −0.249 로 D03(−0.215)보다 **크다** — 원 판정이 D03 을 SUPPORTED, Q01 을 WEAK 로 적은 것은 독해가 뒤집힌 것이며 정보량은 Q01 쪽이 크다(alpha_validation 정정 반영).",
  "[자기적대검증 C-2 2026-08-09] NW lag-60 은 n=259 의 23% 대역폭이라 그 자체로 편향·고분산이다. 겹치는 60개월 창의 유효 독립 관측은 ~4개 수준이므로 이 계열의 어떤 t 도 강한 증거로 읽어선 안 된다. 방어 근거 = 대역폭 비의존 경로인 MBB(L=60, B=2000)가 −4.84/−6.39 로 정합 + Andrews −4.66/−7.07 로 자릿수 일치 (lag-3 만 12~20 대로 튄다). 단일 t 인용 금지 라벨.",
  "[자기적대검증 C-3 2026-08-09] ②의 회전율 통제는 교락 통제가 아니라 **매개 통제(bad control)** 일 수 있다 — 기전이 '개인 lottery 수요' 라면 회전율은 그 수요의 결과다. 부분 방어: 순수 매개면 계수가 0 을 향해 줄지만 실측은 0 을 지나 +2.49 로 역전하며, 교락 실재가 독립 확인된다(회전율→개인 순매수 t +7.61 · D03 z↔회전율 cor −0.559 vs Q01 −0.001). ⇒ 확립된 최대치는 'D03 의 개인-flow 귀속은 거래활동과 분리 불가' 이며 '연관이 허구였다' 는 더 센 진술은 하지 않는다. 판별은 NP-F2.",
  "[자기적대검증 C-4/C-9 2026-08-09] (C-4) 수리는 유니버스 불일치를 없앤 게 아니라 3.31%→0.50% 로 줄였다 — 발행 패널은 판정 유니버스의 부분집합(밖 0행 실측)이며 advisory 배터리는 판정 arm 과 정확히 같은 유니버스가 아니다. (C-9) ⑤ 정정은 '단조 감소 → 고변동 꼬리 왜도 → 제거 대상이 평균 기여 높아 희석이 손해' 3단 사슬의 1단을 무너뜨렸고 Q5−Q1 평균 스프레드도 비유의(t −1.02)라 사슬 전체가 약한 후보로 강등된다. 대체 설명은 세우지 않았다. NOT_CONSUMABLE 결론은 플라시보 p=0.833 이라는 독립 근거가 지탱하므로 불변.",
  "[자기적대검증 C-6 2026-08-09 · REBUTTAL] '섹터-중립화에 미래참조' 의심은 실측 반증 — RAWDATA Sector 는 시변 라벨이다(월말 관측 3,388종 중 824종·24.4% 가 시간에 따라 섹터 변경, 60개월 이상 관측 2,897종 중 791종·27.3%). 정적 스냅샷의 소급 적용이 아니다. 단 재분류 반영 시점 lag 는 미확인이라 약한 잔여 의심으로 남기고 판정 근거로 쓰지 않았다. 출처 = verification_followup/probe_sector_pit.R")

for (f in c(file.path(MB,"alpha_package.json"), file.path(OUT,"alpha_validation.json"))) {
  j <- fromJSON(f, simplifyVector=FALSE)
  j$verification_followup_20260809$self_adversarial_challenge <- list(
    note_path = "stage_artifacts/WT_D20260808_001/verification_followup/challenge_note_followup.md",
    concerns_raised = 9, accept = 5, partial = 3, rebuttal = 1,
    high_severity = 3, escalation_triggered = FALSE,
    manual_escalation = "C-5(판정 arm 의 top-25 중 3.04% 가 20일-ADV 2e8 미만 · 계약 함수 라벨↔구현 불일치) 는 자동 트리거 미발화이나 Q-Lead 수동 상신 대상",
    items = SA)
  if (identical(basename(f), "alpha_package.json"))
    j$challenge_flags <- c(j$challenge_flags, SA)
  write_json(j, f, pretty=TRUE, auto_unbox=TRUE, digits=NA, null="null")
  say("자기적대검증 등재: %s", basename(f))
}

# ── 최종 무결성 검사 ─────────────────────────────────────────────────────────
say("=== 최종 무결성 ===")
ok <- TRUE
for (f in c(file.path(MB,"alpha_package.json"), file.path(OUT,"alpha_validation.json"),
            file.path(OUT,"alpha_scores_PANEL_DEFECT_NOTICE.json"),
            file.path(OUT,"alpha_validation_replication_20260808.json"),
            file.path(ROOT,"06_Registry/alpha_frontier_queue.json"))) {
  r <- tryCatch({fromJSON(f, simplifyVector=FALSE); "OK"}, error=function(e) paste("PARSE FAIL:", conditionMessage(e)))
  ok <- ok && identical(r,"OK"); say("  %-46s %s", basename(f), r) }

pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
req <- c("task_id","as_of_date","alpha_vector","factor_specs","diagnostics")
miss <- req[!req %in% names(pkg)]
say("  schema required 필드 결손: %s", if (length(miss)) paste(miss, collapse=",") else "없음")
ok <- ok && !length(miss)
say("  alpha_vector %d종 · confidence_vector %d종 · 키 일치 %s",
    length(pkg$alpha_vector), length(pkg$confidence_vector),
    identical(sort(names(pkg$alpha_vector)), sort(names(pkg$confidence_vector))))

P <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
say("  발행 패널 %d행 · %d월 · universe_basis 선언 %s", nrow(P), uniqueN(P$Date),
    if ("universe_basis" %in% names(P)) "있음" else "★없음")
say("  구 패널 보존 %s", file.exists(file.path(OUT,"alpha_scores_superseded_20260809.parquet")))
say("  두 패널 병존 검사: 정본명 1개 + _superseded 1개 = %d개",
    length(list.files(OUT, pattern="^alpha_scores.*\\.parquet$")))

say("  superseded 보존 확인:")
say("    package.diagnostics.superseded_20260808_pre_liquidity_repair : %s",
    !is.null(pkg$diagnostics$superseded_20260808_pre_liquidity_repair))
val <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)
say("    validation.F3_beta_drag.superseded_20260808 : %s",
    !is.null(val$falsification_observables$F3_beta_drag$superseded_20260808))
say("    validation.F2_...superseded_20260808 : %s",
    !is.null(val$falsification_observables$F2_agent_individual_flow$superseded_20260808))
say("    validation.verdict.superseded_b_D03_20260808 : %s", !is.null(val$verdict$superseded_b_D03_20260808))
say("  b_D03 기전 강등 반영: %s", grepl("미확립", val$verdict$b_D03))
say("=== 최종 판정: %s ===", if (ok) "PASS" else "★FAIL")
stopifnot(ok)
