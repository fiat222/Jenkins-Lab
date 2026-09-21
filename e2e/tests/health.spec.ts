import { expect, test } from '@playwright/test';

test('API liveness endpoint reports a running instance', async ({ request }) => {
  const response = await request.get('/health/live');

  expect(response.status()).toBe(200);
  expect(await response.json()).toMatchObject({ status: 'live' });
});

test('API readiness endpoint confirms Postgres and Redis are available', async ({ request }) => {
  const response = await request.get('/health/ready');

  expect(response.status()).toBe(200);
  expect(await response.json()).toEqual({ status: 'ready' });
});

test('nginx proxies the aggregate health status from the API', async ({ request }) => {
  const response = await request.get('/health');

  expect(response.status()).toBe(200);
  expect(await response.json()).toMatchObject({
    status: 'ok',
    postgres: 'up',
    redis: 'up',
  });
});
