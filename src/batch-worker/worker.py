import hashlib
import json
import os
import socket
import time
from datetime import UTC, datetime

from azure.identity import DefaultAzureCredential
from azure.storage.queue import QueueClient


def log(event: str, **fields: object) -> None:
    print(
        json.dumps(
            {
                "event": event,
                "timestamp": datetime.now(UTC).isoformat(),
                "pod": socket.gethostname(),
                **fields,
            },
            ensure_ascii=False,
        ),
        flush=True,
    )


def process(task_id: str) -> None:
    seconds = int(os.getenv("PROCESS_SECONDS", "20"))
    log("task_started", task_id=task_id, process_seconds=seconds)
    time.sleep(seconds)
    digest = hashlib.sha256(task_id.encode()).hexdigest()
    log("task_completed", task_id=task_id, result=digest)


def queue_client() -> QueueClient:
    account = os.environ["STORAGE_ACCOUNT"]
    queue = os.environ["QUEUE_NAME"]
    credential = DefaultAzureCredential()
    return QueueClient(
        account_url=f"https://{account}.queue.core.windows.net",
        queue_name=queue,
        credential=credential,
    )


def seed() -> None:
    client = queue_client()
    count = int(os.getenv("MESSAGE_COUNT", "20"))
    batch_id = os.getenv("BATCH_ID", datetime.now(UTC).strftime("%Y%m%d%H%M%S"))
    for index in range(1, count + 1):
        payload = json.dumps({"batch_id": batch_id, "task_id": f"task-{index:03d}"})
        client.send_message(payload)
    log("messages_seeded", batch_id=batch_id, count=count)


def process_one_message() -> None:
    client = queue_client()
    messages = client.receive_messages(messages_per_page=1, visibility_timeout=300)
    message = next(iter(messages), None)
    if message is None:
        log("queue_empty")
        return

    payload = json.loads(message.content)
    task_id = str(payload["task_id"])
    process(task_id)
    client.delete_message(message)
    log("message_deleted", task_id=task_id)


def main() -> None:
    mode = os.getenv("RUN_MODE", "compute")
    if mode == "compute":
        task_id = os.getenv("TASK_ID", os.getenv("JOB_COMPLETION_INDEX", "manual"))
        process(task_id)
    elif mode == "seed":
        seed()
    elif mode == "queue":
        process_one_message()
    else:
        raise ValueError(f"Unsupported RUN_MODE: {mode}")


if __name__ == "__main__":
    main()

