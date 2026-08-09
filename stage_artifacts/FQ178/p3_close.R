## FQ-178+179 종결 — 판정 기록 + 원장 환류 + close_round
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ178")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }
R1 <- readRDS(file.path(OUT, "p1.rds"))

V <- list(
  round_id = "FQ-178 + FQ-179 (통합)", parent = "FQ-176",
  origin_chain = "도훈 발안(위기신호 역방향) → 배분축 판정불가 → 선별축 FQ-176 판정불가 → 본 라운드",
  as_of = "2026-08-09", metric_type = "canonical_screen_diag", capital_claim = FALSE,
  verdict = "L3_INCONCLUSIVE_UNDERPOWERED",

  precheck_that_gated = list(
    question = "연속화가 **실제로** 유효표본을 회복하는가 (낙폭은 자기상관이 높아 자동 아님)",
    dd12_autocorr = list(lag1 = 0.877, lag3 = 0.639, lag6 = 0.372, lag12 = 0.000),
    n_eff = list(binary_episodes = 4, continuous_bartlett = 38.9),
    result = "★통과 — 보정 MDE×sd(d) 0.0567 < 이분 0.168 (개선 2.96x). 자격 규칙은 측정 전 고정.",
    conservative_note = paste0("★사후 확인: 실제 HAC se(0.0980)가 사전 Bartlett 추정(0.3305)보다 **훨씬 작았다** ",
      "— 회귀자 d 의 자기상관 팽창을 잔차 계열에 그대로 적용한 것이 보수적이었기 때문. ",
      "실제 개선폭은 2.96x 가 아니라 **약 10x**(MDE/1sd 0.0168 vs 이분 0.168). precheck 가 과소평가한 방향이라 판정엔 무해.")),

  primary = list(
    model = "spread_IC[t+1] ~ b0 + b1*d[t], HAC(NW lag6), n=281, 2003-02~2026-06",
    composite = list(quality_growth = c("Q02_ROE","Q03_ROA","Q04_Piotroski_F","GR02_Earnings_Growth","GR04_GPA_Growth"),
                     value = c("V02_EP","V03_CFP","V04_fPER"), construction = "월별 횡단면 z → EW 평균 (측정 전 고정)"),
    family_size = 1L,
    b1 = R1$b1, se_hac = R1$se1, t_hac = R1$t1, MDE = R1$MDE,
    ratio_obs_to_MDE = abs(R1$b1)/R1$MDE,
    effect_per_1sd_depth = R1$b1 * R1$sd_d,
    verdict_rule = "L3 = |t|<2.0 ∧ |b1|<MDE",
    sign_note = paste0("★b1 = ", round(R1$b1,4), " > 0 로 **사전등록 방향(b1<0)과 반대**다. ",
      "d 가 음수이므로 깊은 낙폭일수록 spread 가 **낮아진다** = 하락 뒤 밸류가 퀄리티/성장 대비 상대 우위. ",
      "단 t 1.177 로 비유의하므로 **방향 주장 자체가 불가**하다 — 반대 방향을 발견으로 읽는 것도 위반.")),

  secondary = list(
    components = list(icA_quality_growth = list(b = R1$fA$coef[2], t = R1$fA$t[2]),
                      icV_value = list(b = R1$fV$coef[2], t = R1$fV$t[2]),
                      reading = "스프레드 움직임의 출처는 quality_growth 측(t 1.646) — value 는 거의 무반응(t 0.229)"),
    alt_depth = R1$alt,
    alt_reading = "대체 정의 3종 전부 같은 부호(양), |t| 0.503~1.564 — 정의에 robust 하나 어느 것도 문턱 미달",
    era = list(`2003-2012` = list(b = 0.2195, t = 2.072, n = 119L, ratio_to_MDE = 1.04),
               `2013-2026` = list(b = -0.0420, t = -0.266, n = 162L, ratio_to_MDE = 0.13),
               warning = "★2003-2012 이 t 2.07 로 문턱을 넘으나 (a) 2급 진단이고 (b) 분할은 검정력을 파괴하며 (c) 두 구간을 본 것 자체가 다중 조회다. **승격 금지** — FQ-176 의 GR02 순환과 동형 위험.")),

  what_this_says_about_dohoon_hypothesis = paste0(
    "★여전히 **판정 불가**다. 그리고 이 라운드도 **선별(rank-IC)** 축이지 원 가설의 **배분(총노출)** 축이 아니다. ",
    "누적 상태: 배분축 월간 프레임 = 판정 불가(필요 연 24.6~87.7% vs 관측 4.7~23.4%) · ",
    "선별축 이분 조건부 = 판정 불가(에피소드 4개) · 선별축 연속 심도 = 판정 불가(관측/MDE 0.59). ",
    "세 번 모두 '효과 없음' 이 아니라 '이 표본에서 검출 불가' 다 — 방향은 세 번 다 살아 있었다."),

  honest_caveats = c(
    "rank-IC 는 ADVISORY 지표 — 어느 방향이든 자본/졸업 판정 불가",
    "합성축 성분은 FQ-176 의 **유의하지 않은** 방향 패턴에서 도출됐다(binom p=0.375). 사전등록 대상이었지 발견의 확인이 아니다",
    "심도 변동이 시대별로 불균등(sd 2010-17 0.0439 vs pre2003 0.139) — 연속화가 9년 공백을 없앤 게 아니라 저분산 구간으로 바꿨을 뿐",
    "적대검증(순환이동 placebo)은 주판정이 문턱 미달이라 **미실시** — 승격 후보가 없으면 반증할 대상도 없다"),

  artifacts = c("preregistration.json","p0_precheck.R","p0.rds","p1_measure.R","p1.rds",
                "p2_telegram.R","sweep_t_2_0_*.png"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json 기록 — 판정 %s", V$verdict)

source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
for (k in c("FQ-178","FQ-179")) {
  i <- which(ids == k); if (!length(i)) next
  Q$entries[[i]]$status <- "inconclusive_continuous_depth_20260809"
  Q$entries[[i]]$owner <- "COMPLETE — Q-Lead session 2026-08-09 (FQ-178·179 통합 라운드)"
  Q$entries[[i]]$result_ref <- "stage_artifacts/FQ178/validation.json"
  Q$entries[[i]]$next_action <- paste0(
    "★판정 L3_INCONCLUSIVE_UNDERPOWERED. spread_IC[t+1] ~ d[t] HAC(NW6) n=281: b1 **+0.1153** · t **+1.177** · MDE 0.196 · 관측/MDE **0.59**. ",
    "★연속화는 실제로 효과가 있었다 — 유효표본 4 → 38.9, MDE/1sd 0.168 → 0.0168(약 10배 개선, 사전 추정 2.96배보다 큼). ",
    "그런데도 문턱 미달 = **효과 자체가 작다**(1sd 심도당 spread 변화 0.0099 = spread sd 의 0.07배). ",
    "★부호가 사전등록과 **반대**(b1>0 ⇒ 깊은 낙폭 뒤 밸류가 퀄리티/성장 대비 우위) — 단 비유의라 방향 주장 불가. ",
    "성분 출처는 quality_growth(t 1.646), value 는 무반응(t 0.229). 대체 심도 3종 전부 동일 부호·전부 미달. ",
    "⚠2003-2012 만 t 2.072 이나 2급 진단·분할·다중조회라 **승격 금지**(FQ-176 GR02 순환과 동형). ",
    "⇒ FQ-180(문턱 그리드 착수 전 폐기 판정)으로 이관 — 연속화까지 했는데도 미달이면 구성상 한계를 문서화할 차례다.")
  say("  %s 갱신", k)
}
Q$updated <- "2026-08-09"
write_frontier_queue(Q)
say("원장 기록 완료")

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-178+179", verdict_type = "ceiling_reached_frontier_open",
  mechanism_diagnosis = paste0(
    "연속 낙폭심도는 유효표본을 실제로 회복시켰다 — 이분 설계의 에피소드 4개 대비 n_eff 38.9, ",
    "MDE 가 1sd 심도당 0.168 에서 0.0168 로 약 10배 낮아졌다. 그런데도 문턱에 못 미친 이유는 검정력이 아니라 ",
    "**효과 자체가 작기 때문**이다: 1sd 심도 변화당 spread 변화가 0.0099 로 spread 표준편차의 0.07배에 그친다. ",
    "즉 FQ-176 의 '에피소드 구속' 을 고쳤더니 남은 것은 '신호가 애초에 약하다' 였다. ",
    "부호는 사전등록과 반대(깊은 낙폭 뒤 밸류 상대 우위)이나 t 1.177 로 비유의해 방향 주장도 불가하다."),
  next_probes = c(
    "FQ-180 문턱 그리드 착수 전 폐기 판정 — 이제 이관 조건이 충족됐다. 연속화까지 했는데도 미달이므로 어떤 문턱·정의가 남았는지 표로 확정하고, 없으면 레인 닫힘을 문서화한다.",
    "효과 크기 자체를 키우는 축 — 검정력이 아니라 신호가 약한 것이 병목으로 확인됐으므로, 합성축 성분을 바꾸거나(FQ-176 방향 패턴 외 축) 낙폭 아닌 다른 국면 축(유동성·수급)을 재는 설계.",
    "배분 축 복귀 — 도훈 원 가설(총노출 확대)은 세 라운드 모두 미시험이다. 선별 축에서 신호가 약하다는 것이 배분 축 결론을 함의하지 않는다.",
    "즉시실행 정렬 — 본 라운드도 신호 t → IC t+1 로 1개월 갭을 내포한다. 원 가설은 '즉시 대응' 이므로 갭 없는 정렬 판본 필요.",
    "심도 저분산 구간(2010-17 sd 0.0439)의 기여 진단 — 연속화가 9년 공백을 없앤 게 아니라 저분산으로 바꿨을 뿐이다. 그 구간을 빼면 무엇이 달라지는지."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 변화 없음. 국면-조건부 가중 근거 없음",
    "②유니버스 필터 — 라우팅할 양성 신호 없음",
    "③오버레이/국면 — 원 가설이 겨눈 면이나 변화 없음. β_R05 단독 불변",
    "④위험모델 — 미측정",
    "⑤monitoring — 심도 계열(dd12)은 PIT 자명하므로 국면 서술자로 사용 가능",
    "⑥선별 라벨 — negative 라벨: '연속화로 검정력 10배 개선해도 미달 = 효과 크기가 병목' 기록",
    "⑦타 모드 — ★사전 검정력 게이트 + 그 게이트의 **보수성 자기점검**(HAC 실측 대비)을 절차로 이식"),
  frontier_update = "FQ-178 · FQ-179 status=inconclusive_continuous_depth_20260809 (기록 후 재읽기 확인)",
  live_trigger = paste0("이 레인 재개 조건: ①효과 크기를 키우는 구성이 나올 때(현재 1sd당 spread sd 의 0.07배) ",
    "②2003~2026 밖 표본으로 심도 변동이 큰 구간이 늘 때 ③FQ-180 에서 미검 문턱이 발견될 때. ",
    "그 전까지 **판정 불가**이지 기각이 아니다 — 방향은 세 라운드 모두 살아 있었다."),
  layer = "①재료/선별 + 측정무결성",
  evidence_refs = c("stage_artifacts/FQ178/validation.json", "stage_artifacts/FQ176/validation.json",
                    "stage_artifacts/crisis_contrarian/validation.json"))
say("=== FQ-178+179 종결 ===")
