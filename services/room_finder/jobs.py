import asyncio
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Callable


class JobStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    DONE    = "done"
    FAILED  = "failed"


@dataclass
class Job:
    id:         str
    type:       str
    status:     JobStatus        = JobStatus.PENDING
    result:     Any              = None
    error:      str | None       = None
    queued_at:  str              = field(default_factory=lambda: datetime.now().isoformat())
    started_at: str | None       = None
    finished_at: str | None      = None


# in-memory store — replace with SQLite if persistence across restarts is needed
_store: dict[str, Job] = {}
_queue: asyncio.Queue  = asyncio.Queue()
_executor = ThreadPoolExecutor(max_workers=1)   # single worker keeps GPU/model access safe


def get_job(job_id: str) -> Job | None:
    return _store.get(job_id)


def submit(job_type: str, handler: Callable, payload: Any) -> Job:
    job = Job(id=str(uuid.uuid4()), type=job_type)
    _store[job.id] = job
    _queue.put_nowait((job.id, handler, payload))
    return job


async def worker_loop():
    """
    Infinite loop to process jobs from the queue
    """
    loop = asyncio.get_event_loop()
    while True:
        job_id, handler, payload = await _queue.get()
        job = _store[job_id]
        job.status     = JobStatus.RUNNING
        job.started_at = datetime.now().isoformat()
        try:
            job.result      = await loop.run_in_executor(_executor, handler, payload)
            job.status      = JobStatus.DONE
        except Exception as e:
            job.error  = str(e)
            job.status = JobStatus.FAILED
        finally:
            job.finished_at = datetime.now().isoformat()
        _queue.task_done()
