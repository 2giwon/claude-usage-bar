import type { EngineInterface, Register } from "claude-code";

import { labelOf, overWarn } from "./format";
import type { RateLimit, UsageState } from "./format";
import {
  buildSnapshot,
  homeFromPath,
  sessionName,
  SNAPSHOT_FILE,
} from "./snapshot";
import type { SnapshotContext } from "./snapshot";

// 이 mod는 사용량을 ~/.claude/claude-usage-bar.json 에 써서 맥 메뉴 막대 앱 Claude Usage Bar(menubar/)가 보여 주게 한다.
// 사용량이 80%를 처음 넘으면 Claude Code 안에 알림도 띄운다.

// mod를 다시 불러오면 이 값들은 처음으로 돌아가고, session.start 가 다시 돌면서 채운다
let state: UsageState = { status: "loading" };
// 이미 알림을 띄운 창. 80% 아래로 내려가면 지워서 다시 넘을 때 또 알린다
let warned = new Set<string>();
// 이 세션에서 사용량 값을 한 번이라도 받았는지. 받은 뒤에 값이 비면 창이 초기화된 것이다
let hasSeenLimits = false;
// 마지막으로 받은 컨텍스트 사용량. 메뉴 막대 앱의 "지금 세션 컨텍스트" 카드에 쓴다
let context: SnapshotContext | undefined;
// 임시 파일 이름이 세션끼리, 같은 세션의 연달은 쓰기끼리 겹치지 않게 붙이는 값
const writerId = Math.random().toString(36).slice(2, 10);
let writeCount = 0;

// 메뉴 막대 앱이 읽는 파일(~/.claude/claude-usage-bar.json)을 쓴다.
// 실제 사용량을 받았을 때만 쓴다. 로딩이나 실패 때 쓰면 다른 세션이 써 둔 정상 값을 지우기 때문이다.
// 여러 세션이 동시에 써도 내용이 섞이지 않게, 임시 파일에 쓴 뒤 mv 로 한 번에 바꿔치기한다.
// 쓰기에 실패하면 메뉴 막대 앱이 오래된 값으로 표시한다
async function publish($: EngineInterface): Promise<void> {
  if (state.status !== "ready") {
    return;
  }
  try {
    const home = (await $.env.get("HOME")) ?? homeFromPath($.plugin.root);
    if (home === undefined) {
      return;
    }
    const root = await $.session.root();
    const snapshot = buildSnapshot(
      state,
      context,
      sessionName(root),
      new Date()
    );
    const target = `${home}/${SNAPSHOT_FILE}`;
    writeCount += 1;
    const temp = `${target}.${writerId}-${writeCount}.tmp`;
    await $.fs.write(temp, `${JSON.stringify(snapshot, null, 2)}\n`);
    await $.process.run(["/bin/mv", "-f", temp, target]);
  } catch {
    // 메뉴 막대 앱은 오래된 값으로 표시한다
  }
}

function apply(
  $: EngineInterface,
  limits: RateLimit[],
  isQuiet: boolean
): void {
  state = { status: "ready", limits };
  hasSeenLimits = hasSeenLimits || limits.length > 0;
  const over = overWarn(limits);

  // 두 창이 한꺼번에 80%를 넘으면 알림 하나로 묶는다. 따로 띄우면 뒤 알림이 앞 알림을 덮는다
  const fresh = over.filter((kind) => !warned.has(kind));
  if (!isQuiet && fresh.length > 0) {
    const parts = fresh.map((kind) => {
      const limit = limits.find((item) => item.kind === kind);
      return `${labelOf(kind)} ${Math.round(limit?.percentUsed ?? 0)}%`;
    });
    $.ui.toast(`⚠️ Claude 사용량 ${parts.join(", ")}`);
  }
  warned = new Set(over);
}

export const register: Register = (on) => {
  state = { status: "loading" };
  warned = new Set<string>();
  hasSeenLimits = false;
  context = undefined;

  // 세션을 열 때(그리고 mod를 다시 불러올 때) 지금 값을 한 번 읽는다.
  // 이미 80%를 넘은 상태로 열면 알림 창은 띄우지 않는다.
  // 여기서는 파일을 쓰지 않는다. 예전에 받아 둔 값일 수 있어서, 쓰면 오래된 값이 "방금 갱신"처럼 보이고
  // 다른 세션이 써 둔 더 새 값을 덮는다. 파일은 새 측정(session.measure)이 올 때만 쓴다
  on("session.start", async ($, e, next) => {
    const result = await next(e);

    // 예전 버전(0.1.0 첫 버전)이 입력창 아래에 걸어 둔 사용량 문구를 지운다.
    // 상태 표시줄은 다음 호출이 바꿀 때까지 남아 있어서, 지우지 않으면 reload 뒤에도 보인다
    $.ui.status(undefined);

    try {
      const usage = await $.session.usage();
      context = usage.context;
      if (usage.rateLimits.length > 0) {
        apply($, usage.rateLimits, true);
      }
    } catch {
      // 다음 session.measure 때 다시 받는다
    }

    return result;
  });

  // 응답이 끝날 때마다, 사용량이 1%p 움직일 때마다 엔진이 알려 준다.
  // 실제 사용량이 왔을 때만 파일을 쓴다.
  // 값을 받은 뒤에 목록이 비면 창이 초기화된 것이라 다음 응답을 기다린다.
  // 사용량 없이 온 측정은 파일에 쓰지 않는다. 응답이 실패하거나 취소돼도 빈 측정이 올 수 있어서,
  // "구독 요금제가 아님"으로 보고 쓰면 다른 세션이 써 둔 정상 값을 지운다
  on("session.measure", async ($, e, next) => {
    try {
      context = e.context;
      if (e.rateLimits.length > 0) {
        apply($, e.rateLimits, false);
        // 컨텍스트만 바뀐 측정에도 이 세션이 예전에 받은 사용량이 실려 온다.
        // 그걸 쓰면 다른 세션이 써 둔 더 새 값을 "방금 갱신"으로 덮으니, 사용량이 바뀌었을 때만 쓴다
        if (e.changed.includes("rateLimits")) {
          await publish($);
        }
      } else if (hasSeenLimits && e.changed.includes("rateLimits")) {
        state = { status: "loading" };
        warned = new Set<string>();
      }
    } catch {
      // 다음 측정 때 다시 받는다
    }

    return next(e);
  });
};
