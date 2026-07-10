# Self-Adversarial Challenge — WT-H20260710_001 (score_eff 7-factor formation micro-tuning)

Charter §8 No Silent Override. v8.2 Opus-native adversarial pass, finalize 직전 자기 적대검증. grid_spec.sha256 = 6dcd4607cfcdf31bdac5bd230e05942479572672aa1cfa19b0035c72087ca040 (사전등록, 동결).

Selection authority = canonical IS PORT_t (NW lag-3), IS 2005..2018-12, N_trials=25 (사전등록). 결과 요약:
- 참조 바(incumbent): stored score_eff IS PORT_t = 4.806 / rebuilt-incumbent(동일 파이프라인) = 4.278.
- IS PORT_t 최상위 비-incumbent = C5_esbr3m_tp5d 5.505 (paired NW-t vs rebuilt-incumbent = **0.432**).
- paired-t 최대 = A_w2_mad_str (winsor2.0+robust MAD-z) = **1.729** (< 2.0). 25개 config 중 paired-t ≥ 2.0 = **0건**.

## Concern 1 — IS-selection = best-of-25 noise (HIGH)
25 config의 IS PORT_t 산포 3.90~5.51는 incumbent(4.28~4.81) 주변 표본잡음과 구분 불가. winner C5의 point-edge(+0.70 vs stored)는 paired NW-t 0.432로 통계적 유의성 부재. null max-t(sweep N=25) crude ≈ 2.537 — winner의 어떤 paired-t도 이 대역 미만 = 비정보.
→ **분류: ACCEPT.** 이것이 핵심 결론(saturation). rank-IC/point-SR로 selection 전환 유혹 = self-rationalization → 거부. 사전등록 authority(canonical PORT_t) 준수.

## Concern 2 — production 미전이 (06-24 valwt 재발 위험) (HIGH)
C5의 IS 우위는 (a) C-block 재형성(esbr agg + tp smoothing) 기반 (b) 내 raw-esbr 파이프라인이 DB C04와 cross-sec cor 0.134로 크게 상이 — 즉 C5는 순수 'agg-window tweak'이 아니라 부분적으로 *다른* core 팩터. EW-proxy(top-25 canonical) 개선이 top-20 linear_tilt production으로 전이 안 되는 것이 KR 상수 패턴. Stage 4 production carrier(STR_1715 top-20, λ1.5/φ3, 2e8 PIT liq)로 stored score_eff 대비 paired NW-t 측정 = 결정.
→ **분류: PARTIAL → production 실측으로 판정.** [production paired NW-t 결과 아래 기입]

## Concern 3 — winsor-σ 비단조 = noise-fitting signature (MEDIUM)
Block A winsor σ 응답이 비단조: classic-strict {w2.0=4.27, w2.5=4.28, w3.0=4.23, Inf=4.49}, mad-strict {4.70,4.66,4.61,4.75}. 안정적 formation optimum이면 단조/오목 응답이 기대되나 Inf(무클립)가 최고 = 클리핑이 신호를 돕는 게 아니라 특정 표본월 극단치를 통해 우연 적합. 이는 파라미터-내부 최적점 부재(포화)의 징후.
→ **분류: ACCEPT.**

## Concern 4 — C01_SUE/C02 vendor-lock = 재형성 불가 (scope 한계, HIGH honesty)
mandate가 명시한 C01_SUE 추정窓·표준화 분모, C02 horizon 믹스는 QuantiWise 사전계산 필드(CONSENSUS$sue / eps_chg_1m·3m)로 raw actual/forecast/std 미보유 → **재형성 원천 불가**(grid_spec.vendor_locked_out_of_scope 기록). 즉 core 4팩터 중 2개(및 mandate 명시 타깃 2개)의 formation은 sweep 대상에서 구조적으로 배제됨.
→ **분류: PARTIAL(정직 scope 한계).** "factor-internal parameter 포화" 판정은 *재형성 가능 표면*(M08 형성窓/skip/residual-set, C04 agg, C06 smooth, 공통 winsor/std/missing)에 한정. vendor-locked 축은 '포화 입증'이 아니라 '측정 불가'로 라벨.

## Concern 5 — rebuilt-incumbent parity gap (MEDIUM)
rebuilt-incumbent(4.278)이 stored(4.806)보다 약함 (eff cross-sec cor 0.887, min 0.448) — book defense sleeve가 {Q07,M08,Q25} 외 추가/regime-conditional 팩터 사용 정황. config를 *약한* rebuild에 pairing = config에 유리(generous)임에도 유의 개선 0건 → 결론(무개선) robust. 더 강한 stored 대비 production carrier가 결정적 book-marginal 검증.
→ **분류: ACCEPT(결론 방향 강화).**

## Self-rationalization auto-check
"미미/관행적/보수적이면 OK/대부분 동일" 사용 없음. winner를 '작지만 개선'으로 포장하는 유혹 = paired-t 0.432·production 미전이·비단조 3중 반증으로 거부. 정직 결론 = **재형성 가능 formation 표면 포화(map completion)**.

## Q-Lead escalate trigger 점검
HIGH severity concern = 3건(1,2,4). AX axiom hard FAIL 0. PIT C1 위반 0. → escalate 임계(HIGH≥5) 미달. 정상 negative 산출로 종료.
