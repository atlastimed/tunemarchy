import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
const model = vm.createContext({});
vm.runInContext(readFileSync(new URL('../Model.js', import.meta.url), 'utf8').replace(/^\.pragma library\n/, ''), model);

test('companion snapshot rejects invalid protocols and bounds collections', () => {
  for (const line of ['null', '[]', 'broken', '{"v":2}', ' '.repeat(65537)]) assert.equal(model.parseSnapshot(line), null);
  const data = model.parseSnapshot(JSON.stringify({v:1, title:'x'.repeat(1000), volume:12,
    length:100, position:500, queue:Array(100).fill({title:'song'}), devices:[null, {id:'d',name:'Desk'}], accessToken:'secret'}));
  assert.equal(data.title.length, 512);
  assert.equal(data.volume, 1);
  assert.equal(data.position, 100);
  assert.equal(data.queue.length, 10);
  assert.equal(data.devices.length, 1);
  assert.equal(data.accessToken, undefined);
});
test('network artwork and shared tooltip sinks reject unwanted resources', () => {
  for (const url of ['file:///etc/passwd','https://example.com/a','https://i.scdn.co.attacker.test/a','http://i.scdn.co/a']) assert.equal(model.safeArt(url),'');
  assert.equal(model.safeArt('https://i.scdn.co/image/abc'), 'https://i.scdn.co/image/abc');
  assert.equal(model.tooltipText('<img src="https://example.com"> & title'), '<span>&lt;img src="https://example.com"&gt; &amp; title</span>');
});
test('settings and controls handle malformed values and limits', () => {
  assert.equal(model.flag('false',true),false);
  assert.equal(model.normalizeEnum('unknown',['off'],'off'),'off');
  assert.equal(model.clampInt('oops',0,800,240),240);
  assert.equal(model.clampVolume(Infinity),0);
  assert.equal(model.seekTarget(50,100,90),89);
  assert.equal(model.seekTarget(5,-10,90),0);
  assert.equal(model.formatTime(61),'1:01');
  assert.equal(model.barLabel('Title','Artist',false),'Title');
});
test('bar label gives way to the room the bar has left', () => {
  assert.equal(model.labelWidth(300, 240, Infinity, 48), 240);
  assert.equal(model.labelWidth(120, 240, undefined, 48), 120);
  assert.equal(model.labelWidth(300, 240, 150, 48), 150);
  assert.equal(model.labelWidth(100, 240, 150, 48), 100);
  assert.equal(model.labelWidth(300, 240, 47, 48), 0);
  assert.equal(model.labelWidth(300, 240, -20, 48), 0);
  assert.equal(model.labelWidth(300, 0, 500, 48), 0);
});
test('a label with no room for the artist keeps the whole title instead', () => {
  const both = {text: 'Title  ·  Artist', width: 200};
  const title = {text: 'Title', width: 90};
  // Results come from another context, so they are compared by value.
  const fit = (...args) => JSON.stringify(model.fitLabel(...args));
  assert.equal(fit(both, title, 240, Infinity, 48), '{"text":"Title  ·  Artist","width":200}');
  assert.equal(fit(both, title, 240, 150, 48), '{"text":"Title","width":90}');
  assert.equal(fit(both, title, 240, 70, 48), '{"text":"Title","width":70}');
  assert.equal(fit(both, title, 240, 20, 48), '{"text":"","width":0}');
  assert.equal(fit(both, both, 0, Infinity, 48), '{"text":"","width":0}');
});
