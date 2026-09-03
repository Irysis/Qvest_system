#!/usr/bin/env Rscript
#==============================================================================
# test_rf_holdings_axis.R — 보유 종목수 축의 **이중 선정** 차단 검사 (2026-09-01)
#
# 실사고: 강화 셀이 전부 **3종목 포트폴리오**를 재고 있었다. 고정 축은 25인데.
#   기전 2단:
#     ① rf_cell_engine 이 이미 상위 25를 잘라 FACTORS 를 내보낸다
#        (rf_cell_engine.R: PANEL[order(Date,-Score)][, head(.SD, .N_MAX), by=Date]).
#        실측 factors_panel.parquet = 월 정확히 25행.
#     ② run_paper_replication 의 top_n_long 이 **그 25개를 다시** 분위로 자른다
#        (k = max(2, ceiling(n * lfrac)), lfrac=0.10) -> ceiling(25*0.10) = 3.
#   거들던 배선 결함: 워커/러너가 `n =` 을 넘기는데 러너는 `spec$n_max` / `spec$n_long` 을
#   읽는다 — 격자의 n_max 가 **한 번도 전달된 적이 없었다**(기본값 25로 떨어진 뒤 10% 곱).
#   결과: 라이브 셀 산출물이 전부 n_max 3. 격자 주석의 "MDD 61.6~77.2% 대역"은
#   신호가 약해서가 아니라 **분산이 없어서**일 수 있었다.
#
# 검사:
#   (1) 계약 — 셀 실행 경로 2종이 n_long/n_max 를 넘긴다 (읽히지 않는 `n =` 금지)
#   (2) 산술 — 엔진이 25를 건네면 25가 담긴다 (구판 술어 주입 시 3 = 양성 대조)
#   (3) 얇은 달 — 후보가 12개면 버리지 않고 12종을 담는다 (n_long 명시가 달을 죽이지 않는다)
#
# 실행: Rscript 08_Tests/reinforcement/test_rf_holdings_axis.R  · 부작용 없음
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat("  OK   ", m, "\n"); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat("  FAIL ", m, if (nzchar(d)) paste0(" — ", d) else "", "\n"); FAIL <<- FAIL + 1L }
rd <- function(f) tryCatch(paste(readLines(file.path(ROOT, f), warn = FALSE), collapse = "\n"),
                           error = function(e) "")

# ── (1) 계약 ────────────────────────────────────────────────────────────────
for (f in c("02_Infrastructure/ops/rf_cell_worker.R", "02_Infrastructure/ops/reinforce_auto_run.R")) {
  s <- rd(f)
  has_new <- grepl("n_long =", s, fixed = TRUE) && grepl("n_max =", s, fixed = TRUE)
  # 읽히지 않는 구 키가 portfolio_spec 안에 남아 있으면 안 된다
  bad <- grepl('construction = "top_n_long", n = ', s, fixed = TRUE)
  if (has_new && !bad) {
    ok(sprintf("%s — n_long/n_max 전달 (읽히지 않는 `n =` 없음)", basename(f)))
  } else {
    ng(sprintf("%s — 셀 spec 키 불일치", basename(f)),
       sprintf("n_long/n_max=%s · 구키잔존=%s", has_new, bad))
  }
}

# ── 선정 술어 (run_paper_replication 의 top_n_long 과 같은 식) ───────────────
pick_new <- function(n, nl = NA, nmax = 25L, lfrac = 0.10) {
  k <- if (is.finite(nl)) as.integer(nl) else max(2L, as.integer(ceiling(n * lfrac)))
  k <- min(k, nmax); k <- min(k, n)
  if (n < 2L) return(0L)
  k
}
pick_old <- function(n, nl = NA, nmax = 25L, lfrac = 0.10) {   # 구판(위반 주입)
  k <- if (is.finite(nl)) as.integer(nl) else max(2L, as.integer(ceiling(n * lfrac)))
  k <- min(k, nmax)
  if (n < max(2L, k)) return(0L)
  k
}

# ── (2) 엔진이 25를 건네면 25가 담기는가 ────────────────────────────────────
if (pick_new(25L, nl = 25L) == 25L) {
  ok("엔진 산출 25 -> 보유 25 (이중 선정 없음)")
} else {
  ng("엔진 산출 25인데 보유가 25가 아니다", as.character(pick_new(25L, nl = 25L)))
}
# 양성 대조: 구판 경로(n_long 미전달)는 3을 낸다 — 검사가 실제 결함 형태를 잡는다
if (pick_old(25L, nl = NA) == 3L) {
  ok("양성 대조 발화 — 구판(n_long 미전달)은 25를 3으로 자른다")
} else {
  ng("양성 대조 미발화 — 픽스처가 실제 결함 형태가 아니다(검사기 낡음)",
     as.character(pick_old(25L, nl = NA)))
}

