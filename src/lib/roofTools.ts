export function roofPitch(rise: number, run: number): number | null {
  return Number.isFinite(rise) && Number.isFinite(run) && rise > 0 && run > 0 ? Math.atan(rise / run) * 180 / Math.PI : null;
}

export function battenGauge(lengths: number[], setback: number, min: number, max: number) {
  if (!lengths.length || ![...lengths, setback, min, max].every(Number.isFinite) || setback < 0 || min <= 0 || max < min || lengths.some(v => v <= setback)) return null;
  const spans = lengths.map(v => v - setback);
  const courses = Math.ceil(Math.max(...spans) / max);
  if (!Number.isSafeInteger(courses) || courses < 1) return null;
  const gauges = spans.map(v => v / courses);
  const shortest = Math.min(...gauges), longest = Math.max(...gauges);
  return { courses, shortest, longest, outOfRange: shortest < min || longest > max };
}
