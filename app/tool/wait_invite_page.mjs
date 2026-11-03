const debugUrl = 'http://127.0.0.1:9222/json';
const connectBudgetMs = 60_000;
const retryMs = 500;

function describeFetchError(error) {
  if (error && typeof error === 'object') {
    const cause = 'cause' in error ? error.cause : undefined;
    const code =
      cause && typeof cause === 'object' && 'code' in cause ? String(cause.code) : '';
    const message = 'message' in error ? String(error.message) : String(error);
    return code ? `${code}: ${message}` : message;
  }
  return String(error);
}

async function waitForChromePage() {
  const deadline = Date.now() + connectBudgetMs;
  let lastError = 'Chrome DevTools did not respond';
  while (Date.now() < deadline) {
    try {
      const response = await fetch(debugUrl);
      if (!response.ok) {
        lastError = `HTTP ${response.status}`;
      } else {
        const list = await response.json();
        const page = list.find((item) => item.type === 'page' && item.webSocketDebuggerUrl);
        if (page) return page;
        lastError = 'DevTools is up but no page target is ready yet';
      }
    } catch (error) {
      lastError = describeFetchError(error);
    }
    await new Promise((resolve) => setTimeout(resolve, retryMs));
  }
  console.error(
    `timed out after 60s waiting for Chrome DevTools at ${debugUrl}: ${lastError}`,
  );
  process.exit(1);
}

const page = await waitForChromePage();
const resultDeadline = Date.now() + 90_000;
const socket = new WebSocket(page.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
socket.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    pending.get(message.id)(message);
    pending.delete(message.id);
  }
});
await new Promise((resolve) => socket.addEventListener('open', resolve));
function call(method, params) {
  const messageId = ++id;
  return new Promise((resolve) => {
    pending.set(messageId, resolve);
    socket.send(JSON.stringify({ id: messageId, method, params }));
  });
}
await call('Runtime.enable', {});
while (Date.now() < resultDeadline) {
  const result = await call('Runtime.evaluate', {
    expression: 'document.title + "\\n" + document.body.innerText',
    returnByValue: true,
  });
  const text = result.result?.result?.value ?? '';
  const title = text.split('\n')[0];
  console.log(title);
  if (title === 'ALL PASS') {
    process.exit(0);
  }
  if (title === 'FAIL') {
    console.log(text);
    process.exit(1);
  }
  await new Promise((resolve) => setTimeout(resolve, 1000));
}
console.error('timed out after 90s waiting for the invite emulator page result');
process.exit(1);
