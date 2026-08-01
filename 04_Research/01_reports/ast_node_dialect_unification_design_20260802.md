# AST 노드 방언 통일 설계안 (ALB-001 잔여)

**작성**: 2026-08-02 야간 (Q-Lead) — **설계안만. 코드 미변경**(FQ-073 R2 라운드가 해당 파일을 사용 중)
**상태**: ALB-001 `partially_resolved` → 본 설계안이 잔여분의 구현 지침
**전제**: 2026-08-02 수리로 검증기가 컴파일러 방언을 **수용**하게 됐다. 본 문서는 그 **비대칭을 대칭으로** 만드는 방법을 다룬다.

---

## 1. 현재 상태 — 무엇이 해결됐고 무엇이 남았나

**해결됨(08-02)**: `ast_verify.py` 가 4축 방언을 전부 수용한다.

| 축 | 컴파일러(`ast_compile.R`) | 검증기 문서형 | 08-02 처리 |
|---|---|---|---|
| 자식 | `args` | `children` | 진입 지점에서 `children or args` |
| 리프 | `{"type":"leaf","class":X}` | `{"leaf":X}` | 진입 지점 정규화(사본에 `leaf` 주입) |
| 파라미터 | `params:{k:12}` | 최상위 `k` | `params` 를 최상위로 병합(최상위 우선) |
| provenance | `contract` | `provenance` | `provenance or contract` |

**남은 것**: 이건 **검증기가 일방적으로 맞춰준 것**이다. 정본 스펙이 없으므로
- 컴파일러가 5번째 방언을 도입하면 검증기는 또 못 읽는다,
- 제3의 소비자(judge·registry·사이드카 분석)가 생기면 각자 4축을 재구현해야 한다.

**다만 위험도는 낮아졌다**: ALB-007 근본 방어(`leaf_count == 0` → `FAIL_CONTRACT`)가 있어, 방언이 또 갈리면 **침묵 통과가 아니라 계약 실패로 드러난다.** 즉 이 잔여는 "조용한 사고" 위험이 아니라 "반복 노동 + 과차단" 비용이다. **긴급도 MEDIUM, 우선순위는 알파 라운드 뒤.**

---

## 2. 왜 "값 통일"이 아니라 "정본 + 어댑터"인가

가장 단순한 안은 "컴파일러를 문서형으로 고친다"이지만 채택하지 않는다:
- `ast_compile.R` 의 `args`/`params` 형태는 **operator_library.json 의 `arity`·`args[].type`·`params[]` 스키마와 1:1 대응**한다(연산자 정의가 이미 그 형태다). 컴파일러를 바꾸면 연산자 라이브러리까지 바꿔야 한다.
- 반대로 검증기 문서형(`children`/최상위 파라미터)은 **문서 가독성**에 최적화돼 있고 헤더 예시·SOT 서술이 그 형태다.
- 둘 다 자기 맥락에서 합리적이다. **한쪽을 죽이는 대신 정본을 선언하고 어댑터를 공유**한다.

## 3. 설계

### 3-1. 정본 = 컴파일러 방언 (`args` / `type:leaf` / `params` / `contract`)
근거: ① 실행되는 트리가 정본이어야 한다(검증 대상과 실행 대상이 갈리면 그 자체가 ALB-007 재발 조건) ② operator_library 스키마와 대응 ③ 실전 산출물(`alpha_package.json`)이 이미 이 형태.
문서형은 **표기 별칭**으로 강등한다 — SOT·헤더 예시는 그대로 두되 "문서 표기, 정본은 컴파일러 형태"를 명시.

### 3-2. 단일 어댑터 `02_Infrastructure/ast/ast_node.py` + `ast_node.R`
양 언어에 **같은 이름·같은 의미**의 접근자만 둔다. 트리를 변환하지 않고 **읽기만 정규화**한다(변환은 사본 생성 비용 + 원본 훼손 위험).

```
node_children(n)   -> list      # children or args or []
node_leaf_kind(n)  -> str|None  # n["leaf"] or (n["type"]=="leaf" and n["class"])
node_param(n, k)   -> any       # n[k] if present else (n["params"] or {})[k]
node_provenance(n) -> dict      # n["provenance"] or n["contract"] or {}
node_is_leaf(n)    -> bool
node_op(n)         -> str|None
```

`ast_verify.py` 의 08-02 인라인 정규화를 이 접근자 호출로 교체한다(동작 동일, 중복 제거).

### 3-3. 계약 테스트 — **양 언어가 같은 트리에 같은 답을 내는가**
신설 `08_Tests/contracts/test_ast_node_adapter.*`:
- 픽스처 = 두 방언으로 쓴 **동일 의미** 트리 쌍 N개(리프 1/중첩/escape/다중 파라미터).
- 주장: 두 트리에 대해 `node_children` 길이 · `node_leaf_kind` · `node_param("k")` · `node_provenance` 키셋이 **완전 일치**.
- 그리고 **R 접근자와 Python 접근자의 답이 서로 일치**(크로스-언어 parity). 이게 없으면 한쪽만 고쳐지고 갈리는 게 반복된다.
- **위반 주입**: 5번째 방언(예: 자식을 `operands` 로)을 넣었을 때 → 접근자가 조용히 `[]` 를 주지 말고 **명시적으로 미인식을 알릴 것**(그래야 ALB-007 가드가 FAIL 로 잡는다). 음성 통제: 정상 트리는 여전히 통과.

### 3-4. 확장 규율
새 방언이 필요하면 **접근자 한 곳만** 고치고 계약 테스트에 쌍을 추가한다. 소비자 코드는 손대지 않는다. 이 규율이 없으면 소비자가 늘어날수록 4축 재구현이 증식한다.

---

## 4. 하지 말 것

- ~~트리 일괄 변환(normalize 후 저장)~~ — 저장된 `alpha_package.json` 을 재작성하면 `store_build_hash`·사이드카 조인 키가 흔들린다. **읽기 정규화만.**
- ~~검증기 방언을 정본으로~~ — 실행 트리와 검증 트리가 갈린다(§3-1).
- ~~ALB-007 가드 완화~~ — 어댑터가 생겨도 `leaf_count==0 → FAIL_CONTRACT` 는 유지한다. 어댑터는 방언을 줄일 뿐 미래의 미인식을 없애지 못한다. **가드가 최후 방어선이다.**

## 5. 착수 조건
FQ-073 R2 라운드 종료 후(해당 파일 사용 중). 예상 규모: 접근자 2파일 + 검증기 호출 교체 + 계약 테스트 1쌍. 알파 라운드보다 우선하지 않는다.

## 참조
`06_Registry/ast_leaf_table_bugs.jsonl` ALB-001/007 · `02_Infrastructure/docs/qvest_ast_v1_1_sot.md` §2 · `08_Tests/hooks/test_ast_verify_dialect.sh`(현행 12/14 케이스가 방언 수용을 고정)
