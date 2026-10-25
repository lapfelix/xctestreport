// Written by --gcs-signed-in-viewing. Lets a report open through Google Cloud Storage's
// signed-in link (storage.cloud.google.com), which redirects every object to
//   https://<id>-apidata.googleusercontent.com/download/storage/v1/b/<bucket>/o/<encoded name>
// with the whole object name in one percent-encoded segment. A relative URL such as
// "web/report.css" or "../index.html" then resolves to the wrong place. This worker is
// scoped to .../o/, sees every request a report page makes, works out the path the
// page meant from the URL that requested it, and fetches that object by its full name.
'use strict';

const BASE = new URL(self.registration.scope).pathname; // "/download/storage/v1/b/<bucket>/o/"

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

// The object name a URL on this host points at, or null when it is not a full name.
function objectName(urlString) {
    if (!urlString) return null;
    const url = new URL(urlString);
    if (url.origin !== self.location.origin || !url.pathname.startsWith(BASE)) return null;
    const rest = url.pathname.slice(BASE.length);
    // A full name always has a folder, so it carries an encoded slash; a broken relative
    // URL never does, because report file names are encoded and contain no slash.
    if (!/%2f/i.test(rest)) return null;
    return decodeURIComponent(rest);
}

// The relative URL the browser resolved against `.../o/<name>` to produce `pathname`.
function relativeToBase(pathname) {
    const base = BASE.split('/').filter(Boolean);
    const parts = pathname.split('/').filter(Boolean);
    let shared = 0;
    while (shared < base.length && shared < parts.length && base[shared] === parts[shared]) shared++;
    return '../'.repeat(base.length - shared) + parts.slice(shared).join('/');
}

self.addEventListener('fetch', (event) => {
    const request = event.request;
    const url = new URL(request.url);
    if (url.origin !== self.location.origin || objectName(request.url) !== null) return;
    // The referrer is the page, or the stylesheet for a url() inside CSS, that the
    // relative URL was written in.
    const from = objectName(request.referrer);
    if (from === null) return;

    const meant = new URL(relativeToBase(url.pathname), 'https://report.invalid/' + encodeURI(from));
    const name = decodeURIComponent(meant.pathname.slice(1));
    const target = self.location.origin + BASE + encodeURIComponent(name) + url.search;

    if (request.mode === 'navigate') {
        // A redirect keeps the address bar on the real URL, so the next page's links work too.
        event.respondWith(Response.redirect(target, 302));
        return;
    }
    event.respondWith(fetch(target, {
        method: request.method,
        headers: request.headers,
        credentials: 'include',
    }));
});
