#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""sot_access_paths_py.py — 정본(JSON) 소비 경로를 **python ast 로** 추출한다.

R 판(02_Infrastructure/ops/sot_access_paths.R)의 python 대응.
설계는 R 판에서 3축 대조(양성/음성/위반주입) + 별칭 ON/OFF 대조로 검증된 것을 이식했다.

배경: 토큰 grep 으로 "어느 필드가 소비되나"를 재려다 같은 부류로 6번 실패했다
      (전부 **표기 형태를 가정**한 것 — CRLF·bold 마커·모듈명·로드 리터럴 위치·os.path.join 등).
      파서를 쓰면 d["a"]["b"] / d.get("a") / t=d["a"]; t.get("b") 가 같은 경로로 모인다.

한계 (정직):
  - 뿌리 변수명을 사람이 지정한다(로드 지점 지목).
  - 동적 키(d[k] 에서 k 가 변수)는 버린다 — 과소 추출 방향(안전).
  - 별칭은 단순 할당만 따른다. 재할당 시 마지막 것으로 덮어쓴다.
  - 조건부 분기·함수 경계를 넘는 흐름은 추적하지 않는다(정적 근사).
"""
import ast
import io
import sys


def _key_of(node):
    """subscript/attribute 에서 문자열 키를 뽑는다. 동적이면 None."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None


def _chain_of(node, roots):
    """node 가 root(또는 별칭)에 뿌리를 둔 접근 체인이면 (root, [keys]) 반환."""
    chain = []
    cur = node
    while True:
        if isinstance(cur, ast.Subscript):
            k = _key_of(cur.slice)
            if k is None:
                return None
            chain.insert(0, k)
            cur = cur.value
        elif (isinstance(cur, ast.Call) and isinstance(cur.func, ast.Attribute)
              and cur.func.attr == "get" and cur.args):
            k = _key_of(cur.args[0])
            if k is None:
                return None
            chain.insert(0, k)
            cur = cur.func.value
        else:
            break
    if isinstance(cur, ast.Name) and cur.id in roots:
        return cur.id, chain
    return None


def extract_paths(path, root_var, follow_alias=True):
    """root_var 에 뿌리를 둔 dict 접근 경로를 'root$a$b' 형태로 반환(R 판과 표기 통일)."""
    src = io.open(path, encoding="utf-8", errors="replace").read()
    tree = ast.parse(src)
    roots = {root_var: []}

    if follow_alias:
        # 고정점까지 반복 — 2단 체인(t = d["a"]; u = t["b"]) 대응
        for _ in range(3):
            for node in ast.walk(tree):
                if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                        and isinstance(node.targets[0], ast.Name):
                    r = _chain_of(node.value, roots)
                    if r and r[1]:
                        roots[node.targets[0].id] = roots[r[0]] + r[1]

    out = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Subscript, ast.Call)):
            r = _chain_of(node, roots)
            if r and r[1]:
                out.add("$".join([root_var] + roots[r[0]] + r[1]))
    return sorted(out)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: sot_access_paths_py.py <file.py> <root_var>")
        raise SystemExit(2)
    for p in extract_paths(sys.argv[1], sys.argv[2]):
        print(p)
