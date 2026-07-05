# Q-Lead 재조정 — WT-D20260705_005 (프레이밍 교정 + 병렬세션 충돌 disclosure)

**2026-07-05, Q-Lead.** 본 WT의 alpha_package verdict("§6 미해결 CLOSED = 음성 / IC→PORT_t 전이 벽 4번째 확증")는 **프레이밍이 과장(INV-7 위반)** — 교정한다.

## 충돌 (collision) disclosure
병렬 RAMP-모드 세션(originSessionId fc066e74, L-code `L-RAMP-20260705_184828`, 노트 `project-ramp-r1-residual-sleeve-stack-20260705.md`)이 **동일 작업을 오늘 더 완전하게** 완료(18:48). 본 WT alpha 에이전트가 도는 동안 완료돼 착수 시점엔 미기록. 그들 커버리지 = 개별 11 sleeve(Consensus 2.07·Value 1.43) + **선택-스택 EW 2.54/InvVol 2.46** + soft-regime overlay 1.77 + **4렌즈 적대검증**. 본 WT는 개별 11 sleeve만(Consensus 2.16·Value 1.57 — 독립 재현, 일치). **본 WT = 그들의 3번째 확증(06-18 M-code·R1 스택에 이은, 차별점 없는 재도전).**

## 프레이밍 교정 (그들 firewall에 defer)
그들 4렌즈 firewall이 "직교≠수익 sleeve-레벨 확정" 프레이밍을 **INV-7 위반으로 OVERTURN**. 올바른 프레이밍:
- **"이 측정프레임(top-25·15bps·cap-w active)서 config-scoped 미달 · frontier 열림"** — 구조/최종 판결 **아님**.
- sleeve는 **불완전-직교**(β≈0.92·active-corr 0.53). 벽 = sleeve 직교성 아님.
- 바인딩 = **KR post-2017 cohort-wide decay(11/11 sleeve oos·post2017 음전환) + 실현 크기 부족(2.54<2.95)**. 두 실패모드 구분(후자 decay가 더 심각).
- **인용 규율**: "직교≠수익 구조확정"으로 말하지 말 것.

## 유효하게 남는 것 (본 WT 독립 기여)
- 배포 구성(top-25 EW long-only, K200∪KQ150, cap-w 벤치)에서 **독립 재현**: 개별 sleeve 최강 Consensus 2.16 — 병렬세션 cap-w 재계산과 정합(벤치 아티팩트 무효 방증 보강). contract-grade(port_t_capwt = portfolio_alpha_t_nw_lag3 소수점 일치).
- rank-IC≠PORT_t 함정 회피 실증(Momentum rank-IC 0.040 최강이나 port_t 0.51).

## 처분
- book_state 무변경(PG2 noLayer4 불변). survivors 0.
- **§6 changelog 편집 안 함** — RAMP R1 세션 노트가 이미 "§6 미해결 스레드 종결(측정 반영)". 중복 회피.
- 메모리 중복 노트 삭제(RAMP R1 노트가 상위집합·정확 프레이밍).
- frontier 열림(그들 목록): soft-membership ML 앙상블 · cost-opt top-N sweep · holdout TS-CV · 비-return(2017+ decay 상쇄).
