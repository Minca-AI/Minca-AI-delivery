'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { greeting } = require('../greeting');

test('greeting', () => {
  assert.strictEqual(greeting('minca'), 'hello, minca');
});
