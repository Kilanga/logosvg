"""Le seul client Ollama : ce qu'il envoie, et qu'il ne cache pas les pannes."""
import asyncio
import dataclasses

import pytest

import app.ollama as ollama


class Recorder:
    def __init__(self, answer="  bonjour  ", status=200):
        self.sent = None
        self.answer = answer
        self.status = status

    def client(self, timeout):
        recorder = self

        class Client:
            async def __aenter__(self):
                return self

            async def __aexit__(self, *args):
                return False

            async def post(self, url, json):
                recorder.sent = (url, json, timeout)
                return Response(recorder)

        return Client()


class Response:
    def __init__(self, recorder):
        self.recorder = recorder

    def raise_for_status(self):
        if self.recorder.status >= 400:
            raise RuntimeError("ollama en panne")

    def json(self):
        return {"message": {"content": self.recorder.answer}}


@pytest.fixture
def recorder(monkeypatch):
    rec = Recorder()
    monkeypatch.setattr(ollama.httpx, "AsyncClient", rec.client)
    monkeypatch.setattr(ollama, "settings", dataclasses.replace(ollama.settings, ollama_url="http://ollama.test/"))
    return rec


def test_unload_by_default_and_json_on_demand(recorder):
    assert asyncio.run(ollama.chat("système", "question")) == "bonjour"
    url, payload, timeout = recorder.sent
    assert url == "http://ollama.test/api/chat"
    assert payload["keep_alive"] == 0 and "format" not in payload
    assert timeout == ollama.TIMEOUT_SECONDS

    asyncio.run(ollama.chat("système", "question", json=True, keep_alive=ollama.KEEP_WARM))
    assert recorder.sent[1]["format"] == "json"
    assert recorder.sent[1]["keep_alive"] == "20s"


def test_a_failure_is_raised_for_the_caller_to_decide(recorder):
    recorder.status = 500
    with pytest.raises(RuntimeError):
        asyncio.run(ollama.chat("système", "question"))
