// 사용량 값의 모양과, 경고 알림에 쓰는 이름표와 기준

export type RateLimit = {
  kind: string;
  percentUsed: number;
  resetsAt?: string;
};

// loading: 아직 사용량을 받지 못함 (세션을 막 열었거나, 창이 초기화돼 값이 비었음)
// ready: 사용량을 받음 (빈 배열이면 구독 요금제가 아님)
// error: 사용량을 읽다가 실패함
export type UsageState =
  | { status: "loading" }
  | { status: "error" }
  | { status: "ready"; limits: RateLimit[] };

export const WARN_PERCENT = 80;

// 알림에 쓰는 창 이름. spend_limit 같은 다른 창은 알리지 않는다
const LABELS: Record<string, string> = {
  five_hour: "5시간",
  seven_day: "주간",
};
const LABELS_EN: Record<string, string> = {
  five_hour: "5-hour",
  seven_day: "weekly",
};

// 경고 기준(80%) 이상인 창의 kind 목록. 알림을 처음 넘을 때 한 번만 띄우는 데 쓴다
export function overWarn(limits: RateLimit[]): string[] {
  return limits
    .filter(
      (limit) => limit.kind in LABELS && limit.percentUsed >= WARN_PERCENT
    )
    .map((limit) => limit.kind);
}

export function labelOf(kind: string): string {
  return LABELS[kind] ?? kind;
}

export type Lang = "ko" | "en";

// LANG 환경 변수(예: ko_KR.UTF-8)로 알림 언어를 고른다. 한국어가 아니면 영어
export function langFromLocale(locale: string | undefined): Lang {
  return /^ko($|[_.-])/i.test(locale ?? "") ? "ko" : "en";
}

// 80%를 처음 넘은 창들을 알림 한 줄로 만든다. 예: "⚠️ Claude 사용량 5시간 85%"
export function warnToast(
  items: { kind: string; percent: number }[],
  lang: Lang
): string {
  const parts = items.map(({ kind, percent }) => {
    const label = lang === "ko" ? labelOf(kind) : (LABELS_EN[kind] ?? kind);
    return `${label} ${Math.round(percent)}%`;
  });
  return lang === "ko"
    ? `⚠️ Claude 사용량 ${parts.join(", ")}`
    : `⚠️ Claude usage: ${parts.join(", ")}`;
}
