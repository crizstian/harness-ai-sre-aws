import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    if not isinstance(event, dict):
        raise ValueError("Expected a JSON object")

    logger.info(
        "Demo invocation: %s",
        json.dumps({
            "request_id": context.aws_request_id,
            "event": event
        })
    )

    if event.get("fail", False) is True:
        logger.error("Deliberate failure for Harness AI SRE lab")
        raise RuntimeError(
            "Harness AI SRE demo: intentional Lambda failure"
        )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Harness AI SRE demo: successful invocation",
            "request_id": context.aws_request_id
        })
    }
