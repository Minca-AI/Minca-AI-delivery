"""Entry point. `--help` is what the default image:smoke target calls."""

import argparse


def greeting(name: str) -> str:
    """Return the greeting the service would serve."""
    return f"hello, {name}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="example-service")
    parser.add_argument("--name", default="world")
    args = parser.parse_args(argv)
    print(greeting(args.name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
