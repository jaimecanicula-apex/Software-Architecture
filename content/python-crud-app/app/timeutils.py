"""Naive UTC timestamps for the DateTime (no-timezone) columns in the schema.

datetime.utcnow() is deprecated (Python 3.12+); datetime.now(UTC) is its
replacement but returns a timezone-aware value, which would raise on
comparison against the naive values already in those columns. Stripping
tzinfo keeps every timestamp in the app naive and comparable.
"""
import datetime as dt


def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC).replace(tzinfo=None)
