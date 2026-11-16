// Hugging Face daily papers → Atom feed.
//
// https://huggingface.co/api/daily_papers is JSON only, and there is no public
// RSS/Atom endpoint for it (https://huggingface.co/papers/rss answers 401, and
// the community mirrors are stale by days). RSSPub speaks RSS/Atom, so this
// worker flattens the JSON into Atom, filtered to recent papers and sorted by
// upvotes — i.e. "the popular papers of the day", not the whole firehose.
//
// Deploy:
//   npx wrangler deploy workers/hf-papers.js --name hf-papers --compatibility-date 2025-09-01
//
// Query params:
//   limit        how many papers to emit (1-30, default 8)
//   days         only papers submitted to the daily list within N days (1-30, default 2)
//   min_upvotes  drop papers below this upvote count (default 0)
//
// Note: the upstream API rejects limit > 100 ("Too big: expected number to be <=100").

const HF = 'https://huggingface.co/api/daily_papers?limit=100';

function esc(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const limit = Math.max(1, Math.min(Number(url.searchParams.get('limit') || 8), 30));
    const days = Math.max(1, Math.min(Number(url.searchParams.get('days') || 2), 30));
    const minUp = Number(url.searchParams.get('min_upvotes') || 0);
    const cutoff = Date.now() - days * 86400000;

    const upstream = await fetch(HF, { cf: { cacheTtl: 900, cacheEverything: true } });
    if (!upstream.ok) {
      const detail = (await upstream.text()).slice(0, 200);
      return new Response(`upstream ${upstream.status}: ${detail}`, { status: 502 });
    }
    const data = await upstream.json();

    const papers = data
      .filter((d) => d && d.paper && d.paper.id && d.paper.title)
      .map((d) => {
        const p = d.paper;
        const date = p.submittedOnDailyAt || p.publishedAt || new Date().toISOString();
        return {
          id: String(p.id),
          title: p.title,
          summary: p.summary || p.ai_summary || '',
          up: Number(p.upvotes || 0),
          authors: (p.authors || []).map((a) => a.name).filter(Boolean),
          org: (p.organization && p.organization.fullname) || '',
          date,
          ts: new Date(date).getTime(),
        };
      })
      .filter((p) => p.up >= minUp && p.ts >= cutoff)
      .sort((a, b) => b.up - a.up || b.ts - a.ts)
      .slice(0, limit);

    const entries = papers
      .map((p) => {
        const blurb =
          `<p>${p.up} upvotes · ${p.authors.slice(0, 3).join(', ')}` +
          `${p.org ? ' · ' + p.org : ''}</p><p>${p.summary}</p>`;
        return `  <entry>
    <title>${esc(p.title)}</title>
    <id>urn:hf-papers:${esc(p.id)}</id>
    <updated>${new Date(p.date).toISOString()}</updated>
    <link rel="alternate" href="https://huggingface.co/papers/${esc(p.id)}"/>
    <author><name>${esc(p.authors[0] || 'Hugging Face')}</name></author>
    <content type="html">${esc(blurb)}</content>
  </entry>`;
      })
      .join('\n');

    const xml = `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Hugging Face daily papers (popular)</title>
  <id>urn:hf-papers:feed</id>
  <updated>${new Date().toISOString()}</updated>
  <link rel="alternate" href="https://huggingface.co/papers"/>
  <link rel="self" href="${esc(url.origin + url.pathname + url.search)}"/>
  <author><name>Hugging Face</name></author>
  <subtitle>Hugging Face daily papers from the last ${days} day(s), most upvoted first (top ${limit})</subtitle>
${entries}
</feed>`;

    return new Response(xml, {
      headers: {
        'content-type': 'application/atom+xml; charset=utf-8',
        'cache-control': 'public, max-age=1800',
      },
    });
  },
};
