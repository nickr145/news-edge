from __future__ import annotations

import asyncio
import statistics
import time

import websockets


async def run(uri: str, samples: int = 20) -> None:
    latencies: list[float] = []
    async with websockets.connect(uri) as ws:
        for _ in range(samples):
            start = time.perf_counter()
            await ws.recv()
            latencies.append((time.perf_counter() - start) * 1000)

    p50 = statistics.median(latencies)
    p99 = sorted(latencies)[max(int(len(latencies) * 0.99) - 1, 0)]
    print(f"samples={len(latencies)} p50_ms={p50:.2f} p99_ms={p99:.2f}")


if __name__ == "__main__":
    asyncio.run(run("ws://localhost:8000/ws/news/NVDA"))
