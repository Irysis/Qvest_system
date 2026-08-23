#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""build_distilled_usage — DIST 카드의 **실사용 빈도** 사전 산출.

배경 (2026-08-16 Axiom 폐쇄루프 감사):
  주입 훅 `axiom_context_inject.sh` 가 distilled 카드를 `refined_at` 최신순 top-5 로 고른다.
  실측: 주입 5건 중 4건은 **아무도 인용하지 않았고**, 최다 인용 카드 DIST-QPM-003(12파일)은
  주입에서 빠져 있었다. 랭킹이 실사용과 무관하기 때문이다.

왜 사전 산출인가:
  훅은 매 Agent spawn 마다 돈다. 269개 WT 디렉터리 + 레지스트리를 그때마다 스캔할 수 없다.
  ⇒ 이 스크립트가 `.cache/distilled_usage.json` 을 쓰고, 훅은 그 파일만 읽는다(부재 시 기존 동작 유지).

★소비면 선정 원칙 — **생산 파일 제외**:
  DIST 카드 자신(`distilled/*.json`)과 통합 인덱스(`distilled_knowledge.json`)는 자기 id 를 담으므로
  세면 전건이 '사용'으로 계상된다(자기참조 오염). 소비면만 센다.

★단위 = **파일 수**이지 등장 횟수가 아니다. 한 파일이 같은 id 를 10번 써도 1로 센다
  (긴 문서 하나가 랭킹을 지배하는 것을 막는다).
