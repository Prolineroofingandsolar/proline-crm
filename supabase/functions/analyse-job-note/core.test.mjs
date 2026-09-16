import assert from "node:assert/strict";
import test from "node:test";
import { fallbackAnalysis, parseAnalysisText } from "./core.mjs";

test("keeps the spoken update available when AI analysis fails", () => {
  assert.deepEqual(fallbackAnalysis("  Front slope felted and battened.  "), {
    summary: "Front slope felted and battened.",
    suggestions: [],
    materials: [],
    analysis_mode: "note_only",
  });
});

test("uses valid structured analysis", () => {
  const value = parseAnalysisText('{"summary":"Done","suggestions":[]}', "original");
  assert.equal(value.summary, "Done");
  assert.deepEqual(value.suggestions, []);
});

test("falls back safely for empty or malformed model output", () => {
  assert.equal(parseAnalysisText("not json", "Keep this note").summary, "Keep this note");
  assert.equal(parseAnalysisText("", "Keep this note").analysis_mode, "note_only");
});
