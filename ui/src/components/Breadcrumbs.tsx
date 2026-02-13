import type { SlotNode } from "../lib/ops";
import { formatIndex } from "../lib/format";

type BreadcrumbsProps = {
  path: SlotNode[];
  onSelect: (index: bigint) => void;
};

export function Breadcrumbs({ path, onSelect }: BreadcrumbsProps) {
  if (path.length === 0) {
    return null;
  }

  return (
    <div className="flex flex-wrap items-center gap-2 text-sm">
      {path.map((node, idx) => {
        const isCurrent = idx === path.length - 1;
        const targetIndex = isCurrent && idx > 0 ? path[idx - 1].index : node.index;
        return (
          <button
            key={node.index.toString()}
            type="button"
            className={`button-base px-3 py-1 text-xs ${isCurrent ? "button-ink" : "button-outline"}`}
            onClick={() => onSelect(targetIndex)}
          >
            {idx === 0 ? "Root" : formatIndex(node.index)}
          </button>
        );
      })}
    </div>
  );
}
