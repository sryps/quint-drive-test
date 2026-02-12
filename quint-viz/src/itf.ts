/** ITF (Intermediate Trace Format) types and parsing utilities. */

export interface ItfMeta {
  format: string;
  status?: string;
  description?: string;
  [key: string]: unknown;
}

export interface ItfState {
  "#meta": { index: number };
  [varName: string]: unknown;
}

export interface ItfTrace {
  "#meta": ItfMeta;
  vars: string[];
  states: ItfState[];
}

export interface Threshold {
  label: string;
  value: number;
}

export interface VariantChange {
  step: number;
  fromTag: string;
  toTag: string;
}

/** Strip module prefixes: 'a::b::varName' -> 'varName'. */
export function stripPrefix(name: string): string {
  const parts = name.split("::");
  return parts[parts.length - 1];
}

/** Extract a numeric value from an ITF cell, or return null. */
export function extractNumeric(value: unknown): number | null {
  if (typeof value === "number") return value;
  if (
    typeof value === "object" &&
    value !== null &&
    "#bigint" in value &&
    typeof (value as Record<string, unknown>)["#bigint"] === "string"
  ) {
    return Number((value as Record<string, string>)["#bigint"]);
  }
  return null;
}

/** Extract variant tag from an ITF cell, or return null. */
export function extractVariantTag(value: unknown): string | null {
  if (
    typeof value === "object" &&
    value !== null &&
    "tag" in value &&
    typeof (value as Record<string, unknown>)["tag"] === "string"
  ) {
    return (value as Record<string, string>)["tag"];
  }
  return null;
}

/** Classify variables as numeric or variant based on the first state. */
export function classifyVars(
  state: ItfState,
  varNames: string[],
): { numeric: string[]; variant: string[] } {
  const numeric: string[] = [];
  const variant: string[] = [];
  for (const v of varNames) {
    const val = state[v];
    if (extractNumeric(val) !== null) {
      numeric.push(v);
    } else if (extractVariantTag(val) !== null) {
      variant.push(v);
    }
  }
  return { numeric, variant };
}

/** Extract time series dict {shortName: values[]} from states. */
export function buildSeries(
  states: ItfState[],
  varNames: string[],
): Record<string, number[]> {
  const series: Record<string, number[]> = {};
  for (const v of varNames) {
    series[stripPrefix(v)] = [];
  }
  for (const state of states) {
    for (const v of varNames) {
      series[stripPrefix(v)].push(extractNumeric(state[v]) ?? 0);
    }
  }
  return series;
}

/** Extract variant tag series for a single variable. */
export function buildVariantSeries(
  states: ItfState[],
  varName: string,
): (string | null)[] {
  return states.map((s) => extractVariantTag(s[varName]));
}

/** Find variant change points. */
export function findVariantChanges(tags: (string | null)[]): VariantChange[] {
  const changes: VariantChange[] = [];
  for (let i = 1; i < tags.length; i++) {
    if (tags[i] !== tags[i - 1]) {
      changes.push({
        step: i,
        fromTag: tags[i - 1] ?? "?",
        toTag: tags[i] ?? "?",
      });
    }
  }
  return changes;
}

/** Find the full qualified var name matching a short name. */
export function findVariantVar(
  varNames: string[],
  shortName: string,
): string | undefined {
  return varNames.find((v) => stripPrefix(v) === shortName);
}
