source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NP156B1_20260808_MATCHED_NULL_SIGNAL_IS_REAL_BUT_SUBTHRESHOLD",
  verdict_type = "revival_conditional",
  layer = "5_비중",
  mechanism_diagnosis = paste(
    "tier-프로파일 보존 귀무(MEGA ~0.54 · MID ~1 · OTHER ~23.5 종, WT-007 실측 가중 share 기반)로 1.307 을 재판정했다.",
    "결과: 1.307 은 두 귀무 모두에서 정확히 96.7 백분위 — 균등 무작위와 tier-보존이 동일하다. ⇒ tier 구성은 1.307 을 설명하지 못한다.",
    "오히려 tier-보존 귀무의 중앙값이 더 낮다(-0.201 vs 균등 -0.039, 95% 분위 0.946 vs 1.120) — momentum 의 tier 프로파일을 맞추면 cap-tilt 가 평균적으로 더 나빠지므로 1.307 은 올바른 귀무에 대해 더 구별된다.",
    "★NP-156b 판정 정정: '도달 가능 분포가 2.0 에 겨우 닿으니 저EV' 는 부정확했다. 정확히는 (a) 1.307 은 가중 아티팩트가 아니라 신호 의존적 내용이고(두 귀무 일치) (b) 어떤 귀무 draw 도 2.0 에 못 닿으므로(0/60, 0/60) 가중만으로는 불가능하며 신호가 공급해야 하고 (c) 이 저장소 최강 재료(momentum)가 공급한 것이 1.307 이다.",
    "★자기 점검: 직전 라운드에서 '무작위 중앙값 0.140' 을 점추정처럼 보고했으나 같은 설계·다른 시드에서 -0.039 가 나왔다. sd 0.87 · n=60 이면 중앙값 SE ~ 0.14 로 둘은 노이즈 안이다 — 귀무 중심은 60 draw 로 정밀 추정되지 않는다. 분포의 꼬리(백분위)는 안정적이었으나(96.7% 재현) 중심은 아니다.",
    "한계: 96.7 백분위 = 일방 p~0.033 으로 시사적이지 절대적이지 않고, 절대 수준 1.307 은 여전히 문턱 2.0 미달이다. 또한 oos_ret 0.374 · calmar 0.576 은 PORT_t 와 독립으로 HARD FAIL 이다."),
  next_probes = c(
    "NP-156b1a 귀무 draw 확대 — 60 -> 500 draw 로 중심과 꼬리를 함께 안정화. 본 라운드가 '중심은 미정밀'을 실증했으므로 백분위 인용 전 필수. 저비용",
    "NP-156b1b 신호 강도와 증분의 관계 — momentum 이 1.307 을 냈다면 더 강한 신호는 더 큰 증분을 내는가. WT-007 arm 들(port_t 다양)에 cap-tilt 를 얹어 (신호강도, 증분) 산점을 보면 2.0 도달에 필요한 신호강도를 외삽할 수 있다. 필요 강도가 현실 범위 밖이면 레인 처분 확정",
    "NP-156b1c HARD 3종 동시 통과 가능성 — 증분이 2.0 을 넘어도 oos_ret 0.7 · calmar 0.64 가 별도 관문이다. R4 변형들의 그 두 지표 분포를 보면 '증분만 해결하면 되는가'가 판명된다"),
  consumer_surfaces = c("비중방법", "팩터랭킹", "위험모델"),
  frontier_update = "1.307 = 신호 의존적(tier 구성 아님, 두 귀무 96.7% 일치) · 가중만으로는 2.0 불가(0/60 x2) · NP-156b 저EV 판정 정정 · 귀무 중심 미정밀 자기점검 · NP-156b1a/b/c 신규",
  live_trigger = "NP-156b1b 가 2.0 도달에 필요한 신호강도를 현실 범위 안으로 추정하면 비중-측 레인 재개, 밖이면 config-scoped 로 처분",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_156b1_matched_null.R",
                    "stage_artifacts/fq141_precheck_20260808/np_156b_ceiling_generality.R")
)
cat("[close_np_156b1] RC_OK\n")
