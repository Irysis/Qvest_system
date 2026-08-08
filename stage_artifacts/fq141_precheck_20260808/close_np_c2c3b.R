source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NPC2C3B_20260808_PARTIAL_TIER_DRAG_IS_COMMON_LEVEL",
  verdict_type = "config_scoped_negative",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "★라운드 미완(정직 표기) — R4 mid 변형의 tier 비중이 저장돼 있지 않아 변형별 기대 drag 를 정확히 산출할 수 없다.",
    "실측: R4_mid_construction_results.csv 의 mega_w/mid_w/other_w 컬럼이 8/8 행 전부 빈 문자열이고, R4_mid_construction.rds 도 results/verdict/best/best_ew 만 담아 보유내역이 없다.",
    "= 컬럼이 스키마에 선언만 되고 채워지지 않았다. 오늘 반복 검거한 계통('존재 = 기록됨'으로 읽힘)의 또 다른 사례이며, 이 결손이 본 라운드를 실제로 막았다.",
    "★확립 가능분 1 — 해석적 경계: mega 를 구성상 배제하는 변형(mega_drop10 / nonmega_all / mid_band_11_50 / mid_11_100 / kq150_focus)은 mega_w=0 이므로 기대 drag 가 MID(-0.0470)와 OTHER(-0.0341)의 혼합, 즉 [-0.0470, -0.0341]/yr 구간에 든다.",
    "★확립 가능분 2 — 공통 수준 추론: WT-007 실측상 momentum 류 top-25 선택은 이미 mega 비중 ~0.02(base 0.028 의 0.77배)로 사실상 mega-free 다. baseline full_univ 도 그렇다면 그 drag 역시 -0.034~-0.047 구간이다.",
    "⇒ tier drag 는 R4 변형들 사이에서 대체로 **공통**이며 변형 간 차이를 설명하지 못한다. 설명하는 것은 이들이 공통으로 낮은 **수준**(전부 1.0~1.3 대, baseline 1.277)이다.",
    "★R4 진단의 범위 정정: 'tier-beta 가 지배' 는 cap-w basis 와 EW-uni basis 사이의 **수준 격차**에 대해서는 옳고 내 측정이 그것을 -3.4~-4.7%/yr 로 계량했다. 그러나 mid 를 좁힐수록 나빠진 것(mid_band_11_50 port_t -1.106)은 tier 노출이 대체로 공통이므로 tier-beta 로 설명되지 않는다 — breadth/신호 쪽 사유가 필요하다."),
  next_probes = c(
    "NP-c2c3b1 R4 mid 파이프라인 재실행으로 tier 비중 산출 — run_R4_mid_construction.R 에 tier 비중 기록을 추가해 재실행. 컬럼이 이미 선언돼 있으므로 채우기만 하면 되고, 그래야 변형별 기대 drag 를 정확히 뺄 수 있다",
    "NP-c2c3b2 mid 좁힘의 악화 사유 분리 — tier-beta 로 설명 안 되는 부분(mid_band_11_50 -1.106 vs full_univ 1.277)의 원인이 breadth 축소인지 신호 열화인지. 선택 가능 종목수와 port_t 의 관계를 변형 간 대조",
    "NP-c2c3b3 빈-컬럼 계통 스캔 — 스키마에 선언됐으나 전 행이 빈 컬럼이 다른 결과 파일에도 있는지. 오늘만 두 번째 사례(큐 결과 스키마 109종 + 여기)이며 '선언은 소비 가능성을 보장하지 않는다'는 규약의 근거가 쌓인다"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "타모드이식"),
  frontier_update = "NP-c2c3b 부분 완료 — tier drag 는 변형 간 공통(차이 설명 못함)·공통 수준은 설명 · R4 진단 범위 정정 · tier 비중 미기록 결손 적발 · NP-c2c3b1/2/3 신규",
  live_trigger = "NP-c2c3b1 로 tier 비중이 채워지면 변형별 정확한 drag 차감이 가능해져 '신호가 살아있는가'에 확정 답을 낼 수 있다",
  evidence_refs = c("04_Research/method_frontier/wt006_exog_forecast/R4_mid_construction_results.csv",
                    "stage_artifacts/fq141_precheck_20260808/np_c2c3_tier_drag.R")
)
cat("[close_np_c2c3b] RC_OK\n")
