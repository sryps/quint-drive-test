import { useCallback, useState, type DragEvent, type ChangeEvent } from "react";
import type { ItfTrace } from "./itf";

interface DropZoneProps {
  onLoad: (trace: ItfTrace, fileName: string) => void;
}

export default function DropZone({ onLoad }: DropZoneProps) {
  const [dragging, setDragging] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const parseFile = useCallback(
    (file: File) => {
      setError(null);
      const reader = new FileReader();
      reader.onload = () => {
        try {
          const trace = JSON.parse(reader.result as string) as ItfTrace;
          if (!trace.vars || !trace.states) {
            setError("Invalid ITF file: missing 'vars' or 'states' field.");
            return;
          }
          if (trace.states.length === 0) {
            setError("Trace has no states.");
            return;
          }
          onLoad(trace, file.name);
        } catch {
          setError("Failed to parse JSON file.");
        }
      };
      reader.readAsText(file);
    },
    [onLoad],
  );

  const handleDrop = useCallback(
    (e: DragEvent) => {
      e.preventDefault();
      setDragging(false);
      const file = e.dataTransfer.files[0];
      if (file) parseFile(file);
    },
    [parseFile],
  );

  const handleChange = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) parseFile(file);
    },
    [parseFile],
  );

  return (
    <div
      className={`dropzone ${dragging ? "dropzone-active" : ""}`}
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={handleDrop}
    >
      <div className="dropzone-content">
        <p className="dropzone-icon">&#128202;</p>
        <p className="dropzone-title">Quint Trace Visualizer</p>
        <p>Drag &amp; drop an ITF JSON trace file here</p>
        <p className="dropzone-or">or</p>
        <label className="dropzone-browse">
          Browse files
          <input
            type="file"
            accept=".json,.itf.json"
            onChange={handleChange}
            hidden
          />
        </label>
        {error && <p className="dropzone-error">{error}</p>}
      </div>
    </div>
  );
}
