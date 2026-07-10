# Self-Adversarial Challenge — WT-D20260710_002 (Alpha, EW-relative survivor screen)

v8.2 Opus 4.8 자체 적대검증 (외부 Codex 없음). finalize 직전 최약 가정·PIT·과적합·측정 위험 자가제기 → 분류 → 기록.
AX-008 3-source(Forge·Self-Adversarial·Architect) 중 1 source.

## 자기비평 concern (≥3)

### C1 [측정-무결성, ACCEPT→수정반영] 유니버스 불일치 0-fill 드래그 (1차 실행 무효)
- 최초 실행: features 패널이 전체 factor-DB 유니버스(월 ~1772종, 전체 KR시장)인데 returns_monthly는 in_univ(K200∪KQ150, ~350종) 필터. canonical top-25가 유니버스 밖 소형주를 뽑고 forward Ret_1m을 0으로 채움 → 인위적 음수 드래그. 8종 전부 균일 cap-w PORT_t ≈ -2.5, cap-tier UNRANKED ≈ 0.9로 발현.
- 진단 실측: 2015-06 월 features 1772종 중 tradable(returns-univ) 348종 = 11.1%.
- **처리**: scores를 mandate 유니버스(returns_monthly = in_univ & forward-ret 보유)로 제한 후 재실행. tier 합 ≈ 1.00으로 정상화, 결과 분산 회복. 1차 실행 폐기, 2차만 유효. (measurement-graduation §1 real-computation 정합 — 자체합성 아님, 유니버스 정의 오류 수정)

### C2 [C2 자가점검 — rank-IC를 realized로 오독했는가?, ACCEPT/clean]
- 판정 권위 = canonical PORT_t(cap-w + EW diag) 실측. rank-IC/ICIR/IC-t는 advisory 기록만.
- **역증거 실측**: R12_Idiosyncratic_Risk rank-IC +0.0510(8종 최고)·IC_t +4.65인데 portfolio-alpha PORT_t cap-w -1.16 / EW -1.64(양 basis 음수). 구 졸업기준 rank_ic≥0.04였다면 R12·V02_EP 둘 다 통과했겠으나 R12는 portfolio-음수 — rank-IC 거짓양성 실증. EW-survivor 판정에 rank-IC 미사용 확인.

### C3 [EW-basis 소형주 틸트 낙관, PARTIAL] V02_EP EW +4.40이 size-premium 아티팩트?
- V02_EP top-25가 tier OTHER(rank 31+) 98.6% 보유. EW-유니버스 벤치(~350종 동일가중)도 cap-w 대비 소형 틸트. 우려: EW active(+4.40)가 EP 선택력이 아닌 size 프리미엄 이중계상.
- **반박 근거(정량)**: active_ew = port_ret − EW_bench. 둘 다 소형 틸트를 공유하므로 size 공통성분은 차분에서 상쇄 → EW active는 유니버스 *내* EP 선택효과를 격리(cap-w는 mega-cap 드리프트가 지배해 선택력 은폐). 즉 EW active가 cap-w보다 선택력에 더 정직한 측정.
- **PARTIAL 인정**: 그러나 OTHER-tier(rank 31+, 2e8 유동성필터 통과했으나 상대적 소형) 실배포 시 capacity/비용 열위는 실재. → challenge_flag(capacity_concern_other_tier) 기록. 자본 판정 아님(cap-w authoritative)이라 재라우팅 라벨에는 무해.

### C4 [Post-2017 약화, PARTIAL] full-period 강도가 pre-2017 편중
- V02_EP: cap-w pre17 +4.07 → post17 −0.45(cap-w 최근 사멸) / EW post17 +1.73(약양, <2.5). full EW +4.40은 pre-2017 value 프리미엄 편중.
- **처리**: "full-period EW-survivor · post-2017 EW 약양(+1.73, 유의 미달)"로 명시 라벨. 벤치-아티팩트 스윙(cap-w post17 −0.45 → EW +1.73, ~+2.2t)은 실재하나 "최근 완전 부활"로 과대주장 금지. oos_retention_approx 0.52(<0.7)로 EW조차 졸업급 아님 확증.

### C5 [일반화 한계, ACCEPT] 벤치-아티팩트는 factor-specific, 보편 아님
- quality(Q01_GPA/Q08) 양 basis 모두 음수(EW post17 −2.5대) = 진짜 죽음(벤치 아티팩트 아님, AX-004 유지). momentum(M08/M09) 양 basis 약양이나 유의 미달. → "cap-w 기각 = 벤치 아티팩트"는 value/EP에만 부분성립, quality엔 불성립. 과잉일반화 방지 기록.

## 합리화 자기검증 (금지표현 grep)
"미미/관행적/보수적이면/대부분 동일" 미사용. 모든 수치 실측 canonical_screen_bt 경유. EW-survival = 재라우팅 라벨로만 사용, 자본 졸업 주장 없음(cap-w HARD authoritative).

## Q-Lead 자동 escalate 판정
- HIGH severity ≥5? NO (측정수정 1·PARTIAL 2·ACCEPT 2). AX axiom hard FAIL ≥3? NO. PIT C1(lockbox/lookahead) 위반? NO(유니버스·forward-ret PIT clean).
- → **auto-escalate 미발동**. 정상 handoff.

## AX-008 triangulation
self-adversarial = 1 source. Forge(cap-w authoritative 재측정)·Architect(dual-basis 진단설계 자문 = canonical_screen_bt v8.3 M2 배선) 후속 결합 시 2/3 충족.