# ── (3) 얇은 달을 죽이지 않는가 ─────────────────────────────────────────────
if (pick_new(12L, nl = 25L) == 12L) {
  ok("후보 12 -> 12종 담김 (n_long 명시가 얇은 달을 폐기하지 않는다)")
} else {
  ng("얇은 달이 버려진다", as.character(pick_new(12L, nl = 25L)))
}
if (pick_old(12L, nl = 25L) == 0L) {
  ok("양성 대조 발화 — 구판은 후보 12인 달을 통째로 버린다")
} else {
  ng("양성 대조 미발화(얇은 달)", as.character(pick_old(12L, nl = 25L)))
}
# lfrac 경로(충실구현)는 거동이 바뀌면 안 된다
same <- all(vapply(c(20L, 50L, 200L, 400L), function(n) pick_new(n) == pick_old(n), logical(1)))
if (same) {
  ok("lfrac 경로(충실구현) 거동 무변경 — 논문 분위 선정은 그대로")
} else {
  ng("lfrac 경로 거동이 바뀌었다 — 충실구현 측정이 흔들린다")
}

# ── (4) 엔진이 여전히 상위 N 을 자르는가 (전제 확인) ────────────────────────
e <- rd("02_Infrastructure/reinforcement/rf_cell_engine.R")
if (grepl("head(.SD, .N_MAX), by = Date", e, fixed = TRUE)) {
  ok("엔진이 상위 N_MAX 를 잘라 내보낸다 (이중 선정 전제 — 러너는 다시 자르면 안 된다)")
} else {
  ng("엔진의 상위 N 절단이 사라졌다 — 이 검사의 전제가 바뀌었다(검사기 갱신 필요)")
}

# ── (5) long_only 축 — 엔진이 숏 레그를 만들 수 있는가 ──────────────────────
#   ★2026-09-03: 미등록 훅 design_envelope_gate.sh 은퇴에 따라 그 훅이 지려던 축을 여기서 진다.
#   설계 문서의 **키워드**가 아니라 엔진이 실제로 배출하는 **Leg 값**을 본다.
#   (키워드 검사는 정당 문맥에 도배돼 상시 오탐 → 해제 → 계기 사망. 훅 자신이 그 이유를 적어뒀다.)
.legs <- function(s) regmatches(s, gregexpr('Leg *= *"[A-Za-z]+"', s, perl = TRUE))[[1]]
emit <- .legs(e)
if (length(emit) == 0L) {
  ng("엔진에서 Leg 배출 지점을 못 찾았다 — 이 검사의 전제가 바뀌었다(검사기 갱신 필요)")
} else if (all(grepl('"LONG"', emit, fixed = TRUE))) {
  ok(sprintf("long_only 축 — 엔진 배출 Leg %d곳 전부 LONG (숏 레그 생성 불가)", length(emit)))
} else {
  ng("엔진이 LONG 이 아닌 Leg 를 배출한다 — 강화 실투형 envelope 위반",
     paste(unique(emit), collapse = " / "))
}

# 양성 대조 — 숏이 섞인 판을 이 검사가 실제로 잡는가
mut <- sub('Leg = "LONG"', 'Leg = "SHORT"', e, fixed = TRUE)
mm  <- .legs(mut)
if (length(mm) && !all(grepl('"LONG"', mm, fixed = TRUE))) {
  ok("양성 대조 발화 — 숏 주입판을 검사가 잡는다")
} else {
  ng("양성 대조 미발화 — 위 long_only 판정은 무의미하다", paste(unique(mm), collapse = " / "))
}

# 격자 선언과 엔진 거동이 같은 말을 하는가 (선언만 보고 거동을 추정하지 않는다)
ax <- tryCatch(jsonlite::fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"))$fixed_axes$long_only,
               error = function(e) NA)
if (isTRUE(ax)) {
  ok("격자 fixed_axes.long_only=TRUE — 선언과 엔진 거동 일치")
} else {
  ng(sprintf("격자 선언이 long_only 가 아니다(%s) — 엔진은 LONG 만 낸다(선언·거동 불일치)",
             paste(ax, collapse = ",")))
}

cat(sprintf("합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_holdings_axis","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
