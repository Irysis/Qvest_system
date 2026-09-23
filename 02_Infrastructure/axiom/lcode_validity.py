#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""lcode_validity.py — L-code **원천 철회 표식**의 단일 판정 함수 + 표식 writer (2026-09-23).

왜 있나 (Axiom 전수감사 K3 · 도훈 AX-D4-PIT-RETRACT 승인)
---------------------------------------------------------
08-20 에 동월 look-ahead 로 철회된 6월 Shu-Mulvey L-code 가 **원천 파일에 표식이 없어서** 지식층에 다시
수입됐다: 08-22 DIST 수기 정정 다음 날(08-23) 기계 승격이 다시 들여왔고(AX-RAMP-005/006 근거 계산),
오히려 4건에 promoted_to_axiom 역링크가 새로 쓰였다. 철회 사실이 보고서·레지스트리·정정 L-code 에만 있고
**원천에는 없었기** 때문이다 — 소비자는 원천만 읽는다.

규약 (필드 정의 정본 = 02_Infrastructure/axiom/lcode_schema.R::LCODE_INVALIDATION_FIELDS)
-------------------------------------------------------------------------------------
  pit_invalid        : true  — PIT 위반으로 측정 자체가 무효(C1~C15). 결론이 뒤에 재확인돼도 이 측정은 무효다.
  retracted_by       : str   — 철회 근거 참조(정정 L-code id · 레지스트리 경로 · 보고서 절). 비어 있으면 표식이 아니다.
  retracted_at       : str   — 철회(판정) 일자. 표식을 단 날이 아니라 철회가 확정된 날.
  retraction_reason  : str   — 1~2문장 기전.
  retraction_marked_at / retraction_decision_ref / retraction_marked_by — 표식 행위의 감사 흔적.
원 필드(lesson_text·grade·수치·promoted_to_axiom …)는 **한 글자도 바꾸지 않는다** — 철회는 삭제가 아니다(AX-000·INV-7).

단일 판정 함수 — `lcode_invalidation(record) -> str | None`
-----------------------------------------------------------
  ★이 함수 하나가 "이 L-code 를 지식으로 소비해도 되는가"의 유일한 판정이다. 사본을 만들지 않는다.
  소비자:
    ① lcode_harvester.py::harvest()  — 수확 단계에서 제외(corpus.lcodes 에 안 들어감) + corpus.invalidated_lcodes 에
       (id·사유·원천) 기록 → corpus 를 읽는 전 하류(cluster_extractor CAND/DIST · promote · positive_context 최근교훈 ·
       hypothesis_index · knowledge_index)가 자동으로 막힌다.
    ② (예정) P3 rf_lessons 적재(02_Infrastructure/reinforcement/rf_lessons.R — 미구현) — **같은 함수**를 쓴다:
       corpus(.cache/lcode_corpus.json::lcodes)에서 읽으면 이미 걸러져 있고, 원천 파일을 직접 읽어야 하면
       R 래퍼 lcode_schema.R::lcode_invalidation_check(paths) 가 이 모듈의 CLI(`check`)를 부른다 — R 로 재구현 금지.
  판정은 **보수(제외) 쪽**이다: 표식이 모호하게 적혀도(문자열 "true" · 길이 1 배열[true]) 무효로 본다.

CLI
---
  python lcode_validity.py check <l_code_file.json> [...]      → JSON 배열 [{path,l_code,invalid,reason}]
  python lcode_validity.py mark --spec <spec.json> [--backup-dir DIR] [--dry-run]
      spec = {"retracted_by":..., "retracted_at":..., "retraction_reason":..., "decision_ref":..., "marked_by":...,
              "pit_invalid": true, "targets": [{"path": "...", "l_code": "L-..."}, ...]}
      파일마다: 백업(원본 바이트 그대로) → 필드 추가 → 원자 쓰기(tmp→os.replace, CRLF·들여쓰기 보존) → 되읽기 검증.
      이미 같은 표식이면 무쓰기(멱등).
