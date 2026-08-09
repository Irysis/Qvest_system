#==============================================================================
# b9_register.R — FQ 원장 갱신 (FQ-222 결과 반영 + 신규 2건 등재)
#   ★번호 하드코딩 금지: 쓰기 직전 read → 기존 최대 +1 → 기록 → 재읽기 검증
#   ★정본 writer 경유 (digits=NA / pretty=1 / 손실 가드)
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
source(file.path(ROOT, "02_Infrastructure/ops/frontier_queue_io.R"))

Q <- read_frontier_queue()
n0 <- length(Q$entries)
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids[grepl("^FQ-[0-9]+$", ids)])))
nxt <- max(nums, na.rm = TRUE)
mkid <- function(k) sprintf("FQ-%03d", nxt + k)
cat(sprintf("원장 %d건 · 기존 최대 = FQ-%03d · 신규 = %s, %s\n", n0, nxt, mkid(1), mkid(2)))

ART <- "stage_artifacts/infra/se02_window_bakeoff_20260810/"

#-- FQ-222 갱신 (창 길이 bakeoff 결과 + 수정된 수리 스펙/경제성) ---------------
i222 <- which(ids == "FQ-222")
stopifnot(length(i222) == 1L)
e <- Q$entries[[i222]]
e$status <- "measured_awaiting_decision_rollover_blocked"
e$bakeoff_result <- paste0(
  "창 길이 bakeoff 완주(318개월 전수, liveness guard stale<=31d). 선택기준은 측정 **전** 고정",
  "(K1 창내개정 median>=1 & frac>=0.80 / K2 frac_zero<=0.20 / K3 죽은달 0 / K4 앵커신선도<=10d /",
  " K5 |rho|<0.90 vs 벤더 eps_chg_1m·3m). 신호력 미사용. ",
  "결과: L21 frac_zero 0.438(K1/K2 fail) · L35 0.285(fail) · L63 0.144 · L91 0.063(K5 FAIL — ",
  "벤더 eps_chg_3m 과 rho_p95 0.958 = 91일이 곧 벤더 3개월창) · L126 0.013 · L252 0.003. ",
  "★그러나 고정 기준이 **롤오버 축을 빠뜨려** 엄격 판정상 유일 통과가 L252 였는데, ",
  "L252 는 미측정 축에서 최악(12개월 중 8개월 오염)이다 — 기준집합 불완전이 확인된 사례.")
e$second_defect <- paste0(
  "★창과 **직교하는 두 번째 결함**: liveness guard 부재. 저장 SE02 는 월 ~1164행을 내보내는데 ",
  "컨센서스 관측이 31일 이내인 종목은 ~608개뿐 — 배출의 약 48%가 커버리지가 끊긴 종목이고, ",
  "이들은 현재/lag 끝점이 **같은 행**이라 창 길이와 무관하게 구조적 0 이 된다",
  "(guard 없이는 L252 조차 frac_zero 0.59). guard 적용 시 L63 0.627→0.000. ",
  "즉 창만 고쳐도 결함의 절반만 사라진다.")
e$dead_month_mechanism <- paste0(
  "죽은 달 = sd 0 이 아니라 **winsorize 후 상수화**. factor_db_builder.R:672-687 이 Raw 를 ",
  "1/99 로 clip 한 뒤 z 를 내는데, 값의 99%가 정확히 0 이면 q01==q99==0 → 전 종목 Raw_W 상수 ",
  "→ sd<1e-12 → Z 전건 NA → Coverage FALSE. 저장 실측 정합: 죽은 달 frac_zero>=0.988 / ",
  "산 달 <=0.959. 전수 결과 **죽은 달 49개월/318**(201403 은 그 중 하나일 뿐), ",
  "modal_frac>=0.9 인 달 260/318, frac_zero 중앙 0.952.")
