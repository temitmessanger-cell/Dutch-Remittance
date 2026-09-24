const express = require('express');
const path = require('path');
const router = express.Router();

const SOCIAL = {
  youtube:   'https://www.youtube.com/@Dutch.Inc.Platforms',
  instagram: 'https://www.instagram.com/dutchincplatforms',
  tiktok:    'https://www.tiktok.com/@dutch.inc.platforms',
};

// robots.txt
router.get('/robots.txt', (req, res) => {
  res.type('text/plain');
  res.send(
    `User-agent: *\nAllow: /\n\nSitemap: https://dutchremit.com/sitemap.xml\n\n` +
    `# Dutch Remit social media\n` +
    `# YouTube:   ${SOCIAL.youtube}\n` +
    `# Instagram: ${SOCIAL.instagram}\n` +
    `# TikTok:    ${SOCIAL.tiktok}\n`
  );
});

// sitemap.xml
router.get('/sitemap.xml', (req, res) => {
  res.type('application/xml');
  res.send(`<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://dutchremit.com/</loc><priority>1.0</priority><changefreq>weekly</changefreq></url>
  <url><loc>${SOCIAL.youtube}</loc><priority>0.8</priority><changefreq>daily</changefreq></url>
  <url><loc>${SOCIAL.instagram}</loc><priority>0.8</priority><changefreq>daily</changefreq></url>
  <url><loc>${SOCIAL.tiktok}</loc><priority>0.8</priority><changefreq>daily</changefreq></url>
</urlset>`);
});

// JSON-LD structured data — for any web landing page to embed
router.get('/structured-data.json', (req, res) => {
  res.json({
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: 'Dutch Remit',
    url: 'https://dutchremit.com',
    description: 'Send money to 32 countries. Instant transfers across Africa, Europe and the US.',
    sameAs: [
      SOCIAL.youtube,
      SOCIAL.instagram,
      SOCIAL.tiktok,
    ],
    contactPoint: {
      '@type': 'ContactPoint',
      contactType: 'customer support',
      availableLanguage: 'English',
    },
  });
});

module.exports = router;
