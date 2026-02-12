import Plot from "react-plotly.js";
import type { Threshold, VariantChange } from "./itf";

interface ChartProps {
  series: Record<string, number[]>;
  selectedVars: Set<string>;
  steps: number[];
  thresholds: Threshold[];
  variantChanges: VariantChange[];
  markLabel: string;
  title: string;
}

export default function Chart({
  series,
  selectedVars,
  steps,
  thresholds,
  variantChanges,
  markLabel,
  title,
}: ChartProps) {
  const traces: Plotly.Data[] = Object.entries(series)
    .filter(([name]) => selectedVars.has(name))
    .map(([name, values]) => ({
      x: steps,
      y: values,
      mode: "lines+markers" as const,
      name,
      marker: { size: 3 },
      hovertemplate: `${name}<br>Step %{x}<br>Value: %{y}<extra></extra>`,
    }));

  const shapes: Partial<Plotly.Shape>[] = [
    ...thresholds.map(
      (t) =>
        ({
          type: "line" as const,
          x0: 0,
          x1: 1,
          xref: "paper" as const,
          y0: t.value,
          y1: t.value,
          line: { dash: "dash" as const, color: "gray", width: 1 },
        }) satisfies Partial<Plotly.Shape>,
    ),
    ...variantChanges.map(
      (c) =>
        ({
          type: "line" as const,
          x0: c.step,
          x1: c.step,
          y0: 0,
          y1: 1,
          yref: "paper" as const,
          line: { dash: "dash" as const, color: "rgba(100,100,100,0.5)", width: 1 },
        }) satisfies Partial<Plotly.Shape>,
    ),
  ];

  const annotations: Partial<Plotly.Annotations>[] = [
    ...thresholds.map(
      (t) =>
        ({
          x: 0,
          xref: "paper" as const,
          y: t.value,
          text: t.label,
          showarrow: false,
          xanchor: "left" as const,
          yanchor: "bottom" as const,
          font: { color: "gray", size: 11 },
        }) as Partial<Plotly.Annotations>,
    ),
    ...variantChanges.map(
      (c) =>
        ({
          x: c.step,
          y: 1,
          yref: "paper" as const,
          text: `${markLabel}: ${c.toTag}`,
          showarrow: false,
          textangle: "-90",
          xanchor: "left" as const,
          yanchor: "top" as const,
          font: { color: "rgba(100,100,100,0.7)", size: 10 },
        }) as Partial<Plotly.Annotations>,
    ),
  ];

  const layout: Partial<Plotly.Layout> = {
    title: title ? { text: title } : undefined,
    xaxis: { title: { text: "Step" } },
    yaxis: { title: { text: "Value" } },
    hovermode: "x unified" as const,
    legend: {
      orientation: "h",
      yanchor: "bottom",
      y: 1.02,
      xanchor: "right",
      x: 1,
    },
    template: "plotly_white" as unknown as Plotly.Template,
    shapes,
    annotations,
    autosize: true,
  };

  return (
    <div className="chart-container">
      <Plot
        data={traces}
        layout={layout}
        useResizeHandler
        style={{ width: "100%", height: "100%" }}
      />
    </div>
  );
}
