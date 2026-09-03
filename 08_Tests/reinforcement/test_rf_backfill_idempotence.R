#!/usr/bin/env Rscript
#==============================================================================
# test_rf_backfill_idempotence.R — 백필 멱등 검사의 **판정 축** 양방향 검사 (2026-09-01)
#
# 무엇을 지키는가: scoped backfill 의 "이미 했으니 건너뛴다" 판정은 **존재**가 아니라
#   **가용성**을 물어야 한다. 고쳐야 하는 값은 대개 없는 게 아니라 **있는데 못 쓰는** 것이다.
#
# 실사고 2026-09-01: C15_Forecast_Error_Trend 는 301개월 parquet 에 **존재**하지만 전 종목
#   0.0 이었다(구 생산자 산물) — 횡단면 sd=0 → Z 전건 NA → Coverage FALSE → IC 0개월.
#   생산자는 이미 수리돼 있었는데도 백필이 "이미 있음"으로 건너뛰어 **영원히 안 고쳐졌다**
#   (실측: 201006/201506/202006 전부 distinct 1 · Coverage 0 유지. 백필 tick 을 20분 돌려도
#    같은 상태). 계기가 잴 것(쓸 수 있나)을 안 재고 재기 쉬운 것(있나)을 쟀다.
#
# 검사:
#   (1) 소스 계약 — 스킵 조건이 Coverage 를 본다
#   (2) 거동(현행) — 존재하지만 Coverage FALSE 인 id 는 **재대상**이 된다
#   (3) 양성 대조(구판 주입) — 같은 픽스처에서 구 술어는 **건너뛴다**(검사가 죽지 않았음을 증명)
#
# 실행: Rscript 08_Tests/reinforcement/test_rf_backfill_idempotence.R
# 부작용 없음 — 합성 픽스처만 쓴다(실 parquet 미접촉).
#==============================================================================
suppressMessages(library(data.table))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat("  OK   ", m, "\n"); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat("  FAIL ", m, if (nzchar(d)) paste0(" — ", d) else "", "\n"); FAIL <<- FAIL + 1L }

# ── 픽스처: 실제 결함 형태를 그대로 흉내낸다 ────────────────────────────────
#   BROKEN = 존재하지만 Coverage 전건 FALSE (C15 형태)  ·  GOOD = 정상 배출
existing <- rbindlist(list(
  data.table(Ticker = sprintf("A%05d", 1:50), Factor_Name = "BROKEN_FACTOR",
             Raw_Value = 0, Coverage = FALSE),
  data.table(Ticker = sprintf("A%05d", 1:50), Factor_Name = "GOOD_FACTOR",
             Raw_Value = rnorm(50), Coverage = TRUE)))
raw_ids <- c("BROKEN_FACTOR", "GOOD_FACTOR", "NEW_FACTOR")

# 현행 술어 (factor_db_builder.R 의 스킵 조건과 같은 식)
skip_new <- function(target_ids, existing) {
  usable <- if ("Coverage" %in% names(existing))
    unique(existing[Coverage == TRUE, Factor_Name]) else unique(existing$Factor_Name)
  setdiff(target_ids, usable)
}
# 구판 술어 (위반 주입)
skip_old <- function(target_ids, existing) setdiff(target_ids, unique(existing$Factor_Name))

# ── (1) 소스 계약 ───────────────────────────────────────────────────────────
src <- tryCatch(paste(readLines(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_builder.R"),
                                warn = FALSE), collapse = "\n"), error = function(e) "")
if (grepl("existing[Coverage == TRUE, Factor_Name]", src, fixed = TRUE)) {
  ok("스킵 조건이 Coverage 를 본다 (존재가 아니라 가용성)")
} else {
  ng("스킵 조건이 여전히 존재만 본다 — 있는데 못 쓰는 값은 영원히 안 고쳐진다")
}

# ── (2) 현행 거동 ───────────────────────────────────────────────────────────
tgt <- skip_new(raw_ids, existing)
if ("BROKEN_FACTOR" %in% tgt) {
  ok("존재하지만 Coverage FALSE 인 팩터가 재대상에 남는다 (수리 경로가 열린다)")
} else {
  ng("깨진 팩터를 건너뛴다 — C15 사고 재발")
}
if (!("GOOD_FACTOR" %in% tgt)) {
  ok("정상 배출 팩터는 건너뛴다 (멱등 유지 — 헛돌지 않는다)")
} else {
  ng("정상 팩터까지 다시 쓴다 — 멱등이 깨져 매일 밤 전 구간을 헛돈다")
}
if ("NEW_FACTOR" %in% tgt) {
  ok("아예 없는 팩터는 당연히 재대상")
} else {
  ng("신규 팩터를 건너뛴다")
}

# ── (3) 양성 대조 — 구판 술어를 주입하면 실제로 발화하는가 ──────────────────
tgt_old <- skip_old(raw_ids, existing)
if (!("BROKEN_FACTOR" %in% tgt_old)) {
  ok("양성 대조 발화 — 구판 술어는 깨진 팩터를 건너뛴다(검사가 살아 있다)")
} else {
  ng("양성 대조 미발화 — 픽스처가 실제 결함 형태가 아니다(검사기 낡음)")
}

cat(sprintf("합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_backfill_idempotence","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
