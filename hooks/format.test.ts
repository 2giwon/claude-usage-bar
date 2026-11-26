import { expect, test } from "claude-code/testing";

import { langFromLocale, warnToast } from "./format";

test("5. LANG 이 한국어면 한국어, 아니면 영어로 고른다", () => {
  expect(langFromLocale("ko_KR.UTF-8")).toBe("ko");
  expect(langFromLocale("ko")).toBe("ko");
  expect(langFromLocale("en_US.UTF-8")).toBe("en");
  expect(langFromLocale("ja_JP.UTF-8")).toBe("en");
  expect(langFromLocale(undefined)).toBe("en");
  expect(langFromLocale("")).toBe("en");
});

test("5-1. 80% 알림 문구를 언어에 맞게 만든다", () => {
  const items = [
    { kind: "five_hour", percent: 85 },
    { kind: "seven_day", percent: 81 },
  ];

  expect(warnToast(items, "ko")).toBe("⚠️ Claude 사용량 5시간 85%, 주간 81%");
  expect(warnToast(items, "en")).toBe("⚠️ Claude usage: 5-hour 85%, weekly 81%");
});
