import { useState, type KeyboardEvent } from "react";
import type { Threshold } from "./itf";

interface ControlsProps {
  numericVars: string[];
  variantVars: string[];
  selectedVars: Set<string>;
  onToggleVar: (name: string) => void;
  markedVariant: string | null;
  onMarkedVariantChange: (name: string | null) => void;
  thresholds: Threshold[];
  onAddThreshold: (t: Threshold) => void;
  onRemoveThreshold: (index: number) => void;
  title: string;
  onTitleChange: (title: string) => void;
  fileName: string;
  onReset: () => void;
}

export default function Controls({
  numericVars,
  variantVars,
  selectedVars,
  onToggleVar,
  markedVariant,
  onMarkedVariantChange,
  thresholds,
  onAddThreshold,
  onRemoveThreshold,
  title,
  onTitleChange,
  fileName,
  onReset,
}: ControlsProps) {
  const [thresholdInput, setThresholdInput] = useState("");

  const handleAddThreshold = () => {
    const match = thresholdInput.match(/^(.+)=(.+)$/);
    if (match) {
      const value = Number(match[2].trim());
      if (!isNaN(value)) {
        onAddThreshold({ label: match[1].trim(), value });
        setThresholdInput("");
      }
    }
  };

  const handleThresholdKey = (e: KeyboardEvent) => {
    if (e.key === "Enter") handleAddThreshold();
  };

  return (
    <aside className="controls">
      <div className="controls-header">
        <h2>Controls</h2>
        <button className="btn-reset" onClick={onReset} title="Load a different file">
          New file
        </button>
      </div>

      <div className="controls-file">{fileName}</div>

      <section>
        <label className="controls-label">Chart title</label>
        <input
          type="text"
          className="controls-input"
          value={title}
          onChange={(e) => onTitleChange(e.target.value)}
        />
      </section>

      <section>
        <label className="controls-label">Numeric variables</label>
        <div className="controls-checkboxes">
          {numericVars.map((v) => (
            <label key={v} className="controls-checkbox">
              <input
                type="checkbox"
                checked={selectedVars.has(v)}
                onChange={() => onToggleVar(v)}
              />
              {v}
            </label>
          ))}
        </div>
      </section>

      <section>
        <label className="controls-label">Variant markers</label>
        <select
          className="controls-input"
          value={markedVariant ?? ""}
          onChange={(e) =>
            onMarkedVariantChange(e.target.value || null)
          }
        >
          <option value="">None</option>
          {variantVars.map((v) => (
            <option key={v} value={v}>
              {v}
            </option>
          ))}
        </select>
      </section>

      <section>
        <label className="controls-label">Thresholds</label>
        <div className="controls-threshold-input">
          <input
            type="text"
            className="controls-input"
            placeholder="Label=value"
            value={thresholdInput}
            onChange={(e) => setThresholdInput(e.target.value)}
            onKeyDown={handleThresholdKey}
          />
          <button className="btn-add" onClick={handleAddThreshold}>
            Add
          </button>
        </div>
        <div className="controls-chips">
          {thresholds.map((t, i) => (
            <span key={i} className="chip">
              {t.label}={t.value}
              <button className="chip-remove" onClick={() => onRemoveThreshold(i)}>
                &times;
              </button>
            </span>
          ))}
        </div>
      </section>
    </aside>
  );
}
