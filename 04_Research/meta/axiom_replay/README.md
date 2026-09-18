# axiom_replay — Axiom 엔진 효능 축(리플레이) 1단계

**무엇**: 강화 원장의 연구 기록을 시뮬레이터로 되돌려, "그 규칙대로 했다면 어떻게 됐을까"를 **새 백테스트 없이** 채점하는 계기. Dream-RSI(arXiv 2609.14858) §3 의 off-policy 리플레이를 Qvest 원장에 맞춘 판이다.

**왜**: Axiom 엔진의 5축은 *주장의 근거*를 잰다. *그 지식대로 행동했을 때 좋아졌는가*를 재는 축이 없었다.

**경계**: 하네스 쓰기 0 · QEPM 실행 0회 · 원장/카드/로그 읽기 전용 · 산출물은 이 디렉터리 안에만.
등급은 essence 하나다. 여기서 만드는 V 는 **정책 선택 전용 점수**이고 전략 등급이 아니다(AX-002).

## 실행

```
cd 04_Research/meta/axiom_replay
Rscript tests/_run_world.R        # 세계 빌드 (out/worlds.rds)
Rscript tests/test_pi0_replay.R   # P0 양성 대조 — 현행 정책 재현
Rscript tests/_run_validate.R     # 배치 재구성 대 레인 로그
Rscript R/run_pilot.R             # 정책 비교 + 귀무 + 오라클 + 위반 주입
Rscript tests/_run_wp1.R          # 승격 게이트 반사실
Rscript tests/run_wp3.R           # 엔진 자기평가
```

## 읽는 순서

`out/FINAL_report.md` → 필요하면 `wp1_report.md`(승격·기저 관문) · `wp2_report.md`(격자 리플레이 NO-GO) · `wp3_report.md`(엔진 자기평가).
사전등록과 그 개정은 `preregistration.md`. **결과를 보고 문턱을 바꾸지 않았다는 것**이 이 문서로 확인된다.

## 주의

- 블록의 정본은 **격자 코드**다. `essence$block` 은 B4 결합 칸에서 빠뜨린 축의 블록을 적는다(실측 `B4_24`→`"B5"`).
- 체제를 섞지 말 것. 2026-09-04 에 커서와 누적 규칙이 바뀌었다. P0 는 post_0904 에서만 통과한다.
- 배치 크기는 정책이 아니라 환경(일 상한·재개)이 정한다. 리플레이에 `sizes` 로 부여한다.
