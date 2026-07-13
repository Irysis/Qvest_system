# Self-Adversarial Challenge — Kalman TE 추정기 head-to-head (2026-07-13)

**agent**: risk-research · **task**: 칼만 필터 TE 추정기 대결 (진단·결정 재료만, book/monitoring 무변경)
**AX-008**: self-adversarial = 3-source 중 1개 (여기서 결론을 실제로 뒤집음 — 아래 SC-1).
**규율**: v8.2 Opus 4.8 native adversarial (외부 Codex 없음).

## 자기 비평 4건 + 분류·처리

### SC-1 [ACCEPT→결론 변경] "Kalman-SV 승리 = 오프셋/metric 아티팩트"
- **자기 제기**: kSV headline win(분산비 1.015, 오경보 0.009, ewma97 대비 paired z² t=-5.88 p<0.001)이 (a) log-offset c=0.02 nuisance + (b) uncentered z-metric의 산물일 수 있음.
- **처리(ACCEPT)**: 내 적대검증이 확증 — ① 오프셋 민감도: c=0.01→분산비 1.091, c=0.05→0.899(과대). 승리가 offset로 level을 맞춘 효과. ② centered metric(실제 monitoring TE=centered sd에 근접): kSV 0.930(과대예측) vs ewma97 1.002(최적). uncentered 승리가 부분 반전. ③ **단일 스칼라 re-baseline**(uncentered RMS 0.205 상수)이 alert 0.0135/분산비 1.027로 kSV를 거의 복제. → **naive "Kalman 우수" 판독 기각. 권고는 EWMA 유지.** (EW-천장 교훈과 동형: 원리성·복잡도만으로 채택 안 함.)

### SC-2 [PARTIAL] "TV-beta 무흡수 결론이 under-powered(모델 미세조정 탓)일 수 있다"
- **자기 제기**: 오버레이 흡수 부재(cor −0.030)가 stride-12 MLE·β RW 평활 과함 때문일 수 있음.
- **처리(PARTIAL)**: 미세조정으로 (β−1)² 항 크기는 바뀔 수 있으나 **구조적 결론은 불변** — 진단의 오버레이 TE 기여는 active 시계열의 selection×overlay *공분산*(corr +0.60)이고, book-vs-bm β 회귀는 selection·overlay를 단일 잔차 e_t로 합쳐 원리적으로 오버레이 스위칭항을 분리 못함. 현 β̂=0.676(de-risk 반영)이나 (β−1)²항(4e−4)이 잔차(2.4e−3)의 1/6이고 de-risk 강도와 무상관. 근거 있는 null. caveat 기록.

### SC-3 [REBUTTAL] "MLE 재적합이 미래참조(look-ahead) 아닌가"
- **자기 제기**: 확장창 MLE(q per-t, β params stride-12)가 미래정보 누출?
- **처리(REBUTTAL)**: PIT-clean by construction — 모든 적합·filtered state가 1:(t-1)만 소비, 예측은 m_{t-1}/R_t(info≤t-1). 목표 realTE(전향12m)는 입력 아님. **대조군 5/5 정확 재현**이 원 PIT-감사 코드와 eval 프레임 항등 확인. 누출 없음.

### SC-4 [ACCEPT] "implied λ=0.9999 = near-static인데 'Kalman' 프레이밍 과장 아닌가"
- **처리(ACCEPT)**: 정직 보고 — kSV 유효평활 near-static, TE범위 0.160~0.250 ≈ ewma97 0.156~0.246로 **더 적응적이지 않음**; 엣지는 bias-corrected E[a²] targeting의 level shift. 보고서에 "level 효과지 adaptivity 아님"으로 명시.

## 자기-합리화 auto-check
"미미/관행적/보수적이면 OK" 사용 여부: **없음** — robustness를 단정 대신 정량(offset sweep·centered·replication)으로 검증. hand-wave 없음.

## Escalate 판정
PIT hard 위반 ✗ · Σ PD 위반 ✗(Σ 미구축 — active-vol 시계열 모델, §2 근거) · HIGH≥5 ✗ · AX hard-fail≥3 ✗ → **escalate 불요**. self-adversarial이 SC-1에서 결론을 실제 교정(3-source 유효 기여).
