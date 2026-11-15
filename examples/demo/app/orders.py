"""Business rules for orders, with no AWS calls: easy to unit test."""
import base64
import json
from decimal import Decimal


class InvalidOrder(ValueError):
    """A Kinesis record that is not a valid order."""


def parse_record(record: dict) -> dict:
    """Decode one Kinesis record into an order: {"id": ..., "amount": ...}."""
    try:
        order = json.loads(base64.b64decode(record["kinesis"]["data"]))
        Decimal(str(order["amount"]))
        return order
    except (KeyError, TypeError, ValueError, ArithmeticError) as error:
        raise InvalidOrder(str(error)) from error


def summarize(orders: list[dict]) -> dict:
    """Number of orders and their total, rounded to cents (Decimal avoids float drift)."""
    total = sum((Decimal(str(o["amount"])) for o in orders), Decimal("0"))
    return {"orders": len(orders), "total": float(total.quantize(Decimal("0.01")))}
