## P0R01 실현 가능성 지도 — 라운드 정의(엔진 × 부품 · 문헌 근거 · 셀 사양 delta)
##   설계 정본: 06_Registry/research_programs.json::P0_FRONTIER(thesis · decisive_test · kill_or_pivot · literature)
##   ★부품 = 문헌 표준(파라미터는 카탈로그 arm · 팩터 DB 정의 그대로 — 이 라운드가 새로 고른 수치 없음).
##   ★엔진 선택은 성과를 보지 않았다(τ_D 시험 창 판정을 오염시키지 않기 위해):
##     E1 = 문헌 표준 모멘텀(엔진 내장 12-1 · 성과 무관 선택) · E2 = 파일럿 출발점으로 결정된 2002.06975 논문 엔진(GRADE-V3-PROMOTE ③) ·
##     E3 = 같은 계보의 기존 최고 셀 B6_36(P2R01 기저 — 도훈 결정으로 정해진 출발점의 현행형).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

P0_PROGRAM <- "P0_FRONTIER"; P0_ROUND <- "P0R01_feasibility_map"

p0_engines <- function(root) list(
  E1 = list(id = "E1", name = "모멘텀 12-1(문헌 표준 · 엔진 내장)",
            base = list(code = "P0E1", label = "momentum 12-1 top-25 EW", block = "P0",
                        fixed_axes = list(long_only = TRUE, n_max = 25L, commission_bps = 15L, liq_adv20_min = 2e8, weight_cap = NULL,
                                          base_weight = 0.5),
                        base_signal = list(kind = "mom_12_1"), base_weight = 0.5, factors = list(),
                        weighting = list(kind = "ew"), defense_sleeve = NULL,
                        root_paper = list(url = "https://doi.org/10.1111/j.1540-6261.1993.tb04702.x",
                                          title = "Jegadeesh & Titman (1993) Returns to Buying Winners and Selling Losers, JF 48(1)",
                                          paper_key = "JT1993"),
                        root_papers = list(list(url = "https://doi.org/10.1111/j.1540-6261.1993.tb04702.x",
                                                title = "Jegadeesh & Titman (1993) Returns to Buying Winners and Selling Losers, JF 48(1)",
                                                paper_key = "JT1993"))),
            family = "JT1993_builtin_mom_12_1", lineage_trials = 0L, prior_round_variants = 0L,
            why = "문헌 표준 수익 엔진 — 성과를 보지 않고 고른 기준점(엔진 내장 신호 · shift 21/252 · C2)"),
  E2 = list(id = "E2", name = "2002.06975 DNN 엔진(원형 · 25종 롱온리)",
            base = list(code = "P0E2", label = "2002.06975 engine top-25 EW", block = "P0",
                        fixed_axes = list(long_only = TRUE, n_max = 25L, commission_bps = 15L, liq_adv20_min = 2e8, weight_cap = NULL,
                                          base_weight = 0.5),
                        base_signal = list(kind = "engine", path = file.path(root, "04_Research/strategies/RP_AUTO_2002_06975/engine.R")),
                        base_weight = 0.5, factors = list(), weighting = list(kind = "ew"), defense_sleeve = NULL,
                        root_paper = list(url = "https://arxiv.org/abs/2002.06975",
                                          title = "Cross-sectional Stock Price Prediction using Deep Learning for Actual Investment Management",
                                          paper_key = "2002.06975"),
                        root_papers = list(list(url = "https://arxiv.org/abs/2002.06975",
                                                title = "Cross-sectional Stock Price Prediction using Deep Learning for Actual Investment Management",
                                                paper_key = "2002.06975"))),
            family = "2002.06975", lineage_trials = NA_integer_, prior_round_variants = 3L,
            why = "파일럿 출발점으로 결정된 논문 엔진(GRADE-V3-PROMOTE ③ · S0 눈검사 GRADE-V3-S0-EYECHECK) — 원형 신호만"),
  E3 = list(id = "E3", name = "B6_36(2002.06975 계보 기존 최고 셀)",
            base = NULL,   # P2R01 기저 사양 그대로(아래 p0_base_spec 이 읽는다)
            base_path = file.path(root, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/base/base_cell_spec.json"),
            family = "2002.06975", lineage_trials = NA_integer_, prior_round_variants = 3L,
            why = "같은 계보의 현행형(팩터 3 · 엔트로피 비중 · 순위 버퍼) — P2R01 기저와 같은 사양(측정 축만 새 epoch)")
)

## 부품 — 셀 사양 delta(rx_validate 가 엔진 파서로 검증) · 문헌 근거
p0_components <- function() list(
  C0 = list(id = "C0", name = "부품 없음(엔진 그대로)", delta = list(), basis = "기준"),
  C1 = list(id = "C1", name = "추세 현금 규칙(시장 12개월 수익 부호 < 0 → 현금)",
            delta = list(overlay = list(kind = "ts_mom_gate", arm_id = "ts_mom_sign")),
            basis = "Moskowitz, Ooi & Pedersen (2012) Time series momentum, JFE 104(2) doi:10.1016/j.jfineco.2011.11.003 · Hurst, Ooi & Pedersen (2017) JPM 44(1) · Faber (2007) JWM"),
  C2 = list(id = "C2", name = "변동성 타기팅(노출 = min(1, 확장창 중앙 실현변동성 / 현재 60일))",
            delta = list(overlay = list(kind = "vol_scale", arm_id = "vol_median")),
            basis = "Moreira & Muir (2017) Volatility-Managed Portfolios, JF 72(4) doi:10.1111/jofi.12513 · Cederburg et al. (2020) JFE 138(1)"),
  C3 = list(id = "C3", name = "낙폭 제어(낙폭이 확장창 중앙~90분위 구간에서 선형 축소)",
            delta = list(overlay = list(kind = "dd_brake", arm_id = "dd_brake_q")),
            basis = "Grossman & Zhou (1993) Optimal Investment Strategies for Controlling Drawdowns, Math. Finance 3(3) doi:10.1111/j.1467-9965.1993.tb00044.x"),
  C4 = list(id = "C4", name = "저변동 틸트(252일 실현변동성 낮음 — 기저와 rank-z 결합)",
            delta = list(factors = list(list(kind = "db", id = "D03_RealVol"))),
            basis = "Blitz & van Vliet (2007) The Volatility Effect, JPM 34(1) doi:10.3905/jpm.2007.698039 · Frazzini & Pedersen (2014) JFE 111(1)"),
  C5 = list(id = "C5", name = "퀄리티 틸트(복합 퀄리티 — 기저와 rank-z 결합)",
            delta = list(factors = list(list(kind = "db", id = "Q08_Composite_Quality"))),
            basis = "Asness, Frazzini & Pedersen (2019) Quality minus junk, RAS 24 doi:10.1007/s11142-018-9470-2"),
  C6 = list(id = "C6", name = "추세 현금 + 저변동 틸트(시변 노출 × 방어적 보유)",
            delta = list(overlay = list(kind = "ts_mom_gate", arm_id = "ts_mom_sign"), factors = list(list(kind = "db", id = "D03_RealVol"))),
            basis = "C1 + C4 — 비대칭의 원천 ②(시변 노출)와 ③(방어적 보유)의 결합(research-program SKILL 철학)")
)

## 기저 사양(엔진별)
p0_base_spec <- function(eng) {
  if (!is.null(eng$base)) return(eng$base)
  jsonlite::fromJSON(eng$base_path, simplifyVector = FALSE)
}

## 엔진의 팩터 delta 는 기저 팩터 목록에 **덧붙인다**(E3 = 팩터 3 + 틸트 1) · 오버레이는 새로 둔다(기저에 없음)
p0_delta_for <- function(base_spec, comp) {
  d <- comp$delta
  if (!is.null(d$factors)) d$factors <- c(base_spec$factors %||% list(), d$factors)
  d
}
