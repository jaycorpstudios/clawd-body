import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '../../main/fonts');
const conv = createRequire(import.meta.url).resolve('lv_font_conv/lv_font_conv.js');

const TEXT = '0x20-0x7E,0xA0-0xFF,0x2013,0x2014,0x2018,0x2019,0x201C,0x201D,0x2026,0x203A,0x2212';
const SYMBOLS = '0x2713,0x2715,0x25A0,0x25B6';
const DIGITS = '0x20,0x25,0x2D,0x30-0x3A';

const FONTS = [
  ['mono_15', 'JetBrainsMono-Regular', 15, TEXT],
  ['mono_16', 'JetBrainsMono-Regular', 16, TEXT],
  ['mono_17', 'JetBrainsMono-Regular', 17, TEXT],
  ['mono_18', 'JetBrainsMono-Regular', 18, TEXT],
  ['mono_semi_17', 'JetBrainsMono-SemiBold', 17, `${TEXT},${SYMBOLS}`],
  ['mono_semi_18', 'JetBrainsMono-SemiBold', 18, TEXT],
  ['mono_semi_20', 'JetBrainsMono-SemiBold', 20, TEXT],
  ['mono_bold_15', 'JetBrainsMono-Bold', 15, TEXT],
  ['mono_bold_18', 'JetBrainsMono-Bold', 18, TEXT],
  ['mono_bold_23', 'JetBrainsMono-Bold', 23, TEXT],
  ['pixel_26', 'PixelifySans-Bold', 26, TEXT],
  ['pixel_28', 'PixelifySans-Bold', 28, TEXT],
  ['pixel_32', 'PixelifySans-Bold', 32, TEXT],
  ['pixel_35', 'PixelifySans-Bold', 35, TEXT],
  ['pixel_58', 'PixelifySans-Bold', 58, DIGITS],
  ['pixel_92', 'PixelifySans-Medium', 92, DIGITS],
];

mkdirSync(out, { recursive: true });
for (const [name, file, size, range] of FONTS) {
  const fallback = name === 'mono_semi_17' ? ['--lv-fallback', 'lv_font_montserrat_16'] : [];
  const args = [conv, ...fallback, '--font', `ttf/${file}.ttf`, '--range', range, '--size', String(size),
    '--bpp', '4', '--format', 'lvgl', '--no-compress', '--lv-include', 'lvgl.h', '--lv-font-name', `font_${name}`,
    '-o', `../../main/fonts/font_${name}.c`];
  execFileSync(process.execPath, args, { cwd: here, stdio: 'inherit' });
}

const header = ['#pragma once', '', '#include "lvgl.h"', '',
  ...FONTS.map(([name]) => `LV_FONT_DECLARE(font_${name});`), ''].join('\n');
writeFileSync(join(out, 'fonts.h'), header);
