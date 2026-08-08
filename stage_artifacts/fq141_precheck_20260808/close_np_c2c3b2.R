source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NPC2C3B2_20260808_BREADTH_DOMINATES",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "R4 mid 변형의 유니버스 크기를 변형 정의(run_R4_mid_construction.R:87-101)로 재산출하고 성과와 대조했다(R4 OOS 창 월평균 breadth):",
    "full_univ 349.2 port_t 1.277 / mega_drop10=nonmega_all 339.2 1.044 / kq150_focus 149.2 0.740 / mid_11_100 90.0 -0.336 / mid_band_11_50 40.0 -1.106.",
    "cor(port_t, sqrtN) = 0.947 · cor(net_sr, sqrtN) = 0.949 · cor(ew_uni_t, sqrtN) = 0.989 — Grinold(IR ∝ IC x sqrt(N))와 거의 완벽 정합.",
    "★자기 정정: 본 라운드 스크립트가 출력한 자동 판정('breadth 만으로는 설명 불가 → 신호 열화 실재')은 틀렸다. 그 논리가 상수 offset 을 빠뜨렸다.",
    "port_t ~ (alpha_selection - tier_drag)/se 이므로 breadth 가 줄면 alpha_selection -> 0 이지만 tier drag 는 상수로 남아 port_t -> -drag/se < 0 가 된다 — 음수는 순수 breadth 희석 + 상수 drag 로 설명되며 신호 사망을 요구하지 않는다.",
    "실제로 ew_uni_t 는 전 변형에서 양수(1.526~3.030)이고 sqrtN 과 cor 0.989 — 벤치 부담을 덜면 신호는 모든 변형에서 살아 있고 breadth 에 비례해 약해질 뿐이다.",
    "★정정된 결론: 지배 요인은 breadth 이며 신호 열화는 확립되지 않았다. 절편(-2.33 t-단위 추정)이 tier drag 만으로 완전히 설명되는지는 R4 가 active 변동성을 발행하지 않아 확정 불가 — NP-c2c3b 와 동일 결손."),
  next_probes = c(
    "NP-b2a 절편 규명 — port_t = a + b*sqrtN 적합의 절편이 tier drag/se 와 일치하는지. active 변동성이 필요하므로 R4 재실행(NP-c2c3b1)과 묶어서 수행. 일치하면 breadth+drag 2요인으로 완결되고, 남으면 그 잔차가 진짜 신호 성분",
    "NP-b2b breadth 회복 경로 — mid tier 알파를 쓰되 breadth 를 잃지 않는 구성이 가능한가. 예: mid 를 랭킹 축으로만 쓰고 유니버스는 유지(선별이 아니라 가중/틸트). 오늘 확인된 '소비 경로가 판정을 바꾼다' 원칙의 직접 적용면",
    "NP-b2c Grinold 계수 추정 — cor 0.947 의 기울기(약 0.193 port_t per sqrtN)가 다른 재료·다른 라운드에서도 재현되는지. 재현되면 신규 라운드의 breadth 하한을 사전 설계 기준으로 쓸 수 있다"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "타모드이식"),
  frontier_update = "mid 좁힘 악화 = breadth 지배(cor 0.947~0.989) · 자동 판정 자기정정(신호 열화 미확립) · NP-b2a/b/c 신규",
  live_trigger = "NP-c2c3b1 로 active 변동성이 확보되면 절편 검정으로 breadth+drag 2요인 완결 여부 판정",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_c2c3b2_breadth.R",
                    "04_Research/method_frontier/wt006_exog_forecast/R4_mid_construction_results.csv")
)
cat("[close_np_c2c3b2] RC_OK\n")
