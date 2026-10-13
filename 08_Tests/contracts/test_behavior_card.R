## test_behavior_card.R — 행동 카드 계약 검사기 (양방향: 양성 대조 + 위반 주입)
## 규약: "경고 0" 만으로는 검사기가 살아있는지 알 수 없다 — 일부러 틀린 입력을 넣어 발화를 확인한다.
## 대상: 02_Infrastructure/contracts/behavior_card.R (v10.01 · 2026-10-13)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else dirname(sys.frame(1)$ofile %||% ".")
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- normalizePath(file.path(.qv_self_dir(), "..", ".."), mustWork = FALSE)
if (dir.exists(file.path(SELF, "02_Infrastructure/contracts"))) ROOT <- SELF
setwd(ROOT)
source("02_Infrastructure/contracts/behavior_card.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}

## 합성 벤치 — 강세(+2.5%/월 30개월) · 약세(−5%/월 10개월) 사이클 3번 + 끝 강세. 일간 = 월 수익을 21거래일로 나눔
cfg <- bc_cfg()
cfg$period_start <- "2000-01-01"; cfg$tau_d <- "2009-12-31"; cfg$dc_derive_window <- c("2000-01", "2009-12")
mk_bench <- function() {
  seg <- c(rep(0.025, 30), rep(-0.05, 10), rep(0.025, 30), rep(-0.05, 10), rep(0.025, 30), rep(-0.05, 10), rep(0.02, 20))
  months <- seq(as.Date("2000-01-01"), by = "month", length.out = length(seg))
  rbindlist(lapply(seq_along(seg), function(i) {
    days <- seq(months[i], by = "day", length.out = 21L)
    data.table(date = days, benchmark_ret = (1 + seg[i])^(1 / 21) - 1)
  }))
}
B <- mk_bench()

cat("=== A. 위기 구간 정의(bc_crises) ===\n")
cr <- bc_crises(B[, .(date, r = benchmark_ret)], cfg$crisis_depth)
chk("사이클 3번의 약세가 위기 3개로 잡힌다", nrow(cr) == 3L, sprintf("(n=%d)", nrow(cr)))
chk("위기 깊이 = 1 − 0.95^10 ≈ 0.401", all(abs(cr$depth - (1 - 0.95^10)) < 1e-6), paste(round(cr$depth, 4), collapse = ","))
chk("앞 두 위기는 회복(ongoing=FALSE) · 마지막은 미회복(1.02^20 < 1/0.95^10)", identical(cr$ongoing, c(FALSE, FALSE, TRUE)),
    paste(cr$ongoing, collapse = ","))
short <- data.table(date = seq(as.Date("2001-01-01"), by = "day", length.out = 40),
                    r = c(rep(-0.01, 10), rep(0.012, 30)))      # 약 −9.6% 후 회복 → 문턱 미만
chk("깊이 20% 미만 하락은 위기가 아니다(위반 주입)", nrow(bc_crises(short, 0.20)) == 0L)
open <- data.table(date = seq(as.Date("2001-01-01"), by = "day", length.out = 30), r = rep(-0.02, 30))
oc <- bc_crises(open, 0.20)
chk("미회복 하락은 ongoing=TRUE", nrow(oc) == 1L && isTRUE(oc$ongoing[1]))

cat("\n=== B. 문턱 도출(bc_dc_strong_max) — 닫힌 형식 ===\n")
ph <- data.table(start_ym = c("2001-01", "2003-01"), end_ym = c("2002-12", "2003-12"),
                 n_months = c(24L, 12L), kind = c("bull", "bear"), bm_cum = c(1.0, -0.5))
d <- bc_dc_strong_max(ph, 0.55, c("2000-01", "2009-12"))
chk("U=+100% · D=−50% · 참여 0.55 → d 상한 0.7097", abs(d$value - (1 - 2 * 0.5 / 1.55) / 0.5) < 1e-9,
    sprintf("(d=%.4f)", d$value))
ph2 <- copy(ph); ph2$bm_cum <- c(1.0, -0.05)
chk("약세가 얕으면 d 상한이 음수(강세 손실을 못 메움)도 정직하게 낸다",
    bc_dc_strong_max(ph2, 0.55, c("2000-01", "2009-12"))$value < 0)

cat("\n=== C. 양성 대조 — 오라클(위기엔 현금 · 그 밖엔 벤치) ===\n")
in_crisis <- function(dt) Reduce(`|`, lapply(seq_len(nrow(cr)), function(i) dt > cr$peak_date[i] & dt <= cr$trough_date[i]))
S_or <- copy(B)[, ret_net := ifelse(in_crisis(date), 0, benchmark_ret)]
c_or <- bc_card(S_or[, .(date, ret_net)], B, cfg = cfg)
chk("오라클 위기 낙폭 포착 = 0", isTRUE(all(abs(c_or$crises$dd_capture) < 1e-9)))
chk("오라클 판정 = strong", c_or$overall$verdict == "strong",
    sprintf("(verdict=%s, up=%.2f, dc_strong=%.3f)", c_or$overall$verdict,
            c_or$overall$bull_up_capture_median %||% NA, c_or$dc_strong_max %||% NA))

cat("\n=== D. 위반 주입 — 시장 그 자체 · 정적 절반 노출 ===\n")
c_mk <- bc_card(B[, .(date, ret_net = benchmark_ret)], B, cfg = cfg)
chk("시장 그대로는 위기 낙폭 포착 = 1", isTRUE(all(abs(c_mk$crises$dd_capture - 1) < 1e-9)))
chk("시장 그대로는 판정 = weak(방어 아님)", c_mk$overall$verdict == "weak", sprintf("(verdict=%s)", c_mk$overall$verdict))
S_half <- copy(B)[, ret_net := 0.5 * benchmark_ret]
c_h <- bc_card(S_half[, .(date, ret_net)], B, cfg = cfg)
chk("정적 절반 노출: 위기 낙폭 포착 < 1", isTRUE(all(c_h$crises$dd_capture < 1)))
chk("정적 절반 노출: 상승 포착 < 0.55(복리 탓에 절반보다 작다)", isTRUE(c_h$overall$bull_up_capture_median < 0.55),
    sprintf("(up=%.3f)", c_h$overall$bull_up_capture_median))
chk("정적 절반 노출은 strong 이 아니다(비대칭 없음 — 개선안 §대안 1)", c_h$overall$verdict != "strong",
    sprintf("(verdict=%s)", c_h$overall$verdict))

cat("\n=== E. τ_D 분할 ===\n")
chk("τ_D 이전 바닥 위기는 visible", all(c_mk$crises[trough_date <= as.Date(cfg$tau_d)]$window == "visible"))
chk("τ_D 이후 시작 위기는 test", all(c_mk$crises[peak_date > as.Date(cfg$tau_d)]$window == "test"))
chk("visible + test + straddle = 전체", nrow(c_mk$crises) == sum(c_mk$crises$window %in% c("visible", "test", "straddle")))

cat("\n=== F. 크기 짝 대조(bc_attach_controls) ===\n")
c_h2 <- bc_attach_controls(c_h, list(size_matched = B[, .(date, ret = benchmark_ret)]), B)
chk("대조(시장)보다 덜 빠지면 selection_defense", identical(c_h2$controls$size_matched$label, "selection_defense"))
c_h3 <- bc_attach_controls(c_h, list(size_matched = S_half[, .(date, ret = ret_net)]), B)
chk("대조와 같으면 size_or_exposure_defense(위반 주입: 크기 효과뿐)",
    identical(c_h3$controls$size_matched$label, "size_or_exposure_defense"))
chk("대조 미제공이면 status=not_provided(침묵 통과 아님)", identical(c_h$controls$status, "not_provided"))

cat("\n=== G. 설정 실패는 닫힌다 ===\n")
tmp <- tempfile(fileext = ".json"); bad <- fromJSON("06_Registry/behavior_card.json"); bad$uc_floor <- NULL
writeLines(toJSON(bad, auto_unbox = TRUE), tmp)
chk("필수 키 누락 → 오류", inherits(tryCatch(bc_cfg(path = tmp), error = function(e) e), "error"))
chk("겹치는 월 24개 미만 → 오류", inherits(tryCatch(bc_card(B[1:200, .(date, ret_net = benchmark_ret)], B[1:200], cfg = cfg),
                                                    error = function(e) e), "error"))

cat("\n=== I. '강함' 자기 낙폭 조건(GRADE-V3-S0-BANDS ④ · 10-13) ===\n")
# 오라클(위기엔 현금)에 위기 밖 강세 구간의 고유 급락을 끼운다 — 20일 −60% 뒤 20일 ×2.5 로 되찾는다.
#   위기 구간 밖이라 위기 포착은 그대로(0)이고, 같은 강세 국면 안에서 되찾아 상승 포착도 거의 그대로다.
#   다른 조건은 다 '강함'인데 자기 낙폭만 벤치(1 − 0.95^10 ≈ 40.1%)보다 깊다 → 이 조건만이 판정을 가른다.
S_cr <- copy(S_or); ix <- which(!in_crisis(S_cr$date))[101:140]
S_cr[ix[1:20], ret_net := 0.4^(1 / 20) - 1]; S_cr[ix[21:40], ret_net := 2.5^(1 / 20) - 1]
c_cr <- bc_card(S_cr[, .(date, ret_net)], B, cfg = cfg)
chk("I1 [양성 대조] 오라클은 자기 낙폭도 벤치 이하(mdd_vs_bench ≤ 1) — 진짜 방어는 막지 않는다",
    isTRUE(c_or$overall$mdd_vs_bench <= 1) && c_or$overall$verdict == "strong", sprintf("(ratio=%.3f)", c_or$overall$mdd_vs_bench %||% NA))
chk("I2 [위반 주입] 위기 밖 고유 급락 −60% → 위기 포착은 그대로인데 '강함'이 아니다",
    isTRUE(all(abs(c_cr$crises$dd_capture) < 1e-9)) && isTRUE(c_cr$overall$share_crisis_strong > cfg$majority_share) &&
      isTRUE(c_cr$overall$bull_up_capture_median >= cfg$uc_floor) && isTRUE(c_cr$overall$mdd_vs_bench > 1) &&
      c_cr$overall$verdict == "normal",
    sprintf("(verdict=%s · ratio=%.3f · up=%.3f)", c_cr$overall$verdict, c_cr$overall$mdd_vs_bench %||% NA,
            c_cr$overall$bull_up_capture_median %||% NA))
cfg_m <- cfg; cfg_m$strong_mdd_vs_bench_max <- Inf
chk("I3 [돌연변이] 조건을 끄면(문턱 ∞) 같은 전략이 '강함' — 이 조건이 실제로 판정을 움직인다",
    bc_card(S_cr[, .(date, ret_net)], B, cfg = cfg_m)$overall$verdict == "strong")
chk("I4 창별 자기 낙폭 — visible·test 판정에도 mdd_vs_bench 가 실린다",
    !is.null(c_cr$visible$mdd_vs_bench) && !is.null(c_cr$test$mdd_vs_bench))

cat("\n=== J. 위기 정의 LT 20/20 (Lunde-Timmermann 첫 통과 · CRISIS-DEF-LT2020 · 10-13 도훈 선택) ===\n")
mk_path <- function(legs, start = as.Date("2001-01-01")) {   # legs = list(c(목표 배율, 일수), …)
  # 첫날 수익 0 — 두 정의 모두 '첫 관측 = 첫 고점' 관례라, 첫날부터 빠지면 기준점이 1 이 아니다(검사 산술을 1 기준으로 맞춘다)
  r <- c(0, unlist(lapply(legs, function(l) rep(l[1]^(1 / l[2]) - 1, l[2]))))
  data.table(date = seq(start, by = "day", length.out = length(r)), r = r)
}
two <- mk_path(list(c(0.70, 30), c(1.25, 20), c(0.70, 30), c(1.80, 60)))     # 1 → 0.70 → 0.875 → 0.6125 → 1.1025
v1 <- bc_crises(two, 0.20); lt <- bc_crises_lt(two, 0.20, 0.20)
chk("J1 두 파동(사이 +25% 반등 · 이전 고점 미회복): 구판 = 위기 1개 · LT = 2개(반등이 위기를 가른다)",
    nrow(v1) == 1L && nrow(lt) == 2L, sprintf("(v1 %d · lt %d)", nrow(v1), nrow(lt)))
chk("J2 LT 두 위기의 깊이 = 각 파동의 국지 고점 대비(0.30 · 0.30)", nrow(lt) == 2L && all(abs(lt$depth - 0.30) < 1e-9),
    paste(round(lt$depth, 4), collapse = ","))
one <- mk_path(list(c(0.70, 30), c(1.15, 20), c(0.70, 30), c(1.90, 60)))     # 사이 반등 +15% < 20%
lt1 <- bc_crises_lt(one, 0.20, 0.20)
chk("J3 사이 반등이 λ_up(20%) 미만이면 LT 도 한 위기(바닥 = 더 낮은 저점)", nrow(lt1) == 1L && abs(lt1$depth - (1 - 0.7 * 1.15 * 0.7)) < 1e-9,
    sprintf("(n %d · depth %.4f)", nrow(lt1), lt1$depth[1] %||% NA))
chk("J4 LT 위기는 전부 λ_down 이상 깊다(정의) · 끝까지 반등 못 하면 ongoing", all(c(lt$depth, lt1$depth) >= 0.20 - 1e-12) &&
      isTRUE(bc_crises_lt(mk_path(list(c(1.1, 20), c(0.6, 30))), 0.2, 0.2)$ongoing[1]))
bull <- function(n_m, start) mk_path(list(c(1.015^n_m, 21 * n_m)), start)
p1 <- bull(24, as.Date("2003-01-01")); p2 <- mk_path(list(c(0.70, 30), c(1.25, 20), c(0.70, 30), c(1.80, 60)), max(p1$date) + 1)
p3 <- bull(18, max(p2$date) + 1); BJ <- rbind(p1, p2, p3)[, .(date, benchmark_ret = r)]
## 두 정의를 모두 명시한다 — 운영 설정(behavior_card.json)을 기준으로 빌리면 설정을 바꿀 때 검사가 같이 움직인다(10-13 v3.1 전환 때 실제로 J5 가 그렇게 깨졌다)
cfg_lt <- cfg; cfg_lt$crisis_episode_def <- "lt_first_passage"; cfg_lt$crisis_lambda_down <- 0.2; cfg_lt$crisis_lambda_up <- 0.2
cfg_lt$tau_d <- "2009-12-31"
cfg_v1 <- cfg; cfg_v1$crisis_episode_def <- "running_peak_drawdown"; cfg_v1$crisis_lambda_down <- NULL; cfg_v1$crisis_lambda_up <- NULL
c_lt <- bc_card(BJ[, .(date, ret_net = benchmark_ret)], BJ, cfg = cfg_lt); c_v1 <- bc_card(BJ[, .(date, ret_net = benchmark_ret)], BJ, cfg = cfg_v1)
chk("J5 카드가 설정의 위기 정의를 따른다 — 같은 벤치에서 LT 2 · 구판 1 · 카드 설정 사본에 정의가 실린다",
    nrow(c_lt$crises) == 2L && nrow(c_v1$crises) == 1L && identical(c_lt$cfg$crisis_episode_def, "lt_first_passage") &&
      identical(c_v1$cfg$crisis_episode_def, "running_peak_drawdown"), sprintf("(lt %d · v1 %d)", nrow(c_lt$crises), nrow(c_v1$crises)))
tmpj <- tempfile(fileext = ".json"); bj <- fromJSON("06_Registry/behavior_card.json"); bj$crisis_episode_def <- "lt_first_passage"
bj$crisis_lambda_down <- NULL; bj$crisis_lambda_up <- NULL; writeLines(toJSON(bj, auto_unbox = TRUE), tmpj)
chk("J6 [위반 주입] LT 인데 λ 없음 → 오류(문턱을 지어내지 않는다)", inherits(tryCatch(bc_cfg(path = tmpj), error = function(e) e), "error"))
bj$crisis_episode_def <- "rolling_quantile"; writeLines(toJSON(bj, auto_unbox = TRUE), tmpj)
chk("J7 [위반 주입] 위기 정의 어휘 밖 → 오류", inherits(tryCatch(bc_cfg(path = tmpj), error = function(e) e), "error"))
bj$crisis_episode_def <- NULL; writeLines(toJSON(bj, auto_unbox = TRUE), tmpj)
chk("J8 [하위 호환] 정의 키가 없는 구 설정 사본 → 구판 정의(running_peak_drawdown)로 재현", identical(bc_cfg(path = tmpj)$crisis_episode_def, "running_peak_drawdown"))

cat("\n=== H. 저장 왕복 ===\n")
od <- file.path(tempdir(), "bc_rt"); p <- bc_write(c_h2, od)
rt <- fromJSON(p)
chk("저장 후 schema 보존", identical(rt$schema, "behavior_card_v1"))
chk("저장 후 판정 보존", identical(rt$overall$verdict, c_h2$overall$verdict))

cat(sprintf("\n== behavior_card: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"behavior_card","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))   # 배터리 요약 계약(run_all_hooks.sh _last_summary_json)
if (FAIL > 0L) quit(status = 1L)
