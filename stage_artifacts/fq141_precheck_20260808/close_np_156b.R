source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NP156B_20260808_CAPTILT_CEILING_IS_DISTRIBUTIONAL",
  verdict_type = "config_scoped_negative",
  layer = "5_비중",
  mechanism_diagnosis = paste(
    "★필자 가설 반증: '증분 계열은 선택된 종목의 사이즈 분산이 정하므로 무작위 25종목도 ~1.3 을 낸다(= 유니버스 구조 상수)' 는 틀렸다.",
    "R4 창 163개월에서 무작위 25종목 바스켓 60 draw 의 (시총가중 − 동일가중) 증분 NW t: 중앙값 0.140 · 평균 0.182 · sd 0.889 · 5% -1.442 · 95% 1.241.",
    "즉 cap-tilt 는 기계적으로 양의 증분을 만들지 않는다(양수 36/60, 중앙값 ~0) — 동전던지기에 가깝고 대신 분산이 크다.",
    "★그러나 질문에는 다른 방식으로 답이 나왔다: R4 momentum 실측 1.307 은 이 분포의 95.0 백분위이고, 문턱 2.0 도달은 60 draw 중 1건(1.7%)뿐이다.",
    "⇒ 다른 재료로 cap-tilt 를 더 시험하는 것은 저EV 다. 1.307 이 상수라서가 아니라 가중 방식만으로 도달 가능한 분포가 2.0 에 겨우 닿기 때문이며, R4 는 이미 그 분포의 꼭대기 부근을 뽑았다.",
    "★한계(정직): 무작위 바스켓은 신호-선택 바스켓의 정확한 귀무가 아니다(선택이 사이즈 구성을 바꾼다). 거친 귀무로만 읽어야 하며, 정확한 귀무는 동일 사이즈-프로파일 보존 재추출이 필요하다."),
  next_probes = c(
    "NP-156b1 사이즈-프로파일 보존 귀무 — 무작위 대신 R4 선택분과 동일한 cap-tier 구성을 유지한 채 종목만 교체하는 재추출로 귀무를 재구성. 1.307 의 백분위가 95%에서 얼마나 이동하는지가 '신호 기여분'의 정직한 추정치",
    "NP-156b2 분산의 정체 — 증분 t 의 sd 0.889 는 무엇이 만드는가(바스켓 내 사이즈 집중도?). 집중도와 증분 t 의 관계가 확인되면 '어떤 선택이 cap-tilt 로 이득을 볼 수 있는가'를 사전 판별할 수 있다",
    "NP-156b3 비중-측 레인 처분 — 본 라운드로 cap-tilt 확장의 EV 가 낮음이 확인됐다. 비중-측 사이즈 레버를 config-scoped 로 접고 재료·선별 축에 사이클을 돌릴지, 아니면 NP-156b1 로 한 번 더 정밀화할지 판단"),
  consumer_surfaces = c("비중방법", "팩터랭킹", "위험모델"),
  frontier_update = "cap-tilt 천장은 구조 상수 아님(무작위 중앙값 0.140) — 대신 도달 가능 분포가 2.0 에 겨우 닿음(1/60) ⇒ 재료 확장 저EV · 필자 가설 반증 기록 · NP-156b1/2/3 신규",
  live_trigger = "NP-156b1 사이즈-프로파일 보존 귀무에서 1.307 이 여전히 상위 5% 밖이면 신호 기여가 실재하므로 비중-측 레인 재개 가능",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_156b_ceiling_generality.R",
                    "stage_artifacts/fq141_precheck_20260808/fq156_paired_ceiling_findings.md")
)
cat("[close_np_156b] RC_OK\n")
