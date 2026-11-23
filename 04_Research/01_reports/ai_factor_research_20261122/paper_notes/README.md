# 논문 판독 노트 — 그림 · 표와 방법론 정리

2026-11-23 도훈 "나머지 PDF 그림들도 모두 확인해줘" · "Barra 리스크모델 방법론 페이퍼 — 참고해". 계획서(`../FOLLOWUP_PLAN.md`)의 '참고한 자료와 확인 수준' 표가 가리키는 판독의 전문이다.

## 파일

| 파일 | 대상 | 읽은 범위 |
|---|---|---|
| `msci_2020_2021.md` | MSCI 2020 "Straight Talk on Nonlinearities in Linear Factor Models" · MSCI 2021 "Machine Learning Factors" | 그림 · 표가 있는 쪽 전부(7쪽 · 14쪽) |
| `adaptive_2018.md` | MSCI 2018 "Adaptive Multi-Factor Allocation" | 그림 쪽 22쪽 + 지표 정의가 적힌 글 쪽 |
| `factor_indexing_2025.md` | MSCI 2025 "Factor Indexing Through the Decades" | 28쪽(6~13 · 16~25 · 27~34 · 36 · 37) |
| `cmf_docs.md` | MSCI Core Multiple-Factor — 연구 논문 2025-10 · 지수 방법론 2025-04 · 소개 자료 | 논문 11쪽 · 방법론 문서(그림 없음) · 소개 자료 7쪽 |
| `common_language_em.md` | MSCI 2026 "The Common Language of Portfolio Construction" · Rao & Gupta 2025 "Long-Term Investing in Emerging Markets" | 14쪽 · 19쪽 |
| `barra_use4_2011.md` | Barra "USE4 Methodology Notes"(2011-08 · 44쪽) | 전문 — 식 · 매개변수 · 절차 |
| `barra_handbook.md` | Barra Risk Model Handbook(204쪽 · 옛 판) | 주식 부분만(1~3장 · 9장 일부 · 용어집) |
| `barra_use4_empirical_2011.md` | Barra "USE4 Empirical Notes"(2011-09 · 62쪽) | 전문 — 추정 유니버스 · 업종 60개 표 · 스타일 팩터 정의(부록 A) · 팩터 통계표 · 설명력 · 예측 정확도 |
| `clarke_desilva_thorley_2024.md` | Clarke, de Silva & Thorley 2024 "Nonlinear Factor Returns in the US Equity Market"(FAJ 80(3) · 웹 인쇄본 35쪽) | 전문 — Q 가 35쪽을 쪽 그림으로 직접 읽음(글이 뽑히지 않는 파일) · 방법 · 표 1~7 · 그림 1~12 · 기술 부록의 직교화 식 |

## 읽은 방법과 확인 수준

- 하위 에이전트(일곱)가 `../tools/pdf_figs.py` 로 쪽을 그림 파일로 바꿔 읽고, 글로 뽑히는 표는 원문 글과 대조해 옮겼다. 차트에서 읽은 값에는 '약'이, 확실치 않은 판독에는 (?)가 붙어 있다. 본문과 그림이 어긋난 곳은 파일마다 따로 적혀 있다.
- Q 가 직접 본 쪽: Adaptive 7 · 13 · 14 · 19쪽 / Factor Indexing 14 · 15 · 26쪽 / CMF 논문 11 · 12 · 15 · 16쪽.
- Q 가 원문을 직접 읽은 부분: USE4 Empirical Notes 의 부록 A(스타일 팩터 12개의 지표 정의와 가중 · 비선형 규모와 비선형 베타의 구성) · 추정 유니버스 · 스타일 팩터 절과 표 4.2 · 설명력 · 검증 방법과 표 5.1.
- Q 가 원문 글과 대조한 값: USE4 의 표 4.1(팩터 공분산 매개변수) · 표 5.1(고유 위험 매개변수) · 표준화(시가총액 가중 평균 · 동일가중 표준편차 · 3 표준편차 절단) · 회귀 가중(시가총액의 제곱근) · 업종 제약 · 복수 업종 가중(0.75 · 0.25).
- Q 가 전문을 직접 읽은 것: Clarke, de Silva & Thorley 2024(도훈 11-23 '보내준 논문 확인도 해' — 하위 에이전트를 쓰지 않았다. 글자가 선으로 들어 있어 글이 뽑히지 않아 35쪽 전부를 그림으로 바꿔 읽었다).
- 그 밖의 값은 하위 에이전트의 판독이다. 계획의 결정에 쓰기 전에 해당 쪽을 다시 확인한다.
- 논문의 쪽 그림은 저장소에 넣지 않았다(세션 임시 폴더에만 있었다).

## 계획에 반영한 것

- 구성 D 의 한국 위험 모형 사양(USE4 의 절차와 매개변수).
- 원문 재현 판의 팩터 정의표(USE4 부록 A → 한국 자료)와 위험 평가 모형 절(Barra 의 철학 여덟 가지 · 위험 평가 보고서 · 검증 설계 — 도훈 11-23).
- 걸음 1 의 표준화 · 회귀 제약, 원문 그림의 눈금(고유수익 곡선의 모양 · 특성 중요도 · 부분 의존 · 상호작용).
- 네 기둥의 신호 형태와 종목 단위 모의실험의 제약, 국면별 팩터 성과표, 혼잡도, CMF 의 추적오차 예산별 결과.
- Clarke 외 2024: 걸음 1 의 세제곱 성분 · 순수 팩터 포트폴리오의 정보비율과 비선형성 검정 · 범주 분해 · 순수함 세 단계 · 시총 가중 참고 판 · 둘째 재현 판, 걸음 3 의 '직전 10년 IR 비례' 단, 구성 C 의 둘째 기울기 식, 비교 1 의 세 갈래(도훈 11-23 '참고해서 계획 보완해줘').
