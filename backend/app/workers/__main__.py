"""Run background workers as a separate process: `python -m app.workers` (set RUN_WORKERS=false on the API)."""

import asyncio
import logging
import signal

from app.workers.jobs import run_forever


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:  # Windows
            pass
    await run_forever(stop)


if __name__ == "__main__":
    asyncio.run(main())
