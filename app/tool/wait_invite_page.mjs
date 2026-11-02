const deadline = Date.now() + 90000;
const list = await fetch('http://127.0.0.1:9222/json').then((response) => response.json());
const page = list.find((item) => item.type === 'page' && item.webSocketDebuggerUrl);
if (!page) {
  console.error('no chrome page', JSON.stringify(list));
  process.exit(1);
}
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
while (Date.now() < deadline) {
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
console.error('timed out');
process.exit(1);