e$pit_check <- paste0(
  "PIT: (a) eps_1y 값 변경일은 주말 0건 · 월 분포가 전 12개월에 퍼짐(4/6/9/12월 35.5% ≈ 균등 33%) ",
  "· dom<=5 는 18.9% ⇒ FQ-218 의 분기 일괄공표 구조가 **아니다**(런 길이 p50 5일 · 연 ~8런) ",
  "⇒ .cons_quarters() 재사용 부적합 확정(가설을 그대로 믿지 않고 직접 측정). ",
  "(b) 벤더 자체 eps_chg_1m 과 우리 30일 개정률의 rho 가 최대(0.67~0.82)로 정합 ⇒ 레벨 패널의 ",
  "Date 스탬프 = 벤더 관측일. (c) lag1 스트레스(sig_d vs sig_d-1, guard 모집단): rho_p50 ",
  "L21 0.939 / L63 0.989 / L126 0.997, 동일값 비율 0.87~0.88 ⇒ same-day 노출의 값 영향 경미. ",
  "(d) ★단일 vintage 패널이라 **restatement 는 이 자료로 검증 불가** — 필요 시 vintage-swap 통제.")
e$rebuild_scope$integration <- paste0(
  "SE02 배출 318개월(200003..202608) ⊇ 통합C 303개월. SE02 한계비용 +15개월/+15분. ",
  "★그러나 롤오버 계열(M26/M28, 316개월)이 SE02 월집합의 **부분집합**이라 같은 배치에 ",
  "얹는 한계비용은 **0개월/0분**. 따라서 시나리오 E(FQ218+FQ219+SE02+롤오버) = 318개월/332분 ",
  "으로 전부 처리 가능. 역으로, 롤오버를 고치기로 하면 318개월 배치가 **어차피 필요**하므로 ",
  "SE02 를 그 배치로 미루는 한계 페널티는 0분이다(현 confirm 대기분을 303개월로 그냥 진행해도 됨).")
e$next_probe <- list(
  paste0("롤오버 처리 방식 결정이 lag 결정의 **선행 조건** — ", mkid(1), " 참조. ",
         "롤오버-인지 창 적용 시 최적 arm 이 L63 → L126 으로 이동(실측: L63_rollaware frac_zero ",
         "0.227·frac_rev_ge1 0.779 로 K1/K2 미달, L126_rollaware 0.135·0.869 로 통과)"),
  paste0("SE02 정의 분기 해소 — ", mkid(2), " (일간 경로 producer 가 다른 식을 쓴다)"),
  "수리 확정 시 08_Tests/factor_db/ 검사기 신설 + run_all_hooks.sh 등재 (위반 주입 축 = frac_zero + 4/5월 중앙값)")
e$artifacts <- paste0(ART, "b2_bakeoff_summary.csv · b3_agg_guarded.csv · b4_grid.csv · ",
                      "b7_rollover_aware_summary.csv · b8_rebuild_scenarios.csv")
Q$entries[[i222]] <- e

