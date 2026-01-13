import { formatIndex, getChildIndex } from "../../../utils/universalDelegatorIndex";

export function SlotIndexBadge(props: { index: bigint; onCopy: (index: bigint) => void }) {
  return (
    <button
      type="button"
      className="badge badge-sm font-mono text-[10px] shrink-0 whitespace-nowrap cursor-pointer bg-base-100 text-base-content/60 border-base-300/60 transition-colors hover:bg-primary/10 hover:border-primary/30 hover:text-base-content hover:shadow-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      title={formatIndex(props.index)}
      onClick={() => props.onCopy(props.index)}
    >
      {getChildIndex(props.index).toString()}
    </button>
  );
}
