from example_service.cli import greeting, main


def test_greeting() -> None:
    assert greeting("minca") == "hello, minca"


def test_main_returns_zero() -> None:
    assert main(["--name", "minca"]) == 0