#-- 신규 1: FY1 롤오버 (계열 전체 · M26/M28 현행 오염) -------------------------
new1 <- list(
  id = mkid(1),
  title = "FY1 롤오버 — 고정창 레벨 차분 계열 전체 오염 (M26/M28 현행 배출 포함)",
  status = "measured_awaiting_decision",
  owner = "dohoon_decision",
  opened = "2026-08-10",
  category = "infra_measurement_integrity",
  parent = "FQ-222 (SE02 창 bakeoff 중 발견 — SE02 lag 결정의 선행 조건)",
  mechanism = paste0(
    "컨센서스 **FY1 레벨** 지표는 매년 4월 첫 영업일에 회계연도 기준이 롤오버한다. 실측: 그날 ",
    "live 종목의 95~99.7%가 동시에 값이 바뀌고(평일 대비 lift 10~19배), 큰 점프(|rel|>0.20)의 ",
    "78.6%가 상향, 중앙 +43%. 종목-연도의 73.9%가 '연 정확히 1회 대형 상향'. ",
    "지문 확인된 지표: eps_1y(lift 11.3) · revenue_fy1(10.8) · op_profit_fy1(10.3) · ",
    "bps_1y(13.0) · dps_1y(18.8). target_price 는 lift 1.01 로 **비해당**(회계연도량이 아님). ",
    "⇒ 4/1 을 가로지르는 고정창의 차분은 개정이 아니라 **기준 회계연도 교체분**이다."),
  live_impact = paste0(
    "★현행 배출에 이미 들어가 있다: M26_Revenue_Mom · M28_OP_Rev_Mom (각 316개월, 중앙 ~1577행)이 ",
    "revenue_fy1 / op_profit_fy1 을 `sig_date - 63L` 로 차분한다(compute_momentum.R:425,464 / ",
    "factor_db_daily_phase8.R:250-258). 63일 창은 4월·5월 sig 에서 4/1 을 가로지른다 ⇒ 연 2개월 오염. ",
    "실측 오염 크기(SE02 동형 계산): 4월 중앙 +0.165 · 5월 +0.184 vs 평월 0.000. ",
    "C14_Revenue_Surprise / C17_OP_Revision 은 같은 식이나 **배출 원장 0개월**(M26/M28 과 중복 ",
    "등재로 조용히 스킵 — 기존 카드 project-c14-m26-duplicate-silent-skip 재확인)."),
  discriminant = paste0(
    "★벤더는 보정한다: eps_chg_1m / eps_chg_3m 의 4월 분포가 평월과 다르지 않다",
    "(eps_chg_1m 4월 median 0 · p90 0.06 · frac_pos 0.248 — 5월 p90 0.09 보다 오히려 낮다). ",
    "즉 벤더 자체 개정률은 **동일 회계연도 기준 안에서** 계산된다. 우리가 레벨을 직접 차분할 때만 ",
    "롤오버가 새어 들어온다."),
  proposed_repair = paste0(
    "롤오버-인지 창: basis_start = sig 이하에서 가장 최근 '동시 변경일'(live 종목의 >=50% 동시 변경). ",
    "anchor = max(sig - L, basis_start) 위치 관측(뒤가 basis 이전이면 basis 이후 **첫** 관측). ",
    "sig 이하만 보므로 PIT 안전. 실측 효과: 4/5월 중앙값 +0.165/+0.184 → **0.000/0.000**, ",
    "평월 불변. 비용 = 절단된 달의 영값 증가(L126: frac_zero 0.013→0.135). ",
    "★미해결: 동시변경일 탐지기가 초기 희소구간에서 4월 외 12건을 오검출(2000-12-07 등) — ",
    "n_live 문턱/4월 제한 등 강건화 필요. 이 부분이 남은 설계 리스크다."),
  rebuild_scope = list(
    affected_months = 316L, span = "200005..202608",
    integration = paste0("월집합이 SE02 의 318개월 **부분집합** ⇒ FQ-222 와 같은 배치에 얹는 ",
                         "한계비용 0개월/0분. 시나리오 E = 318개월/332분으로 FQ-218+FQ-219+SE02+",
                         "롤오버 전부 처리. 따로 하면 롤오버 단독 330분.")),
  next_probe = list(
    "동시변경일 탐지기 강건화 — n_live 문턱·4월 제한·연 1회 제약 중 무엇이 오검출 12건을 없애는가",
    "M26/M28 의 4·5월 값이 하류(M32 composite·PG2 book)에 실제로 얼마나 전파되는가 측정",
    "bps_1y/dps_1y 를 차분하는 소비자가 있는지 전수 — 있으면 오염 범위가 더 넓다"),
  artifacts = paste0(ART, "b5_r2_synchrony_by_month.csv · b5_r3_big_jumps.csv · ",
                     "b6_s1_rollover_fingerprint.csv · b6_s2_vendor_by_month.csv · ",
                     "b6_s3_contaminated_months.csv · b7_rollover_aware_summary.csv"))

