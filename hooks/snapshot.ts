// 메뉴 막대 앱이 읽을 사용량 파일(~/.claude/claude-usage-bar.json)의 내용을 만든다.
// 엔진 API를 쓰지 않는 순수 함수라 단위 테스트로 검증한다.

import type { RateLimit, UsageState } from "./format";

export const SNAPSHOT_VERSION = 1;
export const SNAPSHOT_FILE = ".claude/claude-usage-bar.json";

export type SnapshotContext = {
  percent?: number;
  tokens?: number;
  window: number;
};

export type Snapshot = {
  version: number;
  updatedAt: string;
  status: UsageState["status"];
  limits: RateLimit[];
  context: SnapshotContext | null;
  session: string | null;
};

export function buildSnapshot(
  state: UsageState,
  context: SnapshotContext | undefined,
  session: string | undefined,
  now: Date
): Snapshot {
  return {
    version: SNAPSHOT_VERSION,
    updatedAt: now.toISOString(),
    status: state.status,
    limits:
      state.status === "ready"
        ? state.limits.map((limit) => ({ ...limit }))
        : [],
    context:
      context === undefined
        ? null
        : {
            ...(context.percent !== undefined && { percent: context.percent }),
            ...(context.tokens !== undefined && { tokens: context.tokens }),
            window: context.window,
          },
    session: session ?? null,
  };
}

// 맥의 홈 폴더(/Users/이름)를 mod 폴더 경로에서 찾는다. HOME 환경 변수를 못 읽을 때만 쓰는 예비 방법이다
export function homeFromPath(path: string): string | undefined {
  return /^\/Users\/[^/]+/.exec(path)?.[0];
}

// 세션 폴더 경로에서 마지막 폴더 이름만 꺼낸다
export function sessionName(root: string): string | undefined {
  const parts = root.split("/").filter((part) => part !== "");
  return parts[parts.length - 1];
}
