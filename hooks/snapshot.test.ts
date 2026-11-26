import { expect, test } from "claude-code/testing";

import { buildSnapshot, homeFromPath, sessionName } from "./snapshot";

const NOW = new Date("2026-11-26T00:14:00.000Z");

test("1. 사용량을 받으면 5시간, 주간, 초기화 시각, 컨텍스트, 갱신 시각을 담은 내용을 만든다", () => {
  const snapshot = buildSnapshot(
    {
      status: "ready",
      limits: [
        {
          kind: "five_hour",
          percentUsed: 8,
          resetsAt: "2026-11-26T04:20:00.000Z",
        },
        {
          kind: "seven_day",
          percentUsed: 41,
          resetsAt: "2026-11-29T06:00:00.000Z",
        },
      ],
    },
    { percent: 20, tokens: 198228, window: 1000000 },
    "claude-usage-bar",
    NOW
  );

  expect(snapshot).toEqual({
    version: 1,
    updatedAt: "2026-11-26T00:14:00.000Z",
    status: "ready",
    limits: [
      {
        kind: "five_hour",
        percentUsed: 8,
        resetsAt: "2026-11-26T04:20:00.000Z",
      },
      {
        kind: "seven_day",
        percentUsed: 41,
        resetsAt: "2026-11-29T06:00:00.000Z",
      },
    ],
    context: { percent: 20, tokens: 198228, window: 1000000 },
    session: "claude-usage-bar",
  });
});

test("1-1. 로딩과 실패 상태도 사용량 없이 상태만 담는다", () => {
  expect(buildSnapshot({ status: "error" }, undefined, undefined, NOW)).toEqual(
    {
      version: 1,
      updatedAt: "2026-11-26T00:14:00.000Z",
      status: "error",
      limits: [],
      context: null,
      session: null,
    }
  );
});

test("2. mod 폴더 경로에서 홈 폴더를 찾는다", () => {
  expect(homeFromPath("/Users/alice/Documents/claude-usage-bar")).toBe(
    "/Users/alice"
  );
  expect(
    homeFromPath(
      "/Users/someone/.claude/plugins/cache/usage-bar-for-claude/0.1.0"
    )
  ).toBe("/Users/someone");
  expect(homeFromPath("/opt/plugins/usage-bar-for-claude")).toBeUndefined();
});

test("2-1. 세션 폴더 경로에서 마지막 폴더 이름을 꺼낸다", () => {
  expect(sessionName("/Users/alice/Documents/claude-usage-bar")).toBe(
    "claude-usage-bar"
  );
  expect(sessionName("/Users/alice/project/")).toBe("project");
  expect(sessionName("/")).toBeUndefined();
});
