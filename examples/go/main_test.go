package main

import "testing"

func TestGreeting(t *testing.T) {
	if got := Greeting("minca"); got != "hello, minca" {
		t.Fatalf("Greeting() = %q", got)
	}
}

func TestDefaultNameWithoutLinkFlags(t *testing.T) {
	if got := Greeting(defaultName); got != "hello, world" {
		t.Fatalf("Greeting(defaultName) = %q; only the image build may override defaultName", got)
	}
}
