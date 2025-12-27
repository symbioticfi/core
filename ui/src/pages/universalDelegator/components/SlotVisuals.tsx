import { forwardRef, type CSSProperties } from "react";

const FILL_OPACITY = 0.2;

function pendingPatternStyle(colorVar: string): CSSProperties {
  const lineColor = `var(${colorVar})`;
  return {
    backgroundImage: `linear-gradient(${lineColor} 0 2px, transparent 2px 10px), linear-gradient(90deg, ${lineColor} 0 2px, transparent 2px 10px)`,
    backgroundSize: "10px 10px",
    backgroundPosition: "-1px -1px",
    backgroundRepeat: "repeat",
    opacity: FILL_OPACITY,
  };
}

function allocatedFillStyle(colorVar: string): CSSProperties {
  return { backgroundColor: `var(${colorVar})`, opacity: FILL_OPACITY };
}

export function SlotFill(props: { allocatedPct: number; pendingPct: number; colorVar: string }) {
  return (
    <>
      <div
        className="pointer-events-none absolute inset-y-0 left-0"
        style={{ width: `${props.allocatedPct}%`, ...allocatedFillStyle(props.colorVar) }}
      />
      {props.pendingPct > 0 ? (
        <div
          className="pointer-events-none absolute inset-y-0"
          style={{
            left: `${props.allocatedPct}%`,
            width: `${props.pendingPct}%`,
            ...pendingPatternStyle(props.colorVar),
          }}
        />
      ) : null}
    </>
  );
}

export function SlotBalances(props: { allocated: string; pending: string }) {
  return (
    <div className="font-mono text-xs opacity-70">
      <div className="truncate">Allocated: {props.allocated}</div>
      <div className="truncate">Pending: {props.pending}</div>
    </div>
  );
}

type AddSlotButtonProps = {
  label: string;
  className: string;
  onClick: () => void;
  dataNoZoom?: boolean;
};

export const AddSlotButton = forwardRef<HTMLButtonElement, AddSlotButtonProps>((props, ref) => {
  return (
    <button
      ref={ref}
      type="button"
      className={props.className}
      onClick={props.onClick}
      data-no-zoom={props.dataNoZoom || undefined}
    >
      <div className="text-center">
        <div className="text-2xl leading-none">+</div>
        <div className="mt-1">{props.label}</div>
      </div>
    </button>
  );
});

AddSlotButton.displayName = "AddSlotButton";
