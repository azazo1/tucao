#!/usr/bin/env python3
"""把日志同时留在内存里, 供状态页查看最近的交互记录."""

import logging
from collections import deque


class MemoryLogHandler(logging.Handler):
    """环形缓冲, 只保存格式化后的文本."""

    def __init__(self, capacity: int = 400):
        super().__init__()
        self._lines: deque[str] = deque(maxlen=capacity)

    def emit(self, record: logging.LogRecord) -> None:
        try:
            self._lines.append(self.format(record))
        except Exception:  # noqa: BLE001 - 日志设施自身不能抛出
            pass

    def lines(self) -> list[str]:
        return list(self._lines)
