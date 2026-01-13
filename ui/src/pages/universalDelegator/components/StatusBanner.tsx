type StatusBannerProps = {
  tone: "info" | "success" | "warning" | "error";
  message: string;
};

export function StatusBanner(props: StatusBannerProps) {
  return (
    <div className={`alert alert-${props.tone} text-xs`}>
      <span>{props.message}</span>
    </div>
  );
}
