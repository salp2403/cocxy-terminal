import test from "node:test";
import assert from "node:assert/strict";

function greeting(name) {
  return `Hello, ${name}!`;
}

test("greeting mentions the name", () => {
  assert.equal(greeting("Cocxy"), "Hello, Cocxy!");
});
