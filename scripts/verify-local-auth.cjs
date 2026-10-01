/** Host logic checks. Run with DevEco's node.exe; native HarmonyOS APIs still need device testing.
 * Preferences is replaced with a temporary file store; CryptoFramework uses Node PBKDF2.
 * No application accounts are read or modified.
 */
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { promisify } = require('node:util');
const ts = require(path.join(process.env.DEVECO_SDK_HOME || 'D:/harmony/DevEco Studio/sdk',
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const root = path.resolve(__dirname, '..');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tanji-auth-test-'));
const file = path.join(dir, 'accounts.json');
let data = {};
let failFlush = false;
const store = {
  async has(key) { return Object.hasOwn(data, key); },
  async get(key, fallback) { return data[key] ?? fallback; },
  async put(key, value) { data[key] = value; },
  async delete(key) { delete data[key]; },
  async flush() {
    if (failFlush) throw new Error('Simulated disk failure');
    fs.writeFileSync(file, JSON.stringify(data));
  }
};
const mockCrypto = {
  createRandom: () => ({ generateRandom: async (length) => ({ data: crypto.randomBytes(length) }) }),
  createKdf: (algorithm) => {
    assert.equal(algorithm, 'PBKDF2|SHA256');
    return { generateSecret: async (spec) => ({ data: await promisify(crypto.pbkdf2)(
      spec.password, spec.salt, spec.iterations, spec.keySize, 'sha256') }) };
  }
};
function load(relative, dependencies) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const result = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  });
  const module = { exports: {} };
  new Function('require', 'module', 'exports', result.outputText)((name) => {
    if (!Object.hasOwn(dependencies, name)) throw new Error(`Unexpected dependency: ${name}`);
    return dependencies[name];
  }, module, module.exports);
  return module.exports;
}
const authModule = load('entry/src/main/ets/services/AuthService.ets', {
  '@kit.AbilityKit': {}, '@kit.ArkData': { preferences: { getPreferences: async () => store } },
  '@kit.CryptoArchitectureKit': { cryptoFramework: mockCrypto }
});
const { AuthService } = authModule;
const { PreviewAuthService } = load('entry/src/main/ets/services/PreviewAuthService.ets', {
  '@kit.AbilityKit': {}, './AuthService': authModule
});
let count = 0;
async function check(name, body) { await body(); count++; console.log(`PASS ${name}`); }
(async () => {
  const service = new AuthService();
  const context = {};
  const password = 'TestPass123';
  await check('empty login rejected', async () => assert.equal((await service.login('', '')).success, false));
  await check('demo login retained', async () => assert.equal((await service.login(' admin ', '123456')).success, true));
  await check('invalid account rejected', async () => assert.equal((await service.register('a!', password, context)).success, false));
  await check('weak password rejected', async () => assert.equal((await service.register('tester', '12345678', context)).success, false));
  await check('demo name reserved', async () => assert.equal((await service.register('admin', password, context)).success, false));
  await check('registration succeeds', async () => assert.equal((await service.register(' tester ', password, context)).success, true));
  await check('duplicate rejected', async () => assert.equal((await service.register('tester', password, context)).success, false));
  await check('wrong password rejected', async () => assert.equal((await service.login('tester', 'Other123', context)).success, false));
  await check('unknown account rejected', async () => assert.equal((await service.login('unknown', password, context)).success, false));
  await check('password is not stored as plaintext', async () => {
    const saved = JSON.parse(data.user_tester);
    assert.equal(saved.passwordHash.length, 64);
    assert.equal(saved.salt.length, 16);
    assert.equal(fs.readFileSync(file, 'utf8').includes(password), false);
  });
  await check('login works after reloading store', async () => {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
    const result = await new AuthService().login('tester', password, context);
    assert.equal(result.success, true); assert.equal(result.user.userId, 'local-tester');
  });
  await check('same password receives independent salt', async () => {
    await service.register('second', password, context);
    assert.notEqual(JSON.parse(data.user_tester).passwordHash, JSON.parse(data.user_second).passwordHash);
  });
  await check('flush failure rolls back registration', async () => {
    failFlush = true;
    await assert.rejects(service.register('failed', password, context));
    assert.equal(await store.has('user_failed'), false);
    failFlush = false;
  });
  await check('preview registration and login are isolated', async () => {
    const preview = new PreviewAuthService();
    assert.equal((await preview.register('previewuser', password)).success, true);
    assert.equal((await preview.login('previewuser', password)).success, true);
    assert.equal((await preview.register('previewuser', password)).success, false);
    assert.equal(await store.has('user_previewuser'), false);
    assert.equal((await new PreviewAuthService().login('previewuser', password)).success, false);
  });
  console.log(`${count} checks passed (platform APIs mocked; device verification required).`);
})().catch((error) => { console.error(error); process.exitCode = 1; })
  .finally(() => fs.rmSync(dir, { recursive: true, force: true }));
