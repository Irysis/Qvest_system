## test_round_kit_pair_alpha.R — round_kit 증분 β-통제 알파 · 보유 집중(2026-10-16) — 실산출물(P3R02 · 읽기 전용)로 대조
##   ① rk_pair_alpha(P3R02_E2_M5, P3R02_E2_RX0) 보는 창 = 1차 라운드 시각 보고 q2(M5 vs P0R01_E2_C0 — RX0 는 C0 의 같은 사양 재측정으로
##      결과 동일이 확인돼 있다) 와 일치 ② 같은 칸끼리(기준 = 자기 자신) → 증분 0 ③ 창 분할(보는 창 마지막 달 ≤ 2022-12 < 시험 창 첫 달)
##   ④ rk_concentration — 리밸일 수 > 0 · 보유 ≤ 25 · 0 < 최대 비중 ≤ 1 · 1 ≤ 유효 종목 수 ≤ 보유 수 · 보는 창 ⊂ 전기간
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
invisible(capture.output(suppressMessages({
  source("02_Infrastructure/contracts/diagnosis_packet.R"); source("02_Infrastructure/contracts/beta_controlled_alpha.R")
  source("04_Research/programs/_lib/round_kit.R")
})))
E <- .dp_deps(ROOT); TAU <- as.Date("2022-12-31")
RD <- "04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz/results"
art <- function(code) jsonlite::fromJSON(file.path(RD, paste0(code, ".json")))$artifacts
m5 <- art("P3R02_E2_M5"); rx <- art("P3R02_E2_RX0")
pa <- rk_pair_alpha(E, m5, rx, TAU)
ref <- data.table::fread("04_Research/01_reports/l1_round1_results_20261015/q2_incremental_alpha.csv")[engine == "E2" & var == "M5"]
rv <- ref[grepl("보는", window)]
chk("① 보는 창 증분 알파 = 시각 보고 q2(M5 · E2)", abs(pa$visible$d_alpha - rv$d_alpha) < 1e-10 && abs(pa$visible$t - rv$t) < 1e-8 && pa$visible$n == rv$n,
    sprintf("%.10f/%.6f/%d vs %.10f/%.6f/%d", pa$visible$d_alpha, pa$visible$t, pa$visible$n, rv$d_alpha, rv$t, rv$n))
p0 <- rk_pair_alpha(E, rx, rx, TAU)
chk("② 기준 = 자기 자신 → 증분 0(또는 계산 불가 NA — 0 분산)", (is.na(p0$visible$d_alpha) || abs(p0$visible$d_alpha) < 1e-12))
chk("③ 창 분할 — 보는 창 끝 ≤ 2022-12 < 시험 창 시작", pa$visible$window[2] <= "2022-12" && pa$test$window[1] > "2022-12",
    paste(c(pa$visible$window, pa$test$window), collapse = " · "))
cc <- rk_concentration(m5, TAU)
v <- cc$visible
chk("④ 보유 집중 — 리밸일 > 0 · 보유 중앙 ≤ 25 · 0 < 최대 비중 ≤ 1 · 1 ≤ 유효 종목 수 ≤ 보유", v$n_dates > 0L && v$names_median <= 25 &&
      v$maxw_max > 0 && v$maxw_max <= 1 + 1e-9 && v$effn_min >= 1 - 1e-9 && v$effn_median <= v$names_median + 1e-9,
    paste(names(v), unlist(v), collapse = " "))
chk("④ 보는 창 리밸일 ⊂ 전기간(수 ≤)", cc$visible$n_dates < cc$full$n_dates)
cat(sprintf("\n== round_kit_pair_alpha: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_kit_pair_alpha","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
