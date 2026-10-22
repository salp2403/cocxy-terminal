// Copyright (c) 2026 Said Arturo Lopez. MIT License.

// Product captures are optional files dropped into public/images and
// public/videos. Each slot renders its capture when the file exists and the
// interim artwork otherwise, so real captures ship without template edits.
// URLs carry a content hash because /images and /videos are served immutable.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const publicRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'public');

export const captureSlots = {
  hero: { frame: 'window', width: 2880, height: 1800, avifBudgetKB: 80, compact: true },
  agents: { frame: 'window', width: 2400, height: 1500, avifBudgetKB: 80 },
  review: { frame: 'window', width: 2400, height: 1500, avifBudgetKB: 80 },
  projects: { frame: 'window', width: 2400, height: 1500, avifBudgetKB: 80 },
  mobile: { frame: 'phone', width: 1179, height: 2556, avifBudgetKB: 80 },
};

export const compactCapture = { width: 800, avifBudgetKB: 14 };

export const tourVideo = { width: 1920, height: 1080, webmBudgetMB: 4, mp4BudgetMB: 8, posterBudgetKB: 120 };

function publicFile(relative) {
  const file = path.join(publicRoot, relative);
  return fs.existsSync(file) ? file : null;
}

function hashedURL(relative) {
  const file = publicFile(relative);
  const digest = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0, 12);
  return `/${relative}?h=${digest}`;
}

function pngSize(file) {
  const header = fs.readFileSync(file).subarray(0, 24);
  if (header.toString('ascii', 12, 16) !== 'IHDR') throw new Error(`${file} is not a PNG`);
  return { width: header.readUInt32BE(16), height: header.readUInt32BE(20) };
}

export function captureAvailable(slot) {
  return Boolean(publicFile(`images/shot-${slot}.png`));
}

export function captureSources(slot) {
  const png = `images/shot-${slot}.png`;
  if (!publicFile(png)) return null;
  const sources = [];
  for (const [suffix, media] of [['-compact', '(max-width: 699px)'], ['', '']]) {
    for (const [extension, type] of [['avif', 'image/avif'], ['webp', 'image/webp']]) {
      const relative = `images/shot-${slot}${suffix}.${extension}`;
      if (!publicFile(relative)) continue;
      const mediaAttribute = media ? ` media="${media}"` : '';
      sources.push(`<source${mediaAttribute} srcset="${hashedURL(relative)}" type="${type}">`);
    }
  }
  return { sources, src: hashedURL(png), ...pngSize(publicFile(png)) };
}

// artwork is inner markup shown, labelled with artworkLabel, until the capture exists.
export function productShot({ slot, alt, artwork, artworkLabel = alt, priority = false, className = '' }) {
  const { frame } = captureSlots[slot] ?? { frame: 'window' };
  const frameClass = frame === 'phone' ? 'phone' : 'window';
  const extra = className ? ` ${className}` : '';
  const capture = captureSources(slot);
  if (!capture) {
    const mockClass = frame === 'phone' ? '' : ' mock';
    return `<div class="${frameClass}${mockClass}${extra}" role="img" aria-label="${artworkLabel}">${artwork}</div>`;
  }
  const loading = priority ? 'fetchpriority="high"' : 'loading="lazy"';
  return `<div class="${frameClass}${extra}">
      <picture>
        ${capture.sources.join('\n        ')}
        <img src="${capture.src}" width="${capture.width}" height="${capture.height}" alt="${alt}" ${loading} decoding="async">
      </picture>
    </div>`;
}

export function tourVideoAvailable() {
  return Boolean(publicFile('videos/cocxy-tour.webm') && publicFile('videos/cocxy-tour.mp4') && publicFile('images/shot-tour-poster.jpg'));
}

export function tourVideoPlayer(label) {
  if (!tourVideoAvailable()) return '';
  return `<div class="window demo__window">
      <video controls muted playsinline preload="none" poster="${hashedURL('images/shot-tour-poster.jpg')}" width="${tourVideo.width}" height="${tourVideo.height}" aria-label="${label}">
        <source src="${hashedURL('videos/cocxy-tour.webm')}" type="video/webm">
        <source src="${hashedURL('videos/cocxy-tour.mp4')}" type="video/mp4">
      </video>
    </div>`;
}

export function tourVideoURLs() {
  if (!tourVideoAvailable()) return null;
  return { mp4: hashedURL('videos/cocxy-tour.mp4'), poster: hashedURL('images/shot-tour-poster.jpg') };
}
