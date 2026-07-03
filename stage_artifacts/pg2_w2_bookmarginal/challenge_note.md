# W2 book-marginal — Self-Adversarial Challenge (Opus 4.8, v8.2)

판정: earnings S3_consensus+band 슬리브 = **NO-GO** (book-marginal). 아래 3+ 약점을 자가제기하고 실측으로 검증 — verdict 불변.

## Challenge 1 — active_cor=0.320이 0.30 문턱 바로 위. 벤치마크 misalignment 아티팩트로 넘은 것 아닌가?
검증: `active_series_joined.csv` 벤치 sanity — 257월 중 **1월(2005-02 seed)만** inc/earn 벤치 상이(내 series `bmw[1]=0`). drop-seed 후 active_cor=**0.3203**(변화 0.0001). 벤치는 동일 pinned KOSPI200. → 아티팩트 아님, 실재 0.32. **문턱 실패 유효.**

## Challenge 2 — 오버레이(m4×β_R05)가 상관을 인위적으로 올린 것 아닌가? raw earnings는 직교일 수도.
검증: overlay는 book-level 동일 스칼라(β_R05·m4)라 inc/earn 양쪽에 공통 적용 → 공통성분 주입 소지. 그러나 §6 실증(long-only β≈0.99·active cor 0.45 baseline) 상 earnings top-25도 STR_1715와 시장성분 공유 불가피. 더 중요한 건 **개별 IR 0.25**(vs incumbent 1.40) — 상관을 0으로 가정해도 IR-max w_earn=0(아래 C3). 상관 논쟁은 부차적, **약함이 주된 사유.**

## Challenge 3 — 전기간 대신 earnings edge 구간(pre-2021)이면 book-marginal GO 아닌가?
검증(`/tmp/adversarial.R`): pre-2021(191월) active_cor=0.222(<0.30)이나 earn IR=0.40 vs inc IR=1.66 → **IR-max w_earn=0.01, ΔIR=+0.0004**(≪0.05). 2016-2020 earn IR=**−0.11**(음). 어떤 subperiod에서도 earnings가 book IR을 0.05 이상 못 올림. → edge 구간에서도 NO-GO.

## Challenge 4 (fabrication risk) — IR-max w_earn=0이 grid 경계 착시 아닌가? 미세 양수 w는 개선?
검증: fine grid(0.005) + 명시 점검 — w=0.05→IR 1.385, w=0.10→1.356, w=0.20→1.270. **단조 감소.** 어떤 양수 배분도 book IR을 낮춤. w=0 최적은 진짜(경계 착시 아님).

## Challenge 5 (schedule/provenance) — earnings 선택수익이 P1 헤드라인과 정합한가?
검증: earnings standalone SR_geo=1.004 ≈ P1 measure_results S3_band_full absSR 1.039(오버레이 전 vs 후 소폭차, overlay β<1·현금혼입으로 하향 정상). PORT_t 1.69 vs P1 2.20 — overlay가 β 축소로 active t 소폭 감쇠(정상, fabrication 아님). 신호 정의·band 알고리즘은 P1 `pg2_w2_measure.R` 바이트 재현.

## AX-008 Triangulation
- Forge 실측(본 파일): NO-GO.
- Self-Adversarial(본 노트): 5약점 자가검증 후 NO-GO 강화.
- 2/3 충족(Architect 미소집 — 결론 일방향·명확, 논쟁 여지 없음).
