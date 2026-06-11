#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""utf8_output_guard.py — Claude Code Bash 출력 sanitizer (v8.1.2 2026-06-11)

목적: Anthropic API 400 "invalid high surrogate in string" 차단.
  - Claude Code는 Bash 출력을 JS(UTF-16) 문자열로 보관하고 약 30k자에서 절단한다.
    non-BMP 문자(U+10000 이상 — 이모지 등)는 UTF-16에서 surrogate pair 2 code-unit이라
    절단점에 걸리면 lone surrogate가 남고, JSON 직렬화 시 RFC 8259 위반으로
    API가 400을 반환한다. (anthropics/claude-code#44230, #16294, #15027)
  - invalid UTF-8 byte(CP949 혼입, multibyte 절단)도 동일 계열 위험.

처리 (stdin bytes -> stdout UTF-8 bytes, 줄 단위 스트리밍):
  1) UTF-8 decode (errors='replace': invalid byte -> U+FFFD)
  2) non-BMP(U+10000+) / surrogate 영역(U+D800-DFFF) / U+FFFD -> '?'
  3) 줄당 MAX_LINE자 초과 시 절단 마커 부착 (1-line spew 방어)
출력은 항상 BMP-only 유효 UTF-8 -> 어떤 지점에서 절단돼도 surrogate가 깨질 수 없다.

사용:
  some_command 2>&1 | python3 -u 02_Infrastructure/ops/utf8_output_guard.py
  - bootstrap.sh: 자체 재실행 래퍼로 자동 적용 (QVEST_BOOT_SANITIZED)
  - 임의 커맨드: bash 02_Infrastructure/ops/safe_run.sh <cmd> [args...]
"""
import sys

MAX_LINE = 4000  # 줄당 상한. 부트 요약 라인 보존을 위해 전체가 아닌 줄 단위로만 절단.


def sanitize_line(raw: bytes) -> bytes:
    s = raw.decode("utf-8", errors="replace")
    has_nl = s.endswith("\n")
    if has_nl:
        s = s[:-1]
    out = []
    for ch in s:
        cp = ord(ch)
        if cp > 0xFFFF or 0xD800 <= cp <= 0xDFFF or cp == 0xFFFD:
            out.append("?")
        else:
            out.append(ch)
    s = "".join(out)
    if len(s) > MAX_LINE:
        s = s[:MAX_LINE] + " ...[line truncated by utf8_output_guard]"
    if has_nl:
        s += "\n"
    return s.encode("utf-8")


def main() -> int:
    src = sys.stdin.buffer
    dst = sys.stdout.buffer
    try:
        for raw in src:
            dst.write(sanitize_line(raw))
            dst.flush()
    except BrokenPipeError:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