"""
from __future__ import annotations

import argparse
import io
import json
import os
import shutil
import sys
import time
from datetime import datetime

INVALIDATION_FIELDS = ("pit_invalid", "retracted_by")          # 판정에 쓰는 필드 (둘 중 하나면 무효)
AUDIT_FIELDS = ("retracted_at", "retraction_reason", "retraction_decision_ref",
                "retraction_marked_at", "retraction_marked_by")
_TRUE_TOKENS = {"true", "1", "yes", "y", "t"}


def _scalar(v):
    """R write_json 이 길이-1 벡터를 배열로 낼 수 있다([true] / ["..."]) — 스칼라로 접는다."""
    if isinstance(v, list) and len(v) == 1:
        return v[0]
    return v


def lcode_invalidation(record) -> "str | None":
    """L-code 1건이 **소비 불가**(철회·PIT 무효)이면 사유 문자열, 아니면 None.

    ★단일 정본 — 수확(harvester)·P3 rf_lessons 적재가 이 함수를 공유한다(모듈 docstring).
    보수 규칙: pit_invalid 가 참으로 읽힐 여지가 있으면(True · "true" · 1 · [true]) 무효.
               retracted_by 가 비지 않은 문자열(또는 비지 않은 목록)이면 무효.
    """
    if not isinstance(record, dict):
        return None
    reasons = []
    pv = _scalar(record.get("pit_invalid"))
    if pv is True or (isinstance(pv, (int, float)) and not isinstance(pv, bool) and pv == 1) \
            or (isinstance(pv, str) and pv.strip().lower() in _TRUE_TOKENS):
        reasons.append("pit_invalid")
    rb = _scalar(record.get("retracted_by"))
    if isinstance(rb, str) and rb.strip():
        reasons.append("retracted_by=" + rb.strip()[:160])
    elif isinstance(rb, list) and any(isinstance(x, str) and x.strip() for x in rb):
        reasons.append("retracted_by=" + "; ".join(x.strip() for x in rb if isinstance(x, str) and x.strip())[:160])
    return " | ".join(reasons) if reasons else None


# ── 원자 쓰기 (harvester::_write_json_atomic 과 같은 계약: 같은 디렉터리 tmp → os.replace · 유한 재시도) ──
#   여기에 두는 이유: harvester 가 이 모듈을 import 하므로 역방향 import 는 순환이 된다.
#   추가 계약: 원본의 줄바꿈(CRLF/LF)·끝 줄바꿈·들여쓰기 폭을 보존한다(원장 diff 최소화 — 필드 추가만 보이게).
_RETRIES = 8


def _detect_style(raw: bytes):
    crlf = b"\r\n" in raw
    trailing_nl = raw.endswith(b"\n")
    indent = 2
    for ln in raw.decode("utf-8", "replace").splitlines()[1:6]:
        s = len(ln) - len(ln.lstrip(" "))
        if s > 0:
            indent = s
            break
    return crlf, indent, trailing_nl


def _atomic_write_like(obj: dict, path: str, crlf: bool, indent: int, trailing_nl: bool = True) -> None:
    d = os.path.dirname(path) or "."
    tmp = os.path.join(d, ".%s.tmp_%d" % (os.path.basename(path), os.getpid()))
    txt = json.dumps(obj, indent=indent, ensure_ascii=False)
    if trailing_nl:
        txt += "\n"
    if crlf:
        txt = txt.replace("\n", "\r\n")
    with io.open(tmp, "wb") as fh:
        fh.write(txt.encode("utf-8"))
    chk = json.loads(io.open(tmp, "rb").read().decode("utf-8"))   # 되읽기 검증 — 파싱 불가를 정본에 올리지 않는다
    if chk != obj:
        os.remove(tmp)
        raise ValueError("되읽기 불일치 — 정본 미갱신: %s" % path)
    last = None
    for i in range(_RETRIES):
        try:
            os.replace(tmp, path)
            return
        except OSError as exc:
            last = exc
            time.sleep(min(0.25, 0.02 * (2 ** i)))
    try:
        os.remove(tmp)
    except OSError:
        pass
    raise OSError("원자적 기록 실패 (os.replace %d회) — 정본 미갱신: %s (%s)" % (_RETRIES, path, last))


def mark_lcode_invalid(path: str, *, retracted_by: str, retracted_at: str, reason: str,
                       decision_ref: str, marked_by: str, pit_invalid: bool = True,
                       backup_dir: "str | None" = None, dry_run: bool = False) -> dict:
    """원천 L-code 파일 1건에 철회 표식을 단다. 원 필드는 불변(추가만). 반환 = 결과 dict."""
    if not (isinstance(retracted_by, str) and retracted_by.strip()):
        raise ValueError("retracted_by 필수 — 근거 없는 표식은 기록이 아니다")
    raw = io.open(path, "rb").read()
    rec = json.loads(raw.decode("utf-8-sig"))
    if not isinstance(rec, dict):
        raise ValueError("L-code 파일이 객체가 아님: %s" % path)
    want = {"pit_invalid": bool(pit_invalid), "retracted_by": retracted_by.strip(),
            "retracted_at": retracted_at, "retraction_reason": reason,
            "retraction_decision_ref": decision_ref}
    same = all(rec.get(k) == v for k, v in want.items())
    out = {"path": path, "l_code": rec.get("l_code"), "action": None}
    if same:
        out["action"] = "unchanged"
        return out
    new = dict(rec)                                  # 원 키 순서 유지 + 뒤에 추가
    for k, v in want.items():
        new[k] = v
    new["retraction_marked_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
    new["retraction_marked_by"] = marked_by
    for k in rec:                                    # 원 필드 불변 단정(방어)
        if k in want or k in ("retraction_marked_at", "retraction_marked_by"):
            continue
        assert new[k] == rec[k], k
    if dry_run:
        out["action"] = "would_mark"
        return out
    if backup_dir:
        os.makedirs(backup_dir, exist_ok=True)
        bp = os.path.join(backup_dir, os.path.basename(path))
        if not os.path.exists(bp):                   # 최초 원본만 보존(재실행이 백업을 덮지 않게)
            shutil.copy2(path, bp)
        out["backup"] = bp
    crlf, indent, trailing_nl = _detect_style(raw)
    _atomic_write_like(new, path, crlf, indent, trailing_nl)
    back = json.loads(io.open(path, "rb").read().decode("utf-8"))
    if lcode_invalidation(back) is None:
        raise RuntimeError("표식 후 판정이 무효를 못 냄 — 계약 위반: %s" % path)
    out["action"] = "marked"
    return out


def _cmd_check(paths):
    res = []
    for p in paths:
        try:
            rec = json.loads(io.open(p, "rb").read().decode("utf-8-sig"))
            why = lcode_invalidation(rec)
            res.append({"path": p, "l_code": rec.get("l_code") if isinstance(rec, dict) else None,
                        "invalid": why is not None, "reason": why})
        except Exception as exc:  # noqa: BLE001 — 읽지 못한 원천은 판정 불가로 정직 표기
            res.append({"path": p, "l_code": None, "invalid": None, "reason": "unreadable: %s" % exc})
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(res, ensure_ascii=False))
    return 0


def _cmd_mark(spec_path, backup_dir, dry_run):
    spec = json.loads(io.open(spec_path, "rb").read().decode("utf-8"))
    res = []
    for t in spec["targets"]:
        rec = json.loads(io.open(t["path"], "rb").read().decode("utf-8-sig"))
        if t.get("l_code") and rec.get("l_code") != t["l_code"]:
            raise ValueError("대상 불일치: %s 의 l_code=%s ≠ %s" % (t["path"], rec.get("l_code"), t["l_code"]))
        res.append(mark_lcode_invalid(
            t["path"], retracted_by=t.get("retracted_by") or spec["retracted_by"],
            retracted_at=t.get("retracted_at") or spec["retracted_at"],
            reason=t.get("retraction_reason") or spec["retraction_reason"],
            decision_ref=spec["decision_ref"], marked_by=spec["marked_by"],
            pit_invalid=bool(t.get("pit_invalid", spec.get("pit_invalid", True))),
            backup_dir=backup_dir, dry_run=dry_run))
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(res, ensure_ascii=False, indent=1))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("paths", nargs="+")
    m = sub.add_parser("mark")
    m.add_argument("--spec", required=True)
    m.add_argument("--backup-dir", default=None)
    m.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    if a.cmd == "check":
        return _cmd_check(a.paths)
    return _cmd_mark(a.spec, a.backup_dir, a.dry_run)


if __name__ == "__main__":
    sys.exit(main())
