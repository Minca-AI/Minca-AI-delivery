#!/usr/bin/env node
'use strict';
// Node fixture consumer of Minca-AI-delivery. `--help` is what the default
// image:smoke target calls, so it must exit 0.
const { greeting } = require('./greeting');

const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('usage: example-service [--name NAME]');
  process.exit(0);
}
const i = args.indexOf('--name');
console.log(greeting(i >= 0 ? args[i + 1] : 'world'));
