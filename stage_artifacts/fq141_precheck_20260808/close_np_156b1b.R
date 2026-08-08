source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NP156B1B_20260808_CAPTILT_LANE_CONFIG_SCOPED_NEGATIVE",
  verdict_type = "config_scoped_negative",
  layer = "5_비중",
  mechanism_diagnosis = paste(
    "★비중-측 사이즈 레인(cap-tilt)의 처분을 결정한 라운드다: 신호 강도가 cap-tilt 증분을 전혀 예측하지 못한다.",
    "WT-007 main arm 15개에서 (신호강도, cap-tilt 증분 t) 실측: cor(port_t, 증분) -0.251 · cor(ew_port_t, 증분) -0.010 · 적합 R2 0.063.",
    "★최강 신호가 최악 증분을 낸다 — LEAK_ORACLE_OOS(port_t 5.262, 누출 오라클) 증분 -0.944. 최대 증분은 음의 신호 arm 에서 나온다(SS_SINGLE_BEST port_t -0.887 -> 증분 1.315 · SS_A_REL_TOP -0.663 -> 1.302).",
    "2.0 도달 필요 강도를 외삽하면 port_t = -13.21 로 무의미 — 외삽할 양의 관계가 없다는 뜻이다.",
    "⇒ 어떤 신호 강도로도 cap-tilt 로 증분 2.0 에 도달할 수 없다. 비중-측 사이즈 레인은 config-scoped negative 로 처분한다.",
    "★직전 라운드(NP-156b1) 정정: '1.307 은 신호 의존적 내용' 이라 했으나 15 arm 에서 신호강도와 증분이 무관하므로 과했다. 정확히는 tier 구성으로도 신호 강도로도 설명되지 않는 **선택-고유 특이값**이며, 귀무 대비 96.7 백분위인 것은 맞으나 재현 가능한 기전이 없다.",
    "⚠수준 비교 주의: 본 라운드 증분은 비용·유동성 필터 없이 composite 점수에서 top-25 를 재구성한 값이라 R4 의 1.307 과 수준을 직접 비교하면 안 된다. 근거는 관계(신호<->증분)이고 이는 수준 오프셋에 무관하다."),
  next_probes = c(
    "NP-156b1b1 증분 분산의 정체 — 신호와 무관하다면 증분 t(-2.478~+1.315)는 무엇이 만드는가. 바스켓 내 사이즈 집중도(예: 최대 종목 시총비중, 시총 지니)와의 관계를 보면 'cap-tilt 가 이득이 되는 선택'을 사전 판별할 수 있고, 판별 가능하면 레인이 조건부로 되살아난다",
    "NP-156b1b2 재료·선별 축으로 사이클 이전 — 비중-측이 처분됐으므로 남은 사이즈 자유도는 선별(유니버스 구성)뿐이고 그쪽은 R4 7변형 + 오늘 NP-b2b/b2b3 로 이미 좁혀졌다. 다음 사이클은 사이즈 축을 떠나 재료(비-return) 또는 소비면으로 이동하는 것이 EV 상 합리적",
    "NP-156b1b3 처분 기록의 소비 — 이 판정을 큐 FQ-156 과 병목 지도 ⑤비중 행에 반영해 다음 세션이 같은 레인을 재시도하지 않게 한다. 오늘 축 통합(④=⑤)을 반영하면 ④construction 서술도 함께 갱신 대상"),
  consumer_surfaces = c("비중방법", "팩터랭킹", "선별라벨"),
  frontier_update = "cap-tilt 레인 config_scoped_negative 처분(신호강도-증분 무관 cor -0.251·R2 0.063, 최강신호가 최악증분) · NP-156b1 의 '신호 의존적' 표현 정정 · NP-156b1b1/2/3 신규",
  live_trigger = "NP-156b1b1 이 '증분을 사전 판별하는 바스켓 속성'을 찾으면 레인이 조건부 부활 — 그 속성으로 선택을 조건화하면 증분이 예측 가능해지기 때문",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_156b1b_signal_vs_increment.R",
                    "stage_artifacts/fq141_precheck_20260808/np_156b1_matched_null.R",
                    "stage_artifacts/fq141_precheck_20260808/fq156_paired_ceiling_findings.md")
)
cat("[close_np_156b1b] RC_OK\n")
