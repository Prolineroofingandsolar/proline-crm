export function fallbackAnalysis(note) {
  const summary = String(note ?? "").trim().slice(0, 5000);
  return {
    summary,
    suggestions: [],
    materials: [],
    analysis_mode: "note_only",
  };
}

export function parseAnalysisText(text, note) {
  if (typeof text !== "string" || !text.trim()) return fallbackAnalysis(note);
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return fallbackAnalysis(note);
    return parsed;
  } catch {
    return fallbackAnalysis(note);
  }
}