"""
import json
import os
import re
import sys
import glob
import collections
import datetime

DIST_RE = re.compile(r"DIST-[A-Z]+-\d+")


def _root():
    for k in ("CLAUDE_PROJECT_DIR", "QM_ROOT"):
        v = os.environ.get(k, "")
        if v and os.path.exists(os.path.join(v, "CLAUDE.md")):
            return v.replace("\\", "/")
    return os.getcwd().replace("\\", "/")


def _read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""


def consumption_surfaces(root):
    """소비면 열거 — 생산 파일(카드 자신·통합 인덱스)은 제외."""
    out = []
    # ① WT 설계·심판 면
    for d in glob.glob(os.path.join(root, "qepm", "mailbox", "worktask", "*")):
        if not os.path.isdir(d):
            continue
        for f in ("request.json", "alpha_hypothesis.json",
                  "challenge_note.md", "challenge_note_hypothesis.md",
                  "alpha_package.json"):
            p = os.path.join(d, f)
            if os.path.exists(p):
                out.append(p)
    # ② 큐·지도 (라운드 선택 입력면)
    # ★hypothesis_index.json 은 **제외** — 실측(2026-08-16): 이 파일이 DIST id 120종을 *나열*하므로
    #   포함하면 사용 1회 카드 102종 중 87종이 '인덱스에 실렸다'는 사실만으로 계상돼 랭킹이 평탄해진다.
    #   등재는 소비가 아니다(생산 파일 제외와 같은 원리 — 자기참조는 아니나 판별력 0).
    # ★`layer_bottleneck_map.md` 제거 (2026-08-23 v9 Lean Loop §3.4(f) / 도훈 승인 D-h):
    #   그 지도는 `06_Registry/_archive/layer_bottleneck_map_20260822.md` 로 아카이브됐고
    #   갱신 의무가 폐지됐다. 소비면 목록에 남겨두면 **아카이브된 문서의 언급이 '소비'로
    #   계상**돼 카드 랭킹이 실제와 어긋난다(등재는 소비가 아니라는 위 ② 주석과 같은 원리).
    for rel in ("06_Registry/alpha_frontier_queue.json",
                "06_Registry/infra_backlog.json"):
        p = os.path.join(root, rel)
        if os.path.exists(p):
            out.append(p)
    # ③ 주간 증류 산출 (사람이 읽는 소비면)
    out += sorted(glob.glob(os.path.join(root, "04_Research", "01_reports", "weekly", "*.md")))
    return out


def build(root, verbose=True):
    surfaces = consumption_surfaces(root)
    per_id = collections.Counter()
    per_id_files = collections.defaultdict(list)
    for p in surfaces:
        txt = _read(p)
        if not txt:
            continue
        # ★파일 단위 집계 — set() 으로 중복 등장 1회 처리
        for did in set(DIST_RE.findall(txt)):
            per_id[did] += 1
            rel = os.path.relpath(p, root).replace("\\", "/")
            if len(per_id_files[did]) < 8:
                per_id_files[did].append(rel)

    # 카드 명부 — 존재하지 않는 id 인용(오타·폐기)도 기록해 드리프트를 보이게 한다
    known = set()
    dk = os.path.join(root, "06_Registry", "distilled_knowledge.json")
    if os.path.exists(dk):
        try:
            with open(dk, encoding="utf-8") as f:
                known = {e.get("dist_id") for e in json.load(f).get("entries", [])}
        except Exception:
            pass
    dangling = sorted(i for i in per_id if known and i not in known)

    payload = {
        "schema_version": "distilled_usage_v1",
        "generated_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generator": "02_Infrastructure/ops/build_distilled_usage.py",
        "note": ("DIST 카드 실사용 빈도(소비면 **파일 수**). 생산 파일(distilled/*.json, "
                 "distilled_knowledge.json)은 자기참조 오염이라 제외. "
                 "★2026-08-23 v9 Lean Loop: 구 소비자 2종(axiom_context_inject.sh 의 DIST "
                 "negative top-5 랭킹 · _shared_prefix.md distilled_map 블록)이 주입면에서 "
                 "제거돼 현재 자동 소비자는 없다. 카드 실사용 감사·수동 조회용 산출물."),
        "n_surfaces_scanned": len(surfaces),
        "n_ids_cited": len(per_id),
        "n_dangling": len(dangling),
        "dangling_ids": dangling,
        "usage": dict(per_id.most_common()),
        "usage_files": {k: per_id_files[k] for k, _ in per_id.most_common()},
    }
    outp = os.path.join(root, ".cache", "distilled_usage.json")
    os.makedirs(os.path.dirname(outp), exist_ok=True)
    with open(outp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)

    if verbose:
        print("[distilled_usage] 소비면 %d 파일 스캔 · 인용 id %d종 · dangling %d"
              % (len(surfaces), len(per_id), len(dangling)))
        for k, v in per_id.most_common(10):
            print("   %-16s %3d 파일" % (k, v))
        print("[distilled_usage] -> %s" % outp)
    return payload


PREFIX_START = "<!-- DISTILLED_MAP_START (generated — build_distilled_usage.py) -->"
PREFIX_END = "<!-- DISTILLED_MAP_END -->"


def write_prefix_block(root, top_k=5, verbose=True):
    """_shared_prefix.md 에 실사용-랭킹 distilled 블록을 멱등 갱신.

    ★(v9 Lean Loop 2026-08-23) **기본 경로에서 호출하지 않는다** — `__main__` 배선 제거.
      사유: 이 블록은 negative/conditional 카드 top-5 를 모든 agent 의 의무 pull 면에 실어,
      주입 훅과 합쳐 지식 입력의 대부분을 "죽은 방향 재제안 금지" 로 만들었다(v9 재극성).
      함수는 남긴다 — 되돌리려면 이 함수를 다시 부르면 되고, 삭제하면 그 레시피가 사라진다.
      `.cache/distilled_usage.json` 산출(build)은 불변이며 다른 소비자가 계속 읽는다.

    ★도달 경로 정직 표기: `_shared_prefix.md` 는 하네스가 서브에이전트에 자동 주입하는 면이 아니다.
      10개 agent 정의(.claude/agents/*.md)가 '모든 agent autoload' 로 지목하는 **의무 pull** 면이다.
      2026-08-16 폐쇄루프 감사 실측: PreToolUse additionalContext 는 호출자 컨텍스트에 붙어
      서브에이전트 도달 0/247. 그래서 훅만으로는 push 가 성립하지 않는다.
    """
    usage = {}
    up = os.path.join(root, ".cache", "distilled_usage.json")
    try:
        with open(up, encoding="utf-8") as f:
            usage = (json.load(f) or {}).get("usage") or {}
    except Exception:
        usage = {}

    dk = os.path.join(root, "06_Registry", "distilled_knowledge.json")
    try:
        with open(dk, encoding="utf-8") as f:
            entries = json.load(f).get("entries", [])
    except Exception:
        if verbose:
            print("[distilled_usage] distilled_knowledge.json 읽기 실패 — prefix 갱신 생략")
        return False

    picks = [e for e in entries
             if e.get("status") == "distilled"
             and e.get("polarity") in ("negative", "conditional")
             and (e.get("statement_refined") or "").strip()]
    # 훅과 **동일한 정렬 키** — 두 소비면이 갈리면 그 자체가 드리프트다
    picks.sort(key=lambda e: (int(usage.get(e.get("dist_id"), 0)), e.get("refined_at") or ""),
               reverse=True)

    lines = [PREFIX_START,
             "<distilled_map>",
             "[Distilled 탐색지도 — 가설 착수 전 대조. 판결이 아니라 방향(프론티어) 표시다.]",
             "[선정 = 실사용 빈도순(소비면 파일 수), 동률 시 최신 정제순. 생산자 = build_distilled_usage.py]"]
    for e in picks[:top_k]:
        tag = "탐색됨→프론티어(INV-7 조건-안 차별점 시 진행)" if e.get("polarity") == "negative" else "조건부"
        n = int(usage.get(e.get("dist_id"), 0))
        stmt = " ".join((e.get("statement_refined") or "").split())[:180]
        lines.append(f"  - {e.get('dist_id')} [{tag}· 인용 {n}] {stmt}")
    lines += ["</distilled_map>", PREFIX_END]
    block = "\n".join(lines)

    pp = os.path.join(root, "02_Infrastructure", "prompts", "_shared_prefix.md")
    cur = _read(pp)
    if not cur:
        if verbose:
            print("[distilled_usage] _shared_prefix.md 부재 — 갱신 생략")
        return False

    if PREFIX_START in cur and PREFIX_END in cur:
        pre, _, rest = cur.partition(PREFIX_START)
        _, _, post = rest.partition(PREFIX_END)
        new = pre + block + post
    else:
        new = cur.rstrip() + "\n\n" + block + "\n"

    if new == cur:
        if verbose:
            print("[distilled_usage] _shared_prefix.md 변경 없음(멱등)")
        return True
    with open(pp, "w", encoding="utf-8") as f:
        f.write(new)
    if verbose:
        print("[distilled_usage] _shared_prefix.md <distilled_map> 갱신 — top%d: %s"
              % (top_k, ", ".join(f"{e.get('dist_id')}({int(usage.get(e.get('dist_id'),0))})"
                                  for e in picks[:top_k])))
    return True


if __name__ == "__main__":
    q = "--quiet" in sys.argv
    build(_root(), verbose=not q)
    # (v9 Lean Loop 2026-08-23) 프리픽스 재작성 중단 — `.cache/distilled_usage.json` 만 쓴다.
    #   구 동작을 되살리려면 --write-prefix. 기본값이 '안 쓴다' 인 것이 요점이다.
    if "--write-prefix" in sys.argv:
        write_prefix_block(_root(), verbose=not q)
