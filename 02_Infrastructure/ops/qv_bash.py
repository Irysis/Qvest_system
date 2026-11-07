# -*- coding: utf-8 -*-
"""qv_bash.py — Python 에서 bash 를 띄울 때 쓰는 실행 파일 경로 (금칙 ⑦ 의 Python 짝 · 2026-11-07).

왜: Windows 의 subprocess(CreateProcess)는 실행 파일을 PATH 보다 System32 에서 먼저 찾는다.
WSL 이 깔린 PC(메인 MAINCOMPUTER)에는 C:\\Windows\\System32\\bash.exe(WSL 런처)가 있어
subprocess 인자 목록 첫 칸에 bare "bash" 를 두면 리눅스 bash 가 뜬다(실측 2026-11-07 — 훅 배터리
9/15 → Git Bash 고정 시 15/15). 해석 순서는 R 판(qv_bash.R)과 같다:
  ① QVEST_BASH  ② PATH 순서의 첫 bash.exe(Windows 시스템 폴더 · WindowsApps 제외)
  ③ 고정 후보(Rtools45 · Git usr/bin · Git bin)  · 비 Windows = "bash" · Windows 에서 없으면 오류.
사용: sys.path 에 02_Infrastructure/ops 를 넣고 `from qv_bash import qv_bash` →
      subprocess.run([qv_bash(), script, ...])
"""
from __future__ import annotations

import os
import re

_SKIP = re.compile(r"(^|[\\/])(system32|syswow64|sysnative)([\\/]|$)"
                   r"|[\\/]windowsapps([\\/]|$)"
                   r"|^[a-z]:[\\/]+windows[\\/]*$", re.IGNORECASE)
FIXED = ("C:/rtools45/usr/bin/bash.exe",
         "C:/Program Files/Git/usr/bin/bash.exe",
         "C:/Program Files/Git/bin/bash.exe")


def qv_bash(path=None, override=None, fixed=FIXED, windows=None):
    """bash 실행 파일 경로. 인자는 검사용(기본 = 이 프로세스의 PATH · QVEST_BASH · 고정 후보)."""
    if windows is None:
        windows = os.name == "nt"
    if not windows:
        return "bash"
    ov = os.environ.get("QVEST_BASH", "") if override is None else override
    if ov:
        if os.path.isfile(ov):
            return ov.replace("\\", "/")
        raise FileNotFoundError("QVEST_BASH 가 가리키는 파일이 없다: %s" % ov)
    p = os.environ.get("PATH", "") if path is None else path
    for d in p.split(";"):
        d = d.strip().strip('"')
        if not d or _SKIP.search(d):
            continue
        c = os.path.join(d.rstrip("\\/"), "bash.exe")
        if os.path.isfile(c):
            return c.replace("\\", "/")
    for c in fixed:
        if os.path.isfile(c):
            return c
    raise FileNotFoundError("bash.exe 를 찾지 못했다(Git for Windows 또는 Rtools 필요) — "
                            "System32 의 WSL bash 는 쓰지 않는다")


if __name__ == "__main__":
    print(qv_bash())
