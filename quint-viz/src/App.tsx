import { useCallback, useMemo, useState } from "react";
import {
  classifyVars,
  stripPrefix,
  buildSeries,
  buildVariantSeries,
  findVariantChanges,
  findVariantVar,
  type ItfTrace,
  type Threshold,
} from "./itf";
import DropZone from "./DropZone";
import Controls from "./Controls";
import Chart from "./Chart";
import "./App.css";

export default function App() {
  const [trace, setTrace] = useState<ItfTrace | null>(null);
  const [fileName, setFileName] = useState("");
  const [selectedVars, setSelectedVars] = useState<Set<string>>(new Set());
  const [thresholds, setThresholds] = useState<Threshold[]>([]);
  const [markedVariant, setMarkedVariant] = useState<string | null>(null);
  const [title, setTitle] = useState("");

  const { numericVars, variantVars } = useMemo(() => {
    if (!trace) return { numericVars: [] as string[], variantVars: [] as string[] };
    const { numeric, variant } = classifyVars(trace.states[0], trace.vars);
    return {
      numericVars: numeric.map(stripPrefix),
      variantVars: variant.map(stripPrefix),
    };
  }, [trace]);

  const handleLoad = useCallback(
    (t: ItfTrace, name: string) => {
      setTrace(t);
      setFileName(name);
      setTitle(name);
      setThresholds([]);
      setMarkedVariant(null);
      const { numeric } = classifyVars(t.states[0], t.vars);
      setSelectedVars(new Set(numeric.map(stripPrefix)));
    },
    [],
  );

  const handleToggleVar = useCallback((name: string) => {
    setSelectedVars((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  }, []);

  const handleReset = useCallback(() => {
    setTrace(null);
    setFileName("");
    setTitle("");
    setThresholds([]);
    setMarkedVariant(null);
    setSelectedVars(new Set());
  }, []);

  const series = useMemo(() => {
    if (!trace) return {};
    const { numeric } = classifyVars(trace.states[0], trace.vars);
    return buildSeries(trace.states, numeric);
  }, [trace]);

  const steps = useMemo(() => {
    if (!trace) return [];
    return Array.from({ length: trace.states.length }, (_, i) => i);
  }, [trace]);

  const { variantChanges, markLabel } = useMemo(() => {
    if (!trace || !markedVariant)
      return { variantChanges: [], markLabel: "" };
    const fullVar = findVariantVar(trace.vars, markedVariant);
    if (!fullVar) return { variantChanges: [], markLabel: "" };
    const tags = buildVariantSeries(trace.states, fullVar);
    return {
      variantChanges: findVariantChanges(tags),
      markLabel: markedVariant,
    };
  }, [trace, markedVariant]);

  if (!trace) {
    return <DropZone onLoad={handleLoad} />;
  }

  return (
    <div className="app">
      <Controls
        numericVars={numericVars}
        variantVars={variantVars}
        selectedVars={selectedVars}
        onToggleVar={handleToggleVar}
        markedVariant={markedVariant}
        onMarkedVariantChange={setMarkedVariant}
        thresholds={thresholds}
        onAddThreshold={(t) => setThresholds((prev) => [...prev, t])}
        onRemoveThreshold={(i) =>
          setThresholds((prev) => prev.filter((_, idx) => idx !== i))
        }
        title={title}
        onTitleChange={setTitle}
        fileName={fileName}
        onReset={handleReset}
      />
      <Chart
        series={series}
        selectedVars={selectedVars}
        steps={steps}
        thresholds={thresholds}
        variantChanges={variantChanges}
        markLabel={markLabel}
        title={title}
      />
    </div>
  );
}
