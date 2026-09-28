package main

import "testing"

func TestGreeting(t *testing.T) {
	if got := Greeting("minca"); got != "hello, minca" {
		t.Fatalf("Greeting() = %q", got)
	}
}
