import io
import json
import os
import unittest
from unittest import mock

os.environ.setdefault("CAP_USD", "5")

import guard  # noqa: E402


class FakeRedis:
    def __init__(self, data: dict[str, str]):
        self.data = dict(data)

    def __call__(self, *args: str) -> object:
        command = args[0]
        if command == "KEYS":
            prefix = args[1].rstrip("*")
            return [k for k in self.data if k.startswith(prefix)]
        if command == "GET":
            return self.data.get(args[1])
        if command == "SET":
            self.data[args[1]] = args[2]
            return "OK"
        raise AssertionError(f"unexpected command {args}")


class CumulativeSpendTest(unittest.TestCase):
    def test_spend_is_the_sum_of_every_window_ever_seen(self):
        # Arrange
        redis = FakeRedis({"cnp:ai-spend:window:1734048000": "4000000", "ai-budget_platform_all_1765584000": "250000"})

        # Act
        with mock.patch.object(guard, "redis_command", redis):
            spend = guard.cumulative_spend_micro_usd()

        # Assert
        self.assertEqual(spend, 4_250_000)

    def test_spend_survives_the_window_expiring(self):
        # Arrange
        redis = FakeRedis({"ai-budget_platform_all_1765584000": "1200000"})
        with mock.patch.object(guard, "redis_command", redis):
            guard.cumulative_spend_micro_usd()
        del redis.data["ai-budget_platform_all_1765584000"]

        # Act
        with mock.patch.object(guard, "redis_command", redis):
            spend = guard.cumulative_spend_micro_usd()

        # Assert
        self.assertEqual(spend, 1_200_000)


class ReplyParsingTest(unittest.TestCase):
    def test_parses_bulk_strings_arrays_and_nil(self):
        # Arrange
        raw = b"*3\r\n$5\r\nhello\r\n$-1\r\n:42\r\n"

        # Act
        reply = guard._read_reply(io.BytesIO(raw))

        # Assert
        self.assertEqual(reply, ["hello", None, 42])

    def test_raises_on_redis_error(self):
        with self.assertRaises(RuntimeError):
            guard._read_reply(io.BytesIO(b"-ERR boom\r\n"))


class ExhaustedPolicyTest(unittest.TestCase):
    def setUp(self):
        self.calls = []

    def fake_kube(self, present: bool):
        def kube(method, url, body=None):
            self.calls.append((method, url, body))
            if method == "GET":
                return 200 if present else 404
            return 201 if method == "POST" else 200
        return kube

    def test_applies_the_429_policy_when_the_cap_is_reached(self):
        with mock.patch.object(guard, "kube", self.fake_kube(present=False)):
            guard.set_exhausted(True)

        method, _, body = self.calls[-1]
        self.assertEqual(method, "POST")
        response = body["spec"]["traffic"]["directResponse"]["conditional"][0]["policy"]
        self.assertEqual(response["status"], 429)
        self.assertEqual(json.loads(response["body"])["error"], "ai_budget_exhausted")

    def test_removes_the_policy_once_below_the_cap(self):
        with mock.patch.object(guard, "kube", self.fake_kube(present=True)):
            guard.set_exhausted(False)

        self.assertEqual(self.calls[-1][0], "DELETE")

    def test_leaves_things_alone_when_state_already_matches(self):
        with mock.patch.object(guard, "kube", self.fake_kube(present=True)):
            guard.set_exhausted(True)

        self.assertEqual([c[0] for c in self.calls], ["GET"])

    def test_message_names_the_cap_in_french(self):
        message = json.loads(guard.EXHAUSTED_BODY)["message"]

        self.assertEqual(message, "Budget IA de la plateforme atteint (5 $). Contactez un admin plateforme.")


if __name__ == "__main__":
    unittest.main()
