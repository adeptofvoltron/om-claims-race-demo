import { test } from 'node:test';
import assert from 'node:assert/strict';
import { slugify } from '../src/slugify.js';

test('lowercases and joins words with dashes', () => {
  assert.equal(slugify('Hello World'), 'hello-world');
});

test('collapses punctuation and trims edge dashes', () => {
  assert.equal(slugify('  -- Release 2.0, final! --  '), 'release-2-0-final');
});

test('drops apostrophes inside words instead of splitting on them', () => {
  assert.equal(slugify("Don't panic"), 'dont-panic');
  assert.equal(slugify('Don’t panic'), 'dont-panic');
});
