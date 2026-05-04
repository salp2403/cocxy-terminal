package main

import "testing"

func TestGreeting(t *testing.T) {
	if got := greeting("Cocxy"); got != "Hello, Cocxy!" {
		t.Fatalf("unexpected greeting: %s", got)
	}
}