#-- 신규 2: SE02 정의 분기 (두 producer) --------------------------------------
new2 <- list(
  id = mkid(2),
  title = "SE02_Consensus_Revision — 살아있는 producer 2개가 서로 다른 식을 쓴다",
  status = "measured_awaiting_decision",
  owner = "dohoon_decision",
  opened = "2026-08-10",
  category = "infra_definition_split",
  parent = "FQ-222 (SE02 수리 범위 산정 중 발견)",
  mechanism = paste0(
    "같은 팩터명에 정의가 둘이다. ",
    "(A) compute_crowding.R:422-428 — (eps_1y[rank1] - eps_1y[rank2]) / |eps_1y[rank2]| (인접 행 비율). ",
    "(B) factor_db_daily_phase8.R:261 — `SE02_Consensus_Revision := eps_chg_1m` (벤더 컬럼 그대로). ",
    "(B)는 같은 파일 260행의 `M27_Analyst_Rev_Mom := eps_chg_1m` 및 compute_consensus.R:316 의 ",
    "`C02_EPS_Chg_1m` 과 **완전 동일** ⇒ 일간 경로에서 SE02 ≡ M27 ≡ C02 삼중 중복. ",
    "(B)는 dead 코드가 아니다 — factor_db_daily_incremental.R:62 가 phase8 을 source 한다. ",
    "월간 저장 패널이 담고 있는 건 (A) 쪽이다(재현 검증: 기준선 vs 저장 frac_zero ",
    "rho 0.993 · mean|diff| 0.0102, 318개월)."),
  risk = paste0(
    "compute_crowding.R 만 고치면 phase8 은 계속 `eps_chg_1m` 을 SE02 이름으로 내보낸다 ⇒ ",
    "수리 후 두 경로가 **더 크게** 갈라진다(현재는 둘 다 쓸모없어 갈라짐이 안 보인다). ",
    "registry 정의도 창을 못박지 않는다: '(EPS_now - EPS_prev)/|EPS_prev|. Recent estimate change.' ",
    "— prev 가 무엇인지 미지정이라 두 구현 모두 문안상 합치한다."),
  proposed_repair = paste0(
    "① 두 경로가 같은 헬퍼를 쓰도록 통일하거나 phase8 의 SE02 라인을 제거(M27 이 이미 같은 값을 낸다). ",
    "② registry definition 에 창 단위·lag·liveness 문턱을 명시해 '문안상 둘 다 맞는' 상태를 없앤다."),
  next_probe = list(
    "phase8 산출물이 어느 소비면까지 도달하는지 — 일간 패널을 읽는 연구 경로가 실재하는가",
    "같은 파일에서 이름만 다르고 식이 같은 쌍 전수(M27/SE02 외에 C14/M26·C17/M28 이미 확인) — 공식 중복 검색"),
  artifacts = paste0(ART, "b1_d_stored_se02_all_months.csv · b2_reproduction_check.csv"))

Q$entries <- c(Q$entries, list(new1), list(new2))
Q$updated <- "2026-08-10"

res <- write_frontier_queue(Q)
cat(sprintf("기록 완료: added=%s · removed=%s · n=%d\n",
            paste(res$added, collapse=","), paste(res$removed, collapse=","), res$n))

#-- 재읽기 검증 ---------------------------------------------------------------
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(e) as.character(e$id)[1], character(1))
cat(sprintf("재읽기: %d건 (증분 %d) · 신규 존재: %s / %s\n", length(Q2$entries),
            length(Q2$entries) - n0, mkid(1) %in% ids2, mkid(2) %in% ids2))
e222 <- Q2$entries[[which(ids2 == "FQ-222")]]
cat(sprintf("FQ-222 status = %s · bakeoff_result 길이 %d\n", e222$status, nchar(e222$bakeoff_result)))
if (length(Q2$entries) != n0 + 2L) stop("[STOP] 증분이 2가 아니다")
cat("\n[b9 완료]\n")
