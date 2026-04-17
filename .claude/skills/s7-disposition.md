---
name: s7-disposition
description: "S7 최종 판정 시 적용 — Grade 확정, L-code 필수, evolution_path"
---
## S7 최종 판정

### Disposition 분류
| 판정 | 조건 | 다음 경로 |
|------|------|----------|
| **Approved** | Grade A/A_NOVEL + Gate 0~5 통과 | → PG0 |
| **Conditional** | Grade B + 조건부 통과 | → S5 재순환 또는 PG0 |
| **Archive** | Grade C | → ARCHIVE + L-code |
| **Discard** | Grade F | → DISCARD + L-code |

### Grade 기준 (hurdle v2.2)
- A: !hard_fail && score≥40 && CAGR≥16% && SR≥0.8
- A_NOVEL: !hard_fail && score≥40 && CAGR≥12% && SR≥0.6 && novelty≥10
- B: !hard_fail && score≥40
- C: MDD≤50% && SR≥0.3 && score≥25
- F: else

### L-code 필수 (S7에서도)
Approved/Archive/Discard 모든 경우에 L-code 작성.
성공도 실패도 반드시 축적 (성공만 기록 금지).
