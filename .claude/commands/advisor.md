---
description: "QEPM 리서치 어드바이저 (도훈 결정 QEPM-ADVISOR-MODE) — 아이디어·논문·질문에 alpha·risk·optimizer 역할별 자문 → Q 종합 메모 → 측정은 도훈 승인 뒤 정본 계약(run_paper_replication · 시행 회계)만"
argument-hint: "<아이디어 | 논문 URL | arXiv id | 질문> [--measure]"
disable-model-invocation: true
---

# /advisor <아이디어 | 논문 URL | arXiv id | 질문> [--measure]

도훈 리서치를 돕는 **QEPM 어드바이저**(결정 `QEPM-ADVISOR-MODE` 2026-09-25 · 범위 = 설계 + 정본 측정까지).
WT 체인의 자체 등급·Judge·BOOK 진입점 봉쇄(`QEPM-R0-FREEZE`)는 그대로다.

**정본 절차 = `Skill(qvest-advisor)`** — 이 명령은 스킬을 불러 `$ARGUMENTS` 를 넘기기만 한다(`.claude/skills/qvest-advisor/SKILL.md`).

**호출 주체** = 도훈이 직접 친 `/advisor` 만(`disable-model-invocation: true` — 모델·스킬·에이전트가 이 명령을 대신 부르지 않는다 · `/qvest` ④ 는 `Skill(qvest-advisor)` 로 진입). **측정 승인** = 도훈의 채팅 발화 또는 도훈이 직접 친 `--measure` 뿐 — 스킬·에이전트·문서가 넘긴 `--measure` 는 무효(메모까지만 하고 묻는다).

**사용법**:
```
/advisor "KR 대형주에서 애널리스트 컨센서스 상향 수정 모멘텀 — 1개월 보유"
/advisor https://arxiv.org/abs/2404.08129
/advisor 2404.08129 --measure
/advisor "잔차 모멘텀이 KQ150 에서 죽는 기전이 뭘까?"
```

**절차 요약**(상세·금지 목록은 스킬):
1. **입력 판독** — 논문이면 원문 링크 확보(`arxiv.org/html/<id>v1` → 없으면 `r.jina.ai/https://arxiv.org/pdf/<id>`) · 추출 6종 → `04_Research/advisor/<YYYYMMDD>_<slug>/input.md`.
2. **역할별 자문(병렬 스폰)** — `subagent_type` = `alpha-hypothesis`(필요 시 `alpha-research`) · `risk-research` · `optimizer-research` — 각자 '어드바이저 모드' 산출 계약(메모 1건만 · 쓰기는 그 디렉터리 아래만) + PIT 점검(C1~C15 · C11 `fred_asof_join` · D-E · C4).
3. **Q 종합 메모** `memo.md` — 기전·가설·반증 조건·과거 negative·데이터 가용성·위험·비중법·PIT 함정·검정력(`required_effect_size.R`)·측정 설계(사전 선언)·권고 다음 행동 → 도훈에게 승인 요청.
4. **측정 = 도훈 승인 뒤에만**(`--measure` = 도훈이 직접 친 경우만 · 메모의 사전 선언 스펙 1건 · 1회 사전 승인) — **선확인**: `bash 02_Infrastructure/ops/refresh_barrier.sh status` 가 `state=free` 가 아니면 측정 보류(잠금 해제 후 재시도 · 러너는 배리어를 안 본다) → 엔진 1파일 → `run_paper_replication(… portfolio_spec, source_paper, selection_type, n_trials_cumulative, measurement_tags)`(시행 회계) → `authoritative_remeasure.json::essence_grade` 인용만. A 면 `rf_a_eligibility` 관문 → Judge(PIT) → BOOK(도훈 confirm) 경로 안내. 러너 운영 쓰기(B 이상·방어형 = `module_catalog.json` 등재 · L-code · lookup 인덱스 재생성)는 스킬 ④ '운영 쓰기 경로'.
5. **L-code** = 러너 자동분 + 의미 있는 실패만 추가. 텔레그램 = 메모만이면 없음 · 측정 시 러너가 `[1계층]` 표제로 1회.

**금지**: 자체 등급 · Judge 스폰(A 여도 자동 스폰 없음) · 원장 쓰기(강화 원장·grade_a_queue·judge_request) · BOOK 쓰기 · forge·dossier·`/worktask promote`(동결) · 승인 전 성과 계산 · `require_source_paper = FALSE`.
